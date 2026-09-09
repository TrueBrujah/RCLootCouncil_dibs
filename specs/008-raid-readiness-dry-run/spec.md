# Feature Specification: Raid Readiness and Dry-Run Center

**Feature Branch**: `008-raid-readiness-dry-run`

**Created**: 2026-09-09

**Status**: Draft

**Input**: User description: "Add a Raid Readiness and Dry-Run Center that checks the Dibs and RCLootCouncil setup before a raid, explains Ready/Degraded/Blocked states, and lets guild administrators test a Dibs award safely without consuming Dibs or sending fake live events."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Check raid readiness before pulling (Priority: P1)

As a GM or Officer, I want one readiness check before a raid, so that the guild can find integration, permissions, season, response, channel, and synchronization problems before loot is awarded.

**Why this priority**: A preflight check prevents a raid from depending on a Dibs button or balance flow that is not actually operational.

**Independent Test**: Prepare one valid and one intentionally broken test environment, run the readiness check from the Officer interface, and verify that every failed condition has a clear reason and recommended action.

**Acceptance Scenarios**:

1. **Given** the guild is in a valid RCLootCouncil raid with an active Dibs season, a verified local Master Looter, a configured Dibs response, and working synchronization, **when** a GM or Officer starts a readiness check, **then** the result is `Ready` and lists the checks that passed.
2. **Given** RCLootCouncil is installed but a capability, response projection, season, identity, or synchronization condition is incomplete, **when** the check runs, **then** the result is `Degraded` or `Blocked` with a specific reason code and no ledger mutation.
3. **Given** the user is not grouped or the guild has no raid channel, **when** the check runs, **then** the result distinguishes an expected unavailable raid context from a configuration failure and keeps standalone Dibs administration usable.
4. **Given** a normal player views readiness, **when** the status is displayed, **then** they see a safe summary without private officer diagnostics, live candidates, votes, or other players' balances.
5. **Given** an Officer changes a setting after a check, **when** readiness is viewed again, **then** the affected check is visibly stale or is refreshed before the status is presented as current.

---

### User Story 2 - Test the finalized Dibs path without spending Dibs (Priority: P1)

As a GM or Officer, I want to simulate a finalized Dibs award locally, so that we can validate the response, identity, item, eligibility, authorization, and idempotency path before using it in a live raid.

**Why this priority**: The guild needs a safe way to test the exact integration boundary without creating a fake loot award, spending a real Dib, or sending confusing raid messages.

**Independent Test**: Enter a test item, winner, response label, status, and session context, run the dry-run twice, and verify the outcome and reasons while the ledger, RCLootCouncil state, chat, and synchronization remain unchanged.

**Acceptance Scenarios**:

1. **Given** a dry-run input contains a valid item, winner, configured Dibs response, final status, and stable test identity, **when** an authorized administrator runs it, **then** the result is `Would award and consume one Dib` or the equivalent validated outcome, clearly marked as a simulation.
2. **Given** a dry-run input is missing an item, winner, final status, stable identity, or configured response, **when** it runs, **then** the result explains the rejection or ignore reason and does not create a transaction.
3. **Given** a dry-run uses a test or pending status, **when** it runs, **then** production Dibs remain unchanged and the report identifies the test-status safeguard.
4. **Given** the same dry-run is replayed, **when** it runs again, **then** it produces the same deterministic result without creating an idempotency record or changing any balance.
5. **Given** RCLootCouncil is absent or degraded, **when** a local dry-run is requested, **then** the addon may evaluate standalone validation but clearly marks live integration checks as unavailable and never fabricates a RCLootCouncil event.
6. **Given** the user is not a verified guild GM or Officer, **when** they attempt to run a dry-run, **then** the action is unavailable or rejected without changing policy, ledger, or live loot state.

---

### User Story 3 - Explain and act on readiness failures (Priority: P1)

As a raid administrator, I want each readiness failure to tell me what it means and what I can do, so that a degraded status can be corrected quickly without guessing.

**Why this priority**: A red status without a useful explanation does not prevent raid mistakes. Administrators need clear boundaries between a missing raid context, a configuration problem, and an unsafe integration capability.

**Independent Test**: Trigger each supported failure class, open its detail, and verify that the explanation identifies impact, safe remediation, required authority, and whether Dibs consumption is currently allowed.

**Acceptance Scenarios**:

1. **Given** the local Master Looter cannot be verified, **when** the detail is opened, **then** it states that automatic RCLootCouncil Dibs consumption is blocked while GM/Officer administration remains available.
2. **Given** the configured Dibs response is missing or not visible in the active RCLootCouncil profile, **when** the detail is opened, **then** it identifies the response configuration problem without overwriting another response.
3. **Given** the synchronization channel or relay is unavailable, **when** the detail is opened, **then** it explains whether local testing is still possible and does not promise cross-raid convergence.
4. **Given** the active season or policy is missing, archived, or inconsistent, **when** the detail is opened, **then** it names the affected policy scope and identifies the GM/Officer action required.
5. **Given** a check is expected to be unavailable because the user is outside a group, **when** the detail is opened, **then** it does not incorrectly report a security failure or suggest changing guild permissions.

---

### User Story 4 - Share a safe readiness report (Priority: P2)

As a GM or Officer, I want a concise report that I can copy to guild chat or a support ticket, so that testers can compare environments without sharing private loot data.

**Why this priority**: A standardized report makes guild testing and troubleshooting faster while respecting the privacy boundaries of the Dibs and RCLootCouncil systems.

**Independent Test**: Generate a report in a valid, degraded, and absent-integration environment, copy it, and verify that it includes useful statuses and versions without live candidates, votes, private notes, or complete balances.

**Acceptance Scenarios**:

1. **Given** a readiness check or dry-run has completed, **when** a GM or Officer selects **Copy report**, **then** the report includes timestamp, addon and integration versions, mode, check statuses, reason codes, dry-run outcome, and test count.
2. **Given** the report is copied for a normal player or public channel, **when** the safe report is generated, **then** private player identities, candidate lists, votes, item payloads, administrator notes, and complete ledger data are omitted.
3. **Given** the administrator requests a detailed Officer report, **when** it is generated, **then** it includes the evidence needed to reproduce the failure while still excluding unrelated live raid state.
4. **Given** diagnostics are configured at level 0, **when** a normal readiness report is requested, **then** essential user-facing status remains visible while verbose implementation traces stay hidden.

---

### User Story 5 - Gate unsafe live behavior (Priority: P2)

As a guild administrator, I want readiness to prevent unsafe automatic Dibs consumption while still allowing ordinary Dibs administration, so that a broken RCLootCouncil integration fails closed.

**Why this priority**: The addon must not debit a player when the award identity, Master Looter, final status, response, or season cannot be trusted.

**Independent Test**: Move the environment through Ready, Degraded, and Blocked states during a test raid, attempt a qualifying and non-qualifying award in each state, and verify the action gates and audit results.

**Acceptance Scenarios**:

1. **Given** the status is `Ready`, **when** a qualifying finalized Dibs award is received, **then** the existing protected award path may consume one Dib exactly once.
2. **Given** the status is `Degraded` because optional diagnostics or synchronization are unavailable but local award provenance remains trustworthy, **when** a qualifying award is received, **then** the report clearly states whether consumption is still allowed under the active policy.
3. **Given** the status is `Blocked` because Master Looter, final status, item, winner, response, or award identity cannot be verified, **when** an award is received, **then** no production Dib is consumed and the reason is recorded.
4. **Given** the readiness panel is open during combat, **when** a check needs protected UI work, **then** the UI portion is deferred safely and no ledger mutation is performed implicitly.
5. **Given** a readiness check is repeated after a repair, **when** all required checks pass, **then** the status returns to `Ready` without resetting seasons, balances, history, or profiles.

## Edge Cases

- RCLootCouncil is not installed, is disabled, or changes its capability surface after readiness was marked `Ready`; the next check reports the new state and never trusts a stale capability indefinitely.
- The user is outside a group, in a non-raid group, or is not the current RCLootCouncil Master Looter; the result distinguishes expected context from an actionable integration block.
- The active response label is localized, renamed, duplicated, or different from `Dibs`; readiness uses the configured alias and shows the original observed label without fuzzy acceptance.
- The Dibs button is projected into a profile with no free response slot, a malformed button count, or a later profile refresh; the check reports projection state without overwriting existing responses.
- The current season is missing, archived, has no rank allocation, or differs between synchronized officers; readiness reports the policy conflict and does not select a season silently.
- A guild channel exists but the relay is unavailable, the roster is stale, or the user has not joined the channel; local dry-run remains possible only if its required inputs are local and safe.
- The dry-run item is unknown, the winner is ambiguous, the status is not final, or the test identity is reused; the simulation returns a reason and never writes an accounting record.
- The dry-run uses a custom alias that is not saved; the result is marked temporary and cannot become a live policy change.
- A dry-run is attempted by a council member or Master Looter who is not a GM/Officer; it cannot be used to grant authority or alter settings.
- The report contains an error message with a player name, item link, or channel identifier; the safe report redacts it while the Officer report applies the existing privacy scope.
- The addon is reloaded between readiness and award; the next award revalidates the current capability and does not rely only on the old panel status.
- Multiple officers run checks concurrently or one officer repairs settings while another reviews a report; each report includes an observed timestamp and configuration fingerprint so stale results are visible.
- A large number of checks or dry-runs is attempted; diagnostic output is bounded and cannot create a memory-retaining history of every simulation.
- A future integration exposes new optional probes; older builds ignore unknown probes without changing award authority or Dibs balances.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a Raid Readiness action in the Officer interface and a documented slash-command entry point for authorized administrators.
- **FR-002**: The system MUST evaluate readiness separately for standalone Dibs administration and optional RCLootCouncil live-award integration, so an integration failure cannot remove valid GM/Officer administration.
- **FR-003**: A readiness result MUST expose one of `Ready`, `Degraded`, `Blocked`, or `Unavailable` and MUST include a timestamp, observed mode, configuration fingerprint or freshness marker, and reason codes for every failed or skipped check.
- **FR-004**: Readiness MUST check, where applicable, active season and policy, guild authority, installation mode, RCLootCouncil availability, current Master Looter identity, Dibs response projection and alias, award identity capability, synchronization context, and required local framework services.
- **FR-005**: Readiness MUST distinguish an expected missing context such as not being grouped or having no raid channel from a security, configuration, or integration failure.
- **FR-006**: The system MUST refresh or invalidate stale readiness after a reload, profile change, season or policy change, RCLootCouncil lifecycle change, roster change, or elapsed freshness interval.
- **FR-007**: The system MUST provide a local dry-run action that accepts a bounded test item, winner, response, finalization status, session identity, and optional difficulty or mode context.
- **FR-008**: Dry-run input MUST be marked as test context and MUST be evaluated through the same validation decisions used for a live award where possible, while never consuming production Dibs or appending a production ledger transaction.
- **FR-009**: Dry-run MUST NOT invoke RCLootCouncil award controls, inject fake global game events, emit fake addon or raid traffic, modify RCLootCouncil SavedVariables, or change live candidates, votes, sessions, or history.
- **FR-010**: Dry-run results MUST report a deterministic outcome such as would allow, would ignore, would reject, or would require review, together with the exact reason codes and whether a real award would be allowed to consume a Dib.
- **FR-011**: Replaying the same dry-run MUST produce the same result without creating an idempotency record, balance mutation, or persistent simulation history beyond bounded diagnostic metadata.
- **FR-012**: A readiness failure MUST gate automatic production Dibs consumption whenever Master Looter, item, winner, explicit configured response, final status, season, eligibility, or stable award identity is not verifiable.
- **FR-013**: Readiness MUST NOT gate or expand GM/Officer administrative authority based on raid role, council membership, or Master Looter status.
- **FR-014**: The system MUST show the impact and recommended remediation for every blocked or degraded check, including the required authority and whether local dry-run remains available.
- **FR-015**: The system MUST provide a safe report that includes addon and integration versions, mode, readiness statuses, reason codes, dry-run outcome, and test evidence without exposing live candidates, votes, complete balances, private notes, or unrelated player identities.
- **FR-016**: An Officer report MAY include additional evidence needed for troubleshooting, but it MUST remain guild-scoped and MUST exclude unrelated live raid state and cross-raid private data.
- **FR-017**: Report copy and diagnostic output MUST respect the configured diagnostic levels; essential readiness errors remain visible while verbose implementation details require the applicable diagnostic scope.
- **FR-018**: Only verified guild GMs or Officers MAY start full readiness checks, change readiness-related policy, run dry-runs, or copy detailed reports. Normal players MAY view a safe readiness summary.
- **FR-019**: Readiness and dry-run operations MUST be read-only with respect to Dibs balances, authoritative ledger transactions, Pre-Dibs, seasons, rank allocations, finalized award evidence, RCLootCouncil history, and synchronization state.
- **FR-020**: Every readiness policy change, dry-run request, dry-run result, report generation, and blocked live-award decision MUST be attributable to an actor or system source and retained only within the bounded audit or diagnostic policy.
- **FR-021**: The system MUST remain usable when RCLootCouncil is absent or degraded and MUST report integration unavailability without fabricating capabilities or expanding permissions.
- **FR-022**: Readiness and dry-run controls MUST be safe during combat; any protected UI work MUST be deferred without performing an implicit ledger or loot action.
- **FR-023**: All statuses, check names, reason codes, remediation text, dry-run outcomes, report fields, and help text MUST be localized with English fallback and MUST explain whether the control can change policy or consume a Dib.
- **FR-024**: Any shipped behavior, diagnostic scope, SavedVariables field, protocol field, or UI control added by this feature MUST include a dated changelog note and an incremented addon version according to the constitution.

### Key Entities

- **Readiness Check**: A timestamped evaluation of the current standalone and integration conditions, with mode, freshness, statuses, reason codes, and observed capability details.
- **Capability Probe**: A bounded check for one required or optional condition such as Master Looter identity, response projection, season, sync, or local service availability.
- **Dry-Run Case**: A local test input representing an item, winner, response, finalization status, session identity, and optional context, explicitly marked as non-production.
- **Dry-Run Result**: A deterministic simulated outcome, reason codes, validation details, and a clear statement that no production state changed.
- **Readiness Report**: A safe or Officer-scoped summary that can be copied for guild testing and troubleshooting.
- **Safety Gate**: The current decision that determines whether a live qualifying award may proceed to Dibs accounting, without granting any Dibs administration authority.
- **Readiness Audit Event**: A bounded record of a check, simulation, report, policy change, or blocked award decision with actor, time, scope, and outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In automated and Retail acceptance tests, 100% of readiness checks and dry-runs leave Dibs balances, ledger transactions, Pre-Dibs, seasons, profiles, RCLootCouncil history, candidates, votes, sessions, chat traffic, and synchronization state unchanged.
- **SC-002**: In a normal test environment, a GM or Officer receives a complete readiness result with reason codes in under five seconds.
- **SC-003**: Across valid, degraded, blocked, absent, not-grouped, and no-channel scenarios, 100% of results use the correct state class and explain whether the issue affects live Dibs consumption, local administration, or only optional diagnostics.
- **SC-004**: Across a dry-run corpus containing valid, custom-label, localized, test, pending, ambiguous, invalid, and duplicate inputs, 100% of outcomes are deterministic and no production transaction is created.
- **SC-005**: In replay tests, 100% of identical dry-runs return the same result and create zero persistent accounting effects.
- **SC-006**: In authority tests, 100% of detailed readiness, dry-run, policy, and full-report operations succeed only for verified guild GMs or Officers.
- **SC-007**: In privacy tests, 100% of safe reports omit live candidates, votes, complete balances, administrator notes, and unrelated identities while retaining actionable diagnostics.
- **SC-008**: In recovery tests, readiness re-evaluates after reload, profile change, roster change, and RCLootCouncil lifecycle change, with no stale `Ready` state authorizing an unverifiable award.
- **SC-009**: At least 95% of guild testers can identify the cause and recommended action for a simulated readiness failure without consulting source code or private logs.
- **SC-010**: In combat and unavailable-integration tests, the feature causes zero protected-action errors, fake global events, unauthorized permission changes, or production Dibs mutations.

## Assumptions

- The readiness center is a safety and explanation layer; it does not replace RCLootCouncil's loot-session authority or the Dibs protected accounting path.
- The default readiness command and Officer button are read-only. A live award is revalidated at the moment of receipt even if the panel recently reported `Ready`.
- Standalone readiness can confirm Dibs administration, seasons, policy, ledger availability, and local UI state without requiring a group or RCLootCouncil.
- Optional integration readiness requires the current RCLootCouncil capability surface and a verified local Master Looter. Raid Assistant, council membership, or guild rank alone cannot satisfy this check.
- The dry-run uses a local synthetic case and never emits a fake event, message, award, or synchronization packet. It may show the names `RCMLAwardSuccess` and `FinalizeAward` as provenance references, but neither is directly invoked by the tester.
- The configured response alias policy is the authority for custom RCLootCouncil labels. Readiness does not guess that a label means Dibs.
- A safe report is the default for copying to chat or public support. Detailed reports remain restricted to GM/Officer views and are not encrypted by the addon.
- Readiness audit retention is bounded and must not become a second full loot-history database.
- The feature uses existing Dibs SavedVariables, diagnostics, profiles, and guild isolation rules; a separate backup/export migration is handled by Feature 007.
- Automatic external telemetry, cloud monitoring, cross-raid live candidate sharing, and automated repair of settings are outside this feature.
- The feature must obey the current constitution's combat safety, append-only ledger, authority, RCLootCouncil ownership, privacy, diagnostic, data-isolation, change-note, and versioning principles.
