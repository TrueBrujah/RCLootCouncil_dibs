# Data Model: Multi-Ledger Management and Independent Raid Sessions

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Status**: Draft

## 1. Entities

### 1.1 GuildLedger

A versioned, append-only accounting container bound to a guild namespace (`realm-guildName`). Multiple guild ledgers can coexist within the same guild database partition.

| Field | Type | Description | Invariant / Validation |
|---|---|---|---|
| `id` | `string` | Unique ledger identifier (e.g. `LDR-1776000000-a1b2c3d4`) | Must match `^LDR%-%d+%-%x+$` or `^guild%-primary$` |
| `name` | `string` | Human-readable ledger name (e.g. "Mythic Team", "Weekend Alts") | 1-50 UTF-8 characters, trimmed |
| `status` | `string` | Lifecycle state: `"PROPOSED"`, `"APPROVED"`, `"ARCHIVED"` | Valid status enum |
| `createdAt` | `number` | Unix timestamp of ledger creation | Positive integer |
| `createdBy` | `string` | Canonical name-realm of creating officer/GM | Valid canonical player identifier |
| `approvedAt` | `number \| nil` | Unix timestamp when GM approved the ledger | Required if status is `"APPROVED"` |
| `approvedBy` | `string \| nil` | Canonical name-realm of the approving GM | Must have GM rank at `approvedAt` |
| `epoch` | `number` | Ledger sequence epoch | Positive integer, default 1 |
| `transactions` | `table` | Array of append-only ledger transactions | Validated via `Dibs.Ledger` schema |
| `playerStates` | `table` | Dictionary of `[seasonId][playerKey]` cached balances | Fully derivable from transactions |
| `canonical` | `table` | Distributed state (commits, rootHash, nextSeq, transactionIndex) | Complies with distributed protocol V2 |
| `settings` | `table` | Optional ledger-specific rule overrides (e.g., Pre-Dib mode) | Table, defaults to guild global settings |

#### Lifecycle State Transitions:
```text
[Officer Proposes] ----> PROPOSED ----> [GM Approves] ----> APPROVED ----> [GM Archives] ----> ARCHIVED
                            |                                  ^
                            v                                  |
                   [GM Declines / Deletes]                     |
                                                               |
[GM Direct Creation] ------------------------------------------+
```

---

### 1.2 LedgerApprovalRecord

A governance record created when the Guild Master approves a proposed ledger or revokes/archives an active ledger.

| Field | Type | Description | Invariant / Validation |
|---|---|---|---|
| `recordId` | `string` | Unique approval record ID (`APR-%d+-%x+`) | Unique within governance |
| `ledgerId` | `string` | Identifier of the approved ledger | Refers to an existing `GuildLedger` |
| `ledgerName` | `string` | Name of the ledger at approval time | String |
| `action` | `string` | `"LEDGER_APPROVED"`, `"LEDGER_REVOKED"`, `"LEDGER_ARCHIVED"` | Valid approval action |
| `gmNameRealm` | `string` | Canonical identifier of the approving GM | Must verify as current GM |
| `gmMemberKey` | `string` | Member key from roster snapshot | Matches roster record |
| `timestamp` | `number` | Unix timestamp of approval | Positive integer |
| `parentHash` | `string` | Preceding governance hash | Ensures immutable hash chain |
| `recordHash` | `string` | Cryptographic content hash of the approval record | Derived via `Governance.contentHash` |

---

### 1.3 IndependentRaidSession

An ephemeral or locally persistent raid session operated by a Master Looter for a non-official, alt, or community raid. It operates without emitting guild-wide synchronization traffic.

| Field | Type | Description | Invariant / Validation |
|---|---|---|---|
| `sessionId` | `string` | Unique session identifier (`IND-%d+-%x+`) | Must match `^IND%-%d+%-%x+$` |
| `name` | `string` | Session display name (e.g. "Pug Raid Heroic") | 1-60 characters |
| `startedAt` | `number` | Unix timestamp of session start | Positive integer |
| `endedAt` | `number \| nil` | Unix timestamp when session concluded | Nil while active |
| `masterLooter` | `string` | Canonical name-realm of the session ML | Current player |
| `startingPoints` | `number` | Configurable starting points per attendee (default 1) | Positive integer (1-10) |
| `balances` | `table` | Dictionary of `[playerKey] = remainingPoints` | Non-negative integer |
| `awards` | `table` | Array of awards finalized during the session | Ordered list of session awards |
| `status` | `string` | `"ACTIVE"`, `"CONCLUDED"`, `"RECONCILED"` | Valid status enum |
| `localOnly` | `boolean` | Flag enforcing zero network broadcast | Always `true` |

#### Session Award Object (`awards[i]`):
| Field | Type | Description |
|---|---|---|
| `awardId` | `string` | Unique session award identifier |
| `timestamp` | `number` | Award timestamp |
| `recipient` | `string` | Canonical name-realm of winner |
| `itemID` | `number` | Item ID awarded |
| `itemLink` | `string` | Full item link |
| `response` | `string` | Winner's RCLootCouncil response (e.g. "DIB", "Major Upgrade") |
| `dibsSpent` | `number` | Points consumed (1 for qualifying DIB, 0 for regular award) |
| `reconciled` | `boolean` | Whether this award has been imported into an official guild ledger |

---

### 1.4 LedgerCatalogManifest

The network payload used in background distributed synchronization to broadcast the catalog of approved guild ledgers.

| Field | Type | Description |
|---|---|---|
| `type` | `string` | Constant `"DIGEST"` |
| `entityType` | `string` | Constant `"LEDGER_CATALOG"` |
| `revision` | `number` | Monotonically increasing revision of the ledger catalog |
| `ledgers` | `table` | Dictionary of `[ledgerId] = { id, name, status, revision, rootHash }` |
| `activeLedgerId` | `string` | Primary/default guild ledger identifier |
| `contentHash` | `string` | Content hash of the catalog state |

---

## 2. Relationships

```text
GuildRoot (realm-guildName)
  │
  ├── db.ledgers [1..*]
  │     ├── GuildLedger ("guild-primary") [APPROVED]
  │     │     ├── Transactions [0..*] (Append-only)
  │     │     └── PlayerStates [seasonId][playerKey]
  │     │
  │     ├── GuildLedger ("LDR-1776000000-...") [PROPOSED]
  │     └── GuildLedger ("LDR-1776000100-...") [APPROVED]
  │           ├── Transactions [0..*] (Append-only)
  │           └── PlayerStates [seasonId][playerKey]
  │
  ├── db.governance.records [1..*]
  │     └── LedgerApprovalRecord [0..*] (GM Signatures)
  │
  ├── db.independentSessions [0..*] (Local-only, ML machine)
  │     └── IndependentRaidSession ("IND-...")
  │           ├── Balances [playerKey]
  │           └── Awards [0..*]
  │
  └── db.activeLedgerId (Local client UI/live raid pointer)
```

## 3. Data Integrity & Validation Rules

1. **Isolation of Ledger Transactions**: Transactions appended to `db.ledgers[id1]` MUST NEVER modify, rewrite, or recalculate balances for `db.ledgers[id2]`.
2. **GM Authority for Approval**: A ledger with status `PROPOSED` MUST NOT accept authoritative awards or consume points until a valid `LedgerApprovalRecord` signed by the verified GM exists in governance records.
3. **Audit Trail Completeness**: Every proposed, approved, or archived ledger record, and every independent session award, MUST record `actor`, `timestamp`, and `action`.
4. **Independent Raid Network Invariant**: In independent mode, no `Sync.Send` calls of type `LEDGER_DIGEST`, `LEDGER_CATALOG`, or `AWARD_COMMIT` may be transmitted over `GUILD` or `OFFICER` channels.
