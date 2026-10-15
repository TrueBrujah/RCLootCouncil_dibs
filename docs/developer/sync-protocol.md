# Synchronization protocol

`Dibs.Sync` uses addon prefix `DIBS`, protocol version `Dibs.PROTOCOL_VERSION`, addon version `Dibs.VERSION`, and guild-scoped envelopes. AceComm/AceSerializer is preferred; the fallback compact payload is `DIBS1:<TYPE>[:<requestId>:<revision>]`. The legacy request path and the V2 canonical-ledger path are separate: compact or legacy traffic never claims a successful canonical commit.

## Addon version compatibility

V2 envelopes include `addonVersion`. Clients are compatible only when their
semantic-version `major.minor` family matches. The 0.8.x family carries the
rank-reconciliation transaction and proposal contract; 0.7.x peers are rejected with
`ADDON_UPDATE_REQUIRED` before any sync payload is applied. The last verified
mismatch is retained for Officer UI, Loot Rules readiness, and the debug
report. A legacy peer that does not send `addonVersion` remains observable as
unknown rather than being treated as a compatible claim.

The existing `SEASON_CATALOG` entity carries the versioned
`guildConfiguration.guildLootRules` schema-v1 snapshot. It includes one
Adventure Guide and one RCLootCouncil decision for every dynamically supported
loot type and remains covered by the catalog hash and parent revision chain.
Only explicit GM adoption/publication changes that snapshot. Legacy local maps
are preserved and excluded from generic catalog replication. Officers consume
the last validated snapshot read-only. A rejected or missing-parent revision
does not change effective rules or the DIBS-owned RCLootCouncil projection.

Loot Rules readiness distinguishes `GUILD_LOOT_RULES_READY`,
`GUILD_LOOT_RULES_NOT_CONFIGURED`, `LOCAL_LEGACY_ONLY`,
`GUILD_LOOT_RULES_SYNC_BEHIND`, `GUILD_LOOT_RULES_INCOMPATIBLE`, and
`UNAVAILABLE`. Catalog lag keeps the last valid guild snapshot effective and
visible in readiness; it must not trigger local fallback.

## Message types

`HELLO` advertises presence. `MANIFEST` lists request revisions. `FETCH` asks an officer peer for missing revisions. `REQUEST` carries one validated Pre-Dib request. `REQUEST_ACK` records delivery acknowledgement. `TRANSFER_BEGIN`, `TRANSFER_CHUNK`, and `TRANSFER_END` carry a bounded request transfer when serialization requires chunks.

## Validation and privacy

Receivers validate the message type, protocol version, sender identity, guild membership, guild key, revision bounds, chunk count/size, and request ownership. Messages containing live loot candidates, votes, or responses are rejected. Only authorized writers can approve new authoritative guild revisions. After a client directly observes an approved governance, operational-policy, season-catalog, or historical-baseline digest from the required authority, any compatible guild member may relay the immutable content matching that exact revision and hash. Unknown or conflicting hashes still require direct authority and fail closed. Transfers expire after a short TTL and duplicate transactions are guarded by `seenTransactions`.

Canonical ledger commits are excluded from member relay. Their aggregate ledger
digest does not attest each individual commit hash, so the active coordinator
remains the authoritative detail source until a stronger per-commit proof
contract exists.

## V2 multi-raid behavior

### Private review requests (additive 2.1 capability, 0.8.8)

`requestDelivery=true` advertises support for WHISPER-only `REQUEST_MESSAGE`
detail transfers. Kinds are `submit`, `reply`, `snapshot`, `receipt`; identity,
guild scope, revision, operation ID and pinned coordinator epoch are validated.
The same existing maximum 8192 bytes / 16 chunks of 480 bytes / eight active
transfers / 300-second TTL applies (effective encoded body limit 7680 bytes).
Ticket bodies are never included in GUILD digests, HELLOs, or live loot state.

Submissions/replies are non-authoritative. Acceptance resolves the actual sender
as the current same-guild owner and requires the local verified coordinator.
Snapshots require that actual coordinator at receipt; verified officer recipients
receive private dossiers, owners always receive an explicit safe projection even
if they are also officers. Internal audit and assignment never enter the owner
body. Snapshot acceptance does not import transactions.

Per-character/per-guild durable outboxes retain at most 128 operations, retry no
more than four sends per pump with 60-second spacing, and distinguish queued,
sent, received, error. A matching private receipt acknowledges acceptance, not
resolution. Actual roster-online/capable targets are checked before any whisper.
Unadvertised/old peers remain unsupported/pending. Replay uses retained request
and reply IDs; fresh transfers can recover a lost receipt after reload.
Snapshots coalesce per request/recipient and catch up eight dossiers per pump,
to the owner plus at most 16 online capable officer peers. Oversize/capacity
failures preserve source data and expose error/pending state.

Only the verified pinned coordinator may mutate shared dossiers or compensate.
Replicas are read-only; optimistic revisions are an additional stale-form guard,
not distributed accounting authority. Changed epochs fail closed; automated
handoff of old dossiers is not implemented. Legacy local dossiers changed before
initial binding do not silently become shared. Developer Mode and Independent
Raid contexts do not send or accept production request delivery.

### Guild state

V2 is enabled only by an explicit GM governance record after baseline and
compatible-writer checks. Guild-wide revision digests and shared detail
transfers use the `GUILD` addon channel. The active coordinator emits bounded
`LEDGER_DIGEST` hints after persisting a commit; peers request `AWARD_COMMIT`
details in bounded batches over `GUILD`, and the coordinator broadcasts those
commits to guild clients. Each receiver applies a commit only at the exact next
sequence with the matching previous hash and content hash. A gap or branch
conflict yields `SYNC_BEHIND`/conflict handling and cannot be skipped.

Peers advertise `guildDetail`; newer clients use the guild route by default
and retain a targeted fallback when talking to an older V2 peer without that
capability. Receivers continue to accept that legacy targeted route.

Targeted `WHISPER` transfers remain for owner-scoped Pre-Dib and Vault details,
award proposals sent to the coordinator, recovery packages, orphaned evidence,
and explicit sync probes. These exceptions preserve the existing ownership or
recipient checks; they do not carry shared revision state.

Before queuing a V2 `WHISPER`, the transport resolves the target against the
current guild roster, verifies the roster reports the member online, and sends
the full `Name-Realm` address, with realm spaces removed. Short names are
accepted only when unambiguous; unknown, ambiguous, or offline targets return
an explicit error without sending. Display names and persisted member keys are
not rewritten by this transport normalization.
This applies to every private transfer frame, response, saved Vault retry, and
older-peer fallback. Detail transfers preserve the exact send failure reason
and stop at the first rejected frame rather than reporting every failure as
`SYNC_UNAVAILABLE`.

The shared Ace3 adapter independently refreshes roster presence immediately
before queuing a whisper, including direct adapter callers. This is a transport
invariant: new private senders must use this boundary, not raw addon whispers.
The final resolved address must contain both a player name and a nonempty realm;
otherwise sending returns `INVALID_WHISPER_TARGET`. A same-realm short roster
name is qualified by Identity using the current realm; cross-realm recipients
retain their own roster realm. Never send a bare player name or guess another
recipient's realm.
Localized `CHAT_MSG_SYSTEM` player-not-found feedback for an unambiguous target
contacted in the last 30 seconds opens a 60-second circuit breaker
(`WHISPER_TARGET_UNREACHABLE`). The feedback is not hidden or chat-filtered.
Tracking is runtime-only, guild-scoped, and limited to 128 destinations; capacity
returns `WHISPER_TARGET_CAPACITY` rather than evicting an active block.
After expiry a retry still requires current online roster evidence. A disconnect
after queuing or traffic from another addon can still produce a Blizzard error;
this guard does not cancel AceComm/ChatThrottleLib messages already queued.

No coordinator or canonical Dibs consumption is allowed while the client is
`SYNC_BEHIND`, `COORDINATOR_UNAVAILABLE`, or `RECOVERY_PENDING`. An award in
those states is proposal evidence with `PENDING_RECONCILIATION`, not a debit.
Normal handoff binds the predecessor epoch, final sequence, and root hash;
forced recovery binds a GM-approved baseline hash and audit decisions.

An uncommitted finalized DIB award also emits a bounded, paged
`AWARD_RESERVATION_DIGEST` over `GUILD`. It contains only reservation identity,
player/actor member keys, season, amount, state, timestamp, and evidence
references; award and vote details remain targeted to the coordinator. Clients
subtract each distinct pending reservation from available Dibs immediately,
without changing the canonical ledger. Applying the matching canonical commit
removes the reservation, so the debit is counted exactly once.

Each raid can maintain its own encounter context. Sync never moves an item, a
live RC candidate list, a vote, or an RC response between raids
(`DIBS-RULE-012`).

## UI terminology and technical state

Player and standard Officer guidance uses **Guild Ledger** for the shared
canonical Dibs record and **Synchronization** for the user-visible exchange
status. The technical-details view may expose `V2_ENFORCED`, `ledgerEpoch`,
`legacyBaselineHash`, and `SyncV2`; these are diagnostic identifiers, not
configuration steps a guild member must understand. `SYNC_BEHIND` means the
client has not caught up and must not be presented as ready for canonical
updates. Guild Setup and Setup Assistant should pair any blocked/unavailable
state with its operational consequence and next action.

See [events.md](events.md) and [combat-safety.md](combat-safety.md) for transport/event boundaries.
