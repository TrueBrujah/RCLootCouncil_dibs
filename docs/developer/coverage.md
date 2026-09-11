# Documentation coverage report

Audit date: 2026-09-11. The implementation under `src/` and the automated tests are authoritative. Validation completed with 226 passing tests in 54 files.

## Covered

- All TOC first-party modules have structured headers and are listed in [modules.md](modules.md).
- Architecture, data model, events, SavedVariables, sync, RC integration, combat safety, naming, testing, and contributing guides are present.
- Officer procedures and player terminology are present under `docs/officer/` and `docs/player/`.
- Stable business rules DIBS-RULE-001 through DIBS-RULE-012 are defined in [architecture.md](architecture.md) and referenced by module headers.
- Core, Ledger, Pre-Dibs, Sync, RC integration, UI entry points, SavedVariables models, and protocol envelopes have LuaCATS declarations or boundary documentation.
- The complete first-party export index is maintained in [api-reference.md](api-reference.md); detailed annotations are concentrated on mutation, sync, RC, and UI entry points where payload semantics are non-trivial.

## Undocumented modules and public APIs

No first-party TOC module is intentionally left without a header or inventory
entry. No public namespace is omitted from the API index. The embedded/vendor
libraries under `src/libs/**` are third-party implementation dependencies and do
not have Dibs public APIs; their upstream documentation is the appropriate
reference.

## Missing documentation

No required Developer, Officer, or Player document is missing. The remaining
gaps are typed detail in the weakly typed areas below, not absent operational
guidance.

## Partial or weakly typed areas

- Large UI widget tables in `OfficerUI.lua`, `PlayerUI.lua`, `DataUI.lua`, and `AceGUI.lua` still rely on inferred AceGUI shapes; they need typed widget interfaces if LuaLS begins checking vendor APIs.
- `Disputes.lua` evidence/reply payloads and several ImportExport payload unions are intentionally open tables because their schemas are validated at runtime.
- RCLootCouncil’s external object shape is capability-probed and cannot be fully typed without the installed RC version’s API definitions.
- Embedded libraries and locale tables are excluded from the Dibs domain model; their vendor types remain external.

## Unresolved naming/documentation items

- Historical lower-camel `CoreAPI` methods coexist with PascalCase module APIs. They are documented compatibility surfaces and should not be renamed without migration.
- `Dibs.Eligibility` remains an alias for older callers; new code should use `Dibs.CharacterEligibility`.
- `RCLootCouncil_dibsDB` and the `DIBS` prefix are persisted/protocol identifiers and must remain unchanged.

## Stale or corrected documentation

The new guides deliberately avoid claiming automatic boss grants, automatic loot transfer, automatic highest-balance wins, or live-loot synchronization. Timestamp documentation now requires Unix seconds and preserves source precision; a displayed zero is treated as missing/invalid data and should be investigated rather than accepted as a real award time.

## Implementation/documentation discrepancies

The audit found no unresolved discrepancy in the documented business rules.
`docs/PROTOCOL.md` previously listed speculative message names; it now lists the
actual `Sync.lua` message types and links to the maintained protocol guide.
Where older root documents describe lower-level details, the new
`docs/developer/` references take precedence and link back to the implementation.

## Recommended next tasks

1. Add generated API/type output from LuaLS once the project adopts a checked `.luarc.json` configuration.
2. Add Retail smoke capture for each Officer navigation page and each protected-action retry path.
3. Type the stable evidence/reply schemas after their payloads are formally versioned.
4. Add a migration fixture whenever the SavedVariables schema changes.
