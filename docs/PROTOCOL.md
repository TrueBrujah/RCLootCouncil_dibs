# Synchronization Protocol Notes

This document is intentionally implementation-neutral until `/speckit.plan` researches current WoW Retail addon messaging constraints.

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

## Security/trust note

WoW addon messaging is not a cryptographically trusted transport. Authorization must therefore be modeled explicitly and the threat model documented during planning.
