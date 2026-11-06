# Worktree backup procedure — RCLootCouncil_dibs

This procedure produces a **complete, restorable copy** of the current
working tree, including the untracked files and the local modifications,
without performing any commit, push, stash, reset or clean.

It exists because the worktree carries roughly 119 modified or untracked
entries, of which 62 are **not tracked by git at all**. A `git stash` or a
plain `git diff` would silently drop the 62 untracked entries. The
procedure therefore never relies on git alone.

**Nothing in this procedure modifies the repository.** It only reads from
it and writes to an external directory.

---

## 1. State to be preserved

| Category | Count | Git state |
|---|---|---|
| Production sources (`src/`) | 28 | modified, tracked |
| Tests (`tests/**/*_spec.lua`) | 15 modified + 45 added | mixed |
| Test helpers and scripts | 6 | mixed |
| Generated documentation (`docs/generated/`) | 4 | modified, tracked |
| Audit documentation (`docs/code-audit/`) | 1 dir | **untracked** |
| Developer documentation (`docs/developer/`) | 9 | 4 modified, 5 untracked |
| Changelog | 1 | modified, tracked |
| Feature specs and tooling (`.specify/`, `.github/skills/`, `specs/`) | 9 | **untracked** |
| Other (`RCLootCouncil_dibs.code-workspace`, `INSTALLATION.md`) | 2 | mixed |
| **Total** | **119** | 0 deleted, 0 staged |
| Protected libraries (`src/libs/`) | 77 | **unchanged** — must stay so |

## 2. Prerequisites

- A destination directory **outside** the repository, on a different
  physical path, so that a recursive copy cannot feed on itself.
- Enough free space for roughly 60 MB (the repository is small; the
  `.git` directory is the large part and is not needed).
- PowerShell 7 is recommended but the procedure works on Windows
  PowerShell 5.1.

## 3. Procedure

### 3.1 Choose and record the destination

```powershell
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$root     = (Get-Location).Path
$backup   = Join-Path $env:USERPROFILE "RCLootCouncil_dibs-backup-$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Write-Output "BACKUP_ROOT=$backup"
```

The destination **must not** be inside `$root`. A path under the
repository would be copied into itself and would also pollute
`git status`.

### 3.2 Record the git state (read-only)

```powershell
git --no-pager status --short            | Out-File -Encoding utf8 "$backup\git-status.txt"
git --no-pager status --short --branch    | Out-File -Encoding utf8 "$backup\git-status-branch.txt"
git --no-pager log --oneline -20          | Out-File -Encoding utf8 "$backup\git-log.txt"
git --no-pager rev-parse HEAD             | Out-File -Encoding utf8 "$backup\git-head.txt"
git --no-pager diff --stat                | Out-File -Encoding utf8 "$backup\git-diff-stat.txt"
git --no-pager diff                        | Out-File -Encoding utf8 "$backup\git-diff.patch"
```

`git diff` alone is **not** sufficient: it contains only the 57 tracked
modifications. The untracked files are copied separately in 3.4.

### 3.3 Copy the tracked modifications

```powershell
# The full working tree, excluding .git and the protected libraries are
# copied too, so the backup is self-sufficient.
robocopy $root $backup\tree /E /XD .git node_modules /XF '*.tmp' '*.bak' | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
```

`robocopy` exit codes below 8 mean success (0–7 are informational:
files copied, extras detected, etc.). Anything **8 or above** is a real
failure and must abort the procedure.

### 3.4 Copy the untracked files explicitly (belt and braces)

`robocopy` in 3.3 already copies them, but they are listed separately so
that the backup is auditable: if the untracked set is ever larger than
what 3.3 copied, the discrepancy is visible.

```powershell
$untracked = git --no-pager ls-files --others --exclude-standard
$untracked | Out-File -Encoding utf8 "$backup\untracked-files.txt"
$missing = @()
foreach ($rel in $untracked) {
    $source = Join-Path $root $rel
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $target = Join-Path $backup "untracked\$rel"
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    } else {
        $missing += $rel
    }
}
if ($missing.Count -gt 0) {
    $missing | Out-File -Encoding utf8 "$backup\untracked-missing.txt"
    Write-Output "WARNING: $($missing.Count) untracked path(s) were directories or vanished."
}
```

### 3.5 Verify the protected libraries are byte-identical

```powershell
$libsBad = 0
foreach ($file in Get-ChildItem (Join-Path $root 'src\libs') -Recurse -File) {
    $rel = $file.FullName.Substring($root.Length + 1)
    $copy = Join-Path $backup "tree\$rel"
    if (-not (Test-Path -LiteralPath $copy)) { $libsBad++; continue }
    if ((Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne
        (Get-FileHash $copy -Algorithm SHA256).Hash) { $libsBad++ }
}
if ($libsBad -ne 0) { throw "The protected libraries differ in $libsBad place(s)." }
```

### 3.6 Compute a manifest of everything

```powershell
$manifest = Get-ChildItem $backup -Recurse -File |
    ForEach-Object {
        [pscustomobject]@{
            Path   = $_.FullName.Substring($backup.Length + 1)
            Bytes  = $_.Length
            SHA256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        }
    }
$manifest | Sort-Object Path | Export-Csv -NoTypeInformation -Encoding utf8 "$backup\manifest.csv"
Write-Output "MANIFEST_ENTRIES=$($manifest.Count)"
```

### 3.7 Verify the backup

```powershell
# Every file in the manifest must be readable and match its hash.
$bad = 0
foreach ($row in (Import-Csv "$backup\manifest.csv")) {
    $p = Join-Path $backup $row.Path
    if (-not (Test-Path -LiteralPath $p)) { $bad++; continue }
    if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $row.SHA256) { $bad++ }
}
if ($bad -ne 0) { throw "Backup verification failed for $bad file(s)." }
Write-Output "BACKUP_VERIFIED files=$($manifest.Count) bad=$bad"
```

## 4. Restore procedure

Restoring is a **manual, deliberate** operation. It is written down so it
is available if it is ever needed, not because it is expected to be run.

```powershell
# 1. Stop the game and any running test.
# 2. Move the current worktree aside (do NOT delete it).
Move-Item $root "$root.aside-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
# 3. Copy the backup tree back.
robocopy "$backup\tree" $root /E /XD .git | Out-Null
# 4. Restore the git metadata from the recorded HEAD.
git --no-pager log --oneline -1      # must match git-head.txt
git --no-pager status --short        # must match git-status.txt
```

The verification of step 4 is the real check: the restored `git status`
must be **identical** to `git-status.txt` and the restored `git diff` must
be **byte-identical** to `git-diff.patch`.

## 5. What this procedure does not do

- It does **not** create a commit, a branch, a tag, a stash or a remote.
- It does **not** run `git reset`, `git clean`, `git checkout` or
  `git restore`.
- It does **not** modify the protected libraries: they are copied and
  their hashes are verified, never rewritten.
- It does **not** touch the real SavedVariables: those live in the WoW
  client directory, outside the repository.
- It does **not** deploy anything into WoW.

## 6. Retention

The backup is a plain directory. Keep at least the three most recent
backups until the Retail campaign is complete. A backup can be deleted
only after the corresponding validation results have been recorded in
`docs/code-audit/AUTONOMOUS-SESSION-STATUS.md`.
