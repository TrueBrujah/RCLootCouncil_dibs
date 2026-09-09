# Implementation Plan: Raid Readiness and Dry-Run Center

**Branch**: `008-raid-readiness-dry-run` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Status**: Draft; design-ready and not implemented.

## Summary

Add a pre-raid readiness center that evaluates standalone Dibs administration and optional
RCLootCouncil live-award integration separately. It reports `Ready`, `Degraded`, `Blocked`,
or `Unavailable` with fresh reason codes and remediation. A local dry-run exercises the
same validation decisions as a finalized award without consuming Dibs, emitting events,
sending traffic, or mutating RCLootCouncil state.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Dependencies**: Existing capability state machine, response projection, protected award
path, Ace3 UI/events/timers, permissions, diagnostics, seasons, and synchronization.

**Storage**: Bounded readiness audit/diagnostic metadata; no simulation ledger or live
session storage.

**Testing**: Fengari contract/integration tests plus manual one-client and two-client Retail
checks for readiness transitions, dry-runs, privacy, and combat safety.

**Constraints**: Read-only checks, no fake events or addon/raid traffic, no automatic repair,
no stale Ready authority, bounded reports, and no leakage of candidates/votes/balances.

## Constitution Check

- **Authority**: detailed checks, dry-runs, policy changes, and detailed reports require
  verified GM/Officer authority; raid roles never grant Dibs administration.
- **Ledger**: readiness and dry-run are read-only; live award handling revalidates through
  the existing protected path.
- **RCLootCouncil ownership**: probes inspect capabilities and projections without writing
  history, candidates, votes, sessions, or SavedVariables.
- **Privacy/diagnostics**: safe reports omit live/private data; verbose traces follow scopes.
- **Combat/release**: UI defers in combat; all new fields/scopes are migrated, documented,
  changelogged, and versioned before release.

## Project Structure

```text
src/modules/Readiness.lua                 probes, status, freshness, safety gate
src/modules/DryRun.lua                    synthetic validation and deterministic result
src/integrations/RCLootCouncil.lua        capability revalidation and live-award gate
src/integrations/RCLootCouncilOptions.lua  Officer readiness/dry-run/report UI
src/ui/PlayerUI.lua                       safe readiness summary
src/ui/DebugLogsUI.lua                    bounded diagnostic report
tests/integration/raid_readiness_spec.lua
tests/contract/raid_dry_run_spec.lua
```

## Delivery Phases

### Phase 0: Probe and report contract

Define status classes, freshness/configuration fingerprint, reason codes, remediation,
safe/Officer report scopes, and dry-run outcome vocabulary.

### Phase 1: Readiness probes

Evaluate season/policy, authority, installation mode, integration capabilities, current
Master Looter, response projection/alias, award identity, synchronization, and local
services. Distinguish expected no-group/no-channel context from failure.

### Phase 2: Dry-run center

Accept bounded synthetic item/winner/response/status/session inputs; reuse validation code,
return deterministic would-allow/would-ignore/would-reject/would-review, and retain only
bounded diagnostics.

### Phase 3: Safety gate and UI

Invalidate stale results on lifecycle/config/roster changes, revalidate live awards at
receipt, expose Officer controls and player-safe summaries, and copy privacy-safe reports.

### Phase 4: Verification and release

Test all status classes, replay, absent/degraded integration, privacy, combat, and no-mutation
invariants; then update docs, migration, changelog, and version metadata.

## Complexity Assessment

No exception is requested. The center composes existing capability and protected-action
boundaries and does not introduce a new synchronization or accounting authority.
