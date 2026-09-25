$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $repositoryRoot 'scripts/docs/DibsDocumentation.psm1') -Force
$script:FixtureRoots = @()

function New-DibsDocFixture {
  param(
    [string]$Id = 'fixture.sample',
    [string]$Since = '0.6.5',
    [string]$Audience = 'player',
    [string]$Scope = 'guild-season',
    [string]$HelpKey = 'UI_HELP_FIXTURE',
    [string]$HelpEnglish = 'A helpful explanation.',
    [string]$HelpFrench = 'Une explication utile.',
    [string]$LabelEnglish = 'Fixture concept',
    [string]$LabelFrench = 'Concept exemple',
    [string[]]$ExtraDocTags = @(),
    [switch]$OmitEnglishHelp,
    [switch]$OmitFrenchHelp,
    [switch]$UseAliasFields,
    [switch]$OrphanAnnotation
  )

  $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dibs-doc-test-" + [guid]::NewGuid().ToString('N'))
  $script:FixtureRoots += $root
  foreach ($directory in @('src/modules', 'src/locales')) {
    [void][System.IO.Directory]::CreateDirectory((Join-Path $root $directory))
  }
  [System.IO.File]::WriteAllText((Join-Path $root 'src/RCLootCouncil_dibs.toc'), "## Version: 0.6.5`n", [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $root 'src/modules/ProtectedActions.lua'), "local ACTIONS = {`n  [`"fixture.permission`"] = true,`n}`n", [System.Text.UTF8Encoding]::new($false))

  $helpTag = if ($UseAliasFields) { "---@doc.help $HelpKey" } else { "---@doc.help-key $HelpKey" }
  $reasonTag = if ($UseAliasFields) { '---@doc.reason_required false' } else { '---@doc.reason-required false' }
  $sourceLines = @(
    "---@doc.id $Id",
    '---@doc.category ledger',
    "---@doc.since $Since",
    "---@doc.audience $Audience",
    "---@doc.scope $Scope",
    '---@doc.audit false',
    $helpTag,
    '---@doc.label-key DOC_FIXTURE_LABEL',
    $reasonTag
  )
  $sourceLines += $ExtraDocTags
  if ($OrphanAnnotation) { $sourceLines += 'local unattached = true' } else { $sourceLines += 'function Fixture.Run()' }
  $sourceLines += 'end'
  [System.IO.File]::WriteAllLines((Join-Path $root 'src/modules/Fixture.lua'), $sourceLines, [System.Text.UTF8Encoding]::new($false))

  $english = @('local Dibs = _G.Dibs', 'Dibs.L = Dibs.L or {}', 'local L = Dibs.L')
  $french = @('local Dibs = _G.Dibs', 'Dibs.L = Dibs.L or {}', 'local L = Dibs.L')
  if (-not $OmitEnglishHelp) { $english += "L.$HelpKey = `"$HelpEnglish`"" }
  if (-not $OmitFrenchHelp) { $french += "L.$HelpKey = `"$HelpFrench`"" }
  $english += "L.DOC_FIXTURE_LABEL = `"$LabelEnglish`""
  $french += "L.DOC_FIXTURE_LABEL = `"$LabelFrench`""
  [System.IO.File]::WriteAllLines((Join-Path $root 'src/locales/enUS.lua'), $english, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllLines((Join-Path $root 'src/locales/frFR.lua'), $french, [System.Text.UTF8Encoding]::new($false))
  return $root
}

function Get-FixtureModel {
  param([string]$Root)
  return Get-DibsDocumentationModel -Root $Root
}

function Get-FixtureRules {
  param($Model, [string]$Rule)
  return ,@($Model.Findings | Where-Object { $_.Rule -eq $Rule })
}

Describe 'DIBS source-driven documentation foundation' {
  BeforeEach { $script:FixtureRoots = @() }
  AfterEach {
    foreach ($root in $script:FixtureRoots) {
      if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
  }

  It 'parses metadata and binds source file, line, module, and symbol' {
    $root = New-DibsDocFixture
    $model = Get-FixtureModel $root
    $model.Concepts.Count | Should Be 1
    $model.Concepts[0].id | Should Be 'fixture.sample'
    $model.Concepts[0].sourceFile | Should Be 'src/modules/Fixture.lua'
    $model.Concepts[0].sourceLine | Should Be 10
    $model.Concepts[0].module | Should Be 'Fixture'
    $model.Concepts[0].symbol | Should Be 'Fixture.Run'
  }

  It 'rejects duplicate IDs and reports both the concept and duplicate rule' {
    $root = New-DibsDocFixture
    $copy = @(
      '---@doc.id fixture.sample', '---@doc.category ledger', '---@doc.since 0.6.5',
      '---@doc.audience player', '---@doc.scope guild-season', '---@doc.audit false',
      '---@doc.help-key UI_HELP_FIXTURE', '---@doc.label-key DOC_FIXTURE_LABEL',
      'function Another.Run()', 'end'
    )
    [System.IO.File]::WriteAllLines((Join-Path $root 'src/modules/Another.lua'), $copy, [System.Text.UTF8Encoding]::new($false))
    $model = Get-FixtureModel $root
    (Get-FixtureRules $model 'duplicate-id').Count | Should Be 1
    (Get-DibsValidationSummary $model).Errors | Should Be 1
  }

  It 'rejects malformed semantic IDs' {
    $root = New-DibsDocFixture -Id 'Fixture.Sample'
    (Get-FixtureRules (Get-FixtureModel $root) 'invalid-doc-id').Count | Should Be 1
  }

  It 'rejects invalid lifecycle versions' {
    $root = New-DibsDocFixture -Since 'version-next'
    (Get-FixtureRules (Get-FixtureModel $root) 'invalid-version').Count | Should Be 1
  }

  It 'rejects an unknown help key' {
    $root = New-DibsDocFixture -HelpKey 'UI_HELP_NOT_DEFINED' -OmitEnglishHelp -OmitFrenchHelp
    (Get-FixtureRules (Get-FixtureModel $root) 'unknown-help-key').Count | Should Be 1
  }

  It 'reports a missing enUS value separately' {
    $root = New-DibsDocFixture -OmitEnglishHelp
    (Get-FixtureRules (Get-FixtureModel $root) 'missing-enUS').Count | Should Be 1
  }

  It 'reports a missing frFR value separately' {
    $root = New-DibsDocFixture -OmitFrenchHelp
    (Get-FixtureRules (Get-FixtureModel $root) 'missing-frFR').Count | Should Be 1
  }

  It 'filters Player documentation to Player-visible concepts' {
    $root = New-DibsDocFixture -Audience 'player'
    $model = Get-FixtureModel $root
    $outputs = New-DibsDocumentationOutputs $model
    $outputs['docs/generated/player-guide.md'] | Should Match 'fixture.sample'
    $outputs['docs/generated/officer-guide.md'] | Should Not Match 'fixture.sample'
  }

  It 'applies output-profile provenance policy without dropping normalized traceability' {
    $root = New-DibsDocFixture -Id 'sync.status' -Audience 'player,officer,gm'
    $model = Get-FixtureModel $root
    $concept = $model.Concepts[0]
    $concept.sourceFile | Should Be 'src/modules/Fixture.lua'
    $concept.sourceLine | Should Be 10
    $concept.symbol | Should Be 'Fixture.Run'

    $outputs = New-DibsDocumentationOutputs $model
    foreach ($path in @('docs/generated/player-guide.md', 'docs/generated/officer-guide.md', 'docs/generated/gm-guide.md')) {
      $outputs[$path] | Should Not Match 'Fixture.lua|Fixture.Run|Source:'
    }
    $outputs['docs/generated/player-guide.md'] | Should Match 'sync.status'
    $outputs['docs/generated/developer-reference.md'] | Should Match 'sync.status'
    $outputs['docs/generated/developer-reference.md'] | Should Match 'Fixture.lua'
    $outputs['docs/generated/developer-reference.md'] | Should Match 'Fixture.Run'
    $outputs['docs/generated/ui-reference.md'] | Should Match 'Fixture.lua'
    $outputs['docs/generated/ui-reference.md'] | Should Match 'Fixture.Run'
    $outputs['docs/generated/documentation.csv'] | Should Match 'src/modules/Fixture.lua'
    $outputs['docs/generated/documentation.csv'] | Should Match 'Fixture.Run'
    $outputs['docs/generated/documentation.json'] | Should Match 'src/modules/Fixture.lua'
    $outputs['docs/generated/documentation.json'] | Should Match 'Fixture.Run'
  }

  It 'includes operational concepts in Officer documentation' {
    $root = New-DibsDocFixture -Id 'ledger.adjust' -Audience 'officer,gm' -ExtraDocTags @('---@doc.permission fixture.permission')
    $model = Get-FixtureModel $root
    $outputs = New-DibsDocumentationOutputs $model
    $outputs['docs/generated/officer-guide.md'] | Should Match 'ledger.adjust'
    $outputs['docs/generated/officer-guide.md'] | Should Match 'fixture.permission'
  }

  It 'includes GM-facing setup concepts in GM documentation' {
    $root = New-DibsDocFixture -Id 'guild.setup' -Audience 'gm,developer'
    $outputs = New-DibsDocumentationOutputs (Get-FixtureModel $root)
    $outputs['docs/generated/gm-guide.md'] | Should Match 'guild.setup'
  }

  It 'excludes Developer-only concepts and protocol vocabulary from Player output' {
    $root = New-DibsDocFixture -Id 'sync.protocol.state' -Audience 'developer' -HelpEnglish 'V2_ENFORCED uses ledgerEpoch.'
    $model = Get-FixtureModel $root
    $outputs = New-DibsDocumentationOutputs $model
    $outputs['docs/generated/player-guide.md'] | Should Not Match 'sync.protocol.state|V2_ENFORCED|ledgerEpoch'
    $outputs['docs/generated/developer-reference.md'] | Should Match 'sync.protocol.state'
    (Get-FixtureRules $model 'developer-term-leak').Count | Should Be 0
  }

  It 'rejects Developer-only terms if attached to a Player audience' {
    $root = New-DibsDocFixture -Audience 'player,developer' -HelpEnglish 'V2_ENFORCED is a protocol state.'
    (Get-FixtureRules (Get-FixtureModel $root) 'developer-term-leak').Count | Should BeGreaterThan 0
  }

  It 'renders deterministic Markdown' {
    $root = New-DibsDocFixture
    $model = Get-FixtureModel $root
    (New-DibsDocumentationOutputs $model)['docs/generated/player-guide.md'] | Should Be (New-DibsDocumentationOutputs $model)['docs/generated/player-guide.md']
  }

  It 'renders deterministic CSV with the approved schema' {
    $root = New-DibsDocFixture
    $outputs = New-DibsDocumentationOutputs (Get-FixtureModel $root)
    $rows = @($outputs['docs/generated/documentation.csv'] | ConvertFrom-Csv)
    $rows.Count | Should Be 1
    $rows[0].Id | Should Be 'fixture.sample'
    $rows[0].SourceFile | Should Be 'src/modules/Fixture.lua'
    $outputs['docs/generated/documentation.csv'] | Should Be (New-DibsDocumentationOutputs (Get-FixtureModel $root))['docs/generated/documentation.csv']
  }

  It 'round-trips CSV commas, quotes, LF, CRLF, accents, and multiple multiline fields' {
    $root = New-DibsDocFixture
    $model = Get-FixtureModel $root
    $concept = $model.Concepts[0]
    $accented = 'Cafe ' + [char]233
    $concept.shortHelp.enUS = 'Simple field'
    $quote = [string][char]34
    $concept.shortHelp.frFR = $accented + ', quote ' + $quote + 'inside' + $quote + " and LF`nsecond line"
    $concept.label.enUS = 'Label, with comma and "quote"'
    $concept.label.frFR = "Premiere`r`nDeuxieme"
    $concept.reference.enUS = "Reference line one`nReference line two"
    $concept.reference.frFR = "Reference ligne un`r`nReference ligne deux`rfinal line"

    $first = New-DibsDocumentationOutputs $model
    $second = New-DibsDocumentationOutputs $model
    $first['docs/generated/documentation.csv'] | Should Be $second['docs/generated/documentation.csv']
    $rows = @($first['docs/generated/documentation.csv'] | ConvertFrom-Csv)
    $rows.Count | Should Be 1
    $rows[0].ShortHelpEN | Should Be 'Simple field'
    $rows[0].LabelEN | Should Be 'Label, with comma and "quote"'
    $rows[0].ShortHelpFR | Should Be ($accented + ', quote ' + $quote + 'inside' + $quote + " and LF`nsecond line")
    $rows[0].LabelFR | Should Be "Premiere`nDeuxieme"
    $rows[0].ReferenceEN | Should Be "Reference line one`nReference line two"
    $rows[0].ReferenceFR | Should Be "Reference ligne un`nReference ligne deux`nfinal line"
  }

  It 'renders structured deterministic JSON with arrays and booleans' {
    $root = New-DibsDocFixture -Audience 'player,officer'
    $outputs = New-DibsDocumentationOutputs (Get-FixtureModel $root)
    $json = ConvertFrom-Json $outputs['docs/generated/documentation.json']
    $json.concepts.Count | Should Be 1
    $json.concepts[0].audit | Should Be $false
    $json.concepts[0].audience.Count | Should Be 2
    $json.concepts[0].source.line | Should Be 10
    $json.concepts[0].lifecycle.removed | Should Be $null
    ($json.concepts[0].lifecycle.changed -is [array]) | Should Be $true
    $json.concepts[0].content.shortHelp.enUS | Should BeOfType ([string])
    $outputs['docs/generated/documentation.json'] | Should Be (New-DibsDocumentationOutputs (Get-FixtureModel $root))['docs/generated/documentation.json']
  }

  It 'warns when a localized label equals its short help' {
    $root = New-DibsDocFixture -LabelEnglish 'Same' -HelpEnglish 'Same' -LabelFrench 'Pareil' -HelpFrench 'Pareil'
    (Get-FixtureRules (Get-FixtureModel $root) 'label-equals-help').Count | Should Be 2
  }

  It 'parses optional fields and the approved help/reason tag aliases' {
    $root = New-DibsDocFixture -UseAliasFields -ExtraDocTags @('---@doc.changed 0.6.5', '---@doc.deprecated 0.6.5', '---@doc.removed 0.6.6', '---@doc.permission fixture.permission')
    $concept = (Get-FixtureModel $root).Concepts[0]
    $concept.helpKey | Should Be 'UI_HELP_FIXTURE'
    $concept.reasonRequired | Should Be $false
    $concept.changed.Count | Should Be 1
    $concept.deprecated | Should Be '0.6.5'
    $concept.removed | Should Be '0.6.6'
    $concept.permissions[0] | Should Be 'fixture.permission'
  }

  It 'rejects unknown permission and scope values' {
    $root = New-DibsDocFixture -Audience 'invalid-role' -Scope 'global-everywhere' -ExtraDocTags @('---@doc.permission fake.permission')
    $model = Get-FixtureModel $root
    (Get-FixtureRules $model 'invalid-permission').Count | Should Be 1
    (Get-FixtureRules $model 'invalid-scope').Count | Should Be 1
    (Get-FixtureRules $model 'invalid-audience').Count | Should Be 1
  }

  It 'reports annotations not attached to a Lua function' {
    $root = New-DibsDocFixture -OrphanAnnotation
    (Get-FixtureRules (Get-FixtureModel $root) 'orphan-annotation').Count | Should Be 1
  }

  It 'writes generated files identically on repeated generation' {
    $root = New-DibsDocFixture
    $model = Get-FixtureModel $root
    $outputs = New-DibsDocumentationOutputs $model
    Write-DibsDocumentationOutputs $outputs $root
    $first = @{}
    foreach ($path in $outputs.Keys) { $first[$path] = [System.IO.File]::ReadAllText((Join-Path $root $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)), [System.Text.Encoding]::UTF8) }
    Write-DibsDocumentationOutputs (New-DibsDocumentationOutputs $model) $root
    foreach ($path in $outputs.Keys) {
      $second = [System.IO.File]::ReadAllText((Join-Path $root $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)), [System.Text.Encoding]::UTF8)
      $second | Should Be $first[$path]
      $bytes = [System.IO.File]::ReadAllBytes((Join-Path $root $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
      ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) | Should Be $false
      ([System.Text.UTF8Encoding]::new($false, $true).GetString($bytes).Contains("`r")) | Should Be $false
    }
  }

  It 'validates the Phase 2 catalog, localized help, and orphan references' {
    $model = Get-DibsDocumentationModel -Root $repositoryRoot
    $summary = Get-DibsValidationSummary $model
    $model.Concepts.Count | Should Be 26
    @($model.Concepts | Select-Object -ExpandProperty id -Unique).Count | Should Be 26
    $summary.Errors | Should Be 0
    $summary.Warnings | Should Be 0
    foreach ($concept in $model.Concepts) {
      $concept.shortHelp.enUS | Should Not BeNullOrEmpty
      $concept.shortHelp.frFR | Should Not BeNullOrEmpty
      $concept.label.enUS | Should Not BeNullOrEmpty
      $concept.label.frFR | Should Not BeNullOrEmpty
    }
  }

  It 'keeps technical relay documentation out of Player output' {
    $model = Get-DibsDocumentationModel -Root $repositoryRoot
    $outputs = New-DibsDocumentationOutputs $model
    $outputs['docs/generated/player-guide.md'] | Should Match 'player.status'
    $outputs['docs/generated/player-guide.md'] | Should Not Match 'sync.raid.relay|sync.raid.reminder|UI_HELP_RAID_RELAY'
    $outputs['docs/generated/officer-guide.md'] | Should Match 'sync.raid.reminder'
    $outputs['docs/generated/developer-reference.md'] | Should Match 'sync.raid.relay'
  }

  It 'records an explicit disposition for each Phase 2 matrix gap' {
    $matrixPath = Join-Path $repositoryRoot 'docs/audits/UI_Help_Documentation_Matrix.md'
    $matrixText = [System.IO.File]::ReadAllText($matrixPath)
    $matrixRows = @($matrixText.Split([string[]]@('## Canonical Terminology Inventory'), [System.StringSplitOptions]::None)[0] -split "`r?`n")
    $expected = [ordered]@{
      'Player RCLootCouncil status' = 'ADD_DOC_CONCEPT'
      'Officer review requests' = 'ADD_HELP'
      'RCLootCouncil historical reconciliation' = 'ADD_HELP'
      'Announcements' = 'ADD_HELP'
      'Player raid readiness' = 'ADD_DOC_CONCEPT'
      'Ledger and audit history columns' = 'ADD_HELP'
      'Raid Relay' = 'ADD_HELP'
    }
    foreach ($entry in $expected.GetEnumerator()) {
      $row = @($matrixRows | Where-Object { $_.StartsWith('| ' + $entry.Key + ' |') })
      $row.Count | Should Be 1
      (($row[0] -split '\|')[-2]).Trim() | Should Be $entry.Value
    }
    @($matrixRows | Where-Object { $_ -match '^\|.*\| MISSING \|$' }).Count | Should Be 0
  }

  It 'starts generated Markdown with the required no-edit warning' {
    $root = New-DibsDocFixture
    $markdown = (New-DibsDocumentationOutputs (Get-FixtureModel $root))['docs/generated/player-guide.md']
    $markdown.StartsWith("THIS FILE IS GENERATED.`nDO NOT EDIT MANUALLY.") | Should Be $true
  }
}
