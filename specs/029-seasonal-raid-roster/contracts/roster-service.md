# Seasonal Roster Service Contract

This addon-local contract describes observable service behavior, not a REST API.

## Common rules

- Every call is scoped to the active guild and canonical `seasonId`.
- Mutations require the expected current revision; stale calls return a conflict and do not mutate.
- GM/Officer writes require current verified guild authority at the mutation boundary.
- Player enrollment writes are bound to the authenticated character/person identity.
- All operations check module state. Disabled blocks writes and incoming mutations while preserving stored history.
- Persisted authoritative decisions emit audit events. Replayed operation IDs are idempotent.
- Never expose private officer notes or ledger details through the public roster projection.

## Lifecycle operations

- `CreateDraft(actor, input)` → season identity and initial revision. Does not change active ledger.
- `UpdateDraft(actor, seasonId, expectedRevision, patch)` → revised draft or validation/conflict.
- `PublishSeasonConfig(actor, seasonId, expectedRevision, rules/status/promotion/allocation)` → immutable revision references.
- `OpenRegistration(actor, seasonId, expectedRevision)` and `CloseRegistration(...)` → validated lifecycle transition. Closing registration does not complete or archive.
- `PreviewActivation(actor, seasonId)` → blockers, referenced revisions, approved participants, rank/no-rank allocation summary, identity conflicts, historical balance-merge status; no write.
- `ActivateSeason(actor, seasonId, expectedManifest, operationId)` → committed manifest and initial season allocation ledger events, or a fail-closed error with previous active state intact.
- `CompleteSeason(actor, seasonId, expectedRevision)` → explicit completion when no end date is set. Archive is read-only after seven days.
- `CopySeasonSettings(actor, sourceSeasonId, targetSeasonId)` → copies configuration only, never participants, approvals, ledger balances, or transactions.

## Enrollment and review

- `UpsertOwnEnrollment(actor, seasonId, expectedRevision, enrollment)` is allowed only during registration, validates inputs, preserves an audit revision, and does not alter Dibs.
- `WithdrawOwnEnrollment(...)` retains historical record and removes it from active counts.
- `ReviewEnrollment(actor, enrollmentId, decision, reason, expectedRevision)` allows only verified GM/Officer; decisions are auditable.
- `GetPublicRoster(seasonId, filters, page)` returns an allowlisted deterministic page and matching totals.
- `RequestMainChange(...)` and `ReviewMainChange(...)` reuse CharacterEligibility. Approval starts a 14-day Dibs-only probation without changing past transaction character snapshots.
- `ReviewLegacyPersonBalance(actor, personKey, selectedMain, expectedLedgerRevision)` displays every linked balance; retaining selected Main balance is the default decision. Required correction is append-only and audited; balances are not summed by default.

## Core Raider

- `RequestPath` records Thursday progression intent, not status.
- `ReviewCorePromotion(actor, enrollmentId, decision, reason, expectedPolicyRevision)` is manual and auditable in the first release.
- A changed policy revision applies to future evaluations; it does not silently promote existing candidates.
- No attendance or performance metric is fabricated by this contract.

## Allocation and reconciliation

- `PreviewSeasonAllocation(seasonId, approvedRosterRevision, rankSnapshotRevision)` includes only approved people and resolves each person's guild rank or the configured no-rank policy. Unknown/ambiguous rank blocks affected rows.
- `PreviewSeasonReconciliation(seasonId)` distinguishes new-season initialization from active-season drift and historical Main/Alt balance merge.
- `ApplySeasonReconciliation(actor, previewId, expectedRevisions, operationId, reason)` requires current authority and unchanged preview dependencies. It appends idempotent ledger events only for reviewed rows.
- Core/Raider category does not affect allocation unless the season explicitly defines a supported policy.

## Error classes

Examples: `MODULE_DISABLED`, `NOT_GUILD_OFFICER`, `GUILD_CONTEXT_STALE`, `SEASON_NOT_FOUND`, `INVALID_TRANSITION`, `REGISTRATION_CLOSED`, `REVISION_CONFLICT`, `ACTIVATION_BLOCKED`, `RANK_UNAVAILABLE`, `NO_RANK_POLICY_REQUIRED`, `BALANCE_REVIEW_REQUIRED`, `SYNC_DEPENDENCY_MISSING`, `PAYLOAD_TOO_LARGE`, `DUPLICATE_OPERATION`.

All failures preserve the last valid season, roster and ledger state.
