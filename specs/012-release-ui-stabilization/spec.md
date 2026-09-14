# Feature Specification: B12 Release UI Stabilization

**Feature Branch**: `012-release-ui-stabilization`

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "/speckit.specify Create the next SpecKit feature: B12 - Release UI Stabilization"

## Normative Design Contract

B12 MUST follow [b12-ui-design-rules.md](../../docs/developer/b12-ui-design-rules.md).
That document is the normative contract for the shared Midnight layout, restrained
visual treatment, contextual secondary actions, authorization-aware menus, dangerous
action confirmation, information-first tables, and release acceptance gates.

## Purpose And Scope

B12 prepares RCLootCouncil_Dibs for a stable, understandable, publishable Retail
release. It is a release stabilization increment, not a full UI rewrite. Existing B00-B11
architecture remains the default: preserve working screens, shared Midnight presentation,
content ownership, protected-action boundaries, domain services, and sandbox isolation.

B12 is divided into independently reviewable release batches:

- **B12a - Runtime UI Stabilization**
- **B12b - Targeted Page Cleanup**
- **B12c - Requests / Dibs Support Tickets**
- **B12d - Historical DIB Transfer**
- **B12e - Release Hardening**
- **B12f - Release Candidate / Publication**

B12 MUST preserve the completed B11 navigation and UI ownership corrections, including
one active routed page, pooled-widget cleanup, Player/Officer isolation, separate window
position state, one page-header owner, canonical option values, safe request disclosure,
and guarded advanced actions.

## Business And Security Freeze

B12 MUST NOT change the semantics or authority of:

- ledger and balances;
- `AWARD_COMMIT` or `AWARD_PROPOSAL`;
- governance and operational policy;
- coordinator and recovery behavior;
- SyncV2;
- identity and production permissions;
- Pre-Dibs lifecycle and mode semantics;
- RCLootCouncil award evidence and ownership;
- developer sandbox isolation or production-provider boundaries.

All authoritative mutations MUST continue through existing protected services and
permission checks. The UI MUST NOT write authoritative state directly.

The existing issue `B11-RETAIL-SANDBOX-001` / `SANDBOX_STORE_TOO_LARGE` remains tracked
separately. It MAY be fixed before release only with bounded, validated behavior. It MUST
NOT be solved by blindly increasing limits. If it remains limited to very large developer
stores while Developer Mode is hidden/off by default, production remains isolated, and
normal users are unaffected, it MAY be documented as a developer-only known limitation
rather than an automatic public-release blocker.

## Clarifications

### Session 2026-09-14

- Q: Should B12c support-ticket categories be presentation-only labels mapped to existing request semantics, rather than new persisted domain fields? → A: Option A - presentation-only labels mapped to existing request semantics.
- Q: Should support-ticket statuses map only to existing request states, with no new persisted ticket lifecycle states? → A: Option A - existing request states only; no new persisted ticket lifecycle.
- Q: Should B12f require an explicit addon version bump when preparing the release candidate? → A: Option A - B12 release candidate requires an explicit addon version bump.

This means B12c MUST NOT add persisted request-category fields, synchronization data,
migration requirements, or new domain meanings solely for the support-ticket presentation.
Support-ticket presentation and actions MUST use existing request states and transitions;
B12c MUST NOT add a separate persisted ticket lifecycle, synchronization payload,
migration requirement, or new state-transition semantics.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Open And Navigate Stable Windows (Priority: P1)

As a player, Officer, or GM, I want Dibs windows to remain stable through ordinary
Retail use so that navigation and repeated opening do not lose content or mix workflows.

**Why this priority**: Runtime defects block every other release workflow and can expose
incorrect or stale information even when domain services are correct.

**Independent Test**: Open and close Player and Officer windows repeatedly, switch every
available route, move each window, refresh or reload, and inspect the visible page and
error log after each transition.

**Acceptance Scenarios**:

1. **Given** a Player or Officer window is opened, **when** the user switches routes,
   **then** exactly one current page is visible and no previous page controls, headers,
   descriptions, or modals remain.
2. **Given** a window has been moved to a valid on-screen location, **when** the user
   changes routes, closes, reopens, or reloads, **then** its position remains usable and
   it does not jump to the top or become immovable.
3. **Given** Player and Officer windows are opened and closed in alternating order,
   **when** either window is reopened, **then** neither window contains the other
   window's controls, page state, callbacks, or content.
4. **Given** a refresh or reload occurs while a page is available, **when** the window
   becomes visible again, **then** the selected page has readable content rather than a
   blank or partially mounted page.
5. **Given** a supported route transition or repeated open/close cycle, **when** the
   UI completes the transition, **then** it produces no self-parent, cyclic-anchor,
   invalid tooltip, or dropdown display/domain-value error.

### User Story 2 - Repair Only Defective Pages (Priority: P1)

As an Officer or GM, I want problematic pages to be clear and predictable without
losing the working parts of the existing UI.

**Why this priority**: Release readiness requires targeted correction while avoiding a
high-risk wholesale rewrite of stable AceConfig/AceGUI workflows.

**Independent Test**: Exercise Pre-Dibs, Settings, Loot Eligibility, Debug, RCLootCouncil,
and any additional page identified by Retail validation, comparing each page against the
shared Midnight contract and its existing service behavior.

**Acceptance Scenarios**:

1. **Given** a page is already readable and stable, **when** B12 validation is performed,
   **then** it remains on the existing architecture without replacement for its own sake.
2. **Given** a page has a demonstrated lifecycle, layout, or Retail runtime defect,
   **when** it is repaired, **then** the correction is limited to the defective page or
   component and preserves its existing domain semantics.
3. **Given** any repaired page is displayed, **when** the user compares it with Player
   and Officer pages, **then** it uses the same simple Midnight shell, text hierarchy,
   spacing, footer, semantic states, and restrained accent treatment.
4. **Given** a page contains secondary row actions, **when** the user right-clicks an
   object, **then** only relevant, authorized actions are shown and generic commands do
   not occupy unnecessary permanent columns.

### User Story 3 - Resolve Requests As Dibs Support Tickets (Priority: P1)

As a non-technical Officer or GM, I want Requests to explain a Dibs problem and guide
me to a safe resolution without requiring ledger expertise.

**Why this priority**: Requests are the most important Officer support workflow and must
be understandable before public release.

**Independent Test**: Review representative requests across supported states and
categories, use the primary support actions, inspect relevant evidence, and verify that
all mutations remain protected and auditable.

**Acceptance Scenarios**:

1. **Given** a request row is visible, **when** the Officer scans it, **then** the row
   clearly identifies who submitted it, the involved player/item, the problem category
   or summary, and current status without a permanent generic Action/Review column.
2. **Given** an Officer left-clicks a request, **when** details open, **then** the page
   leads with the problem, status, relevant evidence, and next action in plain language.
3. **Given** a request detail is open, **when** the Officer uses the normal workflow,
   **then** Ask for information, Resolve, and Reject are visible as primary actions when
   applicable.
4. **Given** a request category is needed, **when** the Officer reviews or submits it,
   **then** supported categories can represent missing Dib, incorrect removal, wrong
   player/item, wrong recipient, award-recipient mismatch, Pre-Dib problem, refund
   request, history problem, general Dibs question, or other without inventing new
   ledger meanings.
5. **Given** an Officer right-clicks a request, **when** the menu opens, **then** it
   provides only relevant secondary actions such as opening the request, viewing the
   player, viewing history, or copying supported identifiers.
6. **Given** an Officer needs a high-risk correction, **when** Advanced Officer Tools
   are opened, **then** Correct player/item, Correct balance, Refund Dib, Revoke Dib,
   and Historical import remain separately disclosed and require existing authorization,
   an explicit reason where applicable, and confirmation before mutation.
7. **Given** a normal Officer lacks authorization for a high-risk action, **when** the
   request is viewed, **then** that action is hidden or unavailable and cannot be
   triggered through a context menu or detail view.

### User Story 4 - Review Historical DIB Transfers Safely (Priority: P2)

As an Officer or GM, I want to review a historical DIB candidate in a concise evidence
view so that confirmation is deliberate and does not alter RCLootCouncil history.

**Why this priority**: Historical transfer is an accounting-adjacent workflow where
readability and confirmation discipline reduce release risk.

**Independent Test**: Open representative candidates, review concise and technical
evidence, reject one, confirm one, and verify stale, ambiguous, unauthorized, and
RCLootCouncil-unavailable outcomes.

**Acceptance Scenarios**:

1. **Given** a historical candidate is selected, **when** review opens, **then** Item,
   Winner, Difficulty, Encounter, Award date, and concise evidence status are visible
   before technical details.
2. **Given** technical evidence exists, **when** the review opens, **then** it is
   collapsed by default and can be expanded without obscuring the primary summary.
3. **Given** a candidate is reviewable, **when** the Officer chooses a primary action,
   **then** Reject and Confirm as DIB are clear, separate, and confirmation-gated as
   required by the existing service.
4. **Given** a candidate is stale, ambiguous, unsupported, incomplete, or unauthorized,
   **when** the Officer attempts review or confirmation, **then** the candidate remains
   visibly blocked or review-required and cannot be presented as confirmed.
5. **Given** an Officer right-clicks a historical candidate, **when** the menu opens,
   **then** only relevant secondary actions are shown; no destructive accounting action
   executes directly from the menu.
6. **Given** a historical transfer is confirmed or rejected, **when** the operation
   completes, **then** RCLootCouncil history and evidence semantics remain unchanged.

### User Story 5 - Prove Retail Release Hardening (Priority: P1)

As a release maintainer, I want repeatable automated and real Retail validation so that
known UI failures are caught before publication.

**Why this priority**: A publishable addon needs evidence from the actual Retail runtime,
not only reduced test doubles.

**Independent Test**: Run the focused regression suites, full suite, diagnostics, and
manual Retail matrix against supported roles, integrations, routes, and window sizes.

**Acceptance Scenarios**:

1. **Given** the focused B12 suites run, **when** they finish, **then** all B12-attributable
   failures are resolved and any unrelated known baseline failure is explicitly recorded.
2. **Given** Player and Officer windows are opened and closed ten times each, **when**
   the sequence completes, **then** both remain functional and isolated.
3. **Given** the user switches repeatedly among all available routes, **when** each route
   is revisited, **then** content remains current, non-blank, single-owned, and free of
   duplicate/stale headers.
4. **Given** each window is dragged and reopened, **when** position is restored, **then**
   movement remains stable and no unexpected top-edge jump occurs.
5. **Given** Pre-Dib modes are changed through their visible controls, **when** supported
   display labels are selected, **then** canonical mode values reach the existing policy
   service and invalid labels fail closed.
6. **Given** RCLootCouncil is available, degraded, or unavailable, **when** relevant
   pages are opened, **then** the UI remains readable and fail-closed behavior is
   preserved.
7. **Given** combat lockdown begins during UI activity, **when** protected work is
   attempted, **then** existing combat-safety deferral and post-combat behavior remain
   intact.
8. **Given** BugSack or equivalent Retail diagnostics are inspected after the matrix,
   **when** results are reviewed, **then** there are zero new Dibs-attributable Lua
   errors, self-parent errors, cyclic-anchor errors, blank-page failures, or
   Player/Officer contamination findings, and zero Dibs-attributable taint findings.

### User Story 6 - Publish A Release Candidate (Priority: P2)

As a maintainer and end user, I want a documented release candidate so that installation,
known limitations, and supported workflows are clear.

**Why this priority**: Publication requires more than code correctness; users need a
traceable version and honest release documentation.

**Independent Test**: Build the release candidate from a clean working state, follow the
installation and player/Officer guides, review known issues, and verify the evidence
links and version metadata.

**Acceptance Scenarios**:

1. **Given** B12 hardening is complete, **when** the release candidate is prepared,
  **then** version, changelog, README, installation guidance, Player guide, Officer/GM
  guide, known issues, checklist, and Retail evidence are aligned.
2. **Given** the sandbox size issue remains, **when** known issues are published,
   **then** it is clearly marked as developer-only and non-blocking only when the stated
   isolation and default-off conditions are verified.
3. **Given** a user installs the release candidate, **when** normal Player and Officer
   workflows are used, **then** the documented primary actions and supported route set
   are available without requiring Developer Mode.

### Edge Cases

- A valid saved window position is near an edge but still on-screen; it must not be
  recentered or clamped merely because a route changed.
- A stored position is actually off-screen or malformed; recovery must restore usability
  without overwriting another window's position record.
- A pooled page contains nested widgets, a modal, a dropdown, or a tooltip when the route
  changes; all stale presentation must close or release before the next page appears.
- Player and Officer windows are reopened in alternating order after several route
  changes; active callbacks and controls must remain scoped to the correct window.
- A grouped navigation callback emits a hierarchical route value; the selected route must
  remain the intended leaf and must not fall back to Dashboard.
- A page has no rows, unavailable integration data, degraded service state, or an empty
  evidence set; the page must remain readable and explain the next safe action.
- A context menu has no applicable actions; it must be absent or empty while primary
  actions remain visible.
- A context menu is opened, then the page/window closes or another menu opens; the first
  menu must close cleanly.
- A normal Officer right-clicks an item with GM-only actions; unavailable actions must not
  be presented as executable.
- A dangerous action is requested without authorization, reason, or confirmation; no
  authoritative mutation may occur.
- A request or historical candidate changes while its detail view is open; stale action
  must be rejected or refreshed rather than applied to a different object.
- A supported display label is returned instead of a canonical Pre-Dib enum key; the
  existing policy receives only the canonical key.
- RCLootCouncil is absent during a page refresh or becomes unavailable after a candidate
  was loaded; the page fails closed without inventing evidence.
- Combat begins during window creation, movement, modal opening, or refresh; protected
  work defers through the existing readiness path.
- The sandbox store exceeds its current safe bound; production state remains untouched
  and the limitation is reported without blindly increasing the bound.
- The known unrelated RCLootCouncil test baseline fails; it remains separately recorded
  and is not silently attributed to B12.

## Requirements *(mandatory)*

### Functional Requirements

#### Release Boundary And Preservation

- **FR-001**: B12 MUST preserve the existing B00-B11 ledger, balance, award, governance,
  policy, coordinator, recovery, synchronization, identity, Pre-Dibs, RCLootCouncil
  evidence, production permission, and sandbox-isolation semantics.
- **FR-002**: B12 MUST preserve working B11 UI architecture and MUST NOT perform a
  wholesale replacement of the existing UI framework or shared Midnight presentation.
- **FR-003**: B12 MUST use the normative B12 UI design contract for every changed page,
  including simple shared Midnight layout, restrained styling, information-first tables,
  contextual secondary actions, shared menus, and confirmation-gated dangerous actions.
- **FR-004**: B12 MUST keep all authoritative mutations behind existing protected
  services and permission checks; UI callbacks MUST NOT write authoritative state directly.
- **FR-005**: B12 MUST keep the existing sandbox provider/store isolation. Any change to
  `SANDBOX_STORE_TOO_LARGE` MUST be bounded, validated, and unable to affect production
  persistence or authority.

#### B12a - Runtime UI Stabilization

- **FR-006**: The system MUST keep Player and Officer window state, content, callbacks,
  menus, and modal ownership isolated across repeated open, close, route, and refresh
  cycles.
- **FR-007**: The system MUST keep exactly one active routed page and one owning content
  surface per window after every supported route transition.
- **FR-008**: The system MUST remove stale widgets, controls, descriptions, headers,
  dropdowns, tooltips, tables, menus, and modals before the next page is mounted.
- **FR-009**: The system MUST preserve valid on-screen window positions through route
  changes, close/reopen, reload, and supported scale changes without unexpected jumps
  or loss of drag behavior.
- **FR-010**: The system MUST recover unusable stored positions without corrupting the
  other window's record or repeatedly restoring during route refreshes.
- **FR-011**: The system MUST prevent or surface no new self-parent, cyclic-anchor,
  invalid tooltip argument, lib-st, or dropdown display/domain-value failures during
  supported UI workflows.
- **FR-012**: The system MUST render a non-blank, readable page after normal refresh,
  reload-like initialization, route transitions, and repeated open/close cycles.
- **FR-013**: The system MUST maintain one owner for each routed page title and optional
  description so duplicate or stale headers cannot remain visible.
- **FR-014**: The system MUST keep supported visible enum controls mapped to canonical
  domain values and MUST fail closed before service invocation for invalid values.

#### B12b - Targeted Page Cleanup

- **FR-015**: B12b MUST repair only pages or components proven defective by focused or
  Retail validation, initially including Pre-Dibs, Settings, Loot Eligibility, Debug,
  RCLootCouncil, and any subsequently proven defective page.
- **FR-016**: B12b MUST keep working portions of each page and MUST NOT replace an existing
  component solely because it uses the established options or UI framework.
- **FR-017**: Every changed page MUST use the shared Midnight shell, simple section
  headers, readable normal and secondary text, restrained accent treatment, semantic
  states, consistent spacing, and stable footer behavior.
- **FR-018**: Every changed list or table MUST prioritize information, avoid unnecessary
  permanent generic action columns, and expose secondary actions through the shared
  context-menu behavior where appropriate.

#### B12c - Requests / Dibs Support Tickets

- **FR-019**: Requests MUST present a support-ticket view centered on submitter, involved
  player/item, problem or category, current status, relevant evidence, and next action.
- **FR-020**: Requests MAY present labels for missing Dib, incorrect removal, wrong
  player/item, wrong recipient, award-recipient mismatch, Pre-Dib problem, refund
  request, history problem, general Dibs question, and other, but those labels MUST
  remain presentation-only mappings to existing request semantics and MUST NOT add
  persisted request fields, synchronization data, migrations, or new ledger meanings.
- **FR-021**: Request detail MUST keep Ask for information, Resolve, and Reject visible
  as the normal primary workflow actions when applicable, using only existing request
  states and transitions; B12c MUST NOT add a separate persisted ticket lifecycle.
- **FR-022**: Request secondary actions MUST use the shared object-aware context menu,
  including supported player, history, identifier, and item-link actions.
- **FR-023**: Advanced Officer Tools MUST separately disclose Correct player/item,
  Correct balance, Refund Dib, Revoke Dib, and Historical import, with existing
  authorization, reason, and confirmation requirements.
- **FR-024**: Request UI MUST hide or disable unavailable advanced actions and MUST NOT
  execute dangerous actions directly from a row or ordinary context-menu item.
- **FR-025**: Request UI MUST preserve privacy boundaries so players cannot see Officer
  request data or administrative evidence outside existing authorization.

#### B12d - Historical DIB Transfer

- **FR-026**: Historical DIB review MUST visibly prioritize Item, Winner, Difficulty,
  Encounter, Award date, and concise evidence status.
- **FR-027**: Technical evidence MUST be collapsed by default and available through an
  explicit disclosure without replacing the readable primary summary.
- **FR-028**: Historical review MUST provide clear Reject and Confirm as DIB actions,
  with existing stale, permission, reason, and confirmation checks preserved.
- **FR-029**: Historical secondary actions MUST use the shared context menu where
  appropriate and MUST NOT directly execute accounting or destructive mutations.
- **FR-030**: Historical workflow MUST NOT write RCLootCouncil history or change the
  established award-evidence semantics.

#### B12e - Release Hardening

- **FR-031**: Release validation MUST cover Player and Officer open/close cycles at least
  ten times each, alternating cross-window use and repeated route switching.
- **FR-032**: Release validation MUST cover every available navigation route, valid window
  movement and restoration, modal lifecycle, dropdown values, Pre-Dib modes, and shared
  right-click menus.
- **FR-033**: Release validation MUST cover combat lockdown during window creation,
  movement, refresh, modal activity, and close, preserving existing deferral behavior.
- **FR-034**: Release validation MUST cover RCLootCouncil available, degraded, and
  unavailable states with fail-closed behavior. The default release gate is a
  single-client Retail matrix; two-client validation is required only if B12 changes
  cross-client behavior.
- **FR-035**: Release validation MUST inspect Retail diagnostics for Lua errors, taint,
  self-parent errors, cyclic-anchor errors, blank pages, stale content, duplicate
  headers, and Player/Officer contamination.
- **FR-036**: The known unrelated RCLootCouncil test baseline MUST remain explicitly
  tracked and MUST NOT be silently classified as a B12 failure or silently ignored.
- **FR-037**: B12 MUST complete real Retail validation before the release candidate is
  declared ready.

#### B12f - Release Candidate / Publication

- **FR-038**: The release candidate MUST include an explicit addon version bump and align
  its version metadata, changelog, README, installation guidance, Player guide,
  Officer/GM guide, known issues, checklist, and Retail validation evidence.
- **FR-039**: Publication documentation MUST state the B12 scope, preserved business and
  security semantics, known limitations, supported workflows, and validation status.
- **FR-040**: A remaining sandbox size limitation MAY be marked developer-only and
  non-blocking only when default-off Developer Mode, production isolation, no simulated
  authority leakage, and unaffected normal-user workflows are evidenced.
- **FR-041**: The release candidate MUST NOT be declared publishable while a required
  Retail release gate remains unvalidated or a B12-attributable blocker remains open.

### Key Entities

- **Release UI stabilization finding**: A reproducible Retail or automated UI defect with
  scope, affected workflow, evidence, correction status, and validation result.
- **Support request**: A Dibs request presented as a readable problem record with submitter,
  involved player/item, category, status, evidence, next action, and authorization scope.
- **Historical DIB candidate**: A reviewable historical award projection with item, winner,
  difficulty, encounter, award date, evidence status, and confirmation state.
- **Release candidate record**: The versioned publication package plus changelog, guides,
  known issues, checklist, and automated/Retail validation evidence.
- **Sandbox limitation record**: The separately tracked status of `SANDBOX_STORE_TOO_LARGE`,
  including whether it is a blocker or documented developer-only limitation and why.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the release matrix, Player and Officer windows complete at least 10
  consecutive open/close cycles each with zero blank pages, stale controls, cross-window
  contamination, or new Dibs-attributable Lua errors.
- **SC-002**: Every available Player and Officer route can be visited and revisited in
  repeated round trips with exactly one current page, one title owner, readable content,
  and no unexpected modal, menu, or dropdown residue.
- **SC-003**: Valid window positions remain draggable and usable through route changes,
  close/reopen, reload, and supported scale changes in 100% of the release validation
  cases.
- **SC-004**: Requests can be reviewed by representative non-technical Officer/GM
  testers with the submitter, problem, status, evidence, and next action identifiable
  without technical knowledge, while advanced mutations remain confirmation-gated.
- **SC-005**: Historical DIB candidates expose all six primary review fields before
  technical evidence and allow deliberate Reject or Confirm as DIB decisions without
  changing RCLootCouncil history.
- **SC-006**: Focused B12 tests and diagnostics report zero B12-attributable self-parent,
  cyclic-anchor, invalid tooltip, dropdown domain-value, blank-page, stale-widget, or
  Player/Officer contamination failures.
- **SC-007**: The full regression result is acceptable for release with every known
  unrelated baseline failure explicitly identified, including the existing RCLootCouncil
  `2/2` versus `1/1` baseline if it remains.
- **SC-008**: Real Retail validation is completed in the single-client release matrix
  for normal Player, Officer, and GM use, RCLootCouncil available/degraded/unavailable
  states, combat transitions, supported window sizes, context menus, and release
  documentation before publication; two-client validation is added when B12 changes
  cross-client behavior.
- **SC-009**: No B00-B11 business, security, synchronization, permission, award-evidence,
  or sandbox-isolation regression is observed in the release candidate.
- **SC-010**: The release candidate can be installed and its primary documented Player
  and Officer workflows completed using the simple Midnight layout without Developer
  Mode or undocumented setup steps.

## Assumptions

- The completed B11 specifications, implementation evidence, and Retail findings are
  the compatibility baseline; B12 corrects remaining defects rather than reopening
  completed architecture.
- The existing protected service and permission boundaries are sufficient for B12; no
  new ledger or authority model is needed for support tickets or historical review.
- The existing shared context-menu facility remains the single menu integration unless
  Retail validation proves it cannot satisfy the normative B12 contract.
- All B12 pages use the existing shared Midnight presentation unless a narrowly scoped
  defective component must be simplified.
- Manual Retail validation requires a supported development client and appropriate
  diagnostics; automated reduced-client tests cannot claim zero Retail taint or Lua
  errors on their own.
- A known unrelated RCLootCouncil test baseline may remain documented separately while
  B12-attributable failures must be resolved.
- B12 release readiness is blocked until real Retail validation is completed, even when
  focused automated tests pass.
