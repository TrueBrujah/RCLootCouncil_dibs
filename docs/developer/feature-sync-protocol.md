# Feature Synchronization

How the guild feature configuration is synchronized between clients.

The feature configuration is **not** a separate synchronization mechanism. It
travels inside the existing canonical `OPERATIONAL_POLICY` entity, so it
inherits the same transport, the same authority verification, the same
revision chain, and the same conflict detection as every other canonical
guild record. There is no parallel Governance or Configuration system.

## Transport

| Property | Value |
| --- | --- |
| Entity type | `OPERATIONAL_POLICY` |
| Digest key | `digests.OPERATIONAL_POLICY` |
| Trusted relay | Yes — `OPERATIONAL_POLICY` is in `TRUSTED_RELAY_ENTITIES`. |
| Guild detail | Yes — `OPERATIONAL_POLICY` is in `GUILD_DETAIL_ENTITIES`. |
| Announcement | `Dibs.Sync.AnnounceOperationalPolicy()` after a successful local change. |
| Record source | `Dibs.OperationalPolicy` |

The generic transfer path in `src/modules/SyncV2.lua` handles the entity. It
verifies the transfer's content hash against the payload and the entity id
against the payload's revision before it applies anything.

## Applying a remote record

```
Dibs.OperationalPolicy.ApplyRecord(record, sender)
```

The acceptance sequence is:

1. **Shape validation.** The record must have the expected schema, record
   class, guild key, revision, parent link, author snapshot, and metadata.
   The stored module map must be a map of string keys to booleans.
2. **Hash validation.** The record's canonical content hash must match its
   contents.
3. **Authority verification.** The sender's actual authority is verified
   against the canonical governance record and the live roster. The sender
   must be the record's author. Unknown authority fails closed.
4. **Revision checks.** An exact replay of the current revision is
   idempotent. A conflicting hash at the same revision is a conflict. A stale
   revision is refused. A revision that does not directly follow the current
   one, or whose parent hash does not match, is a parent miss.
5. **Application.** The revision, hash, and record are stored, and an audit
   entry is appended.

### Rejected records and the chain

A record that is refused for any of these reasons is never partially applied:
the local revision, the local hash, and the local state are untouched.

| Outcome | Reason code | Behaviour |
| --- | --- | --- |
| Replayed record | `IDEMPOTENT_REPLAY` | Accepted as a no-op. The existing record is returned. |
| Same revision, different hash | `POLICY_CONFLICT` | Refused. The conflict is recorded in the conflict list and the client is marked as behind. |
| Older revision | `STALE_POLICY` | Refused. |
| Revision gap or parent mismatch | `POLICY_PARENT_MISSING` | Refused. The client records the target revision and requests the missing revision. |
| Unknown sender authority | `POLICY_WRITER_REQUIRED` and related codes | Refused. Fails closed. |
| Wrong guild | `GUILD_SCOPE_MISMATCH` | Refused. |
| Hash mismatch | `POLICY_HASH_MISMATCH` | Refused. |
| Payload does not match the transfer | `CONTENT_HASH_MISMATCH` | Refused before the policy module is called. |

### Recovering a gap

When a client receives a revision it cannot apply because its parent is
missing, it records the target revision and requests the missing revision
from the source. The client then converges by applying the chain in order.
The recovery path is the same one used for any other canonical entity.

## Clients with different catalogues

Two clients in the same guild may implement different feature catalogues. The
protocol is designed so that this does not break synchronization.

- A record carrying a feature the receiving client does not know is **not**
  rejected. The unknown key is retained so that the record's canonical hash
  stays valid and the parent chain is not broken.
- The unknown feature is not effective on the receiving client. The registry
  reports it as `FEATURE_UNKNOWN`, and the feature fails closed.
- When the receiving client writes its next local revision, it carries the
  unknown key forward unchanged. The key is preserved through the revision
  chain, so the hash of every subsequent record stays consistent for every
  peer.
- The catalogue version is published through
  `Dibs.OperationalPolicy.GetCatalogueVersion()` and the registry version
  through `Dibs.FeatureRegistry.GetCompatibility()`. A client that needs to
  detect a mismatch compares these.

The effect is that a guild can adopt a new feature on an upgraded client
while older clients keep working, ignoring the feature they do not implement.
No client is forced to disconnect or to re-adopt its policy.

## Version compatibility

The addon version compatibility check is unchanged and still applies to the
whole transport. A client whose major and minor version differ from its
peer's is reported as an addon version mismatch, exactly as before the feature
catalogue existed.

The feature catalogue adds a second, finer-grained notion: two clients may
share an addon version and still implement different catalogues. The
catalogue tolerance described above is what makes that safe.

## What is never synchronized

The following are local or session state and are never carried in the
`OPERATIONAL_POLICY` entity:

- Presentation settings, window position, and tab selection.
- The per-character notification preference.
- The per-character raid prompt preference.
- Developer mode and sandbox state.
- Live loot, candidates, votes, and raid session state.

Only the guild feature configuration travels in the canonical policy record.

## Audit trail

Every applied revision appends an entry to the operational policy audit log
with the action, the revision, the content hash, the author snapshot, and the
timestamp. The change history is exposed through
`Dibs.FeatureRegistry.GetChangeHistory(limit)`, which reads that same log so
that the two views cannot diverge.

A change to the feature configuration additionally records the effective
per-feature transition in `audit.moduleChanges`, with the previous and the new
effective state of every feature whose state changed.

## Related documents

- [Feature catalogue](feature-catalog.md)
- [Feature configuration](feature-configuration.md)
- [Synchronization protocol](sync-protocol.md)
