# Synchronization Protocol Notes

The maintained protocol reference is [docs/developer/sync-protocol.md](developer/sync-protocol.md). This file remains a compatibility note and lists only behavior confirmed by `src/modules/Sync.lua`.

The Pre-Dib recovery protocol uses the registered `DIBS` addon-message prefix. It is compact, versioned, bounded, and transfers only persisted active Pre-Dib state.

When AceComm and AceSerializer are available through `LibStub`, Dibs serializes each logical protocol message through AceSerializer and sends it through AceComm. AceComm supplies addon-message registration and fragmentation without changing message fields, validation, transfer bounds, or trust rules. Standalone clients without Ace3 retain the legacy `DIBS1:<type>[:requestId:revision]` compatibility payload.

## Message types

The implementation accepts exactly: `HELLO`, `MANIFEST`, `FETCH`, `TRANSFER_BEGIN`,
`TRANSFER_CHUNK`, `TRANSFER_END`, `REQUEST_ACK`, and `REQUEST`. Names such as
`DIGEST`, `TX_COMMIT`, or `RELAY_ELECTION` are not protocol messages.

## Pre-Dib recovery

- `HELLO` announces feature support.
- `MANIFEST` lists the request owner's active request IDs and revisions.
- An eligible officer returns `FETCH` for missing or stale IDs.
- `TRANSFER_BEGIN`, `TRANSFER_CHUNK`, and `TRANSFER_END` are bounded by chunk count, payload size, and expiry.
- `REQUEST_ACK` records officer receipt of a request revision; it never authorizes an award or Dib spend.
- Data-bearing recovery is guild-scoped: an incoming request must come from its owner and be received by a verified GM/officer, while `FETCH` is accepted only from a verified GM/officer. Ordinary guild members cannot use recovery messages to read another player's stored requests.

Payloads containing live drops, candidates, votes, responses, or loot-session fields are rejected. Incoming request records must match the sender identity, retain immutable origin fields when updating known records, accept only newer revisions, and cannot introduce `fulfilled` state.

RCLootCouncil award callbacks never enter this synchronization protocol. They are handled locally by the adapter and produce a Dibs-owned ledger transaction only after capability, local Master Looter, explicit DIB response, item/winner, final-status, and stable award-reference checks. Award references are persisted in `awardTransactions` so reloads and reconnects are idempotent. No current session ID, candidate list, vote, or response payload is broadcast between raids.

## Difficulty and acquisitions

Persisted request records include normalized `Normal`, `Heroic`, `Mythic`, or `UNKNOWN` difficulty. This field is part of active-request identity and is transferred with the request record. Award fulfillment applies an award difficulty only when the award context supplies one, retaining legacy matching for awards without difficulty.

Great Vault acquisitions are local, display-only SavedVariables records. They are not protocol payloads and never cause a request transition or ledger transaction.

## Snapshot projection

The officer-only `SyncSnapshot` projection may carry bounded ledger transaction
fields and Pre-Dib request fields. Applying it validates each transaction and
request, preserves idempotence, and never accepts live loot candidates, votes,
responses, or item transfers. It is accounting metadata synchronization, not a
loot-session protocol.

## Required properties

- duplicate-safe
- chunk-safe
- throttle-aware
- versioned
- recoverable after reconnect
- no assumption that messages arrive once or in order
- AceComm/AceSerializer and legacy transport acceptance preserve the same forbidden-field checks

## Security/trust note

WoW addon messaging is not a cryptographically trusted transport. Authorization must therefore be modeled explicitly and the threat model documented during planning.
