# Contract: Pre-Dib Recovery Sync

## Scope

This protocol transfers persisted Dibs request state between connected guild clients. It never carries live loot drops, candidates, votes, responses, or loot-session discussion.

## Message Types

| Message | Sender | Recipient | Purpose |
|---|---|---|---|
| `HELLO` | Any participating client | Guild or raid peers | Announces protocol support and identity |
| `MANIFEST` | Request owner | Eligible officer | Lists active request IDs and revisions |
| `FETCH` | Eligible officer | Request owner | Requests missing or stale IDs |
| `TRANSFER_BEGIN` | Request owner | Eligible officer | Begins a bounded record transfer |
| `TRANSFER_CHUNK` | Request owner | Eligible officer | Delivers an ordered transfer segment |
| `TRANSFER_END` | Request owner | Eligible officer | Completes a transfer with integrity metadata |
| `REQUEST_ACK` | Eligible officer | Request owner | Acknowledges accepted request revision |

## Delivery Rules

1. A player sends only their own active request records.
2. Officers use manifests to request only absent or stale records.
3. An inbound record is accepted only when sender identity matches its owner identity and all required immutable fields are valid.
4. An existing record is updated only when its incoming revision is newer.
5. Duplicate, expired, malformed, oversized, or checksum-invalid transfers are ignored and logged diagnostically.
6. Acknowledgement confirms receipt of a revision, not authorization to spend Dibs or award loot.
7. A player retains a request marked `PENDING` until a valid acknowledgement is received or the request reaches a terminal lifecycle state.
8. Fulfilled request state cannot be introduced or overwritten by an untrusted player transfer.

## Privacy and Authority

- Sync messages contain only Dibs request and protocol metadata.
- The protocol never invokes ledger mutation or award finalization directly.
- Mode changes and award fulfillment continue through authorized protected actions.
- Receiving a reminder or sync message never grants recipient permissions.
