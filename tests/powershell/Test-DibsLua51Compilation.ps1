param(
  [string]$Root,
  [string]$LuacPath
)

<#
.SYNOPSIS
  Guards the WoW Retail Lua 5.1 compilation limits for the addon source.

.DESCRIPTION
  WoW Retail runs Lua 5.1. Lua 5.1 allows a function at most 60 upvalues
  (LUAI_MAXUPVALUES in luaconf.h) and 200 local variables per function. A
  source file that exceeds either limit fails to load in the game, even when it
  parses everywhere else.

  Fengari, the Lua 5.4-compatible interpreter used by the Fengari test suite,
  does not reproduce the Lua 5.1 upvalue ceiling, so the automated Lua suite
  cannot detect this class of defect. This guard therefore compiles every
  addon source file with a real Lua 5.1 compiler.

  The guard is skipped, not failed, when no Lua 5.1 compiler is available. The
  build environment is expected to provide one; a skipped run is reported
  explicitly so a missing tool is never mistaken for a passing check.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) }

function Resolve-Luac {
  param([string]$Explicit)

  if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
    if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) {
      throw "The Lua 5.1 compiler was not found at '$Explicit'."
    }
    return (Resolve-Path -LiteralPath $Explicit).Path
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua\luac.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Lua\5.1\luac.exe'),
    (Join-Path $env:ProgramFiles 'Lua\5.1\luac.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Lua\5.1\luac.exe')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }

  $onPath = Get-Command 'luac5.1' -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }

  return $null
}

$luac = Resolve-Luac -Explicit $LuacPath

if (-not $luac) {
  Write-Output 'RESULT: SKIPPED'
  Write-Output 'No Lua 5.1 compiler was found.'
  Write-Output 'The WoW Retail upvalue and local-variable limits were NOT checked.'
  Write-Output 'Set -LuacPath to a Lua 5.1 luac.exe, or place luac5.1 on PATH.'
  exit 0
}

$version = (& $luac -v 2>&1 | Out-String).Trim()
Write-Output "Compiler: $luac"
Write-Output "Version:  $version"
if ($version -notmatch 'Lua 5\.1') {
  throw "The compiler at '$luac' is not a Lua 5.1 compiler: $version"
}

$sourceRoot = Join-Path $Root 'src'
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
  # A deployed addon folder has the sources at its root (Core.lua, ui/, modules/).
  if ((Test-Path -LiteralPath (Join-Path $Root 'Core.lua') -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $Root 'ui') -PathType Container)) {
    $sourceRoot = $Root
  }
  else {
    throw "The addon source directory was not found at '$sourceRoot'."
  }
}

$files = @(Get-ChildItem -Path $sourceRoot -Recurse -Filter '*.lua' | Sort-Object FullName)
Write-Output ("Files:    {0,5}" -f $files.Count)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
  $output = & $luac -p -o NUL $file.FullName 2>&1
  if ($LASTEXITCODE -ne 0) {
    $relative = $file.FullName.Replace($Root + [System.IO.Path]::DirectorySeparatorChar, '')
    $detail = (($output | Where-Object { $_ -and $_ -notmatch '^\s*$' }) -join ' ').Trim()
    $failures.Add("$relative :: $detail")
  }
}

if ($failures.Count -gt 0) {
  Write-Output ''
  Write-Output 'Lua 5.1 compilation failures:'
  foreach ($failure in $failures) { Write-Output ("  " + $failure) }
  Write-Output ''
  Write-Output ("RESULT: FAIL ({0} file(s))" -f $failures.Count)
  exit 1
}

Write-Output ''
Write-Output 'Every addon source file compiles under Lua 5.1.'
Write-Output 'RESULT: PASS'
exit 0
