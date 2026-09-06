# Synchronization Protocol Notes

The Pre-Dib recovery protocol uses the registered `DIBS` addon-message prefix. It is compact, versioned, bounded, and transfers only persisted active Pre-Dib state.

When AceComm and AceSerializer are available through `LibStub`, Dibs serializes each logical protocol message through AceSerializer and sends it through AceComm. AceComm supplies addon-message registration and fragmentation without changing message fields, validation, transfer bounds, or trust rules. Standalone clients without Ace3 retain the legacy `DIBS1:<type>[:requestId:revision]` compatibility payload.

## Message classes

Suggested logical classes:

- HELLO
- DIGEST
- DELTA_REQUEST
- DELTA_CHUNK
- SNAPSHOT_REQUEST
- SNAPSHOT_CHUNK
- TX_PROPOSE
- TX_COMMIT
- TX_ACK
- REQUEST_STATE
- RELAY_HEARTBEAT
- RELAY_ELECTION

## Pre-Dib recovery

- `HELLO` announces feature support.
- `MANIFEST` lists the request owner's active request IDs and revisions.
- An eligible officer returns `FETCH` for missing or stale IDs.
- `TRANSFER_BEGIN`, `TRANSFER_CHUNK`, and `TRANSFER_END` are bounded by chunk count, payload size, and expiry.
- `REQUEST_ACK` records officer receipt of a request revision; it never authorizes an award or Dib spend.
- Data-bearing recovery is guild-scoped: an incoming request must come from its owner and be received by a verified GM/officer, while `FETCH` is accepted only from a verified GM/officer. Ordinary guild members cannot use recovery messages to read another player's stored requests.

Payloads containing live drops, candidates, votes, responses, or loot-session fields are rejected. Incoming request records must match the sender identity, retain immutable origin fields when updating known records, accept only newer revisions, and cannot introduce `fulfilled` state.

## Difficulty and acquisitions

Persisted request records include normalized `Normal`, `Heroic`, `Mythic`, or `UNKNOWN` difficulty. This field is part of active-request identity and is transferred with the request record. Award fulfillment applies an award difficulty only when the award context supplies one, retaining legacy matching for awards without difficulty.

Great Vault acquisitions are local, display-only SavedVariables records. They are not protocol payloads and never cause a request transition or ledger transaction.

## Transaction rules

Each committed transaction must have:

- protocolVersion
- transactionID
- seasonID
- actorGUID
- playerGUID
- timestamp/logical ordering metadata
- action
- payload
- optional referenceTransactionID

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
