# Data Model: Turnkey Guided Setup

The feature adds projections and per-character navigation preferences only. It does not
add an authoritative guild data store.

## Setup Profile

Represents a documented recommended starting configuration.

| Field | Meaning | Validation |
|-------|---------|------------|
| `id` | Stable profile identifier | One of `progression`, `broad`, `custom` |
| `label` | Localized display name | Non-empty |
| `summary` | Short intended-use explanation | Non-empty |
| `benefits` | Reasons the profile is useful | Ordered list |
| `changes` | Settings the profile may apply | Ordered list |
| `preserves` | Data/settings explicitly not changed | Ordered list |
| `presetKey` | Existing preset selected by the profile | Present only for recommended profiles |

Profiles are static definitions. They are not saved as guild policy and do not become
an additional source of truth.

## Setup Preview

Represents the effects expected before confirmation.

| Field | Meaning |
|-------|---------|
| `profileId` | Selected profile |
| `actions` | Ordered prospective actions |
| `preserved` | Existing state guaranteed not to be changed |
| `deferred` | Actions requiring another authority or unavailable context |
| `canApply` | Whether the current actor may run at least one safe action |

Each action contains an identifier, localized title, explanation, expected outcome,
authority note, and current disposition (`APPLY`, `ALREADY_READY`, `DEFERRED`, or
`ADVANCED_ONLY`).

## Setup Application Result

Represents one explicit apply attempt.

| Field | Meaning |
|-------|---------|
| `ok` | True only when every applicable action succeeded or was already ready |
| `profileId` | Applied profile |
| `actions` | Ordered per-action outcomes |
| `reasonCode` | Overall failure reason when `ok` is false |

Per-action outcomes are `APPLIED`, `ALREADY_READY`, `DEFERRED`, or `FAILED`. Failures
retain their specific reason and never become success-shaped defaults.

## Setup Stage

The per-character workflow position.

| Value | Purpose |
|-------|---------|
| `choose` | Select and understand a profile |
| `configure` | Review and explicitly apply changes |
| `verify` | Inspect authoritative current readiness and correct issues |

The stage and selected profile may be stored only in existing per-character UI state.
They do not affect guild authority or synchronization.

## Verification Result

An explanatory projection over an existing authoritative check.

| Field | Meaning |
|-------|---------|
| `id` | Stable result identifier |
| `category` | Human-readable grouping |
| `severity` | `BLOCKING`, `WARNING`, `READY`, or `OPTIONAL` |
| `title` | Concise status |
| `explanation` | What was checked and why |
| `impact` | Operational effect |
| `nextAction` | Specific corrective guidance |
| `route` | Existing Officer UI destination when available |
| `sourceStatus` | Original authoritative state for diagnosis |

### Severity transition

```text
authoritative state changes
          |
          v
BLOCKING / WARNING / READY / OPTIONAL
          |
          +-- correction route changes authoritative state
          |
          v
verification recomputes from source
```

The interface never directly marks a result complete.
