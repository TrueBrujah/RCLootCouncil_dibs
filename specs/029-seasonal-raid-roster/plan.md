# Implementation Plan: Roster saisonnier et inscriptions aux raids

**Branch**: `029-seasonal-raid-roster` | **Date**: 2026-11-07 | **Spec**: [spec.md](spec.md)

## Summary

Make one canonical raid season the owner of its registration window, rules and policy versions, approved roster, Main/Alt snapshot, rank allocations, reconciliation, Dibs ledger, and archive state. Keep those records in their existing domain modules where practical, but use the same `seasonId` and a revisioned activation manifest to prevent a roster, ruleset, and ledger from referring to different seasons. Preparation and registration never change the active ledger. A verified GM/Officer previews and explicitly activates a ready season. Season allocation and reconciliation process only approved participants, not every guild character.

## Technical Context

**Language/Version**: Lua supported by WoW Retail; addon restrictions apply.
**Primary Dependencies**: Existing Dibs modules, Ace3/AceGUI, SyncV2, CharacterEligibility, Permissions, FeatureRegistry, and the append-only Ledger. RCLootCouncil remains optional.
**Storage**: Guild-scoped SavedVariables; additive, versioned schema and migrations.
**Testing**: Existing Lua unit/integration harness (Fengari); two-client Retail validation for live authority, sync and UI.
**Target Platform**: WoW Retail addon sandbox, offline-capable and synchronized through addon messages.
**Project Type**: WoW addon feature across data services, UI, permissions, sync, localization, docs, tests.
**Performance Goals**: Season activation/reconciliation cost scales with approved enrollment count, not total guild roster. Keep UI work bounded and preserve responsive paginated lists. Establish measurable budgets in tests using representative 20–60 raid participants and hundreds/thousands of guild members.
**Constraints**: No external identity service; no protected action automation; bounded messages/staging; multi-writer conflict detection; no destructive migration; no silent balance carry-over; preserve optional RCLootCouncil and module gating.
**Scale/Scope**: Guild with roughly 900 characters, 20–60 active raid participants, several seasons of history, and hundreds of enrollment/audit records.

## Constitution Check

- Seasonal, independent guild-rank allocations: **PASS** — allocation rules remain data for each season and preserve rank-at-transaction snapshots.
- Append-only ledger/audit: **PASS** — activation and reconciliation append idempotent events; no historical transaction rewrite.
- Verified GM/Officer authority: **PASS** — serverless authority is checked at each local and received mutation; roster rank is current and guild-scoped.
- WoW API and optional RCLootCouncil: **PASS** — no protected gameplay automation; feature works without RCLootCouncil.
- Bounded sync and multi-writer safety: **PASS with design gate** — compatible revisions/manifests, bounded staging and stale-write rejection required before implementation.
- Additive migration and SavedVariables preservation: **PASS with design gate** — existing Dibs seasons, roster records, aliases, and ledgers are preserved; no guessed identity merge.
- Performance and UI responsiveness: **PASS with design gate** — only approved cohort is reconciled; lists are paginated and expensive work is measured.

No constitution exception requested. Re-check these gates after implementation design and before implementation.

## Design

### Phase 0: Research

- Trace the current season catalog, seasonal roster, ledger, per-season RankRules, character identity, permissions, module policy, and SyncV2 revisions in the active branch.
- Decide the canonical season identity and preserve older roster-to-Dibs identifiers as explicit aliases.
- Define the activation commit point, manifest requirements, stale revision behavior, and recovery semantics.
- Define rank lookup and a configured no-WoW-rank policy for external participants.
- Verify migration behavior from the existing schema without deleting or rewriting SavedVariables.
- Determine concrete limits from the existing SyncV2 constants and stress-test roster/manifest sizes before implementation.

### Phase 1: Data model and contracts

- Define the season lifecycle and legal transitions.
- Define independently versioned season rules, status catalog, enrollment, Main/Alt relationship snapshot, approval, allocation, reconciliation preview, and activation manifest.
- Keep informative raid rules distinct from settings the addon actually enforces.
- Specify player and officer service operations plus authority, idempotency, expected revision, and error behavior.
- Specify digest/detail synchronization by bounded entities; no single unbounded roster payload.
- Provide executable validation scenarios and manual Retail checks.

### Phase 2: Implementation order

1. Add additive canonical season identity and migration/alias reads.
2. Implement service validation, lifecycle transitions, audit, revision conflicts, and module gating.
3. Add versioned season rules/statuses and player signup/public read-only roster.
4. Add officer review, Main/Alt integration, and manual Core promotion.
5. Add per-season rank allocation, explicit no-rank behavior, and separate historical balance reconciliation.
6. Add previewed, idempotent activation with an atomic visibility/manifest commit point.
7. Add bounded SyncV2 propagation and recovery for season dependencies.
8. Add responsive UI, localization, docs, tests, and Retail comparison evidence.

## Project Structure

```text
src/
  Core.lua
  modules/
    SeasonalRoster.lua
    Seasons.lua
    CharacterEligibility.lua
    Ledger.lua
    Permissions.lua
    OperationalPolicy.lua
    SyncV2.lua
  ui/
    PlayerUI.lua
    OfficerUI.lua
  locales/
    enUS.lua
    frFR.lua
tests/
  unit/
  integration/
specs/029-seasonal-raid-roster/
  spec.md
  plan.md
  research.md
  data-model.md
  quickstart.md
  contracts/
```

**Structure Decision**: Extend the existing single-addon architecture and domain services. Do not create a second season subsystem or modify RCLootCouncil core. Storage may remain split by domain for bounded sync and ownership, but canonical identity and activation coherence are shared.

## Risks and Release Gates

- Old roster seasons and Dibs seasons may not map one-to-one. Migrations must preserve IDs and require an explicit reviewed alias before activation if association is uncertain.
- Synchronization can deliver a season, roster, rules, and ledger at different times. Clients must expose a season as active only after the manifest dependencies match.
- Guild rank can change during registration. Allocation preview and apply must use the same roster/rank snapshot revision or require a refreshed preview.
- Out-of-guild characters have no native guild rank. The season must explicitly configure their allocation or exclude them.
- Manual Core promotion records an officer decision; it is not attendance/performance evidence.
- Live two-client sync, combat safety, real addon memory/CPU, and visual behavior cannot be established by static tests alone.

## Complexity Tracking

No constitution violations or extra projects are introduced.
