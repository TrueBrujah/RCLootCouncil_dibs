# Synchronization protocol

`Dibs.Sync` uses addon prefix `DIBS`, protocol version `Dibs.PROTOCOL_VERSION`, and guild-scoped envelopes. AceComm/AceSerializer is preferred; the fallback compact payload is `DIBS1:<TYPE>[:<requestId>:<revision>]`. The legacy request path and the V2 canonical-ledger path are separate: compact or legacy traffic never claims a successful canonical commit.

## Message types

`HELLO` advertises presence. `MANIFEST` lists request revisions. `FETCH` asks an officer peer for missing revisions. `REQUEST` carries one validated Pre-Dib request. `REQUEST_ACK` records delivery acknowledgement. `TRANSFER_BEGIN`, `TRANSFER_CHUNK`, and `TRANSFER_END` carry a bounded request transfer when serialization requires chunks.

## Validation and privacy

Receivers validate the message type, protocol version, sender identity, guild membership, guild key, revision bounds, chunk count/size, and request ownership. Messages containing live loot candidates, votes, or responses are rejected. Only officers can apply authoritative guild data; a player can submit their own request. Transfers expire after a short TTL and duplicate transactions are guarded by `seenTransactions`.

## V2 multi-raid behavior

V2 is enabled only by an explicit GM governance record after baseline and
compatible-writer checks. The active coordinator emits bounded `LEDGER_DIGEST`
hints after persisting a commit; complete `AWARD_COMMIT` detail is fetched by
WHISPER from that coordinator and applied only at the exact next sequence with
the matching previous hash and content hash. A gap or branch conflict yields
`SYNC_BEHIND`/conflict handling and cannot be skipped.

No coordinator or canonical Dibs consumption is allowed while the client is
`SYNC_BEHIND`, `COORDINATOR_UNAVAILABLE`, or `RECOVERY_PENDING`. An award in
those states is proposal evidence with `PENDING_RECONCILIATION`, not a debit.
Normal handoff binds the predecessor epoch, final sequence, and root hash;
forced recovery binds a GM-approved baseline hash and audit decisions.

Each raid can maintain its own encounter context. Sync never moves an item, a
live RC candidate list, a vote, or an RC response between raids
(`DIBS-RULE-012`).

See [events.md](events.md) and [combat-safety.md](combat-safety.md) for transport/event boundaries.
