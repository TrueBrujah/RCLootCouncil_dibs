# Research: UI Rendering and Data Read Performance

## Evidence reviewed

- Latest user reports show Officer Wizard around 193 ms and Officer
  Integration around 328 ms. The nested AceConfig/RCLootCouncil counter is
  about 221 ms; nested counters are part of their parent and must not be added
  to page totals.
- Dibs Administration's visible balance computation is about 154.5 ms for
  the displayed page. The roster builder already defers balances for ordinary
  name/rank sorting, but the visible-row reflow was resolving history summary
  once per row.
- Guided Setup nested measurements show installation's active-ledger resolution
  at roughly 15.7 ms per ledger check and Pre-Dibs active-ledger resolution at
  roughly 10.4 ms per history-count check. The legacy status check needs both
  checks to inspect the same active ledger, so it can resolve that ID once and
  pass it to both without retaining cached data.
- Sync digest measurements show Vault around 25.5 ms on a cache miss and
  around 0.01 ms on a cache hit. The ledger digest was previously around
  25.7 ms and is now reported between 17.4 and 22.4 ms in two samples after
  the scalar governance digest path. This is a small, noisy sample, not a
  guaranteed gain.
- Lua heap deltas swing by tens of megabytes in both directions. They describe
  global heap net change during a sample and cannot establish addon allocation
  volume or retained memory.

## Decisions

### Batch summaries instead of repeated ledger resolution

**Decision:** Resolve the ledger once and request history summaries for a
collection of players. Keep the existing per-player computation and cache
semantics behind a shared helper.

**Rationale:** The measured Dibs Administration page requests several visible
balances together. One shared ledger resolution removes repeated SavedVariables
normalization/selection without changing the balance formula, sort order, or
persisted records.

**Alternative rejected:** Cache the whole roster's balances across page opens.
That would require explicit invalidation on every ledger transaction, season,
and ledger switch and is unnecessary for this first reduction.

### Revision-keyed reuse only

**Decision:** Any further Wizard or Sync cache must name its full source
revision and have mutation invalidation tests. If that cannot be established,
optimize duplicate calls or return to profiling instead of caching.

**Rationale:** Stale authority, rank, request, or balance information would be
a correctness regression. Existing Vault digest counters demonstrate that
cache misses and hits can be measured independently.

### Treat RCLootCouncil/AceConfig as a boundary

**Decision:** Trace the Dibs call path and avoid repeated Dibs-owned wrapper
work if present. Do not modify RC or bundled AceConfig; do not memoize mutable
provider-owned option trees without an invalidation contract.

**Rationale:** The nested counter is high but may mostly measure framework or
provider option generation outside Dibs' ownership.

### Share the Wizard's active-ledger selection, not its result

**Decision:** During legacy installation status checks, resolve the active
ledger ID once and pass it into both the ledger-history and Pre-Dibs-history
read APIs. Keep both APIs' existing logic and do not cache the status result.

**Rationale:** The counters show repeated active-ledger selection is measurable
while both checks target the same active ledger. Passing the resolved ID is
bounded, keeps secondary-ledger selection intact, and avoids cache invalidation
risks.

### In-game evidence remains separate

**Decision:** Use the existing opt-in timing command for comparable cold and
warm page sequences, and record FPS separately. Do not infer an in-game gain
from Lua harness timing or heap delta.

## Unknowns to resolve during implementation

- How much of `Officer data / dibs-admin-visible-balances` is ledger
  normalization versus per-player transaction summarization.
- Whether Guided Setup or the RC integration page repeats identical work on
  ordinary reopen, and which source revisions can invalidate it.
- Whether PlayerUI's remaining page time is mostly frame/widget creation,
  layout, or a data projection not yet instrumented at a fine enough boundary.
