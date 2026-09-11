# Synchronization protocol

`Dibs.Sync` uses addon prefix `DIBS`, protocol version `Dibs.PROTOCOL_VERSION`, and guild-scoped envelopes. AceComm/AceSerializer is preferred; the fallback compact payload is `DIBS1:<TYPE>[:<requestId>:<revision>]`.

## Message types

`HELLO` advertises presence. `MANIFEST` lists request revisions. `FETCH` asks an officer peer for missing revisions. `REQUEST` carries one validated Pre-Dib request. `REQUEST_ACK` records delivery acknowledgement. `TRANSFER_BEGIN`, `TRANSFER_CHUNK`, and `TRANSFER_END` carry a bounded request transfer when serialization requires chunks.

## Validation and privacy

Receivers validate the message type, protocol version, sender identity, guild membership, guild key, revision bounds, chunk count/size, and request ownership. Messages containing live loot candidates, votes, or responses are rejected. Only officers can apply authoritative guild data; a player can submit their own request. Transfers expire after a short TTL and duplicate transactions are guarded by `seenTransactions`.

## Multi-raid behavior

Each raid can maintain its own active relay and encounter context. Sync reconciles accounting and request metadata; it never moves an item, a live RC candidate list, a vote, or an RC response between raids (DIBS-RULE-012). A manifest is sent on roster changes and a bounded retry is scheduled through AceTimer when available.

See [events.md](events.md) and [combat-safety.md](combat-safety.md) for transport/event boundaries.
