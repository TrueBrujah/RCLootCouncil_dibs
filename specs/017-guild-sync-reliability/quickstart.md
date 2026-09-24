# Quickstart: Validating Guild Sync Reliability

## Prerequisites

- Repository checked out, dependencies available (`npx fengari` runs via `npx.cmd --yes fengari`).
- No WoW client required for these scenarios; validation is via the Fengari test suite using `tests/helpers/distributed_ledger_fixture.lua`, which simulates multiple real guild clients (roles, network delays/partitions) without touching any live guild.

## Scenario 1 — Award proposal relay across two simultaneous raids (User Story 1)

1. Build a guild fixture with three clients: `Coordinator-Realm` (current ledger coordinator), `Officer2-Realm` (officer in a second, separate raid group, not the coordinator), `Player-Realm`.
2. Have `Officer2-Realm` finalize an award for `Player-Realm` while connected but not grouped with `Coordinator-Realm`.
3. Run the pending relay: assert `Officer2-Realm`'s local `AwardProposal` becomes `RELAY_PENDING` immediately, then `RELAY_ACKED`/`COMMITTED` once delivered to `Coordinator-Realm` and confirmed.
4. Assert `Coordinator-Realm`'s ledger balance for `Player-Realm` reflects exactly one deduction, and `Officer2-Realm`'s and `Player-Realm`'s own views converge to the same balance after the resulting `AWARD_COMMIT` broadcast.
5. Repeat step 2's submission twice (simulate a retry) and assert only one ledger effect results (idempotency).
6. Partition `Coordinator-Realm` from `Officer2-Realm` before delivery, then heal the partition; assert the proposal still gets delivered and applied without duplication.

**Run**: `tests/integration/award_proposal_relay_spec.lua`

## Scenario 2 — Season catalog propagation (User Story 2)

1. Build a guild fixture with `GM-Realm` and `Officer-Realm` (initially with no seasons in common).
2. `GM-Realm` creates a season, renames it, then creates and archives a second one.
3. Assert `Officer-Realm`'s local season list and active season match `GM-Realm`'s after normal digest delivery, without `Officer-Realm` creating anything locally.
4. Simulate `Officer-Realm` being offline during the archive step, then reconnect it; assert it catches up to the current catalog on reconnect.

**Run**: `tests/integration/season_catalog_sync_spec.lua`

## Scenario 3 — Visible synchronization status (User Story 3)

1. Start a client where `OperationalPolicy` has never been adopted; change the Pre-Dibs mode setting; assert the officer-facing status explicitly reports "policy not active" rather than silently no-op-ing.
2. Simulate a received envelope whose `protocol.major` does not match the local `MAJOR`; assert the rejection is recorded and retrievable as a distinguishable "version mismatch" status rather than a generic silent drop.

**Run**: covered by unit assertions alongside `tests/unit/season_catalog_spec.lua` and existing `OperationalPolicy`/`SyncV2` specs; see `tasks.md` for the exact new assertions.

## Full regression

After implementing all three scenarios, run the full suite and confirm no regressions:

```powershell
$files = Get-ChildItem -Path tests -Recurse -Filter '*_spec.lua' | ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1).Replace('\','/') }
$env:DIBS_TEST_FILES = $files -join ';'
npx.cmd --yes fengari tests/run.lua
```

Expected: all tests pass (0 failed), including the new specs above.

## Validation record

- 2026-09-22: focused feature validation passed **14 tests in 3 files**:
	`award_proposal_relay_spec.lua`, `season_catalog_spec.lua`, and
	`season_catalog_sync_spec.lua`.
- 2026-09-22: complete Fengari validation passed **588 tests in 133 files with 0
	failures**.
- 2026-09-22: the addon source was deployed with `scripts/deploy.ps1` for local
	Retail smoke testing.
- Automated validation is complete. The remaining release gate is T026: a real
	one-guild, two-raid-group Retail session covering relay, season propagation,
	and status banners.
