# DIBS Guided Setup Wizard: P1 remediation

Date: 2026-09-25. Scope: only F1-F3 in
`DIBS_Guided_Setup_Wizard_Post_Implementation_Validation.md`. No commit or
deployment was requested or performed for this remediation.

## Root causes and fixes

| P1 | Root cause | Exact fix |
| --- | --- | --- |
| F1, raid readiness | `Wizard.GetStatus` derived the global `READY_FOR_RAID` banner from Review alone, although its final step separately held `SetupAssistant.Evaluate().status`. An unknown report also mapped to a warning. | Global `READY_FOR_RAID` now requires both a READY Review and `SetupAssistant`'s actual `READY_FOR_RAID`. `NEEDS_ATTENTION`, `UNAVAILABLE`, `DENIED`, absent/unknown results all prevent a raid-ready banner; non-ready readiness returns a global BLOCKED result. The existing Review and Readiness UI now displays the existing SetupAssistant finding text, without introducing new probes. |
| F2, rank allocations | `RankRules.GetRankConfigurationSummary` counted MISSING reconciliation entries but discarded that count while choosing status; a configured rule alone meant READY. | The rollup keeps MISSING as ACTION_REQUIRED, SURPLUS/incomplete/unknown reconciliation as WARNING, and missing/malformed rules as ACTION_REQUIRED. A zero-allocation rank is OPTIONAL only when its members are reconciled. The Wizard fails closed on absent/empty rollups and identifies affected ranks in Review. No allocation or reconciliation engine was changed. |
| F3, sync transport | The Sync step checked only `Sync.IsSyncBehind`; false does not establish transport availability. Also, a failed send left `Sync.GetStatus().state` at `SYNC_UNAVAILABLE` even after a successful send. | The step reads `Sync.GetStatus` as the transport authority and returns READY only for explicit `SYNC_READY` without a behind flag; unavailable, behind and unknown states stay visible. On a successful existing `Sync.Send`, stale transport-unavailable status is cleared to SYNC_READY or SYNC_BEHIND as appropriate; a failed send still reports SYNC_UNAVAILABLE. The Wizard sends nothing. |

This follows one shared principle across the three defects: READY needs
positive evidence from the owning service, not merely the absence of a known
error. The ownership remains `SetupAssistant` for final raid readiness,
`RankRules.GetAllocationReconciliation` for allocations, and `Sync.GetStatus`
for transport and catch-up. The Wizard only reduces and presents them.

## Files changed

- `src/modules/Wizard.lua`: global verdict, rank/Sync reductions.
- `src/modules/RankRules.lua`: per-rank reconciliation rollup.
- `src/modules/SyncV2.lua`: clear stale unavailable transport status on a
  successful send, preserving `syncBehind`.
- `src/ui/OfficerUI.lua`: show the existing SetupAssistant findings in
  Review and Readiness.
- `tests/integration/guided_setup_wizard_spec.lua`: focused P1 regressions.
- This report. The earlier validation audit remains untouched.

No other production module, addon wire type, or protocol format was changed.

## Regression coverage and results

New/updated integration coverage exercises:

- A configured Review with SetupAssistant `UNAVAILABLE`, `NEEDS_ATTENTION`,
  or an unknown status cannot yield `READY_FOR_RAID`.
- Ready SetupAssistant plus a real incomplete rank remains partially
  configured; changing the SetupAssistant result and refreshing the open
  Wizard updates the displayed verdict. Review and Readiness display the
  existing finding text.
- Rank rules distinguish a healthy allocation, no rule, malformed/partial
  rule, configured positive rule with missing assigned allocation, zero
  allocation (OPTIONAL only if reconciled), surplus, truncated/unknown
  reconciliation, and unavailable roster/projection. The affected rank is
  visible in Review after a live rule change.
- Sync distinguishes healthy registered transport, transport unavailable
  without sync-behind, transport unavailable plus sync-behind, behind with
  transport, unknown status, recovery during an open Wizard, and real
  failed/successful sends. Recovered transport does not clear an existing
  sync-behind condition.

Results:

- Wizard focused: **20 passed, 0 failed** (1 file).
- Wizard plus Sync privacy: **24 passed, 0 failed** (2 files).
- Readiness, Installation, SetupAssistant, RankRules, Permissions, Sync and
  related targeted regressions: **78 passed, 0 failed** (15 files).
- Explicit full suite: **643 passed, 1 failed (139 files)**. The one failing
  assertion remains `tests/integration/predibs_sync_recovery_spec.lua:50`:
  expected one scheduled heartbeat, got two. It was observed in the earlier
  pre-remediation suite (634 passed, 1 failed) and is not altered by the
  changes above. It is classified **PRE-EXISTING**, not hidden as a green run.

VS Code diagnostics on Wizard, RankRules, OfficerUI and the test file are
clear. `SyncV2.lua` still reports two existing WoW secret-value diagnostics
on roster reads (lines 262 and 277); neither location was modified here.
`git diff --check` reported no whitespace errors. Retail runtime validation
of UI presentation was not available from the Lua harness.

## Data and compatibility

- SavedVariables schema: **unchanged**; no migration or completion flag.
- Ledger schema/history/balances: **unchanged**; neither opening nor stepping
  through the Wizard invokes a ledger write.
- RankRules authority: existing reconciliation projection remains the source
  of MISSING/SURPLUS/ALIGNED; the new rollup preserves its signal.
- Sync authority: `Sync.GetStatus` provides transport/behind state. Only a
  successful already-authorized send updates the stale transport status;
  there is no added Wizard broadcast, repair, coordinator election or
  reconciliation. Wire format is unchanged.
- Readiness authority: `SetupAssistant.Evaluate` remains independent and
  authoritative for a raid-ready verdict. The Wizard does not implement
  another readiness engine.

## Remaining findings

Existing P2/P3 items in the validation audit (optional RC/Pre-Dibs status
detail, incomplete tables, read-side normalization, local UI step scope,
installation diagnostics, Retail combat smoke tests) remain separate and
were deliberately not remediated. The known Pre-Dib heartbeat test and the
two pre-existing SyncV2 secret-value diagnostics also remain open. No source
or test was changed to mask these findings.

## Final result

P1 REMEDIATION COMPLETE