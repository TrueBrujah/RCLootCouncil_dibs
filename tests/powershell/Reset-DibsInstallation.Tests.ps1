$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$resetScript = Join-Path $repositoryRoot 'scripts/Reset-DibsInstallation.ps1'

function Assert-TestFixturePath([string]$Path) {
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\dibs-cleanup-test-'
    if (-not [IO.Path]::GetFullPath($Path).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe test fixture path: $Path"
    }
}

function Write-CleanupFixtureFile([string]$Relative, [string]$Content = 'fixture') {
    $path = Join-Path $script:fixtureRoot $Relative
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    [IO.File]::WriteAllText($path, $Content)
    return $path
}

Describe 'Dibs offline installation cleanup' {
    BeforeEach {
        $script:fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('dibs-cleanup-test-' + [guid]::NewGuid().ToString('N'))
        $script:retail = Join-Path $script:fixtureRoot 'WoW\_retail_'
        $script:backups = Join-Path $script:fixtureRoot 'backups'
        $script:fixtureLinks = @()
        $null = Write-CleanupFixtureFile 'WoW\_retail_\Wow.exe'
        $script:addon = Write-CleanupFixtureFile 'WoW\_retail_\Interface\AddOns\RCLootCouncil_dibs\Core.lua' 'addon'
        $script:accountData = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\A\SavedVariables\RCLootCouncil_dibs.lua' 'guild data'
        $script:accountBak = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\A\SavedVariables\RCLootCouncil_dibs.lua.bak' 'guild backup'
        $script:characterData = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\A\Realm\Character\SavedVariables\RCLootCouncil_dibs.lua' 'local data'
        $script:secondAccount = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\B\SavedVariables\RCLootCouncil_dibs.lua' 'second account'
        $script:otherAddon = Write-CleanupFixtureFile 'WoW\_retail_\Interface\AddOns\RCLootCouncil\Core.lua' 'other addon'
        $script:otherData = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\A\SavedVariables\RCLootCouncil.lua' 'other data'
        $script:sharedConfig = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\A\Realm\Character\AddOns.txt' 'shared settings'
        $script:lookalike = Write-CleanupFixtureFile 'WoW\_retail_\WTF\Account\A\SavedVariables\RCLootCouncil_dibs.lua.old' 'keep this'
        Mock Get-Process { @() }
        Mock Copy-Item {
            param($LiteralPath, $Destination)
            [IO.File]::Copy($LiteralPath, $Destination, $false)
        }
    }

    AfterEach {
        foreach ($link in $script:fixtureLinks) {
            Assert-TestFixturePath $link
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
        Assert-TestFixturePath $script:fixtureRoot
        if (Test-Path -LiteralPath $script:fixtureRoot) {
            Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force
        }
    }

    It 'previews without changing files or making a backup' {
        $output = & $resetScript -WowRoot $script:retail -BackupRoot $script:backups
        ($output -join "`n") | Should Match 'PREVIEW ONLY'
        (Test-Path -LiteralPath $script:addon) | Should Be $true
        (Test-Path -LiteralPath $script:accountData) | Should Be $true
        (Test-Path -LiteralPath $script:backups) | Should Be $false
    }

    It 'backs up every selected file with a valid hash and removes only Dibs' {
        $null = & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply
        foreach ($path in @($script:addon, $script:accountData, $script:accountBak, $script:characterData, $script:secondAccount)) {
            (Test-Path -LiteralPath $path) | Should Be $false
        }
        foreach ($path in @($script:otherAddon, $script:otherData, $script:sharedConfig, $script:lookalike)) {
            (Test-Path -LiteralPath $path) | Should Be $true
        }
        $backup = @(Get-ChildItem -LiteralPath $script:backups -Directory)
        $backup.Count | Should Be 1
        $manifest = Get-Content -LiteralPath (Join-Path $backup[0].FullName 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.files.Count | Should Be 5
        foreach ($record in $manifest.files) {
            (Get-FileHash -LiteralPath (Join-Path $backup[0].FullName $record.relativePath) -Algorithm SHA256).Hash | Should Be $record.sha256
        }
        $secondRun = & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply
        ($secondRun -join "`n") | Should Match 'Nothing to remove'
        @(Get-ChildItem -LiteralPath $script:backups -Directory).Count | Should Be 1
    }

    It 'refuses an apply while WoW is running before touching data' {
        Mock Get-Process { [pscustomobject]@{ ProcessName = 'Wow'; Id = 123 } }
        { & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply } | Should Throw 'Close World of Warcraft'
        (Test-Path -LiteralPath $script:accountData) | Should Be $true
        (Test-Path -LiteralPath $script:backups) | Should Be $false
    }

    It 'supports WhatIf without creating backups or deleting anything' {
        $null = & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply -WhatIf
        (Test-Path -LiteralPath $script:addon) | Should Be $true
        (Test-Path -LiteralPath $script:backups) | Should Be $false
    }

    It 'refuses a non Retail root and an in-game backup destination' {
        { & $resetScript -WowRoot $script:fixtureRoot -Apply } | Should Throw 'WowRoot'
        { & $resetScript -WowRoot $script:retail -BackupRoot (Join-Path $script:retail 'backups') -Apply } | Should Throw 'outside'
        (Test-Path -LiteralPath $script:accountData) | Should Be $true
    }

    It 'does not delete any source when a backup copy fails' {
        Mock Copy-Item { throw 'Injected backup failure' }
        { & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply } | Should Throw 'Injected backup failure'
        (Test-Path -LiteralPath $script:addon) | Should Be $true
        (Test-Path -LiteralPath $script:accountData) | Should Be $true
    }

    It 'refuses junctions rather than traversing outside the addon' {
        $outsideFile = Write-CleanupFixtureFile 'outside\keep.lua' 'outside'
        $link = Join-Path (Split-Path $script:addon -Parent) 'escape'
        $null = New-Item -ItemType Junction -Path $link -Target (Split-Path $outsideFile -Parent)
        $script:fixtureLinks += $link
        { & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply } | Should Throw 'junction'
        (Test-Path -LiteralPath $outsideFile) | Should Be $true
        (Test-Path -LiteralPath $script:accountData) | Should Be $true
    }

    It 'can remove leftover SavedVariables even when the addon directory is absent' {
        $addonDirectory = Split-Path $script:addon -Parent
        Assert-TestFixturePath $addonDirectory
        Remove-Item -LiteralPath $addonDirectory -Recurse -Force
        $null = & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply
        (Test-Path -LiteralPath $script:characterData) | Should Be $false
        (Test-Path -LiteralPath $script:otherAddon) | Should Be $true
    }

    It 'can remove an empty addon directory' {
        Assert-TestFixturePath $script:addon
        Remove-Item -LiteralPath $script:addon -Force
        $null = & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply
        (Test-Path -LiteralPath (Split-Path $script:addon -Parent)) | Should Be $false
    }

    It 'copies and verifies real files in a separate fixture process without a Copy-Item mock' {
        $runner = Join-Path $script:fixtureRoot 'run-fixture.ps1'
        # Only the WoW process inventory is simulated in this isolated fixture.
        # The script's real Copy-Item, hashing and removal cmdlets execute here.
        $runnerText = @'
param($ResetScript, $Retail, $Backups)
$ErrorActionPreference = 'Stop'
function Get-Process { param($Name, $ErrorAction) @() }
& $ResetScript -WowRoot $Retail -BackupRoot $Backups -Apply
'@
        [IO.File]::WriteAllText($runner, $runnerText)
        $engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $null = & $engine -NoProfile -File $runner $resetScript $script:retail $script:backups
        $LASTEXITCODE | Should Be 0
        (Test-Path -LiteralPath $script:accountData) | Should Be $false
        (Test-Path -LiteralPath $script:otherAddon) | Should Be $true
        $manifestPath = @(Get-ChildItem -LiteralPath $script:backups -Filter manifest.json -Recurse)[0].FullName
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files.Count | Should Be 5
        foreach ($record in $manifest.files) {
            $backupFile = Join-Path (Split-Path $manifestPath -Parent) $record.relativePath
            (Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash | Should Be $record.sha256
        }
    }

    It 'refuses deletion when a source changes during backup' {
        Mock Copy-Item {
            param($LiteralPath, $Destination)
            [IO.File]::Copy($LiteralPath, $Destination, $false)
            [IO.File]::AppendAllText($LiteralPath, 'changed during backup')
        }
        { & $resetScript -WowRoot $script:retail -BackupRoot $script:backups -Apply } | Should Throw 'source changed'
        (Test-Path -LiteralPath $script:addon) | Should Be $true
        (Test-Path -LiteralPath $script:accountData) | Should Be $true
    }
}
