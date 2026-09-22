# B12 Release UI Contract

This contract defines ownership and release behavior for B12. It supplements the existing addon/domain contracts; it does not replace them.

## B12 Changed-Surface Ownership Map

| Surface | Owner | B12 boundary |
| --- | --- | --- |
| Player and Officer shell, route selection, page mounting | `src/ui/PlayerUI.lua`, `src/ui/OfficerUI.lua` | Own presentation state and route lifecycle; do not persist authoritative data directly. |
| Shared widgets, tables, tooltips, menus, sizing, and refresh deferral | `src/ui/AceGUI.lua` | Own widget cleanup and layout behavior; do not decide permissions or domain values. |
| Midnight tokens, semantic states, empty states, and modal sizing | `src/ui/Midnight.lua` | Own shared presentation language; do not mutate ledger, policy, or request state. |
| Settings labels and canonical values | `src/integrations/RCLootCouncilOptions.lua`, existing domain services | Normalize at the UI boundary and delegate mutations through protected services. |
| Requests and historical candidates | `src/ui/OfficerUI.lua`, `src/ui/LogsUI.lua`, existing request/reconciliation services | Project bounded, privacy-filtered views; do not add ticket lifecycle or alter RCLootCouncil history. |
| Developer Debug and sandbox presentation | `src/ui/DeveloperUI.lua`, `src/integrations/DeveloperSandbox.lua` | Keep simulation/provider state isolated from production authority and SavedVariables. |
| RCLootCouncil capability and evidence | `src/integrations/RCLootCouncil.lua` | Report absent, degraded, unsupported, or operational state; do not replace RCLootCouncil ownership. |

## Freeze Constraints

B12 UI work must preserve the following unchanged contracts:

- No new production SavedVariables fields, synchronization payload fields, or request lifecycle states for presentation-only behavior.
- No direct UI writes to ledger, balances, policy, authority, award history, or RCLootCouncil history.
- No changes to `AWARD_COMMIT`, `AWARD_PROPOSAL`, governance, coordinator/recovery, identity, or production permission semantics.
- All dangerous mutations continue through existing authorization, readiness, confirmation, reason, and `ProtectedActions.lua` boundaries.
- Player projections remain privacy-filtered, Officer/GM evidence remains role-gated, and Developer Mode remains opt-in and provider-isolated.
- A known Retail or unrelated baseline failure must be recorded separately, never hidden by weakening a B12 assertion.

## Shell and Lifecycle

1. Player and Officer windows use the shared Midnight shell: dark translucent frame, left navigation, one primary content host, and stable footer.
2. Each window has one active page/content owner. Route changes release or replace the previous page content before rendering the next route.
3. `WindowState.lua` exclusively owns local window-position persistence and recovery. Player and Officer position records remain separate, restoration occurs once at registration, and route refresh does not restore positions.
4. `AceGUI.lua` owns shared widget release, table/dropdown cleanup, refresh coalescing, tooltip behavior, and context-menu lifecycle.
5. Closing a page or window releases its context menu and pooled page content. Opening a new context menu closes the previous one.

## Values and Presentation

1. Display labels are normalized to canonical domain values at the controller boundary before service calls.
2. Tables and lists use bounded data, stable columns, readable empty states, and explicit error states.
3. Status meaning is understandable without color alone. Normal text, muted text, restrained yellow accent, and semantic status colors follow `docs/developer/b12-ui-design-rules.md`.
4. Left-click selects or opens detail. Right-click invokes the shared object-aware context menu. Critical primary actions remain visible.
5. A menu or secondary action must not become the only path to a high-value workflow.

## Requests / Support Tickets

1. The Requests view projects existing request records into category labels, existing-state status labels, next action, explanation, and safe evidence.
2. Categories are presentation-only. No category field is persisted, synchronized, authorized, or used as a ledger key.
3. Statuses are existing request states only. No new ticket lifecycle or state transition is introduced.
4. Player and Officer/GM visibility follows the existing request privacy rules.
5. Request creation, cancellation, information requests, resolution, rejection, and any correction path delegate to existing services. The UI never writes ledger, balance, policy, or authority state directly.
6. Dangerous actions require the existing authorization and readiness checks, an explicit confirmation, a reason where the service requires one, and delegation through `ProtectedActions.lua`.

## Historical DIB Transfer

1. Search is read-only, bounded, and preview-first.
2. Review exposes item, winner, difficulty, encounter, date, classification, duplicate status, and concise evidence before technical detail.
3. Exact alias matching, unknown-field labeling, source-scan bounds, stale checks, idempotency, and related-winner evidence remain unchanged.
4. Confirm and reject are Officer/GM-authorized operations and delegate through `LogsUI.lua`, `RCLootCouncil.lua`, and the existing protected/reconciliation services.
5. No UI path mutates RCLootCouncil history or bypasses the existing historical confirmation contract.

## Safety and Isolation

1. Protected actions remain the only authoritative mutation boundary for historical, ledger, award, settings, profile, backup/import, and other dangerous operations.
2. Combat-sensitive actions defer or fail according to existing readiness behavior; B12 does not add protected automation.
3. RCLootCouncil absence, late load, unsupported capability, and degraded data produce understandable empty/error states without weakening Dibs authority rules.
4. Developer sandbox provider/store boundaries remain separate from production. Mixed-provider access remains fail-closed.
5. `SANDBOX_STORE_TOO_LARGE` is fixed only with bounded validated behavior. An accepted developer-only limitation must be documented with its isolation and user-impact conditions.

## Validation and Release Gates

1. Focused B12 tests cover ownership/lifecycle cleanup, route normalization, projections, context menus, privacy, dangerous-action delegation, and historical workflow behavior.
2. The explicit full Fengari suite runs after focused tests. The known unrelated failure at `tests/integration/rclootcouncil_buttons_spec.lua:155` is recorded separately if still present.
3. Real Retail validation is mandatory before release readiness. Single-client validation is the default matrix.
4. Two-client validation is required only if B12 changes cross-client behavior, synchronization, or another client-to-client contract.
5. A release candidate requires clean relevant diagnostics, `git diff --check`, automated evidence, Retail evidence, explicit addon version alignment, a dated changelog entry, and documented known limitations.
6. No plan, automated run, or simulated client result may be represented as Retail certification.
