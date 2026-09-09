# Contract: Officer Audit and Dispute Center

## Player report

| Input | Rule |
| --- | --- |
| Own Dibs transaction/finalized context | Prefill available evidence; no technical ID required |
| Category/note | Optional category, bounded inert note |
| Duplicate active evidence/context | Reopen or link existing request; no spam case |
| Other player's record | Reject without disclosure |

Submitting a report changes no authoritative state.

## Officer lifecycle

| Action | Authority | Accounting effect |
| --- | --- | --- |
| Review/ask information/reject/no correction/duplicate | Verified GM/Officer | No balance change |
| Correct balance/advanced correction | Verified GM/Officer + explicit confirmation/reason | Linked append-only compensating transaction |
| Player reply | Request owner | Context only; cannot edit evidence |
| Reopen | Verified GM/Officer | Audit/status only unless a new correction is confirmed |

## Invariants

- Existing Dibs transactions and RCLootCouncil history remain immutable.
- A request/evidence correction is idempotent across reload, replay, and concurrent review.
- Players see only their own safe request and evidence summary; queue and notes are Officer-only.
- RCLootCouncil loot-session award authority is never overridden by a dispute.
- User text is bounded and rendered as inert content.
