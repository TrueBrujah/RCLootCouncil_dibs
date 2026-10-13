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
