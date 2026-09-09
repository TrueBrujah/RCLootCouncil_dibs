# Contract: RCLootCouncil History Reconciliation

This contract is a local, administrator-confirmed bridge from read-only RCLootCouncil
history to the Dibs protected accounting path.

## Search and preview

| Input | Required behavior |
| --- | --- |
| Target season, scope/date range, aliases, review mode | Required before search starts |
| History row | Read-only normalization; retain original source values |
| Explicit alias | Match after case/outer-whitespace normalization only |
| Final status, item, winner, stable identity | Required for guided eligibility |
| Missing/ambiguous evidence | `ambiguous` or `unsupported`; no guided confirmation |
| Test/pending/rejected/non-Dibs row | Excluded or `rejected`; no debit |

Preview returns scanned, eligible, already-accounted, ambiguous, rejected, and unsupported
counts. It does not write a Dibs transaction.

## Confirmation

| Action | Preconditions | Effect |
| --- | --- | --- |
| Guided confirm | GM/Officer; all required evidence valid | One protected append-only historical consumption |
| Manual confirm | GM/Officer; explicit acknowledgement and reason | One protected consumption linked to evidence |
| Reject/defer | GM/Officer | Decision/audit entry only; no balance change |
| Repeat confirm | Existing stable identity/evidence link | Return existing result; no second debit |

## Invariants

- RCLootCouncil history, candidates, votes, sessions, and identifiers are never modified.
- `RCMLAwardSuccess` and `FinalizeAward` may be shown as provenance labels only; neither is
  an executable UI action or permission grant.
- Player views expose only their own safe summary; complete evidence is Officer-only.
- Guild, season, original award time, import time, actor, and reason remain attributable.
