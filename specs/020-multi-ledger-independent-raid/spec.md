# Feature Specification: Multi-Ledger Management and Independent Raid Sessions

**Feature Branch**: `020-multi-ledger-independent-raid`

**Created**: 2026-10-12

**Status**: Draft

**Input**: User description: "Le Multi-Ledger et passage en Raid Independant et passer aussi les droit GM au officier aussi et pas besoin de c'est le ledger officiel, mes il devrais etre appouver par le GM parcontre"

## User Scenarios & Testing

### User Story 1 - Multi-Ledger Creation, GM Approval, and Switching (Priority: P1)

As an Officer or Guild Master, I want to create and maintain multiple co-existing guild ledgers (such as for distinct raid teams, schedules, or events), have newly proposed ledgers approved by the Guild Master, and let members switch their active view between approved ledgers while all approved ledgers remain continuously synchronized across the guild.

**Why this priority**: Guilds frequently run multiple raiding groups or different raid schedules where points and allocations must remain isolated without needing separate guilds or external tracking spreadsheets.

**Independent Test**: An Officer creates a second guild ledger; verify it appears in a pending state until the Guild Master approves it. Once approved, verify both ledgers synchronize changes across guild members, and selecting a ledger updates visible balances and transaction history accordingly.

**Acceptance Scenarios**:

1. **Given** an authorized Officer or GM, **When** they create a new guild ledger with a name and starting rules, **Then** the ledger is assigned a unique ledger identifier under the guild root.
2. **Given** a new ledger created by an Officer, **When** the Guild Master reviews guild ledgers, **Then** the GM can explicitly approve the ledger to make it an active, guild-recognized ledger.
3. **Given** multiple approved guild ledgers, **When** a transaction or allocation occurs in any approved ledger, **Then** all online guild members receive and persist the transaction in that ledger's isolated store, even if that ledger is not currently selected in their interface.
4. **Given** a player or officer with multiple approved ledgers available, **When** they switch the active ledger selector in the UI, **Then** the balances, Pre-Dibs, and transaction histories displayed immediately reflect the selected ledger without reloading the game.

---

### User Story 2 - Officer Administration Empowerment (Priority: P1)

As an Officer, I want to configure seasons, rank rules, Pre-Dib policies, loot rules, and run guided setup checks without being blocked by Guild Master-only restrictions, so that our raid team can prepare and launch on time even when the Guild Master is unavailable.

**Why this priority**: In practical guild operations, raid leaders and loot officers are often distinct from the guild master. Forcing the guild master to be present for routine setup creates operational bottlenecks and prevents raids from proceeding.

**Independent Test**: Log in with an Officer character when the Guild Master is offline, launch the setup workflow, create or modify a season and rank allocations, and verify the setup reaches a raid-ready status without requiring Guild Master login.

**Acceptance Scenarios**:

1. **Given** an Officer with verified guild officer permissions, **When** they access setup, seasons, or rank allocation interfaces, **Then** they can create seasons, adjust rank point rules, and configure raid parameters without encountering Guild Master-only blockers.
2. **Given** an uninitialized guild setup, **When** an Officer runs the initial configuration workflow, **Then** the workflow guides them through readying the raid environment while marking any final guild-wide governance adoption as pending GM confirmation rather than blocking all raid prep.
3. **Given** any administrative action performed by an Officer, **When** the transaction or change is committed, **Then** the immutable audit trail clearly records the acting Officer's identity and timestamp.

---

### User Story 3 - Independent Local Raid Sessions (Priority: P2)

As a Raid Leader (who may not be an Officer or GM), I want to run a standalone, temporary raid session with a local ledger for ad-hoc, alt, or community raids, so that loot priority is managed cleanly using standard RCLootCouncil voting without sending guild-wide synchronization or altering official guild ledgers.

**Why this priority**: Guilds run casual weekend raids, alt runs, or joint community groups where loot should be managed fairly for the evening without polluting the guild's permanent seasonal accounting.

**Independent Test**: Start an independent raid session on the Master Looter's client, award an item where a player clicked the DIB response button in RCLootCouncil, and verify the point is deducted in the local session ledger while the guild's official ledgers remain completely untouched.

**Acceptance Scenarios**:

1. **Given** a raid leader preparing an ad-hoc raid, **When** they choose Independent Raid Mode, **Then** a local session ledger is initialized with configurable starting points per attendee without broadcasting ledger creation to the guild channel.
2. **Given** players in the independent raid who only have standard RCLootCouncil installed, **When** an item is put up for vote with the DIB button enabled, **Then** players can vote DIB normally and the Master Looter's local addon displays their session points and consumes points upon award.
3. **Given** Great Vault acquisition data already tracked by the guild, **When** viewing candidates in an independent raid, **Then** Great Vault history remains visible as informational evidence to inform loot decisions.
4. **Given** an independent raid session that has concluded, **When** an authorized guild Officer inspects past sessions, **Then** they have the option to review and selectively reconcile or import awards into an approved guild ledger if desired.

---

### Edge Cases

- **Concurrent Ledger Creation**: Two officers create a new ledger simultaneously with identical or similar names. The system assigns distinct unique ledger identifiers; both appear in the GM review panel with their respective creator identities so the GM can approve, rename, or decline one without data loss.
- **Ledger Invalidation / Retirement**: The GM revokes or archives an approved ledger. The ledger's historical transactions remain preserved in an immutable, read-only archived state and no further live award debits can be recorded against it.
- **Cross-Guild Isolation**: Multi-ledger identifiers must strictly incorporate the guild identity so that members with characters in multiple guilds never experience ledger collision or bleed.
- **Disconnection During Independent Raid**: If the Master Looter disconnects during an independent raid session, the local session ledger state is preserved on disk and restored upon reconnect.
- **RCLootCouncil Absent for Attendees**: Attendees in an independent raid who lack RCLootCouncil or the Dibs addon can still be manually awarded loot by the Master Looter, with the session ledger properly registering the point deduction.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST support multiple concurrent ledgers within a single guild namespace, each identified by a unique ledger identifier.
- **FR-002**: Officers MUST be permitted to create and configure new proposed guild ledgers.
- **FR-003**: A newly proposed guild ledger MUST require explicit approval by the Guild Master before being recognized as an active guild-synchronized ledger.
- **FR-004**: All approved guild ledgers MUST synchronize transactions in the background across guild members regardless of which ledger is currently selected in a given player's interface.
- **FR-005**: The user interface MUST provide a clear selector enabling players and officers to switch the active ledger context for display and live raid operations.
- **FR-006**: The system MUST allow verified Officers to create seasons, configure rank allocations, set Pre-Dib modes, and complete setup workflows without requiring Guild Master role checks.
- **FR-007**: The system MUST support an Independent Raid Mode that operates entirely within a local session ledger on the Master Looter's client without emitting guild-wide synchronization messages.
- **FR-008**: Independent Raid Mode MUST integrate with RCLootCouncil's standard response buttons, enabling attendees without the Dibs addon to participate via normal RCLootCouncil voting.
- **FR-009**: Independent Raid Mode MUST maintain read-only access to existing Great Vault acquisition evidence to inform award decisions during the raid.
- **FR-010**: The system MUST allow authorized Officers to review completed independent raid sessions and selectively import or reconcile specific awards into an approved guild ledger.
- **FR-011**: Every configuration change and ledger transaction across all modes MUST record the actor's canonical identity and timestamp in the audit log.
- **FR-012**: A Guild Master MUST be able to permanently delete a non-default ledger only when
  it is `ARCHIVED`, explicit confirmation is supplied, and guild synchronization is available.
  The deletion MUST be recorded in the governance audit log and broadcast as an idempotent
  guild-wide tombstone. Proposed, approved, active, and default ledgers MUST be rejected.

### Key Entities

- **GuildLedger**: A named, versioned accounting container under a guild root, possessing a unique identifier, an approval status (`PROPOSED`, `APPROVED`, `ARCHIVED`), seasonal rules, and an append-only transaction ledger.
- **IndependentRaidSession**: An isolated, session-scoped local ledger created by a Master Looter for a single raid event, maintaining ephemeral participant balances, awards, and local settings without guild synchronization.
- **LedgerSelector**: The user interface control and state that determines which approved guild ledger or independent session is currently projected on screen and bound to live loot actions.
- **ApprovalRecord**: An auditable governance record signed by the Guild Master establishing that a proposed guild ledger is officially authorized for guild-wide synchronization and use.
- **LedgerDeletionTombstone**: A guild-scoped, idempotent record stating that a Guild Master permanently deleted an archived non-default ledger.

## Success Criteria

### Measurable Outcomes

- **SC-001**: An Officer can complete a guided setup and achieve a raid-ready status in under 2 minutes without needing the Guild Master to log in.
- **SC-002**: Switching between different approved guild ledgers in the user interface updates all balances, tables, and history views in under 500 milliseconds without visual artifacts or reload requirements.
- **SC-003**: 100% of transactions occurring in any approved guild ledger are received and filed in the background by online guild members within standard addon communication thresholds.
- **SC-004**: An independent raid can be started and completed with 0 addon messages sent over the guild broadcast channel, ensuring complete non-interference with official guild accounting.
- **SC-005**: Raid attendees using only standard RCLootCouncil can successfully submit DIB responses that are correctly tracked and deducted by the Master Looter's session ledger in 100% of tested award scenarios.

## Assumptions

- Guild rank hierarchy continues to follow standard World of Warcraft guild rank numbering where Rank 0 designates the Guild Master and configured officer rank indices designate Officers.
- Normal players remain non-authoritative for guild ledger changes and cannot approve or create official guild ledgers.
- Great Vault acquisition records remain shared at the character/guild level and can be safely referenced across all ledger contexts without ledger-specific duplication.
- Independent raid sessions default to local storage on the Master Looter's machine unless explicitly exported or reconciled by an authorized officer.
