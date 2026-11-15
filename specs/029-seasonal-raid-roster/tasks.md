---
description: "Implementation tasks for the unified seasonal raid lifecycle"
---

# Tasks: Roster saisonnier et inscriptions aux raids

**Inputs**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`.

**Scope**: Implementation is authorized. Check a task only after its behavior and focused validation are complete; pre-existing dirty files alone are not evidence of completion. Preserve all unrelated local changes.

## Phase 1: Setup

**Purpose**: Establish test fixtures and localized UI contract.

- [x] T001 Add reusable canonical season, enrollment, rank and ledger fixtures to `tests/helpers/seasonal_roster_fixtures.lua`.
- [x] T002 [P] Add English and French labels for draft/review/ready/active lifecycle, requested path versus awarded status, and activation blockers to `src/locales/enUS.lua` and `src/locales/frFR.lua`.
- [x] T003 Document the current load order and owners of season, roster, identity, rank allocation, ledger and sync records in `specs/029-seasonal-raid-roster/research.md`.

## Phase 2: Foundational

**Purpose**: Define one stable season identity, migration compatibility, mutation boundary and activation model before story implementation.

- [x] T004 Add additive schema versioning and legacy season-ID aliases without removing existing SavedVariables in `src/Core.lua` and `tests/integration/seasonal_roster_migration_spec.lua`.
- [x] T005 Add shared season transition validation, expected-revision checks, stable operation IDs and audit helpers in `src/modules/SeasonalRoster.lua` and `tests/unit/seasonal_roster_lifecycle_spec.lua`.
- [x] T006 Add verified guild GM/Officer permission actions for season draft, approval, rule publication, allocation, reconciliation and activation in `src/modules/Permissions.lua` and `tests/unit/permissions_spec.lua`.
- [x] T007 Add module-disabled fail-closed behavior for local and received mutations in `src/modules/OperationalPolicy.lua`, `src/modules/FeatureRegistry.lua`, `src/modules/SeasonalRoster.lua`, and `tests/integration/seasonal_roster_feature_gate_spec.lua`.
- [x] T008 Specify and test activation-manifest dependency checks and the persistent visibility commit point in `src/modules/SeasonalRoster.lua`, `src/modules/Seasons.lua` and activation/SyncV2 suites. Commit and remote adoption stay hidden until config, approved roster, immutable identity snapshots, rank allocations and canonical ledger dependencies validate.
- [x] T009 Update the service and sync contracts with exact current schema, authority and conflict behavior in `specs/029-seasonal-raid-roster/contracts/roster-service.md` and `specs/029-seasonal-raid-roster/contracts/roster-sync.md`.

**Checkpoint**: Existing records are preserved; the season identity, authority checks, revision conflicts and manifest commit point have focused tests before UI or sync is changed.

## Phase 3: User Story 1 — Player enrollment (P1)

**Independent test**: In an open synthetic season, a player creates/edits/withdraws only their own registration; closed, stale, duplicate, disabled and other-owner writes fail without ledger mutation.

- [x] T010 [P] [US1] Add service tests for authenticated owner binding, off-guild characters, duplicate replay, closed window and no ledger side effects in `tests/unit/seasonal_roster_enrollment_spec.lua`.
- [x] T011 [P] [US1] Add PlayerUI signup tests for create/edit/withdraw and validation states in `tests/integration/seasonal_roster_signup_ui_spec.lua`.
- [x] T012 [US1] Implement revisioned own-enrollment create/edit/withdraw and immutable audit history in `src/modules/SeasonalRoster.lua`.
- [x] T013 [US1] Add PlayerUI enrollment form bound to the authenticated character and selected canonical season in `src/ui/PlayerUI.lua`.
- [x] T014 [US1] Ensure registration changes do not initialize or adjust Dibs and add regression assertions in `src/modules/SeasonalRoster.lua` and `tests/unit/seasonal_roster_enrollment_spec.lua`.

## Phase 4: User Story 2 — Read-only roster and statistics (P1)

**Independent test**: A normal member sees a paginated, privacy-safe roster; filters and totals agree and linked alts do not inflate the person count.

- [x] T015 [P] [US2] Test public-field allowlist, pagination, filters, off-guild entries, withdrawals and 1,000-row aggregate correctness in `tests/unit/seasonal_roster_projection_spec.lua`.
- [x] T016 [P] [US2] Test PlayerUI read-only access and matching list/statistics filters in `tests/integration/seasonal_roster_public_ui_spec.lua`.
- [x] T017 [US2] Implement bounded deterministic roster projection and cache invalidation keyed by season/revision/filter in `src/modules/SeasonalRoster.lua`.
- [x] T018 [US2] Implement composition statistics from the same eligible Main/person projection in `src/modules/SeasonalRoster.lua`.
- [x] T019 [US2] Add the read-only roster page, empty/stale states and bounded pagination in `src/ui/PlayerUI.lua`.

## Phase 5: User Story 3 — Prepare and manage a season (P1)

**Independent test**: A GM/Officer creates and edits a draft with dates, rules, statuses, Core criteria and rank allocations; no change occurs to the active ledger or previous season.

- [x] T020 [P] [US3] Test legal lifecycle transitions, date validation, revision conflicts, draft isolation and copy-settings-only behavior in `tests/unit/seasonal_roster_lifecycle_spec.lua`.
- [x] T021 [P] [US3] Test officer create/edit/review flows, actor audit and refusal for non-officer/stale roster in `tests/integration/seasonal_roster_officer_ui_spec.lua`.
  - [x] Verify the Officer draft raid-rule editor writes an audited, versioned revision.
  - [x] Cover non-officer denial, current-Officer review, stale enrollment revision and actor attribution in `tests/unit/seasonal_roster_enrollment_spec.lua`.
- [x] T022 [US3] Implement draft creation/editing, registration open/close and explicit completion/archive transitions in `src/modules/SeasonalRoster.lua`.
- [x] T023 [US3] Implement season-scoped versioned rules, participation definitions, promotion policy and rank-allocation configuration, including copying settings only from a prior season in `src/modules/SeasonalRoster.lua`.
  - [x] Persist bounded raid-rule text in immutable season revisions; expose the current text in the public season summary; copy it to a draft without copying participants, dates, identity, or ledger.
  - [x] Add versioned editable status/promotion policy and per-season rank allocation configuration; active-season allocation updates are audited and create a new revision without rewriting the committed activation baseline.
- [x] T024 [US3] Implement officer enrollment review, correction, withdrawal/removal and reasoned audit events in `src/modules/SeasonalRoster.lua`.
- [x] T025 [US3] Add the officer season editor, calendar/time controls, registration management and version history in `src/ui/OfficerUI.lua`.
  - [x] Add the season raid-rule editor to draft creation and the existing draft editor.
  - [x] Add a bounded, officer-only season revision history with actor, reason, action and lifecycle metadata.
  - [x] Test calendar date/time creation and Officer open/close registration controls without activating the season or mutating the active ledger in `tests/integration/seasonal_roster_officer_ui_spec.lua`.
  - [x] Add broader officer season lifecycle, status policy and per-season rank allocation controls, including authorized active-season rank publication for the separate drift workflow.
- [x] T026 [US3] Add tests for seven-day post-completion archive behavior and registration close not archiving in `tests/unit/seasonal_roster_lifecycle_spec.lua`.

## Phase 6: User Story 4 — Main/Alt declaration and person balance (P2)

**Independent test**: A reviewed Main/Alt relationship follows the same person identity; balance preview shows every legacy balance and retains the selected Main balance without summing or rewriting old transactions.

- [x] T027 [P] [US4] Add identity and 14-day Main-change probation regression cases in `tests/unit/character_eligibility_spec.lua`.
- [x] T028 [P] [US4] Add focused tests for selected-Main-balance retention, audited correction and stale-replay safety in `tests/unit/seasonal_roster_balance_spec.lua`.
- [x] T029 [US4] Integrate immutable seasonal Main snapshots and revisioned, audited relationship/Main-change wrappers with `CharacterEligibility` in `src/modules/SeasonalRoster.lua`.
- [x] T030 [US4] Implement explicit legacy person-balance preview/review using append-only correction events in `src/modules/Ledger.lua`.
  - Each Alt correction is a separate protected `ledger.adjust` transaction with a required reason and confirmation; refresh the preview before correcting another character. The Main balance is never changed by this workflow.
- [x] T031 [US4] Add player declaration and officer review UI for seasonal Main/Alt and legacy-balance review in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

## Phase 7: User Story 5 — Optional module gating and preservation (P2)

**Independent test**: Disable the module, reject every local/remote write, preserve history; re-enable and read the same records with no reset.

- [x] T032 [P] [US5] Cover service, UI and incoming-sync denial while disabled in `tests/integration/seasonal_roster_feature_gate_spec.lua` (the feature has no dedicated slash command).
- [x] T033 [US5] Implement optional module registration/status and preserved bounded read-only history in `src/modules/OperationalPolicy.lua`, `src/modules/FeatureRegistry.lua`, `src/modules/SeasonalRoster.lua`, and `src/ui/OfficerUI.lua`.

## Phase 8: User Story 6 — Requested path, Core decision and season rules (P1)

**Independent test**: A signup requests Thursday Core progression but remains Raider/candidate until a manual audited promotion; edits to published rules/policy preserve prior versions.

- [x] T034 [P] [US6] Test AotC-to-Raider mapping, requested-path separation, policy revision snapshots and manual-only promotion in `tests/unit/seasonal_roster_status_spec.lua`.
- [x] T035 [P] [US6] Test public rules visibility and officer-only editing/version history in `tests/integration/seasonal_roster_officer_ui_spec.lua` and `tests/integration/seasonal_roster_public_ui_spec.lua`.
  - [x] Verify published raid rules render in PlayerUI and Officer revision history is bounded and renders.
- [x] T036 [US6] Implement status catalog, rules publication, requested path and manual Core promotion records in `src/modules/SeasonalRoster.lua`.
- [x] T037 [US6] Render requested path separately from awarded status and show the exact published rule revision in `src/ui/PlayerUI.lua`.
- [x] T038 [US6] Add versioned rules/status editor and manual Core review controls with audit reasons in `src/ui/OfficerUI.lua`.
- [x] T039 [P] [US6] Add English/French explanations for Raider, Core Raider, Officer and other statuses in `src/locales/enUS.lua` and `src/locales/frFR.lua`.

## Phase 9: User Story 7 — Preview and activate (P1)

**Independent test**: Incomplete dependencies or identity/balance blockers prevent activation; valid activation atomically publishes one manifest and initializes only approved people for the new season.

- [x] T040 [P] [US7] Test activation blockers, previous-season preservation, precommit failure injection and idempotent retry in `tests/unit/season_activation_spec.lua`.
- [x] T041 [P] [US7] Test approved cohort filtering, Main/Alt deduplication and explicit no-rank handling in `tests/unit/seasonal_roster_activation_spec.lua`.
- [x] T042 [US7] Implement read-only allocation preview from approved participants and the current guild rank snapshot, with a versioned explicit no-rank policy, in `src/modules/SeasonalRoster.lua`.
- [x] T043 [US7] Implement activation manifest prepare/commit, operation replay protection and prior-season retention in `src/modules/SeasonalRoster.lua` and `src/modules/Seasons.lua`.
- [x] T044 [US7] Add officer preview, blockers, preview-bound reason/confirmation and activation state in `src/ui/OfficerUI.lua`.

## Phase 10: User Story 8 — Seasonal allocation reconciliation (P1)

**Independent test**: For an active season with 30 approved participants and 900 unrelated/inactive guild characters, preview contains only the approved cohort; apply appends audited events and replay does not duplicate them.

- [x] T045 [P] [US8] Test cohort-scoped preview, rank changes, stale preview refusal and idempotent append-only apply in `tests/unit/season_reconciliation_spec.lua` and `tests/integration/seasonal_roster_cohort_spec.lua`.
- [x] T046 [US8] Implement separate operations for legacy balance merge, new-season initialization and active-season allocation drift in `src/modules/SeasonalRoster.lua` and `src/modules/Ledger.lua`.
- [x] T047 [US8] Add officer reconciliation preview/apply UI with affected-person counts and reasons in `src/ui/OfficerUI.lua`.

## Phase 11: Cross-cutting sync, migration and release validation

- [x] T048 [P] Add bounded manifest/config/enrollment/identity sync tests for partial chunks, wrong guild, unauthorized/noncanonical sender, conflict, replay, dependency recovery, and module disabled in `tests/integration/seasonal_roster_sync_spec.lua`.
  - [x] Activation coverage uses real serialized bytes and the production OnAddonMessage path for manifest-first and manifest-last adoption, canonical ledger dependency transfer, missing-detail recovery, rank dependency mismatch, author verification, replay, quotas and module gates.
  - [x] Cover wrong-guild authority rejection, missing parent, idempotent replay, unauthorized member, and module-disabled receive.
  - [x] Add transport-level partial chunk/size quota and forged conflict cases.
- [x] T049 Implement canonical season dependency descriptors and manifest-gated activation over existing SyncV2 quotas in `src/modules/SyncV2.lua`.
- [x] T050 Add repeated additive migration tests preserving legacy IDs, aliases, revisions and ledger transactions in `tests/integration/seasonal_roster_migration_spec.lua`.
- [x] T051 Add performance fixtures and operation-count/timing checks for 20/60/500/1,000 roster records in `tests/performance/seasonal_roster_perf_spec.lua`.
  - Four passing scenarios check matching aggregates, bounded/deduplicated pagination, isolated cached results and one identity lookup per eligible row on a cold or invalidated projection, with no identity lookup on cached pagination. Timings are offline measurements; Retail CPU/heap evidence remains part of T053.
- [x] T052 Update player/Officer usage documentation and the dated unreleased changelog with actual behavior, preservation and validation limits. The existing 0.8.12 release notes remain historical; no version or release is changed in this work.
- [ ] T053 Complete the full release validation gate in `specs/029-seasonal-raid-roster/quickstart.md`.
  - [x] Run the focused service/UI/sync/performance suites under Fengari and native Lua 5.1.5; record exact selections and results in the quickstart.
  - [x] Compile all addon Lua sources with Lua 5.1.5 and record local validation limitations.
  - [ ] Run and record the two-client Retail matrix with the actual WoW build ID. No Retail clients are available in this workspace, so this release-only check remains open.

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

## Phase 12: Convergence — activation safety gaps

- [x] T054 [US7] Implement and failure-inject a detached, idempotent batch for initial season allocations so no subset is persisted when any allocation fails; publish the staged ledger only after all rows and the activation manifest validate.
- [x] T055 [US7] Bind the activation manifest to the exact per-season rank-rule snapshot and reject activation/sync adoption when any client has a different or missing rank-rule dependency.
  - [x] Publish local rank-rule values as a validated, immutable `SEASON_ALLOCATION_PUBLISHED` revision; require this snapshot for preview and transfer it through SyncV2.
  - [x] Advertise a separate snapshot capability and refuse the revision when a peer lacks or misrepresents support.
  - [x] Add activation-manifest references and refuse activation on missing or mismatched roster, immutable identity, portable guild-rank snapshot, or allocation revision/hash dependencies. Local generation counters are not compared cross-client.

## Phase 13: Convergence — draft selection safety

- [x] T056 [P] Add local, received-catalog and legacy-selection regression cases proving a roster season in DRAFT never becomes the current active ledger season through catalog publication, archive fallback, `GetCurrent`, or `season.set`. **Validated 2026-11-15:** six safety cases plus the SyncV2 transfer edge pass; independent QA confirms the archive-pointer fix. See `tests/integration/season_draft_selection_safety_spec.lua`.
- [x] T057 Preserve draft/inactive state through catalog synchronization and refuse explicit or implicit selection of a draft; retain the atomic activation manifest as the only path that makes a roster draft Active. **Validated 2026-11-15:** real bounded SyncV2 `TRANSFER_BEGIN/CHUNK/END` applies an archive-only catalog with `currentSeasonId=nil`; the receiver clears the archived pointer and does not select the included inactive draft. Draft/catalog suites pass 17/17 under Fengari and Lua 5.1.5; independent QA confirms the path. Retail validation remains separate under T053.

## Automated completion checkpoint — 2026-11-15

- Focused Lua/Fengari and native Lua 5.1.5 selection: **87 passed, 0 failed (13 files) in each runtime**, including activation failure injection/replay, compact-manifest round-trip under the unchanged wire quota, oversized-identity precommit refusal, reconciliation/stale preview/spent balance, 30- and 60-person cohorts plus 900 unrelated guild characters, real-byte SyncV2 convergence/recovery, UI, module gating and 20/60/500/1,000 projection budgets. Exact commands and timing evidence are in `quickstart.md`.
- Offline Lua 5.1.5 compilation: **108 addon source files passed**, using the project compilation script and an explicit compiler path. Retail two-client validation remains unchecked under T053.
- The native Lua 5.1.5 focused rerun also passed **85 tests across the same 13 files**, including owner-bound enrollment history and all activation, reconciliation, convergence, UI, gating, cohort and performance cases.
- An earlier all-tests native Lua 5.1 run had **1,589 passed and 266 failed (244 files)**, largely due pre-existing gaps in unrelated canonical-dispute fixtures/APIs and Lua harness compatibility. It is recorded in `quickstart.md` and is not represented as a passing full-suite run.
