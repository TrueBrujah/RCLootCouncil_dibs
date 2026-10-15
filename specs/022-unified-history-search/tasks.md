# Tasks: Unified History Search and Filters

**Input**: Design documents from `/specs/022-unified-history-search/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ui-history-filters.md, quickstart.md

**Organization**: Tasks are grouped by user story so each slice can be implemented and tested independently.

## Format

Each task uses `- [ ] T### [P?] [Story?] Description with file path`. `[P]` marks work that can proceed independently; story labels map to the user stories in `spec.md`.

## Phase 1: Setup

**Purpose**: Register the shared UI helper in addon load order.

- [X] T001 Create the shared `Dibs.HistoryFilters` module and register its load order in `src/ui/HistoryFilters.lua`, `src/RCLootCouncil_dibs.toc`, `tests/helpers/load_addon.lua`, and `tests/integration/toc_load_spec.lua`.

---

## Phase 2: Foundational

**Purpose**: Implement consistent, side-effect-free matching semantics before adding page controls.

- [X] T002 [P] Add failing unit tests for literal case-insensitive matching, AND filters, missing metadata, inclusive dates, invalid/reversed dates, and stable timestamp ties in `tests/unit/history_filters_spec.lua`.
- [X] T003 Implement pure query, field, and date-range matching helpers with missing-field-safe semantics in `src/ui/HistoryFilters.lua`.
- [X] T004 [P] Add localized English and French labels, help, date errors, no-results, and unavailable-source text for Player and Officer history filters in `src/locales/enUS.lua` and `src/locales/frFR.lua`.

**Checkpoint**: Shared matching rules, localization keys, and filter contracts are ready for the independent Player and Officer history surfaces.

---

## Phase 3: User Story 1 - Find a Personal Record (Priority: P1) 🎯 MVP

**Goal**: Let a player find personal Dibs and Great Vault history without widening data visibility.

**Independent Test**: Seed personal and other-player records with mixed dates, items, sources, and optional encounter fields; verify matching, clear/reset behavior, empty state, and that no other-player or private Officer data appears.

### Implementation

- [X] T005 [US1] Add failing integration tests for personal Dibs and Great Vault history matching, current-scope clearing, missing encounter metadata, and privacy boundaries in `tests/integration/unified_history_search_spec.lua`.
- [X] T006 [US1] Extend Player Dibs History controls to filter recorded item/raid/boss, date, source, and status metadata without changing its current-season scope in `src/ui/PlayerUI.lua`.
- [X] T007 [US1] Add shared text/date/source/status filtering and reset-to-first-page behavior to the Player Great Vault history page in `src/ui/PlayerUI.lua`.

**Checkpoint**: Personal Dibs and Vault history are searchable and remain limited to the current player's authorized projection.

---

## Phase 4: User Story 2 - Find Guild Records (Priority: P1)

**Goal**: Let verified Officers find guild records using the same criteria across existing ledger, request, Vault, and RCLootCouncil history views.

**Independent Test**: Seed current guild members' Dibs, Pre-Dib, Vault, and award-history records; combine player/item/raid/boss/date/status/source filters and verify that only authorized matching records are returned.

### Implementation

- [X] T008 [US2] Add failing integration tests for player/item/raid/boss/date/status/source matching across authorized Officer sources, preserving record identity, and denying unauthorized guild-wide access in `tests/integration/unified_history_search_spec.lua`.
- [X] T009 [US2] Extend `BuildLedgerDetails` matching for permitted player, item, raid, boss, date, status, and source metadata while preserving existing action and season scope in `src/ui/OfficerUI.lua`.
- [X] T010 [US2] Add consistent player/item/raid/boss/date/status/source filter controls and validated inclusive date ranges to the Officer ledger/actions history view in `src/ui/OfficerUI.lua`.
- [X] T011 [US2] Extend the Officer Pre-Dib history projection and filter controls for recorded item, player, date, status, and source fields in `src/ui/OfficerUI.lua`.
- [X] T012 [US2] Extend Great Vault review criteria to include item, player, date, and available encounter/source metadata without searching private evidence in `src/ui/OfficerUI.lua`.
- [X] T013 [US2] Extend the existing RCLootCouncil history preview filters for player, item, raid, boss, date, and source while retaining its preview/confirmation boundary in `src/ui/OfficerUI.lua` and `src/ui/LogsUI.lua`.

**Checkpoint**: Verified Officers can search each existing supported history page; unauthorized access and historical confirmation behavior are unchanged.

---

## Phase 5: User Story 3 - Understand Search Results (Priority: P2)

**Goal**: Make empty, unavailable, and invalid-filter outcomes distinct and predictable across the history pages.

**Independent Test**: Use empty, unavailable, incomplete-metadata, invalid-date, reversed-range, and multi-page fixtures; verify each state and ensure clearing filters restores the page's original scope.

### Implementation

- [X] T014 [US3] Add failing acceptance tests for source-unavailable versus empty results, missing raid/boss metadata, reversed dates, clear filters, valid page selection, and deterministic ordering in `tests/integration/unified_history_search_spec.lua`.
- [X] T015 [P] [US3] Add explicit no-results, unavailable-source, and invalid-range states plus per-field clear actions to Player history controls in `src/ui/PlayerUI.lua`.
- [X] T016 [P] [US3] Add explicit no-results, unavailable-source, and invalid-range states plus per-field clear actions to Officer history controls in `src/ui/OfficerUI.lua`.
- [X] T017 [US3] Ensure filter changes reset pagination and newest-first sorting uses stable record identities across all affected views in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

**Checkpoint**: Users can distinguish unavailable data from no matches and recover the original view without changing records.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verify the completed feature and keep user-facing documentation/version information aligned.

- [X] T018 Update the English and French Player and Officer history guides to document filter fields, date format, privacy, and missing-metadata behavior in `docs/player/PLAYER_GUIDE_EN.md`, `docs/officer/GM_OFFICER_GUIDE_EN.md`, `docs/player/MODE_EMPLOI_JOUEUR.md`, and `docs/officer/MODE_EMPLOI_GM_OFFICER.md`.
- [X] T019 Update the search/filter roadmap status and scope after implementation in `docs/PUBLIC-ROADMAP.md`.
- [X] T020 Increment the addon version to `0.8.7-dev` and add a dated unified-history-filtering note in `src/Core.lua`, `src/RCLootCouncil_dibs.toc`, and `CHANGELOG.md`.
- [X] T021 Run the focused history, Player, Officer, RCLootCouncil reconciliation, load-order, and localization tests via `tests/run.lua`; run `git diff --check`.
- [ ] T022 Complete the Retail manual scenarios in `specs/022-unified-history-search/quickstart.md` and record any client/API limitations without claiming unavailable metadata was verified.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Register the shared UI helper in the TOC; no code depends on it until Phase 2.
- **Foundational (Phase 2)**: T002–T004 establish matching and localization; Player and Officer stories depend on these semantics.
- **User Story 1 (Phase 3)**: Depends on Phase 2; independently delivers personal search.
- **User Story 2 (Phase 4)**: Depends on Phase 2; can proceed independently of US1 once shared semantics are stable.
- **User Story 3 (Phase 5)**: Depends on US1 and US2 because it adds cross-surface states and pagination behavior.
- **Polish (Phase 6)**: Depends on all desired stories.

### User Story Dependencies

- **US1 (P1)**: Depends on foundational filters; no dependency on Officer implementation.
- **US2 (P1)**: Depends on foundational filters; no dependency on Player implementation.
- **US3 (P2)**: Depends on US1 and US2 to make empty, unavailable, invalid, and paging behavior consistent.

### Parallel Opportunities

- T002 and T004 can proceed independently after T001; T003 follows the tests in T002.
- US1 tests in T005 precede the Player UI tasks T006/T007.
- After shared semantics are stable, US1 and US2 may be implemented in parallel by separate contributors, but both edit shared test/localization surfaces, so coordinate those files.
- US2 tests in T008 precede the Officer/RCLootCouncil implementation tasks T009–T013.
- US3 tests in T014 precede T015–T017; the Player and Officer state tasks T015 [P] and T016 [P] edit separate files.

## Implementation Strategy

1. Deliver US1 as the first user-visible increment, preserving personal-only scope.
2. Add Officer coverage source by source without replacing existing authorization or RCLootCouncil preview flows.
3. Finish with consistent result/error states and bounded ordering/pagination across the covered pages.
4. Validate automated tests first, then perform Retail manual checks where the client exposes the relevant saved history metadata.
