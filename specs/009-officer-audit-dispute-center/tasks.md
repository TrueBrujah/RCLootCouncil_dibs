---

description: "Task list for the Officer Audit and Dispute Center"

---

# Tasks: Officer Audit and Dispute Center

**Input**: Design documents from `/specs/009-officer-audit-dispute-center/`

**Status**: Implemented on `dev` in version 0.3.7-dev.

## Phase 1: Setup

- [x] T001 [P] Define request categories, statuses, bounded text, duplicate keys, and evidence confidence in `src/modules/Disputes.lua`.
- [x] T002 [P] Add player/Officer/replay/privacy fixtures in `tests/helpers/dispute_fixtures.lua`.
- [x] T003 [P] Add localized labels, explanations, and migration/changelog notes in `src/locales/enUS.lua`, `src/locales/frFR.lua`, and `CHANGELOG.md`.

## Phase 2: Foundational

- [x] T004 Implement guild/player scope isolation and request persistence in `src/modules/Disputes.lua` and `src/Core.lua`.
- [x] T005 Implement evidence-link normalization for Dibs and optional RCLootCouncil sources in `src/integrations/RCLootCouncil.lua` and `src/modules/Disputes.lua`.
- [x] T006 Define append-only request timeline and idempotent status/correction keys in `src/modules/Disputes.lua`.
- [x] T007 Route balance corrections through protected actions and linked compensating transactions in `src/modules/ProtectedActions.lua` and `src/modules/Ledger.lua`.

## Phase 3: US1 - Submit a player report (P1)

- [x] T008 [P] [US1] Add own-context, category, bounded-note, duplicate, and no-mutation tests in `tests/integration/dispute_center_spec.lua`.
- [x] T009 [US1] Add **Report a problem** action and prefilled player form in `src/ui/PlayerUI.lua`.
- [x] T010 [US1] Implement request creation, duplicate detection, and safe player request view in `src/modules/Disputes.lua` and `src/ui/PlayerUI.lua`.
- [x] T011 [US1] Implement bounded player reply without evidence editing in `src/modules/Disputes.lua`.

## Phase 4: US2 - Review requests in one Officer queue (P1)

- [x] T012 [P] [US2] Add queue ordering, filter, evidence, and privacy tests in `tests/contract/dispute_authority_privacy_spec.lua`.
- [x] T013 [US2] Implement Officer-only queue/search/paging and status cards in `src/ui/OfficerUI.lua`.
- [x] T014 [US2] Render complete evidence, unavailable fields, and related transaction/award references in `src/ui/OfficerUI.lua`.
- [x] T015 [US2] Enforce GM/Officer access at every queue/read endpoint in `src/modules/Permissions.lua` and `src/modules/Disputes.lua`.

## Phase 5: US3 - Resolve common cases (P1)

- [x] T016 [P] [US3] Add no-correction, information, duplicate, correction, replay, and concurrency tests in `tests/integration/dispute_center_spec.lua`.
- [x] T017 [US3] Implement primary resolution actions with explicit reason/confirmation in `src/modules/Disputes.lua` and `src/ui/OfficerUI.lua`.
- [x] T018 [US3] Implement advanced refund/revoke/import/adjustment routing with effect explanations in `src/ui/OfficerUI.lua` and `src/modules/ProtectedActions.lua`.
- [x] T019 [US3] Create linked append-only compensating transactions and prevent duplicate corrections in `src/modules/Ledger.lua`.
- [x] T020 [US3] Persist every request, reply, evidence link, status, resolution, and correction audit event in `src/modules/Disputes.lua`.

## Phase 6: US4/US5 - Player transparency and audit (P1)

- [x] T021 [P] [US4] Add player-safe status/reason/privacy tests in `tests/integration/dispute_center_spec.lua`.
- [x] T022 [US4] Render own requests, questions, replies, and resolution explanations without Officer notes in `src/ui/PlayerUI.lua`.
- [x] T023 [P] [US5] Add append-only timeline, reload, guild-change, and retention tests in `tests/contract/dispute_authority_privacy_spec.lua`.
- [x] T024 [US5] Add audit timeline and export-safe scope in `src/ui/OfficerUI.lua` and `src/modules/Disputes.lua`.
- [x] T025 [US5] Keep standalone/degraded RCLootCouncil evidence clearly separated from unavailable data in `src/integrations/RCLootCouncil.lua`.

## Phase 7: Polish and release

- [x] T026 [P] Update `docs/ARCHITECTURE.md`, `docs/RC_OPTIONS.md`, `README.md`, and `CHANGELOG.md`.
- [x] T027 [P] Run full suite, privacy/replay/combat checks, and Retail validation in `specs/009-officer-audit-dispute-center/quickstart.md`.
- [x] T028 Review the implementation against `spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md` before versioning.

## Dependencies

Phase 2 blocks all stories. US1 creates safe requests, US2 exposes evidence to Officers,
US3 adds protected resolutions, and US4/US5 complete player transparency and audit. Tests
precede each implementation slice.
