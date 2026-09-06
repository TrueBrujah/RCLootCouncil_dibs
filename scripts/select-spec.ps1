#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Spec
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$featureDir = Join-Path $repoRoot (Join-Path 'specs' $Spec)
$featureFile = Join-Path $repoRoot '.specify/feature.json'

if (-not (Test-Path -LiteralPath $featureDir -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: Unknown spec directory: specs/$Spec")
    exit 1
}

if (-not (Test-Path -LiteralPath (Split-Path $featureFile -Parent) -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: Missing .specify directory in repository root")
    exit 1
}

$content = "{`n  `"feature_directory`": `"specs/$Spec`"`n}`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($featureFile, $content, $utf8NoBom)

$branch = (git -C $repoRoot branch --show-current)
Write-Output "Active Spec-Kit feature set to specs/$Spec"
Write-Output "Current git branch unchanged: $branch"
