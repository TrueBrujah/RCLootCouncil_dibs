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
/dibs vault <item link>
/dibs vault <item link | [Item Name] | itemID> <LFR | Normal | Heroic | Mythic>
```

Input rules:

- `itemID` must be a positive integer; typed names must resolve through the client item cache.
- A full item link without a supplied difficulty uses the raid-origin/dungeon-track detection below.
- Otherwise a valid explicit difficulty is required; missing or invalid input shows usage and creates no record.
- An explicit manual difficulty is normalized using the existing Dibs rules and remains reviewable.
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

## Difficulty detection: raid origin vs dungeon track (user-approved 2026-10-15)

Read the exact reward variant through `C_TooltipInfo.GetHyperlink(exactItemLink)`;
read the upgrade track from `C_Item.GetItemUpgradeInfo(exactItemLink).trackString`
when available, otherwise from the tooltip's `<Track> n/m` line.

- Raid rewards keep the origin label (Raid Finder/LFR, Normal, Heroic, Mythic) when the track is
  compatible: LFR on Veteran, Normal on Champion/Hero, Heroic on Hero/Myth, Mythic on Myth.
  Heroic with Myth 5/6 remains `Heroic`.
- Dungeon rewards (Mythic+ label, Mythic on the Champion track for Mythic 0,
  or Heroic on the Veteran track) follow the track:
  a Heroic-origin dungeon reward on Veteran remains `Heroic`;
  Champion → `Normal`, Hero → `Heroic`, Myth → `Mythic`.
- Tracks below Veteran, a missing track, conflicting origin lines and any
  other origin/track combination are not classified.

Recognize complete lines (including localized client labels), not the item name
or arbitrary substrings. Store the normalized result in `difficulty`; do not copy
it into `upgradeTrack` or overwrite separately supplied upgrade-track evidence.
Do not use item level, link context or Vault activity level. Missing APIs and
unclassified rewards must not produce an automatic `UNKNOWN` acquisition or default
to Normal. Retain explicit manual entry and review; `LFR` and `Raid Finder`
are accepted manual aliases. The canonical stored/synchronized value is `LFR`;
raid difficulty ID 17 normalizes to the same value. Existing record shapes and
protocol versions are unchanged; older clients without LFR normalization should
update before manually re-recording LFR evidence.
This changes no claim-proof, authority, synchronization, or ledger boundary and
does not rewrite historical records.
