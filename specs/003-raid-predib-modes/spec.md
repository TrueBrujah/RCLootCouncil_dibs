# Feature Specification: Raid Pre-Dib Modes

**Feature Branch**: `003-raid-predib-modes`

**Created**: 2026-09-05

**Status**: Draft

**Input**: User description: "Add a guild Officer/GM-controlled Wild Open mode where everyone may create Pre-Dibs at any time, and an Encounter mode that allows a player to Pre-Dib only eligible loot from the current raid. Authorized guild Officers and GMs, the current Raid Leader, or the verified RCLootCouncil Master Looter can send non-accounting reminders. The RCLootCouncil Master Looter may manage loot and finalize qualifying DIB awards, but cannot administer Dibs unless also a guild Officer or GM. On entering a raid, players can choose whether to receive a Dib prompt and open the Adventure Guide for the relevant raid or boss."

## User Scenarios & Testing

### User Story 1 - Choose the Guild Pre-Dib Mode (Priority: P1)

As a GM or authorized officer, I can choose a guild-wide Pre-Dib mode so that the guild can either accept advance reservations freely or restrict requests to the current raid encounter.

**Why this priority**: The active mode determines whether a request is valid and must be understood before players make requests.

**Independent Test**: Switch each mode and submit requests from a guild member inside and outside an eligible raid context.

**Acceptance Scenarios**:

1. **Given** Wild Open mode and an active season, **When** a guild member requests a supported raid item, **Then** the request is accepted without requiring the player to be in that raid.
2. **Given** Encounter mode, **When** a guild member requests loot that belongs to the current raid, **Then** the request is accepted only while that raid context is active.
3. **Given** Encounter mode, **When** a guild member requests an item from another raid, a dungeon, or an unsupported context, **Then** the request is rejected with a clear explanation and no request is recorded.
4. **Given** a mode change, **When** an officer reviews existing requests, **Then** previously recorded requests remain auditable and are not silently deleted or rewritten.

---

### User Story 2 - Recover Pre-Dibs Created Before the Raid (Priority: P1)

As an officer joining a raid after players created Pre-Dibs, I can receive the active requests so that early requests are available without requiring an officer to have been online at creation time.

**Why this priority**: A player may reserve an item hours before the raid, and the guild needs that reservation when the raid begins.

**Independent Test**: Create a Pre-Dib while no officer is connected, reconnect an officer before the raid, and verify that the active request appears once the participating player reconnects.

**Acceptance Scenarios**:

1. **Given** no authorized officer is online, **When** a player creates a valid Pre-Dib, **Then** it is kept locally and remains available after the player reconnects.
2. **Given** a player with active Pre-Dibs and an authorized officer are connected, **When** they join the same guild raid, **Then** the officer receives the active requests without duplicate records.
3. **Given** a previously synchronized request, **When** it is delivered again, **Then** the officer sees one request with its original creation time and latest status.
4. **Given** a player never reconnects before the raid, **When** officers review the guild state, **Then** the system does not claim that the unavailable player's local request was received.

---

### User Story 3 - Remind and Guide Raid Members (Priority: P2)

As an authorized guild Officer, GM, Raid Leader, or verified RCLootCouncil Master Looter, I can send a non-accounting Dib reminder, and as a player I can opt into a prompt when entering a raid so that I can quickly review eligible loot and make a request.

**Why this priority**: Timely reminders improve participation without forcing a UI change on every player.

**Independent Test**: Send a reminder during a raid, enter a supported raid with prompts enabled, and verify that opting in opens the relevant Adventure Guide view.

**Acceptance Scenarios**:

1. **Given** an authorized sender in a raid, **When** they send a Dib reminder, **Then** connected raid members receive one understandable reminder appropriate to the group context.
2. **Given** a player has enabled raid-entry prompts, **When** they enter a supported raid, **Then** they are offered a choice to open the Adventure Guide for that raid.
3. **Given** a player accepts a prompt after a boss becomes known, **When** the prompt opens the Adventure Guide, **Then** it shows that boss's loot where available.
4. **Given** a player declines a prompt or disables prompts, **When** they enter a raid, **Then** no Adventure Guide window is opened for that player.
5. **Given** an unauthorized player, **When** they attempt to send a guild Dib reminder, **Then** no reminder is sent and the player receives a clear reason.

---

### User Story 4 - Review Mode-Aware Seasonal Activity (Priority: P3)

As an officer, I can review Pre-Dibs, reminders, and seasonal activity by selected season so that I can explain why a request was accepted or rejected.

**Why this priority**: Operational visibility supports fair decisions over a long season without changing historical accounting.

**Independent Test**: Create requests and reminders in both modes, select the season in the officer interface, and inspect their recorded context and status.

**Acceptance Scenarios**:

1. **Given** a selected season, **When** an officer opens the Pre-Dibs view, **Then** each request displays player, item, status, creation time, and request mode.
2. **Given** a rejected request, **When** an officer reviews the request history, **Then** the reason and the active mode at the time are visible without altering ledger history.

### Edge Cases

- The Adventure Guide filter differs from the player's real raid difficulty in Encounter mode.
- The same item is requested in more than one difficulty.
- A Vault reward has incomplete raid or difficulty provenance.

- A player changes zone while a raid-entry prompt is visible.
- A reminder is requested outside a raid or when the configured announcement channel is unavailable.
- The Adventure Guide does not expose the selected raid or boss loot at the moment of the prompt.
- Multiple officers change mode at nearly the same time.
- A mode changes after a request is created but before its associated item drops.
- A player reconnects with several active requests, including a request already received by an officer.
- The addon is in combat when it needs to display non-critical prompts or refresh officer information.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST provide guild-wide Wild Open and Encounter Pre-Dib modes, with one active mode per guild season.
- **FR-002**: Only authorized GMs and officers MUST be able to change the active Pre-Dib mode.
- **FR-003**: Wild Open mode MUST accept requests for supported raid loot in the active season without requiring the player to be in the relevant raid.
- **FR-004**: Encounter mode MUST accept requests only for supported loot belonging to the active raid context and MUST reject dungeon and unrelated raid loot.
- **FR-005**: The system MUST retain the mode and validation context associated with every request or rejection visible to officers.
- **FR-006**: Changing modes MUST NOT modify, delete, or invalidate existing request and ledger history without an explicit authorized action.
- **FR-007**: A valid Pre-Dib created while no officer is online MUST persist for the requesting player until it reaches a terminal status or the season ends.
- **FR-008**: When a requesting player reconnects with an authorized officer, the system MUST exchange active Pre-Dib state and deduplicate by stable request identity.
- **FR-009**: The system MUST distinguish locally retained requests that have not yet reached an authorized officer from requests received by an authorized officer.
- **FR-010**: Authorized guild GMs/officers, the current Raid Leader, or the verified RCLootCouncil Master Looter MUST be able to send an in-raid reminder. The reminder MUST NOT grant Dibs administration or change settings, mode, balances, or ledger history; Raid Assistant and council status alone MUST be rejected.
- **FR-011**: Each player MUST be able to enable or disable raid-entry Dib prompts independently.
- **FR-012**: A raid-entry prompt MUST require an explicit player choice before opening the Adventure Guide.
- **FR-013**: When a boss is known and supported, accepting the prompt MUST open its loot view; otherwise it MUST open the relevant raid overview or explain why it cannot.
- **FR-014**: Raid reminders and entry prompts MUST not create or consume Dibs by themselves.
- **FR-015**: Officers MUST be able to filter seasonal Pre-Dib history and see request time, status, mode, and synchronization state.
- **FR-016**: The feature MUST preserve append-only ledger behavior, protected-action authority rules, and the existing raid-only item policy in Encounter mode.
- **FR-017**: The feature MUST defer non-critical prompts and UI refreshes when combat safety requires it.
- **FR-018**: Every Pre-Dib request MUST record a normalized raid difficulty when it can be identified.
- **FR-019**: In Wild Open mode, request difficulty MUST come from the Adventure Guide selection used for the request.
- **FR-020**: In Encounter mode, request difficulty MUST come from the player's verified current raid instance, regardless of the Adventure Guide selection.
- **FR-021**: Active request deduplication and award matching MUST distinguish the same item across different raid difficulties.
- **FR-022**: The system MUST record Great Vault acquisitions as non-accounting ownership information with item, known difficulty, source, and timestamp.
- **FR-023**: Recording a Great Vault acquisition MUST NOT consume a Dib, modify a Pre-Dib status, or append a ledger transaction.
- **FR-024**: The Adventure Guide and officer views MUST identify requests and acquired items by their difficulty and source.

### Key Entities

- **Pre-Dib Mode**: The guild-season policy determining whether supported raid item requests are open in advance or restricted to the current raid context.
- **Request Delivery State**: The recorded state indicating whether a player's retained request has been received by an authorized officer.
- **Dib Reminder**: An authorized, non-accounting raid message inviting members to review or submit requests.
- **Raid-Entry Prompt Preference**: A player's saved choice to receive or suppress an optional Dib prompt when entering supported raids.
- **Validation Context**: The season, mode, raid, and loot eligibility information used when evaluating a request.
- **Loot Difficulty**: The normalized Normal, Heroic, or Mythic context attached to a request or acquisition.
- **Acquired Item Record**: Non-accounting ownership information for an item received from the Great Vault.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of valid requests are accepted or rejected according to the selected mode in automated mode-validation scenarios.
- **SC-002**: 100% of active requests created before an officer connects are available to that officer after the requesting player reconnects, with no duplicate request records.
- **SC-003**: 100% of unauthorized reminder and mode-change attempts leave the active mode, ledger, and request history unchanged.
- **SC-004**: 100% of opted-out players enter a raid without an Adventure Guide prompt or automatic window opening.
- **SC-005**: At least 95% of opted-in supported raid-entry and boss prompts present a usable relevant Adventure Guide destination during manual client validation when that destination is provided by the game client.
- **SC-006**: No reminder, prompt, or mode change independently changes a player's Dib balance or rewrites historical ledger transactions.
- **SC-007**: 100% of automated Wild Open requests use the selected Adventure Guide difficulty, while 100% of Encounter requests use the verified current raid difficulty.
- **SC-008**: 100% of recorded Vault acquisitions leave the request count, request statuses, and ledger transaction count unchanged.

## Assumptions

- Wild Open is limited to supported raid loot in the active season; it does not authorize dungeon loot or generic item requests.
- Encounter mode uses the raid and loot information currently available from the game client and rejects requests when that context cannot be verified.
- A request created while all officers are offline can be delivered only after the requesting player and an authorized officer are connected; the game cannot deliver addon state to an offline client.
- Raid-entry prompts open a relevant raid overview on entry; a boss-specific prompt is available only after the current boss can be identified.
- Existing player and officer configuration surfaces will host the new preferences and controls.
- The game client exposes the current instance difficulty while the player is inside a raid; required Encounter-mode validation fails safely when it cannot be verified.

## Out of Scope

- Automatic loot awards. A validated finalized RCLootCouncil `DIB` event may consume the corresponding Dib through the protected accounting path.
- Synchronizing live candidates, votes, drops, or raid discussion.
- Delivering addon messages to players who are offline.
- Rewriting legacy request or ledger history to match a later mode change.
- Automatic detection of a Great Vault reward before the player explicitly records or confirms it.
