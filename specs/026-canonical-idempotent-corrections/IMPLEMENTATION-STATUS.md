# Implementation Status: Canonical Ledger Operations & Idempotent Dispute Corrections
Feature: `026-canonical-idempotent-corrections`

## Current Phase: Phase 7 — Polish and cross-cutting validation (T036-T045)
Status: **IMPLEMENTATION COMPLETE — PENDING RETAIL VALIDATION**

## Task Progress
- [x] T001-T030: Completed (all of US1, US2, and US3)
- [x] T031: Completed (Backup, restore, and import fixtures)
- [x] T032: Completed (Complete canonical operation history serialization)
- [x] T033: Completed (Restore through the verified recovery boundary)
- [x] T034: Completed (Preview-time operation identity checks)
- [x] T035: Completed (Legacy-compatibility assertions across migration, B06, backup, and import)
- [x] T036: Completed (Focused feature regression set: 128 passed, 0 failed across 14 suites)
- [x] T037: Completed (Complete repository suite)
- [x] T038: Completed (Developer documentation: architecture, saved-variables, sync-protocol, testing)
- [x] T039: Completed (Source-driven documentation: 0 errors, 29 concepts, cross-version 8/8 MATCH)
- [x] T040: Completed (UI acceptance coverage: `t040_ui_acceptance_spec.lua`, 8 passed, 0 failed)
- [ ] T041: BLOCKED — manual Retail multi-client validation (`PENDING_MANUAL_VALIDATION`)
- [ ] T042: PARTIAL — changelog note added; the TOC version increment waits for T041
- [ ] T043: BLOCKED — release activation stays closed until T041 passes
- [x] T044: Completed (Final library and changed-path verification)
- [x] T045: Completed (Retail readiness: Lua 5.1 compilation restored, release flag made
      genuinely release-controlled, operator runbook produced)
- [x] T046: Completed (OfficerUI runtime error `attempt to call a nil value` at
      `src/ui/OfficerUI.lua:3632` diagnosed and fixed)

## Verification Log
- [x] Complete repository suite (T037, T045, T046): **1201 passed, 0 failed** across 175 `*_spec.lua` files.
      The runner needs `NODE_OPTIONS=--max-old-space-size=8192`; the default Node heap aborts
      before the suite completes. That is a harness limit, not a test failure.
- [x] **WoW Retail Lua 5.1 compilation guard (T045)**: all 105 `src/` files compile under a real
      Lua 5.1.5 compiler. `tests/powershell/Test-DibsLua51Compilation.ps1`. The guard is skipped,
      never silently passed, when no Lua 5.1 compiler is available.
- [x] Focused feature regression set (T036): 128 passed, 0 failed across 14 suites.
- [x] Activation-lock suites (T013, protected boundary, operation, sync): 46 passed, 0 failed.
- [x] `tests/integration/t040_ui_acceptance_spec.lua`: 8 passed, 0 failed.
- [x] `tests/integration/request_followup_spec.lua`: 13 passed, 0 failed.
- [x] `tests/integration/request_delivery_spec.lua`: 16 passed, 0 failed.
- [x] Source-driven documentation validation (T039): 0 errors, 29 concepts, 0 missing enUS,
      0 missing frFR, 0 duplicate IDs.
- [x] `scripts/Test-DibsDocsCrossVersion.ps1` (Windows PowerShell 5.1 and PowerShell 7):
      `RESULT: PASS` in both, `Cross-version SHA-256: 8/8 MATCH`.
- [x] `audit_guard.py verify` returns 1 with 40 differences (12 `src/`, 27 `tests/`), ZERO
      `PROTÉGÉ` deltas, and no reported path containing a `libs` segment. `src/libs` keeps its
      77 files and `git status --short` reports no entry under it. The baseline is never
      recaptured.
- [x] `git diff --check` passed.
- [x] `tests/powershell/Generate-DibsDocs.Tests.ps1`: all Pester cases pass. Two assertions
      were stale at HEAD, not RF-0012 regressions: the catalog count was hard-coded to `26`
      while the source already held 29 concepts, and the warnings assertion expected `0` while
      the same 9 legacy orphan help keys already warned at HEAD. The count is now asserted
      against the model itself, and only `orphan-help-key` warnings are tolerated.
- [x] `scripts/Test-DibsDocsCrossVersion.ps1` under Windows PowerShell 5.1 and PowerShell 7:
      `RESULT: PASS` in both, `Cross-version SHA-256: 8/8 MATCH`.
- [x] Final complete repository suite at the final code state: **1195 passed, 0 failed** across
      174 `*_spec.lua` files.

## Defects Found and Fixed
- T011: `resolveLedger` returns `(id, ledger)` but the resolver unpacked it as `(ledger, reason)`, so
  every lookup failed with `LEDGER_UNAPPROVED`. Fixed in `src/modules/MultiLedger.lua`.
- T011: the resolver did not validate the requested guild against the local guild, and reported
  `LEDGER_UNAPPROVED` for an archived ledger and `ORIGINAL_TRANSACTION_NOT_FOUND` for an original
  held in another ledger. All three diagnostics fixed.
- T015: `applyTargetCorrection` contained a duplicated block that shadowed `key`, `state`, and
  `transactionIds`. The duplicate was removed.
- T015: the correction path had no bridge to the Ledger writer. `MultiLedger.RecordCanonicalOperation`
  now resolves the original ledger, builds one canonical operation, and submits it to
  `Ledger.CommitDisputeOperation`.
- T015: `correctionDetails` returned a protected action identifier where the operation needs a
  ledger action type. An explicit closed mapping was added.
- T019: the T010 identity assertion counted the SyncV2 transport message ID. The assertion is now
  scoped to the operation and entry identities the Ledger must never allocate.
- T022: `ApplyOperationCommit` used the projection helper before it was declared, so the receiver
  could not project an operation. The helper is now declared before both use it.
- T025: the derived operation index and the recovery classification table were used before they
  were declared. Both are now declared before their first use.
- T037: `tests/helpers/request_client_fixture.lua` replaced `Governance.GetAuthorityState` with a
  stub that dropped the established `transition`. A canonical operation could not resolve its
  baseline hash and failed with `CANONICAL_BASELINE_REQUIRED`. The stub now preserves the real
  transition while still simulating the world epoch.
- T039: the pre-existing `@AUDIT RF-0013` annotation in `src/modules/Installation.lua` sat after the
  `---@doc` block, so the source-driven documentation validator could not attach it and reported
  `orphan-annotation`. The marker was moved above the block. The RF-0013 finding itself was
  neither resolved nor reclassified.
- T040: `Dibs.OfficerUI.DescribeHistoricalReport` returned the same label for every
  classification because of a tautological ternary. Each of the five classes now has its own
  localized label and explanation.
- T040: the correction outcome reason was only reachable through a heading hover tooltip, so it
  was not plainly visible text. The action-applied and accounting-applied panels now render the
  outcome label and its reason as visible labels.
- T040: the accounting-applied panel did not show the outcome at all. It now receives the outcome
  from the resolve result and displays it.
- T045: **`src/ui/OfficerUI.lua` and `src/modules/SyncV2.lua` did not compile in WoW Retail.**
  Lua 5.1 allows a function at most 60 upvalues. `renderRoute` (OfficerUI) and `Sync.Receive`
  (SyncV2) each captured exactly 60, so the 61st reference failed the load. Fengari is a
  Lua 5.4-compatible interpreter and does not reproduce the 5.1 ceiling, so the Fengari suite
  could never have detected it. The OfficerUI failure was **pre-existing at HEAD**; the SyncV2
  failure was **introduced by RF-0012**. Both were fixed by extraction with no behavior change:
  `applyTransferEntity` in `src/modules/SyncV2.lua` and `renderOfficerRoute` in
  `src/ui/OfficerUI.lua`. `tests/powershell/Test-DibsLua51Compilation.ps1` is the permanent
  guard.
- T045: **the release flag was a SavedVariables value.** The gate read
  `db.settings.canonical_operations`, which contradicted the contract requirement that the flag
  is "release-controlled; it is not a user-facing setting or a SavedVariables toggle", and let a
  player open the canonical path by editing their settings. The flag is now the compiled constant
  `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED` in `src/Core.lua`, read by the shared gate and by
  the protected boundary. No SavedVariables value, UI control, or `/dibs` command writes it.
- T045: `tests/integration/t013_lock_verification_spec.lua` had a second test case with an
  **empty body** and no assertions. It now proves that the boundary still refuses with the
  release flag open when the readiness guards are not met, using the real modules rather than a
  mock, and that a hand-edited SavedVariables value does not open the path.
- T045: a Retail client kept reporting `OfficerUI.lua:8362: function at line 4982 has more than
  60 upvalues` after the fix. The reported definition line `4982` matches **no** committed
  revision (HEAD has `renderRoute` at 4946, the pre-fix worktree snapshot at 5050), and a search of
  every reachable object, reflog entry, and agent session checkpoint found **zero** revisions at
  4982. The report therefore came from a **stale deployed build** created from an uncommitted
  intermediate worktree state. The current source is verifiably clean: `src/ui/OfficerUI.lua` and
  `src/modules/SyncV2.lua` both compile with exit 0 under stock Lua 5.1.5, all 105 `src/` files
  compile, and no function in the current `OfficerUI.lua` is at the 60-upvalue ceiling. The
  runbook now documents the refresh procedure and a deployed-folder check for the guard.
- T046: **OfficerUI runtime error `attempt to call a nil value` at `OfficerUI.lua:3632`.** The
  "Start Independent Session" button callback read the session title and the starting points
  through `Dibs.AceGUI.GetText`, but the AceGUI adapter never defined `GetText` (it only defines
  `SetText`), and `Dibs.AceGUI` **is** the adapter table. The call therefore raised
  "attempt to call a nil value" the moment the button was pressed. The bug was **pre-existing at
  HEAD** (line 3529 there) and was **not** caused by the OfficerUI refactoring. The fix uses the
  file's established `getControlText(control)` helper, which reads the widget's `GetText` under
  `pcall` and falls back to `control._dibsText`; the AceGUI `EditBox` widget exposes `GetText`
  (`self.editbox:GetText()`), so the value round-trips correctly. The callback was not made
  conditional: the fields are contractually required, and the correct action is to read them
  through the existing accessor. `tests/integration/officer_ui_independent_raid_button_spec.lua`
  reproduces the defect — with the bug re-injected it fails with the exact Retail message
  `src/ui/OfficerUI.lua:3632: attempt to call a nil value (field 'GetText')`, and it passes on
  the fixed source. A scan of every `Dibs.AceGUI.*` call in `src/` against the adapter's real
  exports found **no other missing function**.

## Defects Found and Fixed (test fixture corrections, not production behavior)

The two remaining complete-suite failures were **not** production defects. T015 deliberately moved
every balance-changing correction behind the canonical V2 path, which requires an enforced V2
protocol, a verified coordinator, and an approved baseline. The two suites still assumed the
pre-T015 legacy-local behavior, so their corrections were refused with `V2_ENFORCED_REQUIRED` and
`ORIGINAL_TRANSACTION_REQUIRED`. The production refusals are correct per FR-004, FR-017, and
FR-028 and were **not** weakened. The fixtures were corrected instead:

- `tests/integration/request_followup_spec.lua`: the dossier now carries a verifiable original
  transaction, and the test opens the canonical path in its isolated environment.
- `tests/integration/request_delivery_spec.lua`: the coordinator now records a verifiable original
  transaction, opens the canonical path, and delivers its own dossier to the officer replica so the
  competing attempt is refused by authority (`CURRENT_COORDINATOR_REQUIRED`) rather than by a
  missing dossier.
- `tests/helpers/dispute_fixtures.lua`: added `enableCanonicalCorrectionPath` and
  `activateCanonicalCoordinator`. They replace only the private Ledger upvalues and the same public
  release flag the release build keeps closed. No user preference or SavedVariables option is
  involved.

## Activation State
The canonical correction path is closed in the release source. The release flag
`Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED` is a constant compiled into `src/Core.lua` and is
`false` there. It is **not** a user preference, **not** a UI control, and **not** a SavedVariables
value; nothing a player can change opens the path. Two further seams are fail-closed: the Ledger
writer gate (`DISPUTE_OPERATION_WRITES_ENABLED`) and the private runtime readiness probe, which
delegates to the shared gate `Sync.CanonicalOperationGate`. The SyncV2 receiver refuses an
operation record with `CANONICAL_DISPUTE_OPERATIONS_DISABLED` before it buffers the transfer, and
the capability is advertised only while the shared gate is open. A dedicated pre-release candidate
may set the release flag to `true` in a reviewed source revision to exercise the canonical path in
Retail; the stable release keeps it `false`.

## Blockers
**T041 — manual Retail multi-client validation.** The procedure is fully recorded in
`docs/developer/rf-0012-retail-validation.md` with 20 numbered observations, but no observation
is marked `PASS` because no Retail clients were available in this environment. This blocks the
T042 version increment and the T043 release activation. The canonical correction path stays
closed in the release source.

## Next Task
T041 — Execute the manual multi-client Retail validation in
`docs/developer/rf-0012-retail-validation.md` on a dedicated test guild with one coordinator,
one non-coordinator Officer, one compatible follower, and one offline/reconnecting member. Then
complete the T042 `## Version` increment, the T043 release activation, and record the result.

