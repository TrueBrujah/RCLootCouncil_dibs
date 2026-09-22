# Contract: Great Vault Acquisition

## Scope

This contract defines the behavior exposed by the Great Vault acquisition feature to the existing Dibs acquisition and eligibility workflows. It does not define a new ledger operation.

## Automatic detection contract

The detector may publish a candidate only when the runtime capability probe confirms that the current Retail client exposes enough evidence to identify a completed claim.

A detector result contains:

```text
status: CONFIRMED | UNAVAILABLE | AMBIGUOUS
source: GREAT_VAULT
itemID: positive integer when known
resetId: stable reset identity when known
claimedAt: Unix timestamp when known
rewardCategory: optional category
confidence: COMPLETE | PARTIAL | MISSING
reasonCode: capability or validation explanation
```

Rules:

- `CONFIRMED` creates one `AUTOMATIC_CONFIRMED` acquisition after validation.
- `UNAVAILABLE` leaves the manual command available and does not create a confirmed acquisition.
- `AMBIGUOUS` may create a local `UNVERIFIED` record only when the user or policy explicitly permits it; it must never count silently as confirmed.
- Opening the Vault, viewing an option, or receiving an update without claim evidence is not a completed claim.
- The detector must be safe to initialize when the Great Vault API is absent.

## Manual command contract

Command:

```text
/dibs vault <itemID> [difficulty]
```

Input rules:

- `itemID` must be a positive integer.
- `difficulty` is optional and normalized using the existing Dibs difficulty rules.
- The command records the current character and guild/character scope.
- The command never changes the Dibs ledger.
- Repeating the command for the same safe identity returns the existing record.
- When no safe reset or claim identity exists, the result is manual and reviewable rather than automatically confirmed.

User-visible outcomes:

```text
RECORDED_MANUAL
ALREADY_RECORDED
INVALID_ITEM
ACQUISITIONS_UNAVAILABLE
SEASON_CONTEXT_UNAVAILABLE
REVIEW_REQUIRED
```

## Review contract

Only a verified GM or Officer may confirm or reject a manual, legacy, or ambiguous record. Every decision requires a reason and records:

- acquisition identity;
- previous and resulting state;
- actor;
- timestamp;
- evidence references;
- reason.

Review actions are idempotent for the same decision identity and cannot create a Dibs transaction.

## Eligibility boundary

The acquisition is passed to `CharacterEligibility` as evidence with its verification state. The eligibility service decides whether the active policy counts the record. The acquisition feature must not duplicate protected-loot policy or directly decide a Dibs outcome.
