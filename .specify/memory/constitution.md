# Dibs Project Constitution

## I. World of Warcraft API Compliance

The addon MUST use only APIs and addon communication mechanisms permitted by the current World of Warcraft Retail client.

The addon MUST NOT automate protected gameplay actions, bypass protected UI restrictions, or require modification of Blizzard client files.

Combat safety is mandatory. Non-critical processing SHOULD be deferred when execution during combat could destabilize the UI.

## II. Dibs Are Not DKP

A Dib is not DKP and MUST NOT be implemented as a generic boss-kill currency.

The system MUST NOT assume:
- boss kills automatically grant points;
- receiving any item automatically consumes a Dib;
- the player with the largest numeric balance automatically wins loot.

Dib eligibility and consumption MUST be decided by explicit Dibs rules.

## III. Seasonal and Rank-Based Allocation

Dibs MUST be allocated by season.

Each season MUST support independent configurable allocations per guild rank.

Rank allocation values MUST be configuration data and MUST NOT be hard-coded into business logic.

A player's rank at the time of a ledger transaction MUST be preserved in that transaction.

Rank changes during a season MUST NOT silently rewrite historical allocations or historical transactions.

## IV. Append-Only Ledger and Auditability

The authoritative accounting model MUST be an append-only ledger.

Existing ledger transactions MUST NOT be deleted or rewritten to correct mistakes.

Corrections MUST be represented by new transactions such as:
- DIB_REFUNDED
- DIB_REVOKED
- DIB_ADMIN_ADJUSTMENT

Every authoritative transaction MUST contain enough information to audit:
- unique transaction ID;
- timestamp;
- season;
- player identity;
- player rank at transaction time;
- action;
- Dib quantity delta when applicable;
- related item when applicable;
- originating authorized actor/system;
- reason when administrative.

Balances MUST be derivable from ledger transactions.

## V. Player and Administrative Visibility

Players MUST be able to view:
- their current seasonal allocation;
- their current Dib balance;
- their active Pre-Dibs;
- their own Dib transaction history.

Authorized Officers and GMs MUST be able to view the complete Dib ledger and history for all players.

Active public Pre-Dib information MAY be visible guild-wide according to configuration.

Administrative-only metadata MUST NOT be exposed to normal players unless explicitly configured.

## VI. Two Supported Dib Workflows

The system MUST support both:

1. **Pre-Dib**
   - A player requests a Dib on a specific supported item before the item drops.
   - The request is logged and synchronized.
   - A Pre-Dib reservation does not consume a Dib until a qualifying award is finalized.
   - A player who does not win the item retains the active Pre-Dib unless a rule explicitly cancels it.

2. **Drop-Dib**
   - When no applicable rule blocks it, a player may request use of a Dib during the local loot session.
   - A Dib is consumed only after the qualifying item is actually awarded.

Both workflows MUST use the same seasonal ledger.

## VII. RCLootCouncil Compatibility

RCLootCouncil integration MUST be optional and implemented as an adapter/module.

The project MUST NOT modify RCLootCouncil core source files.

The Dibs core MUST remain usable when RCLootCouncil is not installed.

RCLootCouncil MAY:
- expose a DIB response;
- display Dib-related columns or status;
- provide local loot-award information;
- trigger local adapter events.

RCLootCouncil MUST NOT be the authoritative source of Dib balances or Dib history.

Live RCLootCouncil loot-session data MUST NOT be synchronized between separate raid groups.

## VIII. Encounter Journal Integration

Where technically supported by the current WoW Retail API, the addon SHOULD add a localized action such as "I want to DIB this" to supported Encounter Journal raid loot views.

The stored action MUST use stable internal identifiers, not localized display strings.

Localization MUST be separated from business logic.

## IX. Multi-Raid Operation

The addon MUST support multiple guild raid groups operating simultaneously.

No raid group is the exclusive source of truth.

Authorized Officers/GMs MAY create authoritative ledger transactions independently.

Cross-raid synchronization MUST include only guild Dib state such as:
- Dib grants/adjustments;
- Pre-Dib state;
- Dib consumption/refunds;
- finalized award history needed for Dib accounting/audit;
- synchronization metadata.

Cross-raid synchronization MUST NOT include:
- live item drops;
- current RCLootCouncil candidates;
- current RCLootCouncil votes;
- current loot-session state;
- live raid-specific loot discussions.

## X. Distributed Synchronization

Authoritative transactions MUST be:
- uniquely identifiable;
- immutable;
- idempotent;
- deduplicatable;
- order-tolerant where feasible;
- recoverable after clients reconnect.

Offline clients MUST be able to request missing state after reconnecting.

Synchronization SHOULD prefer delta synchronization and compact messages rather than repeatedly broadcasting the complete database.

The protocol MUST tolerate multiple authorized writers.

Last-write-wins MUST NOT be used for independent ledger transactions.

## XI. Authority and Trust

Normal player clients MUST NOT be authoritative for Dib balances.

Player requests such as Pre-Dib creation MUST be distinguishable from authoritative committed transactions.

Authorized Officer/GM clients or an explicitly configured authority mechanism MUST validate and commit authoritative changes.

Permission checks MUST be performed at the point where authoritative transactions are accepted.

## XII. Raid Relay

When multiple authorized officers are in the same raid, the addon SHOULD elect or select a single active relay for routine raid-to-player synchronization, with standby takeover when necessary.

Duplicate relay traffic MUST NOT result in duplicate ledger transactions.

## XIII. Data Ownership and Persistence

Dibs SavedVariables own the Dib ledger.

RCLootCouncil SavedVariables MUST NOT be required to reconstruct Dib balances.

Data formats MUST be versioned and migrations MUST preserve historical audit data.

## XIV. Public Repository Quality

The project MUST remain suitable for a public GitHub repository.

Secrets, private guild identifiers, personal data, test credentials, and private logs MUST NOT be committed.

Public documentation MUST distinguish implemented behavior from planned behavior.

Breaking protocol or SavedVariables changes MUST be documented.

## Governance

This constitution governs all specifications, plans, tasks, and implementations in this repository.

A feature that conflicts with a MUST requirement requires an explicit constitution amendment before implementation.

Architecture decisions affecting ledger integrity, synchronization, authority, RCLootCouncil independence, or cross-raid privacy MUST be reviewed against this constitution.
