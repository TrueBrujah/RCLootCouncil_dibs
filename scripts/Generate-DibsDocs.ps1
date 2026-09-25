[CmdletBinding()]
param(
  [switch]$Validate,
  [switch]$Generate,
  [switch]$Check,
  [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path $PSScriptRoot -Parent }

$selectedModes = @(@($Validate, $Generate, $Check) | Where-Object { $_ }).Count
if ($selectedModes -gt 1) {
  throw 'Choose only one of -Validate, -Generate, or -Check.'
}
if ($selectedModes -eq 0) { $Validate = $true }

Import-Module (Join-Path $PSScriptRoot 'docs/DibsDocumentation.psm1') -Force
$model = Get-DibsDocumentationModel -Root $Root
$summary = Get-DibsValidationSummary $model

Write-Output 'Documentation Validation'
Write-Output ('Concepts:             {0,5}' -f $summary.Concepts)
Write-Output ('Errors:               {0,5}' -f $summary.Errors)
Write-Output ('Warnings:             {0,5}' -f $summary.Warnings)
Write-Output ('Missing enUS:         {0,5}' -f $summary.MissingENUS)
Write-Output ('Missing frFR:         {0,5}' -f $summary.MissingFRFR)
Write-Output ('Duplicate IDs:        {0,5}' -f $summary.DuplicateIDs)

foreach ($finding in $model.Findings) {
  $location = if ($finding.File) { " $($finding.File):$($finding.Line)" } else { '' }
  Write-Output ("{0,-7} {1}{2} {3}" -f $finding.Severity, $finding.Rule, $location, $finding.Message)
}

if ($summary.Errors -gt 0) {
  Write-Output 'RESULT: FAIL'
  exit 1
}

$outputs = New-DibsDocumentationOutputs -Model $model
if ($Generate) {
  Write-DibsDocumentationOutputs -Outputs $outputs -Root $Root
  Write-Output ("Generated {0} documentation files." -f $outputs.Count)
}
if ($Check) {
  $stale = [System.Collections.Generic.List[string]]::new()
  foreach ($relativePath in $outputs.Keys) {
    $path = Join-Path $Root ($relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      $stale.Add("missing $relativePath")
      continue
    }
    $current = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
    if ($current -cne [string]($outputs[$relativePath])) { $stale.Add("stale $relativePath") }
  }
  if ($stale.Count -gt 0) {
    foreach ($item in $stale) { Write-Output "ERROR  generated-output $item" }
    Write-Output 'RESULT: FAIL'
    exit 1
  }
  Write-Output 'Generated files are current.'
}

Write-Output 'RESULT: PASS'
