# Feature Specification: Request follow-up and private delivery

**Feature Branch**: existing development branch (no publication requested)
**Created**: 2026-10-15
**Status**: Approved intent; implementation and Retail certification tracked separately
**Input**: Extend the existing Dibs dispute/request center, not a new ticket system.

## User Scenarios & Testing

### User Story 1 — Reliable private submission (Priority: P1)

A player submits their own report or reply and sees whether it is queued, sent,
received, or in error. Officers receive it privately when both clients are online.

**Why this priority**: A local-only request is not a delivered request.
**Independent Test**: Simulate isolated player/coordinator clients, offline retries,
lost acknowledgements, duplicate delivery, reload, and a guild switch.
**Acceptance Scenarios**:
1. Given an offline recipient, submission stays persisted without whisper traffic.
2. Given a capable verified recipient, a retry delivers exactly one report and
   private acknowledgement; receipt does not resolve the report.
3. Given a forged owner, unknown role, old peer, wrong guild, or test context,
   acceptance fails closed without changing balances or disclosing private fields.

### User Story 2 — Focused officer follow-up (Priority: P2)

An officer reviews, replies publicly, assigns a verified responsible officer,
sets a next follow-up, and filters the existing queue.

**Why this priority**: Responsibility and activity must be visible without helpdesk complexity.
**Independent Test**: Verify role checks, public/private projections, due/assigned/
waiting filters and per-character reminder deduplication.
**Acceptance Scenarios**:
1. Public replies reach the owner; internal evidence never enters that projection.
2. Assignment rejects an unverified or non-officer guild member.
3. Due reminders occur only while the client is running and can be snoozed/rescheduled.

### User Story 3 — Retained conclusions and reconciliation (Priority: P2)

Officers conclude, close, archive and search a complete dossier, preserving linked
compensations and reasons.

**Why this priority**: Archival is retention, not deletion or a second correction.
**Independent Test**: Exercise each lifecycle transition and bounded storage failure.
**Acceptance Scenarios**:
1. Resolved or rejected cases can be explicitly closed and then archived with a reason.
2. Archiving never changes the ledger or removes original evidence/history.
3. Reopening a corrected request cannot apply its compensation again.
4. Concurrent officers cannot produce two compensations for one request.

### Edge Cases

Lost ACK; unsupported peer; coordinator unavailable or changed; stale revision;
officer demotion; duplicate active reports; full dossier or outbox; clock changes;
disabled notifications; guild switch; combat; client closed; legacy saved dossiers.

## Requirements

### Functional Requirements

- **FR-001**: Own-player submission/replies MUST persist pending work and bounded retries,
  distinguish sent from received, and retain failures for recovery.
- **FR-002**: Delivery MUST be private and validate actual current guild sender,
  ownership, capability and administrative authority at acceptance.
- **FR-003**: Administrative mutations MUST use a single verified current coordinator
  for delivered requests, reject stale work, and never infer authority from a payload.
- **FR-004**: Officers MUST assign verified officers, reply publicly, record activity,
  and set optional due times; queues MUST filter due, assigned-to-me, waiting,
  resolved, and archived requests.
- **FR-005**: Reminders MUST persist per character, be deduplicated and throttled while
  online, and support explicit snooze/reschedule; replies/resolutions use existing notifications.
- **FR-006**: Add Closed and Archived without changing serialized legacy statuses.
  Transitions require reasons and audit; archives remain searchable complete dossiers.
- **FR-007**: Capacity MUST fail explicitly before mutation, not silently prune dossiers
  or their audit history. Existing history already lost cannot be reconstructed.
- **FR-008**: Guided confirmed compensations MUST reuse existing accounting protections
  and transaction links. Thread/lifecycle actions MUST NOT change balances.
- **FR-009**: Preserve guild/character and Developer Mode isolation, bounded text/
  evidence/storage, EN/FR presentation, and honest pending/unsupported states.

### Key Entities

- **Request**: existing dossier plus revision, assignment, follow-up and lifecycle audit.
- **Delivery**: durable private pending operation, target, attempts, receipt/error state.
- **Reminder**: per-character request/revision due and snooze state.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Replaying a submission ten times creates exactly one accepted dossier.
- **SC-002**: Offline/reload recovery retains all pending submissions in simulated tests.
- **SC-003**: Unauthorized acceptance and private-field leakage are zero in contract tests.
- **SC-004**: A repeated or competing correction creates no additional compensation.
- **SC-005**: Closing/archiving retains every stored evidence, event and transaction link.

## Assumptions

- Clients cannot deliver or remind while WoW is closed; no external notification service.
- A current capable verified coordinator is required for cross-client mutations;
  unavailable or unsupported peers remain pending, not success-shaped.
- Existing local-only dossiers retain legacy workflows; shared dossiers are fenced.
- Shared writes are coordinator-only, including for assigned officers. No automatic
  coordinator/old-epoch handoff recovery exists; a changed pin blocks old dossiers.
- Defaults: 500 dossiers, 120 audit events per dossier; capacity stops further
  mutations rather than deleting history. No automatic correction or physical item transfer.
- Real Retail/multiple-account certification remains an explicit manual gate.
