# Feature Specification: Great Vault Acquisition Tracking and Guild Sync

**Feature Branch**: `013-great-vault-acquisition-sync`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "Create a specification for Great Vault Acquisition Tracking and Guild Sync. Detect Great Vault claims when Retail supports it, retain `/dibs vault` as a manual fallback, record item and reset context, prevent duplicates, synchronize confirmed acquisitions with authorized clients of the same guild, and preserve privacy and existing history."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record a Great Vault acquisition (Priority: P1)

As a player, I want a Great Vault reward to be recorded when I actually claim it, so that protected-loot eligibility reflects a confirmed acquisition rather than an item that was merely offered.

**Why this priority**: Great Vault progress is useful only when the addon distinguishes a claimed reward from an available choice, an opened Vault, or an unverified local observation.

**Independent Test**: In a Retail test session, expose a Vault reward, claim it, and verify that exactly one acquisition record appears with the player, item, season, reset, timestamp, source, and confirmation state.

**Acceptance Scenarios**:

1. **Given** the Retail client exposes a reliable claim signal with item identity, **when** the player claims a Great Vault reward, **then** the addon records one confirmed acquisition without consuming a Dib.
2. **Given** the Great Vault is opened but no reward is claimed, **when** the addon observes the Vault state, **then** no confirmed acquisition is created.
3. **Given** the client does not expose a reliable claim signal, **when** the player uses `/dibs vault <itemID> [difficulty]`, **then** the addon records a clearly labeled manual acquisition and explains that Officer confirmation may be required for guild-wide eligibility.
4. **Given** the player has no active season, **when** a Vault reward is claimed or entered manually, **then** the local record preserves the event and marks its season context as unavailable instead of assigning it silently to another season.

---

### User Story 2 - Preserve trustworthy acquisition status (Priority: P1)

As a player or Officer, I want to know whether an acquisition was automatically confirmed, entered manually, inherited from legacy data, or merely detected locally, so that an uncertain record cannot silently change protected-loot priority.

**Why this priority**: A local observation is not equivalent to proof of a claimed reward. The distinction protects both fairness and the player's ability to challenge an incorrect record.

**Independent Test**: Create one automatic, one manual, one legacy, and one unverified record, then inspect Player and Officer views and run an eligibility decision for each status.

**Acceptance Scenarios**:

1. **Given** an automatic claim has complete item and reset evidence, **when** eligibility is evaluated, **then** the record is eligible to count according to the active season policy.
2. **Given** a manual `/dibs vault` record has not been confirmed, **when** eligibility is evaluated, **then** the configured unknown-data policy is applied and the player is not silently blocked or granted priority.
3. **Given** a record is marked unverified or ambiguous, **when** an Officer reviews it, **then** the UI shows the missing evidence and offers confirmation, rejection, or retention as reference-only data.
4. **Given** a normal player views their own history, **when** an acquisition is displayed, **then** they see the item, date, source, status, and decision explanation without seeing unrelated players or private Officer evidence.
5. **Given** a GM or Officer views the acquisition queue, **when** the record is displayed, **then** the evidence identity, source, verification state, sync state, and audit actor are available.

---

### User Story 3 - Synchronize confirmed acquisitions within the guild (Priority: P1)

As a guild administrator, I want confirmed Great Vault acquisitions to reach authorized clients in the same guild, so that eligibility decisions do not depend on one player's local SavedVariables.

**Why this priority**: Character eligibility and cross-raid fairness require a consistent guild-scoped view, while the existing security model forbids sending live loot sessions or private raid votes between groups.

**Independent Test**: Use two authorized clients in the same guild, record a confirmed acquisition on one client, synchronize it, and verify that the second client receives exactly one matching record and the expected eligibility result.

**Acceptance Scenarios**:

1. **Given** the sender and receiver are verified members of the same guild, **when** a confirmed acquisition is announced, **then** the receiver can request or receive the bounded acquisition detail according to its visibility scope.
2. **Given** the sender is not a current member of the receiver's guild, **when** an acquisition message arrives, **then** it is rejected without changing local data.
3. **Given** a receiver gets the same acquisition more than once, **when** each copy is processed, **then** the local history and eligibility state change only once.
4. **Given** two clients have different acquisition revisions, **when** they reconnect, **then** the client behind requests only missing or newer records rather than importing the complete database.
5. **Given** a message contains live candidates, votes, responses, loot-session state, or cross-raid discussion data, **when** it is validated, **then** the message is rejected and no acquisition is applied.
6. **Given** the receiver is a normal player, **when** guild synchronization completes, **then** the receiver gets only the acquisition details permitted for that player's own status and configured guild visibility.

---

### User Story 4 - Recover after reload, reconnect, or delayed delivery (Priority: P1)

As a guild administrator, I want Vault records to recover after reloads, offline periods, or out-of-order messages, so that temporary connectivity problems do not create missing or duplicate acquisitions.

**Why this priority**: Addon communication is opportunistic. The feature must remain correct when clients are not online at the same time or when messages arrive in a different order.

**Independent Test**: Deliver a confirmed acquisition before its digest, replay it after a reload, delay one transfer chunk, reconnect the receiver, and verify eventual convergence without duplicate accounting.

**Acceptance Scenarios**:

1. **Given** a receiver was offline when an acquisition was recorded, **when** it reconnects to the same guild, **then** its digest identifies the missing record and a bounded recovery request is made.
2. **Given** an acquisition detail arrives before its manifest or digest, **when** the detail is validated, **then** it is staged safely and applied once its identity and guild scope are valid.
3. **Given** a transfer is incomplete or expires, **when** recovery retries, **then** the partial data is discarded and the receiver requests the record again without applying a partial acquisition.
4. **Given** the sender has changed guilds since an acquisition was created, **when** the old record is encountered, **then** it remains in the old guild's local history and is not exposed to the new guild.
5. **Given** a client has a newer conflicting record with the same acquisition identity but different item or player data, **when** synchronization detects the conflict, **then** it marks the record for review instead of using last-write-wins.

---

### User Story 5 - Review, migrate, and correct historical records (Priority: P2)

As a GM or Officer, I want to review old or ambiguous Vault records and migrate existing history safely, so that installing this feature does not erase prior evidence or silently change eligibility.

**Why this priority**: Existing installations already contain display-only or manually entered Vault records. They must remain usable while gaining a clear verification state.

**Independent Test**: Load legacy Vault records, run the migration preview, confirm one record, reject one record, and verify that historical data remains present and every decision is audited.

**Acceptance Scenarios**:

1. **Given** an existing Vault acquisition lacks the new verification fields, **when** migration runs, **then** the record remains available with a legacy or manual status and no new Dib consumption is created.
2. **Given** an Officer confirms a manual acquisition with sufficient evidence, **when** confirmation is saved, **then** the record becomes eligible for the configured protected-loot policy and the confirmation actor, time, and reason are audited.
3. **Given** an Officer rejects an incorrect acquisition, **when** the rejection is saved, **then** the original evidence remains immutable and a correction or status event explains the outcome.
4. **Given** a player or Officer imports a full-data package containing Vault records, **when** the package is applied twice, **then** records are deduplicated by stable acquisition identity and no second eligibility effect is created.
5. **Given** the required item, player, reset, or guild evidence is missing, **when** an administrator reviews the record, **then** the record remains reference-only or requires explicit review according to policy.

## Edge Cases

- The Great Vault API exposes a reward choice but not a reliable claim event; the addon must not label the choice as confirmed.
- The player claims a reward and immediately reloads or disconnects before the local record is saved; recovery must use the stable reset and acquisition identity when available.
- The same item ID is claimed in two different weekly resets; both claims are distinct acquisitions unless the guild policy explicitly treats them as a duplicate.
- The player manually records an item and the automatic claim signal arrives later; the records must merge or link without double-counting and retain both evidence sources.
- The item link is unavailable while the item ID is known; the record may be stored with an explicit unresolved-item status and must not invent an item name.
- The item ID, difficulty, or reward category is not available from the client; the record must preserve known fields and mark unknown fields without guessing.
- A player has multiple characters in the same guild; the acquisition belongs to the claiming character and the approved linked-player policy determines whether progress is shared.
- The active season changes between reward claim and synchronization; the original season context remains unchanged and a missing context requires review.
- A client is unguilded, joins another guild, or has no roster data; guild synchronization must fail closed while local character-scoped data remains usable.
- A normal player receives an acquisition digest containing another player's private evidence; the receiver must retain only the permitted projection.
- A malicious or malformed sender claims to be a GM/Officer; the receiver must verify roster identity and authority independently of payload claims.
- Messages arrive duplicated, out of order, truncated, oversized, or after their transfer expiry; no partial or duplicate acquisition may be applied.
- The Great Vault is unavailable, the player is in combat, or a protected UI action is required; the addon must defer non-critical UI work and preserve a manual review path.
- A legacy record was created by `/dibs vault` before this feature; migration must preserve it and must not upgrade its confidence without evidence.
- An automatic record conflicts with an existing finalized RCLootCouncil acquisition for the same item; the two sources remain distinct evidence and the eligibility policy decides how they relate.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support a Great Vault acquisition record with, when available, a stable acquisition identity, character identity, item ID, item link, item name, item level, reward category, difficulty or tier, season, weekly reset identity, claim timestamp, source, verification state, evidence state, and sync revision.
- **FR-002**: The system MUST distinguish at least `AUTOMATIC_CONFIRMED`, `MANUAL_RECORDED`, `LEGACY_RECORDED`, `UNVERIFIED`, `OFFICER_CONFIRMED`, `REJECTED`, and `REFERENCE_ONLY` acquisition states or equivalent user-visible meanings.
- **FR-003**: The system MUST create an automatic confirmed record only when the Retail client provides sufficient evidence that the player claimed the reward; opening the Great Vault or viewing a reward choice MUST NOT be sufficient by itself.
- **FR-004**: The system MUST retain `/dibs vault <itemID> [difficulty]` as a manual fallback and MUST label records created through that path as manual until they are explicitly confirmed or otherwise resolved by policy.
- **FR-005**: The system MUST never consume, grant, refund, revoke, or adjust a Dib as a side effect of creating, receiving, confirming, rejecting, or synchronizing a Vault acquisition.
- **FR-006**: The system MUST use a stable deduplication identity based on the strongest available combination of character, weekly reset, item, reward slot or claim identity, and source evidence; it MUST report ambiguity when no safe identity exists.
- **FR-007**: Replaying an automatic event, manual command, import, or synchronization transfer MUST NOT create a second acquisition or apply eligibility twice.
- **FR-008**: Acquisition records MUST remain isolated by guild identity and by character when unguilded; changing guilds MUST NOT merge or expose prior guild records.
- **FR-009**: The system MUST preserve existing display-only and manually recorded Vault acquisitions during migration and MUST NOT silently promote their verification state.
- **FR-010**: A GM or Officer MUST be able to review, confirm, reject, or retain an ambiguous record as reference-only, with actor, timestamp, reason, evidence state, and resulting status recorded.
- **FR-011**: Normal players MUST see their own permitted acquisition status and explanation; complete guild acquisition evidence MUST remain restricted to verified GM/Officer views unless guild policy explicitly permits a broader projection.
- **FR-012**: Eligibility evaluation MUST distinguish confirmed acquisitions from unverified, rejected, and reference-only records and MUST follow the configured unknown-data policy without silently granting or denying protected loot.
- **FR-013**: The system MUST provide a bounded guild synchronization contract for confirmed acquisitions and the minimum metadata needed to discover missing records, recover after reconnect, and verify content integrity.
- **FR-014**: Synchronization MUST accept records only from a verified current member of the same guild and MUST verify the sender identity, guild scope, protocol compatibility, record identity, revision, and content integrity independently of claimed payload authority.
- **FR-015**: Synchronization MUST support a digest or manifest message, a bounded missing-record request, a detail transfer, and an acknowledgement or status result. It MAY reuse the existing bounded transfer envelope and MUST NOT create an independent transport that bypasses current validation.
- **FR-016**: Logical synchronization messages MUST support the following meanings: `VAULT_DIGEST` for bounded record summaries, `VAULT_FETCH` for missing or newer identities, `VAULT_DETAIL` for one or more validated records, and `VAULT_ACK` or an equivalent result for applied, duplicate, rejected, or conflict states.
- **FR-017**: Vault synchronization MUST NOT contain live RCLootCouncil candidates, votes, responses, loot-session state, live raid discussions, or unrelated cross-raid private data.
- **FR-018**: Synchronization MUST be delta-oriented, bounded in count and size, replay-safe, order-tolerant where feasible, and recoverable after reconnect without broadcasting the complete SavedVariables database.
- **FR-019**: A duplicate record MUST return an idempotent result; a stale revision MUST not overwrite newer evidence; a conflicting identity MUST enter review rather than use last-write-wins.
- **FR-020**: A normal player client MUST receive only the record projection allowed by guild privacy policy and the player's own visibility; GM/Officer clients MAY receive complete evidence after authorization.
- **FR-021**: SavedVariables changes MUST be versioned and additive where possible, with migration coverage for existing `preDibs.acquisitions` records, missing fields, old source labels, and guild or character isolation.
- **FR-022**: Migration MUST preserve original acquisition IDs, dates, item fields, source labels, and historical evidence; it MUST record migration metadata separately and MUST NOT create ledger transactions.
- **FR-023**: A failed, cancelled, incomplete, or rejected migration or sync transfer MUST leave active acquisitions and eligibility state usable and MUST not apply partial records.
- **FR-024**: The feature MUST use the existing `PreDibs` acquisition model, `CharacterEligibility` evaluation and confirmation boundaries, `Sync` transport, and `SyncV2` protocol governance rather than creating parallel business rules.
- **FR-025**: The feature MUST remain usable when RCLootCouncil is absent, disabled, degraded, or incompatible; Great Vault acquisition tracking MUST not require RCLootCouncil.
- **FR-026**: Automatic detection MUST be capability-aware. When the Retail client does not expose sufficient evidence, the feature MUST show an unavailable or manual-only state and MUST retain the manual fallback.
- **FR-027**: Diagnostics MUST identify detection, verification, migration, and synchronization failures without exposing live loot-session data or private evidence to unauthorized users.
- **FR-028**: All player-facing fields, statuses, commands, warnings, review actions, and help text MUST have localized labels with English fallback and MUST explain whether the record is confirmed, uncertain, reference-only, or still local.
- **FR-029**: Every new synchronization, SavedVariables, or player-facing behavior change MUST include a dated changelog entry, compatibility note, required documentation updates, and an addon version increment before shipping.

### Key Entities

- **Great Vault Acquisition**: A record that a character obtained a reward from the Great Vault, with item, reset, season, source, verification, and evidence context.
- **Acquisition Evidence**: The facts supporting an acquisition state, such as a reliable claim signal, manual entry, Officer confirmation, legacy origin, or unresolved observation.
- **Weekly Reset Context**: The reset identity and timestamps that distinguish rewards claimed in separate Great Vault periods.
- **Acquisition Projection**: The privacy-filtered representation sent to a player, Officer, or GM client.
- **Vault Synchronization Digest**: A bounded summary of acquisition identities, revisions, content hashes, and sync status used to find missing records.
- **Vault Synchronization Transfer**: A validated request and response carrying one or more acquisition records without live loot data.
- **Acquisition Review Decision**: An append-only decision to confirm, reject, retain, or classify an ambiguous acquisition, including actor, reason, and timestamp.
- **Legacy Acquisition Migration**: A versioned conversion that preserves an older Vault record and adds missing metadata without changing its historical meaning.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In supported Retail validation scenarios, every confirmed Great Vault claim creates exactly one acquisition record, and replaying the same claim after reload creates zero additional records.
- **SC-002**: In automated tests, 100% of manual, automatic, legacy, unverified, rejected, and Officer-confirmed records display the correct status and produce the configured eligibility outcome.
- **SC-003**: In two-client guild tests, at least 99% of valid confirmed acquisitions converge to the same record identity and content after one recovery cycle, with zero duplicate acquisitions.
- **SC-004**: In security tests, 100% of cross-guild, unverifiable-sender, malformed, oversized, and live-loot-containing messages are rejected without changing local acquisition or eligibility state.
- **SC-005**: In replay and out-of-order tests, 100% of duplicated, delayed, incomplete, and stale transfers produce no duplicate accounting effect and leave a recoverable sync status.
- **SC-006**: In migration tests, 100% of existing Vault acquisition records remain accessible with their original item, source, and timestamp, and no migration creates a Dib transaction.
- **SC-007**: A GM or Officer can identify why a Vault record is confirmed, manual, unverified, rejected, or reference-only in under 30 seconds from the acquisition review view.
- **SC-008**: Normal players can view their own permitted Vault status while receiving zero unrelated player identities or Officer-only evidence in privacy tests.
- **SC-009**: When the Retail client cannot provide a reliable claim signal, 100% of test runs expose the manual-only limitation and keep `/dibs vault` available without falsely confirming a reward.
- **SC-010**: In standalone mode, Great Vault recording and local eligibility remain usable with RCLootCouncil absent, while no live loot-session synchronization is generated.

## Assumptions

- Blizzard may not expose a stable or complete Great Vault claim event in every supported Retail client build. Automatic confirmation is therefore capability-aware and manual entry remains a supported workflow.
- A Great Vault claim is an acquisition event, not a Dibs award. It never changes the Dibs ledger.
- The existing guild-scoped SavedVariables model remains authoritative for local data; no remote database, cloud service, GitHub storage, or public API is introduced.
- The existing approved main/alt relationship policy determines whether an acquisition on a linked character affects the same protected-loot pool.
- The existing season policy determines whether Vault progress is scoped to a season, a loot family, a difficulty, or another configured boundary. The acquisition record preserves the original context rather than recalculating history silently.
- Confirmed full evidence is available to verified GM/Officer clients by default. Normal players receive their own status and any explicitly permitted summary projection.
- Existing transport limits, sender verification, protocol governance, and anti-replay rules remain the baseline for Vault synchronization.
- Existing legacy `preDibs.acquisitions` entries may lack verification and reset fields. They are preserved as legacy or manual records until an authorized review supplies stronger evidence.
- Retail manual validation is required for protected or undocumented Blizzard UI behavior; automated tests cover domain, migration, privacy, and replay behavior but cannot prove every client event exists.
- This feature does not attempt to discover every account alt, read Battle.net identity, inspect private account data, or synchronize inventories, bags, banks, or live raid votes.
