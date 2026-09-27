# Feature Specification: Guild-Authoritative Loot Rules

**Feature Branch**: `018-guild-authoritative-loot-rules`

**Created**: 2026-09-25

**Status**: Draft

**Input**: User description: Design and implement one guild-authoritative Loot Rules configuration for DIBS and the RCLootCouncil integration, with explicit GM adoption/publication, safe synchronization, migration, readiness, compatibility, audit, and documentation.

## User Scenarios & Testing

### User Story 1 - Adopt and Publish Guild Loot Rules (Priority: P1)

A Guild Master reviews the existing local Loot Rules, adopts them as the guild configuration, and explicitly publishes later changes. The UI distinguishes a saved local draft from a successful guild publication.

**Why this priority**: Without an explicit, reviewed authority transition, local client settings can silently determine guild behavior.

**Independent Test**: A GM can preview the existing values, adopt them once, publish revisioned changes, and observe a precise failure result when publication is denied or synchronization is unavailable.

**Acceptance Scenarios**:

1. **Given** no authoritative guild Loot Rules and existing local values, **When** the GM opens Loot Rules, **Then** the complete draft is shown for review without changing authority.
2. **Given** the GM confirms adoption, **When** the adoption is authorized and published, **Then** one authoritative configuration is created with writer, ordering, and audit data.
3. **Given** authoritative rules exist, **When** the GM edits draft values, **Then** effective behavior remains on the published revision until the GM explicitly publishes.
4. **Given** publication fails, **When** the writer submits the draft, **Then** the UI reports `GUILD PUBLISH FAILED` and never reports that guild settings were saved successfully.

### User Story 2 - Consume the Same Effective Rules (Priority: P1)

An Officer receives the guild configuration and uses the same Adventure Guide filtering and RCLootCouncil Dibs-button behavior as the GM. Local legacy values cannot override an active guild configuration.

**Why this priority**: Consistent effective behavior across authorized clients is the feature's primary guild value.

**Independent Test**: Apply the GM's published record to a second client with conflicting local settings and prove that both clients expose identical effective values while preserving the second client's local draft.

**Acceptance Scenarios**:

1. **Given** an Officer applies the current guild configuration, **When** the Loot Rules page is opened, **Then** it identifies the configuration as managed by guild policy and displays it read-only.
2. **Given** local legacy values differ from an active guild configuration, **When** loot eligibility or RCLootCouncil buttons are evaluated, **Then** the guild configuration wins and the local values remain preserved.
3. **Given** a new catalog revision is validated and applied, **When** RCLootCouncil is available, **Then** the existing DIBS integration refreshes its button projection without directly rewriting unrelated RCLootCouncil SavedVariables.

### User Story 3 - Migrate Existing Local Rules Safely (Priority: P1)

An existing guild can move from independent local settings to one explicit guild authority without silently promoting an Officer's values or destroying any client's legacy data.

**Why this priority**: Existing guilds already have live local behavior and must retain a recoverable path through migration.

**Independent Test**: Exercise fresh, legacy-only, and already-adopted records on multiple clients; compare local settings before and after adoption, reconnect, duplicate replay, and failed publication.

**Acceptance Scenarios**:

1. **Given** only legacy local settings exist, **When** an Officer connects, **Then** those values remain local and are not adopted or published by that Officer.
2. **Given** a GM previews legacy values and adopts them, **When** adoption succeeds, **Then** the GM's reviewed values seed the initial guild configuration and all prior local values remain recoverable.
3. **Given** an active guild configuration exists, **When** stale local settings or an older catalog arrive, **Then** neither can replace or downgrade the active authority.

### User Story 4 - See Readiness and Compatibility Honestly (Priority: P2)

A GM or Officer can distinguish a synchronized authoritative configuration from missing, local-only, behind, incompatible, or unavailable states and take an appropriate action.

**Why this priority**: A local option page must not be mistaken for guild-wide readiness, especially in a partially upgraded raid.

**Independent Test**: Drive each authority/sync state through the readiness projection and verify localized status, remediation, and refresh behavior.

**Acceptance Scenarios**:

1. **Given** an adopted configuration is current and compatible, **When** readiness runs, **Then** Loot Rules reports `GUILD_LOOT_RULES_READY` with synchronized guild-scope wording.
2. **Given** only local legacy settings exist, **When** readiness runs, **Then** it reports `LOCAL_LEGACY_ONLY`, not guild-wide readiness.
3. **Given** the catalog is behind, incompatible, or unavailable, **When** readiness runs, **Then** it reports the matching non-ready state and the integration does not silently fall back to local values.
4. **Given** a new-version client encounters a 0.6.x peer, **When** synchronization is attempted, **Then** existing version compatibility rejects the peer and the new client reports that an update is required.
5. **Given** an authorized catalog revision changes during a raid, **When** the client validates and applies it, **Then** its effective projection refreshes from that revision and known sync-behind/incompatible state remains visible; local settings never take precedence.

### Edge Cases

- The option source is absent, throws, is malformed, or yields no types.
- A saved rule names a type no longer returned by the option source.
- A local draft has a missing, non-boolean, or conflicting value.
- Two clients have different legacy values before first adoption.
- An authoritative record is duplicated, stale, has a missing parent, has a bad hash, or attempts to remove the adopted configuration.
- The current GM is offline, identity is ambiguous, governance is unavailable, or the local writer lacks authority.
- The sync transport is unavailable during draft save or publication.
- A new GM communicates with an old Officer, an old GM communicates with a new Officer, or only part of a raid is upgraded.
- An Officer reconnects after missing revisions or an update arrives during an active raid.
- RCLootCouncil is absent or its button projection cannot refresh.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST expose one guild-authoritative Loot Rules configuration containing the existing Adventure Guide and RCLootCouncil button choices for every supported loot type.
- **FR-002**: The supported loot-type keys MUST be derived from the existing Loot Rules option source; the system MUST NOT hardcode the example list.
- **FR-003**: The GM MUST be able to review the full local configuration before the first adoption, and adoption MUST require an explicit GM action.
- **FR-004**: An Officer's local settings MUST never seed or replace guild authority without an authorized publication.
- **FR-005**: After adoption, local draft values and guild-authoritative values MUST remain distinguishable; editing a draft MUST NOT change effective behavior until explicit publication succeeds.
- **FR-006**: The verified current GM MUST be able to publish a new revision; Officers MUST NOT publish or edit guild Loot Rules. Each published revision MUST identify its writer, order, and changed loot types through the existing audit/revision infrastructure.
- **FR-007**: Publication failure MUST preserve local draft values, report failure accurately, and leave the prior authoritative revision effective.
- **FR-008**: Before adoption, effective behavior MAY use preserved local legacy settings and MUST identify that state as local-only. After adoption, guild-authoritative values MUST take precedence; stale local values MUST NOT override them.
- **FR-009**: A malformed, unsupported, stale, unauthenticated, or incompatible configuration MUST NOT become effective. An active authority MUST NOT be downgraded to legacy-only by an older record.
- **FR-010**: Compatible authorized clients MUST automatically receive and apply authoritative revisions through the existing bounded V2 synchronization and recovery behavior.
- **FR-011**: Applying a revision MUST refresh the existing DIBS RCLootCouncil projection through the addon integration boundary and MUST NOT directly rewrite unrelated RCLootCouncil SavedVariables.
- **FR-012**: Officers MUST see authoritative values as managed/read-only after adoption. The GM MUST see draft-versus-authoritative differences and explicit adoption/publication actions.
- **FR-013**: Raid Readiness MUST distinguish `GUILD_LOOT_RULES_READY`, `GUILD_LOOT_RULES_NOT_CONFIGURED`, `GUILD_LOOT_RULES_SYNC_BEHIND`, `GUILD_LOOT_RULES_INCOMPATIBLE`, `LOCAL_LEGACY_ONLY`, and `UNAVAILABLE` (or equivalent repository naming).
- **FR-014**: Known behind, incompatible, or unavailable authority MUST NOT be reported as guild-wide readiness or silently fall back to local rules.
- **FR-015**: Existing local settings MUST be preserved idempotently through first adoption, replay, failed publication, and rollback/recovery paths.
- **FR-016**: The migration MUST treat legacy values as reviewable local input unless a valid explicit authoritative Loot Rules record already exists.
- **FR-017**: New and old clients MUST fail closed through the existing addon-version compatibility mechanism when they cannot represent the authoritative configuration; a client MUST NOT author a format it cannot represent.
- **FR-018**: A revision applied during a raid MUST become the client's effective revision only after validation; the client MUST refresh its DIBS projection and expose known synchronization lag rather than use local overrides.
- **FR-019**: Loot Rules status, GM publication, Officer consumption, and developer-level revision behavior MUST be documented for their intended audiences.
- **FR-020**: The feature MUST NOT change Rank Rules business behavior, OperationalPolicy values, ledger semantics, or unrelated RCLootCouncil SavedVariables.

### Key Entities

- **Local Loot Rules Draft**: Per-client, reviewable legacy or edited values for supported loot types; never authoritative by itself.
- **Guild Loot Rules**: One explicitly adopted and published configuration containing both button/eligibility decisions per supported type.
- **Catalog Revision**: The existing guild-authored ordered record that establishes authority, writer identity, synchronization, and audit context.
- **Effective Loot Rules**: The configuration consumed by Adventure Guide filtering and the RCLootCouncil DIBS integration; authoritative when adopted, local fallback only before adoption.

## Success Criteria

### Measurable Outcomes

- **SC-001**: In a two-client test, 100% of supported loot types have identical effective Adventure Guide and RCLootCouncil decisions after the Officer applies the GM's revision.
- **SC-002**: No test involving an active authoritative revision permits a conflicting local draft or stale record to change the effective configuration.
- **SC-003**: Every publication outcome is reported as local draft saved, guild publication succeeded, or guild publication failed; no failed publication is presented as success.
- **SC-004**: All six readiness states are individually observable and tested, including a local-only legacy client.
- **SC-005**: Replaying the same valid revision is idempotent; stale, unauthorized, malformed, and incompatible updates do not replace effective rules.
- **SC-006**: Tests confirm local legacy values and unrelated RCLootCouncil SavedVariables are unchanged by migration and configuration receipt.
- **SC-007**: The full Fengari suite and documentation validation complete with no new failures attributable to this feature.

## Assumptions

- The existing `SEASON_CATALOG` is the guild configuration authority because it already carries guild settings and has a V2 revision/recovery path.
- Adoption and all subsequent Loot Rules publications are GM-only. Officers consume the authoritative values read-only, even if they hold broader catalog-writing permission for other settings.
- The nested Loot Rules configuration has its own schema version while the root SavedVariables schema remains unchanged.
- Addon versions from the previous 0.6.x family cannot safely represent explicit Loot Rules authority and must receive the existing update-required behavior.
- During version mismatch or known catalog lag, clients preserve the last valid authority and do not switch back to local configuration.
- The current Rank Rules Guided Setup reconciliation issue is separate and out of scope.
