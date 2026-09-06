# Architecture

## Modules

### Core
Owns initialization, event dispatch, configuration, protocol/version constants, and module registration. It routes runtime events through the optional Ace3 adapter when AceEvent is available, with the native frame dispatcher retained for standalone operation.

### Ace3Adapter
Capability-probes AceComm, AceSerializer, AceEvent, AceTimer, AceConfig, and AceConfigDialog through `LibStub`. It does not own business rules or persistence. AceComm/AceSerializer carry logical recovery messages and provide fragmentation; the legacy compact addon-message encoding remains available when Ace3 is absent. AceEvent/AceTimer register runtime events and one bounded roster recovery retry. AceConfig registers the existing Dibs options table. Dibs never creates an AceDB database and continues to own `RCLootCouncil_dibsDB` and its versioned migrations.

### Seasons
Owns active season and seasonal configuration.

### RankRules
Maps guild rank identifiers to season allocation rules.

### Ledger
Owns append-only authoritative transactions and balance derivation.

### PreDibs
Owns advance reservation/request lifecycle, per-season `WILD_OPEN` and `ENCOUNTER` policies, request revisions, immutable origin metadata, validation context, normalized difficulty, and delivery acknowledgement metadata. Active request identity includes player, item, season, and difficulty. Mode changes validate future requests only and never rewrite ledger or request history.

PreDibs also owns explicit player-recorded Great Vault acquisition records. They are display-only ownership records (`VAULT`, item, difficulty, timestamp), never synchronize as live loot, never alter request status, and never append or consume ledger state.

### LootPipeline
Owns shared loot-item processing entry points so different adapters (for example Encounter Journal and Developer Mode) converge on one Request Dib processing path instead of duplicating business logic.

### Permissions
Selects authority for each protected action. Dibs administration always requires the current guild master or a guild officer verified from the guild roster, in both standalone and RCLootCouncil modes. The configured installation mode is `AUTO`, `STANDALONE`, or `RCLootCouncil`; an RCLootCouncil failure never expands Dibs administrative rights. RCLootCouncil's verified Master Looter may finalize a qualifying DIB award, which is the only loot-role exception and consumes a Dib through the protected finalization path.

Legacy administrator appointment and revocation events remain as historical data only. Canonical identity prefers a player GUID and retains normalized `Name-Realm` metadata. Council membership, raid leader, raid assistant, and Master Looter status do not grant Dibs administration; a player who is also the guild master or officer retains that guild authority.

### ProtectedActions
Owns the authorization-before-validation acceptance boundary for authoritative mutations. Slash commands, UI actions, synchronization input, and integration callbacks submit commands through this façade instead of writing domain state directly. Decisions include stable authority, availability, action, actor, and reason fields for diagnostics and tests.

### Sync
Owns bounded, revision-aware Pre-Dib recovery messages. `HELLO`, `MANIFEST`, `FETCH`, transfer messages, and `REQUEST_ACK` carry request/protocol data only; inbound records validate owner identity and cannot create or overwrite fulfillment.

### RaidRelay
Owns local player-visible state distribution and authorized, informational raid reminders. Reminders never create requests or mutate the ledger.

### RaidPrompts
Owns the player-local raid-entry prompt preference and session deduplication. Prompts require explicit acceptance before Adventure Guide navigation and defer/revalidate while in combat.

### EncounterJournalAdapter
Adds supported UI integration without placing business logic in Blizzard UI hooks. Wild Open requests use the selected Adventure Guide difficulty; Encounter requests use verified `GetInstanceInfo` raid difficulty even if the Journal selection differs. Acquired Vault items are shown as `Acquired`.

### DeveloperModeAdapter
Provides local-only test injection into Dibs using slash commands, with explicit test contexts and no RCLootCouncil modification.

### RCLootCouncilAdapter
Capability-probes the optional RCLootCouncil AceAddon without force-loading it. It distinguishes `absent`, `operational`, and `degraded`, and re-reads Master Looter identity for every protected action.

When availability is `operational`, the adapter verifies the current RCLootCouncil Master Looter only for loot-session finalization. Dibs administration still uses the verified guild GM/officer policy. When availability is `degraded` or `absent`, standalone Dibs administration remains available to the verified guild GM/officers; no RCLootCouncil or raid role is promoted to Dibs authority.

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

`src/` is the packaged addon root. `RCLootCouncil_dibs.toc` loads `libs/Ace3.toc` before Dibs source modules, then `Core.lua`, `locales/enUS.lua` as the built-in fallback, and `locales/frFR.lua` as a locale-specific override. RCLootCouncil is an optional dependency; embedded libraries may instead be supplied by another loaded addon through `LibStub`. Localization uses the addon namespace directly so it remains available without RCLootCouncil/AceLocale.

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

## Developer Mode boundary

Developer Mode injection is local-only and test-only:

- test contexts are marked `isTest = true`,
- test requests do not append production ledger transactions,
- test requests do not emit production chat announcements,
- test flows do not require raid/master-looter authority,
- test flows must not modify RCLootCouncil source or runtime authority behavior.
