# Release candidate build procedure — RCLootCouncil_dibs

This procedure builds an **isolated, verified copy** of the addon that can
be handed to an operator for a Retail validation campaign.

It **does not publish**, **does not deploy into WoW**, and **does not
change the TOC version**. The copy is produced in a staging directory
outside the repository; installing it into the game is a separate,
deliberate act performed by the operator.

The procedure reproduces exactly what the release workflow
(`.github/workflows/package-addon.yml`) does, and adds the checks that
the workflow does not perform.

---

## 1. Purpose and limits

| It does | It does not |
|---|---|
| Build a byte-exact copy of `src/` | Publish a release |
| Verify the load order, the libraries and the locks | Deploy into the game client |
| Produce a checksum of the artifact | Change `## Version:` |
| Produce a manifest an operator can review | Touch the real SavedVariables |
| Refuse to produce an artifact that fails a check | Modify the repository |

**The version is not changed by this procedure.** The current version is
`0.8.10` and stays `0.8.10`. A version bump is a release decision, not a
build step.

## 2. Prerequisites

- PowerShell 7 (works on 5.1 with minor differences).
- A **Lua 5.1.5** compiler for the compatibility gate. The procedure
  expects `luac51.exe`; see `docs/developer/testing.md` for the
  reproducible build of the upstream `lua-5.1.5` distribution.
- A staging destination **outside** the repository.

```powershell
$root   = (Get-Location).Path
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage  = Join-Path $env:USERPROFILE "RCLootCouncil_dibs-candidate-$stamp"
$luac   = Join-Path $env:TEMP 'lua-5.1.5\src\luac51.exe'
```

## 3. Build

```powershell
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$addon = Join-Path $stage 'RCLootCouncil_dibs'
robocopy (Join-Path $root 'src') $addon /E | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
```

This copies `src/` verbatim, exactly as the release workflow does
(`cp -a src/. "$staging/"`).

## 4. Verification gates

Every gate must pass. **Any failure aborts the build** and the staging
directory must be discarded, not shipped.

### 4.1 Required files are present

```powershell
$required = @(
    'RCLootCouncil_dibs.toc',
    'embeds.xml',
    'Core.lua',
    'media/RCLootCouncil_Dibs_Logo.tga'
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $addon $rel) -PathType Leaf)) { $missing += $rel }
}
if ($missing.Count -gt 0) { throw "Missing required file(s): $($missing -join ', ')" }
```

### 4.2 The TOC load order is complete and ordered

The TOC lists the load order explicitly. Every listed file must exist in
the candidate, and no source file may be absent from the TOC.

```powershell
$toc = Get-Content (Join-Path $addon 'RCLootCouncil_dibs.toc')
$listed = @()
foreach ($line in $toc) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('##')) { continue }
    $listed += ($t -replace '\\', '/')
}
$absent = $listed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $addon $_) -PathType Leaf) }
if ($absent) { throw "TOC lists a file that is absent: $($absent -join ', ')" }

# The reverse: a Lua file present in the candidate but not in the TOC.
# `Types.lua` is deliberately excluded: it is annotation-only (LuaLS /
# LuaCATS declarations) and states in its own header that it is not in
# the runtime TOC. It is a source artifact for editors and static
# analysis, not a loadable module.
$ANNOTATION_ONLY = @('Types.lua')
$inCandidate = Get-ChildItem $addon -Recurse -File -Filter '*.lua' |
    Where-Object { $_.FullName -notmatch '\\libs\\' } |
    ForEach-Object { $_.FullName.Substring($addon.Length + 1).Replace('\', '/') } |
    Where-Object { $ANNOTATION_ONLY -notcontains $_ }
$notListed = $inCandidate | Where-Object { $listed -notcontains $_ }
if ($notListed) { throw "Lua file(s) present but absent from the TOC: $($notListed -join ', ')" }
```

The second check is the one that catches a real packaging fault: a file
that exists but is never loaded. The `libs/` tree is excluded because the
embedded libraries are loaded through `embeds.xml`.

### 4.3 The embedded libraries are complete and untouched

```powershell
$libsSource = Get-ChildItem (Join-Path $root 'src\libs') -Recurse -File
$libsBad = 0
foreach ($file in $libsSource) {
    $rel = $file.FullName.Substring((Join-Path $root 'src').Length + 1)
    $copy = Join-Path $addon $rel
    if (-not (Test-Path -LiteralPath $copy)) { $libsBad++; continue }
    if ((Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne
        (Get-FileHash $copy -Algorithm SHA256).Hash) { $libsBad++ }
}
if ($libsBad -ne 0) { throw "The candidate differs from the protected libraries in $libsBad place(s)." }
Write-Output "LIBRARIES_OK files=$($libsSource.Count)"
```

The library count must be **77**. A different count means a library was
added or lost, which is a protected-surface change.

### 4.4 Lua 5.1 compatibility

```powershell
if (-not (Test-Path $luac)) { throw "Lua 5.1 compiler not found at $luac" }
$luaFiles = Get-ChildItem $addon -Recurse -File -Filter '*.lua'
$failed = @()
foreach ($file in $luaFiles) {
    & $luac -p $file.FullName
    if ($LASTEXITCODE -ne 0) { $failed += $file.FullName }
}
if ($failed) { throw "Lua 5.1 parse failure in: $($failed -join ', ')" }
Write-Output "LUA51_OK files=$($luaFiles.Count)"
```

Every Lua file of the candidate — application sources **and** libraries —
must parse under Lua 5.1. This is the gate that proves Retail will load
the addon: Retail runs Lua 5.1.

### 4.5 The RF-0012 release locks are closed

```powershell
$core = Get-Content (Join-Path $addon 'Core.lua') -Raw
$ledger = Get-Content (Join-Path $addon 'modules\Ledger.lua') -Raw
if ($core -notmatch 'CANONICAL_OPERATIONS_RELEASE_ENABLED\s*=\s*false') {
    throw "RF-0012 lock is open: CANONICAL_OPERATIONS_RELEASE_ENABLED is not false."
}
if ($ledger -notmatch 'DISPUTE_OPERATION_WRITES_ENABLED\s*=\s*false') {
    throw "RF-0012 lock is open: DISPUTE_OPERATION_WRITES_ENABLED is not false."
}
Write-Output "RF0012_LOCKS_CLOSED"
```

This gate is what makes the candidate safe to hand to an operator: the
canonical correction path cannot be reached in the build being tested.

### 4.6 The SavedVariables declaration is unchanged

```powershell
$tocText = Get-Content (Join-Path $addon 'RCLootCouncil_dibs.toc') -Raw
foreach ($declaration in @('RCLootCouncil_dibsDB', 'RCLootCouncil_dibsSandboxDB', 'RCLootCouncil_dibsLocalDB')) {
    if ($tocText -notmatch [regex]::Escape($declaration)) {
        throw "SavedVariables declaration missing: $declaration"
    }
}
if ($tocText -notmatch 'SavedVariablesPerCharacter:\s*RCLootCouncil_dibsLocalDB') {
    throw "RCLootCouncil_dibsLocalDB must stay per-character."
}
Write-Output "SAVEDVARIABLES_DECLARATION_OK"
```

The per-character declaration is what keeps the local presentation
settings out of the shared guild state. Changing it would change the
data model.

### 4.7 The version is unchanged

```powershell
$version = (Select-String -Path (Join-Path $addon 'RCLootCouncil_dibs.toc') -Pattern '^## Version: (.+)$').Matches[0].Groups[1].Value.Trim()
$expected = (Select-String -Path (Join-Path $root 'src\RCLootCouncil_dibs.toc') -Pattern '^## Version: (.+)$').Matches[0].Groups[1].Value.Trim()
if ($version -ne $expected) { throw "The candidate version ($version) differs from the source ($expected)." }
Write-Output "VERSION_UNCHANGED=$version"
```

### 4.8 The optional dependency is declared

```powershell
if ($tocText -notmatch 'OptionalDeps:\s*RCLootCouncil') {
    throw "OptionalDeps: RCLootCouncil is missing."
}
Write-Output "OPTIONALDEPS_OK"
```

`OptionalDeps` is what allows the core to load when RCLootCouncil is
absent. Removing it would turn a soft dependency into a hard one and
break the "usable without RCLootCouncil" contract.

## 5. Produce the artifact and its manifest

```powershell
$artifact = Join-Path $stage "RCLootCouncil_dibs-$version-candidate.zip"
if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    Compress-Archive -Path $addon -DestinationPath $artifact -Force
} else {
    & tar -a -c -f $artifact -C $stage 'RCLootCouncil_dibs'
}
$hash = (Get-FileHash $artifact -Algorithm SHA256).Hash
"$hash  $(Split-Path $artifact -Leaf)" | Out-File -Encoding ascii "$artifact.sha256"

Get-ChildItem $addon -Recurse -File | ForEach-Object {
    [pscustomobject]@{
        Path   = $_.FullName.Substring($addon.Length + 1).Replace('\', '/')
        Bytes  = $_.Length
        SHA256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
} | Sort-Object Path | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $stage 'candidate-manifest.csv')

Write-Output "ARTIFACT=$artifact"
Write-Output "SHA256=$hash"
```

The manifest lets the operator confirm, after the campaign, that the
build they tested is byte-for-byte the one that was validated.

## 6. Operator installation (out of scope of the build)

The build produces the artifact. Installing it into the game is a
separate act:

1. Close WoW completely.
2. Back up the existing `Interface\AddOns\RCLootCouncil_dibs` folder.
3. **Back up the real SavedVariables**:
   `World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\<REALM>\SavedVariables\RCLootCouncil_dibs.lua`
   and the `RCLootCouncil_dibsLocalDB.lua` sibling.
4. Extract the candidate into `Interface\AddOns\`.
5. Start the client and follow
   `docs/developer/rf-0012-retail-test-runbook.md`.

**Step 3 is not optional.** The addon never deletes the real
SavedVariables, and a restore never overwrites a newer shared chain, but
an operator must still be able to return to the previous state.

## 7. What the campaign may not do

- The RF-0012 release locks must stay closed in the tested build.
- The campaign must not edit the real SavedVariables by hand.
- The campaign must not bump the TOC version.
- The campaign must not open `OfficerUI.lua:3632`.
- A failure recorded in the campaign is a **result**, not a reason to
  patch the build: the build is fixed, the campaign is re-run.
