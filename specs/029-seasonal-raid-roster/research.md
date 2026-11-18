# Research: Unified seasonal raid lifecycle

**Date**: 2026-11-07
**Scope**: Code-path research for the current implementation. Automated tests listed later are local evidence; in-game behavior is not claimed as validated here.

## Decisions

### Canonical season identity

**Decision**: Use one functional `seasonId` for the raid season. Keep season catalog, enrollment, rank allocation, and ledger records in their current owning modules when separation helps bounded transfers, but every record and activation manifest references the same canonical ID.

**Rationale**: The current feature has separate Dibs season and seasonal roster identities, which makes operators manually link records and can activate incoherent state. Domain ownership remains useful; duplicate identity is not.

**Alternatives considered**: Move every field into one SavedVariables object (large transfers and ownership coupling); keep independent IDs with a manual link (easy mismatch). Both rejected.

### Draft and explicit activation

**Decision**: Creating a season or opening registration makes a draft/registration state only. Explicit activation requires a reviewed preview and publishes the active season manifest. Activation is idempotent and visible only after all required revisions are committed.

**Rationale**: Signup must not mutate Dibs balances, and incomplete activation must not leave a partial active season.

**Alternatives considered**: Activate on season creation or registration close; rejected because preparation and allocation review are incomplete then.

### Enrollment, participation path, and Core

**Decision**: Record the player's requested participation path separately from the officer-approved seasonal status. Following the approved 2026-11-15 UI revision, names, descriptions and raid days come from the guild's published season; the initial Thursday/Core Raider example is not universal policy. Persisted path IDs remain compatible. Promotion is still a manual, audited officer decision in the first release; criteria are configurable and versioned per season.

**Rationale**: The client has no trustworthy automatic evidence for punctuality, mechanics, DPS/HPS, or helping guildmates. A manual decision avoids claiming that the addon measured those things. AotC is the requested guild label for Raider, not a separate Core state.

**Alternatives considered**: Automatically promote after a hard-coded number of Thursdays; rejected until attendance source and counting rules are agreed. Treat Core request as immediate Core status; rejected because intent is not approval.

### Season-scoped rules

**Decision**: Publish versioned raid rules and participation definitions inside each season. Keep human-readable policy separate from machine-enforced settings. A new revision affects new decisions and the current publication; historical records retain their recorded revision/snapshot.

**Rationale**: The user wants rules adjustable season by season, not embedded permanently in code. Text-only rules cannot be presented as mechanically enforced.

**Alternatives considered**: Global fixed rules or editable text with no history; rejected.

### Allocation and reconciliation scope

**Decision**: Keep allocations configurable by WoW guild rank for each season, as required by the project constitution. Gate the participant set by the approved seasonal roster and count each approved person/Main once. Add an explicit per-season policy for participants with no guild rank (for example, a configured allocation or exclusion); never infer a rank. Core/Raider does not change allocation unless a future explicit season rule says so.

**Rationale**: Reconciliation must not scan the full 900-character guild roster for a 20–60 person raid season. The expected cost should follow the approved cohort.

**Alternatives considered**: Allocate every guild character, or derive Dibs allocation from Core status; rejected as inaccurate and potentially expensive.

### Three separate reconciliation workflows

**Decision**: Keep distinct operations for (1) review and merge of historical Main/Alt balances, (2) initial allocation for a new season, and (3) in-season rank/allocation drift. Each previews exact affected identities and expected ledger events before authorized apply.

**Rationale**: These operations have different sources of truth and must not be conflated. Historical account balances are not copied into a new season automatically.

**Balance decision**: When merging legacy Main/Alt balances, a GM/Officer reviews them and retains the selected Main's balance; do not sum balances. Any necessary correction is append-only and audited.

### Main/Alt identity

**Decision**: Reuse CharacterEligibility's canonical identity and review workflow. A player's Dibs belong to the person and follow approved Main changes. The selected Main for a season is a snapshot; historic item transactions retain their original character. No Battle.net/account identity is inferred.

**Rationale**: This matches the user's explicit identity and privacy requirements.

### Additive migration and historical records

**Decision**: Preserve existing Dibs seasons, seasonal roster records, enrollment IDs, transactions, revisions, and aliases. Migration is additive, idempotent, guild-scoped, and reports ambiguous roster-to-season links for officer review.

**Rationale**: Existing SavedVariables may already contain active balances and audit history; replacing or guessing links risks data loss.

### Synchronization

**Decision**: Use existing SyncV2 entity digest/detail and revision conflict mechanisms. Transfer rules/catalog, enrollment records, approved roster projection, allocations, and activation manifest as bounded entities. The activation manifest names exact revisions and content hashes; a client does not declare the season active or complete until dependencies match.

**Current code evidence**: SyncV2 defines `MAX_TRANSFERS=8`, `MAX_CHUNKS=16`, `MAX_BYTES=8192` in `src/modules/SyncV2.lua`. New season entities must fit the existing limits or use bounded per-record/page transfer. These constants are observations of current code, not an approved expansion.

### UI performance

**Decision**: Paginate/virtualize large views; use only visible/approved season records for activation and reconciliation. Keep heavy calculations out of repeated layout callbacks. Benchmark synthetic 20, 60, 500, and 1,000 record cases and report cold/warm timings.

**Rationale**: Existing user reports identify UI stalls as an operational concern. No static analysis result should be described as an in-game measurement.

## Existing architecture to verify during implementation

- `src/modules/Seasons.lua`: current Dibs season catalog and lifecycle.
- `src/modules/CharacterEligibility.lua`: canonical Main/Alt relationships and 14-day probation.
- `src/modules/Permissions.lua`: guild GM/Officer authorization.
- `src/modules/OperationalPolicy.lua` and `FeatureRegistry.lua`: feature/module gate.
- `src/modules/SyncV2.lua`: bounded digest/detail synchronization and conflict/recovery behavior.
- `src/ui/OfficerUI.lua`, `src/ui/PlayerUI.lua`: season, signup, and roster interfaces.
- `src/modules/Ledger.lua`: append-only authoritative accounting.

This list is a code-navigation map, not a claim that every current behavior satisfies the proposed contract.

## Current code trace (2026-11-07)

- `src/RCLootCouncil_dibs.toc` loads `modules/Seasons.lua` before `modules/SeasonalRoster.lua`, then `modules/SyncV2.lua` is already loaded before the roster service. `PlayerUI.lua` and `OfficerUI.lua` load after both services. The active implementations are these files in the TOC; no alternate later-loaded `SeasonalRoster` definition was found.
- `Seasons.lua` owns `db.seasons` and `db.currentSeasonId`; before this implementation pass, `Create()` always selected a new season. The new `CreateDraft()` stores an inactive season under an explicit canonical ID without changing the active season.
- `SeasonalRoster.lua` owns guild-scoped registrations, revisions, audit records and roster projection under `db.seasonalRoster`. Newly created roster seasons now use the same ID as a native Dibs draft. Existing schema-1 roster IDs are retained; Core migration adds an explicit alias record and keeps their historical `identitySeasonId` values. It does not infer a replacement ID.
- The service revises draft configuration with expected revisions, reasoned audit events and idempotent operation IDs. Season raid-rule text is stored in each immutable configuration revision, bounded to 8,000 characters, and included in the existing revision hash/sync chain. Settings copy carries description, raid-rule text, category catalog and schedule into a target draft without copying dates, identity, participants or ledger data. Permission actions distinguish season creation, draft editing, registration, enrollment review, rule catalog publication, allocation publication, activation and reconciliation. Activation commits the approved cohort's initial allocations atomically with a separate dependency-bound manifest; active allocation drift uses a separate append-only reconciliation operation.
- Public roster composition uses the same bounded filtered projection for its visible rows and counts; linked Main/Alt rows remain visible but count once toward people/class/armor/role composition. Signup and read-only roster routes have focused PlayerUI tests.
- `CharacterEligibility.lua` remains the owner of Main/Alt identity and its season-scoped review state. `RankRules.lua` owns local per-season, per-native-guild-rank working values; a GM/Officer publishes a validated snapshot into an immutable, synchronized seasonal revision after registration closes. `Ledger.lua` owns balances and append-only accounting. Activation initializes only approved seasonal Main identities through the existing canonical ledger writer; reconciliation appends corrections without resetting spent balance.
- `SyncV2.lua` owns the bounded message protocol. Roster configuration/enrollment, immutable `SEASON_IDENTITY`, published allocation snapshots, canonical ledger events and `SEASON_ACTIVATION` manifests remain separate entities. The compact manifest wire form expands before service validation; dependency mismatch preserves the prior current season and remains recoverable through bounded digest/detail requests.
- `FeatureRegistry.RequireEnabled("seasonalRoster")` is checked by the service store boundary. While disabled, reads and writes are unavailable to the service UI, incoming revisions fail before mutation, and the SavedVariables subtree remains intact for re-enable.

### Initial focused evidence — 2026-11-09 (historical)

The initial seasonal-roster selection passed **39 tests across 12 files**, including activation preview dependency binding, allocation snapshot publication and replay, forged snapshot rejection, two-client SyncV2 adoption, Player/Officer UI behavior, migration, and module gating. It did not verify atomic activation or full season reconciliation. The final automated evidence is recorded in `quickstart.md`; Retail behavior remains unvalidated because no Retail client matrix was run.

## Unresolved for implementation, not blocking the product spec

- Exact Core Raider evidence threshold and attendance capture method remain undefined; no attendance or performance evidence is inferred. Manual officer review/promotion is implemented as an explicit seasonal decision and does not claim an automated attendance criterion.
- Exact no-guild-rank policy. Must be an explicit season choice before the first such participant can be activated; default is fail closed.
- The client cannot verify offline character ownership; declarations remain explicit and officer-reviewable.
- The season's scheduled raid time uses the user's local time in the client. A provided time-zone label is descriptive unless the addon has a validated conversion source.
