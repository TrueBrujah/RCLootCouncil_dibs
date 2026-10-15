# Feature Specification: Data Health Review Center

**Feature Branch**: `023-data-health-review-center`
**Created**: 2026-10-14
**Status**: Implemented; Retail validation pending
**Input**: User description: "Add a data health center that groups anomalies, conflicts, and incomplete acquisitions and offers controlled review actions."

## User Scenarios & Testing

### User Story 1 - Review guild data health (Priority: P1)

An authorized Guild Master or Officer opens the data health center to find actionable data anomalies and unresolved Great Vault acquisition reviews in one place.

**Why this priority**: Officers need to locate data requiring review without inspecting SavedVariables or navigating unrelated logs.

**Independent Test**: Populate a synthetic guild fixture with invalid season references, incomplete acquisitions, and unresolved Vault reviews; verify that the authorized view lists them by category and that another guild's records are absent.

**Acceptance Scenarios**:

1. **Given** an authorized Officer and a guild with reviewable records, **When** the Officer opens the center, **Then** each supported finding appears with a stable category, review state, and safe explanation.
2. **Given** no reviewable records, **When** the Officer opens the center, **Then** an explicit healthy/empty state is shown instead of an error.
3. **Given** a normal player, **When** they request the center's report, **Then** no administrative findings or record identifiers are returned.

### User Story 2 - Preview and route a controlled review (Priority: P1)

An authorized Officer inspects a finding before acting and is directed to an existing audited review workflow when one applies.

**Why this priority**: Review actions must not silently change historical accounting or exceed the Officer's authority.

**Independent Test**: Preview each supported finding and verify that the preview is non-mutating; verify unresolved Vault findings link to the existing Vault review workflow and other findings remain exportable for investigation.

**Acceptance Scenarios**:

1. **Given** a finding in the center, **When** an Officer previews it, **Then** the report identifies the affected category and permitted next step without changing saved data.
2. **Given** a Vault finding with an existing review action, **When** the Officer selects review, **Then** the existing Vault review page opens and retains its permission checks and audit requirements.
3. **Given** an anomaly that has no safe correction workflow, **When** an Officer reviews it, **Then** the center offers investigation/export rather than a destructive or unaudited correction.

### User Story 3 - Export findings for investigation (Priority: P2)

An authorized Officer exports a bounded report of findings to share with another maintainer without exposing player identities or private evidence.

**Why this priority**: Support can diagnose data issues without requesting raw guild data.

**Independent Test**: Export a synthetic report and assert that it contains only supported finding categories and bounded identifiers, excludes names and raw payloads, and cannot be imported as a data package.

**Acceptance Scenarios**:

1. **Given** findings exist, **When** the Officer exports them, **Then** the report is versioned, bounded, and contains no player identities, raw payloads, or executable transactions.
2. **Given** an unavailable encoder or denied authority, **When** an export is requested, **Then** the action reports an explicit failure and provides no success-shaped output.

### Edge Cases

- An acquisition is missing identity fields or its saved collection contains malformed entries.
- The same underlying record is detected by more than one check; the center must avoid presenting duplicate findings for the same issue.
- An Officer loses authority between opening the page and requesting a preview or export.
- A finding references another season or guild scope that is not available to the current client.
- A saved record is historically immutable and has no safe correction path.
- The list is empty, unusually large, or an optional Great Vault capability is unavailable.
- A prior Officer review exists, but the finding is still present in the source data.

## Requirements

### Functional Requirements

- **FR-001**: The center MUST be available only to a verified Guild Master or Officer and MUST recheck authority for each review, preview, and export action.
- **FR-002**: The center MUST group supported data-health findings and unresolved Great Vault acquisition reviews by stable category and review state.
- **FR-003**: The center MUST include invalid season references, incomplete or conflicting Great Vault acquisitions, and supported synchronization or migration warnings when their source service can verify them.
- **FR-004**: Each finding MUST provide a stable identifier, a bounded explanation, and a safe reference to the applicable existing review workflow.
- **FR-005**: Previewing a finding MUST be read-only and MUST show whether an existing audited correction workflow is available.
- **FR-006**: Any supported correction MUST use its existing authority and audit workflow; the center MUST NOT rewrite or delete append-only accounting history.
- **FR-007**: The center MUST NOT offer an unaudited ignore, correction, deletion, or acknowledgement action. Findings without a safe workflow MUST remain available for investigation or export.
- **FR-008**: Any destructive action exposed through a future supported workflow MUST require an explicit preview, a current backup, and confirmation before execution.
- **FR-009**: Export MUST be bounded, versioned, non-importable, and exclude player identities, private evidence, raw synchronization payloads, and executable transactions.
- **FR-010**: The center MUST preserve guild and character data isolation and MUST NOT transmit findings or review details through synchronization.
- **FR-011**: Missing or unavailable data sources MUST be clearly identified and MUST NOT be represented as a clean result.
- **FR-012**: The existing read-only operational health dashboard and its diagnostic disclosure behavior MUST remain available.

### Key Entities

- **Health finding**: A bounded description of a verifiable data condition, its category, status, and safe review destination.
- **Review preview**: A non-mutating explanation of the finding and the actions currently permitted to an authorized Officer.
- **Findings report**: A bounded, versioned, non-importable projection for troubleshooting that excludes personal identities and private evidence.

## Success Criteria

### Measurable Outcomes

- **SC-001**: An authorized Officer can locate each supported finding category from one center without opening SavedVariables.
- **SC-002**: The center shows an explicit empty, unavailable, or denied state in every corresponding case; none is presented as healthy by default.
- **SC-003**: Previewing or exporting findings leaves all source records and accounting history unchanged.
- **SC-004**: Automated privacy checks find no player identity, raw synchronization payload, or executable transaction in exported findings.
- **SC-005**: Existing Great Vault review permission and audit behavior remains unchanged when reached from the center.

## Assumptions

- The existing operational health dashboard in feature 015 remains the source for service readiness, persistence, synchronization, and backup status; this feature adds a review center rather than replacing it.
- Existing audited Great Vault review actions are reused instead of implementing duplicate correction logic.
- Historical append-only transactions remain immutable. Findings without a safe existing correction workflow can be inspected and exported, but not altered or silently dismissed.
- Findings are local to the current authorized guild and are not synchronized.
- Retail client validation remains a separate release gate from automated fixture validation.
