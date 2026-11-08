# Seasonal Roster Sync Contract

SyncV2 carries bounded, guild-scoped seasonal state. This contract is for the feature design; implementation must preserve existing protocol compatibility and its current resource limits.

## Entities

- Season catalog metadata and lifecycle revision.
- Season rules/status/promotion/allocation revisions.
- Enrollment record revisions and approved roster projection/digest.
- Main/Alt season snapshot references where required for the participant.
- Activation manifest containing exact dependency revisions and hashes.
- Reconciliation/ledger events through the existing authoritative ledger entity path, never embedded as an unrestricted roster blob.

## Requirements

1. Every entity includes canonical `seasonId`, guild scope, schema/protocol version, revision, content hash, and authority context required by SyncV2.
2. Enrollment changes transfer as individual bounded entities or bounded pages; one edit must not resend every guild character or the entire season history.
3. The activation manifest is transferred only after its dependencies are available from an authorized source. A receiver must not report a season Active until all referenced revisions and hashes match.
4. A partial transfer, missing parent season, stale revision, conflict, invalid sender, wrong guild, or disabled module must leave the last valid local projection intact and mark sync as behind/incomplete as applicable.
5. Transfers honor current SyncV2 constants and quotas; current source defines 8 simultaneous transfers, 16 chunks, and 8,192 bytes total. Do not raise these values without separate payload, memory and rate-limit validation.
6. Offline clients catch up when they next exchange valid digests/details. Do not promise immediate delivery or assume all guild members are online.
7. Authoritative changes are accepted only from verified GM/Officer authority. A player's own enrollment is sender-bound and may not assign another identity.
8. Replay of an existing operation/revision is idempotent. Concurrent edits use expected revision and surface conflicts; no last-write-wins for ledger events.
9. Public roster sync exposes only allowlisted player-facing fields; officer-only review notes and balance data are excluded.
10. Compatibility downgrade/migration preserves unknown historical records and does not silently rewrite canonical IDs or aliases.

## Activation coherence

The manifest is the visibility commit point. Before commit, staged records can be stored but must not be shown as the active season. After commit, a client may show Active only when every manifest reference is locally verified. On mismatch, retain the prior active season and surface a recoverable sync state.
