#Requires -Version 7.4
<#
.SYNOPSIS
    Checks that every URL in data/sources.json resolves on Microsoft Learn and still matches its recorded title.

.DESCRIPTION
    For each source: GET the URL (following redirects), record the HTTP status and final URL, and compare
    the page <title> with the recorded title. Writes reports/link-check.md.

    Errors (exit 1): HTTP 4xx/5xx, or a redirect off learn.microsoft.com.
    Warnings: a redirect to a different path (update the canonical URL), or a title that no longer matches
    (the page may have changed scope). 'Linked from verified page' sources are listed separately because
    this check is what confirms them.

.EXAMPLE
    pwsh ./scripts/check-links.ps1
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $ReportPath,
    [int] $DelayMilliseconds = 500,
    [int] $MaxRetries = 3
)

$ErrorActionPreference = 'Stop'
if (-not $ReportPath) { $ReportPath = Join-Path $RepoRoot 'reports/link-check.md' }

$sources = (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'data/sources.json') | ConvertFrom-Json -Depth 16).sources

function Get-Normalized {
    param([string] $Text)
    $t = [System.Net.WebUtility]::HtmlDecode($Text)
    $t = $t -replace '\s*\|\s*Microsoft Learn\s*$', ''
    $t = $t -replace '\s*-\s*[^-]+$', ''          # Learn appends " - <docset>" to many titles
    $t = $t -replace '\(.*?\)', ''                # recorded titles may carry a qualifier in parentheses
    ($t -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

$results = foreach ($s in $sources) {
    $attempt = 0
    $result = $null
    while (-not $result) {
        $attempt++
        try {
            $resp = Invoke-WebRequest -Uri $s.url -Method Get -MaximumRedirection 10 -SkipHttpErrorCheck `
                -UserAgent 'microsoft-cloud-audit-logs-guide-link-check' -TimeoutSec 60
            if ($resp.StatusCode -eq 429 -and $attempt -lt $MaxRetries) { Start-Sleep -Seconds (5 * $attempt); continue }
            $final = $resp.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
            $title = if ($resp.Content -match '(?is)<title>(.*?)</title>') { $Matches[1].Trim() } else { '' }
            $result = [pscustomobject]@{ Source = $s; Status = [int]$resp.StatusCode; FinalUrl = $final; PageTitle = $title; Failure = $null }
        }
        catch {
            if ($attempt -lt $MaxRetries) { Start-Sleep -Seconds (2 * $attempt); continue }
            $result = [pscustomobject]@{ Source = $s; Status = 0; FinalUrl = $null; PageTitle = ''; Failure = $_.Exception.Message }
        }
    }
    Start-Sleep -Milliseconds $DelayMilliseconds
    $result
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
foreach ($r in $results) {
    $id = $r.Source.id
    if ($r.Failure) { $errors.Add("${id}: request failed: $($r.Failure)"); continue }
    if ($r.Status -ge 400) { $errors.Add("${id}: HTTP $($r.Status) for $($r.Source.url)"); continue }
    $finalUri = [uri]$r.FinalUrl
    if ($finalUri.Host -ne 'learn.microsoft.com') { $errors.Add("${id}: redirected off Microsoft Learn to $($r.FinalUrl)"); continue }
    $recordedPath = ([uri]$r.Source.url).AbsolutePath.TrimEnd('/')
    $finalPath = ($finalUri.AbsolutePath -replace '^/[a-z]{2}-[a-z]{2}/', '/').TrimEnd('/')
    if ($finalPath -ne $recordedPath) { $warnings.Add("${id}: redirects to $($r.FinalUrl); update the recorded URL") }
    $want = Get-Normalized $r.Source.title
    $got = Get-Normalized $r.PageTitle
    if ($want -and $got -and -not ($got.Contains($want) -or $want.Contains($got))) {
        $warnings.Add("${id}: page title '$($r.PageTitle)' differs from recorded '$($r.Source.title)'")
    }
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Link check')
[void]$sb.AppendLine()
[void]$sb.AppendLine("Generated (UTC): $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm')). Sources checked: $($results.Count). Errors: $($errors.Count). Warnings: $($warnings.Count).")
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Source | Method | HTTP | Final URL |')
[void]$sb.AppendLine('|---|---|---:|---|')
foreach ($r in $results) {
    [void]$sb.AppendLine("| ``$($r.Source.id)`` | $($r.Source.verification_method) | $($r.Status) | $($r.FinalUrl) |")
}
[void]$sb.AppendLine()
if ($errors.Count)   { [void]$sb.AppendLine('## Errors');   foreach ($x in $errors)   { [void]$sb.AppendLine("- $x") }; [void]$sb.AppendLine() }
if ($warnings.Count) { [void]$sb.AppendLine('## Warnings'); foreach ($x in $warnings) { [void]$sb.AppendLine("- $x") }; [void]$sb.AppendLine() }
Set-Content -LiteralPath $ReportPath -Value $sb.ToString() -Encoding utf8NoBOM

foreach ($x in $errors)   { Write-Host "ERROR   $x" -ForegroundColor Red }
foreach ($x in $warnings) { Write-Host "WARNING $x" -ForegroundColor Yellow }
Write-Host "Checked $($results.Count) sources: $($errors.Count) error(s), $($warnings.Count) warning(s). Report: $ReportPath"
exit ([int]($errors.Count -gt 0))
