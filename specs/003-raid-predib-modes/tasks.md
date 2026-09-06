---

description: "Task list for Raid Pre-Dib Modes feature implementation"
---

# Tasks: Raid Pre-Dib Modes

**Input**: Design documents from `/specs/003-raid-predib-modes/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included because the feature changes shared request authority, synchronization, and user-facing raid behavior. The repository uses the Fengari Lua harness.

**Organization**: Tasks are grouped by user story so each story can be implemented, tested, and demonstrated independently after shared prerequisites are complete.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when it touches a different file and has no incomplete dependency.
- **[Story]**: User story mapping from spec.md.
- Every task includes an exact repository path.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the test doubles and source registration points needed for safe protocol, raid-context, and UI work.

- [X] T001 Confirm feature 003 documentation paths and addon module load order in `src/RCLootCouncil_dibs.toc`, `tests/helpers/load_addon.lua`, and `specs/003-raid-predib-modes/plan.md`
- [X] T002 [P] Extend addon-message, guild-officer, raid-role, and instance-context doubles in `tests/helpers/wow_api.lua`
- [X] T003 [P] Add deterministic WoW event dispatch, addon-message capture, and peer-delivery helpers in `tests/helpers/wow_api.lua`
- [X] T004 [P] Add Adventure Guide prompt/navigation spies and combat-state controls in `tests/helpers/wow_api.lua`
- [X] T005 Record feature-specific automated and Retail validation commands in `specs/003-raid-predib-modes/quickstart.md`

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make request revision, mode persistence, secure request merge, and bounded transport available to every user story.

- [X] T006 [P] Add contract coverage for mode validation, request revision merging, and immutable request-origin fields in `tests/contract/predibs_api_contract_spec.lua`
- [X] T007 [P] Add protocol privacy and malformed-message coverage in `tests/contract/sync_privacy_spec.lua`
- [X] T008 Add versioned Pre-Dib mode policy persistence and default policy migration in `src/Core.lua` and `src/modules/PreDibs.lua`
- [X] T009 Add request revision, mode-at-creation, validation-context, and delivery-state migration defaults in `src/Core.lua` and `src/modules/PreDibs.lua`
- [X] T010 Add validated Pre-Dib request upsert semantics that preserve immutable fields and accept only newer revisions in `src/modules/PreDibs.lua`
- [X] T011 Add compact protocol envelope validation, forbidden live-loot field rejection, transfer expiry, and bounded reassembly state in `src/modules/Sync.lua`
- [X] T012 Register the addon-message prefix and forward login, reconnect, roster, and addon-message events from `src/Core.lua` to `src/modules/Sync.lua`
- [X] T013 Verify new mode, request, and transport state do not mutate ledger transactions or invoke protected award actions in `tests/integration/predibs_ledger_boundary_spec.lua` and `tests/contract/sync_privacy_spec.lua`

**Checkpoint**: Mode-aware mutable request state is versioned and recoverable, transport accepts only compact Dibs request data, and ledger authority remains untouched.

## Phase 3: User Story 1 - Choose the Guild Pre-Dib Mode (Priority: P1)

**Goal**: Authorized officers can select Wild Open or Encounter policy for a season, and every request is validated through the shared pipeline.

**Independent Test**: Switch modes and submit the same supported item from outside the raid, inside the owning raid, and in a dungeon; verify acceptance or rejection and unchanged historical records.

- [X] T014 [P] [US1] Add Wild Open and Encounter acceptance/rejection matrix tests in `tests/unit/predibs_request_spec.lua`
- [X] T015 [P] [US1] Add actual player raid-context and item-to-raid validation tests in `tests/unit/encounter_journal_predib_spec.lua`
- [X] T016 [US1] Add authorized mode-change action and audit metadata in `src/modules/ProtectedActions.lua` and `src/modules/PreDibs.lua`
- [X] T017 [US1] Implement shared mode-aware request validation before public request persistence in `src/modules/PreDibs.lua` and `src/modules/LootPipeline.lua`
- [X] T018 [US1] Apply Encounter-mode player-location and matching-raid checks to Adventure Guide submission in `src/integrations/EncounterJournal.lua`
- [X] T019 [US1] Expose current mode and rejection reason in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`
- [X] T020 [US1] Add mode selector, authorization feedback, and last-change audit display to the officer settings tab in `src/ui/OfficerUI.lua`
- [X] T021 [US1] Verify a mode change affects only future request validation and never rewrites request or ledger history in `tests/integration/predibs_migration_spec.lua`

**Checkpoint**: Wild Open and Encounter mode decisions are centralized, authorized, auditable, and consistently enforced by every request entry point.

## Phase 4: User Story 2 - Recover Pre-Dibs Created Before the Raid (Priority: P1)

**Goal**: A player-created active Pre-Dib survives an officer absence and reaches an eligible officer once both clients reconnect.

**Independent Test**: Create an active request without an officer, reconnect the player and officer into the same raid, then verify one received record, its original creation time, current revision, and acknowledgement state.

- [X] T022 [P] [US2] Add unit tests for manifest comparison, fetch selection, request revision ordering, and acknowledgement state in `tests/unit/predibs_lifecycle_spec.lua`
- [X] T023 [P] [US2] Add integration tests for offline officer recovery, duplicate delivery, stale updates, lost acknowledgement retry, and offline-player absence in `tests/integration/predibs_sync_recovery_spec.lua`
- [X] T024 [US2] Implement HELLO and active-request MANIFEST exchange for reconnect and raid roster transitions in `src/modules/Sync.lua` and `src/Core.lua`
- [X] T025 [US2] Implement officer-side missing/stale FETCH selection and owner-identity validation in `src/modules/Sync.lua`
- [X] T026 [US2] Implement bounded TRANSFER_BEGIN, TRANSFER_CHUNK, and TRANSFER_END handling with checksum validation in `src/modules/Sync.lua`
- [X] T027 [US2] Implement REQUEST_ACK handling, persisted delivery acknowledgement metadata, and bounded retransmission in `src/modules/Sync.lua` and `src/modules/PreDibs.lua`
- [X] T028 [US2] Prevent untrusted request transfers from creating or overwriting finalized fulfillment in `src/modules/Sync.lua` and `src/modules/PreDibs.lua`
- [X] T029 [US2] Display request delivery state and original creation time in the officer Pre-Dibs tab in `src/ui/OfficerUI.lua`
- [X] T030 [US2] Add multi-officer relay preference and direct-delivery failover coverage without establishing a single source of truth in `src/modules/RaidRelay.lua` and `tests/integration/predibs_sync_recovery_spec.lua`

**Checkpoint**: Persisted active requests recover after reconnect with duplicate-safe revisions and acknowledgements, while missing offline players are never claimed as synchronized.

## Phase 5: User Story 3 - Remind and Guide Raid Members (Priority: P2)

**Goal**: Authorized raid members can send informational Dib reminders, and opted-in players can choose a safe relevant Adventure Guide prompt on raid entry.

**Independent Test**: Exercise reminder authorization and prompt accept/decline/opt-out paths in and out of raid, including combat deferral and boss-aware navigation fallback.

- [X] T031 [P] [US3] Add reminder authorization and channel-availability matrix tests in `tests/unit/permissions_spec.lua` and `tests/integration/predibs_announcements_spec.lua`
- [X] T032 [P] [US3] Add raid-entry prompt preference, event deduplication, combat deferral, and Adventure Guide fallback tests in `tests/integration/raid_prompt_spec.lua`
- [X] T033 [US3] Implement non-accounting reminder authorization for verified guild GM/officer, current Raid Leader, or verified RCLootCouncil Master Looter in `src/modules/Permissions.lua`; reminder authority does not authorize Dibs administration
- [X] T034 [US3] Implement in-raid Dib reminder send and receive behavior without touching request or ledger state in `src/modules/RaidRelay.lua` and `src/Core.lua`
- [X] T035 [US3] Persist the player-local opt-in prompt preference and expose it through `src/ui/PlayerUI.lua` and `src/integrations/RCLootCouncilOptions.lua`
- [X] T036 [US3] Add raid entry and encounter observation with session deduplication in `src/Core.lua` and a new `src/modules/RaidPrompts.lua`
- [X] T037 [US3] Implement explicit accept/decline prompt UI, combat deferral, and post-combat context revalidation in `src/modules/RaidPrompts.lua`
- [X] T038 [US3] Implement supported raid overview and boss-loot Adventure Guide navigation with safe capability fallbacks in `src/integrations/EncounterJournal.lua`
- [X] T039 [US3] Verify reminders and prompts never create requests, consume Dibs, or alter ledger history in `tests/integration/raid_prompt_spec.lua` and `tests/integration/predibs_ledger_boundary_spec.lua`

**Checkpoint**: Reminders and prompts are optional, authorized, combat-safe helpers with no independent accounting effect.

## Phase 6: User Story 4 - Review Mode-Aware Seasonal Activity (Priority: P3)

**Goal**: Officers can filter seasonal Pre-Dib activity and explain each request's mode, context, status, timing, and delivery state.

**Independent Test**: Create requests in both modes, include synchronized and pending-delivery examples, select each season, and search/filter the officer Pre-Dibs view.

- [X] T040 [P] [US4] Add officer seasonal Pre-Dib mode/context/delivery rendering tests in `tests/integration/combat_safety_spec.lua`
- [X] T041 [P] [US4] Add request-history migration and cross-season filtering tests in `tests/integration/predibs_migration_spec.lua`
- [X] T042 [US4] Extend officer Pre-Dib list rows and search matching with mode, validation context, delivery state, and rejection diagnostics in `src/ui/OfficerUI.lua`
- [X] T043 [US4] Add concise mode and recovery status to the officer dashboard and season statistics views in `src/ui/OfficerUI.lua`
- [X] T044 [US4] Preserve display compatibility for legacy requests without mode or delivery metadata in `src/modules/PreDibs.lua` and `src/ui/OfficerUI.lua`

**Checkpoint**: Officers can inspect a season-long, filterable Pre-Dib history and distinguish validated, pending-delivery, and received requests.

## Phase 7: Polish and Cross-Cutting Validation

**Purpose**: Verify all feature requirements, privacy boundaries, regression behavior, and manual Retail scenarios.

- [X] T045 [P] Map FR-001 through FR-017 to automated evidence in `tests/contract/predibs_feature_acceptance_spec.lua` and `specs/003-raid-predib-modes/quickstart.md`
- [X] T046 [P] Review new protocol payloads for forbidden live loot, candidate, vote, response, and session fields in `tests/contract/sync_privacy_spec.lua` and `docs/PROTOCOL.md`
- [X] T047 Update architecture and protocol documentation for mode policy, request recovery, acknowledgements, reminders, and prompt safety in `docs/ARCHITECTURE.md` and `docs/PROTOCOL.md`
- [X] T048 Run the full Fengari suite and record result in `specs/003-raid-predib-modes/quickstart.md`
- [X] T049 Run diagnostics and `git diff --check` for all feature files and record results in `specs/003-raid-predib-modes/quickstart.md`
- [ ] T050 Perform Retail validation for Wild Open/Encounter modes, two-client recovery, reminders, entry prompts, boss navigation fallback, and combat deferral in `specs/003-raid-predib-modes/quickstart.md`
- [X] T051 Review implementation against `specs/003-raid-predib-modes/spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md`; record final acceptance evidence in `specs/003-raid-predib-modes/quickstart.md`

## Phase 8: Difficulty and Vault Acquisition Extension

**Purpose**: Preserve raid-difficulty identity for requests and show Great Vault ownership without adding accounting effects.

- [X] T052 [P] Add Normal/Heroic/Mythic request identity, mode-specific difficulty derivation, and Vault non-accounting tests in `tests/unit/predibs_request_spec.lua`, `tests/unit/encounter_journal_predib_spec.lua`, and `tests/integration/predibs_ledger_boundary_spec.lua`
- [X] T053 [P] Add migration and cross-difficulty duplicate/fulfillment coverage in `tests/integration/predibs_migration_spec.lua` and `tests/integration/finalized_award_flow_spec.lua`
- [X] T054 Add difficulty persistence, migration defaults, and player/item/season/difficulty request matching in `src/modules/PreDibs.lua`
- [X] T055 Add non-accounting Vault acquisition persistence and display query APIs in `src/modules/PreDibs.lua` or a dedicated `src/modules/Acquisitions.lua`, and register any new module in `src/RCLootCouncil_dibs.toc` and `tests/helpers/load_addon.lua`
- [X] T056 Derive Wild Open difficulty from the selected Adventure Guide difficulty and Encounter difficulty from verified instance context in `src/integrations/EncounterJournal.lua` and `src/modules/LootPipeline.lua`
- [X] T057 Match finalized awards to confirmed Pre-Dibs using difficulty when award context provides it in `src/modules/ProtectedActions.lua` and `src/modules/PreDibs.lua`
- [X] T058 Add an explicit player-recorded Vault acquisition workflow and render `Acquired` with difficulty/source in `src/ui/PlayerUI.lua` and `src/integrations/EncounterJournal.lua`
- [X] T059 Render request difficulty and Vault acquisition state in `src/ui/OfficerUI.lua` and add search/filter coverage in `tests/integration/combat_safety_spec.lua`
- [ ] T060 Update `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`, and `specs/003-raid-predib-modes/quickstart.md`; run the full Fengari suite, `git diff --check`, and Retail scenarios E plus the existing T050 validation.

## Dependencies and Execution Order

### Phase Dependencies

- Phase 1 -> Phase 2 -> User Stories 1 and 2.
- US1 and US2 can proceed after Phase 2; US2 uses the shared request revision from Phase 2 but does not depend on mode UI completion.
- US3 depends on Phase 2 and may run alongside the late part of US2.
- US4 depends on US1 and US2 because it displays mode and delivery metadata.
- All user stories -> Phase 7.
- Phase 8 depends on the completed request-mode foundation and must finish before T050 can certify the expanded feature.

### User Story Completion Order

```text
Setup -> Foundation -> [US1 Mode policy + US2 Recovery sync] -> US3 Reminders/prompts -> US4 Officer review -> Polish
																		-> Phase 8 Difficulty/Vault -> Retail validation
```

### Parallel Opportunities

- T002, T003, and T004 can run in parallel after T001.
- T006 and T007 can run in parallel before the foundational implementation.
- T014 and T015 can run in parallel for US1.
- T022 and T023 can run in parallel for US2.
- T031 and T032 can run in parallel for US3.
- T040 and T041 can run in parallel for US4.
- T045 and T046 can run in parallel during polish.

## Independent Story Validation

- **US1**: Wild Open accepts supported active-season raid items outside raid; Encounter accepts only verified matching current-raid loot; unauthorized mode changes and history rewrites fail.
- **US2**: A request made while officers are absent survives locally, synchronizes exactly once after player and officer reconnect, and retains original time and current revision.
- **US3**: Authorized reminders reach the raid without accounting effects; prompt acceptance is opt-in, safely navigates or falls back, and defers in combat.
- **US4**: The officer can select a season and filter requests by player/item/status while seeing mode, validation context, timestamp, and acknowledgement status.
- **Difficulty/Vault extension**: Wild Open uses Adventure Guide difficulty; Encounter uses actual raid difficulty; Vault acquisitions show as Acquired without any Dib, request, or ledger mutation.

## Implementation Strategy

### MVP First: Mode-Aware Requests (US1)

1. Complete setup and foundation through T013.
2. Deliver mode persistence, protected policy changes, and shared validation through T021.
3. Validate Wild Open and Encounter behavior independently before enabling cross-client recovery.

### Increment 2: Offline Recovery (US2)

1. Add manifest/fetch and revision-aware request merge.
2. Add bounded transfers and acknowledgements.
3. Validate two-client reconnect recovery and privacy boundaries.

### Increment 3: Raid Guidance (US3)

1. Deliver reminder authorization and raid chat behavior.
2. Add opt-in preference, event observation, combat-safe prompt, and Adventure Guide navigation.
3. Validate no accounting effects.

### Increment 4: Officer Operational Visibility (US4)

1. Render mode, validation context, delivery status, and legacy-safe rows.
2. Validate seasonal filtering and search.

### Final Validation

1. Run all automated tests through Fengari.
2. Run diagnostics and `git diff --check`.
3. Perform manual Retail validation with two clients where possible.
4. Mark each task complete only after implementation and recorded validation evidence.

## Phase 9: Ace3 Transport and Settings Migration

**Purpose**: Replace duplicated transport, event, timer, and settings infrastructure without changing Dibs authority, persistence, or privacy rules.

- [X] T061 [P] Add Ace3 embedded load-order, LibStub coexistence, and AceComm/AceSerializer protocol compatibility tests in `tests/helpers/load_addon.lua`, `tests/helpers/wow_api.lua`, and `tests/contract/sync_privacy_spec.lua`
- [X] T062 [P] Add AceEvent/AceTimer raid prompt, roster, retry, and combat-deferral regression coverage in `tests/integration/raid_prompt_spec.lua` and `tests/integration/predibs_sync_recovery_spec.lua`
- [X] T063 Load `src/libs/Ace3.toc` before Dibs source modules and create a narrow framework adapter obtained through LibStub in `src/RCLootCouncil_dibs.toc` and `src/integrations/Ace3.lua`
- [X] T064 Replace manual addon-message serialization, fragmentation, and transport registration with AceComm/AceSerializer through the adapter in `src/modules/Sync.lua` while preserving protocol fields and bounded recovery behavior
- [X] T065 Replace duplicate event/timer registrations for sync recovery and raid prompts with AceEvent/AceTimer through the adapter in `src/Core.lua`, `src/modules/RaidPrompts.lua`, and `src/modules/Sync.lua`
- [X] T066 Move player/officer mode, reminder, prompt, and Pre-Dib settings registration to AceConfig through `src/integrations/RCLootCouncilOptions.lua`, preserving current UI controls and Dibs SavedVariables
- [X] T067 Verify AceDB is not introduced as a persistence replacement; preserve versioned Dibs SavedVariables migrations and standalone RCLootCouncil behavior in `src/Core.lua`, `tests/integration/predibs_migration_spec.lua`, and `tests/contract/core_independence_spec.lua`
- [X] T068 Update `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`, and `specs/003-raid-predib-modes/quickstart.md`; run full Fengari regression validation with RCLootCouncil both present and absent. Retail validation remains tracked by T050.
