[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw 'Run this comparison harness from PowerShell 7 or later.'
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$generator = Join-Path $repositoryRoot 'scripts/Generate-DibsDocs.ps1'
$windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $windowsPowerShell -or -not $pwsh) {
  throw 'Both powershell.exe (Windows PowerShell 5.1) and pwsh (PowerShell 7) must be available.'
}

$runtimes = @(
  [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Path = $windowsPowerShell.Source; Version = '5.1' }
  [pscustomobject]@{ Name = 'PowerShell 7'; Path = $pwsh.Source; Version = '7.' }
)
$artifactNames = @(
  'player-guide.md', 'officer-guide.md', 'gm-guide.md', 'developer-reference.md',
  'ui-reference.md', 'terminology.md', 'documentation.csv', 'documentation.json'
)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dibs-doc-cross-version-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempRoot)
$hashesByRuntime = @{}

try {
  foreach ($runtime in $runtimes) {
    $versionText = (& $runtime.Path -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | Select-Object -Last 1).Trim()
    if (-not $versionText.StartsWith($runtime.Version, [System.StringComparison]::Ordinal)) {
      throw "Expected $($runtime.Name), found PowerShell $versionText at $($runtime.Path)."
    }

    $runtimeRoot = Join-Path $tempRoot (($runtime.Name -replace '[^A-Za-z0-9]+', '-').Trim('-'))
    [void][System.IO.Directory]::CreateDirectory($runtimeRoot)
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'src') -Destination $runtimeRoot -Recurse

    foreach ($mode in @('-Validate', '-Generate', '-Check')) {
      $output = & $runtime.Path -NoLogo -NoProfile -File $generator -Root $runtimeRoot $mode 2>&1
      $exitCode = $LASTEXITCODE
      foreach ($line in $output) { Write-Output ("[$($runtime.Name)] {0}" -f $line) }
      if ($exitCode -ne 0) {
        throw "$($runtime.Name) $mode failed with exit code $exitCode."
      }
    }

    $runtimeHashes = @{}
    foreach ($name in $artifactNames) {
      $path = Join-Path $runtimeRoot (Join-Path 'docs/generated' $name)
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$($runtime.Name) did not generate docs/generated/$name."
      }
      $runtimeHashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $hashesByRuntime[$runtime.Name] = $runtimeHashes
  }

  $matches = 0
  foreach ($name in $artifactNames) {
    $matchesExactly = $hashesByRuntime['Windows PowerShell 5.1'][$name] -ceq $hashesByRuntime['PowerShell 7'][$name]
    if ($matchesExactly) { $matches++ }
    Write-Output ('{0,-24} {1}' -f $name, $(if ($matchesExactly) { 'MATCH' } else { 'DIFFER' }))
  }
  Write-Output ("Cross-version SHA-256: {0}/{1} MATCH" -f $matches, $artifactNames.Count)
  if ($matches -ne $artifactNames.Count) { exit 1 }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
