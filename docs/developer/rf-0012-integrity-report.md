# RF-0012 Integrity Report

Feature: `026-canonical-idempotent-corrections` — canonical idempotent dispute
corrections.

Date: 2026-10-18

This record closes T044: the final immutable-library and changed-path
verification for RF-0012. It is a verification record, not a Retail
certification. The manual in-game validation is still
`PENDING_MANUAL_VALIDATION` and is recorded separately in
[the RF-0012 validation record](rf-0012-retail-validation.md).

## 1. Commands executed

All commands were run from the repository root.

```powershell
python .github/skills/lua-code-audit/scripts/audit_guard.py verify
git --no-pager status --short
git --no-pager diff --check
```

## 2. Immutable-library verification

FR-042 requires every directory named `libs`, regardless of case or location,
to remain strictly read-only.

| Check | Result |
|---|---|
| Protected library file count under `src/libs` | 77 |
| `PROTÉGÉ` deltas reported by the audit guard | **0** |
| Any reported path containing a `libs` segment | **0** |
| `git status --short` entries under `src/libs` | **0** |
| Baseline recaptured or restored by this phase | **No** |

No file inside a `libs` directory was modified, added, deleted, renamed,
moved, reformatted, or annotated. No cleanup, refactoring, or removal of
existing `@AUDIT` annotations was performed inside a protected directory.

## 3. Audit guard result

`audit_guard.py verify` exits with code `1`. Per the task's stop/risk rule, a
nonzero guard exit is never reported as a pass, so the raw result is recorded
here.

The 40 reported differences are **all application Lua or test files**, and
every one of them is attributable to the RF-0012 work declared by this feature:

| Group | Count | Attributable to RF-0012 |
|---|---|---|
| Application source (`src/`) | 12 | Yes — the canonical operation model (`Ledger`, `MultiLedger`), the protected boundary (`ProtectedActions`, `Permissions`), the shared gate (`SyncV2`), Governance intent ownership, the backup/import path, the schema-8 core, the locales, and the Officer UI. |
| Test files (`tests/`) | 27 | Yes — the schema-8 expectation, the T015 routing change, the fixture corrections, and the new operation suites. |
| Any other path | 0 | — |

No unexplained difference was found. The guard reports nothing for
`src/libs`.

The 12 `src/` paths the guard names are the ones whose **content** changed
relative to the captured baseline. The other modified `src/` files carry
source-driven documentation annotations and supporting adapter updates that the
guard does not classify as content differences; they were still reviewed
individually through `git status --short` and `git diff --check`.

## 4. Changed-path review

The worktree contains 47 modified tracked files and 23 untracked paths. Every
one is accounted for:

- `src/` (21 modified) — the RF-0012 implementation and the source-driven
  documentation annotation move.
- `docs/developer/` (4 modified, 2 added) — the T038 developer documentation
  and the new RF-0012 Retail validation and integrity records.
- `docs/generated/` (4 modified) — the T039 regenerated outputs. These are
  produced by `scripts/Generate-DibsDocs.ps1` and are never hand-edited.
- `tests/` (16 modified, 11 added) — the RF-0012 suites and the fixture
  corrections.
- `specs/026-canonical-idempotent-corrections/` (added) — the feature
  specification, plan, tasks, and the live implementation status.
- `CHANGELOG.md` (modified) — the dated RF-0012 change note.

The 11 modified `src/` files that are not part of the canonical operation
model itself (`Types`, `Backup`, `Profiles`, `Sync`, `AceGUI`,
`MinimapButton`, `PlayerUI`, `SetupAssistant`, `Installation`) carry the
source-driven documentation annotations and the supporting type/adapter
updates required by the new modules. They were reviewed individually against
the guard output.

### Pre-existing unrelated changes

The following paths were already dirty or untracked before RF-0012 and were
**not** modified, reverted, or claimed by this feature:

- `RCLootCouncil_dibs.code-workspace`
- `.github/skills/lua-code-audit/`, `.github/skills/speckit-bug-assess/`,
  `.github/skills/speckit-bug-fix/`, `.github/skills/speckit-bug-test/`
- `.specify/bugs/`, `.specify/extensions.yml`, `.specify/extensions/`
- `docs/code-audit/`
- `INSTALLATION.md`

The audit index still lists **RF-0012** and **RF-0013** as `NEED_UPDATE`. The
RF-0013 finding in `src/modules/Installation.lua` is a separate, still-open
audit item. Its `@AUDIT` marker was moved above the `---@doc` block only so
the source-driven documentation validator could attach the annotation to its
function; the finding itself was neither resolved nor reclassified.

## 5. Whitespace and diff hygiene

| Check | Result |
|---|---|
| `git --no-pager diff --check` | Exit code `0`, no whitespace error |
| `git diff --check` on the whole worktree | Clean |
| Merge conflict markers | None |
| Leftover temporary files | None — the temporary test-file list and run log were removed |

## 6. Test evidence at final state

| Suite | Result |
|---|---|
| Complete repository suite (174 `*_spec.lua` files) | **1195 passed, 0 failed** |
| WoW Retail Lua 5.1 compilation guard (all 105 `src/` files) | **PASS** — every file compiles under Lua 5.1.5 |
| Focused RF-0012 regression set (14 suites) | 128 passed, 0 failed |
| Activation-lock suites (T013, protected boundary, operation, sync) | 46 passed, 0 failed |
| `tests/integration/t040_ui_acceptance_spec.lua` | 8 passed, 0 failed |
| Source-driven documentation validation | 0 errors, 29 concepts, 0 missing enUS, 0 missing frFR, 0 duplicate IDs |
| `scripts/Test-DibsDocsCrossVersion.ps1` (PowerShell 7) | `RESULT: PASS`, `Cross-version SHA-256: 8/8 MATCH` |
| `tests/powershell/Generate-DibsDocs.Tests.ps1` (Pester) | All cases pass |

The Fengari runner needs `NODE_OPTIONS=--max-old-space-size=8192`. The default
Node heap aborts with an out-of-memory error before the suite completes. That
is a harness limit, not a test failure, and it is recorded here so the result
is reproducible.

### WoW Retail Lua 5.1 compilation

WoW Retail runs Lua 5.1, which allows a function at most **60 upvalues**
(`LUAI_MAXUPVALUES`) and 200 local variables. A file that exceeds either
limit fails to load in the game. Fengari is a Lua 5.4-compatible interpreter
and does **not** reproduce that ceiling, so the Fengari suite cannot detect
this class of defect.

A real Lua 5.1.5 compiler was built from the upstream 5.1.5 source with MSVC
and used as the authoritative checker. It found two files that the addon
could not load with:

| File | Function | Upvalues | Attribution |
|---|---|---|---|
| `src/modules/SyncV2.lua` | `Sync.Receive` | 60 (61st: `clearResolvedLedgerGap`) | **Introduced by RF-0012** — it compiled at HEAD. |
| `src/ui/OfficerUI.lua` | `renderRoute` | 60 (61st: `automaticDibsTableRows`) | **Pre-existing at HEAD** — it did not compile at HEAD either. |

Both were fixed by extraction with no behavior change: the per-entity
transfer dispatch moved to a module-level `applyTransferEntity` in
`src/modules/SyncV2.lua`, and the route body moved to a module-level
`renderOfficerRoute` in `src/ui/OfficerUI.lua` that receives the values it
needs as parameters.

`tests/powershell/Test-DibsLua51Compilation.ps1` is the permanent guard. It
compiles every `src/` file with a real Lua 5.1 compiler, reports the
offending file and diagnostic, and is **skipped rather than silently
passed** when no Lua 5.1 compiler is available. A negative test confirms it
detects a deliberately over-limit file.

### A stale in-game build was still reporting the error

After the fix, a Retail client still reported:

```text
1x LUA_WARNING: RCLootCouncil_dibs/ui/OfficerUI.lua:1
RCLootCouncil_dibs/ui/OfficerUI.lua:8362: function at line 4982 has more than 60 upvalues
```

The reported definition line `4982` matches **no** committed revision: HEAD
has `renderRoute` at 4946, and the pre-fix worktree snapshot had it at 5050.
A search of every reachable object, reflog entry, and agent session
checkpoint found **zero** revisions with `renderRoute` at 4982. The line
number therefore identifies an **uncommitted intermediate worktree state**
that existed during the earlier implementation phase and was never committed.

The current source is verifiably clean:

| File | Stock Lua 5.1.5 |
|---|---|
| `src/ui/OfficerUI.lua` | compiles, exit 0 |
| `src/modules/SyncV2.lua` | compiles, exit 0 |
| All 105 `src/` files | **0 failures** |

No function in the current `src/ui/OfficerUI.lua` is at the 60-upvalue
ceiling. The warning can only come from a **build that predates this fix**.
The remedy is to copy the current `src/` content into the deployed
`Interface\AddOns\RCLootCouncil_dibs\` folder and reload; the procedure is in
[the RF-0012 test runbook](rf-0012-retail-test-runbook.md), section 1.4.

The two line numbers also confirm the source of the report: `8362` is the
callback line and `4982` is the definition line of the same warning, in
WoW's two-line Lua error format.

## 7. Production activation state

The canonical correction path is **closed** in the release source. Three
independent fail-closed seams guard it, and no user preference or
SavedVariables value can open them:

| Seam | Location | State |
|---|---|---|
| Ledger writer gate | `src/modules/Ledger.lua`, `DISPUTE_OPERATION_WRITES_ENABLED` | `false` |
| Private runtime readiness probe | `src/modules/Ledger.lua`, `operationReadinessProbe` | Delegates to the shared gate; unknown readiness is refused |
| Protected-boundary flag | `src/modules/ProtectedActions.lua` and `src/modules/SyncV2.lua`, `db.settings.canonical_operations` | Closed by default |

The shared gate `Sync.CanonicalOperationGate` is consulted by the coordinator
acceptance path, the SyncV2 send path, the SyncV2 receiver, and the
capability advertisement. A closed client never advertises
`ledgerOperationCommit`, so it never claims support it does not have.

## 8. Limitations

- The audit guard exits `1`. The reported differences are all attributable
  application and test changes; the baseline was **not** recaptured, and
  nothing was automatically restored.
- The Fengari results are not a Retail certification. FR-041 requires a
  separate multi-client in-game validation, which is recorded as
  `PENDING_MANUAL_VALIDATION`.
- T043 (release activation) and the `## Version` increment of T042 remain
  blocked by that missing validation. The release source keeps the canonical
  path closed.
