# Tasks: UI Rendering and Data Read Performance

**Input:** `specs/028-ui-performance/spec.md`
**Prerequisites:** `plan.md`, `research.md`, `data-model.md`, `quickstart.md`
**Tests:** Required for all behavior changes; add a regression test before the corresponding optimization.

## Phase 1 — Officer visible balances (US1, P1)

- [X] T001 Add a regression test that the grouped player history summary resolves one ledger and returns the same balances: `tests/integration/officer_dibs_admin_roster_fallback_spec.lua`.
- [X] T002 Add `Ledger.GetPlayerHistorySummaries` while sharing the existing per-player summary cache and calculation: `src/modules/Ledger.lua`.
- [X] T003 Use grouped reads for visible Dibs Administration balances and full-list balance sorting, preserving fallback behavior: `src/ui/OfficerUI.lua`.
- [X] T004 Update the visible-row/sort regression to assert one grouped lookup and the same row bounds: `tests/integration/automatic_dibs_log_spec.lua`.
- [X] T005 Rerun the focused test slices. The batch-balance assertion passed; validation also exposed a duplicate-roster assertion (`expected 2, got 1`) and a dashboard viewed-ledger assertion (`expected selected ledger, got nil`). Their relationship to pre-existing worktree changes is not established.
- [ ] T006 Capture a same-character in-game report and compare `Officer data / dibs-admin-visible-balances` before/after; confirm the displayed balances, name/rank sort, balance sort, and pagination.

## Phase 2 — Guided Setup (US2, P1)

- [X] T007 Add the active-ledger-resolution timing and regression coverage for the repeated installation status lookup: `src/modules/Installation.lua`, `tests/integration/installation_wizard_spec.lua`.
- [X] T008 Resolve the active ledger once for both legacy-history checks without caching their result: `src/modules/Installation.lua`.
- [X] T009 Run the focused Installation, Ledger, Sync, and Officer regression slices; record the dashboard viewed-ledger failure without attributing it to this change.
- [ ] T010 Inspect remaining SetupAssistant, readiness, and rank-summary costs and identify exact repeatable work before adding any cache.
- [ ] T011 Add failing tests for any proposed reuse and its policy/season/roster/sync invalidation paths.
- [ ] T012 Implement only a proven reuse/removal; preserve refresh semantics and status detail.
- [ ] T013 Compare cold and warm Wizard timings in game; abandon a cache if invalidation cannot be proven or the result is not measurably faster.

## Phase 3 — RCLootCouncil integration (US3, P2)

- [ ] T014 Trace `AceConfig / RCLootCouncil` from OfficerUI to the adapter/provider and identify which time is Dibs-owned: `src/ui/OfficerUI.lua`, `src/integrations/RCLootCouncilOptions.lua`.
- [ ] T015 Add a test that revisiting the Dibs integration page preserves RC response options and does not duplicate hooks or registrations.
- [ ] T016 If redundant Dibs-owned work is confirmed, remove only that duplicate work; leave RC and embedded library sources untouched.
- [ ] T017 Run RC adapter, options, hook-retry, and standalone-without-RC tests; classify any remaining framework/provider cost as external.
- [ ] T018 Compare first-open/reopen in-game counters with RC enabled and disabled under otherwise identical conditions.

## Phase 4 — PlayerUI and Sync follow-up (US4, P2)

- [ ] T019 Use the latest Player/Sync report to identify the next single repeated scan, copy, or render cost; do not pool widgets or add a broad cache without evidence.
- [ ] T020 Add regression tests for data equality, visibility, sorting, and revision invalidation before changing the selected path.
- [ ] T021 Implement the smallest bounded optimization and preserve the existing page model and protocol hashes.
- [ ] T022 Run the PlayerUI and Sync regression slices, including multi-member and authority/handoff coverage where applicable.
- [ ] T023 Compare before/after page and digest timings; report FPS and heap changes separately, with measurement limits.

## Phase 5 — Acceptance and release readiness

- [ ] T024 Review the changed paths against the spec and current Constitution, including whether a dated changelog entry and TOC version increment are required before accepting the addon behavior change.
- [ ] T025 Run `git diff --check` on feature-owned changes and preserve unrelated dirty files and known test failures.
- [ ] T026 Record automated results and user in-game results separately; do not claim a fixed FPS, memory ceiling, or overall optimization without adequate Retail evidence.

## Dependency order

Complete T006 before treating US1 as measured. Guided Setup, RC
integration, and Player/Sync proceed sequentially because they share profiling
and UI code. T023–T025 are the final acceptance gate. No commit or deployment
is part of this task list.
