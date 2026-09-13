# Feature Specification: Midnight UI and Safe Developer Sandbox

**Feature Branch**: `011-midnight-ui-developer-sandbox`

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "Create feature B11 - Midnight UI/UX Redesign + Safe Developer Sandbox for the existing RCLootCouncil_Dibs addon."

## Scope and Safety Boundary

B11 improves presentation and creates an isolated local developer sandbox. It MUST NOT
change the production semantics or authority of B00-B10: the append-only ledger,
coordinator fencing, governance, identity, SyncV2, recovery, `AWARD_COMMIT`,
`AWARD_PROPOSAL`, RCLootCouncil award evidence, or B08 combat-safe UI ownership.

B11 is divided into these independently revertible implementation batches:

- **B11a - Midnight UI Foundation / Design System**
- **B11b - Safe Developer Sandbox**
- **B11c - Player UI Redesign**
- **B11d - Officer / GM Dashboard**
- **B11e - Requests / Pre-Dibs / Loot Eligibility UX**
- **B11f - RCLootCouncil History Reconciliation UX**
- **B11g - Responsive Layout / Accessibility / Polish**

## Clarifications

### Session 2026-09-13

- Q: After a reload, should the sandbox data remain available for a later explicit re-entry, or should reload discard the sandbox state entirely? -> A: Preserve sandbox data, but require explicit re-entry after reload.

## User Scenarios & Testing

### User Story 1 - Consistent Midnight presentation (Priority: P1)

As a player, Officer, or GM, I want Dibs windows to share one readable visual language,
so that I can understand status and act without learning a different layout on each screen.

**Why this priority**: Every later B11 screen depends on stable visual hierarchy,
semantic state presentation, and predictable controls.

**Independent Test**: Open the player and officer windows in the default environment,
with a supported UI environment present, and with the optional adapter unavailable.
Verify that the same Midnight design tokens, components, fallbacks, and minimum sizes
produce usable windows in all three cases.

**Acceptance Scenarios**:

1. **Given** no external UI environment is available, **when** a Dibs window opens,
   **then** it uses the complete native Midnight presentation without errors.
2. **Given** an optional UI environment provides presentation hints, **when** a Dibs
   window opens, **then** only local presentation values adapt and all Dibs controls
   remain available.
3. **Given** a presentation adapter is absent, unsupported, or raises an error,
   **when** the window is created or refreshed, **then** Midnight native fallback is
   restored without changing Dibs policy, ledger, sync, or authority state.
4. **Given** a secondary action is available on a player, item, request, season, or
   history row, **when** the user opens its context menu, **then** the menu shows the
   secondary action while every critical primary action remains visible in the page.

### User Story 2 - Isolated developer sandbox (Priority: P1)

As an addon developer, I want to test player, Officer, GM, coordinator, recovery,
and RCLootCouncil states without real guild members or production mutations.

**Why this priority**: Safe testing is required to validate the redesigned screens
without weakening the production governance model.

**Independent Test**: Enable developer mode, clone production state into the sandbox,
exercise each simulated role and fault scenario, inspect production state after every
operation, exit the sandbox, reload, and verify that production services and authority
are restored.

**Acceptance Scenarios**:

1. **Given** developer mode is off, **when** the user opens Dibs navigation,
   **then** Developer and Debug pages are hidden and developer commands do not perform
   sandbox operations.
2. **Given** developer mode is on but the sandbox is inactive, **when** the user
   selects a simulated role or coordinator state, **then** the request is rejected and
   production authority is unchanged.
3. **Given** an active sandbox, **when** the user clones or refreshes production data,
   **then** a separate sandbox snapshot is created and subsequent sandbox mutations
   affect only sandbox state.
4. **Given** an active sandbox with simulated GM or coordinator authority, **when** a
   sandbox workflow performs grants, policy changes, coordinator changes, recovery,
   or test ledger events, **then** no production SavedVariables, production balance,
   production policy, production coordinator, production baseline, or production
   ledger entry changes.
5. **Given** the sandbox is active, **when** the user exits or reloads, **then** the
   production provider is restored, simulated authority is cleared, and the warning
   identifies that production is no longer being modified.
6. **Given** production services and simulated sandbox authority would both be active,
   **when** a protected operation is evaluated, **then** the operation fails closed
   instead of combining the two authorities.

### User Story 3 - Player answers the three daily questions (Priority: P1)

As a player, I want the Player window to show my balance, current requests, and request
entry point immediately, so that I can complete a normal Dibs task during raid preparation.

**Why this priority**: Player workflows are the highest-volume user-facing surface and
should not require understanding ledger internals.

**Independent Test**: With representative balance, active Pre-Dibs, pending requests,
empty history, unavailable RC, and degraded readiness states, open My Dibs, Requests,
and History and complete a request and cancellation using visible primary controls.

**Acceptance Scenarios**:

1. **Given** a player has a current season and balance, **when** My Dibs opens,
   **then** Balance, Active Pre-Dibs, Pending Requests, Current Season, and a simple
   readiness state are visible before technical details.
2. **Given** the player has an active Pre-Dib, **when** Requests opens, **then** the
   item, difficulty, status, and visible Cancel action are shown without exposing other
   players' private data.
3. **Given** the player enters an item link or supported ID, **when** the visible
   request action is submitted, **then** the existing request service validates and
   owns the operation; the UI does not write ledger state directly.
4. **Given** a player opens History, **when** rows are displayed, **then** the view
   shows the player's own readable history and keeps ledger, sync, and coordinator
   internals behind optional details.

### User Story 4 - Officer and GM operate from a dashboard (Priority: P1)

As an authorized Officer or GM, I want grouped navigation and a concise dashboard,
so that I can see operational health and move directly to requests, rules, history,
and integrations.

**Why this priority**: Administrative workflows need fast scanning without weakening
existing GM-versus-Officer authorization boundaries.

**Independent Test**: Open the dashboard as a player, Officer, and GM using matching
fixture states; verify visibility, grouped navigation, summary values, and permission
outcomes for each role.

**Acceptance Scenarios**:

1. **Given** a verified Officer or GM, **when** the dashboard opens, **then** it
   summarizes active season, ledger status, sync status, coordinator state,
   RCLootCouncil capability, pending requests, active Pre-Dibs, and recent activity.
2. **Given** a normal player opens the Dibs UI, **when** officer pages are requested,
   **then** private administrative data and actions remain unavailable.
3. **Given** a technical status is degraded or blocked, **when** the dashboard shows it,
   **then** the primary message is human-readable and technical reason codes are
   expandable diagnostics rather than the headline.
4. **Given** Developer Mode is off, **when** the dashboard navigation is built,
   **then** Developer and Debug groups are absent.

### User Story 5 - Requests and eligibility use progressive disclosure (Priority: P2)

As an Officer or player, I want request, Pre-Dib, and loot eligibility screens to show
common decisions first and advanced policy details only when requested.

**Why this priority**: The workflows are important but currently expose too much
configuration at once, increasing the chance of incorrect choices.

**Independent Test**: Exercise request review, Pre-Dib mode, and recommended eligibility
preset screens with ordinary, blocked, and exceptional item families.

**Acceptance Scenarios**:

1. **Given** the recommended eligibility preset is selected, **when** the page opens,
   **then** Curio, Tier Set, and Token are visibly allowed while Mount, Pet, and
   Cosmetic are visibly blocked, with a clear Customize action.
2. **Given** an advanced category detail is collapsed, **when** the user expands it,
   **then** the semantic rule, reason, and editable control appear without changing
   production policy until an authorized save action is confirmed.
3. **Given** a request is pending or unavailable, **when** the user reviews it,
   **then** status, next action, and safe explanation are visible without exposing
   private candidate, vote, or live loot-session data.

### User Story 6 - History reconciliation is a guided review workflow (Priority: P2)

As an Officer or GM, I want to search, review, confirm, or reject RCLootCouncil
history candidates in distinct steps, so that evidence decisions are deliberate and auditable.

**Why this priority**: Reconciliation is a high-risk administrative workflow where
clarity must improve without changing B09 evidence semantics.

**Independent Test**: Search a bounded history set, inspect possible Dibs candidates,
expand technical evidence, reject one candidate, confirm another, and verify that the
existing protected confirmation path remains the only mutation path.

**Acceptance Scenarios**:

1. **Given** a valid search scope, **when** Search runs, **then** the screen reports
   rows scanned, possible Dibs, ignored rows, and ambiguous rows before review.
2. **Given** a candidate is selected, **when** Review opens, **then** item, winner, date,
   response, and concise evidence summary are primary, while raw technical evidence is
   expandable.
3. **Given** a candidate is rejected or confirmed, **when** the action is submitted,
   **then** the existing permission-checked reconciliation service records the decision;
   the UI never writes RCLootCouncil history or bypasses protected accounting.
4. **Given** a candidate is ambiguous, unsupported, or missing required evidence,
   **when** it is displayed, **then** it remains reviewable as blocked/ambiguous and
   cannot be presented as a confirmed Dibs award.

### User Story 7 - Windows remain readable at supported sizes (Priority: P2)

As any Dibs user, I want windows to resize predictably and remain readable, so that
text, tables, menus, and dialogs do not overlap or become unusable.

**Why this priority**: Readability and accessibility affect every workflow and are
necessary for the redesigned screens to be dependable in real raid layouts.

**Independent Test**: Resize each B11 window through its supported minimum, typical,
and wide sizes; exercise long labels, truncated values, empty states, nested lists,
modal dialogs, and high-contrast presentation hints.

**Acceptance Scenarios**:

1. **Given** a window is at its supported minimum size, **when** long text and tables
   render, **then** controls do not overlap, minimum column widths are preserved, and
   truncated values have a tooltip or equivalent readable detail.
2. **Given** a scrollable page contains a table or list, **when** the user scrolls,
   **then** one clear owner handles scrolling and dropdowns or modals do not cover
   unrelated content.
3. **Given** a user increases local UI scale or enables high-contrast presentation,
   **when** a screen refreshes, **then** selected state, warnings, and actions remain
   distinguishable by text, shape, or state treatment in addition to color.
4. **Given** a window receives frequent state changes, **when** several changes occur
   within one refresh interval, **then** the UI coalesces refresh work and does not
   rebuild the full complex screen for every event.

## Edge Cases

- Developer Mode is enabled while the sandbox is inactive; no simulated authority is
  available and no production authority is changed.
- A sandbox clone is malformed, future-versioned, partially missing, or too large;
  activation fails closed and production data remains untouched.
- Production reload occurs after simulated GM, Officer, coordinator, recovery, or fault
  state was active; the production provider must not retain simulated authority, while
  the separate sandbox data remains available only for later explicit re-entry.
- A sandbox provider and production provider are both reachable; protected operations
  reject the mixed state rather than selecting one implicitly.
- Sandbox reset, exit, or deletion fails midway; production state remains unchanged and
  the sandbox reports a recoverable local error.
- An optional ElvUI, Tukui, EllesmereUI, or BenikUI-family adapter is installed but
  unsupported, throws an error, or supplies invalid media; Midnight native fallback is
  used.
- LibSharedMedia lacks a requested font, texture, or status-bar media; a safe Blizzard
  fallback is used without changing saved policy.
- A context-menu target has no secondary actions; the menu is absent or empty while
  primary actions remain visible.
- A player lacks a current season, has zero balance, has no requests, or has a large
  history; empty states remain informative and bounded.
- A table contains unusually long localized names, item links, realm names, or reason
  text; layout remains stable and details remain accessible by tooltip or expansion.
- RCLootCouncil is absent, degraded, unsupported, or has unavailable history; the UI
  presents a human-readable state and does not read arbitrary integration internals.
- A reconciliation result changes while the review page is open; stale confirmation
  is rejected or refreshed rather than silently confirming a different row.
- Combat lockdown begins while a window is opening, refreshing, moving, or changing
  a protected control; existing B08 deferral and readiness rules remain authoritative.

## Requirements

### Functional Requirements

#### B11a - Midnight UI Foundation

- **FR-001**: The system MUST provide one primary visual theme named Midnight; it MUST
  not create separate ElvUI, Tukui, or other replacement themes.
- **FR-002**: The system MUST centralize colors, semantic status colors, fonts, font
  sizes, spacing, padding, row heights, borders, surfaces, component sizing, scale,
  and density as reusable presentation tokens.
- **FR-003**: Complex application screens MUST use Dibs-owned reusable components;
  simple persistent settings MAY remain in the existing options surface.
- **FR-004**: The UI MUST provide only the reusable components required by B11 screens,
  including consistent windows, panels/sections, navigation/tabs, buttons,
  status badges, fields, dropdowns, checkboxes, lists/tables, modals, tooltips, and
  empty states where used.
- **FR-005**: Presentation media MUST prefer the available shared-media service for
  fonts, status bars, and textures, with safe Blizzard/native fallbacks.
- **FR-006**: Optional UI environment adapters MAY provide only presentation hints
  such as font/media, density, borders, status-bar texture, or scale. Adapter absence,
  failure, or unsupported status MUST fall back to native Midnight.
- **FR-007**: All appearance settings and UI environment hints MUST remain local
  presentation state and MUST NOT enter guild policy, ledger, sync, governance,
  identity, or reconciliation state.
- **FR-008**: Secondary actions MAY be exposed through the existing context-menu
  facility for players, items, requests, Pre-Dibs, seasons, and history rows, but
  critical primary actions MUST remain visible outside context menus.

#### B11b - Safe Developer Sandbox

- **FR-009**: Developer and Debug navigation MUST be hidden by default and MUST become
  available only while local Developer Mode is explicitly enabled.
- **FR-010**: The commands `/dibs dev on`, `/dibs dev off`, and `/dibs dev status` MUST
  control or report local Developer Mode without granting production authority.
- **FR-011**: Simulated PLAYER, OFFICER, and GUILD_MASTER roles and coordinator on/off
  state MUST be available only inside an active sandbox.
- **FR-012**: Sandbox role and coordinator simulation MUST use a provider/service
  boundary; production permission, governance, identity, coordinator, and recovery
  services MUST never treat simulated values as production facts.
- **FR-013**: The sandbox MUST use a physically separate, versioned developer store
  and MUST preserve the existing production SavedVariables schema and values. Sandbox
  data MAY persist across reloads in that separate store, but reload MUST clear active
  sandbox state and simulated authority.
- **FR-014**: The sandbox MAY clone or refresh production state only through an explicit
  production-to-sandbox operation. Sandbox mutations MUST operate only on sandbox state.
- **FR-015**: The system MUST provide sandbox lifecycle operations equivalent to enter,
  refresh, reset, and exit, with an obvious persistent warning stating that production
  is not being modified and identifying simulated authority.
- **FR-016**: The sandbox MUST provide reusable local scenarios for normal player,
  zero balance, active Pre-Dibs, pending Officer requests, GM operation, active or
  unavailable coordinator, `SYNC_BEHIND`, `RECOVERY_PENDING`, absent/degraded/
  unsupported RCLootCouncil, large request/history sets, ambiguous identity, and
  competing proposals.
- **FR-017**: Sandbox fault and state injection MUST be limited to sandbox state and
  MUST NOT emit production addon traffic, fake global events, live loot events, or
  RCLootCouncil authority/evidence.
- **FR-018**: The system MUST fail closed when production and simulated providers are
  simultaneously selected or when sandbox state is invalid, unsupported, or future-versioned.
- **FR-019**: There MUST be no sandbox-to-production mutation, merge, commit, overwrite,
  balance transfer, policy transfer, coordinator transfer, baseline transfer, or ledger
  import path.
- **FR-020**: The system MUST explicitly prove these invariants: Developer Mode alone
  cannot grant production authority; simulated GM exists only in an active sandbox;
  sandbox balance/policy/ledger/coordinator/recovery changes cannot affect production;
  reload cannot retain simulated authority with the production provider; exit restores
  normal production services; and no sandbox-to-production write path exists.

#### B11c - Player UI Redesign

- **FR-021**: The Player UI MUST prioritize My Dibs, Requests, and History navigation.
- **FR-022**: My Dibs MUST present balance, active Pre-Dibs, pending requests, current
  season, and a simple readiness status without exposing coordinator internals, ledger
  epochs, policy revisions, sync hashes, or technical capability diagnostics by default.
- **FR-023**: Player request, cancellation, history, and acquisition actions MUST
  delegate to existing domain services and MUST NOT write authoritative state directly
  from UI callbacks.
- **FR-024**: Player views MUST remain scoped to the current player's permitted data
  and must preserve existing privacy and authorization behavior.

#### B11d - Officer / GM Dashboard

- **FR-025**: Officer UI navigation MUST group Dashboard, Requests, Pre-Dibs, History,
  Seasons, Rank Rules, Loot Rules, Announcements, RCLootCouncil, Settings, and
  Diagnostics under the requested information architecture.
- **FR-026**: The dashboard MUST summarize active season, ledger, sync, coordinator,
  RCLootCouncil capability, pending requests, active Pre-Dibs, and recent activity;
  technical details MUST be expandable.
- **FR-027**: B11 MUST preserve existing GM-only and Officer permissions for every
  administrative view and mutation, including through context menus and sandbox boundaries.
- **FR-028**: RCLootCouncil and readiness status MUST use normalized adapter/service
  state and human-readable primary messages; raw internal error codes belong only in
  expandable diagnostics.

#### B11e - Requests / Pre-Dibs / Loot Eligibility UX

- **FR-029**: Request, Pre-Dib, and eligibility screens MUST use progressive disclosure
  so common decisions are visible before advanced configuration.
- **FR-030**: The eligibility presentation MUST provide a Recommended preset that
  visibly allows Curio, Tier Set, and Token families and visibly blocks Mount, Pet,
  and Cosmetic families, subject to existing authoritative policy.
- **FR-031**: Advanced eligibility details MUST expose semantic category, current state,
  reason, and authorized customization without changing production policy before an
  explicit valid save action.
- **FR-032**: The redesigned request and eligibility UX MUST preserve existing request
  lifecycle, character eligibility, policy, ledger, sync, identity, and combat rules.

#### B11f - RCLootCouncil History Reconciliation UX

- **FR-033**: History reconciliation MUST present distinct Search, Review Candidates,
  Confirm/Reject, and Complete stages.
- **FR-034**: Search results MUST report bounded rows scanned, possible Dibs, ignored
  rows, and ambiguous rows before review.
- **FR-035**: Candidate review MUST prioritize item, winner, date, response, and concise
  evidence summary; technical evidence MUST be expandable.
- **FR-036**: Confirm and reject actions MUST delegate to the existing permission-checked
  reconciliation service and MUST not write RCLootCouncil history, alter B09 evidence
  semantics, or bypass protected accounting.
- **FR-037**: Ambiguous, unsupported, stale, or incomplete candidates MUST remain
  visibly blocked or review-required and MUST NOT be presented as confirmed awards.

#### B11g - Responsive Layout / Accessibility / Polish

- **FR-038**: Each B11 window MUST define minimum dimensions, responsive resize behavior,
  table minimum column widths, row heights, modal sizing, spacing/padding, scroll
  ownership, and local UI scale behavior.
- **FR-039**: Long or truncated values MUST remain accessible through ellipsis with
  tooltip, expansion, or another readable detail path; labels and controls MUST not
  overlap or clip at supported sizes.
- **FR-040**: Midnight MUST define semantic PRIMARY, TEXT, TEXT_MUTED, SUCCESS,
  WARNING, DANGER, and INFO states and MUST communicate critical state through more
  than color alone.
- **FR-041**: The UI MUST support readable text scaling, clear selected state,
  accessible tooltips for truncated values, and a high-contrast Midnight presentation
  adjustment when practical; high contrast MUST not become a separate theme.
- **FR-042**: Complex screens MUST use dirty-state or coalesced refresh behavior and
  MUST avoid rebuilding the complete window for every event; virtualization is only
  required where list size justifies it.
- **FR-043**: B11 UI creation, visibility, movement, refresh, and protected control
  changes MUST preserve B08 combat deferral, readiness checks, and post-combat behavior.

### Key Entities

- **Midnight Design Token Set**: Local presentation values for color, typography,
  spacing, sizing, density, surfaces, borders, and semantic states.
- **UI Environment Adapter**: Optional, non-authoritative source of presentation hints
  from an external UI environment; it never supplies Dibs permissions or policy.
- **Dibs UI Component**: A reusable presentation building block with stable sizing,
  state, accessibility, and callback conventions.
- **Developer Sandbox Store**: Versioned local state cloned from production only by
  explicit action and never writable back to production.
- **Sandbox Provider**: The active service boundary that resolves simulated role,
  coordinator, state, and fault scenarios only while a sandbox is active.
- **Sandbox Scenario**: A named bounded state/fault fixture for a player, Officer, GM,
  coordinator, recovery, RCLootCouncil, identity, request, or scale condition.
- **Dashboard Status Summary**: A human-readable projection of authorized operational
  state with technical diagnostics available on expansion.
- **Reconciliation Workflow State**: Search, candidate review, decision, and completion
  state around existing immutable RCLootCouncil evidence and protected confirmation.
- **Local Presentation Profile**: Character-local UI appearance and scale settings,
  separate from guild policy and synchronized data.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All seven B11 batches have independently reviewable scope and can be
  reverted without removing or changing B00-B10 production semantics.
- **SC-002**: In sandbox isolation tests, 100% of balance, policy, ledger, coordinator,
  baseline, recovery, and authority mutations remain confined to the sandbox, including
  after reset, exit, and reload scenarios.
- **SC-003**: No test permits Developer Mode alone, a sandbox role, or a simulated
  coordinator to authorize a production protected action.
- **SC-004**: A player can identify balance, active Pre-Dibs, pending requests, current
  season, and readiness from the first Player view without opening technical details.
- **SC-005**: A verified Officer or GM can identify all required dashboard operational
  summaries and reach Requests, Pre-Dibs, History, Rules, and RCLootCouncil within two
  navigation actions from the dashboard.
- **SC-006**: 100% of tested unsupported, absent, or failing UI environment adapters,
  media lookups, and RCLootCouncil capability states fall back to readable Midnight
  presentation without changing authoritative state.
- **SC-007**: 100% of reconciliation confirmation and rejection tests continue through
  the existing protected service path, with zero writes to RCLootCouncil history and
  zero changes to B09 evidence semantics.
- **SC-008**: At supported minimum, typical, and wide sizes, all B11 screens pass the
  layout corpus with zero overlapping controls, clipped primary actions, unusable
  dropdowns, or competing scroll owners.
- **SC-009**: Critical state remains distinguishable in normal and high-contrast
  presentation using text, shape, label, or selection treatment in addition to color.
- **SC-010**: The automated B11 test suite proves the ten sandbox invariants, player and
  officer permission boundaries, B08 combat safety, B09 reconciliation boundary,
  environment fallback, responsive layout contracts, and coalesced refresh behavior.
- **SC-011**: B11 introduces no required production SavedVariables migration; any
  appearance persistence is local and any sandbox persistence uses a separately
  versioned developer schema; reload always starts in inactive production mode.

## Assumptions

- B00-B10 production contracts and source behavior are the authority; B11 consumes
  existing services and normalized projections rather than duplicating domain rules.
- `RCLootCouncil_Dibs` production SavedVariables remain authoritative and are not
  replaced by an alternate database for UI convenience.
- A separate developer SavedVariable root such as `RCLootCouncilDibsDevDB` is acceptable
  for sandbox state and is never merged with production.
- AceGUI remains the foundation for complex Dibs-owned screens, while AceConfig remains
  suitable for simple persistent settings; existing menu, media, and window libraries
  are reused rather than replaced.
- Optional UI environment adapters are best-effort presentation integrations and are
  never required dependencies.
- The sandbox may show simulated coordinator, recovery, and RC conditions for UI and
  diagnostics, but it cannot create production addon traffic, live awards, or real
  authority.
- Existing B08 combat scheduling and protected-frame ownership remains in force for
  every redesigned window.
- B11 planning and implementation are additive and independently revertible; no B00-B10
  production behavior is reinterpreted as a side effect of a visual redesign.

## Out of Scope

- Changing ledger calculations, transaction identity, seasons, allocations, or award cost.
- Changing coordinator authority, governance, identity, SyncV2 sequencing, recovery,
  baseline selection, or proposal/commit semantics.
- Changing RCLootCouncil award evidence validation, response projection, or history data.
- Writing to RCLootCouncil source, live candidates, votes, responses, or loot sessions.
- Granting production GM, Officer, Master Looter, or coordinator authority through UI or
  Developer Mode.
- Adding a second visual theme for an external UI addon.
- Replacing B08 combat-safe scheduling or taking ownership of RC-protected controls.
- Implementing planning artifacts beyond this specification in the specify phase.
