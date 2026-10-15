# Implementation Plan: Development Catch-up

**Branch**: `dev` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

## Summary

Retrospectively map the current development changes to explicit acceptance
criteria and test evidence before committing. Do not pretend the artifacts
predate implementation. Retain features 013/017/022/023 as the owners of their
existing contracts. This record covers their corrective deltas and the smaller
minimap/statistics/export additions; it introduces no new accounting policy.

## Technical Context

- **Language/Version**: WoW Retail Lua.
- **Dependencies**: Existing Ace3, LootPipeline, PreDibs, GreatVault, Identity,
  SyncV2, AuditExport, PlayerUI, OfficerUI and MinimapButton.
- **Storage**: Existing guild acquisitions and character-local preferences.
  No new guild schema or message format for these corrections.
- **Testing**: Existing Fengari tests, synthetic fixtures, diff whitespace checks.
- **Target**: WoW Retail addon; standalone and optional RCLootCouncil.
- **Performance**: Reuse bounded UI pagination; scan carried items once per
  Vault render, not once per acquisition. No new background polling.
- **Scope**: Recent 0.8.7-dev changes only; no ticket implementation here.

## Constitution Check

Pre/post-design: PASS for I, IV, XI, XIV, XV, XVII, XIX and XXI.
No protected claim invocation, evidence fabrication, ledger mutation from Vault,
authority expansion, private report export or production developer traffic.
Manual client evidence stays pending. Existing 013 plan's older proposed root
schema-7 wording is not a statement that this corrective slice migrates the root;
the deployed versioned acquisition migration remains owned by that feature.

## Project Structure

- `src/integrations/GreatVault.lua`: passive claim/receipt correlation.
- `src/Core.lua`: full-link manual command and existing version/help.
- `src/ui/PlayerUI.lua`: item names and non-persistent owned previews.
- `src/ui/MinimapButton.lua`: authorized window toggles and local visibility.
- `src/modules/Identity.lua`, `SyncV2.lua`: online recipient guards.
- `src/modules/AuditExport.lua`, `src/ui/OfficerUI.lua`: anonymous audit and
  descriptive statistics; HealthUI and history remain owned by 023/022.
- `tests/unit`, `tests/contract`, `tests/integration`: exact behavior evidence.

## Design

See [research.md](research.md), [data-model.md](data-model.md),
[contract](contracts/corrective-behavior.md), and [quickstart.md](quickstart.md).
No new dependencies or architectural abstraction is required.
