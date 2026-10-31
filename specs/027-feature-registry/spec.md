# Feature Specification: Centralized Feature Registry

**Feature Branch**: `027-feature-registry`

**Created**: 2025-01-01

**Status**: Implemented

**Input**: User description: "Provide a centralized feature registry that classifies every module into REQUIRED_CORE / OPTIONAL / CONDITIONAL_DEPENDENCY, supports guild-level on/off configuration with deterministic precedence, manages dependencies with diagnostics, enforces the state on every entry path, and exposes an officer configuration interface, operating-mode handling, and a full test suite."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Guild Master disables a feature (Priority: P1)

A Guild Master opens the officer interface, navigates to the Modules page,
and turns off the RCLootCouncil integration for the guild. The change is
recorded in the canonical operational policy, is synchronized to the other
guild members, and every member's client immediately stops the RCLootCouncil
award adapter while the rest of Dibs keeps working.

**Why this priority**: This is the core value of the feature. Without it, the
optional capabilities of the addon cannot be governed at all.

**Independent Test**: Can be fully tested by adopting governance, calling
`ChangeModules({ rclootcouncil = false })`, and asserting that the RCLootCouncil
adapter refuses to act and that the ledger is untouched.

**Acceptance Scenarios**:

1. **Given** an adopted guild policy, **When** the Guild Master disables
   `rclootcouncil`, **Then** the policy revision advances by one, the change
   is announced to the guild, and the audit trail records the effective
   transition.
2. **Given** `rclootcouncil` is disabled, **When** any member's client
   attempts an RCLootCouncil award, **Then** the attempt is refused with a
   module-disabled reason and no ledger state is written.
3. **Given** a guild with an RCLootCouncil dependency, **When** the Guild
   Master disables `rclootcouncil`, **Then** `historicalReconciliation` is
   disabled in the same change and the officer interface states that
   consequence before the change is saved.

---

### User Story 2 - A member sees a disabled feature (Priority: P1)

A member whose guild turned a feature off opens the corresponding part of the
interface. The feature is not available, no action is possible through any
path, and a clear message explains that the Guild Master disabled it.

**Why this priority**: A disabled feature that remains reachable through an
alternate path is worse than no feature control at all.

**Independent Test**: Can be fully tested by disabling a feature and asserting
that every public entry point for that feature refuses with the documented
reason code.

**Acceptance Scenarios**:

1. **Given** `requests` is disabled, **When** a member calls the dispute
   creation entry point, **Then** it returns `MODULE_DISABLED_REQUESTS` and
   creates no report.
2. **Given** `requests` is disabled, **When** the member uses the slash route,
   **Then** a message is shown and no window opens.
3. **Given** `requests` is disabled, **When** the member opens the officer
   interface on a stale route, **Then** the route renders a disabled state
   rather than a functional workflow.

---

### User Story 3 - A feature with a dependency (Priority: P2)

A Guild Master sees that the Historical Reconciliation feature requires the
RCLootCouncil integration. The interface shows the requirement, refuses to
enable the dependent while its dependency is off, and disables the dependent
automatically when the dependency is turned off.

**Why this priority**: Dependencies must be managed deterministically, or the
guild can reach a state where a feature is nominally on but cannot work.

**Independent Test**: Can be fully tested by turning the dependency off and
asserting the dependent's effective state and the refusal reason code.

**Acceptance Scenarios**:

1. **Given** `rclootcouncil` is off, **When** the Guild Master tries to enable
   `historicalReconciliation`, **Then** the change is refused with
   `MODULE_DEPENDENCY_RCLootCouncil`.
2. **Given** both are on, **When** the Guild Master turns off `rclootcouncil`,
   **Then** `historicalReconciliation` is turned off in the same change.
3. **Given** the Guild Master is about to disable a feature, **When** the
   interface renders it, **Then** the features that would be turned off as a
   consequence are listed.

---

### User Story 4 - A guild upgrades the addon (Priority: P2)

A guild upgrades the addon. The new build adds features to the catalogue. The
existing policy record stays valid, its content hash is unchanged, and no
re-adoption is required. Members still running the previous build keep
synchronizing with the upgraded members.

**Why this priority**: A catalogue that breaks existing records on upgrade
would force every guild to re-adopt its policy and would break the
synchronization chain.

**Independent Test**: Can be fully tested by persisting a record, adding a
catalogue entry, and asserting the record still validates and the chain
continues.

**Acceptance Scenarios**:

1. **Given** a persisted policy record, **When** the catalogue gains a new
   feature, **Then** the record's content hash is unchanged and the record
   still applies.
2. **Given** a record from a peer that carries an unknown feature, **When** the
   record is received, **Then** it is accepted, the unknown feature is
   reported as unknown, and the parent chain is not broken.
3. **Given** a client that received a record with an unknown feature,
   **When** it writes its next local revision, **Then** the unknown key is
   carried forward unchanged.

---

### User Story 5 - An officer diagnoses the configuration (Priority: P3)

An officer wants to understand why a feature is not working. The diagnostic
report lists every feature with its effective state and the reason code that
produced it, and the change history shows who changed the configuration and
when.

**Why this priority**: Diagnostics are required by the project constitution
and make support tractable, but they are not the primary value.

**Independent Test**: Can be fully tested by asserting the diagnostic report
contains one line per feature and that the change history reflects the
recorded changes.

**Acceptance Scenarios**:

1. **Given** a guild with mixed feature states, **When** the diagnostics are
   requested, **Then** every feature appears with its effective state and
   reason code.
2. **Given** a recorded configuration change, **When** the change history is
   requested, **Then** the change is listed with its author and timestamp.

---

### Edge Cases

- A feature identifier that does not exist in the catalogue: it fails closed
  and reports `FEATURE_UNKNOWN`. It is never treated as enabled.
- A required service targeted for change: refused with
  `FEATURE_CORE_IMMUTABLE`.
- A guild that has not adopted an operational policy: the catalogue defaults
  apply and the officer interface offers the Guild Master the governance
  bootstrap action.
- The roster is unavailable when authority is being verified: authority fails
  closed and the change is refused.
- A change is attempted while the developer sandbox is active: refused with
  `MIXED_PROVIDER_REJECTED`.
- A mandatory safety snapshot is required by another operation while the
  backup feature is disabled: the snapshot is still taken, because refusing it
  would leave the calling operation without its recovery point.
- A local patch names a feature this client does not know: refused with
  `INVALID_MODULE_POLICY`. An unknown feature can never be persisted as a
  guild decision.
- Two clients in one guild have different catalogues: both continue to
  synchronize; each ignores the features it does not implement.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST maintain exactly one canonical catalogue of
  features, classified as required core, optional, or conditional dependency.
  No second list of features may exist.
- **FR-002**: The system MUST expose a public registry API that reads the
  canonical catalogue and never duplicates it.
- **FR-003**: Required core features MUST always be enabled, MUST expose no
  toggle, and MUST be refused in any configuration change.
- **FR-004**: The system MUST resolve the effective state of a feature with a
  fixed, deterministic precedence: required always on, unknown fails closed,
  dependency-disabled, then the guild policy value.
- **FR-005**: The system MUST enforce the effective state on every entry path
  of every optional feature, including UI actions, slash commands, public API
  calls, callbacks, network message handlers, and deferred tasks.
- **FR-006**: The system MUST provide a single enforcement gate that every
  optional feature entry point passes through.
- **FR-007**: The system MUST allow only the verified Guild Master or an
  explicitly authorized policy writer to change the configuration, and MUST
  fail closed when authority cannot be verified.
- **FR-008**: The system MUST require the verified authority to be the local
  player.
- **FR-009**: The system MUST store the configuration in the canonical
  operational policy record as a sparse overlay that contains only the
  features a guild explicitly decided.
- **FR-010**: An absent key in the stored overlay MUST mean the catalogue
  default, and the effective state MUST be the overlay applied on the
  defaults.
- **FR-011**: Growing the catalogue MUST NOT change the canonical content hash
  of an existing record, and MUST NOT require a migration or a re-adoption.
- **FR-012**: A local configuration change MUST be rejected when it names a
  feature that the client does not know.
- **FR-013**: A remote record that carries an unknown feature MUST be
  accepted, the unknown key MUST be retained, and the unknown feature MUST
  NOT become effective on the receiving client.
- **FR-014**: The system MUST refuse to enable a feature while a feature it
  depends on is disabled.
- **FR-015**: The system MUST refuse to disable a feature while an active
  dependent is enabled, and MUST allow both to be changed together.
- **FR-016**: The system MUST report the dependency rule as a local write
  constraint and MUST NOT apply it to record shape validation, so that a
  record from a peer with a different catalogue is not rejected.
- **FR-017**: The system MUST synchronize the configuration through the
  existing canonical operational policy entity, with no parallel
  synchronization mechanism.
- **FR-018**: The system MUST validate the actual sender authority at
  acceptance and MUST fail closed on unknown authority.
- **FR-019**: The system MUST record an audit trail of every configuration
  creation, change, and refusal, including the per-feature effective
  transition.
- **FR-020**: The system MUST NOT delete or roll back data belonging to a
  feature when that feature is disabled, and MUST restore it when the feature
  is re-enabled.
- **FR-021**: The officer interface MUST show the category, description,
  effective state, dependency, and consequences of every feature, and MUST
  NOT write to SavedVariables directly.
- **FR-022**: The officer interface MUST preserve the local draft when a save
  fails, so a rejected change does not discard the officer's work.
- **FR-023**: The system MUST keep the required canonical accounting path
  independent of the registry, and MUST NOT classify a feature as optional
  when the canonical accounting path depends on it.
- **FR-024**: The system MUST keep a mandatory safety snapshot that protects
  another operation permitted even when the backup feature is disabled.
- **FR-025**: The system MUST expose a diagnostic report and a change history
  for the configuration.
- **FR-026**: The system MUST keep the canonical accounting mechanisms and the
  RF-0012 locks unchanged.

### Key Entities

- **Feature definition**: The canonical description of one feature. Key
  attributes: key, label, description, category, required flag, always-enabled
  flag, default-enabled flag, optional dependency key, configurable flag.
- **Feature catalogue**: The ordered set of feature definitions. One per
  addon, in `OperationalPolicy`. Versioned by `CATALOGUE_VERSION`.
- **Module overlay**: The sparse map of explicit guild decisions, stored
  under `values.modules` in the canonical operational policy record.
- **Effective state**: The resolved state of a feature, with its reason code
  and, when dependency-blocked, the blocking dependency.
- **Registry guard**: A pluggable in-flight operation check consulted before a
  feature may be disabled, so that the registry does not need to know the
  internals of every domain module.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every feature in the addon appears in exactly one canonical
  catalogue and in the registry, with no discrepancy between the two.
- **SC-002**: Disabling any optional feature causes every documented entry
  point of that feature to refuse with a specific reason code, and no state
  is written.
- **SC-003**: A guild that upgrades the addon with a new catalogue entry
  keeps a valid policy record with an unchanged content hash, and needs no
  re-adoption.
- **SC-004**: A guild can disable a feature and its dependent in one change,
  and the officer interface states the consequence before the change is
  saved.
- **SC-005**: A member who is not the Guild Master and not an authorized
  policy writer cannot change the configuration, and every refusal names the
  exact blocking reason.
- **SC-006**: The canonical ledger, governance, and synchronization
  mechanisms behave exactly as they did before the registry existed, verified
  by the existing non-regression suites.
- **SC-007**: The registry, catalogue, dependency, persistence, compatibility,
  and enforcement behaviour is covered by discriminating tests that fail when
  the corresponding behaviour is removed.

## Assumptions

- The existing canonical operational policy record, its authority model, its
  revision chain, and its synchronization are the correct substrate. The
  feature registry extends them and does not replace them.
- Guild feature configuration is guild-scoped. Per-character preferences such
  as the notification preference remain local and are an inner gate behind
  the guild policy.
- A feature that the canonical accounting path depends on is a required
  service, not an optional feature. `rankRules` is the confirmed case.
- The developer sandbox and developer mode remain local and isolated from
  production accounting and from guild feature configuration.
- The RF-0012 locks and the canonical accounting mechanisms are out of scope
  and remain unchanged.
