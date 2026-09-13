# Data Model: Midnight UI and Safe Developer Sandbox

## Ownership rule

B11 separates local presentation state, sandbox state, and production authoritative state.
No presentation or sandbox entity is part of guild policy, SyncV2, ledger accounting,
RCLootCouncil history, governance, identity, coordinator authority, or recovery truth.

## Midnight Design Token Set

Local immutable/default presentation values used by Dibs-owned components.

| Field | Meaning | Validation |
| --- | --- | --- |
| `theme` | Primary theme identifier | Always `MIDNIGHT`; no external replacement themes |
| `colors` | Semantic and surface colors | Includes PRIMARY, TEXT, TEXT_MUTED, SUCCESS, WARNING, DANGER, INFO |
| `typography` | Font family, sizes, line heights | Shared-media font with native fallback; readable minimums |
| `spacing` | Padding, gaps, row heights | Stable dimensions for supported window sizes |
| `surfaces` | Panels, borders, status bars, textures | Shared-media values with native fallback |
| `density` | Compact/comfortable presentation hint | Local-only, bounded values |
| `scale` | Local UI scale | Positive bounded value; never synchronized |
| `contrast` | Normal or high-contrast Midnight adjustment | Does not create a second theme |

## UI Environment Adapter Snapshot

Best-effort local projection from an installed external UI environment.

| Field | Meaning | Validation |
| --- | --- | --- |
| `environment` | `NATIVE`, `ELVUI`, `TUKUI`, `ELLESMERE`, or `BENIKUI` | Allowlist only |
| `status` | `absent`, `available`, `unsupported`, or `failed` | Failed/unsupported falls back to native |
| `hints` | Font, media, density, border, texture, or scale hints | Presentation keys only; invalid values ignored |
| `reasonCode` | Bounded diagnostic | Local display only |
| `observedAt` | Last probe time | Non-authoritative timestamp |

## Local Presentation Profile

Character-local saved preferences for Midnight appearance, scale, density, adapter choice,
window positions, and LibWindow restoration metadata. It is never guild-scoped or synced.

## Developer Sandbox Store

Separate versioned local store, preferably under a developer SavedVariables root such as
`RCLootCouncilDibsDevDB`.

| Field | Meaning | Validation |
| --- | --- | --- |
| `schemaVersion` | Sandbox schema version | Future versions reject activation without rewrite |
| `sourceFingerprint` | Production snapshot identity used for clone/refresh | Informational and local |
| `snapshot` | Data-only sandbox projection | Deep-copied; no frames/functions/userdata |
| `scenarioId` | Active or last selected fixture | Allowlisted scenario |
| `simulatedRole` | `PLAYER`, `OFFICER`, or `GUILD_MASTER` | Effective only while sandbox active |
| `simulatedCoordinator` | `ON` or `OFF` | Effective only while sandbox active |
| `faults` | Bounded injected states | Sandbox-only; no transport/event side effects |
| `lastUpdatedAt` | Local persistence timestamp | Informational |

The store may survive reload. Reload always clears active state and simulated authority;
explicit sandbox entry is required before the store can become a provider.

## Sandbox Runtime Context

Ephemeral provider-selection state, never persisted as production data.

| Field | Meaning | Invariant |
| --- | --- | --- |
| `mode` | `PRODUCTION` or `SANDBOX` | Exactly one provider is active |
| `developerModeEnabled` | Local developer gate | Alone grants no authority |
| `sandboxActive` | Explicit lifecycle state | True only after valid entry |
| `providerId` | `production` or `sandbox` | Mixed provider selection fails closed |
| `warning` | Persistent UI warning | Must identify sandbox and simulated role |
| `authorityOrigin` | `verified_production` or `simulated_sandbox` | Production actions reject simulated origin |

State transitions:

```text
PRODUCTION
  -> DEV_ENABLED              (/dibs dev on)
  -> PRODUCTION               (/dibs dev off, reload)

DEV_ENABLED
  -> SANDBOX_ACTIVE           explicit enter after valid store/clone
  -> PRODUCTION               (/dibs dev off, reload)

SANDBOX_ACTIVE
  -> SANDBOX_ACTIVE            scenario/role/fault/refresh/reset
  -> DEV_ENABLED               explicit exit
  -> PRODUCTION                developer off or reload
```

## Sandbox Scenario

Named bounded fixture used to exercise projections and diagnostics without production
traffic.

Required scenario families include normal player, zero balance, active Pre-Dibs,
pending Officer requests, GM operation, coordinator on/off, `SYNC_BEHIND`,
`RECOVERY_PENDING`, absent/degraded/unsupported RCLootCouncil, large lists, ambiguous
identity, and competing proposals.

Each scenario has an identifier, display label, data fixture, optional faults, and a
resettable seed. A scenario cannot provide a production actor, live award, RC evidence,
addon message, or global WoW event.

## Dashboard Status Summary

Read-only projection assembled from normalized services.

| Field | Scope |
| --- | --- |
| `activeSeason` | Player and Officer summary according to permission |
| `ledgerStatus` | Officer detail; player-safe summary only |
| `syncStatus` | Bounded status/reason; no raw payloads |
| `coordinatorStatus` | Officer summary; simulated only in sandbox |
| `rclootcouncilCapability` | Normalized absent/operational/degraded/unsupported |
| `pendingRequests` | Count/list according to actor scope |
| `activePreDibs` | Current actor or authorized administrative scope |
| `recentActivity` | Bounded readable activity projection |
| `diagnostics` | Expandable technical details, never the primary message |

## Reconciliation Workflow State

UI-only state around existing normalized evidence.

```text
SEARCH -> REVIEW_CANDIDATES -> DECISION_PENDING -> COMPLETE
                         \-> BLOCKED/AMBIGUOUS
```

The workflow stores selected session/candidate identifiers, bounded search counts,
classification, decision intent, stale-state marker, and completion status. It does not
own evidence or accounting. Confirm/reject delegates to existing protected services.

## Component Refresh State

Per-window ephemeral state:

- `dirty`: whether a domain or presentation change requires projection refresh;
- `refreshQueued`: whether one refresh is already scheduled;
- `refreshGeneration`: monotonically increasing local render generation;
- `lastRefreshAt`: diagnostic timestamp;
- `refreshCount`: test-visible bounded counter.

Repeated invalidations before the scheduled refresh produce one coalesced refresh.
