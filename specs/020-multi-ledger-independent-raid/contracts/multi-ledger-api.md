# Contract: Multi-Ledger Management API

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Layer**: Domain / Storage (`Dibs.Ledger` & `Dibs.MultiLedger`)

## 1. MultiLedger Module Facade (`Dibs.MultiLedger`)

### 1.1 `Dibs.MultiLedger.GetLedgers()`
Returns a list of all known guild ledgers.

- **Inputs**: None
- **Returns**: `table` array of `GuildLedgerSummary`:
  ```lua
  {
    {
      id = "guild-primary",
      name = "Primary",
      status = "APPROVED",
      createdAt = 1776000000,
      createdBy = "Player-Realm",
      approvedAt = 1776000000,
      approvedBy = "GM-Realm",
      isDefault = true,
      transactionCount = 142,
    },
    ...
  }
  ```

### 1.2 `Dibs.MultiLedger.GetActiveLedgerId()`
Returns the identifier of the currently active/selected ledger for the local client.

- **Inputs**: None
- **Returns**: `string` ledgerId (defaults to `"guild-primary"`)

### 1.3 `Dibs.MultiLedger.SetActiveLedger(ledgerId)`
Switches the local client's active ledger context. Emits `DIBS_ACTIVE_LEDGER_CHANGED`.

- **Inputs**:
  - `ledgerId` (`string`): The ID of the ledger to activate.
- **Returns**: `boolean ok`, `string|nil reasonCode`
- **Error Codes**:
  - `LEDGER_NOT_FOUND`: No ledger with `ledgerId` exists.
  - `LEDGER_UNAPPROVED`: Cannot activate a `PROPOSED` ledger for live raid operations.

### 1.4 `Dibs.MultiLedger.ProposeLedger(actor, name, options)`
Proposes a new guild ledger. Can be invoked by any verified Officer or the Guild Master.

- **Inputs**:
  - `actor` (`string|table|nil`): Proposing actor.
  - `name` (`string`): Desired name for the ledger (1-50 chars).
  - `options` (`table|nil`): Initial rules/settings overrides.
- **Returns**: `table` result: `{ ok = boolean, ledgerId = string|nil, reasonCode = string|nil }`
- **Permissions**: Requires `ledger.propose` (Officer or GM).
- **Audit**: Emits `LEDGER_PROPOSED` event.

### 1.5 `Dibs.MultiLedger.ApproveLedger(actor, ledgerId)`
Approves a proposed ledger, transitioning it to `APPROVED` and publishing a governance approval record.

- **Inputs**:
  - `actor` (`string|table|nil`): Approving actor (MUST be verified Guild Master).
  - `ledgerId` (`string`): Ledger ID to approve.
- **Returns**: `table` result: `{ ok = boolean, reasonCode = string|nil }`
- **Permissions**: Requires `ledger.approve` (GM only).
- **Audit**: Emits `LEDGER_APPROVED` governance record and triggers `LEDGER_CATALOG` broadcast.

### 1.6 `Dibs.MultiLedger.ArchiveLedger(actor, ledgerId)`
Archives an existing ledger, rendering it read-only.

- **Inputs**:
  - `actor` (`string|table|nil`): Archiving actor (GM only).
  - `ledgerId` (`string`): Ledger to archive.
- **Returns**: `table` result: `{ ok = boolean, reasonCode = string|nil }`
- **Permissions**: Requires `ledger.archive` (GM only).

### 1.7 `Dibs.MultiLedger.DeleteLedger(actor, ledgerId, options)`
Permanently deletes a non-default ledger after explicit confirmation.

- **Inputs**:
  - `actor` (`string|table|nil`): Deleting actor (verified GM only).
  - `ledgerId` (`string`): Ledger to delete.
  - `options.confirmed` (`boolean`): MUST be `true`.
- **Returns**: `table` result: `{ ok = boolean, reasonCode = string|nil }`
- **Preconditions**: The local ledger MUST exist and be `ARCHIVED`; the default ledger is never deletable.
- **Audit and sync**: Records `LEDGER_DELETED` and broadcasts an idempotent `LEDGER_DELETE` tombstone.
- **Remote convergence**: After the transport validates the tombstone sender as the current GM,
  peers MUST retain the tombstone and remove the ledger even when their local copy is still
  `APPROVED` or has not arrived yet. Later stale catalog digests MUST NOT recreate that ledger.

---

## 2. Updated `Dibs.Ledger` Signature Contracts

All existing `Dibs.Ledger` methods are updated to accept an optional trailing `ledgerId` parameter. When omitted, `Dibs.MultiLedger.GetActiveLedgerId()` is used as the default target.

```lua
-- Examples:
Dibs.Ledger.GetBalance(playerName, seasonId, ledgerId)
Dibs.Ledger.GetAllTransactions(ledgerId)
Dibs.Ledger.AppendTransaction(transaction, ledgerId)
Dibs.Ledger.GetCanonicalState(ledgerId)
```

Backward compatibility guarantee: Calling `Dibs.Ledger.GetAllTransactions()` without `ledgerId` operates seamlessly on the currently active ledger.
