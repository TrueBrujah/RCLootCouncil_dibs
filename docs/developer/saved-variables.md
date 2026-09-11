# SavedVariables and compatibility

The TOC declares one persisted root: `RCLootCouncil_dibsDB`. The current root shape is:

```lua
RCLootCouncil_dibsDB = {
  schemaVersion = 6,
  guilds = { [guildKey] = <DibsGuildDB> },
}
```

Legacy flat roots are wrapped into a guild bucket during `Core.lua` initialization. Runtime code uses `Dibs.db`; `_G.DibsDB` remains a compatibility alias for the active guild bucket. The guild schema currently reports version 6, with versioned reconciliation and character-eligibility sub-stores.

Persisted names include `RCLootCouncil_dibsDB`, `guilds`, `currentSeasonId`, `rankRules`, `ledger`, `preDibs`, `reconciliation`, `characterEligibility`, `profiles`, `backups`, `backupRetention`, `pendingRestores`, `pendingImports`, `auditLog`, `sync`, and `settings`. They are compatibility surfaces. A rename requires a migration, a version bump, tests for old data, and a documented alias. Do not rename them for style alone.

Backups are bounded snapshots with a configurable retention (default 5, maximum 25). Import/export is versioned and preview-first; applying a package or restoring a snapshot is explicit and audited. No live loot candidates, votes, or item transfers belong in SavedVariables or sync payloads.
