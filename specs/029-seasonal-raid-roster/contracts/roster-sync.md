# Seasonal Roster Sync Contract

SyncV2 carries bounded, guild-scoped seasonal state under the existing transfer quotas. `SEASONAL_ROSTER` carries configuration and individual enrollment revisions. Activation manifests and immutable identity snapshots use separate entity types; canonical ledger events remain in the existing ledger transport.

## Entities

- Implemented: season create/edit, registration-state, completion/archive, category-catalog and season-policy revisions; individual enrollment revisions; published immutable rank-allocation snapshots; `SEASON_IDENTITY` snapshots; and capability-negotiated `SEASON_ACTIVATION` manifests.
- Ledger events remain exclusively owned by the existing authoritative ledger entity path; roster payloads must not carry them.

## Requirements

1. Current revision records include canonical `seasonId`/`enrollmentId`, schema-2 record hashes and parent revision/hash; SyncV2 transfer metadata supplies entity type, revision, content hash and sender context. Existing season IDs are guild-bucket scoped.
2. Enrollment changes transfer as individual bounded entities or bounded pages; one edit must not resend every guild character or the entire season history.
3. The exact rank-allocation snapshot is included in the published `SEASON_ALLOCATION_PUBLISHED` season revision and covered by its content hash. The snapshot validator checks schema, rank keys, rank values, and its own rules hash. SyncV2 advertises a separate `seasonalAllocationSnapshot` capability and refuses to serve or adopt this action for peers that do not advertise it. This synchronizes allocation inputs; it does not activate a season.
4. Current `ApplySyncRevision` fails closed while the optional module is disabled; validates sender role/ownership, parent revision/hash and content hash; duplicate valid revisions are idempotent, older revisions are ignored as stale, and gaps/conflicts are refused. Rejected messages do not replace the local store.
5. Transfers honor current SyncV2 constants and quotas; current source defines 8 simultaneous transfers, 16 chunks, and 8,192 bytes total. Do not raise these values without separate payload, memory and rate-limit validation.
6. Offline clients catch up when they next exchange valid digests/details. Do not promise immediate delivery or assume all guild members are online.
7. Current season configuration revisions are accepted only from a verified GM/Officer. Enrollment revisions must be authored by the owner or verified GM/Officer; player self-service is owner-bound and cannot assign another identity.
8. Replay of an existing operation/revision is idempotent. Concurrent edits use expected revision and surface conflicts; no last-write-wins for ledger events.
9. Public roster sync exposes only allowlisted player-facing fields; officer-only review notes and balance data are excluded.
10. Compatibility downgrade/migration preserves unknown historical records and does not silently rewrite canonical IDs or aliases.

## Activation coherence

### Implemented coherence contract — 2026-11-15

A separate capability-negotiated `SEASON_ACTIVATION` entity carries a committed manifest, not allocation rows or ledger transactions. Its exact content hashes/revisions reference season configuration, approved cohort/enrollment revisions, canonical identity snapshots, published rank allocations and canonical ledger root/sequence. The service-facing manifest carries an `identities` array of `{entityType, entityId, revision, contentHash}` descriptors and an `enrollments` map from enrollment ID to revision. To fit larger approved cohorts inside the existing per-entity transfer quota, SyncV2 encodes those references as bounded tuples in a `wireSchema=1` representation and expands them before service validation and adoption; the canonical manifest content hash is unchanged. Each `SEASON_IDENTITY` snapshot transfers separately under entity ID `identity:<seasonId>:<personGroupId>`. Existing ledger messages continue to carry canonical events. The compact manifest wire payload and each identity snapshot are checked against the existing 8,192-byte per-entity limit before local commit; transfer/chunk/byte quotas remain unchanged.

Manifest receipt is staging, not activation. The receiver validates guild, current sender authority, canonical coordinator authorship, content, operation replay and all dependencies before changing `currentSeasonId`. A missing dependency leaves the prior season current, records bounded recoverable incomplete state and requests missing details through existing transport. Arrival of a later configuration/identity/ledger dependency retries adoption; manifest-first and manifest-last orders are covered by transport tests. A guild-roster generation is client-local and is never compared as a remote identity; portable content hashes and canonical revisions establish coherence.

Lifecycle/catalog updates cannot bypass this visibility gate or select an uncommitted draft. A lost postcommit announcement is recoverable by digest/detail catch-up and cannot roll back committed history.

`PublishRankAllocations` copies staged local `db.rankRules[seasonId]` into a new immutable `SEASON_ALLOCATION_PUBLISHED` revision, requires a reason and `season.allocation.configure`, and is allowed after registration closes in `REVIEW`, `READY` or `ACTIVE`. The snapshot is part of the season content hash and SyncV2 parent chain. `PreviewActivation` reads only this snapshot; unpublished or invalid snapshots block preview. Changes to local staging values do not affect a preview until republished, at which point a new season revision invalidates it. Active-season updates change reconciliation inputs but leave the committed activation baseline immutable.

Activation dependencies are carried by `manifest.dependencies` and manifest references. Portable descriptors identify approved enrollment revisions and immutable Main/Alt identity entity/content hashes, plus the published rank/rules snapshot and committed canonical ledger root/sequence. Client-local generation values are deliberately excluded. A mismatch or unavailable dependency preserves the prior current season and bounded recoverable sync state.
