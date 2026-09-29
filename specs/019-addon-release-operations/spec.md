# Feature Specification: Addon Release Operations

**Feature Branch**: `019-addon-release-operations`

**Created**: 2026-09-29

**Status**: Draft

**Input**: User description: Record the GitHub and CurseForge release procedure in Speckit so beta releases, stable releases, and new-project approval are handled consistently and are not forgotten.

## User Scenarios & Testing

### User Story 1 - Publish a Tested Beta (Priority: P1)

A maintainer pushes validated work to the development branch and can verify that a beta tag and installable package were created from the tested commit.

**Why this priority**: Beta publication is the recurring path used to validate changes before a stable release.

**Independent Test**: Run the beta workflow with passing tests and packaging, then verify the tag points to the tested commit and the release contains the addon ZIP and checksum.

**Acceptance Scenarios**:

1. **Given** tests or package creation fail, **When** the beta workflow completes, **Then** it does not create or push a beta tag.
2. **Given** tests and package creation pass, **When** the beta workflow completes, **Then** one unique beta tag points to the tested commit and the GitHub prerelease contains the package ZIP and checksum.
3. **Given** the CurseForge project is approved and its repository integration is active, **When** the tag is published, **Then** the matching beta file becomes available on CurseForge.

### User Story 2 - Publish an Explicit Stable Release (Priority: P1)

A maintainer merges validated work to the stable branch, tags the addon version deliberately, and can distinguish a stable release from a beta or release candidate.

**Why this priority**: A branch push alone must not accidentally publish a stable release.

**Independent Test**: Verify a stable version tag matches the addon metadata and creates a non-prerelease GitHub release with the package ZIP and checksum.

**Acceptance Scenarios**:

1. **Given** a normal push to the stable branch without a tag, **When** packaging completes, **Then** only a build artifact is produced and no stable release is published.
2. **Given** a stable tag matches the addon version, **When** the tagged workflow completes, **Then** a normal GitHub release and stable package are produced.
3. **Given** a beta or RC tag is used, **When** release metadata is created, **Then** GitHub marks it as a prerelease and CurseForge channel behavior is checked separately.

### User Story 3 - Submit and Verify a CurseForge Project (Priority: P1)

A project owner submits a complete addon listing and understands that moderator approval is an external gate before files become visible or synchronize.

**Why this priority**: A correct GitHub release cannot bypass CurseForge's review of a new project.

**Independent Test**: Follow the project checklist and verify that the owner can identify the pending-approval state, the configured repository integration, and the expected package layout without creating duplicate projects or tags.

**Acceptance Scenarios**:

1. **Given** CurseForge reports that a new project is awaiting moderator approval, **When** a GitHub tag is published, **Then** the owner does not treat the absence of a synchronized CurseForge file as a packaging failure.
2. **Given** the project is approved and the repository integration is active, **When** a qualifying tag is published, **Then** the owner verifies the expected file and release channel on the CurseForge Files page.
3. **Given** CurseForge requests more information, **When** the owner responds, **Then** the listing is corrected using accurate project metadata and no private credentials are shared.

### Edge Cases

- The GitHub App is not installed on the repository or its Actions variable/secret is missing.
- The addon metadata version and tag base version do not match.
- A beta tag already exists or a workflow is rerun after a tag was created.
- CurseForge remains pending approval and does not synchronize files.
- The native packager classifies an RC tag as Release.
- GitHub creates a package artifact but CurseForge's integration is not connected or configured.

## Requirements

### Functional Requirements

- **FR-001**: The release procedure MUST distinguish beta, stable, and RC tag behavior and identify which action starts each release path.
- **FR-002**: A beta MUST be tagged only after the required tests and package build pass, and the tag MUST identify the tested commit.
- **FR-003**: A normal push to the stable branch MUST NOT create a stable release; stable publication MUST use an explicit version tag matching addon metadata.
- **FR-004**: Release verification MUST check that the expected addon ZIP and checksum are attached to the GitHub release.
- **FR-005**: The procedure MUST state that CurseForge packaging is a separate integration and that GitHub Actions' release ZIP is not itself proof of CurseForge synchronization.
- **FR-006**: The procedure MUST treat CurseForge moderator approval as an external prerequisite for a new project's visibility and file synchronization; it MUST NOT promise or imply a review-time guarantee.
- **FR-007**: The procedure MUST identify the required repository-scoped GitHub App permission and Actions variable/secret names without exposing their values.
- **FR-008**: The procedure MUST warn maintainers not to publish RC tags until CurseForge's RC channel behavior is configured or excluded.
- **FR-009**: A maintainer MUST be able to verify the final tag, tested commit, GitHub package, and CurseForge file/channel from the release checklist.

### Key Entities

- **Release tag**: Versioned marker that selects the beta, stable, or RC release path.
- **Package artifact**: Addon ZIP and checksum produced for a GitHub release and, separately, a CurseForge file.
- **CurseForge project**: Listing whose visibility and file synchronization depend on moderator approval and its repository integration.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every beta release checklist confirms passing tests and packaging before verifying its unique tag.
- **SC-002**: Every stable release checklist verifies an explicit tag whose base version matches addon metadata.
- **SC-003**: A maintainer can distinguish a GitHub artifact from a synchronized CurseForge file using the documented checks.
- **SC-004**: The checklist makes the pending-approval state and its effect on file synchronization explicit, with no promised moderator turnaround time.

## Assumptions

- The repository uses `dev` for beta work and `main` for stable releases.
- The GitHub release workflow produces the GitHub ZIP and checksum; CurseForge uses its own configured repository integration/native packager.
- Moderator review timing is controlled by CurseForge and cannot be accelerated by GitHub workflow changes.
- The repository's developer release guide remains the detailed operational reference; this feature's quickstart is the Speckit release checklist.