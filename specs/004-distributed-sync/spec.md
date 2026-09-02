# Feature Specification: RCLootCouncil_dibs Distributed Multi-Raid Synchronization

## Goal

Keep Dib accounting, Pre-Dib state, and finalized award history consistent when two or more guild raids operate simultaneously.

## Network model

- Authorized officer/GM clients form the authoritative synchronization backbone.
- Normal player clients are non-authoritative.
- Each raid may have an active relay that distributes player-visible Dib state locally.
- Separate raid groups do not exchange live loot-session information.

## Cross-raid data allowed

- Dib allocations and adjustments
- Pre-Dib request state
- DIB_USED / DIB_REFUNDED state
- finalized item award history associated with Dib accounting
- revision/digest/sync metadata

## Cross-raid data forbidden

- live item drops
- loot candidates
- council votes
- current response state
- active loot-session payloads

## User Stories

### P1 - Simultaneous officers

Two officers in different raid groups can append different valid transactions without overwriting each other.

### P1 - Reconnect catch-up

An officer who reconnects later can retrieve missing transactions or a trusted snapshot.

### P1 - Deduplication

Receiving the same transaction multiple times does not apply it multiple times.

### P2 - Raid relay

One active relay per raid distributes player-visible updates locally while standby officers can take over.

### P2 - Divergence detection

Authorized clients can detect inconsistent ledger state and request reconciliation.

## Protocol principles

- append-only transaction replication
- unique transaction IDs
- idempotent apply
- delta sync preferred
- full sync/snapshot available for recovery
- protocol version included
