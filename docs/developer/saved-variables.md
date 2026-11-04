# SavedVariables and compatibility

The TOC declares two account-wide stores and one per-character local root.
Production guild data is in `RCLootCouncil_dibsDB`; isolated developer fixtures
are in `RCLootCouncil_dibsSandboxDB`. The local root is
`RCLootCouncil_dibsLocalDB`. Sandbox data is never a production guild bucket.

```lua
RCLootCouncil_dibsDB = {
  schemaVersion = 6,
  guilds = { [guildKey] = <DibsGuildDB> },
  persistenceRecovery = { version = 1, backups = {}, quarantine = {} },
}
```

For guilded characters, `guildKey` combines the guild name with the guild's
home realm reported by `GetGuildInfo("player")`; the character realm is used
when that API value is unavailable. This keeps members of a cross-realm guild
in the same sync scope. Existing buckets created with a character-realm key
are retained and are not automatically merged into the guild-home bucket.

The local root is intentionally small and never synchronized:

```lua
RCLootCouncil_dibsLocalDB = {
  notifications = { enabled = true, seen = { [eventId] = timestamp } },
  settings = {
    language = "AUTO",
    debugLevels = { all = 1 },
    developerModeEnabled = false,
    ejKnownSubCategories = {},
    ejBlockedSubCategories = {},
    minimapButtonShown = true,
    minimapButtonAngle = nil, -- optional degrees (0-360) around the minimap; default 135
    minimapButtonScale = nil, -- optional 0.5-2.0; default 1.0
  },
}
```

Notification replay identities, language, diagnostics, Developer Mode,
minimap icon preferences, and
Adventure Guide discovery state are personal to the character and never
synchronized. Older values found in the guild `settings` subtree are migrated
to this local root and removed from the guild copy.

Version 0.8.8 adds local `requestDelivery[guildKey]` with `pending`, `statuses`
and `reminders`. It is character-local retry/receipt/snooze metadata, never a guild
snapshot. Pending private request operations are bounded to 128 and persist
across reload; a matching acknowledgement removes an operation. Due reminders
are throttled and deduplicated using the existing notification mechanism: one per
request/hour, at most three per minute across the character's current guild queue.
The persisted `lastReminderBatchAt` and rotating `reminderCursor` prevent reload
bursts and let later due requests receive their reminder fairly.

Guild `disputes.version=2` is an additive migration preserving existing request
IDs/statuses, evidence, replies, timeline and correction map. New fields are
`revision`, `assignedTo`, `followUpAt`, `deliveryAuthority`; Closed/Archived are
additive serialized statuses. No terminal dossier or timeline is silently pruned:
new writes fail at 500 dossiers / 120 audit events. Previously removed history
cannot be recovered by this migration. Shared replicas contain a full officer
dossier or an explicit safe owner body and never apply accounting by themselves.

Legacy flat roots are wrapped into a guild bucket during `Core.lua` initialization.
Runtime code uses `Dibs.db`; `_G.DibsDB` remains a compatibility alias for the
active guild bucket. The guild schema currently reports version 7 (the root wrapper remains version 6),
with versioned reconciliation and character-eligibility sub-stores.

Guild `ledgers[ledgerId]` holds each ledger's separate accounting state.
`activeLedgerId` selects the local active view and `ledger` remains its legacy
compatibility pointer. Do not merge different ledgers' transactions or treat a
view change as a balance transfer. Independent Raid uses a separate ephemeral
session context, not an extra production guild ledger.

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

Persisted names include `RCLootCouncil_dibsDB`, `guilds`, `persistenceRecovery`, `currentSeasonId`, `rankRules`, `ledger`, `preDibs`, `reconciliation`, `characterEligibility`, `governance`, `profiles`, `backups`, `backupRetention`, `pendingRestores`, `pendingImports`, `auditLog`, `sync`, and `settings`. They are compatibility surfaces. A rename requires a migration, a version bump, tests for old data, and a documented alias. Do not rename them for style alone.

B12 adds local preference fields but no guild synchronization fields. Requests, history
projections, context-menu state, route state, and release evidence remain
runtime or documentation concerns. The existing developer sandbox store remains
separate from `RCLootCouncil_dibsDB`; its bounded validation and production
isolation are documented in the developer testing and release evidence records.

Backups are bounded snapshots with a configurable retention (default 5, maximum 25). Import/export is versioned and preview-first; applying a package or restoring a snapshot is explicit and audited. No live loot candidates, votes, or item transfers belong in SavedVariables or sync payloads.

Restoring a snapshot never rolls back state shared with the guild. For a `full`
restore, `governance`, `operationalPolicy` and `seasonCatalog` (with `seasons` and
`currentSeasonId`) keep the local copy when its revision is higher, or when the
revision is equal but the hash differs; each ledger in `ledgers` keeps the local copy
when its `canonical.nextSeq` is higher, or equal with a different root hash or more
transactions. `sync` state is always kept. A `guild` restore skips `seasons` once a
catalog revision has been published. The kept parts are returned in
`preview.keptLocal`, and sync catches up the remaining gap.

## Hidden local factory reset

`/dibs factoryreset` (not listed in `/dibs help`) arms a 60-second window;
`/dibs factoryreset CONFIRM` then sets `RCLootCouncil_dibsDB`,
`RCLootCouncil_dibsSandboxDB`, `RCLootCouncil_dibsLocalDB` and the legacy `DibsDB`
to `nil` (again at `PLAYER_LOGOUT`) and reloads the UI, so the client starts as a
fresh install. When any guild has Officer backups (`db.backups`), the main root is
instead a fresh root holding only `preservedBackups[guildKey] = { backups,
backupRetention }`; on the next load of that guild they are merged back into
`db.backups` (by `snapshotId`) and removed from `preservedBackups`. It is refused in
combat, is local only, sends no sync traffic and does not touch RCLootCouncil data or
other members. Per-character local data of other characters is kept until the reset
is run on them; later guild sync may restore shared guild ledgers.
