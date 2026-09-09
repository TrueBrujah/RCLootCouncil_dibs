# Research: RCLootCouncil Item Mapping and Installation Assistant

## Decision 1: Keep Dibs semantics separate from RCLootCouncil set names

RCLootCouncil's button sets mix item families, slot routing, and special-purpose groups.
Dibs needs stable accounting semantics. The integration therefore maps each set to a Dibs
family or marks it as a routing hint; it does not create a balance family for every slot.
Rare and special-effect groups use configurable `OTHER` unless stronger item evidence is
available.

## Decision 2: Resolve token evidence before broad item classes

Context Token metadata maps to `TOKEN`. A class-based Tier Set or Armor Token maps to
`TOKEN_SET` from the RCLootCouncil token table or stable tooltip evidence, even when the
broad item class is Miscellaneous. This order prevents a Tier Set from being mistaken for
a Mount or ordinary loot.

Reference implementation paths in RCLootCouncil:

- [Token table and item evidence](https://github.com/evil-morfar/RCLootCouncil2/blob/develop/core.lua#L967-L985)
- [Item classification helpers](https://github.com/evil-morfar/RCLootCouncil2/blob/develop/core.lua#L941-L960)

## Decision 3: Fail closed for personal categories

Catalyst Items and Cosmetic Items are personal to the player and cannot be represented as
a guild Dibs. They remain blocked even if a broad catch-all policy or RCLootCouncil
Catalyst group is enabled.

## Decision 4: Keep the assistant narrow and repeatable

The assistant prepares the Dibs response in the default set and additional sets already
enabled by the Master Looter. It preserves user-owned response values and never silently
enables a set. Repeating a preset or refresh is idempotent.

Reference configuration shape:

- [RCLootCouncil response-set configuration](https://github.com/evil-morfar/RCLootCouncil2/blob/develop/ml_core.lua#L129-L146)

## Decision 5: Use `OTHER` as the ordinary-loot fallback

Tradeable armor, weapons, and unclassified equipment need a useful default policy without
pretending that an equipment slot is a separate accounting family. They route to
`OTHER`, while personal and cosmetic exclusions are applied first.

## Rejected alternatives

- Treat every RCLootCouncil slot as a separate Dibs type: rejected because it fragments
  accounting and does not describe an item's actual eligibility family.
- Treat all Miscellaneous items as Tier Set tokens: rejected because it misclassifies
  mounts, pets, and unrelated items.
- Let the assistant rewrite all RCLootCouncil sets: rejected because it would overwrite
  guild configuration and silently alter the Master Looter's intent.
- Import or inspect live loot-session votes during setup: rejected because RCLootCouncil
  remains authoritative for session state and Dibs setup must remain read-only there.
