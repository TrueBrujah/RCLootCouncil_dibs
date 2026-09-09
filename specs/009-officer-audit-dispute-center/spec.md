# Feature Specification: Officer Audit and Dispute Center

**Feature Branch**: `009-officer-audit-dispute-center`

**Created**: 2026-09-09

**Status**: Draft

**Input**: User description: "Add a simple player report flow and an Officer review queue for Dibs problems. Players should submit a request with one button and optional notes; GM/Officers should see prefilled evidence and resolve it with a few clear actions, while all corrections remain safe and auditable."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Report a Dibs problem in one step (Priority: P1)

As a player, I want one simple way to report a Dibs problem, so that I do not need to understand the ledger, RCLootCouncil internals, or administrative commands.

**Why this priority**: Players are the first people to notice a missing or incorrect accounting result. A short report path captures the relevant context before it is forgotten without giving the player authority to change anything.

**Independent Test**: Open a player's own Dibs history, press **Report a problem** on a transaction, submit an optional note, and verify that one review request is created with the transaction and award evidence attached automatically.

**Acceptance Scenarios**:

1. **Given** a player can see one of their own Dibs transactions, **when** they press **Report a problem**, **then** the addon opens a short form with the transaction, item, season, date, and source prefilled.
2. **Given** the player leaves the optional category and note empty, **when** they press **Send**, **then** a general review request is created without requiring technical details.
3. **Given** the player chooses a short reason such as `Wrong debit`, `Missing debit`, `Duplicate`, `Wrong item/player`, or `Other`, **when** they send the request, **then** the selected reason is recorded without exposing other players' data.
4. **Given** the player has no Dibs transaction but sees a recent finalized Dibs decision, **when** they press **Report a problem**, **then** the addon attaches the available award context and marks the missing transaction as part of the report.
5. **Given** the same player submits the same report again, **when** the request is recognized as a duplicate, **then** the addon reopens or links the existing request instead of creating a spam duplicate.
6. **Given** a player attempts to report another player's transaction, **when** the request is submitted, **then** it is rejected without revealing that transaction or creating a cross-player request.

---

### User Story 2 - Review requests from one Officer queue (Priority: P1)

As a GM or Officer, I want one queue of open requests with the evidence already attached, so that I can review a problem without searching through several panels or asking the player to provide identifiers.

**Why this priority**: A single review queue reduces response time and avoids administrative mistakes caused by manually copying transaction or award information.

**Independent Test**: Create requests for an incorrect debit, a missing debit, a duplicate, and an eligibility question, open the Officer queue, and verify that each card has the expected evidence and suggested action.

**Acceptance Scenarios**:

1. **Given** open player requests exist, **when** a GM or Officer opens **Review Requests**, **then** the queue shows the newest requests first with player, item, date, category, status, and a short summary.
2. **Given** a request references a Dibs transaction or RCLootCouncil award, **when** the Officer opens it, **then** the related evidence is displayed automatically, including source, reference, response, status, season, and balance impact when available.
3. **Given** a request lacks reliable evidence, **when** the Officer opens it, **then** the queue labels the missing information and suggests `Ask for information` or `No correction`.
4. **Given** a normal player, Master Looter, Raid Leader, Raid Assistant, or council member lacks a verified guild GM/Officer role, **when** they open the queue or try to resolve a request, **then** access is denied without exposing the queue.
5. **Given** another Officer resolves a request while it is open, **when** the first Officer refreshes the queue, **then** the request shows the current outcome and cannot apply a second correction.

---

### User Story 3 - Resolve common cases with clear actions (Priority: P1)

As a GM or Officer, I want a small set of clear resolution actions, so that routine corrections are quick while complex choices remain available only when needed.

**Why this priority**: The normal path should be understandable at a glance. Advanced ledger operations must not be placed in front of every reviewer or encourage arbitrary balance editing.

**Independent Test**: Resolve one request with each primary action and verify the resulting player status, ledger transaction, evidence, and audit record.

**Acceptance Scenarios**:

1. **Given** a request confirms that a valid Dibs debit was missing, **when** the Officer selects **Correct balance**, **then** the addon applies the appropriate append-only correction or accounting action after confirmation and records the reason.
2. **Given** a request claims an incorrect debit but evidence shows the transaction is valid, **when** the Officer selects **No correction**, **then** the request closes with an explanation and no ledger change.
3. **Given** evidence is incomplete but the player may clarify the event, **when** the Officer selects **Ask for information**, **then** the request moves to a waiting state and the player can see the question and reply without editing the evidence.
4. **Given** the request is a duplicate, **when** the Officer selects the duplicate action, **then** the request links to the existing case or transaction and creates no second balance effect.
5. **Given** a correction requires a refund, revoke, historical import, or administrative adjustment, **when** the Officer opens **More options**, **then** the addon explains the effect and requires an explicit reason before using the protected action.
6. **Given** the Officer is reviewing a disagreement with RCLootCouncil's loot decision itself, **when** no Dibs accounting or eligibility error is present, **then** the request can be closed as `No correction` with a clear explanation that Dibs does not replace RCLootCouncil's award authority.

---

### User Story 4 - Keep the player informed without exposing private data (Priority: P1)

As a player, I want to know whether my request is being reviewed and what was decided, so that I do not need to ask an Officer repeatedly or see private guild audit information.

**Why this priority**: A transparent status reduces repeated messages while preserving Officer-only evidence and other players' privacy.

**Independent Test**: Submit a request, move it through review and resolution, and verify the player sees only their request, safe evidence summary, status, and resolution explanation.

**Acceptance Scenarios**:

1. **Given** a player submitted a request, **when** they open **My requests**, **then** they see its status, date, short reason, and the next action without seeing other requests.
2. **Given** an Officer asks for information, **when** the player opens the request, **then** they can provide one concise reply and the request returns to review.
3. **Given** a request is resolved, **when** the player views it, **then** they see whether the balance changed and a plain-language explanation without Officer notes or unrelated evidence.
4. **Given** a request is rejected or closed without correction, **when** the status is shown, **then** the reason is visible and the player can no longer create repeated duplicate submissions for the same evidence without a new context.
5. **Given** a player is not in the guild anymore, **when** they view local request data, **then** guild-scoped private records remain protected according to the existing isolation policy.

---

### User Story 5 - Preserve a trustworthy audit trail (Priority: P1)

As a guild administrator, I want every request and resolution to be traceable, so that a later dispute can be explained without deleting or rewriting history.

**Why this priority**: Corrections affect guild trust. The request, evidence, decision, and any compensating transaction must remain connected and attributable.

**Independent Test**: Submit, review, ask for information, resolve, and reopen a request, then verify that the complete timeline is append-only and links every balance-changing action to its authorized actor and reason.

**Acceptance Scenarios**:

1. **Given** a player report is created, **when** it is stored, **then** it receives a stable request identifier, creator, time, scope, category, note, and attached evidence references.
2. **Given** an Officer changes a request status or resolution, **when** the change is committed, **then** the action records the actor, time, previous status, new status, decision, reason, and affected transaction when applicable.
3. **Given** a correction changes a balance, **when** it completes, **then** the original transaction remains intact and the new compensating transaction links to the request and evidence.
4. **Given** a request is exported or included in an audit report, **when** it is shared, **then** the report follows the existing safe or Officer-only privacy scope.
5. **Given** RCLootCouncil is absent or degraded, **when** a player submits an accounting request, **then** Dibs can still review its own ledger evidence without inventing unavailable RCLootCouncil facts.

## Edge Cases

- The player closes the form before sending; no request is created.
- The current award is still being voted on; the report action is unavailable or clearly marked as a technical report that cannot affect the live vote.
- The player reports a missing debit but the award was never finalized; the Officer sees that no Dibs consumption is currently valid.
- The same award was already refunded or corrected; the queue shows the complete chain and prevents a second compensation.
- A player reports an award recorded under a custom response label; the evidence retains the original label and configured alias.
- The item, winner, award reference, or season is missing; the case becomes `Need information` or `No correction` rather than guessing.
- Two characters with similar names are involved; the request uses the stored canonical identity and does not match by short name alone.
- A request targets a historical reconciliation candidate; the queue links the candidate and import decision without changing the original RCLootCouncil history.
- An Officer loses guild rank while a request is open; they may finish viewing a safe summary but cannot resolve or mutate the request until authority is reverified.
- Two Officers choose different resolutions concurrently; only one valid state transition or balance correction is accepted, and the other sees the current outcome.
- A player submits many reports for the same item or transaction; bounded duplicate detection keeps one active case and links later submissions.
- A report note contains private or abusive text; the UI bounds length, preserves it as player-supplied content, and keeps it out of public reports by default.
- The addon is reloaded, the character changes guild, or a profile switches; request and evidence scope remains isolated and statuses remain recoverable.
- A correction is requested during combat; any protected or UI-sensitive part is deferred and no implicit ledger operation occurs.
- A future eligibility feature adds Curio, Tier Set, main/alt, or probation evidence; the request can reference that decision while older builds display it as an unknown optional field.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide one primary **Report a problem** action from a player's own Dibs transaction or finalized award context.
- **FR-002**: The player report form MUST prefill all available transaction, award, item, season, source, and timestamp context and MUST require no technical identifier from the player.
- **FR-003**: The player MUST be able to submit a report with an optional short category and optional bounded note; the default category MUST be a general Dibs review.
- **FR-004**: The system MUST support at least these report categories: wrong debit, missing debit, duplicate, wrong item or player, eligibility decision, integration problem, and other.
- **FR-005**: A player report MUST be a non-authoritative request and MUST NOT change a balance, award, policy, permission, Pre-Dib, or RCLootCouncil state.
- **FR-006**: The system MUST prevent duplicate active requests for the same player, evidence reference, and issue context, while allowing a new request when materially different evidence exists.
- **FR-007**: The system MUST provide one Officer queue for open, waiting, resolved, and rejected requests with search or bounded filtering and newest-first default ordering.
- **FR-008**: Each Officer request view MUST show the attached Dibs transaction, RCLootCouncil award or history reference, item, winner, response, status, season, balance impact, and evidence confidence when available.
- **FR-009**: Missing or unverifiable fields MUST be shown as unknown or unavailable and MUST never be inferred from another player, another item, or a localized display label alone.
- **FR-010**: The normal Officer review surface MUST provide the primary actions **Correct balance**, **No correction**, and **Ask for information**; advanced actions MUST be grouped separately and explain their effects.
- **FR-011**: A balance-changing resolution MUST require verified guild GM/Officer authority, an explicit confirmation, and a reason, and MUST use the existing protected append-only correction or accounting path.
- **FR-012**: A no-correction, rejection, duplicate, or information request MUST create no balance mutation and MUST record the decision reason and actor.
- **FR-013**: The system MUST support a bounded player reply when an Officer requests information, without allowing the player to edit evidence or administrative fields.
- **FR-014**: A request MUST have a visible status lifecycle including `Open`, `Under review`, `Need information`, `Resolved`, and `Rejected` or equivalent documented states.
- **FR-015**: Players MUST see only their own requests, safe evidence summaries, statuses, questions, replies, and resolution explanations; complete queue data, administrator notes, other players, and private evidence MUST remain Officer-only.
- **FR-016**: The feature MUST make clear that a player can dispute Dibs accounting, eligibility, or integration evidence but cannot use the request to override RCLootCouncil's loot-session award decision.
- **FR-017**: Only verified guild GMs or Officers MAY review, ask for information, resolve, reject, reopen, or apply advanced corrections. Master Looter, Raid Leader, Raid Assistant, and council roles alone MUST NOT grant these rights.
- **FR-018**: Every request, reply, status change, evidence link, resolution, correction, and reopen operation MUST be recorded with stable identifier, actor, timestamp, scope, previous state, new state, reason, and affected transaction when applicable.
- **FR-019**: Existing ledger transactions and RCLootCouncil history MUST remain immutable; any correction MUST use a linked compensating transaction or a separate administrative record.
- **FR-020**: The system MUST prevent a duplicate resolution or second compensating transaction when the same request or evidence is replayed after reload, reconnect, or concurrent Officer review.
- **FR-021**: The feature MUST remain available in standalone mode and when RCLootCouncil is absent or degraded, while clearly separating Dibs-owned evidence from unavailable integration evidence.
- **FR-022**: The feature MUST not expose live candidate lists, votes, private raid discussions, cross-raid state, or unrelated guild data through player reports or safe notifications.
- **FR-023**: All report labels, categories, statuses, primary actions, questions, and explanations MUST be localized with English fallback and MUST use plain language.
- **FR-024**: Report notes, replies, and Officer explanations MUST have bounded lengths and safe display handling so user-provided text cannot become executable content or break the interface.
- **FR-025**: Request and resolution controls MUST be safe during combat; protected UI work is deferred and no report action implicitly changes the ledger.
- **FR-026**: A request may reference reconciliation, readiness, Curio, Tier Set, main/alt, or probation decisions when those features are available, but it MUST not require those features to provide a basic Dibs accounting review.
- **FR-027**: Any shipped request field, SavedVariables schema, protected action, or UI behavior MUST include a dated changelog note and an incremented addon version according to the constitution.

### Key Entities

- **Player Review Request**: A non-authoritative report created by a player, with category, optional note, attached context, status, and creator.
- **Evidence Link**: A reference to a Dibs transaction, RCLootCouncil award or history row, eligibility decision, readiness result, or other source record, with confidence and unavailable fields identified.
- **Officer Review Case**: The complete queue record containing the request, evidence, replies, status transitions, and resolution.
- **Review Reply**: A bounded player response to an Officer question, retained as user-supplied context rather than authoritative evidence.
- **Resolution Decision**: A no-correction, correction, duplicate, information request, rejection, or advanced administrative decision with actor, reason, and time.
- **Compensating Transaction**: An append-only ledger correction linked to the review case and original transaction when a balance changes.
- **Review Status**: The visible lifecycle state of a request, including open, under review, waiting for information, resolved, and rejected outcomes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In usability acceptance tests, a player can submit a report from their own history in under 30 seconds without entering a transaction or award identifier manually.
- **SC-002**: In authority tests, 100% of balance-changing resolutions and advanced review actions succeed only for verified guild GMs or Officers.
- **SC-003**: In automated tests, 100% of player reports, previews, information requests, no-correction decisions, and cancelled actions leave balances and authoritative history unchanged.
- **SC-004**: In duplicate and replay tests, 100% of repeated reports or resolutions create no second active case or compensating transaction for the same evidence.
- **SC-005**: In evidence tests, 100% of review cases display every available source reference and explicitly mark unavailable fields without guessing.
- **SC-006**: In resolution tests, 100% of balance corrections preserve the original transaction and create a linked append-only correction with actor, time, and reason.
- **SC-007**: At least 95% of players can understand their request status and resolution explanation without accessing Officer views or external documentation.
- **SC-008**: At least 95% of Officers can resolve a routine wrong-debit, missing-debit, duplicate, or no-correction case from the main queue without opening an advanced menu.
- **SC-009**: In privacy tests, 100% of normal players are prevented from viewing another player's request, complete evidence, Officer notes, or the full review queue.
- **SC-010**: In standalone and degraded-integration tests, the review center remains usable for Dibs-owned records and causes zero fabricated RCLootCouncil evidence or unauthorized ledger mutation.
- **SC-011**: In combat and reload tests, the feature causes zero protected-action errors and preserves all open requests and their statuses.

## Assumptions

- The primary player flow is intentionally one button with optional detail. Advanced categories, evidence, and correction choices are presented progressively rather than in the first dialog.
- The primary Officer flow is one queue with three common actions. Refund, revoke, historical import, and administrative adjustment remain available through a clearly labeled advanced menu.
- A player report is an appeal of accounting, evidence, eligibility, or integration behavior, not a replacement for RCLootCouncil's council or Master Looter award decision.
- The request queue is guild-scoped and follows the existing GM/Officer authority, multi-guild isolation, privacy, append-only ledger, and diagnostic principles.
- The addon may notify a player of status changes through the existing local or configured guild communication path, but notifications do not include private evidence or cross-raid loot data.
- The feature can use evidence from live awards, historical reconciliation, readiness checks, and future Curio/Tier/Main/Alt decisions without making any one optional feature mandatory.
- Existing protected actions remain the only path to a balance-changing correction. The review center never edits a ledger record in place.
- The default retention for closed requests follows the existing audit retention policy; a future backup/export feature may include them only in a declared sensitive scope.
- External ticketing systems, screenshots, account identity verification, automatic officer assignment, and public dispute boards are outside this feature.
- The feature must obey the current constitution's authority, combat safety, privacy, RCLootCouncil ownership, diagnostics, data isolation, change-note, and versioning rules.
