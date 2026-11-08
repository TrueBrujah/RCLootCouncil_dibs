---
description: "Implementation tasks for the unified seasonal raid lifecycle"
---

# Tasks: Roster saisonnier et inscriptions aux raids

**Inputs**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`.

**Scope**: Plan for future implementation. All tasks below are unchecked; the existing dirty worktree is not evidence that these tasks are complete. Preserve local changes and do not edit production files until this plan is accepted.

## Phase 1: Setup

**Purpose**: Establish test fixtures and localized UI contract.

- [ ] T001 Add reusable canonical season, enrollment, rank and ledger fixtures to `tests/helpers/seasonal_roster_fixtures.lua`.
- [ ] T002 [P] Add English and French labels for draft/review/ready/active lifecycle, requested path versus awarded status, and activation blockers to `src/locales/enUS.lua` and `src/locales/frFR.lua`.
- [ ] T003 Document the current load order and owners of season, roster, identity, rank allocation, ledger and sync records in `specs/029-seasonal-raid-roster/research.md`.

## Phase 2: Foundational

**Purpose**: Define one stable season identity, migration compatibility, mutation boundary and activation model before story implementation.

- [ ] T004 Add additive schema versioning and legacy season-ID aliases without removing existing SavedVariables in `src/Core.lua` and `tests/integration/seasonal_roster_migration_spec.lua`.
- [ ] T005 Add shared season transition validation, expected-revision checks, stable operation IDs and audit helpers in `src/modules/SeasonalRoster.lua` and `tests/unit/seasonal_roster_lifecycle_spec.lua`.
- [ ] T006 Add verified guild GM/Officer permission actions for season draft, approval, rule publication, allocation, reconciliation and activation in `src/modules/Permissions.lua` and `tests/unit/permissions_spec.lua`.
- [ ] T007 Add module-disabled fail-closed behavior for local and received mutations in `src/modules/OperationalPolicy.lua`, `src/modules/FeatureRegistry.lua`, `src/modules/SeasonalRoster.lua`, and `tests/integration/seasonal_roster_feature_gate_spec.lua`.
- [ ] T008 Specify and test the activation manifest dependency check and commit point in `src/modules/SeasonalRoster.lua` and `tests/unit/season_activation_manifest_spec.lua`.
- [ ] T009 Update the service and sync contracts with exact current schema, authority and conflict behavior in `specs/029-seasonal-raid-roster/contracts/roster-service.md` and `specs/029-seasonal-raid-roster/contracts/roster-sync.md`.

**Checkpoint**: Existing records are preserved; the season identity, authority checks, revision conflicts and manifest commit point have focused tests before UI or sync is changed.

## Phase 3: User Story 1 — Player enrollment (P1)

**Independent test**: In an open synthetic season, a player creates/edits/withdraws only their own registration; closed, stale, duplicate, disabled and other-owner writes fail without ledger mutation.

- [ ] T010 [P] [US1] Add service tests for authenticated owner binding, off-guild characters, duplicate replay, closed window and no ledger side effects in `tests/unit/seasonal_roster_enrollment_spec.lua`.
- [ ] T011 [P] [US1] Add PlayerUI signup tests for create/edit/withdraw and validation states in `tests/integration/seasonal_roster_signup_ui_spec.lua`.
- [ ] T012 [US1] Implement revisioned own-enrollment create/edit/withdraw and immutable audit history in `src/modules/SeasonalRoster.lua`.
- [ ] T013 [US1] Add PlayerUI enrollment form bound to the authenticated character and selected canonical season in `src/ui/PlayerUI.lua`.
- [ ] T014 [US1] Ensure registration changes do not initialize or adjust Dibs and add regression assertions in `src/modules/SeasonalRoster.lua` and `tests/integration/seasonal_roster_signup_ui_spec.lua`.

## Phase 4: User Story 2 — Read-only roster and statistics (P1)

**Independent test**: A normal member sees a paginated, privacy-safe roster; filters and totals agree and linked alts do not inflate the person count.

- [ ] T015 [P] [US2] Test public-field allowlist, pagination, filters, off-guild entries, withdrawals and 1,000-row aggregate correctness in `tests/unit/seasonal_roster_projection_spec.lua`.
- [ ] T016 [P] [US2] Test PlayerUI read-only access and matching list/statistics filters in `tests/integration/seasonal_roster_public_ui_spec.lua`.
- [ ] T017 [US2] Implement bounded deterministic roster projection and cache invalidation keyed by season/revision/filter in `src/modules/SeasonalRoster.lua`.
- [ ] T018 [US2] Implement composition statistics from the same eligible Main/person projection in `src/modules/SeasonalRoster.lua`.
- [ ] T019 [US2] Add the read-only roster page, empty/stale states and bounded pagination in `src/ui/PlayerUI.lua`.

## Phase 5: User Story 3 — Prepare and manage a season (P1)

**Independent test**: A GM/Officer creates and edits a draft with dates, rules, statuses, Core criteria and rank allocations; no change occurs to the active ledger or previous season.

- [ ] T020 [P] [US3] Test legal lifecycle transitions, date validation, revision conflicts, draft isolation and copy-settings-only behavior in `tests/unit/seasonal_roster_lifecycle_spec.lua`.
- [ ] T021 [P] [US3] Test officer create/edit/review flows, actor audit and refusal for non-officer/stale roster in `tests/integration/seasonal_roster_officer_ui_spec.lua`.
- [ ] T022 [US3] Implement draft creation/editing, registration open/close and explicit completion/archive transitions in `src/modules/SeasonalRoster.lua`.
- [ ] T023 [US3] Implement season-scoped versioned rules, participation definitions, promotion policy and rank-allocation configuration, including copying settings only from a prior season in `src/modules/SeasonalRoster.lua`.
- [ ] T024 [US3] Implement officer enrollment review, correction, withdrawal/removal and reasoned audit events in `src/modules/SeasonalRoster.lua`.
- [ ] T025 [US3] Add the officer season editor, calendar/time controls, registration management and version history in `src/ui/OfficerUI.lua`.
- [ ] T026 [US3] Add tests for seven-day post-completion archive behavior and registration close not archiving in `tests/unit/seasonal_roster_lifecycle_spec.lua`.

## Phase 6: User Story 4 — Main/Alt declaration and person balance (P2)

**Independent test**: A reviewed Main/Alt relationship follows the same person identity; balance preview shows every legacy balance and retains the selected Main balance without summing or rewriting old transactions.

- [ ] T027 [P] [US4] Add identity and 14-day Main-change probation regression cases in `tests/unit/character_eligibility_spec.lua`.
- [ ] T028 [P] [US4] Add ledger tests for selected-Main-balance retention, audited correction and replay safety in `tests/unit/ledger_operation_spec.lua`.
- [ ] T029 [US4] Integrate seasonal Main snapshot and reviewed Main-change request with CharacterEligibility in `src/modules/SeasonalRoster.lua` and `src/modules/CharacterEligibility.lua`.
- [ ] T030 [US4] Implement explicit legacy person-balance preview/review using append-only correction events in `src/modules/Ledger.lua`.
- [ ] T031 [US4] Add player declaration and officer review UI for seasonal Main/Alt and balance merge in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

## Phase 7: User Story 5 — Optional module gating and preservation (P2)

**Independent test**: Disable the module, reject every local/remote write, preserve history; re-enable and read the same records with no reset.

- [ ] T032 [P] [US5] Cover service, command, UI and incoming-sync denial while disabled in `tests/integration/seasonal_roster_feature_gate_spec.lua`.
- [ ] T033 [US5] Implement optional module registration, status display and preserved read-only history in `src/modules/OperationalPolicy.lua`, `src/modules/FeatureRegistry.lua`, and `src/ui/OfficerUI.lua`.

## Phase 8: User Story 6 — Requested path, Core decision and season rules (P1)

**Independent test**: A signup requests Thursday Core progression but remains Raider/candidate until a manual audited promotion; edits to published rules/policy preserve prior versions.

- [ ] T034 [P] [US6] Test AotC-to-Raider mapping, requested-path separation, policy revision snapshots and manual-only promotion in `tests/unit/seasonal_roster_status_spec.lua`.
- [ ] T035 [P] [US6] Test public rules visibility and officer-only editing/version history in `tests/integration/seasonal_roster_officer_ui_spec.lua` and `tests/integration/seasonal_roster_public_ui_spec.lua`.
- [ ] T036 [US6] Implement status catalog, rules publication, requested path and manual Core promotion records in `src/modules/SeasonalRoster.lua`.
- [ ] T037 [US6] Render requested path separately from awarded status and show the exact published rule revision in `src/ui/PlayerUI.lua`.
- [ ] T038 [US6] Add versioned rules/status editor and manual Core review controls with audit reasons in `src/ui/OfficerUI.lua`.
- [ ] T039 [P] [US6] Add English/French explanations for Raider, Core Raider, Officer and other statuses in `src/locales/enUS.lua` and `src/locales/frFR.lua`.

## Phase 9: User Story 7 — Preview and activate (P1)

**Independent test**: Incomplete dependencies or identity/balance blockers prevent activation; valid activation atomically publishes one manifest and initializes only approved people for the new season.

- [ ] T040 [P] [US7] Test activation blockers, previous-season preservation, failure injection and idempotent retry in `tests/unit/season_activation_spec.lua`.
- [ ] T041 [P] [US7] Test approved cohort filtering, Main/Alt deduplication and explicit no-rank handling in `tests/unit/season_allocation_spec.lua`.
- [ ] T042 [US7] Implement allocation preview from approved participants and current rank snapshot with explicit no-rank policy in `src/modules/SeasonalRoster.lua` and `src/modules/RankRules.lua`.
- [ ] T043 [US7] Implement activation manifest prepare/commit, operation replay protection and prior-season retention in `src/modules/SeasonalRoster.lua` and `src/modules/Seasons.lua`.
- [ ] T044 [US7] Add officer preview, blockers, confirmation and activation state in `src/ui/OfficerUI.lua`.

## Phase 10: User Story 8 — Seasonal allocation reconciliation (P1)

**Independent test**: For an active season with 30 approved participants and 900 unrelated/inactive guild characters, preview contains only the approved cohort; apply appends audited events and replay does not duplicate them.

- [ ] T045 [P] [US8] Test cohort-scoped preview, rank changes, stale preview refusal and idempotent append-only apply in `tests/unit/season_reconciliation_spec.lua`.
- [ ] T046 [US8] Implement separate operations for legacy balance merge, new-season initialization and active-season allocation drift in `src/modules/SeasonalRoster.lua` and `src/modules/Ledger.lua`.
- [ ] T047 [US8] Add officer reconciliation preview/apply UI with affected-person counts and reasons in `src/ui/OfficerUI.lua`.

## Phase 11: Cross-cutting sync, migration and release validation

- [ ] T048 [P] Add bounded manifest/config/enrollment sync tests for partial chunks, wrong guild, unauthorized sender, conflict, replay and module disabled in `tests/integration/seasonal_roster_sync_spec.lua`.
- [ ] T049 Implement canonical season dependency digests and manifest-gated activation over existing SyncV2 quotas in `src/modules/SyncV2.lua`.
- [ ] T050 Add repeated additive migration tests preserving legacy IDs, aliases, revisions and ledger transactions in `tests/integration/seasonal_roster_migration_spec.lua`.
- [ ] T051 Add performance fixtures and operation-count/timing checks for 20/60/500/1,000 roster records in `tests/performance/seasonal_roster_perf_spec.lua`.
- [ ] T052 Update user/Officer documentation, changelog and release notes with actual behavior and migration notes in `docs/`, `CHANGELOG.md`, and `docs/release-notes/`.
- [ ] T053 Execute the focused automated checks and two-client Retail matrix from `specs/029-seasonal-raid-roster/quickstart.md`; record exact commands, build ID, observations and limitations in that file.

## Dependencies and order

- Setup → Foundation.
- US1 enrollment and US3 season management establish the base data; US2 read-only projections depend on US1.
- US4 Main/Alt uses the existing CharacterEligibility boundary and may proceed after foundation, but must be complete before balance-dependent activation.
- US5 module gating is a cross-cutting gate and must be verified before release.
- US6 season rules/path may proceed after US3 and US1.
- US7 activation depends on US1, US3, US4 and US6.
- US8 reconciliation depends on US7's season identity/allocation model and the Ledger boundary.
- Sync, migration, performance and Retail evidence gate release.

```text
Setup -> Foundation -> US1 -> US2
                    -> US3 -> US6
US1 + Foundation -> US4
Foundation -> US5
US1 + US3 + US4 + US6 -> US7 -> US8
all selected stories -> Sync/Migration/Performance/Retail release gate
```

## Parallel opportunities

- T001 and T002 touch separate fixture/locale files.
- T010/T011 can be written independently before US1 implementation.
- T015/T016, T020/T021, and T040/T041 can be authored in parallel on disjoint test files.
- Do not parallelize edits to shared `SeasonalRoster.lua`, `OfficerUI.lua`, `PlayerUI.lua`, `SyncV2.lua`, or SavedVariables migration without explicit ownership.

## Implementation strategy

Deliver an end-to-end MVP with draft season, signup, officer approval, read-only roster, versioned rules/statuses, preview, explicit activation and a single-season ledger identity. Keep Main/Alt balance merge and active-season drift as gated follow-up increments if the legacy data model cannot be safely migrated in the same release. Do not ship partial activation, guessed identity links, or silent previous-season balance carry-over.
