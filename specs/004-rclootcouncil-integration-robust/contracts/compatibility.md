# Contract: RCLootCouncil Compatibility and Fallback

## Supported Surface

The release must document and test the minimum capability surface used by the adapter:

- a discoverable RCLootCouncil addon instance;
- a verifiable enabled/operational state;
- a current Master Looter identity;
- a finalized-award callback carrying a stable winner/item/response context;
- optional loot/voting/options surfaces used for read-only display or DIB controls.

The presence of a compatible-looking version label is not enough. Each capability is probed
at runtime and recorded in the compatibility status.

## Compatibility Outcomes

| Situation | Dibs core | Dibs policy administration | RC award accounting | UI behavior |
|---|---|---|---|---|
| RCLootCouncil absent | Available | GM/officer only | Not available | Standalone surfaces |
| RCLootCouncil operational | Available | GM/officer only | Verified local ML + finalized DIB only | Integration projections available |
| RCLootCouncil degraded | Available | GM/officer only | Denied until revalidated | Show status and safe fallback |
| RCLootCouncil unsupported | Available | GM/officer only | Denied | Preserve standalone UI and explain mismatch |
| RCLootCouncil loads late | Available | GM/officer only | Available after successful recheck | Refresh without data reset |

## Version and Release Evidence

Each supported release must record the WoW client build, RCLootCouncil build or tested
surface, capability results, known limitations, automated test result, and Retail smoke-test
result. A behavior/build change also requires a dated changelog note and addon version
increment according to the constitution.
