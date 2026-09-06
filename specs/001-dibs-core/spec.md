# Feature Specification: Independent Dibs Core

**Feature Branch**: `001-dibs-core`

**Created**: 2026-09-03

**Status**: Draft

**Input**: User description: "Create the first feature of the Dibs World of Warcraft Retail addon: the independent Dibs Core."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configure Seasonal Rank Allocations (Priority: P1)

As a guild master, I can create a season, select the active season, and define Dib allocations per guild rank so the guild has clear seasonal Dib rules before loot decisions.

**Why this priority**: Without season and rank allocation policy, no reliable Dib accounting can be established for any player.

**Independent Test**: A guild manager can create a season, mark it active, set allocation values for multiple ranks, and retrieve the same configuration consistently.

**Acceptance Scenarios**:

1. **Given** no active season exists, **When** a guild master creates a new season and activates it, **Then** the season is available as the authoritative allocation context.
2. **Given** an active season, **When** a guild master sets different allocation values for rank 1 and rank 2, **Then** those values are stored as configurable policy data and can be read back unchanged.

---

### User Story 2 - Maintain Player Seasonal Balances from Ledger (Priority: P1)

As an officer, I can record authoritative Dib transactions and view each player's seasonal remaining balance derived from those transactions.

**Why this priority**: The core value of Dibs is trustworthy accounting, which depends on append-only transactions and derived balances.

**Independent Test**: For one player in an active season, creating allocation, grant, use, and refund transactions results in a deterministic remaining balance and visible transaction history.

**Acceptance Scenarios**:

1. **Given** a player has a seasonal allocation, **When** a sequence of valid Dib transactions is recorded, **Then** remaining balance is derived from ledger history rather than manual overwrite.
2. **Given** a previously recorded transaction, **When** the same transaction identifier is processed again, **Then** ledger state remains unchanged and no duplicate accounting impact occurs.

---

### User Story 3 - Correct Errors with Compensating Transactions (Priority: P2)

As an authorized officer or guild master, I can correct Dib mistakes by adding compensating transactions without deleting or editing historical entries.

**Why this priority**: Auditability requires immutable history and explicit corrections instead of silent rewrites.

**Independent Test**: A mistaken Dib use can be offset with an allowed compensating action while preserving the original row and a traceable reason.

**Acceptance Scenarios**:

1. **Given** an incorrect authoritative transaction exists, **When** an authorized actor creates a correction, **Then** the original transaction remains intact and the correction is represented as a new transaction.
2. **Given** an administrative correction is recorded, **When** history is reviewed, **Then** actor identity and correction reason are present for audit.

---

### User Story 4 - Preserve History Across Rank Changes (Priority: P2)

As an officer, I can update a player's current guild rank during an active season without rewriting historical allocations or historical transactions.

**Why this priority**: Rank changes are operationally common and must not compromise historical accuracy.

**Independent Test**: A player's rank is changed after prior activity; earlier transactions retain the original rank context while future transactions use the updated rank context.

**Acceptance Scenarios**:

1. **Given** a player has existing seasonal transactions, **When** their guild rank changes, **Then** prior transactions retain historical rank-at-transaction-time data.
2. **Given** a player rank change is applied, **When** new transactions are created later, **Then** they reflect the current rank without retroactively changing earlier records.

### Edge Cases

- Duplicate transaction delivery for the same transaction identifier.
- Missing required transaction fields during submission.
- Transaction submitted for a non-existent season.
- Transaction submitted for a player without a valid player identity.
- Administrative correction submitted without a reason.
- Allocation rule update during an active season after prior player activity.
- Player rank promotion/demotion during an active season after existing ledger history.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support creation and management of seasons, including one active season used for authoritative Dib accounting.
- **FR-002**: System MUST support configurable Dib allocation values per guild rank for each season.
- **FR-003**: System MUST NOT hard-code rank allocation values in business policy.
- **FR-004**: System MUST maintain player seasonal state that includes seasonal allocation context and derived remaining Dib balance.
- **FR-005**: System MUST calculate remaining Dib balances from an append-only ledger of authoritative transactions.
- **FR-006**: System MUST preserve all historical transactions; existing transactions MUST NOT be deleted or modified to correct errors.
- **FR-007**: System MUST support compensating correction transactions for authoritative mistakes.
- **FR-008**: System MUST require each authoritative transaction to include a unique transaction identifier, timestamp, season identifier, player GUID, transaction action/type, and Dib quantity delta.
- **FR-009**: System MUST include player name where applicable, guild rank at transaction time, and actor/officer identity where applicable for authoritative transactions.
- **FR-010**: System MUST require an explicit reason for administrative change transactions.
- **FR-011**: System MUST support optional related item information on transactions when relevant.
- **FR-012**: System MUST support the initial transaction types: SEASON_ALLOCATION, DIB_GRANTED, DIB_USED, DIB_REFUNDED, DIB_REVOKED, and DIB_ADMIN_ADJUSTMENT.
- **FR-013**: System MUST provide transaction creation and transaction validation rules prior to authoritative acceptance.
- **FR-014**: System MUST apply authoritative transactions idempotently, preventing duplicate accounting effects from repeated delivery.
- **FR-015**: System MUST persist Dib data in versioned SavedVariables with migration behavior that preserves historical audit data.
- **FR-016**: System MUST provide a permission foundation covering Player, Officer, and GM contexts. Authoritative Dibs actions MUST require a verified guild Officer or GM; legacy configurable Dibs Administrator appointments MUST NOT authorize a non-officer.
- **FR-017**: System MUST ensure rank changes during an active season do not silently rewrite historical allocations or historical transactions.
- **FR-018**: System MUST keep promotion/demotion allocation-adjustment policy open for a later dedicated specification.
- **FR-019**: System MUST remain independent from RCLootCouncil, Encounter Journal integration, raid loot session logic, and cross-raid synchronization for this feature scope.
- **FR-020**: System MUST define stable core APIs that later features can use for Pre-Dibs, Drop-Dibs, optional integrations, multi-raid synchronization, audit/history surfaces, and test mode workflows.

### Key Entities *(include if feature involves data)*

- **Season**: Defines a time-bounded Dib cycle and active-state context used for authoritative accounting.
- **Rank Allocation Rule**: Configuration mapping a guild rank to a Dib allocation value within a season.
- **Player Seasonal State**: Player-level view that ties identity to season context and derived balance.
- **Dib Transaction**: Immutable authoritative ledger row containing identity, time, action/type, quantity delta, and audit metadata.
- **Permission Role Context**: Authorization context used to evaluate whether Player, Officer, or GM can perform a requested authoritative action. Loot and raid roles remain separate from Dibs administration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of authoritative Dib balance outputs for sampled players match the sum of their recorded seasonal transaction deltas.
- **SC-002**: 100% of replay attempts for identical transaction identifiers produce no duplicate accounting impact.
- **SC-003**: 100% of correction workflows preserve the original mistaken transaction and add a compensating transaction with traceable actor and reason metadata.
- **SC-004**: 100% of sampled historical transactions remain unchanged after player rank updates during the same active season.
- **SC-005**: 100% of core Dib operations in this feature execute without requiring RCLootCouncil, Encounter Journal, raid loot-session context, or cross-raid synchronization context.

## Assumptions

- Guild leadership and officers will manage season setup before relying on Dib balances for decisions.
- Player identity is primarily anchored by player GUID; player name is supplemental where applicable.
- Core feature scope excludes live loot-session UX decisions and network synchronization behavior, which will be specified later.
- Promotion/demotion allocation-adjustment policy is intentionally deferred to a later specification and must not be implicitly hard-coded in this feature.
