# Data Model: Unified Seasonal Raid

This is a planning contract. Existing persisted objects are migrated additively; field names below describe logical ownership, not a mandatory one-table storage rewrite.

## Season

- `seasonId`: stable guild-scoped canonical ID; shared by all seasonal records.
- `guildKey`: owning guild identity.
- `name`, `startsAt`, optional `endsAt`, `registrationOpensAt`, optional `registrationClosesAt`, raid schedule and descriptive time-zone label.
- `state`: Draft → RegistrationOpen → Review → Ready → Active → Completed → Archived.
- `revision`: monotonic expected-revision token; stale writes fail.
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`; immutable audit events.
- Registration close blocks new player edits but does not complete/archive the season. Archive occurs seven days after season end; when end date is absent an authorized officer completes the season, starting the same delay.

## Versioned season configuration

- `rulesRevision`: published player-visible raid regulations, each with stable rule ID, text, effective time, author, and whether an addon setting enforces it.
- `statusCatalogRevision`: season-specific status definitions, descriptions, order, active flag, and effective time.
- `promotionPolicyRevision`: Core Raider criteria and review guidance.
- `allocationRevision`: rank-to-allocation values and explicit no-guild-rank behavior.
- Revisions are immutable once published. Draft edits may be coalesced before publication; published changes create a new revision. Existing decisions preserve the revision/snapshot they used.

## Enrollment and seasonal person

- `enrollmentId`, `seasonId`, canonical `personKey`, selected Main character identity, declared linked characters, owner identity, revision and timestamps.
- Requested path: e.g. Core Raider Thursday progression intent. This is not an awarded status.
- Current seasonal status and its catalog revision: ordinary signup begins as Raider/candidate (AotC maps to Raider).
- Class/spec, optional second choice, combat roles, armor type, schedule availability and other approved Excel-derived signup fields.
- `state`: Draft, Submitted, Withdrawn, NeedsReview, Approved, Rejected, Removed.
- Player edits are owner-bound and allowed only in the configured registration state. Officer edits record actor, reason, and before/after revisions.
- Public roster projection is allowlisted and excludes private notes, balance details, and officer-only reasons.

## Main/Alt relationship snapshot

- Reuses canonical CharacterEligibility identities and approved relationships.
- `seasonId` stores the Main/Alt selection and approval snapshot used for this season.
- A Main change request records old/new character, requester, decision, approver, dates, reason, and 14-day Dibs-only probation.
- Dibs balance belongs to the approved person. Historical loot events retain the original character and transaction facts.
- Legacy balance merge is a separate preview/approval: review all linked balances, retain selected Main balance, append any required correction, never sum by default.

## Core Raider evaluation

- Candidate enrollment and requested path.
- Policy revision evaluated.
- Manual decision: pending/promoted/declined/revoked, decision author/time, concise reason, optional notes with officer-only visibility.
- Promotion does not modify WoW guild rank or allocation by itself.
- The first release records an officer judgment; it does not claim automated attendance, punctuality, performance, or helpfulness measurement.

## Seasonal allocation and reconciliation

- One allocation configuration per season and native WoW guild rank, plus explicit no-rank policy.
- Only approved roster persons/Main snapshots are included. Each person is counted once; inactive/offline guild members outside the roster are excluded.
- Reconciliation preview records `seasonId`, roster/rank/config revisions, expected and actual allocation, proposed ledger events, conflicts, and a stable idempotency key.
- Apply requires verified authority, unchanged preview revisions, explicit confirmation, and a reason where an adjustment is made. Events are append-only.
- Historical Main/Alt balance merge, new-season initial allocations, and active-season drift correction are separate preview/apply workflows.

## Activation manifest

- `seasonId`, manifest revision, activation operation ID, actor/time.
- Exact revisions/hashes for season configuration, published rules/statuses, approved roster snapshot, Main/Alt identities, allocations, and initial ledger state.
- States: Prepared, Committed, Superseded or Aborted.
- Clients report Active only when all required referenced revisions/hashes are locally available. Retries with the same operation ID are idempotent.
- A failure before manifest commit leaves the prior active season and ledger untouched. Orphaned staged revisions remain invisible and can be retried/recovered without deleting historical data.

## Synchronization and migration aliases

- Every seasonal entity is guild-scoped and keyed by canonical `seasonId`; enrollments additionally use `enrollmentId`.
- Digest/detail transfer is bounded and revisioned. The manifest is a small coherence record, not a full roster payload.
- Migration preserves old IDs and stores explicit aliases from legacy Dibs season and roster season identifiers. Ambiguous links are surfaced for GM/Officer review. No identity or season link is inferred from character name/account.
