# Feature Specification: Robust RCLootCouncil Integration

**Feature Branch**: `feature/rclootcouncil-integration-robust`

**Created**: 2026-09-06

**Status**: Draft

**Input**: User description: Rework the RCLootCouncil integration so that it is reliable, secure, compatible with Standalone mode, and respects the authority rules for guild administrators and the Master Looter.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use Dibs with or without RCLootCouncil (Priority: P1)

As a guild administrator, I want Dibs to keep the same rules when RCLootCouncil is absent, available, or temporarily incompatible, so that the guild can continue managing Dibs without losing authority or data.

**Why this priority**: Dibs administration and accounting must remain dependable even when an optional loot addon changes state.

**Independent Test**: Load the addon without RCLootCouncil, with a supported RCLootCouncil installation, and with an unsupported or partially available installation. Verify that guild administration, player balances, and existing history remain available and that unsupported integration actions fail safely.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil is not installed, **When** a guild GM or officer opens Dibs settings and manages the ledger, **Then** the action succeeds using the Standalone workflow.
2. **Given** RCLootCouncil is installed but its supported capabilities cannot be verified, **When** a player or loot role attempts an integration action, **Then** the action is rejected with a useful status and Dibs administrative rights are not expanded.
3. **Given** RCLootCouncil becomes available after Dibs loads, **When** the addon rechecks the integration, **Then** supported integration features become available without resetting seasons, balances, requests, or history.

---

### User Story 2 - Finalize a DIB Award Safely (Priority: P1)

As the verified RCLootCouncil Master Looter, I want a finalized DIB decision to consume the correct player's Dib exactly once, so that loot decisions and Dibs accounting remain consistent.

**Why this priority**: This is the only automatic accounting path originating from RCLootCouncil and therefore the highest-risk integration behavior.

**Independent Test**: Run a loot session with a verified Master Looter, finalize a qualifying DIB award, replay the same award, and then finalize non-DIB and test awards. Compare the ledger and player balance after every action.

**Acceptance Scenarios**:

1. **Given** the current verified Master Looter finalizes a qualifying `DIB` response for an eligible player and item, **When** the award is accepted, **Then** exactly one protected Dib consumption is recorded for that player and item.
2. **Given** the same award event is delivered more than once, **When** the duplicate is processed, **Then** no additional Dib is consumed and the existing accounting result is reused.
3. **Given** the response is not explicitly `DIB`, is a test award, or the award identity cannot be verified, **When** the event is received, **Then** production Dibs remain unchanged and the integration reports why it was ignored.
4. **Given** a client is not the current Master Looter, **When** it receives or replays a Master Looter callback, **Then** it cannot finalize an award locally or change the ledger.

---

### User Story 3 - Keep Authority Boundaries Clear (Priority: P1)

As a guild GM or officer, I want Dibs administration to remain under guild authority while the Master Looter manages RCLootCouncil loot, so that no raid role can grant or remove Dibs arbitrarily.

**Why this priority**: Clear separation prevents privilege escalation and makes the rules understandable to the guild.

**Independent Test**: Exercise settings, mode, season, rank, grant, removal, refund, and award actions as a GM, officer, Master Looter, Raid Leader, Raid Assistant, council member, and ordinary player.

**Acceptance Scenarios**:

1. **Given** a current guild GM or officer is authenticated by the guild roster, **When** they change Dibs policy or make a manual ledger correction, **Then** the change succeeds and records the authorized actor.
2. **Given** a Master Looter who is not a guild GM or officer, **When** they manage an RCLootCouncil session, **Then** loot management and qualifying award finalization work, but manual Dibs grants, removals, refunds, settings, and mode changes are rejected.
3. **Given** a Raid Leader, Raid Assistant, or council member without guild authority, **When** they attempt Dibs administration, **Then** the action is rejected regardless of their raid or council role.
4. **Given** a player is not the local verified actor for an incoming action, **When** the action is delivered, **Then** the receiver validates the sender and refuses claimed authority from payload data alone.

---

### User Story 4 - Preserve Loot History and Player Experience (Priority: P2)

As a guild member, I want RCLootCouncil loot information to appear in Dibs without corrupting RCLootCouncil history or exposing private raid data, so that both addons remain predictable.

**Why this priority**: The integration must add Dibs value without taking ownership of another addon’s data or making the raid experience fragile.

**Independent Test**: Review an RCLootCouncil session before and after Dibs is loaded, inspect Dibs player and officer views, and replay an award with missing or partial metadata.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil has existing history entries, **When** Dibs initializes and displays DIB-related records, **Then** unrelated RCLootCouncil entries and identifiers remain unchanged.
2. **Given** an award contains a stable item and winner identity but incomplete optional metadata, **When** it is finalized, **Then** Dibs uses the stable identity, records the available audit context, and does not guess missing authority.
3. **Given** an ordinary player opens Dibs, **When** RCLootCouncil is active, **Then** the player sees only their own balance, requests, and permitted status information.
4. **Given** the integration is unavailable, **When** a player uses Dibs core features, **Then** the player receives a clear standalone status instead of an error or empty accounting state.

---

### Edge Cases

- The RCLootCouncil addon is installed but exposes an unknown or incompatible capability surface.
- The Master Looter changes during a session or is not present when an award callback arrives.
- A callback arrives on a client that is not the Master Looter, or arrives after the session has ended.
- The winner has a cross-realm name, a GUID, or an identity that cannot be matched uniquely.
- The same award is delivered repeatedly, including after a reload or reconnect.
- A DIB response is localized, differently cased, empty, or includes surrounding text.
- The item link is missing, malformed, or cannot be resolved to a stable item identity.
- A guild officer is offline while a player uses Standalone Dibs features.
- RCLootCouncil is disabled after Dibs has persisted previous integration state.
- A normal player attempts to read officer views, diagnostic logs, stored recovery state, or relay state.
- A protocol or SavedVariables version is newer than the version supported by the installed addon.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support Standalone Dibs operation when RCLootCouncil is absent.
- **FR-002**: The system MUST distinguish absent, operational, degraded, and unsupported RCLootCouncil states and expose a clear user-facing status for each state.
- **FR-003**: The system MUST preserve the same guild GM/officer authority policy in Standalone and RCLootCouncil modes.
- **FR-004**: The system MUST verify the current RCLootCouncil Master Looter for each protected loot-finalization action.
- **FR-005**: The system MUST allow the verified Master Looter to manage loot and finalize awards according to RCLootCouncil permissions.
- **FR-006**: The system MUST accept automatic Dibs accounting only for a finalized, explicitly identified `DIB` award that passes item, winner, season, and eligibility validation.
- **FR-007**: The system MUST record a qualifying finalized award through the protected ledger path and MUST consume at most one Dib for one award identity.
- **FR-008**: The system MUST treat duplicate delivery of a finalized award as idempotent and MUST NOT create another consumption.
- **FR-009**: The system MUST reject or ignore non-DIB awards, test awards, missing award identities, unverifiable Master Looter authority, and integration states that cannot be trusted.
- **FR-010**: The system MUST NOT allow the Master Looter, Raid Leader, Raid Assistant, or council membership alone to grant, remove, refund, or adjust Dibs or change Dibs settings.
- **FR-011**: The system MUST validate the local actor and incoming sender before accepting any authoritative integration action.
- **FR-012**: The system MUST preserve RCLootCouncil history entries and identifiers that were not created by Dibs.
- **FR-013**: The system MUST keep Dibs ledger and SavedVariables as the authoritative source for Dibs balances and history.
- **FR-014**: The system MUST NOT transmit live RCLootCouncil candidates, votes, responses, or session state as cross-raid Dibs synchronization data.
- **FR-015**: The system MUST provide safe behavior and a useful diagnostic when optional RCLootCouncil metadata is missing or malformed.
- **FR-016**: The system MUST limit ordinary players to their own Dibs views and MUST protect officer-only data and diagnostic surfaces.
- **FR-017**: The system MUST retain existing Dibs seasons, balances, Pre-Dibs, and audit history when RCLootCouncil is added, removed, or becomes degraded.
- **FR-018**: The system MUST document every shipped addon change in a dated changelog entry and MUST increment the addon version metadata for each addon behavior or build change.
- **FR-019**: The integration MUST report compatibility assumptions for a supported RCLootCouncil release and MUST fail closed when those assumptions cannot be verified.

### Key Entities

- **Integration State**: The verified availability and compatibility status of RCLootCouncil for the current client, including the capabilities that were confirmed.
- **Master Looter Identity**: The current, verified player identity allowed to finalize RCLootCouncil awards for the active session.
- **Finalized Award**: A completed RCLootCouncil loot decision containing a stable award identity, winner, item, response, and validated provenance.
- **Award Accounting Record**: The immutable Dibs ledger entry created from one qualifying finalized award, including its idempotency identity and audit context.
- **Dibs Administrative Actor**: The local guild GM or officer authorized to change Dibs policy or make manual accounting corrections.
- **Compatibility Record**: The documented supported RCLootCouncil surface and release assumptions used to decide whether integration actions are safe.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the complete authority matrix, 100% of manual Dibs policy and ledger actions succeed only for verified guild GMs/officers.
- **SC-002**: For every qualifying award test, one finalized DIB award produces exactly one Dib consumption, and replaying it produces zero additional consumptions.
- **SC-003**: In all absent, degraded, and unsupported integration tests, Dibs core balances and history remain available with zero unauthorized ledger mutations.
- **SC-004**: At least 95% of supported integration scenarios provide a clear success or rejection reason to the user without a Lua error or blocked Dibs window.
- **SC-005**: A compatibility test suite covering supported, absent, degraded, and unknown RCLootCouncil surfaces completes with zero privilege-escalation failures.
- **SC-006**: Manual two-client and live-client validation confirms that a non-ML client cannot finalize a remote ML callback and that ordinary players cannot open officer-only data views.
- **SC-007**: Every release candidate includes a dated changelog entry and a matching addon version increment, with no behavior-changing commit left at the previous addon version.

## Assumptions

- RCLootCouncil remains an optional dependency and Dibs must continue to initialize without it.
- The supported target is the WoW Retail client and the integration may expose only capabilities that can be verified at runtime.
- RCLootCouncil remains responsible for its own loot-session permissions, candidate handling, voting, and item award execution.
- The current guild roster and configured officer rank policy are the source for Dibs administrative authority.
- A qualifying automatic debit is defined by the existing Dibs rules for an explicitly finalized `DIB` response; no automatic debit is inferred from ordinary loot or a player's numeric balance.
- Missing optional metadata is tolerated only when the stable winner, item, award, and authority identities remain verifiable.
- Two-client and live Retail validation are required before the feature is considered release-ready.
- A repository changelog will be the canonical location for dated release notes; the exact file path may be standardized during planning.
- Full distributed convergence of seasons, rank rules, and the ledger is a separate follow-up unless planning proves that a narrow integration change requires it.
