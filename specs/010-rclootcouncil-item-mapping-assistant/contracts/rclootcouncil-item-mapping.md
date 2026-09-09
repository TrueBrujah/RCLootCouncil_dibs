# Contract: RCLootCouncil Item Mapping and Installation Assistant

This is an in-game configuration contract between Dibs and the optional RCLootCouncil
integration. It is intentionally not a network or live-loot protocol.

## Semantic mapping

| Input family or evidence | Dibs result | Eligibility rule |
| --- | --- | --- |
| Retail Context Token | `TOKEN` | Follows `TOKEN` policy |
| RCLootCouncil Armor Token / class token | `TOKEN_SET` | Follows `TOKEN_SET` policy |
| Catalyst Items or Cosmetic Items | blocked | Never eligible for Dibs |
| Mounts | `MOUNTS` | Follows `MOUNTS` policy |
| Pets | `PETS` | Follows `PETS` policy |
| Recipes | `RECIPE` | Follows `RECIPE` policy |
| Decor | `DECOR` | Follows `DECOR` policy |
| Rare or special-effect item | `OTHER` | Follows `OTHER` policy |
| Ordinary armor, weapon, or unknown tradeable item | `OTHER` | Follows `OTHER` policy |
| Equipment slot group | inherited | Routes to the item's semantic family |

Token evidence is resolved before broad Miscellaneous classification. Slot groups are
routing hints and do not create Dibs accounting categories.

## Assistant actions

| Action | Effect | Invariants |
| --- | --- | --- |
| Curio + Tier Set | Enables `TOKEN` and `TOKEN_SET`; prepares Dibs response | GM/Officer authority; no ledger write |
| Standard loot + collections | Enables `TOKEN`, `TOKEN_SET`, `MOUNTS`, `PETS`, `RECIPE`, `OTHER` | Decor stays disabled by default; no ledger write |
| Refresh Dibs buttons | Reprojects the response to default and already-enabled sets | Idempotent; disabled sets untouched |

## Projection invariants

- Existing response text, colors, order, slot choices, and active responses remain intact.
- If a target set is full, no existing entry is displaced and a capacity status is shown.
- If RCLootCouncil is unavailable, Dibs policy remains usable and projection can retry.
- The contract does not alter RCLootCouncil source, candidates, votes, history, awards, or
  live loot-session authority.
