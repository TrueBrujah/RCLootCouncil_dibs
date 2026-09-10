# Feature Specification: Character Loot Eligibility and Main/Alt Governance

**Feature Branch**: `005-character-loot-eligibility`

**Created**: 2026-09-07

**Status**: Implemented on `dev` in version `0.5.0-dev`; Retail visual and two-client validation remain scheduled.

**Input**: User description: "Track Curios and Tier Set loot across a player's linked characters, prevent duplicate priority across difficulties according to configurable guild rules, and support main/alt declarations with officer-approved main changes and a configurable probation period."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Track protected loot families (Priority: P1)

As a player, I want the addon to remember when I or one of my linked characters received a tracked Curio or Tier Set item, so that priority follows the guild's current loot round instead of being reset by a difficulty or character change.

**Why this priority**: This is the core fairness rule and prevents a character from bypassing the guild's one-per-player policy by changing difficulty or character, while still reopening the next piece when the eligible group has caught up.

**Independent Test**: Record qualifying loot on a player's first character, present the matching family on a second linked character at another difficulty, and verify that the configured round, eligibility result, and explanation are shown before an award.

**Acceptance Scenarios**:

1. **Given** a season tracks Curios across all configured difficulties, **when** a linked character receives a Curio in Normal and the same Curio family is considered in Heroic, **then** the second request is marked ineligible or requires the configured officer review, with the previous acquisition and rule shown.
2. **Given** a Tier Set token group contains several eligible classes and every active member of that group has at least one qualifying piece, **when** another matching token drops, **then** the next Tier Set round opens and eligible members may vote for a second piece according to the configured policy.
3. **Given** a new eligible player joins a Tier Set token group with zero pieces while the existing members have one or more, **when** a matching token drops, **then** only the lowest-progress member(s) receive normal priority until that member reaches the current group round; the next round opens once the group is ready again.
4. **Given** two different loot families are configured independently, **when** a player owns a Curio but not a Tier Set piece, **then** the Curio rule does not incorrectly block the Tier Set request.
5. **Given** an item was only proposed, voted on, or displayed but not finalized as awarded, **when** eligibility is evaluated, **then** it is not counted as acquired.

### User Story 2 - Configure the policy per season (Priority: P1)

As a GM or Officer, I want to choose which loot families are tracked and how difficulties, slots, and exceptions are treated, so that the addon follows our guild's policy instead of imposing one fixed rule.

**Why this priority**: Guilds differ on whether Normal, Heroic, Mythic, and LFR share a quota, whether a Tier Set group is defined by class or token, and whether a Curio upgrade should start a new round.

**Independent Test**: Create two seasons with different Curio and Tier Set policies, finalize the same test history in both, and verify that each season evaluates eligibility using only its own policy.

**Acceptance Scenarios**:

1. **Given** an authorized Officer edits the active season, **when** they enable cross-difficulty tracking for Tier Set and same-difficulty tracking for Curios, **then** each category applies its selected scope immediately and the change is recorded in history.
2. **Given** a new season starts, **when** no policy is explicitly configured, **then** the documented guild default is applied and the previous season's policy remains unchanged.
3. **Given** an authorized Officer edits Tier Set rules, **when** they define a class/token group and its eligible classes, **then** the group advances independently from other Tier Set groups and its round state is visible.
4. **Given** an authorized Officer edits Curio rules, **when** they define the slot-completion threshold and upgrade-track behavior, **then** a character reaching 4/4 can be marked complete while a higher-track Mythic Curio can be configured to reopen eligibility.
5. **Given** an item cannot be confidently mapped to a configured loot family, **when** it appears for award, **then** the addon shows an unknown-family warning and follows the configured unknown-data behavior without silently treating it as a confirmed duplicate.
6. **Given** a policy change would affect future eligibility, **when** it is saved, **then** it does not rewrite prior acquisitions or historical awards.
7. **Given** a Catalyst item is shown in the Adventure Guide or an RCLootCouncil
   session, **when** Dibs eligibility is evaluated, **then** no Dibs action is
   offered because Catalyst progress is personal to the player; Curios and
   class-based Tier Set tokens remain distinct semantic families.

### User Story 3 - Declare and review main/alt relationships (Priority: P1)

As a player, I want to declare which characters belong to me, and as a GM or Officer, I want to verify that relationship, so that an alt cannot be used to obtain a second share of protected guild loot.

**Why this priority**: The guild rule is player-based, but the game presents characters. A controlled relationship is required to apply the rule across characters without exposing private account information.

**Independent Test**: Declare two characters as one player group, approve the relationship as an Officer, and verify that the two characters share the configured protected-loot history while an unrelated character does not.

**Acceptance Scenarios**:

1. **Given** a player declares a character as an alt, **when** the relationship is not yet approved, **then** the character remains unlinked for enforcement and the player sees that Officer review is pending.
2. **Given** an Officer approves a main and one or more alts, **when** a protected award is finalized on any linked character, **then** the acquisition is attributed to the linked player group according to the active season policy.
3. **Given** two characters have not been linked, **when** one receives protected loot, **then** the other is not blocked solely from a name or class similarity.
4. **Given** a character leaves the guild or is moved to another guild, **when** the roster is refreshed, **then** the old guild's history remains private and immutable while the character's new guild has a separate policy context.
5. **Given** a player has multiple eligible classes for one Tier Set token group, **when** the relationship is approved, **then** the guild policy explicitly determines whether progress is counted per class character or pooled per linked player group; the addon does not infer a second entitlement automatically.

### User Story 4 - Manage a main-character change and probation (Priority: P2)

As a GM or Officer, I want to approve a change from one main character to another and apply a configurable probation period, so that legitimate roster changes are possible without letting a player reset their loot priority mid-season.

**Why this priority**: Main changes are an explicit guild exception and need a visible, time-bounded rule instead of an informal note.

**Independent Test**: Approve a main change with the default probation, verify the new main's eligibility during probation and after expiry, then verify that an authorized emergency exception is separately recorded.

**Acceptance Scenarios**:

1. **Given** a player has an approved main and requests a new main, **when** a GM or Officer approves the change, **then** the addon records the old main, new main, approver, effective date, probation end date, and policy used.
2. **Given** the default probation policy is two weeks with no main-spec protected loot, **when** the new main requests a protected item before the probation ends, **then** the request is blocked or downgraded according to the selected policy and the remaining time is shown.
3. **Given** the probation period has ended, **when** the new main requests a protected item, **then** the normal active-season policy applies without manual cleanup.
4. **Given** an Officer authorizes an emergency role exception, **when** a protected award is made during probation, **then** the exception contains a reason, scope, expiry or one-award limit, and the approving authority in the audit history.
5. **Given** a normal player or RCLootCouncil council member attempts to approve a main change or alter probation, **when** the action is submitted, **then** it is rejected and no policy or history is changed.

### User Story 5 - Explain decisions in the loot workflow (Priority: P2)

As a player or loot administrator, I want a clear explanation when a request is blocked, downgraded, or allowed by exception, so that loot decisions can be resolved without disputes.

**Why this priority**: A visible reason is necessary for trust when the rule depends on another character, another difficulty, or a probation date.

**Independent Test**: Exercise one allowed request, one duplicate-family rejection, one probation rejection, and one officer exception, and verify that each produces a concise player-facing explanation and a detailed Officer history entry.

**Acceptance Scenarios**:

1. **Given** a request is blocked because a linked character already acquired the family, **when** the player views the decision, **then** the message identifies the family, acquisition difficulty, acquisition character label, and active rule without exposing unrelated private data.
2. **Given** the item is allowed by an exception, **when** an administrator reviews the award, **then** the audit entry identifies the exception, actor, scope, and reason.
3. **Given** the history is incomplete or unverifiable, **when** the decision cannot be made safely, **then** the UI asks for Officer review rather than presenting an unverified result as fact.

## Edge Cases

- A player has several linked characters and the same family was acquired in a prior season; the Officer can choose whether the rule is season-scoped or carries forward, with the season-scoped behavior as the default.
- A Tier Set token can be used by multiple classes; the policy defines the eligible class/token group and tracks the group's lowest-progress round rather than treating each difficulty as an unrelated entitlement.
- A Tier Set group has members with different piece counts; only the member(s) at the current lowest round receive normal priority until the group catches up, unless the policy selects another outcome.
- A Curio has multiple item IDs, slots, or upgrade tracks; the policy can group them under one stable family while retaining the exact item, slot, difficulty, and track for audit.
- A Curio participant reaches the configured 4/4 completion threshold or explicitly opts out; they leave the active Curio pool until a policy-defined higher-track upgrade reopens their need.
- Every participant has 4/4 Curios and a Mythic Curio appears; the policy can treat Mythic as a separate upgrade round, allow it under a higher-track rule, or require Officer review.
- The same character receives an item, trades it away, deletes it, or never equips it; a finalized guild award remains an acquisition unless an authorized correction is recorded.
- A finalized award arrives twice or after a reload; the protected-loot history records it once.
- An item is received outside RCLootCouncil or before this feature is enabled; an Officer can add a confirmed historical record without rewriting existing records.
- A character rename, realm transfer, or missing character identity occurs; the relationship remains pending until the identity is reverified.
- A main change is approved while another probation is active; the addon prevents overlapping ambiguous states and requires an Officer decision to close or supersede the existing one.
- The RCLootCouncil integration is absent or degraded; standalone Dibs and Officer-managed records remain usable, while unverified automatic acquisition is not silently accepted.
- A player is not in a group or the guild has no raid channel; local history and policy views remain available without attempting raid synchronization.
- A policy is changed during an active loot session; the applied rule is identified in the award record so the result can be reconstructed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST maintain a seasonal acquisition history for configured loot families, including Curios and Tier Set items, with the exact item, family, difficulty, slot or token context when known, receiving character, linked player group, season, timestamp, source, and authorized actor or finalized-award identity.
- **FR-002**: The system MUST count an acquisition only after a qualifying award is finalized or an authorized Officer/GM confirms a historical record; pending votes, visible candidates, test events, and rejected awards MUST NOT count.
- **FR-003**: The system MUST support per-season enablement and independent policy for at least Curios and Tier Set families.
- **FR-004**: Each tracked family MUST support a configurable difficulty scope, including at least same-difficulty and all-configured-difficulties modes; the default Tier Set scope MUST be all configured difficulties unless the guild changes it.
- **FR-005**: Each tracked family MUST support a configurable matching scope for exact item, item family, slot, token family, or complete-set policy where the source data makes that distinction possible.
- **FR-006**: Tier Set policy MUST support configurable class/token groups, eligible classes, and a group round rule that identifies the lowest-progress active members before normal priority is granted.
- **FR-007**: For a Tier Set group, the system MUST advance to the next piece round only when every active eligible member has reached the current round or has an authorized no-need status; a newly approved eligible member with less progress MUST be considered in the lowest-progress round.
- **FR-008**: Curio policy MUST support a guild-wide active participant pool independent of class, a configurable completion threshold with a default of 4/4 slots, and an explicit no-longer-needed status.
- **FR-009**: Curio policy MUST support a configurable higher-difficulty or upgrade-track rule so that a Mythic or otherwise stronger Curio can start a new round, remain blocked, or require Officer review after baseline completion.
- **FR-010**: The system MUST evaluate protected-loot eligibility before a Dibs priority or award is finalized and MUST expose one of the configured outcomes: allow, warn, require Officer review, downgrade priority, or block.
- **FR-011**: The system MUST provide a stable, localized explanation for every non-default eligibility outcome and MUST identify the relevant round, rule, and prior acquisition without exposing unrelated players' private data.
- **FR-012**: The system MUST allow a player to declare a main and related alts, but a declaration MUST NOT affect enforcement until it is approved by a verified guild GM or Officer.
- **FR-013**: The system MUST keep character relationships scoped to the guild and season policy context; it MUST NOT attempt to infer or expose a player's Battle.net account identity or unrelated-guild characters.
- **FR-014**: The system MUST allow a verified GM or Officer to approve, reject, suspend, or correct a character relationship while preserving the prior relationship history.
- **FR-015**: The system MUST allow a verified GM or Officer to approve a main-character change with an effective date, configurable probation duration, probation outcome, optional role exception, approver, and reason.
- **FR-016**: The default main-change probation MUST be 14 days and MUST prevent the new main from receiving main-spec protected loot or Dibs priority during that period; the guild MUST be able to select another documented probation outcome per season.
- **FR-017**: Emergency exceptions MUST be limited in scope and time or number of awards, MUST require GM/Officer authority, and MUST be visible in the audit history.
- **FR-018**: Master Looter, Raid Leader, Raid Assistant, and RCLootCouncil council membership MUST NOT grant authority to configure policies, link characters, approve main changes, or create manual historical acquisitions; the existing validated Master Looter exception may only supply a qualifying finalized RCLootCouncil award event.
- **FR-019**: Every policy change, relationship decision, main change, probation exception, manual acquisition, and correction MUST be append-only, attributed to the authorized actor, and include a reason where applicable.
- **FR-020**: Duplicate delivery of the same finalized award or historical import MUST be idempotent and MUST NOT create a second acquisition or change eligibility twice.
- **FR-021**: When required identity, family, difficulty, class group, or award evidence is missing, the system MUST follow a configured unknown-data behavior and MUST default to Officer review rather than silently denying or granting protected loot.
- **FR-022**: Normal players MUST see only their own acquisition status, linked-character labels permitted by the guild, probation status, and decision explanations; GM/Officer views MAY include complete guild-scoped relationships and history.
- **FR-023**: The feature MUST remain usable in standalone mode and MUST preserve the current Dibs ledger and history when RCLootCouncil is absent, disabled, degraded, or incompatible.
- **FR-024**: The feature MUST provide a migration or manual-entry path for confirmed historical Curio and Tier Set acquisitions without rewriting existing ledger transactions.
- **FR-025**: Policy and relationship changes MUST apply prospectively unless a GM/Officer explicitly chooses a documented retroactive evaluation; historical acquisition records MUST remain unchanged.
- **FR-026**: The feature MUST include localized labels and help text for tracked family, class/token group, round progress, difficulty scope, matching scope, completion status, probation status, exceptions, and unknown-data decisions.
- **FR-027**: The feature MUST classify Curios as the semantic `TOKEN` family and class-based Tier Set tokens as `TOKEN_SET`; it MUST NOT classify either family by equipment slot alone.
- **FR-028**: `CATALYST` MUST be treated as personal player progress and MUST be excluded from Dibs buttons, Pre-Dibs, policy enablement, protected awards, and ledger consumption. A saved or local Catalyst override MUST NOT re-enable Dibs for it.

### Key Entities

- **Loot Family Policy**: A season-scoped rule for a category such as Curio or Tier Set, including enabled state, family matching, difficulty scope, enforcement outcome, and unknown-data behavior.
- **Loot Acquisition**: A confirmed historical record that a character received a tracked item or family, including source, item context, class or token group, difficulty, upgrade track, character, linked player group, season, and evidence.
- **Tier Set Group**: A configured set of eligible classes or token recipients sharing one progression round, with the current minimum piece count and active participants.
- **Loot Round**: A fairness cycle that opens a protected family for members at the current progress threshold and advances only when the active group is ready.
- **Curio Participant Status**: A guild-scoped state such as active need, complete at the configured slot threshold, or explicitly no longer needed.
- **Character Relationship**: A guild-scoped, approval-controlled association between a player's main and one or more alt characters, with status and history.
- **Main Change**: An approved transition from one main character to another, including effective time, probation end, selected probation outcome, exceptions, and approver.
- **Loot Eligibility Decision**: The explainable result for one request or award: allow, warn, review, downgrade, or block, with the policy and acquisitions considered.
- **Probation Exception**: A bounded, authorized override for a role or award during main-change probation, including reason and expiry or award limit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In automated acceptance tests, 100% of qualifying finalized Curio and Tier Set awards create exactly one acquisition record, and replaying the same award creates no additional record.
- **SC-002**: In automated policy tests, 100% of configured same-difficulty, cross-difficulty, class-group, token-group, lowest-progress, 4/4 completion, and higher-track scenarios return the expected outcome.
- **SC-003**: In automated authority tests, 100% of policy, relationship, main-change, exception, and manual-history mutations succeed only for verified guild GMs or Officers.
- **SC-004**: In a two-character test matrix, a linked alt cannot bypass a configured shared protected-loot quota, while an unlinked character is not blocked solely by name or class similarity.
- **SC-005**: At least 95% of eligibility decisions in the supported loot workflow display a clear reason to the affected player or administrator without a client error or blocked interface.
- **SC-006**: 100% of private relationship and complete-history views are inaccessible to normal players, while affected players can see their own status and the rule explanation.
- **SC-007**: A new season can be configured with a different Curio and Tier Set policy without changing any prior season's decisions or acquisition history.
- **SC-008**: A GM/Officer can review a main change, probation status, exception, and related acquisition history in under two minutes during a simulated loot decision.
- **SC-009**: In a simulated Tier Set group with a late-arriving member, the member with the lowest progress receives priority until the group reaches the next round, and no higher-progress member bypasses that round without an exception.
- **SC-010**: In a simulated Curio pool, a participant at 4/4 or marked no-longer-needed leaves the active pool, while a configured higher-track Mythic item produces the selected reopen, allow, or review result.

## Assumptions

- Guild policy is the authority for fairness; the feature does not claim to reproduce Blizzard's personal loot, collection, or raid-lockout rules.
- Curios and Tier Set are the first protected families, but the policy model is extensible to other guild-defined families later.
- A player's linked characters cannot be reliably discovered from the addon alone. The player must declare the relationship and a verified GM/Officer must approve it, unless a future trusted data source is explicitly added.
- The default policy is season-scoped, tracks Tier Set across all configured difficulties, groups Tier Set eligibility by configured class/token groups, uses lowest-progress round priority, treats Curios as one guild-wide non-class `TOKEN` pool, considers 4/4 slots complete, and applies a 14-day no-main-spec protected-loot probation after an approved main change. `TOKEN_SET` is reserved for class-based Tier Set tokens, and `CATALYST` is always personal and excluded from Dibs.
- A Tier Set round is satisfied when all active eligible members in that group reach the current minimum piece count or have an authorized no-need status; a new member with less progress joins the lowest active round.
- Curio completion and higher-track behavior are policy decisions. The default treats a character at 4/4 as complete for the baseline track, while a stronger Mythic track can be configured to reopen need or require review.
- Existing RCLootCouncil finalized-award validation remains the source for automatic records when the integration is operational; standalone or historical records require explicit confirmation.
- An acquisition means the guild finalized the award to the character, even if the item is later traded, deleted, sold, or unequipped. Corrections use the existing append-only audit model.
- Normal, Heroic, Mythic, and LFR are treated as labels whose availability and relationship may vary by raid and season; Officers choose the active scope instead of relying on a permanent difficulty assumption.
- Character identity and relationship data remain guild-scoped and must not expose Battle.net account identifiers or unrelated guild membership.
- This specification covers policy, history, eligibility, relationship, and audit behavior. Automatic discovery of every account alt, external roster imports, and a complete transmog-collection tracker are future extensions.
