$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$validationScript = Join-Path $repositoryRoot 'scripts/Test-DibsAddonFiles.ps1'

function Add-LoadFixture([string]$Relative, [string]$Content = '-- fixture') {
    $path = Join-Path $script:loadFixture $Relative
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    [IO.File]::WriteAllText($path, $Content)
    return $path
}

Describe 'Dibs packaged load files' {
    BeforeEach {
        $script:loadFixture = Join-Path ([IO.Path]::GetTempPath()) ('dibs-load-test-' + [guid]::NewGuid().ToString('N'))
        $null = Add-LoadFixture 'RCLootCouncil_dibs.toc' "## Version: test`nembeds.xml`nCore.lua`n"
        $null = Add-LoadFixture 'Core.lua'
        $null = Add-LoadFixture 'embeds.xml' '<Ui xmlns="http://www.blizzard.com/wow/ui/"><Include file="libs\nested.xml"/><Script file="libs\LibAceGUIWidgets\LibAceGUIWidgets-1.0.lua"/><Script file="libs\LibAceGUIWidgets\LibAceGUIWidgets-DatePicker.lua"/></Ui>'
        $null = Add-LoadFixture 'libs/nested.xml' '<Ui><Script file="nested.lua"/></Ui>'
        $null = Add-LoadFixture 'libs/nested.lua'
        foreach ($file in @('LibAceGUIWidgets-1.0.lua', 'LibAceGUIWidgets-DatePicker.lua', 'LICENSE', 'Fonts/DejaVuSans.ttf', 'Fonts/LICENSE-DejaVu.txt', 'Textures/calendar.tga', 'Textures/copy.tga')) {
            $null = Add-LoadFixture ('libs/LibAceGUIWidgets/' + $file)
        }
    }
    AfterEach {
        $safePrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\dibs-load-test-'
        if (-not [IO.Path]::GetFullPath($script:loadFixture).StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup' }
        Remove-Item -LiteralPath $script:loadFixture -Recurse -Force
    }
    It 'accepts a complete bundle with namespaced XML and nested includes' {
        (& $validationScript -SourcePath $script:loadFixture) | Should Match 'verified'
    }
    It 'rejects the missing calendar core reported by Retail' {
        $missing = Join-Path $script:loadFixture 'libs/LibAceGUIWidgets/LibAceGUIWidgets-1.0.lua'
        Remove-Item -LiteralPath $missing
        { & $validationScript -SourcePath $script:loadFixture } | Should Throw 'LibAceGUIWidgets-1.0.lua'
    }
    It 'rejects a missing DatePicker and a directory masquerading as its file' {
        $missing = Join-Path $script:loadFixture 'libs/LibAceGUIWidgets/LibAceGUIWidgets-DatePicker.lua'
        Remove-Item -LiteralPath $missing
        [void][IO.Directory]::CreateDirectory($missing)
        { & $validationScript -SourcePath $script:loadFixture } | Should Throw 'DatePicker.lua'
    }
    It 'resolves nested XML paths relative to the containing XML file' {
        Remove-Item -LiteralPath (Join-Path $script:loadFixture 'libs/nested.lua')
        { & $validationScript -SourcePath $script:loadFixture } | Should Throw 'nested.lua'
    }
    It 'rejects missing non-XML calendar assets and license notices' {
        Remove-Item -LiteralPath (Join-Path $script:loadFixture 'libs/LibAceGUIWidgets/Fonts/LICENSE-DejaVu.txt')
        { & $validationScript -SourcePath $script:loadFixture } | Should Throw 'LICENSE-DejaVu.txt'
    }
    It 'rejects paths escaping the addon directory' {
        $null = Add-LoadFixture 'embeds.xml' '<Ui><Script file="..\outside.lua"/></Ui>'
        { & $validationScript -SourcePath $script:loadFixture } | Should Throw 'escapes'
    }
    It 'does not recurse forever when XML includes repeat' {
        $null = Add-LoadFixture 'libs/nested.xml' '<Ui><Include file="..\embeds.xml"/><Script file="nested.lua"/></Ui>'
        (& $validationScript -SourcePath $script:loadFixture) | Should Match 'verified'
    }
    It 'keeps an installed addon intact when deployment preflight fails' {
        $fixtureScripts = Join-Path $script:loadFixture 'scripts'
        [void][IO.Directory]::CreateDirectory($fixtureScripts)
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/deploy.ps1') -Destination $fixtureScripts
        Copy-Item -LiteralPath $validationScript -Destination $fixtureScripts
        $null = Add-LoadFixture 'src/RCLootCouncil_dibs.toc' "## Version: test`nmissing.lua"
        $sentinel = Add-LoadFixture 'installed/keep.txt' 'existing installation'
        { & (Join-Path $fixtureScripts 'deploy.ps1') -TargetPath (Split-Path $sentinel -Parent) } | Should Throw 'missing.lua'
        [IO.File]::ReadAllText($sentinel) | Should Be 'existing installation'
    }
    It 'accepts the real source bundle after the approved restoration' {
        (& $validationScript -SourcePath (Join-Path $repositoryRoot 'src')) | Should Match 'verified'
    }
    It 'preserves all seven approved vendor files byte for byte' {
        $record = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'docs/developer/libaceguiwidgets-vendoring.md'))
        $rows = [regex]::Matches($record, '(?m)^\|\s*`([^`]+)`\s*\|\s*`[0-9a-f]{64}`\s*\|\s*`([0-9a-f]{64})`\s*\|')
        $rows.Count | Should Be 7
        foreach ($row in $rows) {
            $file = Join-Path (Join-Path $repositoryRoot 'src/libs/LibAceGUIWidgets') $row.Groups[1].Value
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() | Should Be $row.Groups[2].Value
        }
    }
}
