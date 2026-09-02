# Feature Specification: RCLootCouncil_dibs Core

## Goal

Implement the independent core data model and rules engine for seasonal, rank-based Dibs without requiring RCLootCouncil or Encounter Journal integration.

## User Stories

### P1 - Seasonal allocation by guild rank

As a GM, I can create/select a season and configure a Dib allocation for each supported guild rank so that different ranks may receive different numbers of Dibs.

### P1 - Player balance

As a player, I can see my seasonal allocation, used/refunded Dib transactions, and derived remaining balance.

### P1 - Immutable accounting

As an officer, every grant, use, refund, and correction is recorded as a new immutable transaction so that the history can be audited.

### P2 - Rank changes

As an officer, a player's rank change during a season does not silently rewrite historical data.

## Initial entities

- Season
- RankRule
- PlayerSeason
- DibTransaction
- PermissionPolicy

## Initial authoritative transaction types

- SEASON_ALLOCATION
- DIB_GRANTED
- DIB_USED
- DIB_REFUNDED
- DIB_REVOKED
- DIB_ADMIN_ADJUSTMENT

## Requirements

- Balances are derived from transactions.
- Transaction IDs are globally unique enough for addon synchronization.
- Transaction application is idempotent.
- Core APIs do not depend on RCLootCouncil.
- SavedVariables schema is versioned.
- No hard-coded guild rank allocations.

## Out of scope

- Encounter Journal modifications
- RCLootCouncil integration
- Network synchronization
- UI polish
