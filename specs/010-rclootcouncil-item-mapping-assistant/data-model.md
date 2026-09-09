# Data Model: RCLootCouncil Item Mapping and Installation Assistant

## Dibs Semantic Loot Family

| Key | Meaning | Dibs policy |
| --- | --- | --- |
| `TOKEN` | Retail Context Token / Curio | Independently enabled or disabled |
| `TOKEN_SET` | Class-based Tier Set or Armor Token | Independently enabled or disabled |
| `MOUNTS` | Mount collection item | Independently enabled or disabled |
| `PETS` | Pet collection item | Independently enabled or disabled |
| `RECIPE` | Recipe or profession item | Independently enabled or disabled |
| `DECOR` | Housing decor item | Independently enabled or disabled |
| `OTHER` | Ordinary tradeable loot, rare, or special-effect fallback | Configurable catch-all |
| blocked | Personal Catalyst or Cosmetic item | Always ineligible |

Families are evaluated in stable precedence order. A slot label never creates a new
ledger category.

## RCLootCouncil Button Set Mapping

| RCLootCouncil group | Mapping | Notes |
| --- | --- | --- |
| Context Token | `TOKEN` | Stable metadata preferred |
| Armor Token / Tier Set | `TOKEN_SET` | Token table or tooltip evidence |
| Catalyst Items / Cosmetic | blocked | Personal item; no Dibs action |
| Mounts | `MOUNTS` | Collection family |
| Pets | `PETS` | Collection family |
| Recipes | `RECIPE` | Profession family |
| Decor | `DECOR` | Housing family |
| Rare items / Items with special effects | `OTHER` | Configurable fallback |
| Chest, Back, Feet, Finger, Hands, Head, Legs, Neck, Shoulder, Trinket, Waist, Wrist, Weapon | inherited | Slot-only routing hint |

## Item Classification Result

```text
family       canonical Dibs family or blocked
evidence     metadata, token table, tooltip, alias, or fallback
source       RCLootCouncil, Encounter Journal, WoW API, or semantic fallback
eligible     boolean after policy and personal-category guard
reason       concise diagnostic for mapping/status UI
```

## Installation Preset

| Preset | Enabled families | Default intent |
| --- | --- | --- |
| Curio + Tier Set | `TOKEN`, `TOKEN_SET` | Progression tokens only |
| Standard loot + collections | `TOKEN`, `TOKEN_SET`, `MOUNTS`, `PETS`, `RECIPE`, `OTHER` | General guild loot; Decor remains off |

The assistant also exposes a refresh operation that does not change policy.

## Projection Status

```text
authorized       verified GM/Officer settings authority
rclc_available   optional integration readiness
target_sets      default plus already-enabled additional sets
inserted         sets that contain the Dibs response after projection
skipped          disabled, unavailable, or full-capacity sets
preserved        pre-existing response values retained by the operation
```

Projection status is read-only state for the settings UI and is not a ledger record.
