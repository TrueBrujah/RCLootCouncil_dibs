# Feature Specification: Turnkey Guided Setup

**Feature Branch**: `021-turnkey-guided-setup`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Simplifier le Guided Setup pour qu'il soit cle en main, avec beaucoup de documentation dans le processus. Expliquer ce que chaque action fait et pourquoi elle est utile. Signaler clairement en rouge les actions obligatoires qui n'ont pas ete faites et pointer directement vers leur correction."

## User Scenarios & Testing *(mandatory)*

### Approved navigation revision — 2026-11-15

The user requires setup to control feature visibility, rather than leaving an
unconfigured application full of disabled or misleading pages.

- **FR-025**: A genuinely fresh guild installation MUST expose only Guided Setup
  in Officer navigation. Old tab selections and direct route requests MUST resolve
  to Guided Setup until the installation foundation is configured.
- **FR-026**: Navigation MUST derive completion from existing authoritative
  installation, published season/rank configuration, ledger and feature state.
  A locally selected wizard stage, a bootstrap Season 1, or a clicked button MUST
  NOT count as completed guild setup. No new persisted completion flag is required.
- **FR-027**: After foundation setup, configuration routes MUST remain available
  so the administrator can configure the next part. Operational sections become
  visible only when their own prerequisites are satisfied. Missing optional RC,
  disabled optional modules, or temporary coordinator unavailability MUST NOT
  become a global setup requirement.
- **FR-028**: An existing installation MUST retain safe access to preserved history
  and migration/recovery workflows. Hiding a page MUST NOT change permissions,
  erase data, perform setup, or bypass a domain mutation gate. A normal member
  sees a public setup-waiting state, never administrative details or actions.
- **FR-029**: Visibility MUST be refreshed after configuration/context changes;
  empty navigation groups and hidden-page renderers MUST not remain accessible
  through stale selection, aliases or direct routes. Setup itself remains reachable.

### User Story 1 - Complete a Turnkey Setup (Priority: P1)

As a Guild Master or authorized Officer, I want a short guided setup that applies a coherent starting configuration, so that I can prepare DIBS for a raid without understanding every internal catalog, revision, or synchronization state.

**Why this priority**: The current fourteen-step workflow exposes technical checks as if each were a separate user decision. This makes a valid setup feel blocked and difficult even when most checks are already complete or informational.

**Independent Test**: Starting from an unconfigured guild, an authorized administrator selects a recommended setup profile, reviews the announced changes, runs the setup, and reaches a final readiness summary without navigating fourteen separate pages.

**Acceptance Scenarios**:

1. **Given** a new guild installation and an authorized administrator, **When** the administrator opens Guided Setup, **Then** the workflow presents no more than three primary stages: choose, configure, and verify.
2. **Given** the administrator selects a recommended profile, **When** the configuration is confirmed, **Then** all safe routine settings covered by that profile are configured together and the workflow explains each resulting change.
3. **Given** an action requires separate Guild Master confirmation or another protected decision, **When** an Officer runs setup, **Then** the workflow completes all Officer-authorized preparation and identifies the remaining GM action without pretending it succeeded.
4. **Given** configuration already exists, **When** Guided Setup is opened, **Then** existing valid settings are preserved and the workflow changes from first-time setup to focused repair or review.

---

### User Story 2 - Understand Every Setup Decision (Priority: P1)

As an administrator unfamiliar with DIBS internals, I want contextual documentation throughout setup, so that I understand what will change, why the setting is recommended, and how it affects players and raids.

**Why this priority**: A turnkey action is trustworthy only when users can understand its effects before confirming it.

**Independent Test**: A tester unfamiliar with the addon can describe the purpose and player impact of each setup profile and each unresolved result using only the information shown in the workflow.

**Acceptance Scenarios**:

1. **Given** a setup profile is displayed, **When** the administrator reviews it, **Then** the workflow explains its intended guild type, enabled behavior, player-visible effects, and settings that remain unchanged.
2. **Given** setup is ready to apply, **When** the administrator reviews the confirmation, **Then** the workflow lists what will be created, published, preserved, and deferred before any change occurs.
3. **Given** a completed or skipped setup item, **When** the administrator views its details, **Then** the workflow explains why it is complete or why no action is required.
4. **Given** detailed documentation is available, **When** the administrator does not need it, **Then** the primary actions and status remain easy to scan without a wall of text.

---

### User Story 3 - Find and Correct Missing Work (Priority: P1)

As an administrator, I want missing required work highlighted and linked to its correction, so that I know exactly why setup is not ready and what to do next.

**Why this priority**: The current review uses warnings for many different conditions and makes the user search through the addon to discover the appropriate correction screen.

**Independent Test**: Introduce one blocking configuration issue and one optional warning. Verify that only the blocker is red, that it explains cause and impact, and that its correction action opens the exact relevant workflow.

**Acceptance Scenarios**:

1. **Given** a required setup result is missing or invalid, **When** the verification stage is shown, **Then** that result is red and includes its plain-language cause, raid impact, and a direct correction action.
2. **Given** a condition is recommended but does not prevent safe operation, **When** verification is shown, **Then** it is visually distinct as a non-blocking warning and is not presented as a red failure.
3. **Given** a condition is ready or optional, **When** verification is shown, **Then** it is identified as successful or optional without competing visually with unresolved blockers.
4. **Given** multiple blockers exist, **When** the administrator selects the primary correction action, **Then** the workflow directs them to the highest-priority unresolved blocker and preserves their setup progress.
5. **Given** the administrator corrects an issue and returns, **When** verification refreshes, **Then** the result reflects the authoritative current state rather than stale setup progress.

---

### User Story 4 - Retain Advanced Control (Priority: P2)

As an experienced administrator, I want access to advanced configuration, so that simplification does not remove valid guild-specific choices.

**Why this priority**: The guided workflow should reduce cognitive load without replacing the existing specialized configuration pages.

**Independent Test**: From Guided Setup, open advanced configuration for a profile setting, change it through the existing authoritative page, and return to see the updated verification result.

**Acceptance Scenarios**:

1. **Given** an administrator needs guild-specific settings, **When** they choose the custom path or an advanced-settings action, **Then** the existing specialized configuration pages remain available.
2. **Given** a setting is changed on an advanced page, **When** Guided Setup is revisited, **Then** it reports the actual current setting and does not overwrite it automatically.

### Edge Cases

- An Officer can prepare routine settings but cannot perform a separately GM-restricted adoption; setup must clearly separate completed preparation from pending approval.
- Existing historical data requires reconciliation; the workflow must not conceal, discard, or automatically accept it.
- The guild roster, synchronization transport, or RCLootCouncil integration is temporarily unavailable; only genuinely required conditions may block setup.
- No raid is currently active; live-session readiness checks must be described as expected and non-blocking outside a raid.
- A profile action partially succeeds; successful authoritative changes remain reported, failed actions are explicit, and the workflow must not claim overall success.
- The administrator enters combat while using setup; protected or unsafe work must be deferred without losing the selected profile or review position.
- Local settings differ from the guild-authoritative state; the workflow must identify which source controls the outcome and must not silently replace guild policy.
- The selected profile is already fully applied; rerunning setup must be idempotent and must not create duplicate records or revisions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Guided Setup MUST present no more than three primary stages: profile selection, reviewed configuration, and final verification.
- **FR-002**: Guided Setup MUST retain all existing authoritative readiness checks while grouping them into understandable outcomes rather than separate mandatory navigation steps.
- **FR-003**: The profile-selection stage MUST offer recommended profiles for progression-focused and broad standard-loot guilds, plus a custom path that preserves advanced control.
- **FR-004**: Each profile MUST explain its intended use, the behavior it enables, its player and raid impact, and which settings it does not change.
- **FR-005**: Before applying a profile, Guided Setup MUST show a review of settings that will be created, changed, published, preserved, or deferred.
- **FR-006**: Profile application MUST preserve existing valid configuration unless the administrator explicitly confirms a listed change.
- **FR-007**: Profile application MUST be idempotent and MUST NOT create duplicate records, duplicate allocations, or unnecessary revisions when the selected state is already active.
- **FR-008**: Guided Setup MUST apply only actions authorized for the current administrator and MUST identify separately restricted actions as pending rather than successful.
- **FR-009**: Guided Setup MUST NOT bypass Guild Master approvals, Officer authority checks, synchronization verification, historical-data reconciliation, combat restrictions, or protected-action safeguards.
- **FR-010**: The verification stage MUST categorize every relevant result as blocking, warning, ready, or optional.
- **FR-011**: Blocking results MUST be visually red and MUST state the missing or invalid condition, why it matters, its operational impact, and the next corrective action.
- **FR-012**: Each blocking result MUST provide a direct correction action when the addon has an applicable configuration destination.
- **FR-013**: Non-blocking warnings MUST use a distinct non-red treatment and MUST explicitly state that raid preparation may continue when that is true.
- **FR-014**: Ready and optional results MUST remain available for reassurance and auditability but MUST be visually subordinate to unresolved blockers.
- **FR-015**: The primary verification action MUST direct the administrator to the highest-priority unresolved blocker.
- **FR-016**: Verification MUST refresh from authoritative current state after every correction and MUST NOT depend on a stale checklist maintained by the interface.
- **FR-017**: Every primary stage MUST include concise always-visible guidance and optional expanded documentation for users who need more detail.
- **FR-018**: Documentation MUST use guild and raid language rather than internal protocol terminology wherever a plain-language explanation is possible.
- **FR-019**: When internal terminology must be shown for diagnosis, it MUST be accompanied by a plain-language explanation and a recommended next action.
- **FR-020**: Partial application failures MUST identify each failed action and MUST NOT return a success-shaped overall result.
- **FR-021**: Existing specialized configuration pages MUST remain available and authoritative for advanced customization.
- **FR-022**: User-facing setup guidance and statuses MUST be localizable, with an English fallback.
- **FR-023**: Guided Setup MUST preserve current setup progress when the administrator follows a correction link and returns.
- **FR-024**: No active or historical ledger transactions may be rewritten, removed, or reset by turnkey setup.

### Approved inline season preparation — 2026-11-15

- **FR-030**: Configure MUST offer an optional raid-season draft form for progression and standard profiles when no seasonal roster exists, with explicit name, required start/registration dates, one required Normal/Heroic/Mythic checkbox group defining both signup categories and raid difficulties, optional raid nights with an optional expected difficulty, and rules text. Selecting a profile alone MUST NOT create a season. Published legacy categories and registrations remain unchanged (029 FR-056–057, approved 2026-11-16).
- **FR-031**: Confirming the profile with this option MUST delegate creation to SeasonalRoster only after foundation readiness, using a stable operation ID. Validate the requested draft before applying any setup action; invalid input MUST leave setup unchanged. Reapplication or concurrently discovered existing seasons MUST NOT create duplicates or edit existing seasons.
- **FR-032**: The preview MUST distinguish technical foundation from raid-season preparation. Disabled Seasonal Roster stays disabled with an explicit deferred result. Custom remains manual. Draft preparation MUST NOT publish registration, activate a season, allocate balances or infer guild promotion criteria or raid nights.

### Key Entities

### Approved resumable guided completion — 2026-11-15

- **FR-033**: The default completion screen MUST show one ordered next action in plain language with completed/pending progress. Full technical verification remains available through an explicit details control; unchanged readiness and permission gates stay authoritative. A missing raid-season draft/publication must precede later seasonal configuration.
- **FR-034**: Setup MUST retain selected profile, stage, pending season-form fields and correction context across window closure and reload in existing character-local settings, isolated by guild. Store only bounded allowlisted data, never widgets, authoritative completion flags or ledger data. Recompute the next action from current state on resume.
- **FR-035**: Setup action feedback MUST appear inside the addon with green success, yellow warning/pending and red failure plus text labels. Successful actions MUST NOT contain failure reason codes. Guided profile application must suppress redundant preset chat notices while preserving direct options behavior.
- **FR-036**: Already-open PlayerUI MUST update its setup/navigation presentation after local setup and synchronized prerequisite changes without closing/reopening; preserve current inputs and selections when visible sections are unchanged, and avoid polling expensive full readiness reports.

### Approved season presentation redesign — 2026-11-16

- **FR-037**: Configure MUST present a compact profile summary and clear primary
  action, with secondary technical details available explicitly. The optional season
  form MUST share the organization used in direct season creation and draft editing:
  essential fields first, summarized expandable optional sections, no loss of input
  when sections collapse, and validation revealing the affected section. Internal
  result codes MUST use understandable localized labels in the presentation without
  changing serialized identifiers, profile effects or authoritative service gates.

### Entities

- **Setup Profile**: A named, documented collection of recommended starting choices, including its intended guild type, effects, exclusions, and confirmation summary.
- **Setup Stage**: One of the three user-facing phases—choose, configure, or verify—with concise guidance and optional expanded documentation.
- **Setup Result**: An authoritative current-state finding categorized as blocking, warning, ready, or optional, with cause, impact, explanation, and correction destination where applicable.
- **Configuration Change Summary**: The pre-application description of settings that will be created, changed, published, preserved, or deferred.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An authorized administrator can complete a normal first-time setup in under two minutes using no more than three primary stages.
- **SC-002**: A first-time user can identify what a selected profile changes and what remains unchanged before confirming it, without consulting external documentation.
- **SC-003**: Every simulated blocking condition is displayed in red with a cause, impact, and actionable correction destination.
- **SC-004**: No simulated non-blocking warning is displayed as a red failure.
- **SC-005**: At least 90% of representative setup issues can be reached from verification with one correction action.
- **SC-006**: Reapplying an already-active profile produces no duplicate accounting records and no unnecessary configuration revisions.
- **SC-007**: Existing guilds can open the simplified workflow without losing or silently replacing valid configuration.
- **SC-008**: A user unfamiliar with DIBS can correctly explain the purpose of every primary stage and the next action for every blocker after one walkthrough.

## Assumptions

- The existing readiness, installation, policy, synchronization, season, rank, Pre-Dibs, Loot Rules, and RCLootCouncil systems remain authoritative.
- "Red" is reserved for conditions that genuinely prevent safe setup or raid readiness; recommended and optional work uses lower-severity presentation.
- Recommended profiles use already approved project defaults and existing preset behavior rather than inventing new accounting policy.
- Detailed guidance is provided through progressive disclosure so the workflow can be both well documented and easy to scan.
- The abandoned distributed reinstall/reset concept is outside this feature's scope.
- Existing ledgers, transactions, seasons, and historical evidence are preserved.
