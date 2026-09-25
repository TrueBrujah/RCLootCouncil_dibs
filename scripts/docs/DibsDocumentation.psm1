Set-StrictMode -Version Latest

$script:AllowedDocFields = @(
  'id', 'since', 'changed', 'deprecated', 'removed', 'category', 'audience',
  'permission', 'scope', 'help-key', 'label-key', 'reference-key', 'audit', 'reason-required'
)
$script:AllowedAudiences = @('player', 'officer', 'gm', 'developer')
$script:AllowedScopes = @('player', 'guild', 'guild-season', 'character-local', 'raid-session')
$script:AllowedCategories = @('ledger', 'rank-rules', 'predibs', 'setup', 'synchronization', 'governance', 'protocol')
$script:DeveloperTerms = @('LEGACY_LOCAL', 'CUTOVER_PREPARED', 'V2_ENFORCED', 'ledgerEpoch', 'legacyBaselineHash', 'SyncV2')
$script:VersionPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'

function Add-DibsFinding {
  param(
    [System.Collections.Generic.List[object]]$Findings,
    [ValidateSet('ERROR', 'WARNING', 'INFO')][string]$Severity,
    [string]$Rule,
    [string]$Message,
    [string]$File = '',
    [int]$Line = 0,
    [string]$ConceptId = ''
  )

  $Findings.Add([pscustomobject][ordered]@{
    Severity = $Severity
    Rule = $Rule
    Message = $Message
    File = $File
    Line = $Line
    ConceptId = $ConceptId
  })
}

function Test-DibsVersion {
  param([AllowNull()][string]$Version)
  return ($null -ne $Version -and $Version -cmatch $script:VersionPattern)
}

function ConvertTo-DibsCanonicalText {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return '' }
  return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function ConvertFrom-LuaQuotedString {
  param([Parameter(Mandatory)][string]$Literal)

  if ($Literal.Length -lt 2 -or $Literal[0] -ne '"' -or $Literal[$Literal.Length - 1] -ne '"') {
    throw "Expected a double-quoted Lua string: $Literal"
  }

  $builder = [System.Text.StringBuilder]::new()
  for ($index = 1; $index -lt $Literal.Length - 1; $index++) {
    $character = $Literal[$index]
    if ($character -ne '\') {
      [void]$builder.Append($character)
      continue
    }

    $index++
    if ($index -ge $Literal.Length - 1) { throw "Incomplete Lua escape in $Literal" }
    $escaped = $Literal[$index]
    switch ($escaped) {
      'a' { [void]$builder.Append([char]7); break }
      'b' { [void]$builder.Append([char]8); break }
      'f' { [void]$builder.Append([char]12); break }
      'n' { [void]$builder.Append("`n"); break }
      'r' { [void]$builder.Append("`r"); break }
      't' { [void]$builder.Append("`t"); break }
      'v' { [void]$builder.Append([char]11); break }
      '\' { [void]$builder.Append('\'); break }
      '"' { [void]$builder.Append('"'); break }
      default {
        if ([char]::IsDigit($escaped)) {
          $digits = [System.Text.StringBuilder]::new()
          [void]$digits.Append($escaped)
          for ($digitIndex = 0; $digitIndex -lt 2 -and $index + 1 -lt $Literal.Length - 1 -and [char]::IsDigit($Literal[$index + 1]); $digitIndex++) {
            $index++
            [void]$digits.Append($Literal[$index])
          }
          $codePoint = [int]::Parse($digits.ToString(), [Globalization.CultureInfo]::InvariantCulture)
          if ($codePoint -gt 255) { throw "Lua decimal escape exceeds 255 in $Literal" }
          [void]$builder.Append([char]$codePoint)
        } elseif ($escaped -eq 'z') {
          while ($index + 1 -lt $Literal.Length - 1 -and [char]::IsWhiteSpace($Literal[$index + 1])) { $index++ }
        } else {
          throw "Unsupported Lua escape '\$escaped' in $Literal"
        }
      }
    }
  }
  return $builder.ToString()
}

function Read-DibsLocaleCatalog {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
  )

  $catalog = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Add-DibsFinding $Findings ERROR 'locale-file-missing' "Locale file not found: $Path" $Path
    return $catalog
  }

  $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
  $assignmentPattern = '^\s*L\.([A-Za-z0-9_]+)\s*=\s*("(?:\\.|[^"\\])*")\s*$'
  for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
    if ($lines[$lineIndex] -notmatch $assignmentPattern) { continue }
    $key = $Matches[1]
    try {
      $value = ConvertFrom-LuaQuotedString $Matches[2]
      if ($catalog.ContainsKey($key)) {
        Add-DibsFinding $Findings ERROR 'duplicate-locale-key' "Duplicate locale key $key." $Path ($lineIndex + 1)
      } else {
        $catalog[$key] = $value
      }
    } catch {
      Add-DibsFinding $Findings ERROR 'invalid-locale-string' $_.Exception.Message $Path ($lineIndex + 1)
    }
  }
  return $catalog
}

function Get-DibsRelativePath {
  param([string]$Root, [string]$Path)
  $rootPrefix = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Source path is outside repository root: $Path"
  }
  return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-DibsModuleName {
  param([string]$SourceFile)
  return [System.IO.Path]::GetFileNameWithoutExtension($SourceFile)
}

function Get-DibsKnownPermissions {
  param([string]$Path)
  $permissions = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $permissions }
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  foreach ($match in [regex]::Matches($text, '\["(?<id>[a-z][a-z0-9.-]*)"\]\s*=\s*true')) {
    $permissions[$match.Groups['id'].Value] = $true
  }
  return $permissions
}

function ConvertTo-DibsTags {
  param(
    [AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings,
    [hashtable]$RawTags,
    [string]$File,
    [int]$Line
  )

  $tags = @{}
  $changed = [System.Collections.Generic.List[string]]::new()
  foreach ($rawName in $RawTags.Keys) {
    $name = $rawName.ToLowerInvariant()
    if ($name -eq 'help') { $name = 'help-key' }
    if ($name -eq 'reason_required') { $name = 'reason-required' }
    if ($name -notin $script:AllowedDocFields) {
      Add-DibsFinding $Findings ERROR 'unknown-doc-field' "Unknown @doc field '$rawName'." $File $Line ([string]($RawTags['id']))
      continue
    }
    if ($name -eq 'changed') {
      foreach ($version in ([string]($RawTags[$rawName]) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $changed.Add($version)
      }
      continue
    }
    if ($tags.ContainsKey($name)) {
      Add-DibsFinding $Findings ERROR 'duplicate-doc-field' "@doc.$name may appear only once." $File $Line ([string]($RawTags['id']))
      continue
    }
    $tags[$name] = [string]($RawTags[$rawName])
  }
  $tags['changed'] = @($changed)
  return $tags
}

function Get-DibsDocBlocks {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
  )

  $sourceRoot = Join-Path $Root 'src'
  $sourcePaths = @()
  if (Test-Path -LiteralPath $sourceRoot -PathType Container) {
    $sourcePaths = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.lua' |
      Where-Object { $_.FullName -notmatch '[\\/]locales[\\/]' -and $_.FullName -notmatch '[\\/]generated[\\/]' } |
      ForEach-Object { $_.FullName })
  }
  [Array]::Sort($sourcePaths, [System.StringComparer]::Ordinal)

  $blocks = [System.Collections.Generic.List[object]]::new()
  foreach ($path in $sourcePaths) {
    $relative = Get-DibsRelativePath $Root $path
    $lines = [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)
    for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
      if ($lines[$lineIndex] -notmatch '^\s*---\s*@doc\.([a-z_-]+)\s+(.+?)\s*$') { continue }

      $blockLine = $lineIndex + 1
      $rawTags = @{}
      $cursor = $lineIndex
      $firstDeclarationLine = 0
      $symbol = ''
      while ($cursor -lt $lines.Length) {
        $current = $lines[$cursor]
        if ($current -match '^\s*---\s*@doc\.([a-z_-]+)\s+(.+?)\s*$') {
          $rawName = $Matches[1].ToLowerInvariant()
          $rawValue = $Matches[2].Trim()
          if (-not $rawTags.ContainsKey($rawName)) { $rawTags[$rawName] = [System.Collections.Generic.List[string]]::new() }
          $rawTags[$rawName].Add($rawValue)
          $cursor++
          continue
        }
        if ($current -match '^\s*---') { $cursor++; continue }
        if ($current -match '^\s*$') { $cursor++; continue }
        if ($current -match '^\s*(?:local\s+)?function\s+(?<symbol>[A-Za-z_][A-Za-z0-9_.:]*)\s*\(') {
          $symbol = $Matches['symbol']
          $firstDeclarationLine = $cursor + 1
        }
        break
      }

      if ($firstDeclarationLine -eq 0) {
        $rawId = if ($rawTags.ContainsKey('id') -and $rawTags['id'].Count -gt 0) { $rawTags['id'][0] } else { '' }
        Add-DibsFinding $Findings ERROR 'orphan-annotation' 'Annotation block is not immediately attached to a supported Lua function declaration.' $relative $blockLine $rawId
        $lineIndex = [Math]::Max($lineIndex, $cursor - 1)
        continue
      }

      $canonicalRawTags = @{}
      foreach ($name in $rawTags.Keys) {
        if ($name -eq 'changed') {
          $canonicalRawTags[$name] = @($rawTags[$name])
        } else {
          if ($rawTags[$name].Count -gt 1) {
            Add-DibsFinding $Findings ERROR 'duplicate-doc-field' "@doc.$name may appear only once." $relative $blockLine ([string](($rawTags['id'])[0]))
          }
          $canonicalRawTags[$name] = $rawTags[$name][0]
        }
      }
      $tags = ConvertTo-DibsTags $Findings $canonicalRawTags $relative $blockLine
      $blocks.Add([pscustomobject]@{
        Tags = $tags
        File = $relative
        Line = $firstDeclarationLine
        AnnotationLine = $blockLine
        Symbol = $symbol
      })
      $lineIndex = $cursor - 1
    }
  }
  return $blocks.ToArray()
}

function Get-DibsValidationSummary {
  param([Parameter(Mandatory)]$Model)
  $findings = @($Model.Findings)
  return [pscustomobject][ordered]@{
    Concepts = @($Model.Concepts).Count
    Errors = @($findings | Where-Object Severity -eq 'ERROR').Count
    Warnings = @($findings | Where-Object Severity -eq 'WARNING').Count
    Infos = @($findings | Where-Object Severity -eq 'INFO').Count
    MissingENUS = @($findings | Where-Object Rule -eq 'missing-enUS').Count
    MissingFRFR = @($findings | Where-Object Rule -eq 'missing-frFR').Count
    DuplicateIDs = @($findings | Where-Object Rule -eq 'duplicate-id').Count
  }
}

function Get-DibsDocumentationModel {
  [CmdletBinding()]
  param([string]$Root = (Join-Path $PSScriptRoot '../..'))

  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
  $findings = [System.Collections.Generic.List[object]]::new()
  $enUS = Read-DibsLocaleCatalog (Join-Path $resolvedRoot 'src/locales/enUS.lua') $findings
  $frFR = Read-DibsLocaleCatalog (Join-Path $resolvedRoot 'src/locales/frFR.lua') $findings
  $currentVersion = ''
  $tocPath = Join-Path $resolvedRoot 'src/RCLootCouncil_dibs.toc'
  if (Test-Path -LiteralPath $tocPath -PathType Leaf) {
    $tocText = [System.IO.File]::ReadAllText($tocPath, [System.Text.Encoding]::UTF8)
    if ($tocText -match '(?m)^## Version:\s*(\S+)') { $currentVersion = $Matches[1].Trim() }
  }
  if (-not (Test-DibsVersion $currentVersion)) {
    Add-DibsFinding $findings ERROR 'invalid-addon-version' "Invalid or missing addon version '$currentVersion'." 'src/RCLootCouncil_dibs.toc'
  }

  $knownPermissions = Get-DibsKnownPermissions (Join-Path $resolvedRoot 'src/modules/ProtectedActions.lua')
  $blocks = @(Get-DibsDocBlocks $resolvedRoot $findings)
  $concepts = [System.Collections.Generic.List[object]]::new()
  $seenIds = @{}
  foreach ($block in $blocks) {
    $tags = $block.Tags
    $id = [string]($tags['id'])
    if ([string]::IsNullOrWhiteSpace($id)) {
      Add-DibsFinding $findings ERROR 'missing-doc-id' 'Annotation is missing @doc.id.' $block.File $block.AnnotationLine
    } elseif ($id -cnotmatch '^[a-z][a-z0-9]*(?:\.[a-z0-9]+)+$') {
      Add-DibsFinding $findings ERROR 'invalid-doc-id' "Invalid semantic ID '$id'; use lowercase dot-delimited tokens." $block.File $block.AnnotationLine $id
    }
    if ($id -and $seenIds.ContainsKey($id)) {
      Add-DibsFinding $findings ERROR 'duplicate-id' "Duplicate semantic ID '$id'; first declared at $($seenIds[$id].File):$($seenIds[$id].Line)." $block.File $block.AnnotationLine $id
    } elseif ($id) {
      $seenIds[$id] = $block
    }

    foreach ($required in @('id', 'category', 'since', 'audience', 'scope', 'help-key', 'audit')) {
      if (-not $tags.ContainsKey($required) -or [string]::IsNullOrWhiteSpace([string]($tags[$required]))) {
        Add-DibsFinding $findings ERROR "missing-$required" "Missing required @doc.$required." $block.File $block.AnnotationLine $id
      }
    }
    $category = [string]($tags['category'])
    if ($category -and $category -notin $script:AllowedCategories) {
      Add-DibsFinding $findings ERROR 'invalid-category' "Unknown documentation category '$category'." $block.File $block.AnnotationLine $id
    }
    $since = [string]($tags['since'])
    if ($since -and -not (Test-DibsVersion $since)) {
      Add-DibsFinding $findings ERROR 'invalid-version' "Invalid @doc.since version '$since'." $block.File $block.AnnotationLine $id
    }
    foreach ($field in @('deprecated', 'removed')) {
      if ($tags.ContainsKey($field) -and -not (Test-DibsVersion ([string]($tags[$field])))) {
        Add-DibsFinding $findings ERROR 'invalid-version' "Invalid @doc.$field version '$($tags[$field])'." $block.File $block.AnnotationLine $id
      }
    }
    foreach ($changedVersion in @($tags['changed'])) {
      if (-not (Test-DibsVersion ([string]$changedVersion))) {
        Add-DibsFinding $findings ERROR 'invalid-version' "Invalid @doc.changed version '$changedVersion'." $block.File $block.AnnotationLine $id
      }
    }

    $audience = @(([string]($tags['audience']) -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) | Sort-Object -Unique)
    foreach ($role in $audience) {
      if ($role -notin $script:AllowedAudiences) {
        Add-DibsFinding $findings ERROR 'invalid-audience' "Unknown audience '$role'." $block.File $block.AnnotationLine $id
      }
    }
    $permissions = @(([string]($tags['permission']) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Sort-Object -Unique)
    foreach ($permission in $permissions) {
      if (-not $knownPermissions.ContainsKey($permission)) {
        Add-DibsFinding $findings ERROR 'invalid-permission' "Unknown protected action '$permission'." $block.File $block.AnnotationLine $id
      }
    }
    $scope = [string]($tags['scope'])
    if ($scope -and $scope -notin $script:AllowedScopes) {
      Add-DibsFinding $findings ERROR 'invalid-scope' "Unknown semantic scope '$scope'." $block.File $block.AnnotationLine $id
    }

    $audit = $false
    if ($tags.ContainsKey('audit')) {
      if ([string]($tags['audit']) -notin @('true', 'false')) {
        Add-DibsFinding $findings ERROR 'invalid-boolean' "@doc.audit must be true or false." $block.File $block.AnnotationLine $id
      } else { $audit = ([string]($tags['audit']) -ceq 'true') }
    }
    $reasonRequired = $false
    if ($tags.ContainsKey('reason-required')) {
      if ([string]($tags['reason-required']) -notin @('true', 'false')) {
        Add-DibsFinding $findings ERROR 'invalid-boolean' "@doc.reason-required must be true or false." $block.File $block.AnnotationLine $id
      } else { $reasonRequired = ([string]($tags['reason-required']) -ceq 'true') }
    }
    if ($reasonRequired -and -not $audit) {
      Add-DibsFinding $findings ERROR 'reason-without-audit' '@doc.reason-required true requires @doc.audit true.' $block.File $block.AnnotationLine $id
    }
    if (-not $block.File -or $block.Line -lt 1 -or -not $block.Symbol) {
      Add-DibsFinding $findings ERROR 'missing-source-trace' 'Concept must identify source file, declaration line, and symbol.' $block.File $block.AnnotationLine $id
    }

    $helpKey = [string]($tags['help-key'])
    $labelKey = [string]($tags['label-key'])
    $referenceKey = [string]($tags['reference-key'])
    foreach ($keyInfo in @(
      [pscustomobject]@{ Key = $helpKey; Kind = 'help' },
      [pscustomobject]@{ Key = $labelKey; Kind = 'label' },
      [pscustomobject]@{ Key = $referenceKey; Kind = 'reference' }
    )) {
      if (-not $keyInfo.Key) { continue }
      $hasEnglish = $enUS.ContainsKey($keyInfo.Key)
      $hasFrench = $frFR.ContainsKey($keyInfo.Key)
      if (-not $hasEnglish -and -not $hasFrench) {
        Add-DibsFinding $findings ERROR "unknown-$($keyInfo.Kind)-key" "Unknown $($keyInfo.Kind) key '$($keyInfo.Key)'." $block.File $block.AnnotationLine $id
      }
      if (-not $hasEnglish) { Add-DibsFinding $findings ERROR 'missing-enUS' "Missing enUS value for '$($keyInfo.Key)'." $block.File $block.AnnotationLine $id }
      if (-not $hasFrench) { Add-DibsFinding $findings ERROR 'missing-frFR' "Missing frFR value for '$($keyInfo.Key)'." $block.File $block.AnnotationLine $id }
    }

    $label = [ordered]@{
      enUS = if ($labelKey -and $enUS.ContainsKey($labelKey)) { $enUS[$labelKey] } else { '' }
      frFR = if ($labelKey -and $frFR.ContainsKey($labelKey)) { $frFR[$labelKey] } else { '' }
    }
    $shortHelp = [ordered]@{
      enUS = if ($helpKey -and $enUS.ContainsKey($helpKey)) { $enUS[$helpKey] } else { '' }
      frFR = if ($helpKey -and $frFR.ContainsKey($helpKey)) { $frFR[$helpKey] } else { '' }
    }
    $reference = [ordered]@{
      enUS = if ($referenceKey -and $enUS.ContainsKey($referenceKey)) { $enUS[$referenceKey] } else { '' }
      frFR = if ($referenceKey -and $frFR.ContainsKey($referenceKey)) { $frFR[$referenceKey] } else { '' }
    }
    if ($labelKey) {
      foreach ($locale in @('enUS', 'frFR')) {
        if ($label[$locale] -and $shortHelp[$locale] -and $label[$locale] -ceq $shortHelp[$locale]) {
          Add-DibsFinding $findings WARNING 'label-equals-help' "Localized label and short help are identical in $locale." $block.File $block.Line $id
        }
      }
    } else {
      Add-DibsFinding $findings WARNING 'missing-label-key' 'No localized label-key; generated output will identify this concept by ID.' $block.File $block.Line $id
    }

    $concepts.Add([pscustomobject][ordered]@{
      id = $id
      sourceFile = $block.File
      sourceLine = $block.Line
      module = Get-DibsModuleName $block.File
      symbol = $block.Symbol
      category = $category
      since = $since
      changed = @($tags['changed'])
      deprecated = if ($tags.ContainsKey('deprecated')) { [string]($tags['deprecated']) } else { $null }
      removed = if ($tags.ContainsKey('removed')) { [string]($tags['removed']) } else { $null }
      audience = $audience
      permissions = $permissions
      scope = $scope
      helpKey = $helpKey
      labelKey = $labelKey
      referenceKey = $referenceKey
      audit = $audit
      reasonRequired = $reasonRequired
      label = $label
      shortHelp = $shortHelp
      reference = $reference
    })
  }

  $legacyHelpKeys = @($enUS.Keys | Where-Object { $_ -like 'UI_HELP_*' })
  $allSourceText = ''
  $sourceRoot = Join-Path $resolvedRoot 'src'
  if (Test-Path -LiteralPath $sourceRoot -PathType Container) {
    $allSourceText = (Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.lua' |
      Where-Object { $_.FullName -notmatch '[\\/]locales[\\/]' -and $_.FullName -notmatch '[\\/]generated[\\/]' } |
      ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) }) -join "`n"
  }
  foreach ($key in $legacyHelpKeys) {
    if ($allSourceText -notmatch ('(?<![A-Za-z0-9_])' + [regex]::Escape($key) + '(?![A-Za-z0-9_])')) {
      Add-DibsFinding $findings WARNING 'orphan-help-key' "Legacy help key '$key' has no first-party source reference." 'src/locales/enUS.lua' 0 $key
    }
  }

  foreach ($role in @('player', 'officer', 'gm')) {
    $roleConcepts = @($concepts | Where-Object { $_.audience -contains $role })
    foreach ($concept in $roleConcepts) {
      $visibleText = @($concept.label.enUS, $concept.label.frFR, $concept.shortHelp.enUS, $concept.shortHelp.frFR) -join ' '
      foreach ($term in $script:DeveloperTerms) {
        if ($visibleText.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
          Add-DibsFinding $findings ERROR 'developer-term-leak' "Developer-only term '$term' appears in $role concept '$($concept.id)'." $concept.sourceFile $concept.sourceLine $concept.id
        }
      }
    }
  }

  $sortedConcepts = [System.Collections.Generic.SortedDictionary[string, object]]::new([System.StringComparer]::Ordinal)
  foreach ($concept in $concepts) {
    if ($concept.id -and -not $sortedConcepts.ContainsKey($concept.id)) { $sortedConcepts.Add($concept.id, $concept) }
  }
  return [pscustomobject][ordered]@{
    SchemaVersion = 1
    AddonVersion = $currentVersion
    Concepts = @($sortedConcepts.Values)
    Findings = @($findings.ToArray())
  }
}

function ConvertTo-DibsMarkdownRole {
  param([object[]]$Concepts, [string]$Role, [string]$Title)
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine('THIS FILE IS GENERATED.')
  [void]$builder.AppendLine('DO NOT EDIT MANUALLY.')
  [void]$builder.AppendLine()
  [void]$builder.AppendLine("# $Title")
  [void]$builder.AppendLine()
  [void]$builder.AppendLine("Addon version: $script:OutputVersion")
  [void]$builder.AppendLine()
  $visible = @($Concepts | Where-Object { $_.audience -contains $Role })
  foreach ($concept in $visible) {
    $heading = if ($concept.label.enUS) { $concept.label.enUS } else { $concept.id }
    [void]$builder.AppendLine("## $heading")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("- **ID:** ``$($concept.id)``")
    [void]$builder.AppendLine("- **Category:** ``$($concept.category)``")
    [void]$builder.AppendLine("- **Audience:** $($concept.audience -join ', ')")
    [void]$builder.AppendLine()
    if ($concept.shortHelp.enUS) {
      [void]$builder.AppendLine("**English:** $($concept.shortHelp.enUS)")
    }
    if ($concept.shortHelp.frFR) {
      [void]$builder.AppendLine("**Francais:** $($concept.shortHelp.frFR)")
    }
    if ($Role -eq 'developer' -and $concept.reference.enUS) {
      [void]$builder.AppendLine()
      [void]$builder.AppendLine("**Technical reference:** $($concept.reference.enUS)")
      if ($concept.reference.frFR) { [void]$builder.AppendLine("**Reference technique:** $($concept.reference.frFR)") }
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Scope: ``$($concept.scope)`` | Audit: ``$($concept.audit.ToString().ToLowerInvariant())`` | Reason required: ``$($concept.reasonRequired.ToString().ToLowerInvariant())``")
    if ($concept.permissions.Count -gt 0) { [void]$builder.AppendLine("Permission: ``$($concept.permissions -join ', ')``") }
    $sourceLink = "../../$($concept.sourceFile)#L$($concept.sourceLine)"
    [void]$builder.AppendLine("Source: [$($concept.sourceFile):$($concept.sourceLine)]($sourceLink) - ``$($concept.symbol)``")
    [void]$builder.AppendLine()
  }
  if ($visible.Count -eq 0) { [void]$builder.AppendLine('_No concepts are published for this audience in the current pilot._') }
  return (ConvertTo-DibsCanonicalText $builder.ToString()).TrimEnd([char[]]@([char]10)) + "`n"
}

function ConvertTo-DibsUIReference {
  param([object[]]$Concepts)
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine('THIS FILE IS GENERATED.')
  [void]$builder.AppendLine('DO NOT EDIT MANUALLY.')
  [void]$builder.AppendLine()
  [void]$builder.AppendLine('# UI and API Reference')
  [void]$builder.AppendLine()
  foreach ($concept in $Concepts) {
    $label = if ($concept.label.enUS) { $concept.label.enUS } else { $concept.id }
    [void]$builder.AppendLine("## $label (``$($concept.id)``)")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Category: ``$($concept.category)`` | Module: ``$($concept.module)`` | Audience: $($concept.audience -join ', ')")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("**English:** $($concept.shortHelp.enUS)")
    [void]$builder.AppendLine("**Francais:** $($concept.shortHelp.frFR)")
    if ($concept.reference.enUS) { [void]$builder.AppendLine("**Technical reference:** $($concept.reference.enUS)") }
    [void]$builder.AppendLine("Source: ``$($concept.sourceFile):$($concept.sourceLine)`` (``$($concept.symbol)``)")
    [void]$builder.AppendLine()
  }
  return (ConvertTo-DibsCanonicalText $builder.ToString()).TrimEnd([char[]]@([char]10)) + "`n"
}

function ConvertTo-DibsTerminology {
  param([object[]]$Concepts)
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine('THIS FILE IS GENERATED.')
  [void]$builder.AppendLine('DO NOT EDIT MANUALLY.')
  [void]$builder.AppendLine()
  [void]$builder.AppendLine('# Terminology')
  [void]$builder.AppendLine()
  foreach ($concept in @($Concepts | Where-Object { $_.audience -contains 'player' -or $_.audience -contains 'officer' -or $_.audience -contains 'gm' })) {
    if (-not $concept.label.enUS -and -not $concept.label.frFR) { continue }
    [void]$builder.AppendLine("## $($concept.label.enUS) / $($concept.label.frFR)")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("**English:** $($concept.shortHelp.enUS)")
    [void]$builder.AppendLine("**Francais:** $($concept.shortHelp.frFR)")
    [void]$builder.AppendLine()
  }
  return (ConvertTo-DibsCanonicalText $builder.ToString()).TrimEnd([char[]]@([char]10)) + "`n"
}

function ConvertTo-DibsCsv {
  param([object[]]$Concepts)
  $columns = @('Id', 'Module', 'Category', 'Since', 'Changed', 'Deprecated', 'Removed', 'Audience', 'Permission', 'Scope', 'HelpKey', 'LabelKey', 'Audit', 'ReasonRequired', 'LabelEN', 'LabelFR', 'ShortHelpEN', 'ShortHelpFR', 'PlayerHelpEN', 'PlayerHelpFR', 'OfficerHelpEN', 'OfficerHelpFR', 'GMHelpEN', 'GMHelpFR', 'ReferenceEN', 'ReferenceFR', 'TechnicalEN', 'TechnicalFR', 'SourceFile', 'SourceLine', 'Symbol')
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.Append(($columns -join ','))
  [void]$builder.Append("`n")
  foreach ($concept in $Concepts) {
    $values = @(
      $concept.id, $concept.module, $concept.category, $concept.since, ($concept.changed -join ';'), $concept.deprecated, $concept.removed,
      ($concept.audience -join ';'), ($concept.permissions -join ';'), $concept.scope, $concept.helpKey, $concept.labelKey,
      $concept.audit.ToString().ToLowerInvariant(), $concept.reasonRequired.ToString().ToLowerInvariant(),
      $concept.label.enUS, $concept.label.frFR, $concept.shortHelp.enUS, $concept.shortHelp.frFR,
      '', '', '', '', '', '', $concept.reference.enUS, $concept.reference.frFR, '', '',
      $concept.sourceFile, [string]$concept.sourceLine, $concept.symbol
    )
    for ($index = 0; $index -lt $values.Count; $index++) {
      if ($index -gt 0) { [void]$builder.Append(',') }
      $cell = ConvertTo-DibsCanonicalText ([string]$values[$index])
      [void]$builder.Append('"')
      [void]$builder.Append($cell.Replace('"', '""'))
      [void]$builder.Append('"')
    }
    [void]$builder.Append("`n")
  }
  return $builder.ToString()
}

function Write-DibsJsonString {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value, [Parameter(Mandatory)][System.Text.StringBuilder]$Builder)

  $slash = [string][char]92
  [void]$Builder.Append([char]34)
  for ($index = 0; $index -lt $Value.Length; $index++) {
    $character = $Value[$index]
    $code = [int]$character
    switch ($code) {
      8 { [void]$Builder.Append($slash + 'b'); break }
      9 { [void]$Builder.Append($slash + 't'); break }
      10 { [void]$Builder.Append($slash + 'n'); break }
      12 { [void]$Builder.Append($slash + 'f'); break }
      13 { [void]$Builder.Append($slash + 'r'); break }
      34 { [void]$Builder.Append($slash + [char]34); break }
      92 { [void]$Builder.Append($slash + $slash); break }
      default {
        if ($code -lt 32) {
          [void]$Builder.Append($slash + 'u' + $code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture))
        } elseif ([char]::IsHighSurrogate($character)) {
          if ($index + 1 -lt $Value.Length -and [char]::IsLowSurrogate($Value[$index + 1])) {
            [void]$Builder.Append($character)
            $index++
            [void]$Builder.Append($Value[$index])
          } else {
            [void]$Builder.Append($slash + 'u' + $code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture))
          }
        } elseif ([char]::IsLowSurrogate($character)) {
          [void]$Builder.Append($slash + 'u' + $code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture))
        } else {
          [void]$Builder.Append($character)
        }
      }
    }
  }
  [void]$Builder.Append([char]34)
}

function Write-DibsJsonValue {
  param(
    [AllowNull()][AllowEmptyString()][object]$Value,
    [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
    [int]$Depth = 0
  )

  if ($null -eq $Value) {
    [void]$Builder.Append('null')
    return
  }
  if ($Value -is [string]) {
    Write-DibsJsonString $Value $Builder
    return
  }
  if ($Value -is [bool]) {
    if ($Value) { [void]$Builder.Append('true') } else { [void]$Builder.Append('false') }
    return
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -eq 0) {
      [void]$Builder.Append('{}')
      return
    }
    [void]$Builder.Append("{`n")
    for ($index = 0; $index -lt $properties.Count; $index++) {
      [void]$Builder.Append((' ' * (($Depth + 1) * 2)))
      Write-DibsJsonString $properties[$index].Name $Builder
      [void]$Builder.Append(': ')
      Write-DibsJsonValue $properties[$index].Value $Builder ($Depth + 1)
      if ($index -lt $properties.Count - 1) { [void]$Builder.Append(',') }
      [void]$Builder.Append("`n")
    }
    [void]$Builder.Append((' ' * ($Depth * 2)))
    [void]$Builder.Append('}')
    return
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $keys = @($Value.Keys)
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)
    if ($keys.Count -eq 0) {
      [void]$Builder.Append('{}')
      return
    }
    [void]$Builder.Append("{`n")
    for ($index = 0; $index -lt $keys.Count; $index++) {
      [void]$Builder.Append((' ' * (($Depth + 1) * 2)))
      Write-DibsJsonString ([string]$keys[$index]) $Builder
      [void]$Builder.Append(': ')
      Write-DibsJsonValue $Value[$keys[$index]] $Builder ($Depth + 1)
      if ($index -lt $keys.Count - 1) { [void]$Builder.Append(',') }
      [void]$Builder.Append("`n")
    }
    [void]$Builder.Append((' ' * ($Depth * 2)))
    [void]$Builder.Append('}')
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $items = @($Value)
    if ($items.Count -eq 0) {
      [void]$Builder.Append('[]')
      return
    }
    [void]$Builder.Append("[`n")
    for ($index = 0; $index -lt $items.Count; $index++) {
      [void]$Builder.Append((' ' * (($Depth + 1) * 2)))
      Write-DibsJsonValue $items[$index] $Builder ($Depth + 1)
      if ($index -lt $items.Count - 1) { [void]$Builder.Append(',') }
      [void]$Builder.Append("`n")
    }
    [void]$Builder.Append((' ' * ($Depth * 2)))
    [void]$Builder.Append(']')
    return
  }
  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
    [void]$Builder.Append(([System.IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture))
    return
  }
  throw "Unsupported JSON value type '$($Value.GetType().FullName)'."
}

function ConvertTo-DibsJson {
  param([object[]]$Concepts, [string]$AddonVersion)
  $items = [System.Collections.Generic.List[object]]::new()
  foreach ($concept in $Concepts) {
    $items.Add([pscustomobject][ordered]@{
      id = $concept.id
      module = $concept.module
      category = $concept.category
      lifecycle = [pscustomobject][ordered]@{
        since = $concept.since
        changed = @($concept.changed)
        deprecated = $concept.deprecated
        removed = $concept.removed
      }
      audience = @($concept.audience)
      permission = @($concept.permissions)
      scope = $concept.scope
      audit = [bool]$concept.audit
      reasonRequired = [bool]$concept.reasonRequired
      helpKeys = [pscustomobject][ordered]@{
        label = $concept.labelKey
        shortHelp = $concept.helpKey
        reference = $concept.referenceKey
      }
      content = [pscustomobject][ordered]@{
        label = [pscustomobject][ordered]@{ enUS = $concept.label.enUS; frFR = $concept.label.frFR }
        shortHelp = [pscustomobject][ordered]@{ enUS = $concept.shortHelp.enUS; frFR = $concept.shortHelp.frFR }
        reference = [pscustomobject][ordered]@{ enUS = $concept.reference.enUS; frFR = $concept.reference.frFR }
      }
      source = [pscustomobject][ordered]@{
        file = $concept.sourceFile
        line = [int]$concept.sourceLine
        symbol = $concept.symbol
      }
    })
  }
  $model = [pscustomobject][ordered]@{
    schemaVersion = 1
    addonVersion = $AddonVersion
    concepts = @($items.ToArray())
  }
  $builder = [System.Text.StringBuilder]::new()
  Write-DibsJsonValue $model $builder
  [void]$builder.Append("`n")
  return $builder.ToString()
}

function New-DibsDocumentationOutputs {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Model)

  $script:OutputVersion = $Model.AddonVersion
  $concepts = @($Model.Concepts)
  $outputs = [ordered]@{
    'docs/generated/player-guide.md' = ConvertTo-DibsMarkdownRole $concepts 'player' 'Player Documentation Reference'
    'docs/generated/officer-guide.md' = ConvertTo-DibsMarkdownRole $concepts 'officer' 'Officer Documentation Reference'
    'docs/generated/gm-guide.md' = ConvertTo-DibsMarkdownRole $concepts 'gm' 'Guild Master Documentation Reference'
    'docs/generated/developer-reference.md' = ConvertTo-DibsMarkdownRole $concepts 'developer' 'Developer Documentation Reference'
    'docs/generated/ui-reference.md' = ConvertTo-DibsUIReference $concepts
    'docs/generated/terminology.md' = ConvertTo-DibsTerminology $concepts
    'docs/generated/documentation.csv' = ConvertTo-DibsCsv $concepts
    'docs/generated/documentation.json' = ConvertTo-DibsJson $concepts $Model.AddonVersion
  }
  return $outputs
}

function Write-DibsDocumentationOutputs {
  param([Parameter(Mandatory)]$Outputs, [Parameter(Mandatory)][string]$Root)
  foreach ($relativePath in $Outputs.Keys) {
    $path = Join-Path $Root ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $directory = [System.IO.Path]::GetDirectoryName($path)
    [void][System.IO.Directory]::CreateDirectory($directory)
    $content = ConvertTo-DibsCanonicalText ([string]($Outputs[$relativePath]))
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
  }
}

Export-ModuleMember -Function Get-DibsDocumentationModel, Get-DibsValidationSummary, New-DibsDocumentationOutputs, Write-DibsDocumentationOutputs, Test-DibsVersion
