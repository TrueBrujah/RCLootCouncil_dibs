# Testing and development

The automated suite runs in Lua through Fengari with WoW, Ace3, and optional RCLootCouncil doubles:

```powershell
npx.cmd --yes fengari tests/run.lua
```

Use `DIBS_TEST_FILES` to run a semicolon-separated subset. Tests cover domain policies, ledger invariants, SavedVariables migration, sync validation, import/export limits, RC capability degradation, UI callback wiring, and TOC load integrity. The documentation pass was validated with 226 passing tests in 54 files.

Retail-only checks remain manual: protected-frame behavior, real RC callback authority, Blizzard Encounter Journal timing, guild roster identity, and visual layout at multiple scales. Do not report those as automated results.

Developer mode and DryRun are test/dev-only surfaces. They must not bypass permission, readiness, combat, or append-only accounting rules. Add tests when changing a rule or compatibility boundary, not for comments that do not alter behavior.
