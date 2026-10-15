# Tasks: Development Catch-up

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts](contracts/corrective-behavior.md).
This is an explicitly retrospective task inventory; completion reflects verified
existing behavior, not a claim that tasks preceded implementation.

## Phase 1: Setup

- [X] T001 Inventory recent changes and map FR-001 through FR-008 to source/test paths in `specs/024-development-catchup/contracts/corrective-behavior.md`.

## Phase 2: Foundation

- [X] T002 Document evidence ownership, unchanged accounting, privacy and manual validation boundaries in `specs/024-development-catchup/data-model.md` and `research.md`.

## Phase 3: US1 - Accurate rewards

Independent test: exact links survive; invalid claims create nothing.

- [X] T003 [US1] Verify passive claim/receipt completion and rejection cases in `src/integrations/GreatVault.lua` with `tests/integration/great_vault_retail_capability_spec.lua` (FR-001).
- [X] T004 [US1] Verify ID and full-link manual commands in `src/Core.lua` with `tests/unit/great_vault_acquisition_spec.lua` (FR-002).
- [X] T005 [US1] Verify transient unambiguous owned previews and recorded exact-link preservation in `src/ui/PlayerUI.lua` with `tests/integration/great_vault_ui_spec.lua` (FR-003).

## Phase 4: US2 - Shortcuts and delivery

Independent test: repeated toggle restores visibility; offline send is refused.

- [X] T006 [US2] Verify permissions, toggles and character-local visibility in `src/ui/MinimapButton.lua` with `tests/integration/minimap_button_spec.lua` (FR-004).
- [X] T007 [US2] Verify roster online identity and offline whisper rejection in `src/modules/Identity.lua`, `src/modules/SyncV2.lua`, `tests/unit/b04_transport_spec.lua` and `tests/integration/sync_status_spec.lua` (FR-005).

## Phase 5: US3 - Investigation

Independent test: reports are read-only and privacy-safe.

- [X] T008 [US3] Verify period statistics in `src/ui/OfficerUI.lua` with `tests/unit/officer_history_statistics_spec.lua` and `tests/integration/officer_period_statistics_ui_spec.lua` (FR-006).
- [X] T009 [US3] Verify anonymous audit export in `src/modules/AuditExport.lua` with `tests/contract/audit_export_contract_spec.lua` and `tests/integration/audit_export_ui_spec.lua` (FR-006).
- [X] T010 [US3] Preserve existing task/evidence ownership in `specs/022-unified-history-search/tasks.md` and `specs/023-data-health-review-center/tasks.md`; do not close their manual gates (FR-007).

## Phase 6: Validation and checkpoint

- [X] T011 Run full regression through `tests/run.lua`, inspect failures and record the exact result in `specs/024-development-catchup/quickstart.md`.
- [ ] T012 Verify documentation links, no private data and `git diff --check`; commit the development checkpoint and push `dev` before ticket source changes; record the commit in `specs/024-development-catchup/quickstart.md`.
- [ ] T013 Perform outstanding Retail scenarios in `specs/024-development-catchup/quickstart.md` and original feature 013 T051/T052 plus 022 T022 (manual; cannot be certified by Fengari).

## Dependencies and execution

T001 precedes T002. T003-T010 depend on T002; the three story groups can be
verified independently, with tests combined into one runner. T011 follows all
story verification; T012 follows T011; T013 requires actual Retail clients and
is not a prerequisite for an explicitly non-certified development checkpoint.

## Implementation strategy

Preserve existing behavior, record exact automated evidence, retain manual
gates, save/push the baseline, then begin the separate ticket extension.
