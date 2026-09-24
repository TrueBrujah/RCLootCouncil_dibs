# Feature Specification: Guild Sync Reliability

**Feature Branch**: `017-guild-sync-reliability`

**Created**: 2026-09-22

**Status**: Draft

**Input**: User description: "Le GM crée des saisons et change le mode Pre-Dibs (Wild Open / Encounter) mais les officiers et joueurs ne les reçoivent pas. Les changements de channel d'annonce ne sont pas reçus non plus. Il faut aussi synchroniser les Dibs des joueurs entre le Master Looter et les officiers, y compris quand une deuxième session de raid simultanée a son propre Master Looter et ses propres officiers."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Award evidence reaches the guild's single ledger authority regardless of raid group (Priority: P1)

A guild runs two raid groups at the same time, each with its own Master Looter and officers. When either Master Looter finalizes a loot award that consumes a Dib, every officer in both raid groups — and the player who used the Dib — must end up with the same, correct balance, even though only one member of the guild is allowed to be the authoritative record-keeper at any moment.

**Why this priority**: Without this, two simultaneous raids can silently diverge on who has spent a Dib, creating double-spend risk and loss of trust in the addon during exactly the scenario (big guild, multiple raid teams) the user is testing.

**Independent Test**: Can be fully tested by having a non-authoritative officer finalize an award while a different officer holds record-keeping authority, and verifying the authoritative officer's, the non-authoritative officer's, and the affected player's balances all converge to the same value without manual intervention.

**Acceptance Scenarios**:

1. **Given** an officer who does not hold record-keeping authority finalizes an award for a player, **When** the authoritative record-keeper is reachable, **Then** the award is automatically forwarded to the authoritative record-keeper, accepted exactly once, and the resulting balance change reaches every online officer and the affected player.
2. **Given** the authoritative record-keeper is temporarily unreachable when a non-authoritative officer finalizes an award, **When** the record-keeper becomes reachable again, **Then** the pending award is still delivered and applied without duplication, and the submitting officer can see that it is still pending until confirmed.
3. **Given** two officers in different raid groups both attempt to finalize an award referencing the same event, **When** both submissions reach the authoritative record-keeper, **Then** only one balance change is applied and the duplicate is recognized as the same event, not a second deduction.

---

### User Story 2 - Season changes reach every officer and player (Priority: P2)

When the Guild Master creates, renames, activates, or archives a season, every officer and player should see the same season list and the same active season without needing to recreate it themselves.

**Why this priority**: Officers cannot manage rank allocations or reconciliation for a season they don't know exists; players see the wrong active season. This is a visible, everyday trust problem but does not itself cause balance corruption the way User Story 1 does.

**Independent Test**: Can be fully tested by having the Guild Master create/rename/archive a season, then confirming an officer's and a player's client show the identical season list and active season without any local action on their part.

**Acceptance Scenarios**:

1. **Given** the Guild Master creates a new season, **When** an officer's client is online, **Then** the officer's season list includes the new season without the officer creating it locally.
2. **Given** the Guild Master archives a season and activates another, **When** a player's client is online, **Then** the player's view of the active season updates to match.
3. **Given** an officer's client was offline when a season was created, **When** the officer's client reconnects, **Then** it catches up to the current season list.

---

### User Story 3 - Officers and the Guild Master can tell when synchronization is not working (Priority: P3)

Guild Masters and officers need a way to notice, without guesswork, when guild-wide settings or season/policy changes are not reaching other members — including because of a version mismatch between clients.

**Why this priority**: This does not fix the underlying propagation problem by itself, but it turns "silent failure" (the exact complaint that started this investigation) into a visible, actionable diagnostic, and prevents wasted troubleshooting time.

**Independent Test**: Can be fully tested by putting two clients into a known-mismatched state (e.g., different versions, or an unconfirmed guild policy) and confirming both surface a clear, specific status rather than appearing to work normally.

**Acceptance Scenarios**:

1. **Given** guild-wide policy changes have never been confirmed/activated by the Guild Master, **When** an officer opens the relevant management screen, **Then** the officer sees an explicit notice that guild-wide policy is not yet active, rather than a silent no-op.
2. **Given** two guild members are running different addon versions that cannot understand each other's synchronization messages, **When** either member checks the addon's status/diagnostic view, **Then** the version mismatch is reported clearly enough that either member knows to update.

### Edge Cases

- What happens when the authoritative record-keeper role changes hands (handoff) while an award is still in transit from a non-authoritative officer? The pending award must still be deliverable to whoever holds authority afterward, not lost.
- How does the system handle the same award being submitted twice (e.g., officer retries after a timeout)? It must be recognized as one event, not counted twice.
- What happens when a season is renamed by the Guild Master at nearly the same time an officer is viewing the old name? The officer's view must update rather than showing a stale name indefinitely.
- What happens when no member currently holds record-keeping authority (e.g., nobody has been designated)? Awards must be held as pending rather than silently dropped or wrongly applied.
- What happens when an officer who submitted a pending award goes offline before it is confirmed? The pending award must still be resolvable from the authoritative side alone.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST automatically forward award evidence created by a non-authoritative officer to whichever guild member currently holds record-keeping authority, without requiring manual copy/resubmission.
- **FR-002**: The system MUST apply each distinct award exactly once, even if the same award evidence is submitted more than once (e.g., due to retries or two officers independently reporting the same event).
- **FR-003**: The system MUST retry delivery of a pending award until the authoritative record-keeper acknowledges it, and MUST survive the record-keeper being temporarily offline.
- **FR-004**: The system MUST let an officer see which of their own submitted awards are still pending confirmation versus already applied.
- **FR-005**: The system MUST propagate season creation, rename, activation, and archival from the Guild Master to every other guild member's client without those members recreating the season locally.
- **FR-006**: The system MUST let a guild member's client catch up on season changes it missed while offline.
- **FR-007**: The system MUST NOT permit a guild member other than the Guild Master or an authorized officer to create, rename, or archive seasons on another member's client (season sync must respect the same authority rules already enforced locally).
- **FR-008**: The system MUST surface a clear, visible notice to officers when guild-wide policy (including the Pre-Dibs mode setting) has not yet been confirmed/activated by the Guild Master, instead of silently discarding subsequent changes.
- **FR-009**: The system MUST report a detectable, distinguishable status when two guild members' addon versions cannot understand each other's synchronization messages, so the mismatch can be diagnosed rather than appearing as a silent no-op.
- **FR-010**: None of the above MUST weaken existing rules that the Dibs ledger is append-only and that only authorized guild roles may create balance-affecting events.

### Key Entities

- **Award Proposal**: A record of a loot award finalized by a guild member who is not the current record-keeping authority; carries enough information (player, item/event reference, submitting officer, raid context) for the authority to confirm it exactly once, and tracks its own delivery/confirmation status.
- **Season Catalog Entry**: A season's identity, name, active/archived state, and lifecycle timestamps, replicated from the Guild Master's authoritative copy to every other guild member.
- **Synchronization Status**: A per-member, human-readable indication of whether guild-wide policy is active, whether season data is current, and whether a peer's protocol/version is compatible.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When two simultaneous raid groups each finalize awards, every online officer's and the affected players' balances match the authoritative record within a normal in-combat delay window, with zero duplicate or lost awards across repeated testing.
- **SC-002**: A season created, renamed, or archived by the Guild Master appears identically for every online officer and player without any local recreation, and any member who was offline catches up automatically upon reconnecting.
- **SC-003**: An officer can determine, without asking the Guild Master, whether guild-wide policy is active and whether their own pending award submissions have been confirmed.
- **SC-004**: A version or protocol mismatch between two guild members' addons is visible in each member's own diagnostic view within one status check, rather than presenting as an unexplained lack of sync.

## Assumptions

- The existing single-authority (one record-keeper at a time) model for balance-affecting ledger changes is retained; this feature adds reliable delivery *to* that authority, not multiple simultaneous authorities.
- "Simultaneous raid sessions" means multiple guild raid groups active at the same time in-game, not multiple guilds; cross-guild isolation is already required by existing project principles and is unaffected by this feature.
- Delivery of guild-wide data (season catalog, award proposals, policy digests) is expected to reach only guild members who are online and connected to the addon's existing communication channel; store-and-forward beyond normal reconnect/catch-up is out of scope.
- Existing authority rules (who may create/rename/archive seasons, who may change guild-wide policy) are reused as-is; this feature does not introduce new roles or permissions.
- Item transfer, live loot candidates, votes, and responses remain outside the scope of what is synchronized, consistent with existing project boundaries.
