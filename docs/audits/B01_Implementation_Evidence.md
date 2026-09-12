# B01 Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B01_START_COMMIT`: `a82fa9d50ce05b2750c513803b204945d080e226`
- `B01_CHECKPOINT_COMMIT`: `a82fa9d50ce05b2750c513803b204945d080e226`
- `B01_RESULT_COMMIT`: `e00b387c301724282d1e14da2d9d4e9d4bab5e1b`

The B00 evidence commit was verified as the exact committed project checkpoint
before B01. Existing uncommitted user work (`docs/RC_OPTIONS.md` and
`RCLootCouncil_dibs.code-workspace`) was neither staged nor changed.

## Files changed

- `src/Core.lua` — replaces optimistic SavedVariables defaulting with a staged,
  validated persistence boundary.
- `docs/developer/saved-variables.md` — documents the additive recovery
  metadata and startup states.
- `tests/integration/persistence_recovery_spec.lua` — B01 validation,
  migration, recovery, backup, and atomic-failure coverage.
- `tests/helpers/load_addon.lua` — lets tests provide a non-table saved-variable
  root for wrong-root recovery coverage.
- `tests/integration/predibs_migration_spec.lua` — verifies preserved historical
  request fields rather than Lua table identity, because staged commit correctly
  replaces the migrated table graph atomically.

## SavedVariables schema and migration boundary

The root schema remains **6** and the guild schema remains **6**. B01 adds the
backward-compatible root field `persistenceRecovery`:

```lua
persistenceRecovery = {
  version = 1,
  backups = {},       -- at most 3 startup recovery snapshots
  quarantine = {},    -- at most 25 malformed original values
  nextBackupId = 1,
}
```

Startup now validates the root, guild map, active guild version, settings,
seasons, ledger/history, Pre-Dibs, profiles when present, permissions, sync,
backups, audit data, reconciliation, eligibility, and migration metadata before
they are indexed or migrated. Supported flat roots and guild versions 1–6 are
migrated with a detached staged copy, then committed only after success.

## Backup and quarantine strategy

- A structural migration or recovery creates one deterministic, bounded root
  recovery snapshot before commit; normal validated startup creates none.
- Malformed subtrees are copied to `persistenceRecovery.quarantine` with scope
  and reason, then only the affected runtime subtree is rebuilt.
- Valid ledger transactions, transaction IDs, player-name evidence, Pre-Dib
  requests, and settings survive migration unchanged by value.
- If staged migration fails, the original SavedVariables root is left untouched
  and the session enters read-only degraded recovery mode.

## Future-schema behavior

An unsupported future root schema or active-guild version is not downgraded,
rewritten, or partially migrated. The original SavedVariables table remains in
place. `Dibs.GetPersistenceStatus()` reports `FUTURE_UNSUPPORTED`, sets
`readOnly = true`, and gives an actionable update diagnostic while an isolated
in-session database permits degraded startup where possible.

The possible status values are `VALID`, `MIGRATABLE`, `RECOVERABLE_INVALID`, and
`FUTURE_UNSUPPORTED`.

## Tests executed

Focused B01/B00 regression:

```powershell
$env:DIBS_TEST_FILES = 'tests/integration/persistence_recovery_spec.lua;tests/contract/b00_architecture_contract_spec.lua'
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **18 passed, 0 failed (2 files)**.

Broader suite, executed once after the final source change:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter '*_spec.lua' | ForEach-Object { $_.FullName.Substring($PWD.Path.Length + 1).Replace('\','/') } | Sort-Object
$env:DIBS_TEST_FILES = ($files -join ';')
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **244 passed, 0 failed (56 files)**.

The focused contracts prove valid-current handling; schemas 1–6; wrong root;
wrong settings and ledger types; truncation; nil optional fields; future schema;
repeat migration; backup creation; quarantine; staged migration failure; and
preservation of `legacy-tx-1` and `legacy-request-1` identifiers/history.

## Known limitations and scope confirmation

B01 validates and migrates only the active guild bucket semantically at startup;
invalid inactive guild buckets are preserved as quarantined recovery evidence
rather than chosen as any authority source. This is intentional and prevents
automatic canonical selection of legacy data.

No B02a+ work was implemented: no governance/GuildPolicy state, coordinator,
ledger epoch, distributed synchronization, protocol-V2 activation, or
RCLootCouncil integration behavior was added. B01 only establishes the
defensive persistence boundary required before those batches.

This evidence is committed separately because a Git commit cannot contain its
own result hash. The result hash above identifies the B01-only implementation
commit.
