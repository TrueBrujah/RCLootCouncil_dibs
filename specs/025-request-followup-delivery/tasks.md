# Tasks: Request follow-up and private delivery

## Phase 1 — Setup
- [x] T001 Create approved spec and design artifacts in specs/025-request-followup-delivery/.

## Phase 2 — Foundation
- [x] T002 Preserve bounded complete dossiers/audit and migrate additively in src/modules/Disputes.lua.

## Phase 3 — US1: Private persisted delivery
Independent test: isolated clients, retries/reload, actual sender and privacy contracts.
- [x] T003 [US1] Add capability/private detail routing and lifecycle pump in src/modules/SyncV2.lua.
- [x] T004 [US1] Implement durable scoped delivery/ACK and coordinator-fenced acceptance in src/modules/RequestDelivery.lua.
- [x] T005 [US1] Wire local report/reply hooks in src/modules/Disputes.lua and loader/TOC.
- [x] T006 [US1] Test simulated offline/replay/reload/privacy in tests/integration/request_delivery_spec.lua.

## Phase 4 — US2: Follow-up
Independent test: assignment/reply/due filters and persisted reminder throttling.
- [x] T007 [US2] Implement assignment/public reply/follow-up/filter services in src/modules/Disputes.lua.
- [x] T008 [US2] Implement online reminders and snooze in src/modules/RequestDelivery.lua and Notifications.lua.
- [x] T009 [US2] Extend existing detail/queue presentation in src/ui/PlayerUI.lua and OfficerUI.lua with EN/FR locales.
- [x] T010 [US2] Test existing UI and follow-up interactions in tests/integration/request_followup_spec.lua.

## Phase 5 — US3: Retained lifecycle and corrections
Independent test: close/archive/search retain evidence and links; replicas cannot compensate.
- [x] T011 [US3] Add reasoned Closed/Archived transitions and safe reopen in src/modules/Disputes.lua.
- [x] T012 [US3] Test retention/capacity and competing corrections in tests/integration/request_followup_spec.lua.

## Phase 6 — Polish
- [x] T013 Update docs/player/, docs/officer/, docs/developer/sync-protocol.md and saved-variables.md.
- [x] T014 Update src/Core.lua, src/RCLootCouncil_dibs.toc, README.md and CHANGELOG.md to 0.8.8-dev consistently.
- [x] T015 Run focused regression slices, diagnostics, diff checks; record evidence in specs/025-request-followup-delivery/tasks.md.
- [ ] T016 Certify real-client delivery, coordinator changes and EN/FR narrow/wide/combat UI using specs/025-request-followup-delivery/quickstart.md (MANUAL RETAIL).

## Dependencies and execution
T001 -> T002; T003/T004 -> T005 -> T006; T002 -> T007/T011;
T004/T007 -> T008 -> T009 -> T010; T011 -> T012; all automated slices -> T015.
T013 and T014 may be independently prepared after contracts stabilize.
No nested delegation. Incremental MVP is private own-player delivery; subsequent
stories retain existing guided accounting and improve the same request center.

## Evidence / remaining gates
2026-10-15: final combined focused gate **149 passed, 0 failed (21 files)**:

- 28 new feature tests across `request_delivery_spec.lua` (15) and
  `request_followup_spec.lua` (13), including persisted reminder burst/fairness
  and aggregate pending/error receipt-state regressions.
- Existing request regression/privacy/accounting/UI suites:
  `dispute_center_spec.lua`, `b12_requests_support_ticket_spec.lua`,
  `b12_requests_primary_actions_spec.lua`, `b12_requests_context_menu_spec.lua`,
  `dispute_authority_privacy_spec.lua`, `b12_request_disclosure_spec.lua`,
  `b12_requests_actions_spec.lua`, `b12_advanced_request_actions_spec.lua`.
- Shared `b04_transport_spec.lua`, `sync_status_spec.lua`,
  `predibs_sync_recovery_spec.lua`, `great_vault_sync_recovery_spec.lua`,
  `great_vault_sync_privacy_spec.lua`, `sync_privacy_spec.lua`,
  `great_vault_sync_contract_spec.lua`, `persistence_recovery_spec.lua`,
  `notifications_wiring_spec.lua`, `notifications_contract_spec.lua`,
  `toc_load_spec.lua`.

Runner: root PowerShell; explicit semicolon-separated `DIBS_TEST_FILES`, restored
in `finally`; `npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua`.
Synthetic output retained in the session `files/025-request-validation.txt`.
`git diff --check` passed. Workspace diagnostics found no issues in RequestDelivery,
SyncV2, PlayerUI or Core; existing `@doc.*` annotation warnings in Disputes and
pre-existing annotation/type-model warnings in OfficerUI remain unrelated.

**Open**: T016 is manual Retail certification, not a Fengari success claim.
Safe defaults/limitations: coordinator-only shared writes; no automated old-epoch
handoff; owner plus 16 online capable officer replicas; oversize/capacity errors
retain source and pending work. Modified legacy-local dossiers cannot be shared
as fresh requests. No real offline-client execution, external service, physical
item transfer, new accounting policy, publication or deployment is implemented.

## Phase 7: Convergence

- [x] T017 Add a persisted three-reminder/minute global budget with fair request rotation in src/modules/RequestDelivery.lua and verify reload/burst behavior in tests/integration/request_followup_spec.lua per FR-005 (partial).

Convergence identified a per-request-only reminder throttle; the new regression
first failed (four notifications rather than three), then passed with a persisted
batch budget and rotating cursor. Empty queues return before clock/state work,
preserving existing lifecycle coalescing. The final 149-test gate covers all
source changes. T016 remains deliberately unchecked.
