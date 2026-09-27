---
description: "Dependency-ordered implementation tasks for guild-authoritative Loot Rules"
---

# Tasks: Guild-Authoritative Loot Rules

**Input**: Design documents from `specs/018-guild-authoritative-loot-rules/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/season-catalog-guild-loot-rules.md`, `quickstart.md`

**Tests**: Required by the feature specification and implementation plan. Test tasks precede each story's implementation.

**Organization**: Tasks are grouped by the four user stories and preserve existing unrelated worktree changes. Do not modify Rank Rules business behavior.

## Phase 1: Setup

**Purpose**: Establish the released compatibility boundary and source module integration.

- [X] T001 Update addon version to 0.8.0 in `src/RCLootCouncil_dibs.toc` and `src/Core.lua`, and add the dated compatibility/migration note to `CHANGELOG.md`.

## Phase 2: Foundational Work

**Purpose**: Define the snapshot domain and catalog contract required by all stories.

- [X] T002 [P] Add unit contract tests for complete dynamic-key normalization, schema version, booleans, unsupported keys, and missing-option-source behavior in `tests/unit/guild_loot_rules_spec.lua`.
- [X] T003 Implement `Dibs.LootRules` draft, normalization, authority lookup, effective-value, and status APIs in `src/modules/LootRules.lua`, then register it in `src/RCLootCouncil_dibs.toc`.
- [X] T004 Extend `src/modules/Seasons.lua` to validate and carry forward schema-v1 `guildConfiguration.guildLootRules` without changing the catalog entity or content-hash envelope; expose a preflightable publication seam for `Dibs.LootRules`.
- [X] T005 Add catalog contract tests for nested validation-before-mutation, complete snapshot transfer, hash coverage, and active-authority carry-forward in `tests/integration/season_catalog_sync_spec.lua`.

**Checkpoint**: Normalization and catalog record boundaries pass independently before any UI or consumer changes.

## Phase 3: User Story 1 - Adopt and Publish Guild Loot Rules (Priority: P1)

**Goal**: GM reviews local values, explicitly adopts once, and publishes later revisions without confusing drafts with effective guild behavior.

**Independent Test**: Run the US1 domain/UI tests with an unadopted catalog, then with an adopted catalog; verify GM authorization, revision/audit data, draft isolation, and truthful failure outcomes.

### Tests for User Story 1

- [X] T006 [P] [US1] Add independent adoption/publication tests in `tests/integration/guild_loot_rules_spec.lua`: LRA01-LRA07 cover explicit adoption, authorization, draft isolation, audit metadata, transport failure, and rollback.

### Implementation for User Story 1

- [X] T007 [US1] Implement GM-only first adoption and later publication, complete dynamic snapshot building, change summary, and transport/authority preflight in `src/modules/LootRules.lua` and `src/modules/Seasons.lua`.
- [X] T008 [US1] Replace the Loot Rules route controls with preview, explicit Adopt/Publish actions, draft-versus-authority comparison, and distinct publication failure/success states in `src/ui/OfficerUI.lua`.
- [X] T009 [P] [US1] Add English and French labels, explanations, help text, and publication outcomes for adoption and publishing in `src/locales/enUS.lua` and `src/locales/frFR.lua`.

**Checkpoint**: GM can explicitly adopt and publish; no control opening or draft edit silently changes authority.

## Phase 4: User Story 2 - Consume the Same Effective Rules (Priority: P1)

**Goal**: Adventure Guide and RCLootCouncil consume one adopted snapshot; Officers see managed rules without editing controls.

**Independent Test**: Apply a published catalog to a second client with conflicting local maps and verify identical decisions, read-only Officer presentation, and safe DIBS projection refresh.

### Tests for User Story 2

- [X] T010 [P] [US2] Add two-client consumer tests in `tests/integration/guild_loot_rules_spec.lua` and `tests/integration/guild_loot_rules_ui_spec.lua`: LRA08-LRA11 cover all-key parity, read-only Officer UI, shared consumer getters, projection refresh, and unrelated RC SavedVariables preservation.

### Implementation for User Story 2

- [X] T011 [US2] Route `IsDibEnabledForType` and `IsRCButtonEnabledForType` through `Dibs.LootRules` effective values and refresh the DIBS-owned projection after a validated catalog apply in `src/integrations/RCLootCouncil.lua` and `src/modules/Seasons.lua`.
- [X] T012 [US2] Make dynamic Loot Rules option callbacks update GM-local draft only, and render adopted authority read-only to Officers in `src/integrations/RCLootCouncilOptions.lua` and `src/ui/OfficerUI.lua`.
- [X] T013 [P] [US2] Add localized managed/read-only labels, draft comparison text, and RCLootCouncil-unavailable wording in `src/locales/enUS.lua` and `src/locales/frFR.lua`.

**Checkpoint**: Both consumers use the same effective resolver; no Officer editing route bypasses explicit publication.

## Phase 5: User Story 3 - Migrate Existing Local Rules Safely (Priority: P1)

**Goal**: Preserve every client's legacy maps, avoid Officer auto-adoption, and prevent stale or malformed records from replacing authority.

**Independent Test**: Apply legacy, current, replayed, and invalid catalogs to clients with conflicting local maps and verify no destructive migration or authority downgrade.

### Tests for User Story 3

- [X] T014 [P] [US3] Add migration/recovery tests in `tests/integration/guild_loot_rules_spec.lua` and `tests/integration/season_catalog_sync_spec.lua`: LRA12-LRA19 cover local preservation, complete transfer, invalid schema/hash, carry-forward, replay, downgrade, and missing-parent rejection; unit tests cover malformed keys and unavailable options.

### Implementation for User Story 3

- [X] T015 [US3] Remove `dibAllowedTypes` and `dibRCEnabledTypes` from automatic catalog export/application while preserving their local values, and reject authority downgrade or invalid snapshot records in `src/modules/Seasons.lua` and `src/modules/LootRules.lua`.
- [X] T016 [US3] Add guild-isolation and reconnect/recovery regression coverage for Loot Rules records in `tests/integration/season_catalog_sync_spec.lua` without changing Rank Rules semantics.

**Checkpoint**: Migration is idempotent and preserves local data; after adoption no local fallback can override authority.

## Phase 6: User Story 4 - See Readiness and Compatibility Honestly (Priority: P2)

**Goal**: GMs and Officers can distinguish ready, local-only, missing, behind, incompatible, and unavailable rules.

**Independent Test**: Drive each readiness state through the same public projection used by the UI, including an old-version peer and a catalog update during a raid.

### Tests for User Story 4

- [X] T017 [P] [US4] Add readiness and compatibility tests in `tests/integration/guild_loot_rules_spec.lua` and `tests/integration/sync_status_spec.lua`: LRA20 all six statuses; LRA21 0.7.x peer rejection with update-required state; LRA22 raid-time update applies only after validation while sync lag remains visible and local rules never take over.

### Implementation for User Story 4

- [X] T018 [US4] Add Loot Rules authority, peer lag, and compatibility projection to `src/modules/Readiness.lua` and surface its localized result through existing Setup Assistant probe rendering without changing Rank Rules findings.
- [X] T019 [US4] Verify incompatible peers cannot author/apply schema-v1 rules and map existing SyncV2 version/parent recovery statuses to Loot Rules readiness.
- [X] T020 [P] [US4] Add localized remediation for every Loot Rules readiness state in `src/locales/enUS.lua` and `src/locales/frFR.lua`.

**Checkpoint**: All six outcomes remain distinct, and readiness never equates local option availability with guild authority.

## Phase 7: Polish and Cross-Cutting Validation

**Purpose**: Complete user/developer documentation and establish an auditable release decision.

- [X] T021 [P] Update English/French Player and GM/Officer guides, version-bearing current developer protocol docs, and document the absence of new Retail screenshot evidence in the feature audit.
- [X] T022 Regenerate and validate source-driven guides/reference data with `scripts/Generate-DibsDocs.ps1 -Generate`, `-Validate`, and `-Check`; update `README.md` and active version-bearing docs to identify 0.8.0 as the current compatibility family after 0.6.5.
- [X] T023 [P] Update `docs/audits/Guild_Wide_Loot_Rules_Implementation.md` with actual schema, code paths, test evidence, compatibility/migration impact, and explicit final readiness outcome.
- [X] T024 Run focused feature tests and the full Fengari suite from `specs/018-guild-authoritative-loot-rules/quickstart.md`; report known unrelated baseline failures separately and do not alter Rank Rules behavior. Focused: 82 passed, 0 failed (8 files). Full: 745 passed, 1 confirmed pre-existing Pre-Dib heartbeat failure (144 files).
- [ ] T025 Complete narrow/wide UI and two-client Retail validation and set the release outcome in the implementation audit. Automated coverage confirms unrelated RC SavedVariables are unchanged; real Retail validation and screenshots are unavailable in this environment, so the audit records `NOT READY`.

## Dependencies and Execution Order

### Phase Dependencies

- Setup (Phase 1) precedes foundational work because the version boundary must be consistent before payload changes are exercised.
- Foundational work (Phase 2) blocks all stories: the normalizer, domain service, and catalog snapshot contract must exist first.
- US1 is first because it creates the authority transition and publication workflow.
- US2 consumes the authority and drafts established by US1.
- US3 hardens migration and recovery against existing legacy catalog data; it depends on the schema and consumers from US1/US2.
- US4 reports the resulting authority and SyncV2 states; it depends on the domain and migration model.
- Polish is final; real Retail validation may remain an explicit release gate if the environment lacks two clients.

### User Story Dependencies

- US1: after Phase 2; independently testable with an unadopted catalog.
- US2: after Phase 2 and US1 APIs; tests can use a constructed valid authority record.
- US3: after Phase 2; end-to-end assertions exercise the US1/US2 effective resolver.
- US4: after Phase 2; full integration follows US1-US3 so readiness reflects final behavior.

### Parallel Opportunities

- T002 can be written alongside version setup T001; it must pass after T003.
- US1 localization T009 can proceed alongside domain/UI implementation once strings and state names are fixed.
- US2 consumer tests T010 can be authored before adapter edits T011-T012; locale task T013 is independent.
- US3 test suite T014 can be authored in parallel with documentation scoping; T015 and T016 must preserve those tests.
- US4 tests T017 and locale T020 can proceed independently after the status contract is fixed.
- Final docs/audit edits T021 and T023 can proceed in parallel with final code review, but generation/validation T022 follows source annotations and version updates.

## Parallel Example: User Story 1

```text
Task: T006 Write adoption/publication tests in tests/integration/guild_loot_rules_spec.lua
Task: T009 Add English/French publication strings in src/locales/enUS.lua and src/locales/frFR.lua
```

## Implementation Strategy

### MVP First

1. Complete setup and foundational tasks.
2. Complete US1, then run its focused tests before moving on.
3. Add US2 so both consumers follow the authority.
4. Add US3 migration/replay guarantees, then US4 readiness and compatibility.
5. Finish docs and run focused, full-suite, and available Retail checks.

### Incremental Delivery

Each story retains an independent test criterion. Do not declare the feature ready before all 22 `LRA` cases, the documentation validator, the full suite, and the applicable two-client review are accounted for.

## Test-Area Index

The integration/UI tests contain 22 independently named scenarios: LRA01 adoption; LRA02 Officer denial; LRA03 draft isolation; LRA04 publication audit; LRA05 transport preflight; LRA06 non-GM publication denial; LRA07 rollback/projection; LRA08 dynamic-key parity and saved-data preservation; LRA09 GM preview; LRA10 explicit UI publication; LRA11 Officer read-only view; LRA12 legacy preservation; LRA13 complete snapshot transfer; LRA14 schema validation; LRA15 hash coverage; LRA16 authority carry-forward; LRA17 replay; LRA18 downgrade rejection; LRA19 missing-parent rejection; LRA20 six readiness states; LRA21 0.6.x compatibility rejection; and LRA22 raid-time application with lag visibility.
