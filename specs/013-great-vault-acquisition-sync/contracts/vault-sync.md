# Contract: Great Vault Guild Synchronization

## Transport boundary

Vault synchronization uses the existing `DIBS` addon-message transport and its current guild envelope, serializer, sender validation, chunk limits, expiry, and replay handling. It does not create a second prefix or transport.

Messages are guild-scoped and must be rejected when the sender, guild key, protocol, or record scope cannot be verified.

## Logical message meanings

### `VAULT_DIGEST`

Sent on the guild channel as a bounded anti-entropy summary.

```text
{
  type = "VAULT_DIGEST",
  entityType = "VAULT_INDEX",
  revision = integer,
  contentHash = string,
  records = [
    {
      acquisitionId = string,
      revision = integer,
      contentHash = string,
      verificationState = string,
      claimedAt = integer|nil
    }
  ]
}
```

The digest must not contain live loot-session data or full private evidence.

### `VAULT_FETCH`

Sent privately to request missing or newer acquisition details.

```text
{
  type = "VAULT_FETCH",
  requests = [
    {
      acquisitionId = string,
      revision = integer,
      contentHash = string
    }
  ]
}
```

The request is bounded and may contain only identities and integrity metadata.

### `VAULT_DETAIL`

Sent privately through the existing bounded detail transfer.

```text
{
  type = "VAULT_DETAIL",
  acquisition = <validated acquisition projection>,
  revision = integer,
  contentHash = string,
  projection = "PLAYER" | "OFFICER"
}
```

The sender may provide the full Officer projection only when the receiver's authorization permits it. A player projection must exclude unrelated private evidence.

### `VAULT_ACK`

Returned as an apply result or bounded acknowledgement.

```text
{
  type = "VAULT_ACK",
  acquisitionId = string,
  revision = integer,
  result = "APPLIED" | "IDEMPOTENT_REPLAY" | "STALE_REVISION" | "CONFLICT" | "REJECTED",
  reasonCode = string|nil
}
```

An acknowledgement is not proof of a claim and must not upgrade a record's verification state.

## Receiver validation

The receiver must validate:

1. current guild membership and canonical sender identity;
2. guild key and protocol compatibility;
3. message type and bounded array/count limits;
4. acquisition identity, immutable fields, revision, and content hash;
5. projection visibility and authorized evidence scope;
6. absence of forbidden live loot fields;
7. replay, stale revision, and conflict state.

A failed validation leaves local acquisition and eligibility state unchanged.

## Apply semantics

- `APPLIED`: a new valid acquisition was stored.
- `IDEMPOTENT_REPLAY`: the same content was already stored; no new effect.
- `STALE_REVISION`: the local record is newer; no overwrite.
- `CONFLICT`: the identity exists with different immutable content; Officer review is required.
- `REJECTED`: the message or record violates scope, authority, privacy, or validation rules.

`last-write-wins` is not valid for conflicting acquisition evidence.

## Recovery semantics

- Guild lifecycle or roster events may announce a digest.
- A client behind the digest requests only missing or newer records.
- Detail transfers are bounded, expire, and apply atomically.
- Incomplete transfers are discarded and may be retried.
- A client in a different guild never receives or applies the prior guild's record.
- The transport must continue to work in standalone mode for local records even when synchronization is unavailable.
