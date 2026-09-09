# Implementation Plan: RCLootCouncil Item Mapping and Installation Assistant

**Branch**: `010-rclootcouncil-item-mapping-assistant` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Status**: Implemented and released in `0.3.5`.

## Summary

The feature aligns Dibs semantic loot families with RCLootCouncil button families while
keeping the two configuration models independent. It classifies Context Tokens and Tier
Set tokens with stable evidence, excludes personal Catalyst and Cosmetic items, routes
ordinary equipment through configurable `OTHER`, and adds a narrow installation assistant
that prepares Dibs responses in the default and already-enabled RCLootCouncil sets.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Primary Dependencies**: WoW API, Ace3 (GUI, Config, Comm, Event, Timer), optional
RCLootCouncil integration.

**Storage**: Existing `RCLootCouncil_dibsDB` SavedVariables; no new external storage.

**Testing**: Fengari Lua test runner (`npx.cmd --yes fengari tests/run.lua`), static
`git diff --check`, and manual Retail UI validation.

**Target Platform**: World of Warcraft Retail client, with standalone operation when
RCLootCouncil is absent or loads later.

**Project Type**: WoW addon integration and configuration UI.

**Performance Goals**: Classification and projection are bounded by the existing item
and response-set sizes; repeated refreshes must not create duplicate entries.

**Constraints**: No RCLootCouncil source modification, protected automation, live loot
session mutation, candidate/vote/history mutation, or cross-raid data access.

**Scale/Scope**: Guild-scoped seasonal Dibs policy, the built-in RCLootCouncil response
sets, and the existing test corpus.

## Constitution Check

The delivered design passes the constitution gate:

- **WoW API safety**: metadata is read through supported APIs and failures are handled
  conservatively.
- **RCLootCouncil independence**: RCLootCouncil remains optional and authoritative for
  its own responses and awards; Dibs only projects a response configuration.
- **Semantic item policy**: `TOKEN`, `TOKEN_SET`, collections, `OTHER`, and blocked
  personal categories have explicit precedence and fallback rules.
- **Authority**: assistant actions require verified Dibs GM/Officer settings authority.
- **Ledger integrity**: configuration changes never write Dibs transactions, balances,
  history, candidates, or votes.
- **Diagnostics and privacy**: readiness and mapping status are read-only and avoid
  transmitting live loot data.
- **Release traceability**: code, tests, documentation, and package version were
  released together as `0.3.5`.

## Project Structure

The implementation is organized around the existing integration boundary:

```text
src/integrations/RCLootCouncil.lua          classification and projection policy
src/integrations/RCLootCouncilOptions.lua   mapping guide and installation assistant
src/integrations/EncounterJournal.lua       stable token metadata precedence
tests/integration/ace3_options_spec.lua     mapping and assistant regression coverage
docs/RC_OPTIONS.md                          operator-facing RCLC configuration guide
docs/TEST_PLAN.md                           manual and automated validation plan
```

## Delivery Phases

### Phase 0: Research and decisions

Research records why Dibs semantic families stay separate from RCLootCouncil set names,
why Context Token and Armor Token evidence is resolved before broad item classes, why
Catalyst/Cosmetic fails closed, and why the assistant only touches the default and
already-enabled sets.

### Phase 1: Foundational mapping

The integration defines canonical family keys, readable aliases, slot-only routing hints,
and deterministic fallback rules. The Encounter Journal and RCLootCouncil token-table
paths are checked before broad Miscellaneous or collection fallbacks.

### Phase 2: Player-safe classification

Representative Curio, Tier Set, Catalyst, Cosmetic, ordinary gear, Mount, Pet, Recipe,
and Decor cases are covered by regression tests. Personal categories are excluded before
policy lookup so a broad `OTHER` setting cannot enable them.

### Phase 3: Officer installation assistant

The UI exposes two presets—`Curio + Tier Set` and `Standard loot + collections`—plus an
idempotent refresh action. The assistant preserves existing response text, colors, order,
slot choices, and active entries, and reports capacity or late-load status.

### Phase 4: Verification and release

The automated suite, static whitespace check, documentation, TOC, internal version, and
package manifest are verified. The behavior is recorded as delivered in `0.3.5`.

## Complexity Assessment

No constitution violation or complexity exception is required. The assistant is a small
projection layer over existing RCLootCouncil configuration and does not introduce a new
storage service, synchronization protocol, or authority boundary.
