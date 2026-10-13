# Implementation Plan: Turnkey Guided Setup

**Branch**: `021-turnkey-guided-setup` | **Date**: 2026-10-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/021-turnkey-guided-setup/spec.md`

**Note**: This template is filled in by the `$speckit-plan` command; its definition describes the execution workflow.

## Summary

Replace the fourteen-page Guided Setup navigation with a three-stage workflow:
Choose, Configure, and Verify. `Dibs.Wizard` remains a projection/orchestration layer
over the existing authoritative modules. It will expose documented setup profiles,
a deterministic preview, an idempotent apply operation, and grouped verification
results with severity and correction routes. `OfficerUI` will render those projections
through the existing Midnight shell, using red only for true blockers and always
pairing color with labels, explanations, impact, and corrective actions.

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Lua 5.1-compatible WoW addon code; Fengari test runtime

**Primary Dependencies**: WoW Retail API, embedded Ace3/AceGUI, existing Dibs
Installation, Governance, OperationalPolicy, Seasons, RankRules, PreDibs, LootRules,
SetupAssistant, Readiness, Sync, and RCLootCouncil adapter modules

**Storage**: Existing guild SavedVariables for authoritative settings and existing
per-character UI state for selected setup stage/profile; no new accounting store

**Testing**: `tests/run.lua` through `fengari-node-cli`, focused integration and
contract suites, plus `git diff --check`

**Target Platform**: World of Warcraft Retail addon runtime

**Project Type**: Single Lua addon with modules, integrations, and AceGUI UI

**Performance Goals**: One readiness evaluation per setup render; no repeated full
roster or ledger scans caused by stage rendering; immediate stage navigation

**Constraints**: Preserve append-only accounting, authority boundaries, existing
serialized identifiers, combat safety, guild isolation, localization with English
fallback, and optional RCLootCouncil operation

**Scale/Scope**: One three-stage Officer UI workflow, two recommended profiles plus
custom mode, existing setup checks grouped into documented results, focused automated
coverage

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I — WoW API compliance**: PASS. Uses existing addon UI and service APIs; no
  protected gameplay automation.
- **III/IV — Seasonal allocation and append-only ledger**: PASS. Setup may configure
  policy but cannot rewrite or reset transactions.
- **V/XI — Visibility and authority**: PASS. Officer/GM access remains delegated to
  existing permission and protected-action boundaries; GM-only adoption remains
  explicit.
- **VII — Optional RCLootCouncil**: PASS. Profiles use the existing optional adapter
  and must remain useful without RCLootCouncil.
- **VIII — Localization**: PASS. New user-facing guidance is added through locale
  keys with English fallback.
- **XVIII — Diagnostics**: PASS. Partial failures are returned explicitly and shown
  in the workflow rather than hidden or printed unconditionally.
- **XXI — Human-centered interface**: PASS. Uses the shared Midnight shell, semantic
  statuses, visible primary actions, explanations, and correction destinations.
- **XXIII — Efficient work**: PASS. Reuses verified projections and targeted test
  suites; no second readiness engine is introduced.

No constitution exception is required.

## Project Structure

### Documentation (this feature)

```text
specs/021-turnkey-guided-setup/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md        # Phase 1 output ($speckit-plan command)
├── quickstart.md        # Phase 1 output ($speckit-plan command)
├── contracts/
│   └── guided-setup-api.md
└── tasks.md             # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
src/
├── modules/
│   └── Wizard.lua
├── ui/
│   └── OfficerUI.lua
└── locales/
    ├── enUS.lua
    └── frFR.lua

tests/
├── contract/
│   └── turnkey_guided_setup_contract_spec.lua
└── integration/
    └── guided_setup_wizard_spec.lua
```

**Structure Decision**: Extend the existing single-addon structure. Domain orchestration
and projections remain in `src/modules/Wizard.lua`; the Officer UI only renders and
routes actions; locale files own new user-facing copy. Existing authoritative modules
remain unchanged unless a missing safe public operation is proven during implementation.

## Complexity Tracking

No constitution violations or additional architectural layers are required.

## Post-Design Constitution Check

PASS. The design artifacts retain existing authority, readiness, persistence, sync,
and ledger ownership. Setup profiles orchestrate existing public operations and return
explicit partial results; they do not introduce a second policy store or readiness
engine. UI severity is semantic and does not rely on color alone.
