# B11f Implementation Evidence

## Scope

This pass implements only US6 / B11f, the RCLootCouncil History Reconciliation
UX slice. B11g / US7 remains untouched.

`B11F_START_COMMIT=e051c00d97f9255bdb3c1e9b6ec1826d7782e14a`

The result commit is the single commit containing this evidence file; its full
hash is recorded in the final completion report.

## Guided workflow

- `Dibs.LogsUI.SearchHistory` starts a bounded, permission-checked, read-only
  history scan through `Dibs.RCLootCouncil.CreateReconciliationSession`.
- The Officer surface now presents explicit Search History, History scan
  complete, Review Candidates, Confirm/Reject, and Reconciliation complete
  stages while retaining the compatible B09 entry point.
- Scan summaries report rows scanned, possible Dibs, ignored rows, ambiguous
  rows, confirmed rows, rejected rows, and unresolved rows.
- Candidate rows prioritize item, winner, date, difficulty, response, status,
  and a concise evidence summary. `ReviewCandidate` exposes technical fields
  only in the secondary detail projection.
- Empty history and no-candidate states are explicit. RCLootCouncil unavailable,
  degraded, and unsupported states have human-readable messages.

## Authority and safety

- `Dibs.LogsUI.ConfirmCandidate` and `RejectCandidate` delegate to the existing
  `Dibs.RCLootCouncil.ConfirmReconciliationCandidate` and
  `RejectReconciliationCandidate` services. Those services call
  `ProtectedActions.Execute("history.confirm", ...)` and
  `ProtectedActions.Execute("history.reject", ...)`.
- Ambiguous, unsupported, legacy, already-accounted, stale, or incomplete rows
  cannot be presented as confirmable. Duplicate confirmation remains handled by
  the existing service and does not append a second debit.
- UI code does not query `GetHistoryDB`, write RCLootCouncil tables, synthesize
  RC history rows, call `RecordHistoricalAward`, debit balances, or append
  ledger events directly.
- Full Name-Realm identity and B05/B06 coordinator, recovery, authority, and
  synchronization checks remain in the existing protected/domain services.
- Player history uses `Dibs.PlayerUI.BuildHistoryView`, a bounded local
  projection containing no Officer evidence, candidate, vote, or raw RC fields.

## Tests

Focused B11f and B09 reconciliation tests:

```text
20 passed, 0 failed (4 files)
```

The B11a-f regression passed:

```text
45 passed, 0 failed (13 files)
```

The full suite result was:

```text
355 passed, 1 failed (88 files)
```

The sole failure is the unchanged baseline
`tests/integration/rclootcouncil_buttons_spec.lua:155` (`expected 2/2, got 1/1`).

Static diagnostics reported no errors for the touched Lua files. The complete
B11 regression and full Fengari suite therefore introduce no new failures.

## Result

`B11f COMPLETE - READY FOR B11g`.
