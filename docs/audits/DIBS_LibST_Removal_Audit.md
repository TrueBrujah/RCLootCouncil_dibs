# DIBS lib-st Removal Audit

**Audit date:** 2026-09-28
**Scope:** `src/`, `tests/`, `specs/`, `docs/`, and `src/embeds.xml`
**Phase:** Read-only inventory completed before implementation changes

## Search Method and Counts

The pre-change scan counted matching source lines for the case-insensitive pattern:

```regex
lib[-_ ]st\b|ScrollingTable|_dibsScrollingTable|AddScrollingTable|getScrollingTable
```

There were **93 matching lines in 20 files** across the requested trees. The vendored `src/libs/lib-st/` directory contained **3 files**; one of them (`Core.lua`) contained 26 matching lines.

| Classification | Exact count | Files / interpretation |
|---|---:|---|
| A. DIBS internal UI/runtime | 30 lines | 28 in `src/ui/AceGUI.lua`, 1 acquisition in `src/integrations/Ace3.lua`, 1 include in `src/embeds.xml`. One optional ScrollingTable registration, a direct LibStub fallback, and a conditional `AddTable` renderer. |
| B. RCLootCouncil compatibility | 1 matching source line | A historical callback-signature changelog comment in `src/integrations/RCLootCouncil.lua`; separately, 47 lines in that adapter reference the voting-column surface (`AddColumn`, `scrollCols`, `frame.st`, `UpdateSt`, `GetFrame`, and refresh calls). These are external compatibility code, not DIBS-owned tables. |
| C. Test harness | 15 lines | 11 in `tests/integration/b11_retail_ui004_ownership_spec.lua`, 3 in `tests/integration/b12_ui_ownership_spec.lua`, and 1 in `tests/integration/rclootcouncil_buttons_spec.lua`. Includes obsolete ownership assertions and a callback-contract test. |
| D. Active documentation/specifications | 8 lines | 5 lines across `docs/ARCHITECTURE.md`, `docs/developer/api-reference.md`, `docs/developer/architecture.md`, and this project’s active UI audit; 3 lines across the plan/spec/tasks for spec 012. |
| E. Vendored library | 26 lines | Matching text in `src/libs/lib-st/Core.lua`; the vendored directory has 3 files total (`CHANGES.txt`, `Core.lua`, `lib-st.xml`). |
| F. Historical evidence only | 13 lines | 7 in B11 runtime evidence, 2 in B12 RCLootCouncil column evidence, 2 in B12a implementation evidence, 1 in the RCLootCouncil technical audit, and 1 historical test report in `docs/RC_OPTIONS.md`. These records are not runtime dependencies and will be retained. |

Other active DIBS grid inventory: **26 direct `AddTable` callsites**: PlayerUI 11, OfficerUI 11, LogsUI 2, DataUI 2; DebugLogsUI has 0. All currently route through the shared `Dibs.AceGUI.AddTable` adapter, whose Retail branch is still conditional on lib-st. The fallback is a separate static AceGUI label layout and does not currently provide the same sorting, selection, and context-menu behavior.

## RCLootCouncil API Check

The local Retail installation is RCLootCouncil **3.23.3**. Its `Modules/VotingFrame/ColumnAPI.lua` documents `AddColumn`, `RemoveColumn`, `GetColumn`, and `GetColumnIndex`; the `AddColumn` documentation directs integrations to alter columns during the voting frame's `OnInitialize` lifecycle. DIBS can therefore use the public column API without accessing `scrollCols`, `frame.st`, or RCLootCouncil's internal ScrollingTable. The minimum DIBS voting-column compatibility baseline will be documented as **RCLootCouncil 3.23.3**, the verified API baseline; older surfaces must report unsupported/update required rather than silently using internal table fields.

## Migration Acceptance

- Remove DIBS's bundled library, embed, acquisition, direct LibStub lookup, and all internal native-table paths.
- Promote one shared DIBS Data Grid implementation behind `AddTable` and preserve existing page callbacks, sorting, selection, tooltips, context menus, action sizing, scrolling, responsive widths, and release behavior.
- Keep RCLootCouncil-owned callback argument compatibility private to `src/integrations/RCLootCouncil.lua`, use only its public column lifecycle API, and retain RCLootCouncil as an optional external addon.
- Keep historical evidence in classification F unchanged; update active architecture/API/spec documentation and replace ownership tests with grid behavior tests.

## Post-Migration Verification

The inventory above is the pre-migration baseline. The case-insensitive scan after migration found no matches in runtime source, tests, embeds, or active architecture/API/spec documents. The three vendored library files, embed, and Ace3 acquisition are removed. The active embedded-library catalog in `.specify/memory/constitution.md` no longer lists the dependency.

Remaining matches are limited to changelog entries and historical audit/evidence records, including this report's pre-migration inventory. These records are retained as evidence and are not runtime dependencies.

Validation:

- Focused Data Grid, RCLootCouncil public-column API, combat-safety, and B12 ownership suites: **40 passed, 0 failed**.
- Focused page, navigation, responsive-layout, and lifecycle consumer suites: **144 passed, 0 failed**.
- Full suite: **798 passed, 1 failed**. The isolated failure is `tests/integration/predibs_sync_recovery_spec.lua`, `Pre-Dib recovery sync / uses AceComm registration and AceTimer for one bounded anti-entropy heartbeat` (`expected 1, got 2`); it is outside the table-rendering migration.
- Changed Lua syntax, documentation validation, and generated-document check: passed. Documentation validation retains 8 existing orphan-help-key warnings.
- In-game Retail route and interaction validation: **pending**; no in-game pass is claimed.