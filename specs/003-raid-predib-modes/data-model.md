# Data Model: Raid Pre-Dib Modes

## Pre-Dib Mode Policy

| Field | Meaning | Validation |
|---|---|---|
| `seasonId` | Season governed by the policy | References an active or historical season |
| `mode` | `WILD_OPEN` or `ENCOUNTER` | Required; only authorized actors may change it |
| `changedAt` | Time the mode became active | Recorded for audit |
| `changedBy` | Authorized actor identity | Required for changes |

A policy change applies to future validation only. It does not rewrite existing requests or ledger rows.

## Pre-Dib Request Extensions

| Field | Meaning | Validation |
|---|---|---|
| `requestId` | Stable request identity | Immutable and globally deduplicated |
| `revision` | Owner-controlled mutable-state version | Increments on permitted request state changes |
| `modeAtCreation` | Mode used at initial validation | Immutable after creation |
| `validationContext` | Raid, encounter, and supported-loot context | Required for Encounter mode; absent is valid for Wild Open |
| `delivery` | Local acknowledgement metadata | Informational; never grants authority |
| `delivery.state` | `PENDING` or `ACKNOWLEDGED` | Changes only from protocol acknowledgement |
| `delivery.lastAcknowledgedRevision` | Latest officer-confirmed revision | Cannot exceed request revision |
| `delivery.acknowledgedBy` | Officer identity | Required when acknowledged |
| `delivery.acknowledgedAt` | Acknowledgement time | Required when acknowledged |
| `difficulty` | Normal, Heroic, Mythic, or `UNKNOWN` | Derived by mode-specific rule |

Request lifecycle remains `pending -> confirmed -> fulfilled|cancelled|invalidated`. A synchronized request may update only when its revision is newer. Fulfillment with an award reference remains controlled by the authoritative award workflow.

## Acquired Item Record

| Field | Meaning | Validation |
|---|---|---|
| `acquisitionId` | Stable ownership record identity | Required and deduplicated |
| `playerId` | Acquiring player identity | Required |
| `itemID` | Stable item identity | Required |
| `difficulty` | Normal, Heroic, Mythic, or `UNKNOWN` | Captured when known |
| `source` | `VAULT` | Required |
| `acquiredAt` | Recorded acquisition time | Required |

Acquired item records are display-only ownership data. They never alter requests, balances, or the append-only ledger.

## Sync Transfer

| Field | Meaning |
|---|---|
| `protocolVersion` | Compatibility version |
| `messageType` | HELLO, MANIFEST, FETCH, TRANSFER_BEGIN, TRANSFER_CHUNK, TRANSFER_END, REQUEST_ACK |
| `transferId` | Stable identity for one chunked transfer |
| `senderId` | Sender identity used for validation and diagnostics |
| `requestId` | Stable request reference where applicable |
| `revision` | Request revision where applicable |
| `chunkIndex`, `chunkCount` | Ordered chunk metadata |
| `checksum` | Transfer integrity value |
| `expiresAt` | Bounded reassembly lifetime |

Transfer buffers are runtime-only and expire. Persisted request data remains the source for reconnect recovery.

## Reminder Event

| Field | Meaning |
|---|---|
| `reminderId` | Stable reminder identity for deduplication |
| `seasonId` | Current season at send time |
| `senderId` | Authorized sender identity |
| `sentAt` | Send time |
| `raidContext` | Current raid identity when available |
| `message` | Localized, non-accounting reminder text |

Reminders do not change requests or ledger data.

## Player Prompt Preference

| Field | Meaning |
|---|---|
| `raidEntryDibPromptsEnabled` | Player-local opt-in flag, default false |
| `lastPromptedRaid` | Runtime/session de-duplication signature |
| `pendingPromptContext` | Latest raid/boss context deferred for combat safety |

The preference is local to the player and is never synchronized.
