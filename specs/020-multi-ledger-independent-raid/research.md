# Research: Multi-Ledger Management and Independent Raid Sessions

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Status**: Completed

## 1. Multi-Ledger Storage & Namespace Architecture

### Context
Currently, `Dibs.GetDB().ledger` maintains a single flat transaction list, player state table, and canonical distributed-ledger state for the active guild. To support multiple raid teams or schedules within the same guild, multiple isolated ledgers must coexist without data cross-contamination.

### Decision
Store multi-ledgers under `db.ledgers = { [ledgerId] = ledgerObject }` within the guild-scoped database partition (`DibsDB[guildKey]`), and maintain `db.activeLedgerId` as a local client pointer.

```lua
-- Structure of a GuildLedger
{
  id = "LDR-<timestamp>-<hash>", -- Unique ledger identifier
  name = "Main Roster",          -- User-friendly display name
  status = "APPROVED",           -- "PROPOSED" | "APPROVED" | "ARCHIVED"
  createdAt = 1776000000,
  createdBy = "OfficerName-Realm",
  approvedAt = 1776000500,
  approvedBy = "GMName-Realm",
  epoch = 1,
  transactions = {},             -- Append-only list of transactions
  playerStates = {},             -- Derived [seasonId][playerKey] balances
  canonical = {                  -- Canonical distributed state
    schema = 1,
    epoch = 1,
    nextSeq = 1,
    rootHash = "...",
    commits = {},
    transactionIndex = {},
    positions = {},
  },
  settings = {
    -- Ledger-specific rules or overrides if applicable
  }
}
```

### Migration & Backward Compatibility
- When reading `db.ledger` on clients updating from prior versions:
  - If `db.ledgers` does not exist or is empty and `db.ledger` contains data, migrate `db.ledger` into `db.ledgers["guild-primary"]` with `name = "Primary"`, `status = "APPROVED"`.
  - Set `db.activeLedgerId = "guild-primary"`.
  - Keep `db.ledger` as a compatibility proxy or redirect all `Dibs.Ledger` calls through `Dibs.Ledger.GetActiveLedgerId()`.

### Alternatives Considered
- *Separate SavedVariables tables for each ledger*: Rejected because WoW SavedVariables management is cleaner when all guild state remains within the existing guild-isolated partition (`DibsDB[guildKey]`).
- *A single transaction log with a `ledgerId` tag*: Rejected because computing balances and cryptographic commit roots would require full partition scans and could leak state between distinct ledgers. Physical separation in `db.ledgers[ledgerId]` ensures complete memory and hash isolation.

---

## 2. Officer Empowerment & GM Approval Protocol

### Context
Constitution Principle XI grants administrative authority to both the Guild Master (rank 0) and verified Officers. However, the current installation code (`Installation.lua`) and certain permission entries in `Permissions.lua` (`GM_ONLY_ACTIONS`) enforce GM-only checks for setup, settings modification, and cutover. This prevents officers from initializing raids when the GM is absent.

### Decision
1. **Officer Authority Alignment**:
   - Reclassify setup, season creation, rank configuration, and operational policy actions in `Permissions.lua` as `ADMIN_ACTIONS` accessible to both GMs and verified Officers.
   - Enable Officers to run `Installation.Initialize`. When run by an officer, the setup completes all pre-flight checks, baseline reconciliation, and marks the proposed guild ledger as `PROPOSED`.
2. **GM Approval Gate for Guild-Wide Ledgers**:
   - A proposed guild ledger requires explicit GM approval (`ledger.approve`) to transition from `PROPOSED` to `APPROVED`.
   - The GM interface exposes an "Approval Panel" listing all `PROPOSED` ledgers with their creator, timestamp, and configuration snapshot.
   - Once approved by the GM, an auditable `LEDGER_APPROVED` governance record is published, authorizing all guild members to synchronize the ledger.
   - If an unapproved ledger receives transactions from a rogue client, guild peers reject the sync packets because no valid GM `LEDGER_APPROVED` signature exists for that `ledgerId`.

### Alternatives Considered
- *Let officers approve official guild ledgers without GM*: Rejected because concurrent officers could create competing root ledgers (split-brain). GM approval maintains a single authoritative anchor for official guild accounting.
- *Blocking all officer setup until GM logs in*: Rejected because this is the exact operational bottleneck reported by users during guild testing.

---

## 3. Background Multi-Ledger Distributed Synchronization

### Context
In a multi-ledger guild, members might participate in one raid team or multiple teams (e.g. main raider on Tuesday, alt raider on Saturday). Synchronization must ensure that all approved guild ledgers stay up to date on all guild members' clients, regardless of which ledger is currently displayed on screen.

### Decision
1. **Ledger Catalog Digest (`LEDGER_CATALOG`)**:
   - Announce the set of approved ledgers via a periodic or on-demand catalog digest over `GUILD` chat:
     `{ type = "DIGEST", entityType = "LEDGER_CATALOG", ledgers = { [ledgerId] = { id, name, status, revision, rootHash } } }`.
2. **Scoping `LEDGER_DIGEST` with `ledgerId`**:
   - Extend `LEDGER_DIGEST` messages to carry `ledgerId`:
     `{ type = "LEDGER_DIGEST", entityType = "LEDGER", ledgerId = "LDR-...", entityId = tostring(epoch), revision = seq, rootHash = hash }`.
3. **Background Processing**:
   - When a peer receives a `LEDGER_DIGEST` for any `APPROVED` ledger, it verifies the root hash and missing transaction sequences.
   - It requests missing batches for that specific `ledgerId` via `DETAIL_FETCH` and applies them directly into `db.ledgers[ledgerId]`.
   - The UI does not reload; if the user is currently viewing the updated ledger, an event `DIBS_LEDGER_UPDATED(ledgerId)` fires to update displayed balances in-place.

### Alternatives Considered
- *Syncing only the active ledger*: Rejected because raiders who do not have the Saturday ledger selected would miss transactions and fall out of sync, requiring expensive full reconciliations later.

---

## 4. Independent / Standalone Raid Session

### Context
A raid leader (who may not be an officer or GM) wants to lead a pickup, alt, or community raid and track loot priority with Dibs, using standard RCLootCouncil voting. The session must not broadcast to the guild or affect official guild ledgers.

### Decision
1. **Local Session Container**:
   - Store independent raid data in `db.independentSessions[sessionId]` on the Master Looter's client:
     ```lua
     {
       sessionId = "IND-<timestamp>-<hash>",
       name = "Saturday Alt Raid",
       startedAt = 1776000000,
       endedAt = nil,
       startingPoints = 1, -- Configurable points per attendee
       balances = { ["Player-Realm"] = 1 },
       awards = {},        -- List of awards { itemID, winner, timestamp, dibsSpent }
       status = "ACTIVE",  -- "ACTIVE" | "CONCLUDED"
     }
     ```
2. **Network Silence (Zero Guild Broadcast)**:
   - When in Independent Mode, the Master Looter's client explicitly disables all `Sync.Send(..., "GUILD")` and `Sync.Send(..., "OFFICER")` calls for session accounting.
   - No ledger or digest messages are transmitted over guild channels.
3. **RCLootCouncil Integration for Non-Addon Users**:
   - The Master Looter configures RCLootCouncil with the standard "DIB" button (via existing `Dibs.RCLootCouncil` helpers).
   - When an item is awarded, RCLootCouncil fires `RCMLAwardSuccess`.
   - The Dibs adapter detects `mode == "INDEPENDENT"`:
     - It checks if the winner's response was "DIB".
     - It checks if the winner has remaining session points in `session.balances[winner]`.
     - It deducts 1 point from `session.balances[winner]` and appends an entry to `session.awards`.
     - Attendees only need vanilla RCLootCouncil; they do not need `RCLootCouncil_dibs`.
4. **Great Vault Display Integration**:
   - Great Vault data is read from `Dibs.CharacterEligibility` or cached guild evidence in read-only mode to display vault gear icons in the loot window, without writing any data.
5. **Reconciliation / Post-Raid Export**:
   - An authorized Officer can inspect past independent sessions via an "Import Independent Session" tab and selectively import awards into an approved guild ledger via `ProtectedActions.FinalizeAward`.

### Alternatives Considered
- *Relying on custom chat channels for independent raid sync*: Rejected because attendees without the addon cannot join or decode custom channels. Local Master Looter accounting with vanilla RCLootCouncil buttons provides 100% attendee compatibility.
