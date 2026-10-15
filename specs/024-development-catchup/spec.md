# Feature Specification: Development Catch-up

**Feature Branch**: `dev`
**Created**: 2026-10-15
**Status**: Retrospective specification; automated validation in progress; Retail gates open
**Input**: Bring the recent corrections and additions under Spec Kit before saving development and extending the existing request center.

## User Scenarios & Testing

### User Story 1 - Inspect accurate reward information (Priority: P1)

A player sees a Great Vault claim only when sufficient evidence exists and can
record a full item link manually without losing its variant.

**Why this priority**: A base item tooltip must not be mistaken for the acquired reward.
**Independent Test**: Claim fixtures and manual full-link commands preserve the
complete item string, create no Dibs transaction, and never promote a preview
to confirmed evidence.

**Acceptance Scenarios**:
1. **Given** a selected reward, **When** a matching local receipt and claim completion arrive in either order, **Then** exactly one acquisition is recorded.
2. **Given** only an item identifier, **When** history opens, **Then** a base-item tooltip is not represented as the acquired variant.
3. **Given** one currently owned variant, **When** an ID-only entry is displayed, **Then** a labeled owned preview may appear without rewriting evidence.
4. **Given** a full shift-clicked link, **When** manual recording is submitted, **Then** the complete variant and manual verification state are retained.

### User Story 2 - Use reliable shortcuts and delivery (Priority: P1)

Players can toggle their authorized windows and avoid whispers to known-offline recipients.

**Why this priority**: Shortcuts should be predictable and retries should not produce repeated offline-player errors.
**Independent Test**: Repeated minimap clicks alternate visibility; a known-offline recipient receives no queued whisper.

**Acceptance Scenarios**:
1. **Given** an authorized Officer, **When** left-clicking twice, **Then** the Officer window opens and closes; right-click does the same for Player.
2. **Given** a normal player, **When** either shortcut is used, **Then** no Officer access is granted.
3. **Given** an offline guild member, **When** targeted synchronization is attempted, **Then** sending is refused explicitly and recoverable work waits for reconnection.

### User Story 3 - Investigate without changing accounting (Priority: P2)

Officers use descriptive statistics, anonymous audit exports and health reviews;
players and Officers search only their permitted history.

**Why this priority**: Investigation must not become an accounting policy or expose private data.
**Independent Test**: Synthetic reports preserve source records and omit identities
from anonymous exports; unauthorized users receive no Officer data.

**Acceptance Scenarios**:
1. **Given** a player and date range, **When** statistics are requested, **Then** recorded activity is summarized without an invented fairness score.
2. **Given** private audit input, **When** anonymous export is produced, **Then** names, identifiers and free-form private reasons are excluded and the result is not importable.
3. **Given** the history and health features, **When** filters or previews are used, **Then** the contracts of features 022 and 023 remain unchanged.

### Edge Cases

- Expired claims, unrelated receipts, another player's loot, guild changes,
  Developer Mode and ambiguous reward choices must not confirm a claim.
- Several owned variants must not be guessed; recorded exact links win over previews.
- Difficulty describes source content, not the Hero/Myth upgrade track.
- Existing acquisition identity is not replaced by resubmitting a manual command.
- Missing API or authority remains explicit; automated fixtures are not Retail certification.

## Requirements

### Functional Requirements

- **FR-001**: Preserve complete reward links and require sufficient claim evidence; previews alone never confirm an acquisition.
- **FR-002**: Preserve manual ID commands and accept full links containing spaces and either supported color representation, without spending or granting Dibs.
- **FR-003**: Distinguish missing exact variants and display-only owned previews; never rewrite persisted evidence from bag inspection.
- **FR-004**: Toggle Player/Officer minimap routes without expanding permissions; persist per-character icon visibility.
- **FR-005**: Refuse targeted delivery to known-offline recipients explicitly and preserve existing recovery behavior.
- **FR-006**: Provide Officer-only descriptive period statistics and separate bounded anonymous audit export.
- **FR-007**: Retain features 022/023 history, privacy and read-only health contracts rather than duplicating their scope.
- **FR-008**: Record retrospective traceability honestly and leave real-client gates open until performed.

### Key Entities

- **Acquisition**: Existing reward record with original link and verification state.
- **Owned preview**: Transient display, not acquisition evidence.
- **Anonymous report**: Non-importable, bounded investigation output.
- **Validation evidence**: Exact automated suite result with distinct outstanding Retail checks.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All supported link-format fixtures retain the exact complete link.
- **SC-002**: All invalid claim fixtures create zero confirmed acquisitions.
- **SC-003**: Two successive shortcut clicks return each authorized window to its original visibility.
- **SC-004**: Offline-recipient fixtures send zero targeted messages.
- **SC-005**: Anonymous exports contain zero fixture identity or private-note sentinels.
- **SC-006**: Every recent change category maps to a task and a named verification suite or explicit manual gate.

## Assumptions

- This is retrospective documentation, not evidence that specifications preceded code.
- Existing features 013, 016, 017, 022 and 023 own their original requirements.
- No new cancellation policy, RCLootCouncil engine, fairness metric or gameplay automation is introduced.
- The user authorized autonomous catch-up, checkpoint commit/push and subsequent ticket work.
