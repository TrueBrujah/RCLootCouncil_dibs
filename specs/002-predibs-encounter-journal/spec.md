# Feature Specification: Pre-Dibs Encounter Journal

**Feature Branch**: `002-predibs-encounter-journal`

**Created**: 2026-09-05

**Status**: Draft

**Input**: User description: "Resume feature 002-predibs-encounter-journal. The Dibs Core is already implemented and validated. The feature must cover the standalone Pre-Dib flow, public requests and deduplication, confirmation, cancellation and fulfillment, Adventure Guide / Encounter Journal integration, a Dib button for raids only, no button for dungeons, a configurable sub-category matrix, unknown categories visible by default, optional RCLootCouncil integration, operation without RCLootCouncil, and the Dibs ledger as the authority source."

## User Scenarios & Testing

### User Story 1 - Request a Pre-Dib (Priority: P1)

As a player, I can register a Pre-Dib request for a specific supported raid item before it drops, so my intention is visible to the guild without consuming a Dib immediately.

**Why this priority**: The Pre-Dib request is the primary workflow this feature delivers and must work independently of any loot-session addon.

**Independent Test**: Create a request for a valid raid item, read it back, and confirm that it is active, tied to the current season and player, and has not created a balance-consuming ledger transaction.

**Acceptance Scenarios**:

1. **Given** an active season and public Pre-Dibs enabled, **When** a player requests a valid supported raid item, **Then** one active Pre-Dib is recorded with the item identity, player identity, season, status, and timestamps.
2. **Given** a player already has an active request for the same item and season, **When** the player requests it again, **Then** the existing request is returned and no duplicate request is created.
3. **Given** public Pre-Dibs are disabled, **When** a player submits a public request, **Then** the request is rejected with a clear reason and no state is added.

### User Story 2 - Manage the Pre-Dib Lifecycle (Priority: P1)

As an authorized actor or the owning workflow, I can confirm, cancel, and fulfill Pre-Dib requests while preserving their history and consuming a Dib only after a qualifying award is finalized.

**Why this priority**: Lifecycle state must remain trustworthy so requests cannot consume Dibs prematurely or disappear without explanation.

**Independent Test**: Move a request through confirmation, cancellation, and finalized-award fulfillment scenarios and verify each resulting state and ledger effect.

**Acceptance Scenarios**:

1. **Given** a pending request, **When** it is confirmed, **Then** it becomes active for eligibility and retains confirmation metadata.
2. **Given** an active request that does not result in an award, **When** the loot outcome is finalized for another player or cancelled, **Then** the request remains active unless an explicit cancellation rule applies.
3. **Given** a confirmed request for a player who receives the qualifying item, **When** the award is finalized, **Then** exactly one Dib consumption is appended to the authoritative ledger and the request is fulfilled.
4. **Given** a finalized award that is replayed, **When** the same award is processed again, **Then** no second ledger transaction is added and the request state does not produce a second fulfillment.

### User Story 3 - Use the Adventure Guide Safely (Priority: P1)

As a player, I can use a Dib action beside eligible raid loot in the Adventure Guide, so I can create a Pre-Dib request from the item I am viewing without seeing misleading actions for dungeons or unrelated categories.

**Why this priority**: The Adventure Guide is the main discoverable entry point for the workflow and must respect the raid-only policy.

**Independent Test**: Open raid and dungeon loot contexts with eligible, blocked, and unknown item categories and verify action visibility and submission behavior.

**Acceptance Scenarios**:

1. **Given** the Adventure Guide displays raid loot, **When** the addon recognizes a supported loot row, **Then** a localized Dib action is available according to the configured category policy.
2. **Given** the Adventure Guide displays dungeon loot, **When** loot rows are shown, **Then** no Dib action is available and direct submission is rejected.
3. **Given** a raid item belongs to a blocked category such as cosmetic, mount, pet, recipe, or housing decor, **When** the loot row is refreshed, **Then** the Dib action is hidden or disabled according to policy.
4. **Given** a raid item belongs to an unknown category, **When** the loot row is refreshed, **Then** the Dib action remains visible by default so legitimate loot is not silently suppressed.
5. **Given** the Adventure Guide UI is unavailable or changes state, **When** the addon attempts to attach its action, **Then** the addon retries or exits safely without replacing Blizzard functions or producing errors.

### User Story 4 - Configure and Announce Pre-Dibs (Priority: P2)

As an officer, I can configure the local category policy and announcement behavior, so the guild can adapt the workflow without changing authoritative accounting rules.

**Why this priority**: Guilds need operational control over visibility and communication, while these settings must remain separate from ledger authority.

**Independent Test**: Change category and announcement settings, submit a request, and verify the visible action and announcement destinations without changing the player's balance.

**Acceptance Scenarios**:

1. **Given** the recommended category policy, **When** it is applied, **Then** clearly non-Dib categories are blocked while unknown categories remain allowed.
2. **Given** public and officer announcement channels are configured, **When** a request is confirmed, **Then** announcements are sent only to available configured channels and unavailable channels do not cause an error.
3. **Given** the category policy is changed for a known sub-category, **When** loot rows are refreshed, **Then** only local action visibility changes and no ledger or historical record is rewritten.

### User Story 5 - Operate With or Without RCLootCouncil (Priority: P2)

As a guild, I can use the Pre-Dib and Adventure Guide workflow whether RCLootCouncil is installed or not, while RCLootCouncil remains an optional display and event adapter.

**Why this priority**: Dibs must remain a standalone addon and must not make accounting dependent on a third-party loot-session addon.

**Independent Test**: Execute the request and finalized-award flows with RCLootCouncil absent, then repeat with a compatible local adapter present, and compare the authoritative Dibs state.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil is unavailable, **When** a player creates and fulfills a Pre-Dib through a supported standalone flow, **Then** Dibs records the request and authoritative ledger state successfully.
2. **Given** RCLootCouncil is available, **When** it reports a compatible local loot outcome, **Then** Dibs may mirror or display the event but still owns the request history and balance calculation.
3. **Given** RCLootCouncil is unavailable or degraded, **When** the player uses the Adventure Guide action, **Then** the request path does not fail solely because the adapter is absent.

### Edge Cases

- Repeated requests for the same player, item, and season.
- Requests for invalid or missing item identities.
- No active season exists.
- Public Pre-Dibs are disabled.
- A request is cancelled, invalidated, or fulfilled and then submitted again.
- A player loses an item after creating a Pre-Dib.
- A finalized award event is delivered more than once.
- An item category is unknown, localized, or not returned by the Adventure Guide.
- The Adventure Guide is open on a dungeon or unsupported context.
- A configured announcement channel is unavailable or lacks permission.
- RCLootCouncil is absent, disabled, degraded, or changes authority during an operation.
- The addon is in combat while the Adventure Guide UI needs to be refreshed.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST allow a player to create a Pre-Dib request for a specific supported item within the active season.
- **FR-002**: Each request MUST retain a stable request identity, player identity, item identity, season identity, lifecycle status, and creation/update timestamps.
- **FR-003**: The system MUST deduplicate active requests by player, item, and season.
- **FR-004**: The system MUST support pending, confirmed, cancelled, invalidated, and fulfilled request outcomes.
- **FR-005**: A Pre-Dib request MUST NOT consume a Dib when it is created or confirmed.
- **FR-006**: A Dib MUST be consumed only after a qualifying item award is finalized for the requesting player.
- **FR-007**: A finalized award MUST be idempotent so repeated delivery cannot append duplicate accounting effects or fulfill a request twice.
- **FR-008**: A request that does not win an item MUST remain active unless an explicit cancellation or invalidation rule applies.
- **FR-009**: The system MUST support configurable public and officer announcement destinations with graceful handling of unavailable channels.
- **FR-010**: The Adventure Guide integration MUST expose the Dib action only in supported raid loot contexts.
- **FR-011**: The Adventure Guide integration MUST hide or disable the Dib action for dungeon loot and reject direct submissions from non-raid contexts.
- **FR-012**: The system MUST provide a configurable sub-category policy for local Adventure Guide action visibility.
- **FR-013**: The recommended policy MUST block clearly non-Dib categories including cosmetics, housing decor, mounts, pets, and recipes while allowing unknown categories by default.
- **FR-014**: Users MUST be able to override the local sub-category policy without changing ledger rules, balances, or historical transactions.
- **FR-015**: The integration MUST use stable item identifiers and category keys rather than localized display text as accounting identity.
- **FR-016**: The system MUST continue to support Pre-Dib creation and authoritative accounting when RCLootCouncil is absent.
- **FR-017**: RCLootCouncil integration MUST remain optional and MUST NOT become the source of truth for Pre-Dib history or Dib balances.
- **FR-018**: The system MUST route authoritative award fulfillment through the existing protected Dibs acceptance boundary.
- **FR-019**: The system MUST not modify Blizzard or RCLootCouncil core code, replace protected UI functions, or automate protected gameplay actions.
- **FR-020**: The system MUST preserve existing Dibs Core behavior and remain compatible with its stable season, ledger, permission, and protected-action contracts.

### Key Entities

- **Pre-Dib Request**: A player's advance intention for a specific item, including request identity, player, item, season, lifecycle status, source, and timestamps.
- **Adventure Guide Policy**: A local visibility preference mapping recognized loot sub-categories to allowed or blocked action states.
- **Finalized Award Reference**: A stable identifier for a completed award used to prevent duplicate fulfillment and duplicate ledger consumption.
- **Announcement Settings**: Configured public and officer destinations for request notifications.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of repeated active requests for the same player, item, and season resolve to one request record.
- **SC-002**: 100% of Pre-Dib requests created before an award leave the player's Dib balance unchanged until a qualifying award is finalized.
- **SC-003**: 100% of replayed finalized awards produce zero additional ledger transactions and zero additional request fulfillments.
- **SC-004**: 100% of dungeon Adventure Guide contexts expose zero usable Dib actions and reject direct Pre-Dib submission attempts.
- **SC-005**: 100% of recommended policy evaluations block the defined non-Dib categories while leaving unknown categories visible by default.
- **SC-006**: 100% of standalone Pre-Dib and fulfillment scenarios succeed without RCLootCouncil being installed or operational.
- **SC-007**: At least 95% of valid supported raid loot rows receive a usable Dib action during manual Adventure Guide validation, excluding rows whose item metadata is unavailable from the client.
- **SC-008**: No tested Pre-Dib or local policy operation modifies a historical ledger transaction or changes a player's balance without an accepted authoritative award action.

## Assumptions

- An active Dibs season exists before normal Pre-Dib use; requests without a valid season are rejected without persistent accounting changes.
- The player's GUID is the primary identity when available, with the normalized player name retained for display and compatibility.
- A Pre-Dib is a request or reservation, not a committed Dib spend; the ledger remains authoritative for committed consumption.
- The Adventure Guide provides enough stable instance and item metadata to distinguish raid contexts in supported Retail versions; unknown contexts fail closed for action submission.
- Unknown loot sub-categories remain visible by default to avoid hiding legitimate combat loot, while the recommended preset blocks known non-Dib categories.
- RCLootCouncil can optionally report local finalized award events, but standalone Dibs workflows remain valid without it.
- Cross-raid synchronization of live loot-session candidates, votes, responses, and discussion remains outside this feature.
- Real-client smoke validation may be environment-limited and must be recorded separately from automated validation.

## Out of Scope

- Cross-raid synchronization protocol design.
- Complete RCLootCouncil candidate and vote replication.
- Automatic boss-kill allocation or generic DKP behavior.
- A universal promotion/demotion allocation policy.
- Modification of Blizzard or RCLootCouncil source code.
