# Implementation Plan: Data Health Review Center

**Branch**: `023-data-health-review-center` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/023-data-health-review-center/spec.md`

## Summary

Extend the existing Officer diagnostics experience with a grouped, read-only review center for verifiable ledger references and Great Vault acquisition issues. Reuse the existing Vault review page and its audited conflict-resolution controls; keep anomaly previews non-mutating, and export only safe finding categories and counts. No SavedVariables, ledger, or synchronization schema change is required.

## Technical Context

**Language/Version**: Lua for the World of Warcraft Retail addon runtime.

**Primary Dependencies**: Existing Dibs modules, AceGUI wrappers, Midnight UI helpers, and optional Great Vault integration.

**Storage**: Existing guild-scoped SavedVariables are read only; no new persisted state.

**Testing**: Fengari through `tests/run.lua`, focused contract and Officer UI suites, plus `git diff --check`.

**Target Platform**: World of Warcraft Retail; automated tests use the repository's WoW/Ace3/RCLootCouncil doubles.

**Project Type**: Lua addon with domain modules, integrations, and AceGUI projections.

**Performance Goals**: On-demand scan and display complete within 2 seconds for a representative guild fixture containing 5,000 ledger transactions and 1,000 acquisition records.

**Constraints**: GM/Officer authorization is rechecked at action boundaries; preserve guild isolation, append-only ledger history, RCLootCouncil optionality, existing Vault review audit behavior, localization, and protected-frame/combat rules. Do not persist or synchronize findings.

**Scale/Scope**: One guild-scoped Officer diagnostics page; bounded report/export; no new accounting policy or data lifecycle.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **World of Warcraft API compliance**: PASS. Uses existing non-protected Officer UI; no protected gameplay action or new Retail API dependency.
- **Append-only accounting and auditability**: PASS. Scanning, previewing, navigation, and export are read-only. Existing Great Vault conflict decisions remain in the existing audited workflow.
- **Authority and privacy**: PASS. Access is limited to verified Guild Masters and Officers; export omits personal identities, private evidence, and raw payloads.
- **Guild isolation and synchronization**: PASS. Reads the active guild only and adds no synchronization payload or state.
- **Optional RCLootCouncil compatibility**: PASS. The health/review center remains available without RCLootCouncil.
- **UI and validation conventions**: PASS. Reuse the existing Diagnostics route, shared table helpers, localized strings, and focused Fengari suites. Retail validation remains an explicit manual gate.

## Project Structure

### Documentation (this feature)

```text
specs/023-data-health-review-center/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── health-review-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
src/
├── ui/
│   ├── HealthUI.lua
│   └── OfficerUI.lua
└── locales/
    ├── enUS.lua
    └── frFR.lua

tests/
├── contract/
│   └── health_anomaly_contract_spec.lua
└── integration/
    └── health_dashboard_ui_spec.lua
```

**Structure Decision**: Extend the already loaded `Dibs.HealthUI` projection and its existing Officer Diagnostics page. Route Vault-specific issues to the established `vault` Officer page instead of duplicating conflict decisions. Add focused contract/UI coverage in the existing test layout.

## Complexity Tracking

No constitution violations or additional architectural components are required.
