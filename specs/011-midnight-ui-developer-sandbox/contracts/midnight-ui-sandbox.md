# Contract: Midnight UI and Safe Developer Sandbox

These contracts describe the boundaries that implementation and tests must preserve.
Names are conceptual until implementation selects the compatible existing namespace
functions. They are not permission bypasses or new production authority APIs.

## Developer commands

```text
/dibs dev on
/dibs dev off
/dibs dev status
```

- `on` enables only the local developer gate.
- `off` disables the gate and exits the sandbox if active.
- `status` reports developer mode, sandbox mode, provider, simulated role, and warning.
- Unknown or malformed arguments return usage text without mutation.

## Sandbox lifecycle contract

```text
EnterSandbox(options) -> ok, contextOrReason
RefreshSandbox(options) -> ok, contextOrReason
ResetSandbox(options) -> ok, contextOrReason
ExitSandbox() -> ok, productionContextOrReason
GetSandboxStatus() -> status
```

Rules:

1. Entry requires Developer Mode and valid versioned sandbox data or an explicit clone.
2. Entry selects the sandbox provider atomically; a production/sandbox mixed provider is
   rejected.
3. Refresh and reset mutate only the separate developer store.
4. Exit clears simulated role/coordinator/fault state and restores production provider.
5. Reload starts in production mode with no simulated authority; retained sandbox data is
   eligible only for later explicit entry.
6. Invalid, future-versioned, malformed, or oversized sandbox data fails closed.

## Provider contract

```text
GetActiveProvider() -> "production" | "sandbox" | nil
ResolveAuthority(operation, actor) -> decision
ReadProjection(scope, query) -> projection
ExecuteSandboxScenario(scenarioId, options) -> result
```

- The production provider delegates to existing verified services.
- The sandbox provider resolves simulated values only for sandbox projections.
- Production protected operations reject `authorityOrigin = simulated_sandbox`.
- No provider may combine production authority with sandbox state.
- Sandbox operations never emit addon traffic, fake global events, live loot events, or RC
  authority/evidence.

## UI environment adapter contract

```text
ProbeEnvironment() -> status, hints, reasonCode
ApplyHints(tokenSet, hints) -> localTokenSet
ResetToNative() -> localTokenSet
```

Only presentation hints are accepted: fonts, media, density, borders, textures, and
scale. Unknown or invalid hints are ignored. Probe failure always returns native Midnight.

## UI projection contract

Each complex screen exposes a read-only projection and delegates mutation:

```text
BuildPlayerSummary(scope) -> summary
BuildOfficerDashboard(scope) -> summary
BuildRequestView(scope, filter) -> rows
BuildReconciliationView(sessionId) -> workflowView
RequestRefresh(reason) -> queued
```

Primary actions remain visible in the page. Context menus expose secondary actions only.
All authoritative mutations go through existing domain services or `ProtectedActions`.

## Reconciliation contract

```text
SearchHistory(criteria) -> boundedSession
ReviewCandidate(sessionId, candidateId) -> candidateView
ConfirmCandidate(sessionId, candidateId, confirmation) -> protectedResult
RejectCandidate(sessionId, candidateId, reason) -> protectedResult
```

Search and review are read-only. Confirmation/rejection revalidate permissions and stale
identity through the existing reconciliation service. No operation writes RCLootCouncil
history or changes B09 evidence semantics.

## Refresh and combat contract

- `RequestRefresh` is idempotent while a refresh is queued.
- Complex screens rebuild at most once per coalescing interval for a burst of invalidations.
- Protected frame creation, movement, visibility, and controls defer during combat and
  retry through the existing post-combat path.
- Pure projection reads may remain safe during combat when they do not touch protected UI.
