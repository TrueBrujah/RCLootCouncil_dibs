#requires -Version 5.1
<#
.SYNOPSIS
Check the TOC/XML load graph and required calendar assets before deployment.
#>
[CmdletBinding()]
param([string]$SourcePath = (Join-Path $PSScriptRoot '../src'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath $SourcePath).Path.TrimEnd([char[]]'\/')
$rootPrefix = $sourceRoot + [IO.Path]::DirectorySeparatorChar
$visited = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Test-LoadFile([string]$Parent, [string]$Reference) {
    if ([IO.Path]::IsPathRooted($Reference)) { throw "Rooted load path is forbidden: $Reference" }
    $relative = $Reference.Replace('\', [IO.Path]::DirectorySeparatorChar).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $Parent $relative))
    if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Load path escapes the addon: $Reference"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required addon file missing: $path"
    }
    if (-not $visited.Add($path)) { return }
    if ([IO.Path]::GetExtension($path) -ieq '.xml') {
        [xml]$xml = [IO.File]::ReadAllText($path)
        foreach ($entry in $xml.SelectNodes('//*[local-name()="Script" or local-name()="Include"][@file]')) {
            Test-LoadFile (Split-Path $path -Parent) $entry.GetAttribute('file')
        }
    }
}

$tocPath = Join-Path $sourceRoot 'RCLootCouncil_dibs.toc'
Test-LoadFile $sourceRoot 'RCLootCouncil_dibs.toc'
foreach ($line in [IO.File]::ReadAllLines($tocPath)) {
    $reference = $line.Trim()
    if ($reference -and -not $reference.StartsWith('#')) { Test-LoadFile $sourceRoot $reference }
}
# These assets/notices are referenced inside vendor code, rather than TOC/XML.
foreach ($asset in @(
    'libs/LibAceGUIWidgets/LibAceGUIWidgets-1.0.lua',
    'libs/LibAceGUIWidgets/LibAceGUIWidgets-DatePicker.lua',
    'libs/LibAceGUIWidgets/LICENSE',
    'libs/LibAceGUIWidgets/Fonts/DejaVuSans.ttf',
    'libs/LibAceGUIWidgets/Fonts/LICENSE-DejaVu.txt',
    'libs/LibAceGUIWidgets/Textures/calendar.tga',
    'libs/LibAceGUIWidgets/Textures/copy.tga'
)) { Test-LoadFile $sourceRoot $asset }

Write-Output ('Addon load files and calendar assets verified: {0} files.' -f $visited.Count)
