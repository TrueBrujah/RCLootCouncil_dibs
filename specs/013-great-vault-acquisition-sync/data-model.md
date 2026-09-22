# Data Model: Great Vault Acquisition Tracking and Guild Sync

## 1. Great Vault Acquisition

A guild-scoped record describing a reward claimed by one character. It is an eligibility evidence record, not a ledger transaction.

| Field | Type | Required | Rules |
|---|---|---:|---|
| `acquisitionId` | string | yes | Stable identity. Must remain unchanged after migration or sync. |
| `guildKey` | string | yes | Realm plus guild identity. Must match the active guild scope. |
| `playerName` | string | yes | Canonical claiming character identity. |
| `characterId` | string | preferred | Stable character identity when the client can resolve it. |
| `itemID` | integer | yes | Positive item identifier. |
| `itemLink` | string | no | Preserved when available; never fabricated as evidence. |
| `itemName` | string | no | Display value only; missing names remain unknown. |
| `itemLevel` | integer | no | Non-negative value when provided by the client. |
| `family` | enum | no | Semantic Dibs family such as `TOKEN`, `TOKEN_SET`, or `UNKNOWN`. |
| `rewardCategory` | string | no | Vault activity or reward category when available. |
| `difficulty` | enum/string | no | Normalized supported difficulty or `UNKNOWN`. |
| `upgradeTrack` | string | no | Track or tier label when available. |
| `seasonId` | string | no | Original active season, or absent when no season was active. |
| `resetId` | string | preferred | Weekly reset identity used for deduplication. |
| `claimedAt` | integer | yes | Claim time when known; manual records use entry time until confirmed. |
| `createdAt` | integer | yes | Local record creation time. |
| `source` | enum | yes | `GREAT_VAULT`, `VAULT_MANUAL`, `VAULT_LEGACY`, or equivalent localized labels. |
| `verificationState` | enum | yes | `AUTOMATIC_CONFIRMED`, `MANUAL_RECORDED`, `LEGACY_RECORDED`, `UNVERIFIED`, `OFFICER_CONFIRMED`, `REJECTED`, or `REFERENCE_ONLY`. |
| `evidenceState` | enum | yes | `COMPLETE`, `PARTIAL`, `AMBIGUOUS`, or `MISSING`. |
| `evidenceId` | string | no | Retail claim, manual evidence, or review reference when available. |
| `evidence` | bounded table | no | Non-live evidence fields only; must exclude candidates, votes, responses, and session data. |
| `review` | bounded table | no | Latest decision status, actor, timestamp, reason, and prior status. |
| `revision` | integer | yes | Monotonic record revision for synchronization. |
| `contentHash` | string | preferred | Hash of the canonical sync projection. |
| `syncState` | enum | yes | `LOCAL`, `ANNOUNCED`, `SYNCED`, `PENDING`, `CONFLICT`, or `REJECTED`. |
| `migration` | bounded table | no | Source schema and migration timestamp for legacy records. |

### Invariants

- An acquisition never creates or modifies a Dibs ledger transaction.
- `REJECTED` and `REFERENCE_ONLY` records never count as confirmed eligibility evidence.
- `MANUAL_RECORDED`, `LEGACY_RECORDED`, and `UNVERIFIED` records follow the active unknown-data policy.
- `AUTOMATIC_CONFIRMED` requires sufficient claim evidence; `OFFICER_CONFIRMED` requires verified GM/Officer authority and a reason.
- Immutable identity fields include `acquisitionId`, `guildKey`, `playerName`, `characterId` when verified, original item identity, original `claimedAt`, and original source evidence.
- A later review appends or records a decision transition; it does not erase original evidence.
- `CATALYST` remains excluded from Dibs eligibility even when a Vault record contains a related item.

## 2. Acquisition Status Transitions

Allowed transitions are intentionally narrow:

```text
MANUAL_RECORDED -> OFFICER_CONFIRMED
MANUAL_RECORDED -> REJECTED
MANUAL_RECORDED -> REFERENCE_ONLY
LEGACY_RECORDED -> OFFICER_CONFIRMED
LEGACY_RECORDED -> REJECTED
LEGACY_RECORDED -> REFERENCE_ONLY
UNVERIFIED -> OFFICER_CONFIRMED
UNVERIFIED -> REJECTED
UNVERIFIED -> REFERENCE_ONLY
AUTOMATIC_CONFIRMED -> REFERENCE_ONLY (authorized correction only)
AUTOMATIC_CONFIRMED -> REJECTED (authorized correction only)
```

A duplicate event remains at the existing state and returns an idempotent result. A conflicting event with the same identity is not a transition; it creates a review conflict.

## 3. Weekly Reset Context

The reset context distinguishes separate Vault periods:

- `resetId`: stable client-provided reset identity when available;
- `resetStartedAt`: optional reset start timestamp;
- `resetEndsAt`: optional reset end timestamp;
- `resetSource`: `RETAIL`, `DERIVED`, or `UNKNOWN`;
- `confidence`: whether the reset identity is confirmed or inferred.

A derived reset may help display and review but must not be treated as a stable deduplication key when the client does not provide enough evidence.

## 4. Synchronization Digest Entry

A digest entry is safe metadata, not full acquisition evidence:

| Field | Rules |
|---|---|
| `acquisitionId` | Stable identity, bounded length. |
| `revision` | Positive integer within protocol bounds. |
| `contentHash` | Hash of the canonical permitted detail projection. |
| `playerKey` | Canonical identity only when the receiver's visibility scope permits it. |
| `claimedAt` | Optional ordering hint. |
| `verificationState` | Safe status summary. |
| `terminal` | Whether the record is rejected/reference-only and needs no further detail. |

Digests must be bounded and must not include item-session, vote, candidate, or private Officer evidence fields.

## 5. Sync Transfer State

A bounded transfer uses existing transport limits and contains:

- sender and receiver guild scope;
- transfer identity;
- entity type and acquisition identity;
- revision and content hash;
- chunk count and bounded chunks when serialization requires it;
- expiry timestamp;
- apply result: `APPLIED`, `IDEMPOTENT_REPLAY`, `STALE_REVISION`, `CONFLICT`, `REJECTED`, or a recoverable validation error.

Incomplete or expired transfers are discarded without applying any acquisition.

## 6. Review Decision

A review decision contains:

- `decisionId`;
- `acquisitionId`;
- previous status;
- resulting status;
- verified actor identity;
- timestamp;
- required reason;
- evidence references used by the decision;
- optional correction scope and expiry.

Review decisions are guild-scoped and append-only. They may change eligibility interpretation but never rewrite the original claim evidence or ledger.

## 7. Visibility Projections

### Player projection

Contains the player's own character, item, date, source, verification state, sync state, and eligibility explanation. It excludes unrelated player identities, complete evidence, Officer notes, and private conflict details.

### Officer projection

Contains the complete guild-scoped record, evidence state, source, reset context, review history, content hash, sync conflict, and audit actor after permission validation.

### Digest projection

Contains only bounded identity, revision, hash, safe status, and ordering metadata needed for anti-entropy recovery.
