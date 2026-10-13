# Contract: Multi-Ledger Synchronization Protocol

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Layer**: Network / Distributed Synchronization (`Dibs.SyncV2`)

## 1. Catalog Digest (`LEDGER_CATALOG`)

Broadcast periodically or upon ledger state change over `GUILD` chat channel to synchronize the set of approved ledgers.

```json
{
  "type": "DIGEST",
  "entityType": "LEDGER_CATALOG",
  "revision": 3,
  "contentHash": "CAT-3a8f10b2",
  "protocolState": "ENFORCED",
  "ledgers": {
    "guild-primary": {
      "id": "guild-primary",
      "name": "Main Roster",
      "status": "APPROVED",
      "epoch": 1,
      "revision": 45,
      "rootHash": "LDR-99af310c"
    },
    "LDR-1776000100-a1b2c3d4": {
      "id": "LDR-1776000100-a1b2c3d4",
      "name": "Weekend Alts",
      "status": "APPROVED",
      "epoch": 1,
      "revision": 12,
      "rootHash": "LDR-11ec82bb"
    }
  }
}
```

## 2. Scoped Ledger Digest (`LEDGER_DIGEST`)

Each approved ledger emits its own digest to announce transaction sequence progress.

```json
{
  "type": "LEDGER_DIGEST",
  "entityType": "LEDGER",
  "ledgerId": "LDR-1776000100-a1b2c3d4",
  "entityId": "1",
  "revision": 12,
  "lastSeq": 12,
  "rootHash": "LDR-11ec82bb",
  "contentHash": "LDR-11ec82bb"
}
```

## 3. Detail Fetch & Transfer Envelopes

When a client detects a sequence gap for any approved `ledgerId`:

### 3.1 `DETAIL_FETCH` Request
```json
{
  "type": "DETAIL_FETCH",
  "requests": [
    {
      "entityType": "LEDGER_BATCH",
      "ledgerId": "LDR-1776000100-a1b2c3d4",
      "startSeq": 8,
      "endSeq": 12
    }
  ]
}
```

### 3.2 `TRANSFER_BEGIN` Response
```json
{
  "type": "TRANSFER_BEGIN",
  "entityType": "LEDGER_BATCH",
  "ledgerId": "LDR-1776000100-a1b2c3d4",
  "transferId": "XFER-58291",
  "totalChunks": 2,
  "totalBytes": 1420
}
```

### 3.3 Integrity Rule
A client MUST discard any incoming ledger batch or transaction payload whose `ledgerId` does not match an `APPROVED` ledger in `db.governance.approvedLedgers`.

## 4. Ledger-Scoped Pre-Dib Synchronization

Each approved ledger has an independent `PREDIB_INDEX` digest and Pre-Dib request history.
The digest and its `DETAIL_FETCH` entries identify the target `ledgerId`; a request detail
transfer carries the same `ledgerId` in its transfer envelope and request record. Receivers
MUST reject a scope mismatch and MUST verify that the target ledger is approved before
fetching or applying the request.

For backward compatibility, a missing `ledgerId` on a legacy Pre-Dib digest or request
transfer means `guild-primary` only. An alternate-ledger request MUST NOT be applied to the
currently selected ledger merely because that ledger is active locally.

## 5. Ledger Deletion Tombstones

A Guild Master may delete only an archived, non-default ledger that is not the active ledger
after explicit confirmation and only when synchronization is available. The local client
records a governance authorization before attempting the guild broadcast. If the send fails,
the operation reports `SYNC_PENDING`, retains the archived ledger for retry, and MUST NOT
report deletion success. After a successful send, it records the deletion and applies a durable
local tombstone.

Peers MUST record the verified Guild Master deletion in their governance audit before applying
the tombstone. Repeated deletion messages are idempotent. Clients periodically rebroadcast
retained tombstones that have not recently been sent, so a temporary disconnect does not make
the deletion depend on the ledger still being present locally.

Ledger approval follows the same explicit-result rule: governance approval is recorded before
the local ledger changes to `APPROVED`, and a failed catalog send is reported as `SYNC_PENDING`.
The approved catalog is periodically rebroadcast to reconcile missed updates.
