# SavedVariables and compatibility

The TOC declares one persisted root: `RCLootCouncil_dibsDB`. The current root shape is:

```lua
RCLootCouncil_dibsDB = {
  schemaVersion = 6,
  guilds = { [guildKey] = <DibsGuildDB> },
  persistenceRecovery = { version = 1, backups = {}, quarantine = {} },
}
```

Legacy flat roots are wrapped into a guild bucket during `Core.lua` initialization. Runtime code uses `Dibs.db`; `_G.DibsDB` remains a compatibility alias for the active guild bucket. The guild schema currently reports version 6, with versioned reconciliation and character-eligibility sub-stores.

Startup validates the root and active guild bucket before indexing persisted
subtrees. `persistenceRecovery` is additive root metadata containing at most
three startup safety snapshots and at most 25 quarantined malformed values.
It is written only for a structural migration or recovery; normal validated
startup does not create another backup. Valid ledger transactions, historical
transaction IDs, player-name evidence, and Pre-Dib records are copied unchanged.

The startup status returned by `Dibs.GetPersistenceStatus()` is one of `VALID`,
`MIGRATABLE`, `RECOVERABLE_INVALID`, or `FUTURE_UNSUPPORTED`. A future root or
active-guild schema is never downgraded or rewritten: the addon uses an
in-session read-only/degraded database and reports an update diagnostic. Invalid
subtrees are placed in `persistenceRecovery.quarantine` before only the affected
runtime subtree is rebuilt. A failed staged migration leaves the original
SavedVariables root unchanged.

Persisted names include `RCLootCouncil_dibsDB`, `guilds`, `persistenceRecovery`, `currentSeasonId`, `rankRules`, `ledger`, `preDibs`, `reconciliation`, `characterEligibility`, `profiles`, `backups`, `backupRetention`, `pendingRestores`, `pendingImports`, `auditLog`, `sync`, and `settings`. They are compatibility surfaces. A rename requires a migration, a version bump, tests for old data, and a documented alias. Do not rename them for style alone.

Backups are bounded snapshots with a configurable retention (default 5, maximum 25). Import/export is versioned and preview-first; applying a package or restoring a snapshot is explicit and audited. No live loot candidates, votes, or item transfers belong in SavedVariables or sync payloads.
