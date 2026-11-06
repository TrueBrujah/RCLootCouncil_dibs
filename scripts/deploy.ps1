#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Mirrors src/ into the local WoW AddOns folder for RCLootCouncil_dibs.
.PARAMETER TargetPath
  Destination AddOns folder. Defaults to the known Retail install path.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$TargetPath = "E:\Games\World of Warcraft\_retail_\Interface\AddOns\RCLootCouncil_dibs"
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourcePath = Join-Path $repoRoot 'src'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: Missing source directory: $sourcePath")
    exit 1
}

New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

Write-Output "Syncing files: $sourcePath -> $TargetPath"
Write-Output "Files to copy:"
$preview = robocopy $sourcePath $TargetPath /MIR /L /FP /NDL /NJH /NJS /NP
if ($preview) {
    $preview | ForEach-Object { Write-Output ("  " + $_) }
} else {
    Write-Output "  (none - destination is already synchronized)"
}
$null = robocopy $sourcePath $TargetPath /MIR /FP /NDL /NJH /NJS /NP
$exitCode = $LASTEXITCODE

# Robocopy exit codes 0-7 indicate success (bit flags for copied/extra/mismatched files)
if ($exitCode -ge 8) {
    [Console]::Error.WriteLine("ERROR: robocopy failed with exit code $exitCode")
    exit $exitCode
}

$commit = git -C $repoRoot rev-parse --short=12 HEAD
if ($LASTEXITCODE -ne 0 -or -not $commit) {
    [Console]::Error.WriteLine("ERROR: Could not identify the current Git commit.")
    exit 1
}
$sourceChanges = git -C $repoRoot status --porcelain --untracked-files=all -- src
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("ERROR: Could not inspect source worktree state.")
    exit 1
}
$worktreeState = if ($sourceChanges) { 'dirty' } else { 'clean' }
$buildId = "$commit-$worktreeState"
$tocPath = Join-Path $TargetPath 'RCLootCouncil_dibs.toc'
if (-not (Test-Path -LiteralPath $tocPath -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: Deployed TOC file is missing: $tocPath")
    exit 1
}
$tocContent = [System.IO.File]::ReadAllText($tocPath)
$buildMetadata = "## X-Dibs-Build: $buildId"
if ($tocContent -match '(?m)^## X-Dibs-Build:') {
    $tocContent = [regex]::Replace($tocContent, '(?m)^## X-Dibs-Build:.*$', $buildMetadata)
} else {
    $tocContent = $tocContent.TrimEnd() + "`r`n$buildMetadata`r`n"
}
[System.IO.File]::WriteAllText($tocPath, $tocContent, [System.Text.UTF8Encoding]::new($false))
Write-Output "Deployed src/ -> $TargetPath"
Write-Output "Stamped in-game build ID: $buildId"
