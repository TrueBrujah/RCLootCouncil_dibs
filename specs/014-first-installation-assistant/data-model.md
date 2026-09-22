# Data Model: First Installation Assistant

## SetupCheck

Transient projection only; not persisted or synchronized.

| Field | Type | Required | Rules |
|---|---|---:|---|
| `id` | string | yes | Stable check identifier such as `season` or `rclootcouncil`. |
| `state` | enum | yes | `ready`, `blocked`, `degraded`, `unavailable`, or `skipped`. |
| `required` | boolean | yes | Whether failure blocks `READY_FOR_RAID`. |
| `reasonCode` | string/nil | no | Stable diagnostic code. |
| `impact` | string | yes | Human-readable consequence. |
| `remediation` | string | yes | Next action or explanation. |
| `source` | string | yes | Existing service that supplied the observation. |

## SetupReport

Transient aggregate returned by the assistant.

| Field | Type | Required | Rules |
|---|---|---:|---|
| `status` | enum | yes | `READY_FOR_RAID`, `NEEDS_ATTENTION`, `UNAVAILABLE`, or `DENIED`. |
| `actorRole` | string | yes | Current verified presentation role. |
| `checks` | array | yes | Bounded list of `SetupCheck` records. |
| `blockingCount` | number | yes | Count of required non-ready checks. |
| `dryRun` | table/nil | no | Last transient dry-run result only. |
| `checkedAt` | number | yes | Runtime observation time. |

## SetupAction

Input to an existing protected operation; never an authority record.

| Field | Type | Required | Rules |
|---|---|---:|---|
| `actionId` | string | yes | Must be in the existing ProtectedActions allowlist. |
| `payload` | table | yes | Canonical service values only. |
| `actor` | string/nil | no | Resolved by existing permission checks. |
| `source` | string | yes | Must identify the assistant caller. |

## State Rules

- `READY_FOR_RAID` is allowed only when all required checks are `ready`.
- Optional unavailable checks may coexist with `READY_FOR_RAID` when standalone operation remains valid.
- `DENIED` is returned for a player requesting administrative details.
- Reports are recomputed; no completion state is persisted.
