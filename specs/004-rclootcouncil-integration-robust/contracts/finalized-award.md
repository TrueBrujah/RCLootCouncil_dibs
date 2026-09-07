# Contract: Finalized RCLootCouncil Award

## Input

The adapter normalizes one local finalized-award callback into:

```text
{
  awardRef,
  historyId?,
  sessionId?,
  awardIndex?,
  itemID,
  itemLink?,
  winnerId,
  responseCode,
  sourceStatus,
  source = "rclootcouncil",
  observedAt,
  responseValidated = true
}
```

Fields are descriptive; the exact Lua table shape is an implementation detail. The
following invariants are mandatory:

- `source` is RCLootCouncil and cannot be supplied by an untrusted remote payload.
- `responseCode` is exactly the canonical DIB response after explicit normalization.
- `sourceStatus` identifies a real finalized award and is not `test_mode`.
- `itemID`, `winnerId`, and `awardRef` are stable and resolvable.
- The callback actor is the local client and matches the current verified RCLootCouncil
  Master Looter.
- The integration state is `operational` at the time of validation.

## Outcomes

| Outcome | Meaning | Ledger effect |
|---|---|---|
| `AWARDED` | New qualifying finalized award accepted | Exactly one protected Dib consumption, subject to normal eligibility/cost rules |
| `DUPLICATE` | `awardRef` already accounted | No new transaction; return existing result |
| `IGNORED` | Non-DIB, test, unavailable, incomplete, or unsupported event | No ledger mutation |
| `REJECTED` | Explicit validation or authority failure | No ledger mutation; diagnostic/reason code recorded locally |

## Idempotency

`awardRef` MUST be unique for one award and stable across duplicate delivery. The protected
action MUST check existing accounting after authorization and before appending a transaction.
An in-memory-only reference is insufficient for a reload-safe award. When no stable source
identity exists, the adapter MUST return `IGNORED` or `REJECTED` rather than generate a
guessing identity.

## Rejection Rules

The adapter MUST ignore or reject:

- normal, non-DIB, or ambiguous responses;
- test or simulation awards;
- callbacks from a client that is not the current Master Looter;
- remote actor objects that do not represent the local client;
- missing, malformed, or ambiguous item/winner/session identity;
- changed Master Looter or integration capability state between checks;
- awards that fail Dibs season, eligibility, or cost validation.

## Audit Requirements

An accepted award records the award reference, winner, item, source, verified actor, source
status, and reason through the existing append-only Dibs ledger. The adapter does not rewrite
prior transactions or RCLootCouncil history.
