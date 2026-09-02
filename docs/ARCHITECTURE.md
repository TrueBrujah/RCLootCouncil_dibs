# Architecture

## Modules

### Core
Owns initialization, event bus, configuration, protocol/version constants, and module registration.

### Seasons
Owns active season and seasonal configuration.

### RankRules
Maps guild rank identifiers to season allocation rules.

### Ledger
Owns append-only authoritative transactions and balance derivation.

### PreDibs
Owns advance reservation/request lifecycle.

### Permissions
Determines player/officer/GM/Dibs-admin capabilities.

### Sync
Owns officer backbone synchronization, deduplication, delta/full sync, revision/digest logic, and validation.

### RaidRelay
Owns local player-visible state distribution for the current raid group.

### EncounterJournalAdapter
Adds supported UI integration without placing business logic in Blizzard UI hooks.

### RCLootCouncilAdapter
Consumes supported RCLootCouncil interfaces and maps local loot events to Dibs core operations.

### AuditUI
Presents history appropriate to the current user's permissions.

## Authority model

Player requests are proposals.

Authoritative committed transactions require validation by an authorized actor or authority mechanism.

The ledger, not the UI adapter, is the system of record.

## Cross-raid privacy boundary

The following may cross raid boundaries:

- Dib ledger changes
- Pre-Dib states
- finalized award history needed for accounting
- sync protocol metadata

The following may not cross raid boundaries:

- current drop events
- candidate lists
- council votes
- current RC responses
- current loot-session payloads
