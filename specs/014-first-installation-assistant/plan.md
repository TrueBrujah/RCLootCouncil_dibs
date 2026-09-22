# Implementation Plan: First Installation Assistant

**Branch**: `014-first-installation-assistant` | **Date**: 2026-09-22 | **Spec**: [spec.md](spec.md)

## Summary

Add a transient first-installation assistant that composes the existing readiness, permissions, configuration, and dry-run services. The first increment exposes a stable checklist/projection and protected action delegation; the visual wizard can then consume the same contract without creating a second authority model or persisted completion flag.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code

**Primary Dependencies**: Existing Dibs modules, AceGUI/Midnight UI, optional RCLootCouncil adapter, Fengari test harness

**Storage**: No new SavedVariables or SyncV2 fields; transient runtime state only

**Testing**: Fengari unit, contract, and integration tests; manual Retail validation for protected UI and live integration

**Target Platform**: World of Warcraft Retail client, standalone or optional RCLootCouncil installation

**Project Type**: Single addon project

**Performance Goals**: Checklist evaluation remains bounded and does not rebuild unrelated pages or scan unbounded history

**Constraints**: Preserve existing protected-action, guild-scope, combat, privacy, ledger, protocol, and RCLootCouncil ownership boundaries

**Scale/Scope**: One first-installation checklist, one local dry-run entry point, and supported setup actions for a new guild

## Constitution Check

- World of Warcraft API compliance: PASS; no protected automation or client-file changes.
- Ledger and authority preservation: PASS; mutations remain delegated to existing `ProtectedActions`.
- RCLootCouncil optionality: PASS; standalone mode remains supported and absent RC is explicit.
- Data ownership: PASS; no new persisted or synchronized state.
- Privacy and guild scope: PASS; administrative details remain GM/Officer-only.
- Combat safety: PASS; protected actions retain existing combat/readiness gates.
- Documentation and tests: PASS; focused automated tests and manual Retail matrix are included.

## Project Structure

```text
specs/014-first-installation-assistant/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/setup-assistant.md
├── quickstart.md
└── tasks.md

src/
├── ui/SetupAssistant.lua
├── RCLootCouncil_dibs.toc
└── ... existing services consumed by the assistant

tests/
├── contract/setup_assistant_contract_spec.lua
└── integration/setup_assistant_spec.lua
```

**Structure Decision**: Keep the assistant as a thin UI/domain projection in `src/ui/SetupAssistant.lua`; use existing services for observations, mutations, localization, and dry-run semantics.

## Design Notes

- `Evaluate` gathers existing `Readiness.Evaluate` probes, then adds bounded setup checks for rank rules, channels, and loot-type configuration where available.
- `ExecuteAction` validates the assistant allowlist and calls `ProtectedActions.Execute` with canonical values.
- `RunDryRun` calls `Dibs.DryRun.Run` and stores only the last result in memory for the current session.
- The visual window is a follow-up slice after the pure contract is green; it will use the existing Officer route and shared Midnight controls.

## Complexity Tracking

No constitution violations.
