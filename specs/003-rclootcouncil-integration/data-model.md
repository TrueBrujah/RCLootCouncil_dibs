# Data Model: RCLootCouncil Permission Authority

## AuthorityDecision (ephemeral)

| Field | Type | Rules |
|---|---|---|
| `allowed` | boolean | Required |
| `authority` | enum | `rclootcouncil`, `standalone`, `none` |
| `availability` | enum | `absent`, `operational`, `degraded` |
| `actionId` | string | Protected action identifier |
| `actorId` | string | Canonical actor identity |
| `reasonCode` | string | Stable machine code |
| `diagnostic` | string | Safe user-facing explanation |

## ProtectedAction command

| Field | Type | Rules |
|---|---|---|
| `actionId` | string | One of supported protected action keys |
| `actor` | any | Canonicalized by Permissions |
| `payload` | table | Action-specific validated fields |

Lifecycle: `requested -> authorized -> business-validated -> committed|rejected`.

## StandaloneAdminEvent (persisted, append-only)

| Field | Type | Rules |
|---|---|---|
| `eventId` | string | Unique ID |
| `adminId` | string | Canonical target identity |
| `adminName` | string | Display name snapshot |
| `action` | enum | `APPOINTED`, `REVOKED` |
| `actorId` | string | Must be verified guild master |
| `createdAt` | number | Unix timestamp |
| `reason` | string | Optional note |

## Ledger Transaction (persisted, append-only)

| Field | Type | Rules |
|---|---|---|
| `transactionId` | string | Unique and idempotent |
| `type` | enum | Allocation/grant/use/refund/revoke/adjust |
| `playerId` | string | Canonical player identity |
| `playerName` | string | Snapshot display name |
| `seasonId` | string | Season reference |
| `amount` | number | Signed Dib delta |
| `actorId` | string | Authorized actor or system origin |
| `playerRank` | number | Rank snapshot at write time |
| `awardRef` | string | Optional finalized-award idempotency key |
| `itemID` | number | Optional related item |
| `reason` | string | Optional business/admin reason |
| `createdAt` | number | Unix timestamp |

## CandidateDibStatus (ephemeral)

| Field | Type | Rules |
|---|---|---|
| `playerName` | string | Candidate player |
| `itemID` | number | Item in local session |
| `balance` | number | Derived from Dibs ledger |
| `hasPreDib` | boolean | Confirmed request for candidate+item |
| `canUseDib` | boolean | Eligibility with pre-dib priority gate |
| `status` | enum | `none`, `pre-dib`, `dib-available`, `ineligible` |

## Sync snapshot constraints

Snapshots may include ledger transactions and pre-dib records, but must reject live loot-session fields such as candidates, votes, responses, lootTable, or session objects.
