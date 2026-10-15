# Implementation Plan: Unified History Search and Filters

**Branch**: `022-unified-history-search` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/022-unified-history-search/spec.md`

## Summary

Add one consistent, privacy-safe filter model to existing Player and Officer history surfaces. Reuse existing ledger, Pre-Dib, Great Vault, and RCLootCouncil history projections; search only metadata those sources already expose. Keep search state local to the view, preserve current role checks, and do not add a combined multi-source timeline, persistence, synchronization, or accounting behavior.

## Technical Context

**Language/Version**: WoW Retail Lua (addon runtime)

**Primary Dependencies**: Existing `Dibs.AceGUI`, Player/Officer UI controllers, and history projection services; no new external dependency

**Storage**: Existing guild/character-scoped SavedVariables accessed through domain services; search criteria are transient UI state

**Testing**: `tests/run.lua` with Fengari; focused Player, Officer, RCLootCouncil reconciliation, privacy, and history regression suites

**Target Platform**: World of Warcraft Retail addon

**Project Type**: Lua addon with domain modules, framework adapters, and UI controllers

**Performance Goals**: Filter a synthetic 5,000-record history fixture in under 2 seconds in the test environment; keep visible rows paginated and bounded

**Constraints**: Follow guild/character isolation and Officer authorization; do not synthesize missing metadata, leak Officer evidence, mutate accounting/history, or synchronize search criteria

**Scale/Scope**: Existing Player Dibs History and Great Vault history, plus Officer ledger/actions, Pre-Dibs, Great Vault review, and RCLootCouncil history-review surfaces where fields exist

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **World of Warcraft API Compliance**: PASS. Read-only filtering uses existing addon data and UI helpers; no protected gameplay action or new game API is required.
- **Dibs Are Not DKP / Append-Only Ledger**: PASS. Search is a projection only and cannot add, alter, remove, or account for records.
- **Player and Administrative Visibility**: PASS. Player results remain personal; guild-wide results retain the existing verified GM/Officer boundary and player-safe projections.
- **Synchronization and guild scope**: PASS. No messages, protocol changes, cross-raid data, or changes to synchronization are introduced.
- **UI and localization**: PASS. Existing Midnight tables, bounded pagination, explicit empty/unavailable/error states, and English/French localization are reused.
- **Change notes and versioning**: REQUIRED during implementation. The `0.8.7-dev` build includes the earlier unreleased development work; keep the README, TOC, runtime version, and dated changelog entry aligned.
- **No unexplained complexity**: PASS. A small shared UI filtering helper is justified to keep Player and Officer matching/date semantics consistent. No database, new permissions, or external service is required.

## Project Structure

### Documentation (this feature)

```text
specs/022-unified-history-search/
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── ui-history-filters.md
├── quickstart.md
└── tasks.md
```

### Source Code

```text
src/ui/
├── HistoryFilters.lua       # Shared pure filtering and date-range validation
├── PlayerUI.lua             # Personal Dibs and Great Vault history controls
├── OfficerUI.lua            # Authorized guild ledger, requests, and Vault filters
└── LogsUI.lua               # Existing RCLootCouncil history search boundary

src/locales/
├── enUS.lua                 # Filter labels, help, validation and result states
└── frFR.lua

tests/
├── unit/                    # Matching rules and date-range edge cases
└── integration/             # Player privacy, Officer authorization, filter UX
```

**Structure Decision**: Keep the shared search behavior in the existing UI layer. `HistoryFilters.lua` is a pure presentation helper loaded before `PlayerUI.lua` and `OfficerUI.lua`; source-specific authorized projections remain owned by their existing controllers and services.

## Phase 0: Research

Repository inspection established the following prior art:

- Player Dibs History has a text search and current/all-season switch in `src/ui/PlayerUI.lua`; its current matcher searches formatted transaction lines.
- Player Great Vault history already uses the player's privacy-safe acquisition projection and bounded pagination.
- Officer ledger details already accept player, action type, source, and inclusive timestamp criteria through `BuildLedgerDetails`.
- Officer Great Vault review already applies guild-member filtering, a text query, status, and season constraints, but currently searches a narrower field set.
- RCLootCouncil history review is a separate preview workflow through `Dibs.LogsUI.SearchHistory`; it remains behind its existing verified Officer authorization and must retain its preview/confirmation boundary.
- Existing source records vary in available metadata, so the shared matcher must treat absent metadata as absent rather than using display fallbacks as searchable values.

No external research or technology choice is required. The user clarification selected common filters in existing pages, not a merged timeline.

## Phase 1: Design

- Represent user-entered criteria as transient view state.
- Match text against permitted, raw recorded fields (including item, player where permitted, source/status, and encounter fields when present); do not match display placeholders such as "Unknown" or private evidence.
- Normalize date criteria as inclusive local-calendar boundaries and reject invalid or reversed ranges before querying.
- Use AND semantics across active criteria and deterministic newest-first sorting, followed by existing bounded pagination.
- Keep player and officer field access distinct; the shared helper receives only the already-authorized record projection.
- Report unavailable sources separately from an available source with no matching records.
- Add no SavedVariables, protocol, transaction, migration, or eligibility changes.

## Complexity Tracking

No Constitution violations or unjustified complexity.
