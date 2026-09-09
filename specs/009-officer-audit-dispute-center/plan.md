# Implementation Plan: Officer Audit and Dispute Center

**Branch**: `009-officer-audit-dispute-center` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Status**: Draft; design-ready and not implemented.

## Summary

Add one player-facing **Report a problem** action and one Officer review queue. Reports
carry available Dibs/RCLootCouncil evidence without requiring technical IDs, remain
non-authoritative until reviewed, and use clear primary resolutions: Correct balance, No
correction, and Ask for information. Any balance change goes through a protected append-only
correction path; requests, replies, decisions, evidence, and actors form an auditable timeline.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Dependencies**: Existing Ace3 UI, Dibs `Ledger`, `ProtectedActions`, permissions,
RCLootCouncil evidence adapter, guild isolation, diagnostics, and optional reconciliation,
readiness, and backup features.

**Storage**: Versioned guild-scoped SavedVariables for bounded requests, replies, evidence
links, status transitions, and append-only audit events.

**Testing**: Fengari contract/integration tests plus manual player/Officer privacy, duplicate,
concurrency, reload, and combat checks.

**Constraints**: Player reports never mutate authoritative data, only GM/Officer actors may
resolve, existing transactions stay immutable, user text is bounded/safe, and live loot
authority remains RCLootCouncil's.

## Constitution Check

- **Authority**: only verified guild GM/Officer may review, resolve, reopen, or correct;
  ML/raid/council roles alone do not grant access.
- **Ledger**: correction uses a linked compensating append-only transaction; no in-place edit.
- **Privacy**: players see their own safe request summary; queue, notes, and complete
  evidence are Officer-only and guild-scoped.
- **RCLootCouncil ownership**: a dispute may explain Dibs evidence but cannot override an RC
  award decision or expose live candidates/votes.
- **Combat/release**: protected UI/actions defer in combat; schema, docs, changelog, and
  version are required before release.

## Project Structure

```text
src/modules/Disputes.lua                 requests, status lifecycle, duplicate detection
src/modules/Ledger.lua                   linked compensating transactions
src/modules/ProtectedActions.lua         authority and correction boundary
src/integrations/RCLootCouncil.lua       optional award/history evidence links
src/integrations/RCLootCouncilOptions.lua Officer queue and actions
src/ui/PlayerUI.lua                      report form and own-request view
src/ui/OfficerUI.lua                     review queue and evidence detail
tests/integration/dispute_center_spec.lua
tests/contract/dispute_authority_privacy_spec.lua
```

## Delivery Phases

### Phase 0: Contract and lifecycle

Define categories, bounded text, statuses, duplicate key, evidence confidence, primary and
advanced resolutions, actor/audit fields, and privacy scopes.

### Phase 1: Player reporting

Prefill the player's own context, submit non-authoritative reports, detect active duplicates,
and support bounded replies when an Officer asks for information.

### Phase 2: Officer queue and evidence

Build newest-first queue, filtering, evidence cards, unavailable-field labels, and links to
Dibs transactions/RCLootCouncil history without leaking unrelated live state.

### Phase 3: Resolution and audit

Implement no-correction, duplicate, ask-information, correction, and advanced paths with
explicit confirmation/reason, linked append-only accounting, concurrency guards, and a
complete timeline.

### Phase 4: Verification and release

Run authority/privacy/replay/combat/reload tests and manual player/Officer flows; update
migration, docs, changelog, and version metadata.

## Complexity Assessment

No exception is requested. The center is a bounded request/audit layer over existing protected
actions and does not become a second award or permission system.
