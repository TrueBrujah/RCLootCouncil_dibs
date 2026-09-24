# Tasks: Guild Sync Reliability

**Input**: Design documents from `specs/017-guild-sync-reliability/` (plan.md, research.md, data-model.md, contracts/sync-messages.md, quickstart.md)

**Tests**: Included — this repository's established convention requires focused Fengari tests for every behavioral change before deploy/commit (see repo memory and prior specs).

## Phase 1: Setup

- [X] T001 Confirm `tests/helpers/distributed_ledger_fixture.lua` supports partition/heal and offline/reconnect scenarios needed by later phases (read-only check, no code change expected).

## Phase 2: Foundational (blocking prerequisites)

- [X] T002 Add `AWARD_PROPOSAL` and `SEASON_CATALOG` to the accepted `entityType` allowlists for `DETAIL_FETCH`/`TRANSFER_*` in `src/modules/SyncV2.lua`.
- [X] T003 Add a bounded local delivery-retry primitive reusable by both new entities (module-level helper in `src/modules/SyncV2.lua`, following the existing `Sync.recoveryRetry`/heartbeat pattern), without weakening existing message-size/replay bounds.

**Checkpoint**: SyncV2 accepts the new entity types (rejects gracefully if payload shape is wrong) but nothing produces them yet — safe to merge/test in isolation.

## Phase 3: User Story 1 — Award proposals reach the ledger authority across raids (Priority: P1) 🎯 MVP

**Goal**: A non-coordinator officer's finalized award reaches the current coordinator exactly once, is confirmable, and results in a consistent balance everywhere.

**Independent Test**: `tests/integration/award_proposal_relay_spec.lua` — non-coordinator finalizes an award, coordinator receives/commits it, balance matches across coordinator/submitter/player views; duplicate submission and partition/reconnect do not duplicate the ledger effect.

- [X] T004 [US1] Extend `Governance.RecordAwardProposal` in `src/modules/Governance.lua` to resolve the current coordinator from local authority state and enqueue a relay attempt (status `RELAY_PENDING`), without changing its existing zero-ledger-effect local behavior when no coordinator is known.
- [X] T005 [US1] Implement `Sync.SendAwardProposal(proposal, target)` in `src/modules/SyncV2.lua` using `TRANSFER_BEGIN/CHUNK/END` with `entityType = "AWARD_PROPOSAL"` per contracts/sync-messages.md, WHISPER-only, and an `AWARD_PROPOSAL_ACK` reply message.
- [X] T006 [US1] Implement the coordinator-side receiver in `src/modules/SyncV2.lua`: verify the receiver is the current coordinator, dedupe by `proposalId`, store into a bounded pending-proposals queue, and send the ack.
- [X] T007 [US1] Implement submitter-side ack handling updating local `AwardProposal.status` (`RELAY_PENDING` → `RELAY_ACKED`) and a bounded retry loop (reuse T003 helper) that stops retrying once acked or once `relayAttempts` cap is hit, surfacing a diagnostic under the `sync` scope when the cap is hit.
- [X] T008 [US1] Add `Dibs.Governance.GetPendingCoordinatorProposals()` and wire an Officer UI "Pending awards to confirm" list/action in `src/ui/OfficerUI.lua` that calls the existing `Ledger.CommitAwardProposal` on confirmation.
- [X] T009 [US1] Add `tests/integration/award_proposal_relay_spec.lua` covering: normal relay+commit convergence, duplicate submission idempotency, and partition/heal delivery (using `distributed_ledger_fixture.lua`).
- [X] T010 [US1] Run the focused test file and fix regressions before proceeding.

**Checkpoint**: User Story 1 independently functional and tested — this is the MVP slice.

## Phase 4: User Story 2 — Season catalog propagation (Priority: P2)

**Goal**: Season create/rename/activate/archive by the GM reaches every other client automatically, including catch-up after reconnect.

**Independent Test**: `tests/integration/season_catalog_sync_spec.lua` — GM mutates seasons, officer client (online and previously-offline) converges without local recreation.

- [X] T011 [US2] Add revisioned catalog state (`db.seasonCatalog`: `policyRevision`, `parentHash`, `contentHash`, `authorMemberKey`, `currentSeasonId`, `seasons` map) and bump/hash logic to `src/modules/Seasons.lua`, following data-model.md.
- [X] T012 [US2] Implement `Sync.BuildSeasonCatalogDigest()` / `Sync.AnnounceSeasonCatalog()` and the `SEASON_CATALOG` DIGEST/DETAIL_FETCH/TRANSFER handling in `src/modules/SyncV2.lua`, reusing `OperationalPolicy.writerAuthorized`-equivalent authorization for seasons.
- [X] T013 [US2] Implement `Dibs.Seasons.ApplyCatalog(record, sender)` merge logic in `src/modules/Seasons.lua` per data-model.md (keyed union, never delete, conditional `currentSeasonId` update).
- [X] T014 [US2] Call `Dibs.Sync.AnnounceSeasonCatalog()` after successful `season.create`/`season.rename`/`season.archive`/`season.set` in `src/modules/ProtectedActions.lua`.
- [X] T015 [US2] Include the `SEASON_CATALOG` digest in `Sync.OnLifecycle` in `src/modules/SyncV2.lua` so reconnecting/late clients catch up automatically.
- [X] T016 [US2] Add `tests/unit/season_catalog_spec.lua` (merge/authorization/hash-chain unit behavior) and `tests/integration/season_catalog_sync_spec.lua` (multi-client convergence + offline catch-up, using `distributed_ledger_fixture.lua`).
- [X] T017 [US2] Run the focused test files and fix regressions before proceeding.

**Checkpoint**: User Stories 1 and 2 both independently functional and tested.

## Phase 5: User Story 3 — Visible synchronization status (Priority: P3)

**Goal**: Officers/GM can tell, without guessing, when guild-wide policy isn't active or a peer's protocol/version is incompatible.

**Independent Test**: Unadopted-policy and protocol-major-mismatch scenarios both surface a distinguishable status rather than a silent no-op.

- [X] T018 [US3] Record the most recent `UNSUPPORTED_PROTOCOL_MAJOR` rejection (sender, local/remote major, timestamp) under the existing `sync` diagnostic scope in `src/modules/SyncV2.lua`, bounded to a small recent-history list.
- [X] T019 [US3] Add a `SynchronizationStatus` projection helper (per data-model.md) combining governance/policy-adoption/season-revision/pending-proposal/protocol-mismatch state, exposed via `Dibs.Governance`/`Dibs.OperationalPolicy`/`Dibs.SyncV2` read-only accessors.
- [X] T020 [US3] Surface an always-visible banner in `src/ui/OfficerUI.lua` (Guild Rules / Pre-Dibs and Modules pages) when `OperationalPolicy.IsAdopted() == false`, and extend `Dibs.BuildDebugReport` in `src/Core.lua` with governance/policy/season-catalog/protocol-mismatch status lines.
- [X] T021 [US3] Add focused unit assertions for the status projection and debug report lines (extend existing `operational_policy_spec.lua`/`module_management_spec.lua` or add a small new spec as needed).
- [X] T022 [US3] Run the focused test files and fix regressions before proceeding.

**Checkpoint**: All three user stories independently functional and tested.

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T023 Add/update English and French locale strings for any new user-facing labels (pending-proposal list, policy-not-active banner, version-mismatch status) in `src/locales/enUS.lua` and `src/locales/frFR.lua`.
- [X] T024 Run the full Fengari suite (`tests/run.lua` over every `*_spec.lua`) and `get_errors` diagnostics across all touched files; fix any regressions.
- [X] T025 Update `specs/017-guild-sync-reliability/checklists/requirements.md` notes if scope changed, and deploy via `scripts/deploy.ps1` for local Retail smoke testing.
- [ ] T026 Perform one-guild, two-raid-group Retail validation session (manual, requires real WoW clients) confirming award-proposal relay, season propagation, and status banners; record evidence before marking this task complete.

## Dependencies

- Phase 2 (Foundational) blocks all user story phases (Phases 3–5).
- Phase 3 (US1), Phase 4 (US2), and Phase 5 (US3) are independent of each other and may be implemented/tested in any order once Phase 2 is done; priority order (P1 → P2 → P3) is recommended for incremental delivery.
- Phase 6 (Polish) depends on all selected user-story phases being complete.

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (User Story 1)** — closes the highest-risk gap (award evidence loss across simultaneous raids) and is independently testable/shippable on its own. User Stories 2 and 3 add visible reliability improvements but do not block MVP delivery.
