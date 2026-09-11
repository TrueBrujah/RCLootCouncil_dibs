# Contract: RCLootCouncil History Reconciliation

This contract is a local, administrator-confirmed bridge from read-only RCLootCouncil
history to the Dibs protected accounting path.

## Search and preview

| Input | Required behavior |
| --- | --- |
| Target season, scope/date range, aliases | Required before search starts; the Officer uses one annotation-confirm flow |
| History row | Read-only normalization; retain original source values |
| Explicit alias | Match after case/outer-whitespace normalization only |
| Final status, item, winner, stable identity | Required for guided eligibility |
| Missing/ambiguous evidence | `ambiguous` or `unsupported`; the Officer must review it before confirmation |
| Test/pending/rejected/non-Dibs row | Non-Dibs rows are hidden; matching rows with an invalid final status remain `rejected`; no debit |

Preview returns matching DIB rows, source rows checked, hidden non-DIB rows, eligible,
already-accounted, ambiguous, rejected, and unsupported counts. It does not write a Dibs
transaction.

When a legacy row has a stable history id or date but no separate final-status field, the
preview may apply the explicit history-final-status rule and mark the row as
`HISTORY_FINAL_STATUS_INFERRED`. The row remains reviewable and still requires an Officer
annotation before confirmation.

## Confirmation

| Action | Preconditions | Effect |
| --- | --- | --- |
| Confirm as DIB | GM/Officer; annotation and required evidence | One protected append-only historical consumption linked to evidence |
| Reject/defer | GM/Officer | Decision/audit entry only; no balance change |
| Repeat confirm | Existing stable identity/evidence link | Return existing result; no second debit |

## Invariants

- RCLootCouncil history, candidates, votes, sessions, and identifiers are never modified.
- `RCMLAwardSuccess` and `FinalizeAward` may be shown as provenance labels only; neither is
  an executable UI action or permission grant.
- Player views expose only their own safe summary; complete evidence is Officer-only.
- Guild, season, original award time, import time, actor, and reason remain attributable.
