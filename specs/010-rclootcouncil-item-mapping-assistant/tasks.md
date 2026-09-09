---

description: "Task list for the RCLootCouncil item mapping and installation assistant"

---

# Tasks: RCLootCouncil Item Mapping and Installation Assistant

**Input**: Design documents from `/specs/010-rclootcouncil-item-mapping-assistant/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Status**: All implementation tasks were completed for the `0.3.5` release. This is a
post-hoc Spec Kit record for behavior that shipped before the documentation was formalized.

**Tests**: Required by the feature specification. The implementation and regression tests
are recorded below; Retail-only checks remain manual validation steps in quickstart.md.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel when it touches a different file and has no incomplete dependency.
- **[Story]**: Maps the task to a user story from `spec.md`.
- Every task includes an exact repository path.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Record the RCLootCouncil family catalog and establish regression coverage.

- [X] T001 [P] Record the RCLootCouncil family catalog and Dibs semantic mapping in `specs/010-rclootcouncil-item-mapping-assistant/contracts/rclootcouncil-item-mapping.md`.
- [X] T002 [P] Add mapping, classification, and assistant fixtures in `tests/integration/ace3_options_spec.lua`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish canonical policy keys, classification precedence, and safe projection invariants.

- [X] T003 Canonicalize `TOKEN`, `TOKEN_SET`, `MOUNTS`, `PETS`, `RECIPE`, `DECOR`, and `OTHER` policy keys in `src/integrations/RCLootCouncil.lua`.
- [X] T004 Define RCLootCouncil family aliases and readable slot labels in `src/integrations/RCLootCouncilOptions.lua`.
- [X] T005 Enforce personal Catalyst/Cosmetic blocking and ordinary-loot fallback in `src/integrations/RCLootCouncil.lua`.
- [X] T006 Preserve projection idempotency, active responses, and response capacity invariants in `src/integrations/RCLootCouncil.lua`.

**Checkpoint**: Semantic families, fail-closed categories, and protected response projection are available before story-specific behavior.

---

## Phase 3: User Story 1 - Understand and configure loot families (Priority: P1) 🎯 MVP

**Goal**: Give GMs and Officers a clear mapping between RCLootCouncil button families and Dibs policy families.

**Independent Test**: Open the RCLootCouncil settings page and verify semantic, blocked, alias, resolved, and slot-only associations.

### Tests for User Story 1

- [X] T007 [P] [US1] Add mapping-guide and semantic-policy assertions in `tests/integration/ace3_options_spec.lua`.
- [X] T008 [P] [US1] Add readable slot and alias mapping assertions in `tests/integration/ace3_options_spec.lua`.

### Implementation for User Story 1

- [X] T009 [US1] Expose the semantic type list and RCLootCouncil mapping guide in `src/integrations/RCLootCouncilOptions.lua`.
- [X] T010 [US1] Map collection, special-effect, and readable equipment-slot groups without creating slot accounting families in `src/integrations/RCLootCouncilOptions.lua`.
- [X] T011 [US1] Verify officer/shared options and English fallback labels in `src/integrations/RCLootCouncilOptions.lua` and `src/locales/enUS.lua`.

**Checkpoint**: Every listed RCLootCouncil group has an understandable Dibs policy path or an explicit slot-only/blocked status.

---

## Phase 4: User Story 2 - Classify items safely (Priority: P1)

**Goal**: Show Dibs for eligible Curios, Tier Set tokens, collections, and standard loot while excluding personal categories.

**Independent Test**: Evaluate representative Curio, Tier Set, Catalyst, Cosmetic, ordinary gear, Mount, Pet, Recipe, and Decor items under different policies.

### Tests for User Story 2

- [X] T012 [P] [US2] Add Context Token and Tier Set classification assertions in `tests/integration/ace3_options_spec.lua`.
- [X] T013 [P] [US2] Add Armor Token disambiguation, ordinary-equipment fallback, and Catalyst/Cosmetic blocking assertions in `tests/integration/ace3_options_spec.lua`.

### Implementation for User Story 2

- [X] T014 [US2] Classify Context Tokens and RCLootCouncil token-table entries before broad Miscellaneous fallback in `src/integrations/RCLootCouncil.lua`.
- [X] T015 [US2] Add stable Context Token and token-table precedence to `src/integrations/EncounterJournal.lua`.
- [X] T016 [US2] Route ordinary equipment, Mounts, Pets, Recipes, and Decor through their documented semantic families in `src/integrations/RCLootCouncil.lua`.
- [X] T017 [US2] Keep personal Catalyst and Cosmetic items ineligible before policy lookup in `src/integrations/RCLootCouncil.lua`.

**Checkpoint**: Classification and policy eligibility match the documented family rules for the full acceptance corpus.

---

## Phase 5: User Story 3 - Complete first-time setup quickly (Priority: P1)

**Goal**: Let an authorized GM or Officer prepare a safe Dibs response without rebuilding RCLootCouncil configuration.

**Independent Test**: Apply each preset with RCLootCouncil available, absent, late-loaded, with enabled additional sets, and at full capacity.

### Tests for User Story 3

- [X] T018 [P] [US3] Add assistant preset, authorization, and no-ledger-write assertions in `tests/integration/ace3_options_spec.lua`.
- [X] T019 [P] [US3] Add repeat-refresh, preserved-response, enabled-set, and capacity assertions in `tests/integration/ace3_options_spec.lua`.

### Implementation for User Story 3

- [X] T020 [US3] Expose Curio + Tier Set, Standard loot + collections, and Refresh Dibs buttons controls in `src/integrations/RCLootCouncilOptions.lua`.
- [X] T021 [US3] Apply assistant presets through verified Dibs GM/Officer settings authority without writing the ledger in `src/integrations/RCLootCouncilOptions.lua`.
- [X] T022 [US3] Project the dedicated response into the default and already-enabled RCLootCouncil sets while preserving existing values in `src/integrations/RCLootCouncil.lua`.
- [X] T023 [US3] Keep the assistant usable without RCLootCouncil and retry projection after late load or profile availability changes in `src/integrations/RCLootCouncil.lua` and `src/Core.lua`.
- [X] T024 [US3] Add assistant readiness, capacity, and safety instructions to `specs/010-rclootcouncil-item-mapping-assistant/quickstart.md` and `docs/RC_OPTIONS.md`.

**Checkpoint**: First-time setup is repeatable, preserves guild configuration, and reports unavailable or full-capacity targets clearly.

---

## Phase 6: Polish and Cross-Cutting Validation

**Purpose**: Complete documentation, release traceability, and automated validation for the delivered feature.

- [X] T025 [P] Update the operator guide and feature changelog in `docs/RC_OPTIONS.md`, `README.md`, and `CHANGELOG.md`.
- [X] T026 [P] Record mapping decisions, entities, and projection contract in `specs/010-rclootcouncil-item-mapping-assistant/research.md`, `data-model.md`, and `contracts/rclootcouncil-item-mapping.md`.
- [X] T027 Run the full Lua suite and `git diff --check` using `specs/010-rclootcouncil-item-mapping-assistant/quickstart.md`.
- [X] T028 Verify TOC/version alignment and the packaged addon contents in `src/RCLootCouncil_dibs.toc` and `dist/RCLootCouncil_dibs-0.3.5.zip`.
- [X] T029 Review the delivered implementation against `specs/010-rclootcouncil-item-mapping-assistant/spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md`.

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1** has no dependencies and records fixtures and the mapping contract.
- **Phase 2** depends on Phase 1 and blocks all user stories.
- **User Stories 1, 2, and 3** depend on Phase 2 and can proceed independently once the
  shared policy and projection boundaries exist.
- **Phase 6** depends on the delivered story behavior and is the release documentation gate.

### User Story Dependencies

- **US1 (P1)**: Depends only on the foundational semantic keys and alias catalog.
- **US2 (P1)**: Depends on the foundational precedence and fail-closed classification rules.
- **US3 (P1)**: Depends on the projection invariants and authority boundary; it integrates
  the mappings from US1 and classifications from US2.

### Parallel Opportunities

- T001-T002 can run in parallel because they touch the contract and test fixture files.
- T007-T008, T012-T013, and T018-T019 are independent test additions within their story.
- T025-T026 are independent documentation updates during polish.

## Implementation Strategy

The MVP is US1 plus US2: a GM or Officer can understand the mapping and receive a safe
classification for Curios, Tier Set tokens, and ordinary loot. US3 then adds the repeatable
installation assistant. All listed work is complete and is represented by the `0.3.5`
release artifacts; this file preserves traceability for future changes.
