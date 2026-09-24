# Sync Message Contracts: Guild Sync Reliability

All messages below travel over the existing `Dibs.SyncV2` envelope
(`Sync.BuildEnvelope`), which stamps `protocol`, `addonVersion`, `messageId`,
`guildKey`, `senderNameRealm`, and `senderMemberKey`. `addonVersion` uses
semantic-version `major.minor` compatibility: all `0.6.x` versions are
compatible, while a peer on `0.7.x` is rejected with `ADDON_UPDATE_REQUIRED`.
Only the
feature-specific `type`/`entityType` payload shapes are documented here; the
envelope, replay-dedup, and channel-validation rules are unchanged.

## 1. AWARD_PROPOSAL (new entity type)

**Digest is not required** — award proposals are point-to-point (submitter →
coordinator), not guild-wide state, so there is no `DIGEST` broadcast for this
entity type. Delivery uses the existing detail-transfer primitives directly.

**Transport**: `TRANSFER_BEGIN` / `TRANSFER_CHUNK` / `TRANSFER_END`, channel
`WHISPER`, target = current coordinator's `displayName` (resolved from local
`Dibs.Governance` state).

**Payload** (carried in the final `TRANSFER_END.request`-equivalent field,
following the same shape as existing `PREDIB_REQUEST`/`VAULT_DETAIL`
transfers):

```lua
{
  entityType = "AWARD_PROPOSAL",
  proposalId = "<string>",
  playerSnapshot = { memberKey = "<string>", displayName = "<string>" },
  submitterSnapshot = { memberKey = "<string>", displayName = "<string>" },
  itemID = <number|nil>,
  itemLink = "<string|nil>",
  awardRef = "<string|nil>",
  evidenceId = "<string|nil>",
  raidContext = "<string|nil>",
  createdAt = <timestamp>,
}
```

**Receiver contract** (coordinator only):
- MUST reject if the receiver is not the current, verified coordinator
  (mirrors existing `isAdmin`/coordinator checks already in `SyncV2.lua`).
- MUST treat a re-delivered `proposalId` as a no-op (idempotent), never a
  second pending entry.
- On acceptance, MUST add the proposal to the coordinator's local pending
  list surfaced in Officer UI; MUST NOT auto-commit it.

**Acknowledgement**: coordinator sends a small `WHISPER` reply
`{ type = "AWARD_PROPOSAL_ACK", proposalId = ... }` so the submitter can move
local status from `RELAY_PENDING` to `RELAY_ACKED`. If no ack arrives within
the existing heartbeat window, the submitter retries (bounded).

## 2. SEASON_CATALOG (new entity type, DIGEST + detail, same shape as OPERATIONAL_POLICY)

**Digest** (`type = "DIGEST"`, channel `GUILD`, sent from `Sync.OnLifecycle`
alongside the existing `GOVERNANCE`/`OPERATIONAL_POLICY` digests):

```lua
{
  type = "DIGEST",
  entityType = "SEASON_CATALOG",
  entityId = "current",
  revision = <policyRevision>,
  contentHash = "<hash>",
  parentHash = "<hash|nil>",
}
```

**Detail fetch** (receiver behind → `DETAIL_FETCH`, channel `WHISPER`, same
shape as the existing `GOVERNANCE`/`OPERATIONAL_POLICY` detail-fetch
requests):

```lua
{
  type = "DETAIL_FETCH",
  requests = { { entityType = "SEASON_CATALOG", entityId = "current",
                 revision = <revision>, contentHash = "<hash>",
                 parentHash = "<hash|nil>" } },
}
```

**Detail transfer payload** (`TRANSFER_*`, channel `WHISPER`):

```lua
{
  entityType = "SEASON_CATALOG",
  schema = 1,
  policyRevision = <integer>,
  parentHash = "<hash|nil>",
  contentHash = "<hash>",
  authorMemberKey = "<string>",
  authorNameRealm = "<string>",
  currentSeasonId = "<string|nil>",
  seasons = {
    ["<seasonId>"] = {
      id = "<seasonId>", name = "<string>",
      createdAt = <timestamp>, updatedAt = <timestamp|nil>,
      archivedAt = <timestamp|nil>, isActive = <boolean>, isArchived = <boolean>,
    },
    -- ...
  },
}
```

**Receiver contract**:
- MUST re-verify sender writer authority the same way
  `OperationalPolicy.writerAuthorized` does (GM, or configured rank rule) —
  never trust `authorMemberKey` alone without resolving it against the live
  or last-known roster.
- MUST merge `seasons` as a keyed union (add/update by `id`), never delete a
  locally known season absent from the incoming map.
- MUST only update `currentSeasonId` if that season exists post-merge and is
  not archived.

## 3. Synchronization status (no new wire message)

Purely local presentation, built from already-synchronized state
(`Governance`, `OperationalPolicy`, local `SeasonCatalogRecord`, and the
existing `UNSUPPORTED_PROTOCOL_MAJOR` rejection already raised by
`validateEnvelope`/protocol-major checks in `SyncV2.lua`). No new message
type; this contract only requires recording the last protocol-mismatch
observation for display, using the existing `sync` diagnostic scope.
