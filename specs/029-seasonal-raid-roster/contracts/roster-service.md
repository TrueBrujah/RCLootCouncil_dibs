# Seasonal Roster Service Contract

This addon-local contract describes observable service behavior, not a REST API.
The implemented roster store is schema 2 (`db.seasonalRoster`) and configuration
revisions use SyncV2 entity `SEASONAL_ROSTER`. Activation manifests and immutable
identity snapshots use separate bounded SyncV2 entities; ledger events remain in
the canonical ledger protocol.

## Common rules

- Every call is scoped to the active guild and canonical `seasonId`.
- Mutations require the expected current revision; stale calls return a conflict and do not mutate.
- GM/Officer writes require current verified guild authority at the mutation boundary.
- Player enrollment writes are bound to the authenticated character/person identity.
- Ordinary service reads and all writes require the optional `seasonalRoster` module to be enabled. `GetPreservedHistory(actor)` is the narrow read-only exception: it returns a bounded allowlist of preserved season/rule revision history while disabled, with actor/reason metadata only for the authenticated GM/Officer. The module gate preserves the SavedVariables subtree for re-enable.
- Persisted authoritative decisions emit audit events. Replayed operation IDs are idempotent.
- Never expose private officer notes or ledger details through the public roster projection.

## Lifecycle operations

- Date validation (FR-058): new seasons, explicit draft updates and draft
  publication require `registrationStartAt < startAt`; when both end timestamps
  exist, `registrationEndAt <= endAt`. Violations return
  `REGISTRATION_MUST_PRECEDE_SEASON` or `REGISTRATION_EXCEEDS_SEASON_END`
  without writes. End dates remain optional. `ValidateSeasonInput(input, true)`
  enables these checks for UI/setup preflight; the default schema-validation
  mode remains compatible with historical revisions and synchronization.
  Existing operation receipts remain idempotent; old dates are never rewritten.

- `CreateSeason(input, operationId, actor)` is implemented: it creates one canonical ID in SeasonalRoster and an inactive Dibs season draft. Start and registration-open timestamps are required. Optional `raidDifficulties` is a unique list drawn from `NORMAL`, `HEROIC` and `MYTHIC`; the compatible domain field remains separate from signup categories. The approved new/draft UI (029 FR-056–057) now submits identical selected `NORMAL`/`HEROIC`/`MYTHIC` lists for both fields and a matching catalog; published legacy seasons and their registrations are not migrated. Current season and ledger remain unchanged.
- `UpdateDraft(seasonId, patch, expectedRevision, operationId, reason, actor)` is implemented for draft name, description, raid-rule text (up to 8,000 characters), dates, schedule, `raidDifficulties`, category catalog and the versioned no-rank allocation policy. A schedule entry may optionally include `difficulty` (`NORMAL`, `HEROIC` or `MYTHIC`); omission remains valid for legacy and unspecified nights. It creates an immutable audited revision, rejects forbidden fields and stale revisions, and does not change the active season or ledger. `ListSeasons()` includes current public raid rules, difficulties and allocation policy; historical values remain in immutable revisions.
- `UpdateCategoryCatalog(...)` publishes a new immutable catalog revision; historic catalog revisions remain addressable.
- `SetRegistrationState(...)` is implemented for opening and closing registration. Opening is date-gated and audited; closing transitions to review. Closing does not complete or archive the season.
- `CompleteSeason(seasonId, expectedRevision, operationId, reason, actor)` explicitly completes an eligible season and records an immutable revision. `ArchiveSeason(...)` is a separate audited transition after the seven-day grace period. Closing registration alone neither completes nor archives a season.
- `CopySeasonSettings(sourceSeasonId, targetSeasonId, expectedRevision, operationId, reason, actor)` is implemented for description, raid-rule text, Core promotion policy, category catalog, raid schedule, `raidDifficulties` and no-rank allocation policy. It leaves target identity/name/dates/lifecycle, enrollments, approvals and ledger untouched.
- `PreviewActivation(seasonId, actor)` is implemented as a read-only Officer operation. It requires a closed registration in `REVIEW` or `READY`, includes only approved enrollments, counts one explicitly selected Main per approved Main/Alt person group, and reads explicit rank allocations without creating defaults. Linked Alt balances in the currently active season must be zero after reviewed corrections, no linked character may have a pending Dibs reservation, and balance data must be readable before the preview is ready. The new season's allocation remains independent and never imports those balances. The stable preview ID binds roster, identity, guild-roster generation, rank rules and source-ledger revision; a changed dependency requires a new preview. It returns rows, exclusions and blockers. It never changes the active season, rank rules, SavedVariables roster, or ledger. A ready preview is not activation.
- `PrepareActivationManifest(...)` prepares a read-only, content-hashed activation proposal, and `ValidateActivationManifest(...)` checks its current dependencies. `ActivateSeason(seasonId, previewId, expectedRevision, operationId, reason, actor, confirmation)` requires explicit confirmation, current authority, a fresh ready preview and canonical writer availability. It stages the new allocations in a detached copy of the currently approved ledger, validates manifest and identity payload sizes against the existing 8,192-byte per-entity limit, then publishes the complete ledger and season visibility at one guild-bucket commit. A failed stage leaves the bucket, previous current season and ledger unchanged. Replaying the same operation is idempotent; changed content under the operation ID is refused.
- `PublishRankAllocations(seasonId, expectedRevision, operationId, reason, actor)` copies the current local rank-rules draft into an immutable season revision. It requires GM/Officer allocation permission, a reason and closed registration; publication is supported in `REVIEW`, `READY` and `ACTIVE`. The snapshot is schema- and hash-validated and included in SyncV2. Preview reads only that snapshot; local edits after publication are not authoritative until republished. An active-season publication updates future reconciliation inputs without rewriting the activation manifest or historical transactions.
- Each immutable season revision may define `noRankPolicy`: `UNCONFIGURED` (default; blocks an approved participant not in the current guild roster), `EXCLUDE` (lists the participant but omits them from starting allocation), or `FIXED` with an integer allocation from 0 to 100,000. This policy is included in the revision hash and seasonal roster sync. Rank allocations must be explicitly configured and enabled for every included guild rank; no global/default rank allocation is inferred. The published rank snapshot is required; local unstaged values do not satisfy this gate.
- A preview alone never changes the current season or ledger. Only a committed and dependency-validated activation manifest exposes the new season as active.

## Enrollment and review

- `UpsertOwnEnrollment(actor, seasonId, expectedRevision, enrollment)` is allowed only during registration, validates inputs, preserves an audit revision, and does not alter Dibs.
- `WithdrawOwnEnrollment(...)` retains historical record and removes it from active counts.
- `AdminUpdateEnrollment(...)` allows verified GM/Officer correction/removal with expected revision and reasoned audit. It is implemented.
- `GetPublicRosterPage(seasonId, options)` returns an allowlisted deterministic page and matching composition totals (roles, categories, classes, armor, unique linked people); page size is clamped to 50.
- `RequestMainChange(...)` and `ReviewMainChange(...)` reuse CharacterEligibility. Approval starts a 14-day Dibs-only probation without changing past transaction character snapshots.
- `GetBalanceReconciliationPreview(seasonId, character, actor)` displays the selected Main balance and linked legacy character balances. `ApplyLegacyBalanceCorrection(seasonId, character, expectedPreview, reason, operationId, confirmation, actor)` is an explicit append-only audited Alt correction; the selected Main balance is retained and balances are never summed by default.

## Core Raider

- `RequestPath` records participation intent according to the guild's published configuration, not an awarded status or a fixed weekday. Persisted path identifiers remain unchanged.
- There is no separate `ReviewCorePromotion` endpoint. A verified GM/Officer records promotion through `AdminUpdateEnrollment(...)` by changing the seasonal category to `CORE_RAIDER`; the current policy revision, actor and required reason are captured in the immutable enrollment decision. Requested path is stored separately; no automatic Core promotion occurs.
- A changed policy revision applies to future evaluations; it does not silently promote existing candidates.
- No attendance or performance metric is fabricated by this contract.

## Allocation and reconciliation

- `PreviewSeasonReconciliation(seasonId, actor)` is available only for a committed active season. It projects the approved cohort, reports assigned allocation and signed rank/configuration drift, and binds season, roster and ledger revisions. It does not enumerate unrelated guild members or combine historical Main/Alt balances.
- `ApplySeasonReconciliation(actor, previewId, expectedRevisions, operationId, reason, confirmation)` requires explicit confirmation, current coordinator/writer authority, a reason and unchanged preview dependencies. A detached canonical ledger batch appends idempotent allocation adjustments; prior transactions and spent Dibs remain unchanged.
- Historical Main/Alt balance review is a distinct read-only preview and append-only correction operation. New-season initialization, historical Alt correction and active-season drift are separate operations.
- Core/Raider category does not affect allocation unless the season explicitly defines a supported policy.

## Error classes

## Completion operation contract — 2026-11-14

- `ActivateSeason(seasonId, previewId, expectedRevision, operationId, reason, actor, confirmation)` requires current guild administration/activation authority, a fresh ready preview and explicit confirmation (`true` or `{confirmed=true}`). It stages canonical allocations for approved people only in the currently approved ledger, under the new season ID. It preserves all previous-season transactions and does not carry balances forward. A repeated identical operation returns its committed result; changed content under the same ID is refused.
- `Ledger.PrepareSeasonAllocationBatch(...)` validates and stages allocation events using the existing canonical coordinator/writer contract without publishing intermediate state. The commit publishes the complete ledger and activation visibility together; any precommit failure leaves the prior guild bucket untouched. Roster payloads never contain ledger events.
- `GetActivationSyncPayload(seasonId)`, `ApplyActivationSyncPayload(manifest, sender)` and `RetryPendingActivations(sender)` serve and stage a compact manifest. Remote adoption exposes Active only after every dependency and canonical author validate. Unknown, partial, unauthorized, stale or incompatible state retains the prior current season and bounded recoverable pending state.
- Immutable Main/Alt activation records use `SEASON_IDENTITY`; `GetActivationIdentitySyncPayload(entityId)` and `ApplyActivationIdentitySyncPayload(payload, sender)` serve/adopt one bounded identity snapshot at a time. Manifest references use stable member keys and content hashes, never ledger transactions.
- `PreviewSeasonReconciliation(seasonId, actor)` projects only the committed approved cohort, binds the current canonical ledger/configuration/identity/rank revisions, and reports signed allocation differences independently from balance and historical Main/Alt corrections.
- `ApplySeasonReconciliation(actor, previewId, expectedRevisions, operationId, reason, confirmation)` requires `{seasonId, seasonRevision, rosterRevision, sourceLedgerRevision}`, an unchanged preview, current canonical writer authority, reason, operation ID and explicit confirmation. The detached batch appends allocation adjustments atomically and idempotently; spent Dibs and old transactions remain unchanged.
- Archive records a new immutable lifecycle revision only after completion and the seven-day grace period. It never deletes history or makes a draft current.

These signatures define the completed service contract. Automated coverage and its limits are recorded in the feature validation quickstart.

Representative failures include `MODULE_DISABLED`, `GUILD_ADMIN_REQUIRED`, `PERMISSION_DENIED`, `SEASON_NOT_FOUND`, `INVALID_TRANSITION`, `REGISTRATION_CLOSED`, `REGISTRATION_NOT_OPEN`, `STALE_REVISION`, `OPERATION_CONFLICT`, `SEASON_READ_ONLY`, `CONFIRMATION_REQUIRED`, `ACTIVATION_MANIFEST_TOO_LARGE`, `SEASON_IDENTITY_TOO_LARGE`, `STALE_RECONCILIATION_PREVIEW`, and canonical coordinator/ledger readiness errors.

All failures preserve the last valid season, roster and ledger state.
