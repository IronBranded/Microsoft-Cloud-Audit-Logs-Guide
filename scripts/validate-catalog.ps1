#Requires -Version 7.4
<#
.SYNOPSIS
    Validates the Microsoft Cloud Audit Logs Guide data files and writes the validation report.

.DESCRIPTION
    1. Validates each data file against schema/evidence-catalog.schema.json (Test-Json, JSON Schema 2020-12).
    2. Runs cross-file and accuracy-gate checks that a schema cannot express (ids resolve,
       'Verified' means no open gaps, terminology rules, publication rules, sensitive-data scan).
    3. Writes reports/validation-report.md from the catalog itself, so the report cannot drift
       from the data.

    Exit code 0 when there are no errors (warnings are allowed), 1 otherwise.
    No third-party modules are required.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's folder.

.PARAMETER ReportPath
    Where to write the Markdown validation report. Defaults to reports/validation-report.md.

.PARAMETER StaleAfterDays
    Entries whose last_verified date is older than this produce a warning.

.EXAMPLE
    pwsh ./scripts/validate-catalog.ps1
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $ReportPath,
    [int] $StaleAfterDays = 180
)

$ErrorActionPreference = 'Stop'
if (-not $ReportPath) { $ReportPath = Join-Path $RepoRoot 'reports/validation-report.md' }

$errors   = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$checks   = [System.Collections.Generic.List[object]]::new()

function Add-CheckResult {
    param([string] $Name, [string[]] $Failures, [ValidateSet('Error', 'Warning')] [string] $Severity = 'Error')
    $failed = @($Failures | Where-Object { $_ })
    foreach ($f in $failed) {
        if ($Severity -eq 'Error') { $errors.Add("[$Name] $f") } else { $warnings.Add("[$Name] $f") }
    }
    $checks.Add([pscustomobject]@{
        Name     = $Name
        Severity = $Severity
        Result   = if ($failed.Count -eq 0) { 'Pass' } elseif ($Severity -eq 'Error') { 'Fail' } else { 'Warn' }
        Count    = $failed.Count
    })
}

# ---------------------------------------------------------------- load files
$files = [ordered]@{
    catalog       = @{ Path = 'data/evidence-catalog.json'; Def = 'catalogFile' }
    products      = @{ Path = 'data/products.json';         Def = 'productsFile' }
    sources       = @{ Path = 'data/sources.json';          Def = 'sourcesFile' }
    relationships = @{ Path = 'data/relationships.json';    Def = 'relationshipsFile' }
}
$schemaPath = Join-Path $RepoRoot 'schema/evidence-catalog.schema.json'
$schemaText = Get-Content -Raw -LiteralPath $schemaPath
$raw  = @{}
$data = @{}
foreach ($key in $files.Keys) {
    $full = Join-Path $RepoRoot $files[$key].Path
    $raw[$key]  = Get-Content -Raw -LiteralPath $full
    $data[$key] = $raw[$key] | ConvertFrom-Json -Depth 64
}

# ---------------------------------------------------------------- 1. schema validation
$schemaFailures = foreach ($key in $files.Keys) {
    $wrapper = $schemaText | ConvertFrom-Json -AsHashtable -Depth 64
    $wrapper['$ref'] = "#/`$defs/$($files[$key].Def)"
    $wrapperText = $wrapper | ConvertTo-Json -Depth 64
    $schemaErrors = $null
    $ok = Test-Json -Json $raw[$key] -Schema $wrapperText -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
    if (-not $ok) {
        foreach ($e in $schemaErrors) { "$($files[$key].Path): $($e.Exception.Message) $($e.ErrorDetails.Message)".Trim() }
        if (-not $schemaErrors) { "$($files[$key].Path): failed schema validation" }
    }
}
Add-CheckResult -Name 'Schema validation' -Failures $schemaFailures

$entries   = @($data.catalog.entries)
$products  = @($data.products.products)
$sources   = @($data.sources.sources)
$relations = @($data.relationships.relationships)

$productById = @{}; foreach ($p in $products) { $productById[$p.id] = $p }
$sourceById  = @{}; foreach ($s in $sources)  { $sourceById[$s.id]  = $s }
$entryById   = @{}; foreach ($e in $entries)  { $entryById[$e.id]   = $e }

# Collects every source id an entry references.
function Get-EntrySourceIds {
    param($Entry)
    $ids = [System.Collections.Generic.List[string]]::new()
    $ids.Add($Entry.evidence_doc_source_id)
    foreach ($t in @($Entry.log_analytics_tables)) { foreach ($i in @($t.source_ids)) { $ids.Add($i) } }
    foreach ($c in @($Entry.powershell.commands))  { foreach ($i in @($c.source_ids)) { $ids.Add($i) } }
    foreach ($p in @($Entry.required_permissions)) { foreach ($i in @($p.source_ids)) { $ids.Add($i) } }
    foreach ($k in @($Entry.kql_examples))         { foreach ($i in @($k.source_ids)) { $ids.Add($i) } }
    foreach ($i in @($Entry.api.source_ids))           { $ids.Add($i) }
    foreach ($i in @($Entry.verification.source_ids))  { $ids.Add($i) }
    return @($ids | Where-Object { $_ })
}

# ---------------------------------------------------------------- 2. integrity checks
$dupFailures = @()
foreach ($set in @(
        @{ Name = 'entry';        Ids = $entries.id },
        @{ Name = 'product';      Ids = $products.id },
        @{ Name = 'source';       Ids = $sources.id },
        @{ Name = 'relationship'; Ids = $relations.id },
        @{ Name = 'command';      Ids = @($entries | ForEach-Object { $_.powershell.commands.id }) },
        @{ Name = 'source URL';   Ids = $sources.url })) {
    $dupFailures += $set.Ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object { "Duplicate $($set.Name): $($_.Name)" }
}
$dupFailures += $entries | Group-Object { "$($_.product_id)|$($_.evidence_source)" } | Where-Object Count -gt 1 |
    ForEach-Object { "Same product and evidence source listed twice: $($_.Name)" }
Add-CheckResult -Name 'Unique identifiers' -Failures $dupFailures

$refFailures = @()
foreach ($e in $entries) {
    if (-not $productById.ContainsKey($e.product_id)) { $refFailures += "$($e.id): unknown product_id '$($e.product_id)'" }
    foreach ($sid in (Get-EntrySourceIds $e)) {
        if (-not $sourceById.ContainsKey($sid)) { $refFailures += "$($e.id): unknown source id '$sid'" }
    }
    if ($e.replaced_by -and -not $entryById.ContainsKey($e.replaced_by)) { $refFailures += "$($e.id): replaced_by '$($e.replaced_by)' not in catalog" }
}
foreach ($p in $products) {
    if (-not $sourceById.ContainsKey($p.what_is_source_id)) { $refFailures += "product $($p.id): unknown what_is_source_id '$($p.what_is_source_id)'" }
}
foreach ($r in $relations) {
    foreach ($end in @($r.from, $r.to)) {
        if (-not $entryById.ContainsKey($end)) { $refFailures += "$($r.id): endpoint '$end' not in catalog" }
    }
    if ($r.from -eq $r.to) { $refFailures += "$($r.id): relationship points to itself" }
    foreach ($sid in @($r.source_ids)) {
        if (-not $sourceById.ContainsKey($sid)) { $refFailures += "$($r.id): unknown source id '$sid'" }
    }
}
Add-CheckResult -Name 'References resolve' -Failures $refFailures

# ---------------------------------------------------------------- 3. accuracy gates
$gateFailures = @()
foreach ($e in $entries) {
    $status = $e.verification.status
    $gaps   = @($e.verification.gaps)
    if ($status -eq 'Verified') {
        if ($gaps.Count -gt 0) { $gateFailures += "$($e.id): Verified but lists $($gaps.Count) open gap(s)" }
        $json = $e | ConvertTo-Json -Depth 32
        if ($json -match 'Verification required') { $gateFailures += "$($e.id): Verified but contains 'Verification required'" }
        if (@($e.powershell.commands | Where-Object { -not $_.verified }).Count)  { $gateFailures += "$($e.id): Verified but has unverified commands" }
        if (@($e.required_permissions | Where-Object { -not $_.verified }).Count) { $gateFailures += "$($e.id): Verified but has unverified permissions" }
        if (@($e.log_analytics_tables | Where-Object { -not $_.verified }).Count) { $gateFailures += "$($e.id): Verified but has unverified tables" }
        if (@($e.kql_examples | Where-Object { -not $_.verified }).Count)         { $gateFailures += "$($e.id): Verified but has unverified KQL" }
        $linked = @(Get-EntrySourceIds $e | Where-Object { $sourceById[$_].verification_method -eq 'Linked from verified page' })
        if ($linked.Count) { $gateFailures += "$($e.id): Verified but relies on link-only sources ($($linked -join ', '))" }
    }
    if ($status -in 'Conditional', 'Verification required' -and $gaps.Count -eq 0) {
        $gateFailures += "$($e.id): status '$status' needs at least one documented gap (or should be Verified)"
    }
    if ($status -eq 'Deprecated or replaced' -and -not $e.replaced_by) {
        $gateFailures += "$($e.id): Deprecated or replaced needs replaced_by"
    }
}
Add-CheckResult -Name 'Verification status matches evidence' -Failures $gateFailures

$flagFailures = @()
$flagRules = @{
    'Automatic'                               = 'AUTO'
    'Automatic with limited native retention' = 'AUTO'
    'Configuration required'                  = 'CONFIG'
    'Auditing policy dependent'               = 'POLICY'
    'Licensing dependent'                     = 'LICENSE'
    'Deployment dependent'                    = 'DEPLOY'
    'On demand'                               = 'ON DEMAND'
}
foreach ($e in $entries) {
    $flags = @($e.availability_flags)
    $need  = $flagRules[$e.availability]
    if ($need -and $flags -notcontains $need) { $flagFailures += "$($e.id): availability '$($e.availability)' requires the $need flag" }
    if ($e.configuration_required -and -not ($flags -contains 'CONFIG' -or $flags -contains 'POLICY')) {
        $flagFailures += "$($e.id): configuration_required is true but neither CONFIG nor POLICY is flagged"
    }
    if ($flags -contains 'AUTO' -and $flags -contains 'CONFIG') { $flagFailures += "$($e.id): AUTO and CONFIG both set" }
    if ($e.licensing_dependency -and $flags -notcontains 'LICENSE') { $flagFailures += "$($e.id): licensing_dependency set but LICENSE flag missing" }
    if ($flags -contains 'LICENSE' -and -not $e.licensing_dependency) { $flagFailures += "$($e.id): LICENSE flag set but licensing_dependency empty" }
    if ($flags -contains 'DEPLOY' -and -not $e.deployment_dependency) { $flagFailures += "$($e.id): DEPLOY flag set but deployment_dependency empty" }
}
Add-CheckResult -Name 'Availability labels consistent' -Failures $flagFailures

$pubFailures = @()
foreach ($e in $entries) {
    $pub = $e.publication
    if (-not $pub.site) { $pubFailures += "$($e.id): every catalog entry must appear on the site" }
    if ($e.priority -eq 'Core' -and -not ($pub.poster_1 -and $pub.poster_2)) { $pubFailures += "$($e.id): Core entries must be on Poster 1 and Poster 2" }
    if ($e.priority -eq 'Specialized' -and ($pub.poster_1 -or $pub.poster_2)) { $pubFailures += "$($e.id): Specialized entries are site-only" }
    if ($pub.poster_2 -and -not $e.powershell.supported) { $pubFailures += "$($e.id): on Poster 2 without a documented PowerShell method" }
}
Add-CheckResult -Name 'Priority and publication rules' -Failures $pubFailures

# ---------------------------------------------------------------- 4. terminology rules (section 16)
$termFailures = @()
foreach ($e in $entries) {
    $texts = @($e.evidence_source, $e.description, $e.configuration_notes, $e.where_to_investigate) + @($e.limitations) + @($e.investigation_relevance)
    foreach ($t in ($texts | Where-Object { $_ })) {
        if ($t -match '(?i)diagnostic logs?' -and $t -notmatch 'Resource Logs') {
            $termFailures += "$($e.id): uses 'diagnostic logs' without explaining the Resource Logs name"
        }
    }
    if ($e.evidence_type -eq 'Collection configuration' -and $e.evidence_source -match '(?i)\blogs?\b') {
        $termFailures += "$($e.id): a collection configuration must not be named as a log"
    }
    if ($e.product_id -eq 'sentinel' -and $e.evidence_type -ne 'Correlation layer') {
        $termFailures += "$($e.id): Sentinel entries must be typed 'Correlation layer'"
    }
    if ($e.product_id -eq 'defender-antivirus' -and $e.evidence_plane -ne 'Microsoft Defender Antivirus') {
        $termFailures += "$($e.id): Defender Antivirus evidence must stay in its own plane"
    }
    if ($e.product_id -eq 'defender-endpoint' -and $e.evidence_plane -ne 'Microsoft Defender for Endpoint') {
        $termFailures += "$($e.id): Defender for Endpoint evidence must stay in its own plane"
    }
    if ($e.product_id -match 'sysmon' -and -not ($e.configuration_required -and @($e.availability_flags) -contains 'CONFIG')) {
        $termFailures += "$($e.id): Sysmon must be marked configuration required"
    }
    if ($e.product_id -eq 'windows' -and $e.evidence_source -match '(?i)security' -and
        -not ($e.availability -eq 'Auditing policy dependent' -and @($e.availability_flags) -contains 'POLICY')) {
        $termFailures += "$($e.id): Windows Security audit depth must be marked policy dependent"
    }
    # AzureDiagnostics must never be presented as the only possible table when the mode says otherwise.
    $tableModes = @($e.log_analytics_tables.mode | Select-Object -Unique)
    switch ($e.log_analytics_mode) {
        'Resource-specific' { if ($tableModes -contains 'AzureDiagnostics') { $termFailures += "$($e.id): Resource-specific mode lists AzureDiagnostics" } }
        'AzureDiagnostics'  { if ($tableModes | Where-Object { $_ -ne 'AzureDiagnostics' }) { $termFailures += "$($e.id): AzureDiagnostics mode lists other tables" } }
    }
}
$resLogs = $entryById['azure-resource-logs']
if ($resLogs -and $resLogs.log_analytics_mode -ne 'AzureDiagnostics or resource-specific') {
    $termFailures += 'azure-resource-logs: must acknowledge both AzureDiagnostics and resource-specific tables'
}
Add-CheckResult -Name 'Terminology rules' -Failures $termFailures

$apiFailures = @()
foreach ($e in $entries) {
    # A collection configuration is inspected, not acquired; everything else needs a command that acquires evidence.
    $primaryRole = if ($e.evidence_type -eq 'Collection configuration') { 'Inspects configuration' } else { 'Acquires evidence' }
    $primary = @($e.powershell.commands | Where-Object role -eq $primaryRole)
    if ($e.powershell.supported -and $primary.Count -eq 0) { $apiFailures += "$($e.id): PowerShell marked supported but no '$primaryRole' command" }
    if (-not $e.powershell.supported -and @($e.powershell.commands).Count) { $apiFailures += "$($e.id): PowerShell marked unsupported but commands are listed" }
    $current = @($primary | Where-Object api_status -notin 'Retiring', 'Retired')
    if ($primary.Count -gt 0 -and $current.Count -eq 0) { $apiFailures += "$($e.id): only retiring or retired interfaces are offered" }
}
Add-CheckResult -Name 'Acquisition methods present and current' -Failures $apiFailures

# ---------------------------------------------------------------- 5. sensitive data scan
$sensitive = @(
    @{ Name = 'GUID';                Pattern = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' },
    @{ Name = 'email address';       Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' },
    @{ Name = 'storage account key'; Pattern = '(?i)AccountKey=' },
    @{ Name = 'SAS signature';       Pattern = '(?i)[?&]sig=' },
    @{ Name = 'secret assignment';   Pattern = '(?i)(client_?secret|password)\s*[:=]\s*\S' }
)
$secretFailures = foreach ($key in $files.Keys) {
    foreach ($rule in $sensitive) {
        foreach ($m in [regex]::Matches($raw[$key], $rule.Pattern)) { "$($files[$key].Path): possible $($rule.Name) '$($m.Value)'" }
    }
}
Add-CheckResult -Name 'No credentials, tenant identifiers, or personal data' -Failures $secretFailures

# ---------------------------------------------------------------- 6. warnings
$today = [datetime]::UtcNow.Date
$staleFailures = foreach ($e in $entries) {
    $d = [datetime]::ParseExact($e.verification.last_verified, 'yyyy-MM-dd', $null)
    if ($d -gt $today) { "$($e.id): last_verified is in the future" }
    elseif (($today - $d).TotalDays -gt $StaleAfterDays) { "$($e.id): last verified $($e.verification.last_verified), older than $StaleAfterDays days" }
}
Add-CheckResult -Name 'Verification freshness' -Failures $staleFailures -Severity Warning

$used = [System.Collections.Generic.HashSet[string]]::new()
foreach ($e in $entries)   { foreach ($i in (Get-EntrySourceIds $e)) { [void]$used.Add($i) } }
foreach ($p in $products)  { [void]$used.Add($p.what_is_source_id) }
foreach ($r in $relations) { foreach ($i in @($r.source_ids)) { [void]$used.Add($i) } }
Add-CheckResult -Name 'Unused sources' -Severity Warning -Failures @(
    $sources | Where-Object { -not $used.Contains($_.id) } | ForEach-Object { "$($_.id) is not referenced" })
Add-CheckResult -Name 'Products without entries' -Severity Warning -Failures @(
    $products | Where-Object { $_.id -notin $entries.product_id } | ForEach-Object { "$($_.id) has no catalog entry" })
$linkOnly = @($sources | Where-Object verification_method -eq 'Linked from verified page')
Add-CheckResult -Name 'Link-only sources awaiting link check' -Severity Warning -Failures @(
    $linkOnly | ForEach-Object { "$($_.id) ($($_.url))" })

# ---------------------------------------------------------------- 7. report
function Format-Cell { param([string] $Text) ($Text -replace '\|', '\|' -replace "`r?`n", ' ') }
function Yes { param([bool] $Value) if ($Value) { 'Yes' } else { '-' } }

$statusOrder = @('Verified', 'Conditional', 'Verification required', 'Deprecated or replaced')
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Validation report')
[void]$sb.AppendLine()
[void]$sb.AppendLine('Generated by `scripts/validate-catalog.ps1` from the data files. Do not edit by hand.')
[void]$sb.AppendLine()
[void]$sb.AppendLine("- Catalog: $($data.catalog.catalog_phase) (schema $($data.catalog.schema_version))")
[void]$sb.AppendLine("- Generated (UTC): $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm'))")
[void]$sb.AppendLine("- Entries: $($entries.Count) | Products: $($products.Count) | Sources: $($sources.Count) | Relationships: $($relations.Count)")
[void]$sb.AppendLine("- Result: **$(if ($errors.Count) { 'FAIL' } else { 'PASS' })** with $($errors.Count) error(s) and $($warnings.Count) warning(s)")
[void]$sb.AppendLine()

[void]$sb.AppendLine('## Status summary')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Status | Entries | Core | Extended | Specialized |')
[void]$sb.AppendLine('|---|---:|---:|---:|---:|')
foreach ($s in $statusOrder) {
    $in = @($entries | Where-Object { $_.verification.status -eq $s })
    [void]$sb.AppendLine("| $s | $($in.Count) | $(@($in | Where-Object priority -eq 'Core').Count) | $(@($in | Where-Object priority -eq 'Extended').Count) | $(@($in | Where-Object priority -eq 'Specialized').Count) |")
}
[void]$sb.AppendLine()

[void]$sb.AppendLine('## Entries')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Evidence source | Product | Plane | Priority | Status | Poster 1 | Poster 2 | Site | Open gaps |')
[void]$sb.AppendLine('|---|---|---|---|---|:-:|:-:|:-:|---:|')
foreach ($e in ($entries | Sort-Object { [array]::IndexOf($statusOrder, $_.verification.status) }, priority, id)) {
    $prod = if ($productById[$e.product_id]) { $productById[$e.product_id].short_name } else { $e.product_id }
    [void]$sb.AppendLine("| ``$($e.id)`` $(Format-Cell $e.evidence_source) | $prod | $($e.evidence_plane) | $($e.priority) | $($e.verification.status) | $(Yes $e.publication.poster_1) | $(Yes $e.publication.poster_2) | $(Yes $e.publication.site) | $(@($e.verification.gaps).Count) |")
}
[void]$sb.AppendLine()

[void]$sb.AppendLine('## Documentation gaps (verification backlog)')
[void]$sb.AppendLine()
foreach ($e in ($entries | Where-Object { @($_.verification.gaps).Count } | Sort-Object priority, id)) {
    [void]$sb.AppendLine("### $($e.id)")
    foreach ($g in $e.verification.gaps) { [void]$sb.AppendLine("- $g") }
    [void]$sb.AppendLine()
}

$deprecated = @($entries | Where-Object { $_.verification.status -eq 'Deprecated or replaced' })
$retiringApis = @($entries | ForEach-Object {
        $e = $_
        $e.powershell.commands | Where-Object api_status -in 'Beta', 'Preview', 'Retiring', 'Retired' |
            ForEach-Object { "``$($e.id)``: $($_.command) ($($_.api_status))" }
        if ($e.api.status -in 'Beta', 'Preview', 'Retiring', 'Retired') { "``$($e.id)``: $($e.api.name) ($($e.api.status))" }
    })
[void]$sb.AppendLine('## Deprecated, preview, and beta interfaces')
[void]$sb.AppendLine()
foreach ($e in $deprecated) { [void]$sb.AppendLine("- ``$($e.id)`` is deprecated or replaced; use ``$($e.replaced_by)``.") }
foreach ($line in $retiringApis) { [void]$sb.AppendLine("- $line") }
if (-not ($deprecated.Count + $retiringApis.Count)) { [void]$sb.AppendLine('- None.') }
[void]$sb.AppendLine()

[void]$sb.AppendLine('## Sources by verification method')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Method | Count |')
[void]$sb.AppendLine('|---|---:|')
foreach ($g in ($sources | Group-Object verification_method | Sort-Object Name)) { [void]$sb.AppendLine("| $($g.Name) | $($g.Count) |") }
[void]$sb.AppendLine()

[void]$sb.AppendLine('## Checks')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Check | Severity | Result | Findings |')
[void]$sb.AppendLine('|---|---|---|---:|')
foreach ($c in $checks) { [void]$sb.AppendLine("| $($c.Name) | $($c.Severity) | $($c.Result) | $($c.Count) |") }
[void]$sb.AppendLine()

if ($errors.Count)   { [void]$sb.AppendLine('## Errors'); [void]$sb.AppendLine(); foreach ($x in $errors)   { [void]$sb.AppendLine("- $(Format-Cell $x)") }; [void]$sb.AppendLine() }
if ($warnings.Count) { [void]$sb.AppendLine('## Warnings'); [void]$sb.AppendLine(); foreach ($x in $warnings) { [void]$sb.AppendLine("- $(Format-Cell $x)") }; [void]$sb.AppendLine() }

$reportDir = Split-Path -Parent $ReportPath
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
Set-Content -LiteralPath $ReportPath -Value $sb.ToString() -Encoding utf8NoBOM

# ---------------------------------------------------------------- console summary
foreach ($c in $checks) { '{0,-5} {1}' -f $c.Result, $c.Name | Write-Host }
foreach ($x in $errors)   { Write-Host "ERROR   $x" -ForegroundColor Red }
foreach ($x in $warnings) { Write-Host "WARNING $x" -ForegroundColor Yellow }
Write-Host ("{0} entries, {1} error(s), {2} warning(s). Report: {3}" -f $entries.Count, $errors.Count, $warnings.Count, $ReportPath)
exit ([int]($errors.Count -gt 0))
