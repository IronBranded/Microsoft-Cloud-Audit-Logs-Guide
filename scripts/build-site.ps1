#Requires -Version 7.4
<#
.SYNOPSIS
    Builds the data layer of the interactive GitHub Pages site from the catalog.

.DESCRIPTION
    The site (site/index.html, site/js/app.js, site/css/site.css) is static and hand-written.
    This script generates the parts that come from data, so the site cannot drift from the catalog:

      site/data/catalog-data.js   window.GUIDE_DATA = { meta, catalog, products, sources, relationships, presentation }
      site/data/*.json            copies of the data files, offered as downloads
      site/css/planes.css         one class per evidence plane, colors from data/presentation.json
      site/microsoft-cloud-audit-logs-guide-offline.html
                                  the whole site as one self-contained HTML file (styles, scripts, and data
                                  inlined) for offline use, for example on an isolated analysis workstation

    The data files are embedded as their original JSON text (no PowerShell round trip), so values
    such as dates reach the browser unchanged. The output is deterministic: running the script twice
    on the same data produces identical files, which lets CI check that the committed site is current.

    Before writing, the script checks the rules the site depends on and fails on any error:
      - every reference URL is an https://learn.microsoft.com/ page
      - every evidence plane in the catalog has a presentation entry with a valid color
      - every site command maps to one of the six acquisition paths (same rule as Poster 2)
      - every destination pattern compiles, its entry_ids exist, and it matches at least one entry
      - every relationship endpoint exists, and every product has a summary
      - site/index.html, site/js, and site/css contain no external URLs (the site makes no network requests)

.EXAMPLE
    pwsh ./scripts/build-site.ps1
    pwsh ./scripts/build-site.ps1 -Bundle ./dist/microsoft-cloud-audit-logs-guide.html   # write the offline file elsewhere
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Bundle = (Join-Path (Split-Path -Parent $PSScriptRoot) 'site/microsoft-cloud-audit-logs-guide-offline.html')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$siteRoot = Join-Path $RepoRoot 'site'
$dataRoot = Join-Path $RepoRoot 'data'
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

$names = @('evidence-catalog', 'products', 'sources', 'relationships', 'presentation')
$raw = @{}
$data = @{}
foreach ($n in $names) {
    $path = Join-Path $dataRoot "$n.json"
    $raw[$n] = (Get-Content -LiteralPath $path -Raw).TrimEnd()
    $data[$n] = $raw[$n] | ConvertFrom-Json -Depth 64
}
$catalog = $data['evidence-catalog']
$products = @($data['products'].products)
$sources = @($data['sources'].sources)
$rels = @($data['relationships'].relationships)
$copy = $data['presentation']
$entries = @($catalog.entries | Where-Object { $_.publication.site })

# ------------------------------------------------------------------ checks
foreach ($s in $sources) {
    if ($s.url -notmatch '^https://learn\.microsoft\.com/') { $errors.Add("Source $($s.id) is not a learn.microsoft.com URL: $($s.url)") }
}

$planeByName = @{}
foreach ($pl in $copy.planes) {
    $planeByName[$pl.name] = $pl
    if ($pl.color -notmatch '^#[0-9A-Fa-f]{6}$') { $errors.Add("Plane '$($pl.name)' has an invalid color '$($pl.color)'.") }
}
foreach ($e in $entries) {
    if (-not $planeByName.ContainsKey($e.evidence_plane)) { $errors.Add("Entry $($e.id) uses plane '$($e.evidence_plane)', which presentation.json does not define.") }
}

$pathByCommand = @{}
foreach ($p in $copy.acquisition_paths) { foreach ($c in $p.commands) { $pathByCommand[$c] = [int]$p.number } }
$typePaths = $copy.acquisition_type_paths
foreach ($e in $entries) {
    $cmds = @($e.powershell.commands)
    for ($i = 0; $i -lt $cmds.Count; $i++) {
        $c = $cmds[$i]
        $found = $pathByCommand.ContainsKey($c.command)
        if (-not $found -and $c.role -eq 'Authenticates session') {
            for ($j = $i + 1; $j -lt $cmds.Count; $j++) { if ($pathByCommand.ContainsKey($cmds[$j].command)) { $found = $true; break } }
        }
        if (-not $found -and $typePaths.PSObject.Properties.Name -contains $e.powershell.acquisition_type) { $found = $true }
        if (-not $found) { $errors.Add("Command '$($c.command)' in $($e.id) has no acquisition path.") }
    }
}

if (-not ($copy.PSObject.Properties.Name -contains 'site')) { $errors.Add('presentation.json has no "site" section.') }
else {
    $entryIds = @($catalog.entries.id)
    foreach ($d in $copy.site.destinations) {
        try { $rx = [regex]::new($d.pattern, 'IgnoreCase') } catch { $errors.Add("Destination '$($d.id)' pattern does not compile: $($_.Exception.Message)"); continue }
        foreach ($id in @($d.entry_ids)) { if ($id -and $id -notin $entryIds) { $errors.Add("Destination '$($d.id)' names unknown entry '$id'.") } }
        $hits = @($entries | Where-Object { $e = $_; ($e.id -in @($d.entry_ids)) -or (@($e.preservation_options | Where-Object { $rx.IsMatch($_) }).Count -gt 0) })
        if ($hits.Count -eq 0) { $warnings.Add("Destination '$($d.id)' matches no site entry.") }
    }
}

$allIds = @($catalog.entries.id)
foreach ($r in $rels) {
    foreach ($end in @($r.from, $r.to)) { if ($end -notin $allIds) { $errors.Add("Relationship $($r.id) points to unknown entry '$end'.") } }
}
foreach ($p in $products) {
    if (-not ($p.PSObject.Properties.Name -contains 'summary') -or [string]::IsNullOrWhiteSpace($p.summary)) { $errors.Add("Product $($p.id) has no summary.") }
}

$codeFiles = @(Get-Item -LiteralPath (Join-Path $siteRoot 'index.html')) +
    @(Get-ChildItem -LiteralPath (Join-Path $siteRoot 'js') -Filter '*.js' -File) +
    @(Get-ChildItem -LiteralPath (Join-Path $siteRoot 'css') -Filter '*.css' -File)
foreach ($f in $codeFiles) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    $urls = [regex]::Matches($text, 'https?://[^\s"''<>)]+') | ForEach-Object Value | Where-Object { $_ -ne 'http://www.w3.org/2000/svg' }
    foreach ($u in $urls) { $errors.Add("$($f.Name) contains an external URL ($u). The site must not make network requests.") }
}

foreach ($w in $warnings) { Write-Warning $w }
if ($errors.Count) {
    $errors | ForEach-Object { Write-Host "ERROR  $_" -ForegroundColor Red }
    throw "Site build failed with $($errors.Count) error(s)."
}

# ------------------------------------------------------------------ generate
$utf8 = [System.Text.UTF8Encoding]::new($false)
$lastVerified = ($catalog.entries.verification.last_verified | ForEach-Object { [string]$_ } | Sort-Object -Descending | Select-Object -First 1)

function New-Meta([bool]$isBundle) {
    [ordered]@{
        title          = $copy.site.title
        catalog_phase  = $catalog.catalog_phase
        schema_version = $catalog.schema_version
        last_verified  = $lastVerified
        entry_count    = $entries.Count
        source_count   = $sources.Count
        bundle         = $isBundle
    } | ConvertTo-Json -Compress
}

function New-DataScript([bool]$isBundle) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('/* Generated by scripts/build-site.ps1 from the files in data/. Do not edit by hand. */')
    [void]$sb.AppendLine('window.GUIDE_DATA = {')
    [void]$sb.AppendLine('"meta": ' + (New-Meta $isBundle) + ',')
    [void]$sb.AppendLine('"catalog": ' + $raw['evidence-catalog'] + ',')
    [void]$sb.AppendLine('"products": ' + $raw['products'] + ',')
    [void]$sb.AppendLine('"sources": ' + $raw['sources'] + ',')
    [void]$sb.AppendLine('"relationships": ' + $raw['relationships'] + ',')
    [void]$sb.AppendLine('"presentation": ' + $raw['presentation'])
    [void]$sb.AppendLine('};')
    $sb.ToString()
}

$siteData = Join-Path $siteRoot 'data'
New-Item -ItemType Directory -Force -Path $siteData | Out-Null
[System.IO.File]::WriteAllText((Join-Path $siteData 'catalog-data.js'), (New-DataScript $false), $utf8)
foreach ($n in $names) {
    [System.IO.File]::WriteAllText((Join-Path $siteData "$n.json"), $raw[$n] + "`n", $utf8)
}

$planeCss = [System.Text.StringBuilder]::new()
[void]$planeCss.AppendLine('/* Generated by scripts/build-site.ps1 from data/presentation.json. Do not edit by hand. */')
foreach ($pl in $copy.planes) {
    [void]$planeCss.AppendLine(('.plane-{0} {{ --plane: {1}; }}' -f [int]$pl.number, $pl.color.ToLowerInvariant()))
}
[void]$planeCss.AppendLine('.plane-0 { --plane: #64748b; }')
[System.IO.File]::WriteAllText((Join-Path $siteRoot 'css/planes.css'), $planeCss.ToString(), $utf8)

Write-Host "Site data written: $($entries.Count) entries, $($products.Count) products, $($sources.Count) references, $($rels.Count) relationships."

# ------------------------------------------------------------------ single-file offline copy
if ($Bundle) {
    $html = Get-Content -LiteralPath (Join-Path $siteRoot 'index.html') -Raw
    $css = (Get-Content -LiteralPath (Join-Path $siteRoot 'css/site.css') -Raw) + "`n" + $planeCss.ToString()
    $themeJs = Get-Content -LiteralPath (Join-Path $siteRoot 'js/theme.js') -Raw
    $appJs = Get-Content -LiteralPath (Join-Path $siteRoot 'js/app.js') -Raw
    $dataJs = New-DataScript $true
    $icon = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $siteRoot 'assets/icon.svg')))

    function Protect-Script([string]$s) { $s -replace '</', '<\/' }
    function Protect-Style([string]$s) { $s -replace '</style', '<\/style' }

    $csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"
    $html = $html -replace '<meta http-equiv="Content-Security-Policy" content="[^"]*">', "<meta http-equiv=`"Content-Security-Policy`" content=`"$csp`">"
    $html = $html.Replace('<link rel="icon" href="assets/icon.svg" type="image/svg+xml">', "<link rel=`"icon`" href=`"data:image/svg+xml;base64,$icon`" type=`"image/svg+xml`">")
    $html = $html.Replace('<link rel="stylesheet" href="css/site.css">', "<style>`n$(Protect-Style $css)`n</style>")
    $html = $html.Replace('<link rel="stylesheet" href="css/planes.css">', '')
    $html = $html.Replace('<script src="js/theme.js"></script>', "<script>`n$(Protect-Script $themeJs)`n</script>")
    $html = $html.Replace('<script src="data/catalog-data.js"></script>', "<script>`n$(Protect-Script $dataJs)`n</script>")
    $html = $html.Replace('<script src="js/app.js"></script>', "<script>`n$(Protect-Script $appJs)`n</script>")
    $html = [regex]::Replace($html, '(?s)<noscript>.*?</noscript>', '<noscript><div class="notice"><p>This guide needs JavaScript to filter and display the catalog. The data files are in the data folder of the project repository.</p></div></noscript>')
    if ($html -match '<(link|script)\b[^>]*\b(src|href)="(css|js|data|assets)/') { throw 'Bundle still loads a local file.' }

    $bundleDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($Bundle))
    New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Bundle), $html, $utf8)
    Write-Host "Single-file bundle written: $Bundle ($([math]::Round((Get-Item $Bundle).Length / 1KB)) KB)"
}
