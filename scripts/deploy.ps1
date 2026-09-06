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
robocopy $sourcePath $TargetPath /MIR /FP /NDL /NJH /NJS /NP
$exitCode = $LASTEXITCODE

# Robocopy exit codes 0-7 indicate success (bit flags for copied/extra/mismatched files)
if ($exitCode -ge 8) {
    [Console]::Error.WriteLine("ERROR: robocopy failed with exit code $exitCode")
    exit $exitCode
}

Write-Output "Deployed src/ -> $TargetPath"
