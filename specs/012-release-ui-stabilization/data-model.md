# B12 UI and Projection Data Model

B12 adds no authoritative domain entities. The records below describe transient UI projections, local lifecycle state, or release evidence. They must not be serialized into production request, ledger, RCLootCouncil, or synchronization data unless an existing contract explicitly owns that data.

## Release UI Finding

A bounded record used during implementation and validation to describe an observed UI defect.

| Field | Meaning |
|---|---|
| `id` | Stable test or evidence identifier |
| `surface` | Window, route, page, table, menu, or lifecycle surface |
| `symptom` | Observable incorrect behavior |
| `owner` | Existing controller/helper that directly controls the behavior |
| `expected` | Behavior required by the B12 contract |
| `evidence` | Focused test, diagnostic, or Retail observation |
| `status` | Open, fixed, deferred, or accepted limitation |

This is planning/evidence metadata, not addon runtime state.

## Request Support-Ticket Projection

A transient view model derived from an existing request record and current permissions.

| Field | Meaning |
|---|---|
| `requestId` | Existing request identity |
| `categoryLabel` | Presentation-only category derived from existing request data |
| `statusLabel` | Human-readable label for an existing request state |
| `nextAction` | Action currently available under existing authorization and readiness rules |
| `explanation` | Plain-language reason or state description |
| `evidence` | Existing request facts safe for the current viewer |
| `actions` | Existing callbacks, guarded by service and protected-action rules |
| `visibility` | Existing Player/Officer/GM disclosure result |

`categoryLabel` is not a persisted category field. `statusLabel` is not a new lifecycle state. The projection must tolerate unknown, legacy, pending, cancelled, invalidated, fulfilled, rejected, confirmed, and other existing states without changing them.

## Historical DIB Candidate Projection

A transient view model returned by the existing RCLootCouncil history/reconciliation services.

| Field | Meaning |
|---|---|
| `sessionId` | Existing reconciliation session identity |
| `candidateId` | Existing candidate identity |
| `item` | Item/link information when available |
| `winner` | Winner identity or unknown-field marker |
| `difficulty` | Difficulty value or unknown-field marker |
| `encounter` | Encounter value or unknown-field marker |
| `timestamp` | Historical date/time or unknown-field marker |
| `classification` | Existing eligible, accounted, ambiguous, rejected, or unsupported classification |
| `evidence` | Existing bounded source and related-winner evidence |
| `availableActions` | Existing review, confirm, or reject actions |

The projection does not mutate RCLootCouncil history. Confirm and reject remain delegated operations and must preserve authorization, reason, stale, duplicate, idempotency, and combat/readiness behavior.

## Context-Menu Action Projection

A transient list produced by the shared `AceGUI.lua` context-menu implementation.

| Field | Meaning |
|---|---|
| `objectType` | Request, candidate, item, row, or other supported object type |
| `objectId` | Existing object identity |
| `label` | User-facing action label |
| `enabled` | Current permission, readiness, and state result |
| `reason` | Safe disabled/unavailable explanation |
| `callback` | Existing controller callback, never a direct ledger write |
| `dangerous` | Whether confirmation/reason/protected delegation is required |

Only one shared context menu may be open. It is released when another menu opens and when the owning page or window closes.

## Window and Page Lifecycle State

Local, non-authoritative state owned by the existing UI layer.

| Field | Owner | Rule |
|---|---|---|
| `windowRole` | `WindowState.lua` | Player and Officer positions remain separate |
| `positionRestored` | `WindowState.lua` | Restore once at registration |
| `currentRoute` | `OfficerUI.lua` or `PlayerUI.lua` | Route changes replace the current page content |
| `contentHost` | UI controller | One active page/content owner |
| `refreshQueued` | `AceGUI.lua` | Coalesce invalidations without unbounded timers |
| `contextMenuOpen` | `AceGUI.lua` | Close on page/window close or replacement |

This state must not be used to infer authority or persist domain decisions.

## Release Candidate Record

A documentation/evidence record for a candidate build.

| Field | Meaning |
|---|---|
| `version` | Explicit addon version from the TOC/source owner |
| `automatedEvidence` | Focused and full test results |
| `diagnostics` | Workspace diagnostics and `git diff --check` result |
| `retailEvidence` | Single-client Retail matrix results |
| `twoClientEvidence` | Present only when cross-client behavior changed |
| `knownLimitations` | Explicit unrelated baselines or developer-only limitations |
| `changelogEntry` | Dated changelog reference |
| `ready` | True only after all required gates pass |

## Sandbox Limitation Record

A developer-facing documentation record for a bounded sandbox limitation. It records the observed limit, affected developer-only operation, validation, and user impact. It must state that production storage is isolated, normal users are unaffected, and Developer Mode is hidden or off by default when the limitation is accepted rather than fixed.
