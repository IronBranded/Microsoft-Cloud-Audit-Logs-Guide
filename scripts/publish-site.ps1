#Requires -Version 7.4
<#
.SYNOPSIS
    Publishes the interactive site to the gh-pages branch for GitHub Pages ("Deploy from a branch").

.DESCRIPTION
    No GitHub Actions involved. The script:
      1. validates the catalog (scripts/validate-catalog.ps1)
      2. rebuilds the site data (scripts/build-site.ps1)
      3. stops if site/ has changes that are not committed, because only committed content is published
      4. splits the site/ folder of the source branch into its own commit history (git subtree split)
      5. force-pushes that history to the gh-pages branch, so the site's index.html sits at the branch root

    One-time GitHub setting: Settings > Pages > Build and deployment > Source: Deploy from a branch,
    Branch: gh-pages, folder: / (root).

.EXAMPLE
    pwsh ./scripts/publish-site.ps1
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [string]$SourceBranch = 'main',
    [string]$PagesBranch = 'gh-pages'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $inside = git rev-parse --is-inside-work-tree 2>$null
    if ($inside -ne 'true') {
        throw "$repoRoot is not a Git repository. Clone the GitHub repository, or run 'git init' and 'git remote add origin <url>' in this folder, then commit before publishing."
    }
    if (-not (git remote get-url $Remote 2>$null)) { throw "This repository has no remote named '$Remote'." }

    & (Join-Path $PSScriptRoot 'validate-catalog.ps1')
    if ($LASTEXITCODE) { throw 'Catalog validation failed. Fix the errors in reports/validation-report.md first.' }

    & (Join-Path $PSScriptRoot 'build-site.ps1')

    $pending = git status --porcelain -- site
    if ($pending) {
        $pending | ForEach-Object { Write-Host "  $_" }
        throw "site/ has uncommitted changes. Commit them to $SourceBranch, then run this script again."
    }
    $branch = git rev-parse --abbrev-ref HEAD
    if ($branch -ne $SourceBranch) { Write-Warning "You are on '$branch'; publishing the committed site/ from '$SourceBranch'." }

    $commit = [string](git subtree split --prefix site $SourceBranch | Select-Object -Last 1)
    $commit = $commit.Trim()
    if ($LASTEXITCODE -or $commit -notmatch '^[0-9a-f]{40}$') { throw "git subtree split failed. Is site/ committed on '$SourceBranch'?" }

    git push $Remote "${commit}:refs/heads/$PagesBranch" --force
    if ($LASTEXITCODE) { throw "Push to $Remote/$PagesBranch failed." }
    Write-Host "Published site/ from $SourceBranch ($($commit.Substring(0, 7))) to $Remote/$PagesBranch."
}
finally {
    Pop-Location
}
