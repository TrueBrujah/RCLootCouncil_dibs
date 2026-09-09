# Contract: Raid Readiness and Dry-Run Center

## Readiness states

| State | Meaning | Live Dibs consumption |
| --- | --- | --- |
| `Ready` | Required local and integration checks pass | Existing protected path may proceed after final revalidation |
| `Degraded` | Optional or recoverable condition is missing | Explicitly reports whether local consumption remains allowed |
| `Blocked` | Required award evidence/authority cannot be verified | No production Dib consumption |
| `Unavailable` | Expected context/integration is absent | Standalone administration remains usable |

Every result includes timestamp, mode, freshness/fingerprint, probe statuses, reason codes,
impact, and remediation.

## Dry-run contract

| Input | Rule |
| --- | --- |
| Item, winner, response, final status, stable test identity | Bounded and evaluated using live validation decisions |
| Missing/ambiguous/non-final/test status | Deterministic ignore/reject/review result |
| Repeat input | Same result; no idempotency record or ledger mutation |
| RCLootCouncil absent/degraded | Standalone checks may run; live capability is unavailable |

## Invariants

- No global event, addon/raid message, award control, SavedVariables change, ledger,
  candidate, vote, session, history, or synchronization mutation occurs.
- Only verified GM/Officer actors may run detailed checks, dry-runs, policy changes, and
  detailed reports. Safe summaries may be shown to players.
- `RCMLAwardSuccess` and `FinalizeAward` are evidence references, never executable controls.
