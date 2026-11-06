# Spec: UI Rendering and Data Read Performance

**Status:** In progress
**Owner:** RCLootCouncil_dibs maintainers
**Date:** 2026-10-31

## Problem

Recent Retail `/dibs perf report` captures show several page builders spending
roughly 100–330 ms in synchronous Lua work. The user reports frame-rate drops
and freezes while opening Officer and Player pages. These are user observations;
the addon counters measure only instrumented synchronous sections, and Lua heap
deltas are global net changes affected by garbage collection.

## Goal

Reduce avoidable synchronous work on Dibs pages while preserving displayed data,
sorting, pagination, permissions, synchronization, and SavedVariables semantics.
Prefer one-pass/batched reads and revision-aware reuse where invalidation is
provable. Do not add broad caches or background scheduling without a measurable
need and a correctness test.

## User stories

### US1 — Fast Officer balance pages (P1)

As an Officer, I want the visible Dibs Administration rows to load their
balances without repeating ledger normalization for each row, while retaining
the full roster, correct balances, page navigation, and correct balance sort.

### US2 — Responsive Guided Setup (P1)

As an Officer, I want Guided Setup to evaluate only the information needed for
the visible result and reuse unchanged projections safely, while immediately
reflecting changes to rules, seasons, authority, roster, and synchronization.

### US3 — Efficient RCLootCouncil integration page (P2)

As an Officer, I want the integration page to avoid unnecessary Dibs-side
reconstruction when revisiting it, while leaving RCLootCouncil as owner of its
options and preserving the optional adapter boundary.

### US4 — Player and synchronization responsiveness (P2)

As a player or Officer, I want page rendering and synchronization status to
process only the required data and reuse unchanged, revisioned summaries
without stale balances, requests, history, or peer state.

## Scope and constraints

- Work only on evidenced hot paths in PlayerUI, OfficerUI, Wizard, Ledger,
  SyncV2, and the RCLootCouncil adapter.
- Keep accounting and synchronization results byte-for-byte/equivalently
  stable where they form hashes or protocol messages.
- Do not change RCLootCouncil or embedded third-party library source.
- Do not remove, truncate, or reset SavedVariables or history.
- Retain complete lists; pagination may limit rendered rows but must not hide
  records or change sort semantics.
- Do not claim in-game performance or memory improvements from static tests.

## Acceptance criteria

- Batched balance reads return the same per-player balance as the existing
  summary API and resolve/normalize the selected ledger once per batch.
- Balance sorting still evaluates every matching member before sorting; normal
  name/rank pages calculate only balances they actually display.
- Any cache has explicit input revisions, bounded retention, and tests proving
  invalidation for every relevant mutation path; otherwise it is not introduced.
- Opening/reopening each targeted page preserves its content and actions; data
  mutations become visible on refresh without reload.
- Existing unit/integration tests for ledger, Guided Setup, PlayerUI, OfficerUI,
  Sync, and RC compatibility pass, apart from failures separately identified
  as pre-existing and not caused by the change.
- In-game before/after reports use comparable conditions and distinguish cold
  misses from warm hits. Heap deltas remain labeled as global/noisy.

## Out of scope

- General UI rewrite or style changes.
- Changes to ledger schema, authority, permission model, transport protocol,
  SavedVariables migration, or third-party libraries.
- Guarantees of a fixed FPS, memory ceiling, or absolute page-render time.
- Forced garbage collection or permanent per-event logging.
