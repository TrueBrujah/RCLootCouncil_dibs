# Feature Specification: First Installation Assistant

**Feature Branch**: `014-first-installation-assistant`

**Created**: 2026-09-22

**Status**: Draft

**Input**: User request to implement Etape 1 from `docs/PUBLIC-ROADMAP.md`: guide a GM or Officer through first installation checks and reach `Ready for raid` without manual SavedVariables editing.

## User Scenarios & Testing

### User Story 1 - Inspect installation readiness (Priority: P1)

As a GM or Officer, I want one guided checklist for RCLootCouncil, permissions, season, rank rules, channels, and loot types so that I can see what remains before the first raid.

**Why this priority**: A new guild needs a trustworthy starting point before any configuration action is attempted.

**Independent Test**: Load a new guild fixture with missing prerequisites, run the assistant projection, and verify each prerequisite has a state, reason, and next action without changing persisted authority data.

**Acceptance Scenarios**:

1. **Given** a GM or Officer opens the assistant, **when** the checks run, **then** the result contains all required installation checks with stable identifiers and actionable states.
2. **Given** RCLootCouncil is absent or degraded, **when** the checks run, **then** the assistant explains that standalone Dibs remains available and does not grant live-award capability.
3. **Given** the viewer is a normal player, **when** the assistant is requested, **then** administrative installation details are denied or reduced to the existing safe readiness projection.
4. **Given** a prerequisite is missing, **when** it is displayed, **then** the assistant identifies the delegated configuration action or explains that an Officer/GM is required.

### User Story 2 - Apply guided configuration safely (Priority: P1)

As a GM or Officer, I want guided actions for supported missing settings so that I can configure the installation from the assistant without editing SavedVariables.

**Why this priority**: The roadmap exit criterion requires a new guild to become ready through supported UI actions.

**Independent Test**: Invoke each supported action with a fixture, verify it delegates to the existing protected action, and verify unauthorized actors and invalid values are rejected without mutation.

**Acceptance Scenarios**:

1. **Given** a missing active season, **when** an authorized Officer submits a valid season action, **then** the existing protected season service receives the canonical payload.
2. **Given** a rank rule or installation mode action, **when** the action is submitted, **then** it uses the existing protected boundary and never writes authority state directly.
3. **Given** an invalid value or unauthorized actor, **when** an action is submitted, **then** the assistant reports the rejection and leaves production state unchanged.
4. **Given** a setting requires RCLootCouncil or a channel unavailable in the current client, **when** the action is selected, **then** it remains explicitly unavailable rather than being simulated as complete.

### User Story 3 - Run a local pre-raid test (Priority: P1)

As a GM or Officer, I want a local dry-run from the assistant so that I can verify the integration before the first raid without creating a ledger transaction or sending live loot data.

**Why this priority**: A local test is the safest way to identify a broken response mapping before live use.

**Independent Test**: Run the assistant dry-run with valid fixture input, verify a bounded result and no ledger, request, RCLootCouncil, or addon-message mutation.

**Acceptance Scenarios**:

1. **Given** local dry-run inputs are valid, **when** the test runs, **then** the assistant reports pass, warning, or failure with a remediation message.
2. **Given** the dry-run runs without RCLootCouncil, **when** the test runs, **then** manual/standalone limitations are reported and no live award capability is implied.
3. **Given** a dry-run is repeated, **when** it runs again, **then** it does not create ledger transactions, consume Dibs, or duplicate persistent records.

## Edge Cases

- No active season or no rank rules exist.
- The current character is not a GM or Officer.
- The guild roster or channel is unavailable during login.
- RCLootCouncil is missing, unsupported, or temporarily degraded.
- No loot categories are configured or only blocked categories are visible.
- A protected action is attempted during combat or with a stale readiness result.
- The user closes and reopens the assistant; the checklist must recompute from current state.

## Requirements

### Functional Requirements

- **FR-001**: The assistant MUST expose stable checks for RCLootCouncil capability, Dibs authority, active season, rank rules, configured channels, and loot types.
- **FR-002**: Each check MUST expose a state, reason, remediation, and whether it blocks `Ready for raid`.
- **FR-003**: Administrative installation details MUST be available only to verified GM/Officer actors; players MUST receive the existing safe readiness projection.
- **FR-004**: Supported configuration actions MUST delegate to existing `ProtectedActions` operations and canonical service values.
- **FR-005**: The assistant MUST NOT write new SavedVariables fields, SyncV2 fields, ledger transactions, or RCLootCouncil state.
- **FR-006**: The assistant MUST use current runtime state when reopened and MUST NOT treat a prior transient result as completion.
- **FR-007**: The assistant MUST offer a local dry-run through the existing `Dibs.DryRun` path.
- **FR-008**: The dry-run MUST remain local and MUST be clearly distinguished from a live Retail certification.
- **FR-009**: Missing optional RCLootCouncil or channel capabilities MUST produce explicit limitations rather than false readiness.
- **FR-010**: All user-facing labels, status text, and remediation messages MUST have English fallback and French localization coverage.
- **FR-011**: The assistant MUST remain usable in standalone mode.
- **FR-012**: The assistant MUST preserve existing combat, permission, privacy, and guild-scoping rules.

## Key Entities

- **SetupCheck**: A transient readiness item with an identifier, state, blocking flag, evidence, and remediation.
- **SetupReport**: A transient aggregate containing checks, overall status, actor scope, and dry-run outcome.
- **SetupAction**: A requested configuration operation mapped to an existing protected action and canonical payload.

## Success Criteria

- **SC-001**: A GM or Officer can inspect all required first-installation checks from one assistant surface without opening SavedVariables.
- **SC-002**: Every missing prerequisite has a visible remediation or an explicit unavailable reason.
- **SC-003**: A valid local dry-run completes without changing ledger transaction count, request state, RCLootCouncil history, or addon-message output.
- **SC-004**: Unauthorized and invalid setup actions are rejected by existing authority checks in 100% of contract cases.
- **SC-005**: Reopening the assistant reflects current runtime state rather than stale completion data.
- **SC-006**: The feature adds no SavedVariables or SyncV2 fields.

## Assumptions

- Existing `Readiness`, `DryRun`, `Permissions`, `Seasons`, `RankRules`, `RCLootCouncil`, and `ProtectedActions` services remain the sources of truth.
- Channel and loot-type checks may be unavailable in standalone or outside a raid and must be represented as explicit non-blocking or blocking states according to the existing readiness policy.
- Completion is derived from current checks; no separate persisted wizard-complete flag is required for the first increment.
- Retail protected-frame and real addon-message behavior remain manual validation gates.
