# B12 Retail Validation Evidence

## Status

`PENDING_MANUAL_RETAIL_VALIDATION`

Date prepared: 2026-09-22

The current VS Code/Fengari environment does not provide a WoW Retail client or
BugSack runtime. No single-client Retail execution is claimed from this record.
T051 remains open until the matrix below is executed in a real supported Retail
client.

## Automated evidence

- Focused B12 Fengari suite: `55 passed, 0 failed (16 files)`.
- Explicit full Fengari suite: `541 passed, 0 failed (128 files)`.
- Workspace diagnostics for touched B12 files: clean.
- `git diff --check -- specs/012-release-ui-stabilization src tests docs`: clean
  apart from normal Windows LF/CRLF warnings.
- Fengari results do not replace Retail BugSack, taint, lifecycle, or visual
  validation.

## Single-client matrix pending

Execute and record evidence for:

- Ten Player and Officer open/close cycles with no duplicate frames, headers,
  callbacks, or stale content.
- Every Player and Officer route, including History/Reconciliation, Settings,
  Loot Eligibility, Debug, and RCLootCouncil integration.
- Window movement, resizing, reload/relog position restoration, and narrow/wide
  layouts without overlap or clipped actions.
- Request, item, player, and historical context-menu replacement and cleanup.
- Both `WILD_OPEN` and `ENCOUNTER` Pre-Dib modes.
- Combat entry/exit around UI refreshes, menus, and protected actions.
- RCLootCouncil absent, disabled, late-loaded, degraded, operational, and
  unsupported states.
- Player-safe confirmed history versus Officer-only candidate and technical
  evidence.
- Historical preview, confirm, reject, duplicate, stale, ambiguous, and
  unknown-field cases with no RCLootCouncil history mutation.
- Developer Mode bounded storage, default-off behavior, provider isolation, and
  production-state isolation.

After each group, inspect BugSack and the client error frame. Record zero new
Dibs-attributable Lua, taint, lifecycle, stale-content, privacy, or contamination
findings before changing the status to complete.

## Cross-client applicability

`NOT REQUIRED: no B12 cross-client behavior change.`

B12 changes covered by this evidence are UI projections, protected historical
review delegation, context-menu safety, Player/Officer disclosure, tests, and
validation documentation. They do not change SyncV2, synchronization payloads,
coordinator/recovery behavior, or cross-client state propagation. The conditional
T052 two-client matrix therefore does not apply.

## Release gate

Release readiness remains false until T051 is executed and this record is updated
with dated Retail results. The known unrelated baseline at
`tests/integration/rclootcouncil_buttons_spec.lua:155` remains separate from B12
validation.
