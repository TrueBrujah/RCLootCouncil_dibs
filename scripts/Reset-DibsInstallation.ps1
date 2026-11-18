#requires -Version 5.1
<#
.SYNOPSIS
Preview or remove the Dibs installation and SavedVariables from one WoW Retail.
.DESCRIPTION
Preview only by default. -Apply requires WoW to be closed, copies and verifies
every affected file outside WoW, then removes only the Dibs addon directory and
its exact SavedVariables filenames at account and character scope. Other addons,
shared WoW settings and remote guild data are not reset. Reparse points are refused.
.EXAMPLE
.\scripts\Reset-DibsInstallation.ps1
.EXAMPLE
.\scripts\Reset-DibsInstallation.ps1 -Apply
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WowRoot = 'E:\Games\World of Warcraft\_retail_',
    [string]$BackupRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'RCLootCouncil_dibs\CleanupBackups'),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "An absolute path is required: $Path" }
    return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
}

function Assert-PlainPath([string]$Path) {
    $cursor = Get-NormalPath $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a symbolic link or junction: $cursor"
            }
        }
        $parent = Split-Path -Path $cursor -Parent
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Assert-InRoot([string]$Path, [string]$Root) {
    $normal = Get-NormalPath $Path
    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    if (-not $normal.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target escapes the intended directory: $normal"
    }
    Assert-PlainPath $normal
}

function Get-PlainDirectories([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    Assert-PlainPath $Path
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Directory -Force)) {
        Assert-PlainPath $item.FullName
        $item
    }
}

function Get-AddonFiles([string]$Path) {
    Assert-InRoot $Path $retailRoot
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force)) {
        Assert-InRoot $item.FullName $retailRoot
        if ($item.PSIsContainer) { Get-AddonFiles $item.FullName }
        else { $item.FullName }
    }
}

function Assert-WowClosed {
    $processes = @(Get-Process -Name Wow, WowB, WowT, WoWClassic -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) { throw 'Close World of Warcraft completely before using -Apply. Nothing has been deleted.' }
}

$retailRoot = Get-NormalPath $WowRoot
Assert-PlainPath $retailRoot
if ((Split-Path $retailRoot -Leaf) -ine '_retail_' -or
    -not (Test-Path -LiteralPath (Join-Path $retailRoot 'Wow.exe') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $retailRoot 'Interface\AddOns') -PathType Container)) {
    throw 'WowRoot must be an existing _retail_ directory containing Wow.exe and Interface\AddOns.'
}

$addonPath = Join-Path $retailRoot 'Interface\AddOns\RCLootCouncil_dibs'
Assert-InRoot $addonPath $retailRoot
$addonExists = Test-Path -LiteralPath $addonPath
if ($addonExists -and -not (Test-Path -LiteralPath $addonPath -PathType Container)) {
    throw 'The Dibs addon path is not a directory.'
}
$targets = @()
if ($addonExists) { $targets += @(Get-AddonFiles $addonPath) }
$accountRoot = Join-Path $retailRoot 'WTF\Account'
Assert-InRoot $accountRoot $retailRoot
foreach ($account in @(Get-PlainDirectories $accountRoot)) {
    $savedDirectories = @((Join-Path $account.FullName 'SavedVariables'))
    foreach ($realm in @(Get-PlainDirectories $account.FullName)) {
        if ($realm.Name -ieq 'SavedVariables') { continue }
        foreach ($character in @(Get-PlainDirectories $realm.FullName)) {
            $savedDirectories += Join-Path $character.FullName 'SavedVariables'
        }
    }
    foreach ($directory in $savedDirectories) {
        foreach ($name in @('RCLootCouncil_dibs.lua', 'RCLootCouncil_dibs.lua.bak')) {
            $path = Join-Path $directory $name
            Assert-InRoot $path $retailRoot
            if (Test-Path -LiteralPath $path) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected a file: $path" }
                $targets += $path
            }
        }
    }
}
$targets = @($targets | Sort-Object -Unique)
Write-Output "Retail: $retailRoot"
Write-Output 'Scope: Dibs addon and Dibs saved data for ALL accounts/characters in this Retail.'
if ($addonExists) { Write-Output "Addon directory: $addonPath" }
foreach ($path in $targets) { Write-Output ('  ' + $path.Substring($retailRoot.Length + 1)) }
if (-not $addonExists -and $targets.Count -eq 0) {
    Write-Output 'No Dibs installation or SavedVariables found. Nothing to remove.'
    return
}
if (-not $Apply) {
    Write-Output 'PREVIEW ONLY: no files changed. Close WoW, then run again with -Apply to back up and remove these targets.'
    return
}
Assert-WowClosed
if (-not $PSCmdlet.ShouldProcess($retailRoot, 'Back up and remove Dibs addon and ALL local Dibs saved data')) { return }

$backupBase = Get-NormalPath $BackupRoot
$gameRoot = Get-NormalPath (Split-Path $retailRoot -Parent)
if ($backupBase.Equals($gameRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $backupBase.StartsWith($gameRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BackupRoot must be outside the World of Warcraft installation.'
}
Assert-PlainPath $backupBase
$backupPath = Join-Path $backupBase ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($backupPath)
Assert-InRoot $backupPath $backupBase
$records = @()
foreach ($path in $targets) {
    Assert-InRoot $path $retailRoot
    $relative = $path.Substring($retailRoot.Length + 1)
    $destination = Join-Path $backupPath $relative
    Assert-InRoot $destination $backupPath
    [void][IO.Directory]::CreateDirectory((Split-Path $destination -Parent))
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Copy-Item -LiteralPath $path -Destination $destination -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -cne $hash) {
        throw 'Backup verification failed. Nothing has been deleted.'
    }
    $records += [pscustomobject]@{ relativePath = $relative; sha256 = $hash }
}
$manifest = [ordered]@{
    schema = 1; createdAt = (Get-Date).ToUniversalTime().ToString('o')
    wowRoot = $retailRoot; addonDirectoryExisted = [bool]$addonExists; files = @($records)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupPath 'manifest.json') -Encoding UTF8

# Recheck every source and the addon tree before the first deletion.
Assert-WowClosed
foreach ($record in $records) {
    $path = Join-Path $retailRoot $record.relativePath
    Assert-InRoot $path $retailRoot
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $record.sha256) {
        throw "A source changed while backing up. Nothing has been deleted. Backup: $backupPath"
    }
}
if ($addonExists) {
    $originalFiles = @($targets | Where-Object { $_.StartsWith($addonPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) })
    $currentFiles = @(Get-AddonFiles $addonPath)
    if (@(Compare-Object -ReferenceObject $originalFiles -DifferenceObject $currentFiles).Count -gt 0) {
        throw "The addon tree changed while backing up. Nothing has been deleted. Backup: $backupPath"
    }
}
Write-Output "Verified backup: $backupPath"
if ($addonExists) {
    Assert-InRoot $addonPath $retailRoot
    Remove-Item -LiteralPath $addonPath -Recurse -Force -ErrorAction Stop
}
foreach ($path in $targets) {
    if ($path.StartsWith($addonPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
    Assert-InRoot $path $retailRoot
    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
}
Write-Output 'Dibs removed locally. Other addons and shared WoW settings are unchanged.'
Write-Output 'To reinstall, run scripts\deploy.ps1. Guild sync can restore shared data after reinstalling.'
