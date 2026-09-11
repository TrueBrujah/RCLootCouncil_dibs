# Documentation pass checkpoint

Date: 2026-09-11

## Scope

Complete documentation and nomenclature pass for the Dibs addon, based on the
implementation in `src/` and the existing tests/specifications. Preserve
business behavior unless a naming change is required for compatibility or
documentation correctness.

## Pass status

- [x] Pass 1 inventory and architecture documents
- [x] Pass 2 naming convention and compatibility audit
- [x] Pass 3 LuaLS/LuaCATS model and API annotations
- [x] Pass 4 file-level headers
- [x] Pass 5 function documentation
- [x] Pass 6 business-rule traceability
- [x] Pass 7 developer documentation set
- [x] Pass 8 Officer documentation set
- [x] Pass 9 Player documentation set
- [x] Pass 10 consistency audit and coverage report

## Confirmed implementation anchors

- Packaged source starts at `src/Core.lua`; the TOC declares
  `RCLootCouncil_dibsDB` and `RCLootCouncil` as optional.
- Guild-scoped persistence is rooted at `SavedVariables.guilds[guildKey]`;
  guild schema version is currently 6, with additive reconciliation and
  character-eligibility sub-schemas.
- First-party namespaces are under `Dibs`; the legacy alias
  `Dibs.Eligibility` points to `Dibs.CharacterEligibility`.
- Protected mutations pass through `Dibs.ProtectedActions.Execute`; the
  append-only ledger is `Dibs.Ledger`.
- Cross-client sync uses prefix `DIBS` and message types defined in
  `src/modules/Sync.lua`.
- RCLootCouncil is capability-probed and may be absent, operational, degraded,
  or unsupported; Dibs administration remains guild-authorized.

## Validation

- `npx.cmd --yes fengari tests/run.lua` with all 54 discovered suites: 226 passed,
  0 failed.
- `git diff --check`: clean.

## Remaining work

No documentation-pass work remains. Retail visual/protected-frame and two-client
delivery checks remain manual as described in `docs/developer/testing.md`.
