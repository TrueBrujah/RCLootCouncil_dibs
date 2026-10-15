# Validation: Development Catch-up

Run from the repository root in PowerShell:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\integration\minimap_button_spec.lua;tests\integration\great_vault_ui_spec.lua;tests\unit\great_vault_acquisition_spec.lua;tests\integration\great_vault_retail_capability_spec.lua;tests\integration\unified_history_search_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
git diff --check
```

Observed before this retrospective record: 40 passed, 0 failed across these
five suites. Earlier dispute verification: 21 passed across four suites.
The full pre-ticket run is recorded separately when completed.

First full run: 965 passed, 1 failed across 155 suites. The dashboard assertion
still expected unknown coordinator presence although the corrected shared
roster fixture now explicitly supplies online status. Align that assertion to
the fixture; keep the separate live-presence transition test unchanged.

After that assertion correction: 72 passed, 0 failed across seven selected
suites covering the dashboard, transport, sync status, anonymous export and
period statistics. `git diff --check` passed. This is a full run followed by a
targeted successful rerun, not a claim of a second all-green full run.

Checkpoint `07a6ce1` was committed and pushed to `origin/dev` before any ticket
source extension. Immediately after the push, local and remote dev had zero
divergence and the tracked worktree was clean.

## Manual gates still open

- Actual Retail selected Vault claim and local loot payload correlation.
- Full link inserted from bags/equipment, including a Myth-track reward.
- Real minimap toggling for normal member and Officer, including combat.
- Same-guild two-client recovery and privacy, including offline recipients.
- Visual scale/layout checks for history, health, statistics and export.

Original feature 013 tasks T051/T052 and feature 022 T022 remain unchecked.

## 2026-10-15 whisper guard follow-up

FR-005 is enforced again at the shared Ace3 transport boundary. Current roster
presence is refreshed before private sends; localized player-not-found feedback
for a recently contacted unambiguous recipient pauses retries for 60 seconds.
No chat errors are hidden and no saved work is discarded.

Full regression: **998 passed, 0 failed** across 157 suites before the final
pending-Vault retention test and legacy fallback rejection preservation edit.
Final focused run: **82 passed, 0 failed** across `tests/unit/b04_transport_spec.lua`,
`tests/integration/request_delivery_spec.lua`,
`tests/integration/request_followup_spec.lua`, `tests/unit/sync_trace_spec.lua`
and `tests/integration/toc_load_spec.lua`. This includes stale presence, repeated
blocked sends, English/French feedback, expiry, unrelated/ambiguous feedback and
pending Vault retention with a deterministic clock, plus unchanged guild sends.
`git diff --check` passed. The editor still reports the pre-existing single-return
annotation diagnostic in legacy `Sync.lua`; no diagnostics were reported in
the checked Ace3 adapter, Core or SyncV2 files.
Real Retail feedback ordering and already-queued AceComm
messages remain manual validation boundaries.

Qualified-address follow-up (2026-10-15): **84 passed, 0 failed** across the same
five focused suites after adding same-realm short-name completion and explicit
missing-realm rejection tests at the shared adapter boundary. Existing
cross-realm, realm-space and ambiguous-name coverage remains green. Editor
diagnostics for the changed adapter and transport tests are clear;
`git diff --check` passed.
