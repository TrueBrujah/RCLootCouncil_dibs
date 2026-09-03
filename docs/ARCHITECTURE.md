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
Selects exactly one authority for each protected action. A compatible, operational RCLootCouncil instance delegates authority exclusively to its current Master Looter. Only when RCLootCouncil is absent or disabled does standalone policy authorize the guild master and explicitly appointed Dibs administrators. Loaded but incompatible or unverifiable RCLootCouncil state fails closed.

Standalone administrator membership is derived from append-only appointment and revocation events. Canonical identity prefers a player GUID and retains normalized `Name-Realm` metadata. Guild officer, raid leader, and raid assistant roles do not implicitly grant Dibs authority.

### ProtectedActions
Owns the authorization-before-validation acceptance boundary for authoritative mutations. Slash commands, UI actions, synchronization input, and integration callbacks submit commands through this façade instead of writing domain state directly. Decisions include stable authority, availability, action, actor, and reason fields for diagnostics and tests.

### Sync
Owns officer backbone synchronization, deduplication, delta/full sync, revision/digest logic, and validation.

### RaidRelay
Owns local player-visible state distribution for the current raid group.

### EncounterJournalAdapter
Adds supported UI integration without placing business logic in Blizzard UI hooks.

### RCLootCouncilAdapter
Capability-probes the optional RCLootCouncil AceAddon without force-loading it. It distinguishes `absent`, `operational`, and `degraded`, re-reads Master Looter identity for every protected action, and never falls back to standalone after a present-integration error or denial.

The adapter observes compatible local Ace messages and maps a valid `RCMLAwardSuccess` event to one idempotent finalized-award command. It does not replace candidate getters, write RCLootCouncil registries or SavedVariables, or inject RCLootCouncil wire messages. Candidate status is a read-only projection; an explicit local Dibs display is the compatibility fallback.

### AuditUI
Presents history appropriate to the current user's permissions.

## Authority model

Player requests are proposals.

Authoritative committed transactions require validation by an authorized actor or authority mechanism.

The ledger, not the UI adapter, is the system of record.

Authorization only permits an action to proceed. Domain validation still decides whether a Dib can be consumed, a Pre-Dib can be fulfilled, or a configuration mutation is valid. A successful finalized award is indexed by `awardRef`, so replay returns the existing result without appending another transaction.

## Compatibility boundary

RCLootCouncil does not publish a generic permission API for Dibs actions. The supported Retail 3.x compatibility surface is therefore deliberately small and capability-detected:

- an AceAddon instance named `RCLootCouncil`,
- `enabled == true`,
- a canonicalizable `masterLooter`,
- Ace message registration when available,
- the local `RCMLAwardSuccess` message for finalized awards.

Synthetic contract fixtures cover compatible 3.x-shaped surfaces, absent/disabled states, malformed state, exceptions, and an unknown incompatible surface. Version labels alone never establish compatibility. `## OptionalDeps: RCLootCouncil` supplies load ordering when installed, while `ADDON_LOADED`-safe initialization handles late availability. Standalone startup does not require LibStub or Ace libraries.

## Packaging and localization

`src/` is the packaged addon root. `RCLootCouncil_dibs.toc` loads `Core.lua`, then `locales/enUS.lua` as the built-in fallback and `locales/frFR.lua` as a locale-specific override, before domain and UI modules. Localization uses the addon namespace directly so it remains available without RCLootCouncil/AceLocale.

## Combat safety

Combat lockdown restricts protected UI and secure actions, not ordinary Lua table or SavedVariables work. Ledger-only and other non-UI domain work therefore remains synchronous in combat. Creation, visibility, anchoring, or reconfiguration that can touch a protected frame is queued and resumed after `PLAYER_REGEN_ENABLED`. The integration uses event observation rather than function replacement to reduce taint risk.

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
