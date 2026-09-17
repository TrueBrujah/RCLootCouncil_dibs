# Testing and development

The automated suite runs in Lua through Fengari with WoW, Ace3, and optional RCLootCouncil doubles:

```powershell
npx.cmd --yes fengari tests/run.lua
```

Use `DIBS_TEST_FILES` to run a semicolon-separated subset. Tests cover domain policies, ledger invariants, SavedVariables migration, sync validation, import/export limits, RC capability degradation, UI callback wiring, optional-module navigation and guards, and TOC load integrity. The 0.6.2 release-candidate pass was validated with 455 passing tests in 91 files.

Retail-only checks remain manual: protected-frame behavior, real RC callback
authority, Blizzard Encounter Journal timing, guild roster identity, visual
layout at multiple scales, two-client coordinator handoff, partition/recovery,
and clean-package installation. Do not report those as automated results.

The release gate also requires the current B00-B09 evidence records, an explicit
`V2_ENFORCED` cutover test, exact-sequence/gap recovery, coordinator-unavailable
proposal behavior, and validation of the specific RCLootCouncil profile. Until
those checks are recorded, `RETAIL_RUNTIME_VALIDATION` remains pending and the
development tree must not be described as production-ready.

Developer mode and DryRun are test/dev-only surfaces. They must not bypass permission, readiness, combat, or append-only accounting rules. Add tests when changing a rule or compatibility boundary, not for comments that do not alter behavior.
