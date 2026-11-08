# Research: Unified seasonal raid lifecycle

**Date**: 2026-11-07
**Scope**: Planning only. No production implementation or in-game behavior is claimed as validated by this document.

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

**Decision**: Record the player's requested participation path separately from the officer-approved seasonal status. A Core Raider request means intent to raid Thursday progression. The player begins as Raider/candidate; promotion to Core Raider is a manual, audited officer decision in the first release. Promotion criteria are configurable and versioned per season.

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

## Unresolved for implementation, not blocking the product spec

- Exact Core Raider evidence threshold and attendance capture method. Initial UI/configuration supports a versioned criterion and manual officer decision only.
- Exact no-guild-rank policy. Must be an explicit season choice before the first such participant can be activated; default is fail closed.
- The client cannot verify offline character ownership; declarations remain explicit and officer-reviewable.
- The season's scheduled raid time uses the user's local time in the client. A provided time-zone label is descriptive unless the addon has a validated conversion source.
