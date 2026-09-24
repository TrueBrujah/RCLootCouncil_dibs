# Autonomous Improvement Log - 2026-09-24

## Scope

Improve the addon across six areas: transfer reliability, diagnostics, automated tests, SavedVariables safety, Guild synchronization UI, and governance recovery.

## Progress

- [x] Transfer diagnostics: baseline ACKs, final result states, transfer timeout window, and chunk progress fields.
- [x] Guild synchronization UI: local/remote baseline state is visible as `Present`, `Missing`, `Applying`, `Rejected`, or `Unknown`.
- [x] Local governance UI: the local baseline state is shown in the synchronization summary and the V2 approval action is hidden after enforcement.
- [ ] Transfer completion: Firebutt still needs a live test with the latest build. The observed state was `TRANSFER_STARTED` without `BASELINE_APPLIED`.
- [x] Baseline persistence inspection: GM SavedVariables contain an approved baseline with hash `D3-V2-51ab59b4`.
- [x] Automated transport coverage: a unit test now checks duplicate chunks and reports missing-chunk progress.
- [x] Backup/export review: existing Backup and ImportExport modules provide bounded recovery workflows; no destructive reset was added without a guild-scope guarantee.
- [ ] Firebutt-only reset command: existing backup/import infrastructure exists, but a destructive reset needs a separate explicit workflow and live validation.
- [ ] Full governance recovery validation: requires two live WoW clients; the automated suite now covers the deterministic transport and governance paths, but not live AceComm scheduling.

## Confirmed Findings

- The GM baseline is present and structurally valid in SavedVariables.
- The baseline is currently empty of historical evidence (`sources`, `decisions`, and `playerSeasonState` are empty), but this is valid.
- The GM file recorded `TRANSFER_STARTED`; it did not record `BASELINE_APPLIED`.
- The hash format `D3-V2-*` is correct. No hash compatibility change is needed.
- The previous `Local behind` display for the GM was a UI projection issue and has been corrected.

## Blockers

- Lua runtime blocker resolved: Lua 5.4.6 is installed locally and `lua tests/run.lua` passes 24 tests with 0 failures.
- No local WoW runtime can be simulated by the Lua test runner. AceComm throttling, message ordering, and Firebutt's actual SavedVariables load must still be tested in game.
- A receiver-side error after `TRANSFER_BEGIN` can only be conclusively identified from the new final ACK and chunk counters.
- A safe Firebutt-only reset depends on whether Firebutt uses a separate WoW account/guild scope; deleting the global account file could erase GM data.

## Next Live Test

1. Reload both clients with the deployed build.
2. Run one `/dibs sync repair Firebutt` from Hudada.
3. Run `/dibs sync probe Firebutt` and `/dibs sync report Firebutt`.
4. Record the baseline column and `baselineAck` result, including `chunks=x/y` when present.

Do not delete the GM SavedVariables before this test.
