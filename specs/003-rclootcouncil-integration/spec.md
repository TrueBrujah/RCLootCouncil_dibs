# Feature Specification: RCLootCouncil Permission Authority

**Feature Branch**: `003-rclootcouncil-integration`

**Created**: 2026-09-02

**Status**: Draft

**Input**: User description: "RCLootCouncil doit être la première autorité pour les permissions lorsqu’il est disponible. Si RCLootCouncil refuse une action, le système ne doit pas retomber sur les permissions standalone. Les permissions standalone sont utilisées uniquement lorsque RCLootCouncil est absent."

## Clarifications

### Session 2026-09-02

- Q: Est-ce que RCLootCouncil doit être prioritaire pour toutes les actions protégées, y compris la modification des saisons, des rangs et les ajustements manuels du ledger? → A: Oui, pour toutes les actions protégées lorsque RCLootCouncil est opérationnel; les permissions propres à Dibs sont l'autorité uniquement en mode standalone.
- Q: En mode standalone, quels joueurs doivent pouvoir effectuer toutes les actions protégées? → A: Le maître de guilde et les administrateurs Dibs qu'il configure explicitement.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Respect RCLootCouncil authority (Priority: P1)

As a raid administrator using RCLootCouncil, I want Dibs administrative and loot actions to respect RCLootCouncil's permission decision so that Dibs cannot bypass the raid's established authority model.

**Why this priority**: Permission bypass could allow an unauthorized player to change Dib state or influence a loot decision.

**Independent Test**: With RCLootCouncil available, simulate both an authorized and unauthorized actor and verify that Dibs produces the same allow or deny outcome without consulting standalone permissions after a denial.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil is available and authorizes an actor, **When** that actor requests a protected Dibs action, **Then** Dibs allows the action subject to its non-permission business rules.
2. **Given** RCLootCouncil is available and denies an actor, **When** that actor requests a protected Dibs action, **Then** Dibs denies the action and does not evaluate standalone permissions as a fallback.
3. **Given** RCLootCouncil is detected but its permission decision cannot be obtained, **When** an actor requests a protected action, **Then** Dibs denies the action and reports that authority could not be verified.
4. **Given** RCLootCouncil is operational and its Master Looter is not the guild master, **When** that actor attempts to appoint or revoke a standalone Dibs administrator, **Then** Dibs denies the change because guild-master verification is an additional business rule.

---

### User Story 2 - Preserve standalone operation (Priority: P1)

As a guild using Dibs without RCLootCouncil, I want existing standalone permissions to remain usable so that the core addon does not require RCLootCouncil.

**Why this priority**: Standalone operation is a constitutional requirement and a core compatibility promise.

**Independent Test**: Run Dibs without RCLootCouncil, exercise protected actions with authorized and unauthorized standalone actors, and verify the existing standalone policy decides each result.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil is absent, **When** an authorized standalone actor requests a protected action, **Then** Dibs evaluates and allows it according to standalone policy.
2. **Given** RCLootCouncil is absent, **When** an unauthorized standalone actor requests a protected action, **Then** Dibs denies it according to standalone policy.
3. **Given** RCLootCouncil is absent, **When** the guild master explicitly appoints or removes a Dibs administrator, **Then** that player's standalone authority is updated accordingly.

---

### User Story 3 - Keep Dibs accounting authoritative (Priority: P2)

As a guild officer, I want RCLootCouncil to authorize eligible actions without owning Dib accounting so that balances and history remain recoverable from Dibs alone.

**Why this priority**: Separating permission authority from accounting ownership protects auditability and optional integration.

**Independent Test**: Complete an authorized loot action and verify that its resulting Dib transaction is recorded in Dibs while no RCLootCouncil data is required to rebuild the balance.

**Acceptance Scenarios**:

1. **Given** RCLootCouncil authorizes an action that changes Dib accounting, **When** the action is finalized, **Then** Dibs validates its business rules and appends the resulting transaction to its own ledger.
2. **Given** an item award is proposed but not finalized, **When** Dibs evaluates the event, **Then** no Dib is consumed.

---

### User Story 4 - Expose Dib status locally (Priority: P2)

As a council member, I want to see relevant Dib and Pre-Dib status for candidates in the current local loot session so that the council can make an informed decision.

**Why this priority**: Status visibility supports the loot workflow but must not weaken privacy boundaries or accounting rules.

**Independent Test**: Start a local loot session with candidates having different balances and Pre-Dib states and verify the displayed state matches the Dibs ledger and active requests.

**Acceptance Scenarios**:

1. **Given** a local candidate has an available Dib or applicable confirmed Pre-Dib, **When** the council views that candidate, **Then** the corresponding status is visible through a compatible RCLootCouncil presentation surface or, when none exists, through the local Dibs UI.
2. **Given** a local loot session is active, **When** Dibs shares status with RCLootCouncil, **Then** that live candidate and response information is not sent to other raid groups.

### Edge Cases

- RCLootCouncil is installed but disabled, not loaded, or otherwise unavailable; Dibs treats it as absent and uses standalone permissions.
- RCLootCouncil is available but its authority check raises an error, returns no decision, or returns an unsupported value; Dibs fails closed and does not use standalone fallback.
- RCLootCouncil becomes unavailable during a protected operation; the current operation is denied and a later operation may use standalone policy only after absence is established.
- An actor authorized by standalone policy is explicitly denied by RCLootCouncil; the RCLootCouncil denial wins.
- An actor is authorized but has insufficient Dib balance or fails another Dibs eligibility rule; authorization alone does not make the action valid.
- A RCLootCouncil Master Looter who is not the guild master attempts to change standalone administrators; the action is denied by the guild-master-only business rule without invoking standalone authorization.
- Duplicate finalized-award notifications do not consume more than one Dib.
- A proposed, cancelled, reassigned, or otherwise non-final award does not consume a Dib.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Dibs MUST determine whether RCLootCouncil is available before selecting the permission authority for a protected action.
- **FR-002**: When RCLootCouncil is available, Dibs MUST use its permission decision as the first and exclusive permission authority for every protected action, including season changes, rank-rule changes, Pre-Dib administration, loot actions, and manual ledger adjustments.
- **FR-003**: When RCLootCouncil denies an action, Dibs MUST deny it without consulting standalone permissions.
- **FR-004**: When RCLootCouncil is available but no valid permission decision can be obtained, Dibs MUST deny the action and expose a clear diagnostic reason.
- **FR-005**: Dibs MUST use its own standalone permission system as the sole permission authority only when RCLootCouncil is absent, disabled, not loaded, or otherwise established as unavailable.
- **FR-006**: Permission authorization MUST NOT bypass Dibs balance, Pre-Dib eligibility, season, finalization, idempotency, or ledger validation rules.
- **FR-007**: Dibs MUST remain the authoritative source for Dib balances, Pre-Dib state, and transaction history.
- **FR-008**: RCLootCouncil data MUST NOT be required to reconstruct a player's Dib balance or audit history.
- **FR-009**: A Dib MUST be consumed only after a qualifying item award is finalized.
- **FR-010**: Applying the same finalized award more than once MUST NOT create duplicate consumption transactions.
- **FR-011**: The integration MUST expose relevant Dib and confirmed Pre-Dib status for local candidates through a compatible RCLootCouncil presentation surface when available, and MUST otherwise expose the same status through the local Dibs UI.
- **FR-012**: Applicable Pre-Dib priority rules MUST prevent an ineligible non-Pre-Dib candidate from submitting or having accepted the DIB response while leaving permitted non-Dib responses available.
- **FR-013**: Dibs MUST NOT modify RCLootCouncil's core files or stored accounting data.
- **FR-014**: Live item drops, candidates, council votes, responses, and loot-session state MUST remain local to the raid and MUST NOT enter cross-raid Dibs synchronization.
- **FR-015**: Every protected entry point that can create or alter authoritative Dibs state MUST apply the selected permission check before accepting the change.
- **FR-016**: In standalone mode, the guild master MUST be authorized and MUST be able to explicitly appoint or remove Dibs administrators.
- **FR-017**: In standalone mode, only the guild master and explicitly appointed Dibs administrators MUST be authorized for protected actions; raid leader or raid assistant status alone MUST NOT grant this authority.
- **FR-018**: Appointing or revoking a standalone Dibs administrator MUST additionally require verified guild-master identity in every mode, including when RCLootCouncil authorizes its Master Looter.
- **FR-019**: Every authoritative ledger transaction MUST record the canonical player identity, player rank at transaction time, canonical actor identity or verified system origin, action, timestamp, season, quantity delta when applicable, and related item/reason when applicable.

### Key Entities *(include if feature involves data)*

- **Authority Decision**: The allow or deny result for one actor, protected action, and evaluation time, including which authority produced the result and a diagnostic reason when denied.
- **Protected Dibs Action**: An operation that can configure rules, confirm administrative state, or create an authoritative ledger change and therefore requires permission validation.
- **Standalone Dibs Administrator**: A player identity explicitly appointed by the guild master to perform protected actions when RCLootCouncil is unavailable.
- **Finalized Award Reference**: A stable reference connecting a qualifying local award to at most one Dibs consumption transaction.
- **Candidate Dib Status**: Local, read-only presentation data derived from the Dibs ledger and applicable Pre-Dib state for a candidate and item.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In all authorization tests where RCLootCouncil returns a denial, 100% of protected actions are denied even when standalone policy would allow the actor.
- **SC-002**: In all tests where RCLootCouncil is absent, 100% of protected actions are decided by the standalone policy with no dependency on RCLootCouncil data.
- **SC-003**: In all tests where RCLootCouncil is available but cannot provide a valid decision, 100% of protected actions fail closed with a visible diagnostic reason.
- **SC-004**: Replaying the same finalized award up to 10 times produces exactly one Dib consumption transaction.
- **SC-005**: A balance rebuilt solely from Dibs-owned history matches the displayed balance for every tested authorized award.
- **SC-006**: No test involving a proposed, cancelled, or non-final award changes a player's Dib balance.
- **SC-007**: Inspection of cross-raid synchronization payloads finds zero live loot-session records, candidate lists, votes, or responses.
- **SC-008**: In standalone authorization tests, 100% of guild masters and appointed Dibs administrators are authorized, while 100% of unappointed raid leaders and raid assistants are denied.
- **SC-009**: Inspection of every supported authoritative transaction type finds all constitution-required audit fields populated in 100% of accepted test transactions.

## Assumptions

- RCLootCouncil can provide a definitive permission decision when its integration is operational; the technical mechanism will be selected during planning.
- "Available" means the integration is loaded, enabled, compatible, and capable of answering the required authority check.
- A missing, malformed, or failed authority response from an otherwise available RCLootCouncil integration is not equivalent to absence and therefore fails closed.
- Authorization and Dib eligibility are separate decisions: an authorized actor can still be denied by Dibs business rules.
- RCLootCouncil remains optional and is never the owner of the Dibs ledger or balance history.

## Out of Scope

- Modifying RCLootCouncil core code or its SavedVariables.
- Replacing or removing the standalone permission system used when RCLootCouncil is unavailable.
- Synchronizing live loot-session data, candidate lists, responses, or council votes across raids.
- Making RCLootCouncil authoritative for Dib balances, Pre-Dib state, or audit history.
