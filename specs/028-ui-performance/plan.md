# Implementation Plan: UI Rendering and Data Read Performance

**Branch**: `028-ui-performance`
**Date**: 2026-10-31
**Spec**: `specs/028-ui-performance/spec.md`

## Summary

Reduce measured synchronous costs through grouped ledger reads and narrowly
scoped projection reuse. First priority is Dibs Administration, whose visible
balance calculation measured 154.5 ms. Next, decompose Guided Setup (~193 ms)
and the Officer integration page (~328 ms, with an AceConfig/RCLootCouncil
counter around 221 ms) before choosing optimizations. Player and Sync work must
be selected from nested measurements and preserve current data semantics.

## Technical Context

| Item | Value |
|---|---|
| Language | Lua 5.1 as embedded by WoW Retail |
| Runtime | WoW Retail; no in-game runtime is available in the repository test environment |
| Dependencies | Existing addon modules, WoW APIs, AceGUI/AceConfig, optional RCLootCouncil adapter |
| Persistence | Existing guild-scoped SavedVariables; no schema or persistence change planned |
| Tests | `lua tests/run.lua` with `DIBS_TEST_FILES` selecting the smallest relevant slice |
| Profiling | Existing opt-in `/dibs perf` counters based on `debugprofilestop`; heap deltas are global net samples |
| Performance goals | Reduce measured hot-path CPU without stale data or changed user-visible behavior; compare under the same client/data/page sequence |
| Constraints | No forced GC, per-event logging, third-party source edits, history truncation, or unbounded cache |
| Scale | Small test guilds and live guild rosters, with tests up to 60 peers and user guilds expected to have hundreds of offline members |

## Constitution Check

- **World API / combat safety:** No new API or combat-sensitive background work is required. Any deferred work proposal remains out of scope until separately reviewed.
- **Ledger integrity:** Balance summaries stay read-only and derivable from the existing ledger; transaction semantics and hashes remain unchanged.
- **Visibility and UI:** Preserve all roster members, existing pagination, search, sorting, and permissions. Visible-row bounds remain a render optimization only.
- **RCLootCouncil boundary:** Treat AceConfig as an external integration cost. Do not edit RC or embedded library code; keep standalone Dibs usable.
- **Evidence and bounded work:** Each optimization requires a discriminating test and a same-condition in-game report before claiming a live gain.
- **Versioning/docs:** Before accepting addon behavior changes, follow the repository's changelog and TOC version policy. Internal instrumentation-only changes must stay opt-in and low overhead.

**Gate result:** Pass with the constraints above. No architecture or persistence migration is proposed.

## Design

### 1. Batch balance summary reads

Resolve the selected ledger once, then compute/reuse each requested player's
existing history summary. Use the grouped API for visible rows and for a full
roster balance sort. Preserve per-player summary cache validation and the
existing individual API as a fallback. The normal name/rank page still computes
only the balances it renders; balance sorting still computes every matching
row before sorting.

### 2. Guided Setup decomposition before reuse

The latest nested report showed that installation legacy detection resolves
the active ledger independently for Ledger and Pre-Dibs. Resolve that ID once
and pass it to both read-only status checks. The change preserves which active
ledger is inspected and does not cache its results. After validating this
reduction, inspect remaining SetupAssistant (~40 ms), readiness (~22–27 ms),
and rank summary (~35 ms) work. Reuse a revision-keyed source projection only
where every mutation invalidation path is explicit. Do not cache the whole
Wizard result based on guessed timestamps or recompute it in the background.

### 3. RCLootCouncil integration boundary

Trace the 221 ms AceConfig/RCLootCouncil counter to its caller and determine
whether repeated Dibs-side option construction is involved. Prefer avoiding
redundant Dibs wrapper/tree work. If most time is inside RC/AceConfig, record
that as an external limit and do not change third-party files or cache mutable
provider options without a supported invalidation signal.

### 4. Player and Sync follow-up

Keep measuring view-model, page, digest, and cache-hit/miss counters separately.
Only optimize a path with an identified repeated scan/copy. Any Sync summary
cache must use authoritative revision/hash invalidation and retain protocol
payloads and ordering. Heap deltas are not used as allocation-volume estimates.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Batch reads return a different balance or omit a player | Compare against the individual summary API for populated and empty state; retain fallback |
| A cache serves stale Wizard or Sync data | Require explicit revision inputs and mutation invalidation tests; otherwise do not cache |
| Balance sorting changes order | Test ascending/descending sorting and equal-balance tie behavior over the full filtered roster |
| RC integration cache becomes stale | Do not retain provider-owned options without a documented invalidation event |
| Test harness passes while Retail behavior differs | Report tests separately from user in-game validation; use same-session before/after measurements |
| Memory counters are misread | Keep the existing global heap-delta caveat; make no memory-leak claim without retained-memory sampling |

## Project Structure

```text
src/modules/Ledger.lua
src/modules/Wizard.lua
src/modules/SyncV2.lua
src/ui/OfficerUI.lua
src/ui/PlayerUI.lua
src/integrations/RCLootCouncilOptions.lua
tests/integration/
tests/unit/
```

**Structure Decision:** Extend the current Ledger, Wizard, UI, and adapter paths; do not add a new runtime subsystem or SavedVariables model.

## Validation

1. Run focused tests for grouped ledger summaries, Dibs Administration, Wizard,
   PlayerUI, SyncV2, and the RC adapter for the files actually changed.
2. Run `git diff --check` only on paths changed by this feature; preserve and
   report unrelated whitespace/status issues already in the worktree.
3. Deploy manually only after local validation. In WoW, compare cold first open
   and warm reopen for the same page sequence, roster, location, and addon set.
4. Report CPU counters, page counts, cache hit/miss counts, and game FPS
   separately. Repeat after `/reload`; do not interpret heap delta as memory
   retained or bytes allocated.

## Complexity Tracking

No constitution violations or new architectural layer are proposed.
