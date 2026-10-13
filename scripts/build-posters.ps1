#Requires -Version 7.4
<#
.SYNOPSIS
    Builds Poster 1 (evidence map) and Poster 2 (PowerShell acquisition) from the catalog.

.DESCRIPTION
    Reads data/evidence-catalog.json, products.json, sources.json, and presentation.json and writes
    one self-contained HTML file per poster. Every product fact on the posters comes from the catalog;
    presentation.json holds only titles, legends, colors, and methodology statements.

    After building, the script checks the output against the catalog:
      - every entry flagged for a poster appears on it exactly once, and no other entry appears
      - every catalog command of a Poster 2 entry appears on Poster 2
      - every link points to a URL registered in sources.json
    With -Pdf it also prints each poster to a single-page PDF with a Chromium-based browser and fails
    if the content overflows onto a second page.

.EXAMPLE
    pwsh ./scripts/build-posters.ps1
    pwsh ./scripts/build-posters.ps1 -Pdf -BrowserPath /usr/bin/google-chrome
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot,
    [switch]$Pdf,
    [string]$BrowserPath,
    [switch]$Png
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $OutputRoot) { $OutputRoot = Join-Path $RepoRoot 'posters' }

function Read-Json([string]$name) {
    Get-Content -LiteralPath (Join-Path $RepoRoot "data/$name") -Raw | ConvertFrom-Json -Depth 64
}

$catalog = Read-Json 'evidence-catalog.json'
$products = Read-Json 'products.json'
$sources = Read-Json 'sources.json'
$copy = Read-Json 'presentation.json'

$sourceById = @{}; foreach ($s in $sources.sources) { $sourceById[$s.id] = $s }
$productById = @{}; foreach ($p in $products.products) { $productById[$p.id] = $p }
$entryById = @{}; foreach ($e in $catalog.entries) { $entryById[$e.id] = $e }
$planeByName = @{}; foreach ($pl in $copy.planes) { $planeByName[$pl.name] = $pl }
$roleTag = @{}; foreach ($r in $copy.command_roles) { $roleTag[$r.role] = $r.tag }
$statusInfo = @{}; foreach ($v in $copy.verification_legend) { $statusInfo[$v.status] = $v }

$lastVerified = ($catalog.entries.verification.last_verified | Sort-Object -Descending | Select-Object -First 1)
$generatedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')

# ------------------------------------------------------------------ helpers
function Esc([object]$text) {
    if ($null -eq $text) { return '' }
    [System.Net.WebUtility]::HtmlEncode([string]$text)
}

function Get-SourceUrl([string]$id) {
    if (-not $sourceById.ContainsKey($id)) { throw "Unknown source id '$id'." }
    $sourceById[$id].url
}

function Link([string]$sourceId, [string]$label) {
    "<a href=`"$(Esc (Get-SourceUrl $sourceId))`">$(Esc $label)</a>"
}

function Get-PlaneStyle([string]$planeName) {
    $pl = $planeByName[$planeName]
    if (-not $pl) { throw "Plane '$planeName' has no presentation entry." }
    "--plane:$($pl.color)"
}

function Get-PlaneBadge([string]$planeName) {
    $pl = $planeByName[$planeName]
    '<span class="plane-no" aria-hidden="true">{0:D2}</span>' -f [int]$pl.number
}

function Get-Chips($flags) {
    ($flags | ForEach-Object {
        $cls = ($_ -replace '\s', '-').ToLowerInvariant()
        "<span class=`"chip chip-$cls`">$(Esc $_)</span>"
    }) -join ' '
}

function Get-StatusBadge($entry) {
    $status = $entry.verification.status
    $info = $statusInfo[$status]
    $cls = switch ($status) {
        'Verified' { 'ok' } 'Conditional' { 'cond' } 'Deprecated or replaced' { 'dep' } default { 'req' }
    }
    $gapCount = @($entry.verification.gaps).Count
    $noun = if ($gapCount -eq 1) { 'gap' } else { 'gaps' }
    $suffix = if ($status -eq 'Conditional') { " &middot; $gapCount open $noun" } else { '' }
    "<span class=`"status status-$cls`"><span aria-hidden=`"true`">$(Esc $info.symbol)</span> $(Esc $status)$suffix</span>"
}

function Get-List($items, [string]$class = '') {
    $items = @($items | Where-Object { $_ })
    if ($items.Count -eq 0) { return '' }
    $cls = if ($class) { " class=`"$class`"" } else { '' }
    "<ul$cls>" + (($items | ForEach-Object { "<li>$(Esc $_)</li>" }) -join '') + '</ul>'
}

function Get-FirstSentence([string]$text) {
    if (-not $text) { return $null }
    $parts = [regex]::Split($text, '(?<=[.!?])\s+(?=[A-Z])')
    $parts[0]
}

# ------------------------------------------------------------------ shared CSS
$css = @'
:root {
  --ink: #0f172a; --ink-2: #334155; --ink-3: #475569; --rule: #cbd5e1; --paper: #ffffff; --wash: #f1f5f9;
  --head: #0b1f33; --accent: #1d4ed8;
  --ok: #166534; --ok-bg: #dcfce7; --cond: #92400e; --cond-bg: #fef3c7; --dep: #991b1b; --dep-bg: #fee2e2;
  --req: #6b21a8; --req-bg: #f3e8ff;
}
@page { size: 48in 36in; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: var(--paper); color: var(--ink); }
body { width: 48in; min-height: 36in; padding: 0.55in 0.6in 0.45in; font-family: "Inter", "Segoe UI", system-ui, sans-serif;
       font-size: 12.5pt; line-height: 1.32; -webkit-print-color-adjust: exact; print-color-adjust: exact; display: flex; flex-direction: column; }
a { color: var(--accent); text-decoration: underline; text-underline-offset: 2px; }
code, .mono { font-family: "Cascadia Mono", "Consolas", "DejaVu Sans Mono", monospace; }
.masthead { display: flex; justify-content: space-between; align-items: flex-end; gap: 1in; padding: 0.45in 0.55in; background: var(--head);
            color: #fff; border-radius: 0.18in; }
.masthead .kicker { margin: 0 0 0.08in; font-size: 15pt; letter-spacing: 0.08em; text-transform: uppercase; color: #bfdbfe; font-weight: 600; }
.masthead h1 { margin: 0; font-size: 66pt; line-height: 1.02; letter-spacing: -0.01em; font-weight: 800; }
.masthead .subtitle { margin: 0.12in 0 0; font-size: 25pt; color: #e2e8f0; font-weight: 500; }
.masthead .meta { max-width: 14in; text-align: right; font-size: 14pt; color: #cbd5e1; }
.masthead .meta .question { font-size: 18pt; color: #fff; font-weight: 600; margin: 0 0 0.12in; }
.layout { display: grid; grid-template-columns: 8.6in 1fr; gap: 0.45in; margin-top: 0.4in; flex: 1; align-items: start; }
.sidebar { display: flex; flex-direction: column; gap: 0.3in; }
.panel { border: 2px solid var(--rule); border-radius: 0.14in; padding: 0.28in 0.3in; background: var(--paper); }
.panel h2 { margin: 0 0 0.12in; font-size: 25pt; line-height: 1.12; }
.panel h3 { margin: 0 0 0.12in; font-size: 16pt; text-transform: uppercase; letter-spacing: 0.06em; color: var(--ink-2); }
.panel p { margin: 0 0 0.1in; }
.panel ol, .panel ul { margin: 0; padding-left: 0.32in; }
.panel li { margin: 0 0 0.06in; }
.panel.alert { border: 4px solid var(--head); background: var(--wash); }
.panel.alert h2 { font-size: 29pt; }
.panel.alert ol { font-size: 15pt; font-weight: 500; }
.legend-row { display: grid; grid-template-columns: 1.9in 1fr; gap: 0.15in; align-items: baseline; margin-bottom: 0.08in; }
.chip { display: inline-block; padding: 0.02in 0.09in; margin: 0 0.04in 0.05in 0; border: 2px solid currentColor; border-radius: 0.06in;
        font-weight: 700; font-size: 10.5pt; letter-spacing: 0.04em; white-space: nowrap; background: #fff; }
.chip-auto { color: #166534; } .chip-config { color: #9a3412; border-style: dashed; } .chip-export { color: #1d4ed8; }
.chip-license { color: #6b21a8; } .chip-deploy { color: #0f766e; } .chip-policy { color: #b45309; border-style: dashed; }
.chip-on-demand { color: #334155; border-style: dotted; } .chip-supporting { color: #475569; border-style: dotted; }
.chip-fmt { color: var(--ink-2); }
.status { display: inline-block; margin-top: 0.06in; padding: 0.02in 0.1in; border-radius: 0.06in; font-size: 10.5pt; font-weight: 700; }
.status-ok { color: var(--ok); background: var(--ok-bg); } .status-cond { color: var(--cond); background: var(--cond-bg); }
.status-dep { color: var(--dep); background: var(--dep-bg); } .status-req { color: var(--req); background: var(--req-bg); }
table { width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; }
th { position: relative; text-align: left; vertical-align: bottom; font-size: 12pt; text-transform: uppercase; letter-spacing: 0.05em;
     color: var(--ink-2); padding: 0 0.12in 0.1in; border-bottom: 3px solid var(--head); }
td { vertical-align: top; padding: 0.12in; border-bottom: 1.5px solid var(--rule); }
td ul { margin: 0; padding-left: 0.2in; } td li { margin: 0 0 0.04in; }
.plane-cell { vertical-align: top; background: color-mix(in srgb, var(--plane) 12%, white); border-left: 0.14in solid var(--plane); border-bottom: 2px solid var(--plane); }
.plane-cell .plane-no { display: block; font-size: 30pt; font-weight: 800; color: var(--plane); line-height: 1; }
.plane-cell .plane-name { display: block; margin-top: 0.06in; font-size: 15pt; font-weight: 700; line-height: 1.15; }
.product { font-size: 14pt; font-weight: 700; }
.etype { display: block; margin-top: 0.04in; font-size: 10.5pt; color: var(--ink-3); text-transform: uppercase; letter-spacing: 0.05em; }
.source { font-size: 14pt; font-weight: 700; line-height: 1.2; }
.small { font-size: 10.5pt; color: var(--ink-2); }
.muted { color: var(--ink-3); }
footer { margin-top: 0.3in; display: flex; justify-content: space-between; gap: 1in; font-size: 11pt; color: var(--ink-2);
         border-top: 2px solid var(--rule); padding-top: 0.14in; }
footer .disclaimer { max-width: 30in; }
'@

$p1css = @'
.evidence col.c-plane { width: 2.9in; } .evidence col.c-product { width: 3.3in; } .evidence col.c-source { width: 4.1in; }
.evidence col.c-avail { width: 3.7in; } .evidence col.c-where { width: 5.1in; } .evidence col.c-pres { width: 5.9in; }
.evidence col.c-rel { width: 7.6in; } .evidence col.c-learn { width: 4.2in; }
.evidence td.learn a { display: block; margin-bottom: 0.08in; font-weight: 600; }
.evidence td.learn .doc { font-weight: 400; font-size: 11pt; }
'@

$p2css = @'
body { font-size: 13.5pt; line-height: 1.26; }
.p2main { margin-top: 0.34in; }
.flow { column-count: 5; column-gap: 0.3in; column-fill: balance; height: 30.4in; }
.flow > .panel { break-inside: avoid; margin: 0 0 0.2in; }
.flow .panel h3 { font-size: 15.1pt; }
.flow .legend-row { grid-template-columns: 1.7in 1fr; font-size: 12.4pt; }
.flow .panel p.small { margin: 0.08in 0 0; }
.masthead { padding: 0.32in 0.5in; }
.masthead h1 { font-size: 60.5pt; }
.masthead .subtitle { font-size: 23.8pt; margin-top: 0.06in; }
.masthead .kicker { font-size: 14.0pt; }
.masthead .sheet { margin: 0 0 0.06in; display: inline-block; padding: 0.05in 0.16in; border: 2px solid #bfdbfe; border-radius: 0.08in;
                   font-size: 19.4pt; font-weight: 700; color: #fff; }
.masthead .sheet-paths { margin: 0 0 0.12in; font-size: 14.0pt; color: #e2e8f0; }
.masthead .meta { max-width: 17in; }
.path-head { break-inside: avoid; break-after: avoid; margin: 0 0 0.18in; padding: 0.14in 0.18in; background: var(--head); color: #fff; border-radius: 0.1in; }
.path-head .path-title { display: flex; align-items: baseline; gap: 0.16in; }
.path-head .no { font-size: 32.4pt; font-weight: 800; color: #bfdbfe; }
.path-head h2 { margin: 0; font-size: 21.6pt; line-height: 1.12; }
.path-head p { margin: 0.06in 0 0; color: #e2e8f0; font-size: 13.0pt; }
.shared { margin-top: 0.12in; padding: 0.1in 0.14in; background: #fff; color: var(--ink); border-radius: 0.07in; font-size: 12.4pt; }
.shared .label { font-size: 10.8pt; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--ink-3); }
.shared .sublabel { margin-top: 0.06in; font-weight: 700; font-size: 11.9pt; }
.shared ul { margin: 0; padding-left: 0.2in; } .shared li { margin-bottom: 0.03in; }
.card { break-inside: avoid; margin: 0 0 0.18in; border: 1.5px solid var(--rule); border-left: 0.13in solid var(--plane); border-radius: 0.1in;
        padding: 0.12in 0.16in 0.13in; background: #fff; }
.card .meta { margin-top: 0.05in; font-size: 12.4pt; }
.card .meta .k { font-size: 10.6pt; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--ink-3); margin-right: 0.05in; }
.card .meta .mono { font-size: 11.9pt; }
.card .meta.out { margin-top: 0.09in; border-top: 1px solid var(--rule); padding-top: 0.05in; }
.card-kicker .status { margin: 0 0 0 0.06in; text-transform: none; letter-spacing: 0; vertical-align: 1px; }
.card-kicker { font-size: 11.3pt; font-weight: 600; color: var(--ink-3); text-transform: uppercase; letter-spacing: 0.04em; }
.card-kicker .plane-no { color: var(--plane); font-weight: 800; }
.card .source { margin: 0.03in 0 0; font-size: 16.2pt; line-height: 1.18; }
.card .field { margin-top: 0.07in; }
.card .label { font-size: 10.6pt; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--ink-3); margin-bottom: 0.03in;
               border-top: 1px solid var(--rule); padding-top: 0.05in; }
.card ul { margin: 0; padding-left: 0.2in; } .card li { margin-bottom: 0.03in; }
.card .see { margin: 0.08in 0 0; }
.cmd { margin: 0 0 0.09in; }
.cmd:last-child { margin-bottom: 0; }
.cmd .name { font-weight: 700; font-size: 14.0pt; }
.cmd code { display: block; margin: 0.04in 0; padding: 0.05in 0.08in; background: var(--wash); border-radius: 0.05in; font-size: 11.4pt;
            line-height: 1.24; white-space: pre-wrap; word-break: break-word; }
.tag { display: inline-block; margin-right: 0.06in; padding: 0 0.06in; border: 1.5px solid var(--ink-2); border-radius: 0.05in;
       font-size: 10.4pt; font-weight: 700; letter-spacing: 0.05em; color: var(--ink-2); vertical-align: 1px; }
.tag-changes-config { color: #9a3412; border-color: #9a3412; border-style: dashed; }
.api { display: inline-block; margin-left: 0.05in; font-size: 10.8pt; font-weight: 700; color: var(--ink-3); }
.api-beta, .api-preview { color: #9a3412; } .api-retiring, .api-retired { color: var(--dep); }
.cmd .paging, .cmd .note { font-size: 11.9pt; color: var(--ink-2); } .cmd .note { color: var(--ink-3); }
.unverified { color: var(--req); font-weight: 700; }
.chip { font-size: 11.3pt; }
.status { font-size: 11.3pt; margin-top: 0.04in; }
.small { font-size: 11.7pt; }
.panel { padding: 0.24in 0.26in; }
.panel.warning { border: 4px solid var(--dep); background: var(--dep-bg); }
.panel.warning h2 { font-size: 28.1pt; color: #7f1d1d; }
.panel.note-panel { border-style: dashed; font-size: 12.4pt; }
.panel.note-panel p { margin: 0; }
'@

function Get-Head([string]$title, [string]$extraCss) {
    @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(Esc $title)</title>
<style>
$css
$extraCss
</style>
</head>
"@
}

function Get-Masthead($posterCopy, $entries, [string]$sheetLabel) {
    $entries = @($entries)
    $productCount = @($entries.product_id | Sort-Object -Unique).Count
    $sheet = ''
    if ($sheetLabel) {
        $parts = $sheetLabel -split ': ', 2
        $sheet = "<p class=`"sheet`">$($parts[0])</p>"
        if ($parts.Count -gt 1) { $sheet += "<p class=`"sheet-paths`">$($parts[1])</p>" }
    }
    @"
<header class="masthead">
  <div class="titles">
    <p class="kicker">Independent investigator reference &middot; Microsoft Cloud Audit Logs Guide</p>
    <h1>$(Esc $posterCopy.title)</h1>
    <p class="subtitle">$(Esc $posterCopy.subtitle)</p>
  </div>
  <div class="meta">
    $sheet
    <p class="question">$(Esc $posterCopy.question)</p>
    <p>$($entries.Count) evidence sources &middot; $productCount Microsoft products &middot; $(@($sources.sources).Count) official Microsoft references<br>
    Checked against Microsoft Learn on $(Esc $lastVerified)</p>
  </div>
</header>
"@
}

function Get-Footer([string]$posterName) {
    @"
<footer>
  <p class="disclaimer">$(Esc $copy.disclaimer) Not an official Microsoft publication.</p>
  <p>$(Esc $posterName) &middot; generated $(Esc $generatedUtc) from data/evidence-catalog.json (schema $(Esc $catalog.schema_version))</p>
</footer>
"@
}

function Get-StatusLegend {
    ($copy.verification_legend | ForEach-Object {
        $fake = [pscustomobject]@{ verification = [pscustomobject]@{ status = $_.status; gaps = @('x') } }
        $badge = (Get-StatusBadge $fake) -replace ' &middot; 1 open gap', ''
        "<div class=`"legend-row`"><span>$badge</span><span>$(Esc $_.meaning)</span></div>"
    }) -join "`n"
}

$planeOrder = @{}; foreach ($pl in $copy.planes) { $planeOrder[$pl.name] = [int]$pl.number }

function Sort-Entries($entries) {
    $entries | Sort-Object @{ Expression = { $planeOrder[$_.evidence_plane] } },
                            @{ Expression = { switch ($_.priority) { 'Core' { 0 } 'Extended' { 1 } default { 2 } } } },
                            @{ Expression = { $_.id } }
}

# ================================================================== POSTER 1
$p1Entries = @(Sort-Entries ($catalog.entries | Where-Object { $_.publication.poster_1 }))
$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append((Get-Head $copy.posters.poster_1.title $p1css))
[void]$sb.Append('<body class="poster poster-1">')
[void]$sb.Append((Get-Masthead $copy.posters.poster_1 $p1Entries ''))

# Sidebar
$catalogued = @($catalog.entries.evidence_plane | Sort-Object -Unique)
$missingPlanes = @($copy.planes | Where-Object { $_.name -notin $catalogued } | ForEach-Object { $_.name })
$questionItems = ($copy.readiness.questions | ForEach-Object { '<li>' + (Esc $_) + '</li>' }) -join ''
$legendRows = ($copy.availability_legend | ForEach-Object {
    "<div class=`"legend-row`"><span>$(Get-Chips @($_.code))</span><span>$(Esc $_.meaning)</span></div>"
}) -join "`n"

[void]$sb.Append(@"
<div class="layout">
<aside class="sidebar">
  <section class="panel alert" aria-labelledby="readiness">
    <h2 id="readiness">$(Esc $copy.readiness.headline)</h2>
    <p>$(Esc $copy.readiness.intro)</p>
    <ol>$questionItems</ol>
  </section>
  <section class="panel" aria-labelledby="legend-availability">
    <h3 id="legend-availability">Availability legend</h3>
    $legendRows
  </section>
  <section class="panel" aria-labelledby="legend-status">
    <h3 id="legend-status">Verification status</h3>
    $(Get-StatusLegend)
  </section>
  <section class="panel" aria-labelledby="terms">
    <h3 id="terms">Terminology</h3>
    $(Get-List $copy.terminology_notes)
  </section>
  <section class="panel" aria-labelledby="categories">
    <h3 id="categories">Resource Log categories</h3>
    <p>Categories and tables differ for every Azure service and are not printed here. See $(Link 'src-resource-logs-categories' $sourceById['src-resource-logs-categories'].title) and the interactive map.</p>
  </section>
"@)
if ($missingPlanes.Count) {
    [void]$sb.Append(@"
  <section class="panel" aria-labelledby="planned">
    <h3 id="planned">Not yet catalogued</h3>
    <p class="small">These planes have no verified catalog entries yet and are intentionally left off this edition:</p>
    $(Get-List $missingPlanes 'small')
  </section>
"@)
}
[void]$sb.Append('</aside>')

# Main table
[void]$sb.Append(@'
<main>
<table class="evidence">
<caption class="small" style="text-align:left;caption-side:bottom;padding-top:0.12in">Each row is one catalog entry. Availability chips use text labels; color is supplementary.</caption>
<colgroup><col class="c-plane"><col class="c-product"><col class="c-source"><col class="c-avail"><col class="c-where"><col class="c-pres"><col class="c-rel"><col class="c-learn"></colgroup>
<thead><tr><th scope="col">Evidence plane</th><th scope="col">Microsoft product</th><th scope="col">Log or evidence source</th><th scope="col">Availability</th><th scope="col">Where to investigate</th><th scope="col">Preservation or destination</th><th scope="col">Investigation relevance</th><th scope="col">Microsoft Learn</th></tr></thead>
<tbody>
'@)
foreach ($plane in $copy.planes) {
    $rows = @($p1Entries | Where-Object { $_.evidence_plane -eq $plane.name })
    if ($rows.Count -eq 0) { continue }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $e = $rows[$i]
        $prod = $productById[$e.product_id]
        [void]$sb.Append("<tr data-entry-id=`"$(Esc $e.id)`" style=`"$(Get-PlaneStyle $e.evidence_plane)`">")
        if ($i -eq 0) {
            [void]$sb.Append("<th scope=`"rowgroup`" rowspan=`"$($rows.Count)`" class=`"plane-cell`">$(Get-PlaneBadge $e.evidence_plane)<span class=`"plane-name`">$(Esc $e.evidence_plane)</span></th>")
        }
        [void]$sb.Append("<td><span class=`"product`">$(Esc $prod.name)</span><span class=`"etype`">$(Esc $e.evidence_type)</span></td>")
        $replaced = ''
        if ($e.replaced_by) { $replaced = "<div class=`"small`">Use instead: $(Esc $entryById[$e.replaced_by].evidence_source)</div>" }
        [void]$sb.Append("<td><div class=`"source`">$(Esc $e.evidence_source)</div>$(Get-StatusBadge $e)$replaced</td>")
        $retention = if ($e.native_retention) { "<div class=`"small`">Native retention: $(Esc $e.native_retention)</div>" } else { '' }
        [void]$sb.Append("<td>$(Get-Chips $e.availability_flags)<div class=`"small`">$(Esc $e.availability)</div>$retention</td>")
        [void]$sb.Append("<td>$(Esc $e.where_to_investigate)</td>")
        [void]$sb.Append("<td>$(Get-List $e.preservation_options)</td>")
        [void]$sb.Append("<td>$(Get-List $e.investigation_relevance)</td>")
        $doc = $sourceById[$e.evidence_doc_source_id]
        [void]$sb.Append("<td class=`"learn`">$(Link $prod.what_is_source_id $prod.learn_label)<span class=`"doc`">Evidence docs: $(Link $e.evidence_doc_source_id $doc.title)</span></td>")
        [void]$sb.Append("</tr>`n")
    }
}
[void]$sb.Append('</tbody></table></main></div>')
[void]$sb.Append((Get-Footer 'Poster 1: Evidence Map'))
[void]$sb.Append('</body></html>')

$p1Dir = Join-Path $OutputRoot 'poster-1-evidence-map'
New-Item -ItemType Directory -Force -Path $p1Dir | Out-Null
$p1Path = Join-Path $p1Dir 'poster-1-evidence-map.html'
Set-Content -LiteralPath $p1Path -Value $sb.ToString() -Encoding utf8NoBOM

# ================================================================== POSTER 2
$pathByCommand = @{}
foreach ($path in $copy.acquisition_paths) { foreach ($c in $path.commands) { $pathByCommand[$c] = [int]$path.number } }
$primaryPath = @{}
foreach ($prop in $copy.acquisition_type_paths.PSObject.Properties) { $primaryPath[$prop.Name] = [int]$prop.Value }

function Get-CommandPath($entry, [int]$index) {
    $cmds = @($entry.powershell.commands)
    $c = $cmds[$index]
    if ($pathByCommand.ContainsKey($c.command)) { return $pathByCommand[$c.command] }
    if ($c.role -eq 'Authenticates session') {
        for ($j = $index + 1; $j -lt $cmds.Count; $j++) {
            if ($pathByCommand.ContainsKey($cmds[$j].command)) { return $pathByCommand[$cmds[$j].command] }
        }
    }
    throw "Command '$($c.command)' in '$($entry.id)' has no acquisition path in presentation.json."
}

$p2Entries = @(Sort-Entries ($catalog.entries | Where-Object { $_.publication.poster_2 }))
# rows[pathNumber] = ordered list of @{ entry; commands }
$rowsByPath = @{}
foreach ($path in $copy.acquisition_paths) { $rowsByPath[[int]$path.number] = [System.Collections.Generic.List[object]]::new() }
$noMethod = [System.Collections.Generic.List[object]]::new()
foreach ($e in $p2Entries) {
    $cmds = @($e.powershell.commands)
    if (-not $e.powershell.supported -or $cmds.Count -eq 0) { $noMethod.Add($e); continue }
    $byPath = [ordered]@{}
    for ($i = 0; $i -lt $cmds.Count; $i++) {
        # String keys: an [ordered] dictionary indexed with an int returns the item at that position.
        $k = [string](Get-CommandPath $e $i)
        if (-not $byPath.Contains($k)) { $byPath[$k] = [System.Collections.Generic.List[object]]::new() }
        $byPath[$k].Add($cmds[$i])
    }
    foreach ($k in $byPath.Keys) { $rowsByPath[[int]$k].Add([pscustomobject]@{ entry = $e; commands = $byPath[$k] }) }
}

function Get-CommandLinkSource($cmd) {
    $ref = $cmd.source_ids | Where-Object { $sourceById[$_].doc_type -eq 'Cmdlet reference' } | Select-Object -First 1
    if (-not $ref) { $ref = $cmd.source_ids | Select-Object -First 1 }
    $ref
}

function Get-CommandHtml($cmd, $sharedPaging) {
    $tag = $roleTag[$cmd.role]
    $tagCls = 'tag-' + (($tag -replace '\s', '-').ToLowerInvariant())
    $api = if ($cmd.api_status -and $cmd.api_status -notin @('Not applicable')) {
        "<span class=`"api api-$($cmd.api_status.ToLowerInvariant() -replace '\s','-')`">$(Esc $cmd.api_status)</span>"
    } else { '' }
    $srcId = Get-CommandLinkSource $cmd
    $name = if ($srcId) { Link $srcId $cmd.command } else { Esc $cmd.command }
    $unverified = if (-not $cmd.verified) { ' <span class="unverified">Verification required</span>' } else { '' }
    $paging = if ($sharedPaging -and $sharedPaging.Contains([string]$cmd.pagination)) {
        '<div class="paging">Paging and limits: see the shared box for this path.</div>'
    } elseif ($cmd.pagination -and $cmd.pagination -ne 'Not applicable') {
        $cls = if ($cmd.pagination -eq 'Verification required') { 'paging unverified' } else { 'paging' }
        "<div class=`"$cls`">Paging and limits: $(Esc $cmd.pagination)</div>"
    } else { '' }
    $note = if ($cmd.notes) { "<div class=`"note`">$(Esc $cmd.notes)</div>" } else { '' }
    "<div class=`"cmd`" data-command-id=`"$(Esc $cmd.id)`"><span class=`"tag $tagCls`">$(Esc $tag)</span><span class=`"name`">$name</span>$api$unverified<code>$(Esc $cmd.example)</code>$paging$note</div>"
}

function Get-PriorCollection($e) {
    $first = Get-FirstSentence $e.configuration_notes
    if (-not $first) { $first = $e.deployment_dependency }
    $retention = if ($e.native_retention) { "<div class=`"small`">Native retention: $(Esc $e.native_retention)</div>" } else { '' }
    $firstHtml = if ($first) { '<div>' + (Esc $first) + '</div>' } else { '' }
    '<div>' + (Get-Chips $e.availability_flags) + ' <strong>' + (Esc $e.availability) + '</strong></div>' + $firstHtml + $retention
}

$tagLegend = ($copy.command_roles | ForEach-Object {
    $cls = 'tag-' + (($_.tag -replace '\s', '-').ToLowerInvariant())
    "<div class=`"legend-row`"><span><span class=`"tag $cls`">$(Esc $_.tag)</span></span><span>$(Esc $_.role)</span></div>"
}) -join "`n"
$formatRows = ($copy.output_guidance | ForEach-Object {
    "<div class=`"legend-row`"><span><span class=`"chip chip-fmt`">$(Esc $_.format)</span></span><span>$(Esc $_.use)</span></div>"
}) -join "`n"

function Get-PermText($perm) {
    $u = if (-not $perm.verified) { ' <span class="unverified">Verification required</span>' } else { '' }
    '<strong>' + (Esc $perm.context) + ':</strong> ' + (Esc $perm.value) + $u
}

function Get-Repeated([string[]]$values) {
    # Values that occur in two or more cards of the same path are printed once in the path box.
    $set = [System.Collections.Generic.HashSet[string]]::new()
    $values | Group-Object | Where-Object { $_.Count -ge 2 } | ForEach-Object { [void]$set.Add($_.Name) }
    , $set
}

# Which sheet carries each path, so cross-references can name the other sheet.
$sheets = @($copy.posters.poster_2.sheets)
$sheetByPath = @{}
foreach ($sh in $sheets) { foreach ($pn in $sh.paths) { $sheetByPath[[int]$pn] = $sh } }
foreach ($path in $copy.acquisition_paths) {
    if (-not $sheetByPath.ContainsKey([int]$path.number)) { throw "Acquisition path $($path.number) is not assigned to a Poster 2 sheet in presentation.json." }
}

function Get-PathHtml($path) {
    $n = [int]$path.number
    $rows = $rowsByPath[$n]
    if ($rows.Count -eq 0) { return '' }
    $out = [System.Text.StringBuilder]::new()

    $primaryRows = @($rows | Where-Object {
        $t = $_.entry.powershell.acquisition_type
        (-not $primaryPath.ContainsKey($t)) -or $primaryPath[$t] -eq $n
    })
    # Each card contributes each distinct value once.
    $sharedPerms = Get-Repeated @($primaryRows | ForEach-Object { @($_.entry.required_permissions | ForEach-Object { Get-PermText $_ } | Select-Object -Unique) })
    $sharedLims = Get-Repeated @($primaryRows | ForEach-Object { @($_.entry.limitations | Select-Object -Unique) })
    $sharedPaging = Get-Repeated @($rows | ForEach-Object { @($_.commands | Where-Object { $_.pagination -notin @('Not applicable', 'Verification required') } | ForEach-Object { [string]$_.pagination } | Select-Object -Unique) })

    [void]$out.Append(@"
<section class="path-head" aria-labelledby="path-$n"><div class="path-title"><span class="no" aria-hidden="true">$n</span><h2 id="path-$n">$(Esc $path.name)</h2></div><p>$(Esc $path.description)</p>
"@)
    if ($sharedPerms.Count -or $sharedLims.Count -or $sharedPaging.Count) {
        [void]$out.Append('<div class="shared"><div class="label">Shared by several sources in this path</div>')
        if ($sharedPerms.Count) { [void]$out.Append('<div class="sublabel">Required permissions</div><ul>' + (($sharedPerms | ForEach-Object { "<li>$_</li>" }) -join '') + '</ul>') }
        if ($sharedPaging.Count) { [void]$out.Append('<div class="sublabel">Paging and limits</div>' + (Get-List $sharedPaging)) }
        if ($sharedLims.Count) { [void]$out.Append('<div class="sublabel">Important limitations</div>' + (Get-List $sharedLims)) }
        [void]$out.Append('</div>')
    }
    [void]$out.Append('</section>')

    foreach ($row in $rows) {
        $e = $row.entry
        $prod = $productById[$e.product_id]
        $hasPrimary = $primaryPath.ContainsKey($e.powershell.acquisition_type)
        $isPrimary = (-not $hasPrimary) -or $primaryPath[$e.powershell.acquisition_type] -eq $n
        $method = if ($isPrimary) { Esc $e.powershell.acquisition_type } else { (Esc $path.name) + ' <span class="muted">(additional route)</span>' }
        $apiLine = ''
        if ($isPrimary -and $e.api.supported -and $e.api.name) {
            $apiStatus = if ($e.api.status -and $e.api.status -ne 'Not applicable') { ' (' + (Esc $e.api.status) + ')' } else { '' }
            $apiLine = '<div class="meta"><span class="k">API</span> ' + (Esc $e.api.name) + $apiStatus + '</div>'
        }
        $interfaces = @($row.commands | ForEach-Object { $_.interface } | Select-Object -Unique)
        $ifaceHtml = ($interfaces | ForEach-Object { '<span class="mono">' + (Esc $_) + '</span>' }) -join ', '
        $cmdHtml = ($row.commands | ForEach-Object { Get-CommandHtml $_ $sharedPaging }) -join ''
        [void]$out.Append("<article class=`"card`" data-entry-id=`"$(Esc $e.id)`" data-path=`"$n`" style=`"$(Get-PlaneStyle $e.evidence_plane)`">")
        [void]$out.Append("<div class=`"card-kicker`">$(Get-PlaneBadge $e.evidence_plane) $(Esc $prod.short_name) $(Get-StatusBadge $e)</div>")
        [void]$out.Append("<h3 class=`"source`">$(Esc $e.evidence_source)</h3>")
        [void]$out.Append("<div class=`"meta`"><span class=`"k`">Acquisition method</span> $method</div>$apiLine<div class=`"meta`"><span class=`"k`">PowerShell module or interface</span> $ifaceHtml</div>")
        [void]$out.Append("<div class=`"field`"><div class=`"label`">Cmdlet, API, or query mechanism</div>$cmdHtml</div>")
        if ($isPrimary) {
            $own = @($e.required_permissions | Where-Object { -not $sharedPerms.Contains((Get-PermText $_)) })
            $permCount = @($e.required_permissions).Count
            $permItems = @($own | ForEach-Object { '<li>' + (Get-PermText $_) + '</li>' })
            if ($own.Count -lt $permCount) { $permItems += '<li class="muted">Plus the shared permissions for this path</li>' }
            $perms = if ($permCount) { '<ul>' + ($permItems -join '') + '</ul>' } else { '<span class="muted">None documented</span>' }
            $ownLims = @($e.limitations | Where-Object { -not $sharedLims.Contains($_) })
            $limItems = @($ownLims | ForEach-Object { '<li>' + (Esc $_) + '</li>' })
            if ($ownLims.Count -lt @($e.limitations).Count) { $limItems += '<li class="muted">Plus the shared limitations for this path</li>' }
            $lims = if ($limItems.Count) { '<ul>' + ($limItems -join '') + '</ul>' } else { '' }
            $fmtHtml = ($e.output_formats | ForEach-Object { '<span class="chip chip-fmt">' + (Esc $_) + '</span>' }) -join ' '
            [void]$out.Append("<div class=`"field`"><div class=`"label`">Required permissions</div>$perms</div>")
            [void]$out.Append("<div class=`"field`"><div class=`"label`">Prior-collection requirement</div>$(Get-PriorCollection $e)</div>")
            [void]$out.Append("<div class=`"meta out`"><span class=`"k`">Recommended output format</span> $fmtHtml</div>")
            [void]$out.Append("<div class=`"field`"><div class=`"label`">Important limitations</div>$lims</div>")
        } else {
            $primaryNo = $primaryPath[$e.powershell.acquisition_type]
            $where = "path $primaryNo"
            $otherSheet = $sheetByPath[$primaryNo]
            if ($otherSheet.id -ne $sheetByPath[$n].id) { $where += " on $(Esc $otherSheet.label)" }
            [void]$out.Append("<p class=`"small see`">Permissions, prior-collection requirement, output, and limitations: see this source under $where.</p>")
        }
        [void]$out.Append("</article>`n")
    }
    $out.ToString()
}

$p2Dir = Join-Path $OutputRoot 'poster-2-powershell-acquisition'
New-Item -ItemType Directory -Force -Path $p2Dir | Out-Null
# Remove outputs from earlier layouts so a stale single-sheet poster can't be mistaken for the current one.
Get-ChildItem -LiteralPath $p2Dir -File | Where-Object { $_.Name -like 'poster-2*' } | Remove-Item -Force
$p2Paths = [System.Collections.Generic.List[string]]::new()

foreach ($sh in $sheets) {
    $sheetPaths = @($copy.acquisition_paths | Where-Object { [int]$_.number -in @($sh.paths | ForEach-Object { [int]$_ }) })
    $sheetEntries = @($sheetPaths | ForEach-Object { $rowsByPath[[int]$_.number] } | ForEach-Object { $_.entry } | Sort-Object id -Unique)
    $pathNames = ($sheetPaths | ForEach-Object { "$($_.number). $($_.name)" }) -join ' &middot; '
    $sheetName = if ($sh.PSObject.Properties['name'] -and $sh.name) { " &middot; $(Esc $sh.name)" } else { '' }
    $sheetLabel = "$(Esc $sh.label) of $($sheets.Count)${sheetName}: $pathNames"

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append((Get-Head "$($copy.posters.poster_2.title) ($($sh.label))" $p2css))
    [void]$sb.Append("<body class=`"poster poster-2 sheet-$(Esc $sh.id)`">")
    [void]$sb.Append((Get-Masthead $copy.posters.poster_2 $sheetEntries $sheetLabel))
    # Side panels are configurable per sheet in presentation.json (posters.poster_2.sheets[].panels_start / panels_end).
    $panelHtml = @{
        warning      = "<section class=`"panel warning`"><h2>$(Esc $copy.acquisition_warning)</h2><p>$(Esc $copy.readiness.headline)</p></section>"
        tags         = "<section class=`"panel`"><h3>Command tags</h3>$tagLegend<p class=`"small`">Interface status follows each command name: GA, Current, Beta, Preview, Retiring. Beta and preview interfaces can change without notice.</p></section>"
        status       = "<section class=`"panel`"><h3>Verification status</h3>$(Get-StatusLegend)<p class=`"small`">`"Verification required`" marks a value Microsoft documentation did not confirm. Test it before relying on it.</p></section>"
        availability = "<section class=`"panel`"><h3>Availability legend</h3>$legendRows</section>"
        record       = "<section class=`"panel`"><h3>Record every acquisition</h3>$(Get-List $copy.acquisition_record)<p class=`"small`">$(Esc $copy.chain_of_custody_note)</p></section>"
        formats      = "<section class=`"panel`"><h3>Output formats</h3>$formatRows</section>"
    }
    function Get-Panels($ids) {
        (@($ids) | Where-Object { $_ } | ForEach-Object {
            if (-not $panelHtml.ContainsKey($_)) { throw "Unknown Poster 2 panel '$_' in presentation.json." }
            $panelHtml[$_]
        }) -join "`n"
    }
    $startPanels = if ($sh.PSObject.Properties['panels_start']) { $sh.panels_start } else { @('warning', 'tags', 'status', 'availability') }
    $endPanels = if ($sh.PSObject.Properties['panels_end']) { $sh.panels_end } else { @('record', 'formats') }
    $noteHtml = if ($sh.PSObject.Properties['note'] -and $sh.note) { "<section class=`"panel note-panel`"><p>$(Esc $sh.note)</p></section>" } else { '' }

    [void]$sb.Append('<main class="p2main"><div class="flow">')
    [void]$sb.Append((Get-Panels $startPanels))
    [void]$sb.Append($noteHtml)
    foreach ($path in $sheetPaths) { [void]$sb.Append((Get-PathHtml $path)) }
    if ($sh.id -eq $sheets[-1].id -and $noMethod.Count) {
        [void]$sb.Append('<section class="panel"><h3>No documented PowerShell method</h3>')
        [void]$sb.Append((Get-List ($noMethod | ForEach-Object { $productById[$_.product_id].short_name + ': ' + $_.evidence_source })))
        [void]$sb.Append('</section>')
    }
    [void]$sb.Append((Get-Panels $endPanels))
    [void]$sb.Append('</div></main>')
    [void]$sb.Append((Get-Footer "Poster 2: PowerShell Acquisition, $($sh.label)"))
    [void]$sb.Append('</body></html>')

    $file = Join-Path $p2Dir "poster-2$($sh.id)-powershell-acquisition.html"
    Set-Content -LiteralPath $file -Value $sb.ToString() -Encoding utf8NoBOM
    $p2Paths.Add($file)
}

# ================================================================== consistency checks
$failures = [System.Collections.Generic.List[string]]::new()
$knownUrls = [System.Collections.Generic.HashSet[string]]::new([string[]]@($sources.sources.url))

function Test-Poster([string[]]$paths, [string]$flag, [string]$label) {
    $all = [System.Text.StringBuilder]::new()
    foreach ($path in $paths) {
        $html = Get-Content -LiteralPath $path -Raw
        [void]$all.Append($html)
        foreach ($m in [regex]::Matches($html, 'href="([^"]+)"')) {
            $url = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
            if (-not $knownUrls.Contains($url)) { $failures.Add("$(Split-Path -Leaf $path): link '$url' is not a registered source URL.") }
        }
    }
    $html = $all.ToString()
    $ids = [regex]::Matches($html, '<(?:tr|article) [^>]*?data-entry-id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    $expected = @($catalog.entries | Where-Object { $_.publication.$flag } | ForEach-Object { $_.id })
    foreach ($id in $expected) {
        $count = @($ids | Where-Object { $_ -eq $id }).Count
        if ($flag -eq 'poster_1' -and $count -ne 1) { $failures.Add("${label}: entry '$id' should appear exactly once.") }
        if ($flag -eq 'poster_2' -and $count -lt 1 -and @($entryById[$id].powershell.commands).Count -gt 0) { $failures.Add("${label}: entry '$id' is missing.") }
    }
    foreach ($id in ($ids | Sort-Object -Unique)) { if ($id -notin $expected) { $failures.Add("${label}: entry '$id' is not flagged for this poster.") } }
    $html
}

[void](Test-Poster @($p1Path) 'poster_1' 'Poster 1')
$p2Html = Test-Poster $p2Paths.ToArray() 'poster_2' 'Poster 2'
$commandHits = @([regex]::Matches($p2Html, 'data-command-id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
foreach ($e in $p2Entries) {
    foreach ($c in $e.powershell.commands) {
        $hits = @($commandHits | Where-Object { $_ -eq $c.id }).Count
        if ($hits -ne 1) { $failures.Add("Poster 2: command '$($c.id)' of '$($e.id)' appears $hits times across the sheets; expected once.") }
    }
}

# ================================================================== optional rendering
function Find-Browser {
    if ($BrowserPath) { return $BrowserPath }
    $candidates = @($env:CHROME_PATH, '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '/usr/bin/google-chrome', '/usr/bin/chromium',
                    '/usr/bin/chromium-browser', 'C:\Program Files\Google\Chrome\Application\chrome.exe',
                    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
    $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

# Measures the laid-out page in a headless browser: content must stay inside 48 x 36 in, and the
# fixed-height column flow on Poster 2 must not spill into extra columns beyond the page width.
$overflowProbe = @'
<script>
(function () {
  var r = [], ppi = 96;
  var f = document.querySelector('.flow');
  if (f && f.scrollWidth > f.clientWidth + 2) { r.push('column flow needs ' + Math.round(f.scrollWidth / ppi * 10) / 10 + ' in of width but has ' + Math.round(f.clientWidth / ppi * 10) / 10 + ' in'); }
  var h = document.documentElement.scrollHeight; if (h > 36 * ppi + 2) { r.push('page height ' + Math.round(h / ppi * 10) / 10 + ' in exceeds 36 in'); }
  var w = document.documentElement.scrollWidth; if (w > 48 * ppi + 2) { r.push('page width ' + Math.round(w / ppi * 10) / 10 + ' in exceeds 48 in'); }
  var fill = '';
  if (f) {
    var limit = f.clientHeight; f.style.height = 'auto'; f.style.columnFill = 'balance';
    fill = ' | balanced column height ' + Math.round(f.scrollHeight / ppi * 10) / 10 + ' in of ' + Math.round(limit / ppi * 10) / 10 + ' in available';
  }
  document.title = 'OVERFLOW-CHECK:' + (r.join('; ') || 'ok') + fill;
})();
</script>
'@

$headroomWarnings = [System.Collections.Generic.List[string]]::new()

function Test-Overflow([string]$browser, [string]$html) {
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("probe-" + [guid]::NewGuid().ToString('N') + '.html')
    try {
        (Get-Content -LiteralPath $html -Raw).Replace('</body>', "$overflowProbe</body>") | Set-Content -LiteralPath $probe -Encoding utf8NoBOM
        $uri = [System.Uri]::new($probe).AbsoluteUri
        $dom = & $browser '--headless=new' '--no-sandbox' '--disable-gpu' '--hide-scrollbars' '--window-size=4608,3456' '--virtual-time-budget=5000' '--dump-dom' $uri 2>$null | Out-String
        $m = [regex]::Match($dom, '<title>OVERFLOW-CHECK:([^<]*)</title>')
        if (-not $m.Success) { return 'overflow probe did not run' }
        $result = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        $parts = $result -split ' \| ', 2
        if ($parts.Count -gt 1) {
            Write-Host "     $(Split-Path -Leaf $html): $($parts[1])"
            $fm = [regex]::Match($parts[1], 'height ([\d.]+) in of ([\d.]+) in')
            if ($fm.Success -and ([double]$fm.Groups[1].Value / [double]$fm.Groups[2].Value) -gt 0.95) {
                $script:headroomWarnings.Add("$(Split-Path -Leaf $html) is over 95% full; one more card may not fit. Rebalance the sheets in presentation.json.")
            }
        }
        if ($parts[0] -eq 'ok') { return $null } else { return $parts[0] }
    } finally { Remove-Item -LiteralPath $probe -ErrorAction SilentlyContinue }
}

if ($Pdf -or $Png) {
    $browser = Find-Browser
    if (-not $browser) { throw 'No Chromium-based browser found. Pass -BrowserPath.' }
    foreach ($html in @(@($p1Path) + $p2Paths.ToArray())) {
        $uri = [System.Uri]::new((Resolve-Path -LiteralPath $html).Path).AbsoluteUri
        $base = [System.IO.Path]::ChangeExtension($html, $null).TrimEnd('.')
        $common = @('--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars', '--run-all-compositor-stages-before-draw', '--virtual-time-budget=5000')
        $overflow = Test-Overflow $browser $html
        if ($overflow) { $failures.Add("$(Split-Path -Leaf $html): layout overflow: $overflow") } else { Write-Host "FIT  $(Split-Path -Leaf $html) fits on one 48 x 36 in page" }
        if ($Pdf) {
            $pdfPath = "$base.pdf"
            & $browser @common '--no-pdf-header-footer' "--print-to-pdf=$pdfPath" $uri 2>$null | Out-Null
            if (-not (Test-Path -LiteralPath $pdfPath)) { $failures.Add("PDF not produced for $html") ; continue }
            $bytes = [System.IO.File]::ReadAllText($pdfPath, [System.Text.Encoding]::Latin1)
            $pages = [regex]::Matches($bytes, '/Type\s*/Page(?![a-zA-Z])').Count
            if ($pages -ne 1) { $failures.Add("$(Split-Path -Leaf $pdfPath): content overflows onto $pages pages; it must fit on one.") }
            Write-Host "PDF  $pdfPath ($pages page)"
        }
        if ($Png) {
            $pngPath = "$base.png"
            & $browser @common '--window-size=4608,3456' '--force-device-scale-factor=0.5' "--screenshot=$pngPath" $uri 2>$null | Out-Null
            Write-Host "PNG  $pngPath"
        }
    }
}

Write-Host "HTML $p1Path ($($p1Entries.Count) entries)"
foreach ($f in $p2Paths) { Write-Host "HTML $f" }
$headroomWarnings | ForEach-Object { Write-Host "WARN $_" }
if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'Poster consistency checks passed.'
