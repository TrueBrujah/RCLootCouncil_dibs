# Research: Midnight UI and Safe Developer Sandbox

## Decision 1: Keep Midnight as the only Dibs theme

Use one Dibs-owned Midnight token set and component vocabulary. External UI addons may
supply presentation hints through optional adapters, but they do not define a second theme
or alter Dibs behavior.

**Rationale**: A single theme keeps screenshots, accessibility rules, fallback behavior,
and test fixtures stable. It also honors the requirement that ElvUI, Tukui, EllesmereUI,
and BenikUI-family integrations remain optional presentation adapters.

**Alternatives considered**:

- Build a full theme per external UI addon: rejected because it multiplies UI behavior and
  makes fallback and accessibility validation inconsistent.
- Let each screen style itself: rejected because the current AceGUI windows need shared
  sizing, state, and refresh conventions.

## Decision 2: Extend the existing Dibs-owned UI boundary

Keep `src/ui/AceGUI.lua` as the reusable adapter and evolve `PlayerUI.lua`,
`OfficerUI.lua`, `LogsUI.lua`, and `DataUI.lua` through shared Midnight components. Keep
AceConfig for simple settings and use the existing dropdown facility for secondary actions.
Use LibSharedMedia and LibWindow where already embedded, with native fallbacks.

**Rationale**: The architecture already separates UI controllers from domain modules and
already has modeless windows, tables, tabs, scrolling, search, pagination, combat-safe
lifecycle, media, and position persistence. Reusing that boundary avoids a second UI
framework and preserves the established callback surface.

**Alternatives considered**:

- Replace the UI layer wholesale: rejected because it risks B08 combat ownership and
  existing public UI behavior.
- Put complex screens in AceConfig: rejected because AceConfig is appropriate for simple
  options, not bounded search/review workflows or modeless tables.

## Decision 3: Use a physically separate sandbox store and provider

Introduce a versioned developer store rooted separately from `RCLootCouncil_dibsDB`, with
an active sandbox provider selected only after explicit Developer Mode and sandbox entry.
Production services remain the default provider. Reload clears active sandbox state and
simulated authority, but persisted sandbox data remains available for explicit re-entry.

**Rationale**: A separate root makes the no-write-back invariant structurally testable and
prevents simulated role values from being read by production permission, governance,
coordinator, recovery, or ledger services. The clarified reload rule supports repeatable
scenarios without allowing authority to survive reload.

**Alternatives considered**:

- Add an `isSandbox` flag inside production guild data: rejected because one shared store
  leaves accidental production writes and mixed-provider reads possible.
- Clone data only in memory: rejected because the clarified workflow requires sandbox data
  to remain available across reloads.
- Reuse production permission services with temporary role overrides: rejected because it
  violates the constitution's authority boundary and makes fail-closed behavior fragile.

## Decision 4: Sandbox mutators must be provider-scoped and traffic-free

Sandbox scenarios, role simulation, coordinator simulation, recovery states, and fault
injection operate on sandbox projections only. They must not call production ledger,
`ProtectedActions`, SyncV2 transport, RCLootCouncil award/history mutation, live loot
handlers, or fake global event emitters.

**Rationale**: `ProtectedActions` is authoritative for production mutations, while the
sandbox needs to exercise UI and diagnostics without becoming a second authority source.
A provider boundary plus explicit operation mode makes mixed production/sandbox selection
an immediate fail-closed condition.

**Alternatives considered**:

- Route sandbox actions through production `ProtectedActions`: rejected because even a
  guarded test payload would risk production mutation and audit pollution.
- Emit fake WoW or RCLootCouncil events: rejected by the constitution and unnecessary for
  testing projections through deterministic sandbox state.

## Decision 5: Treat reconciliation as a presentation workflow over existing evidence

Implement Search -> Review Candidates -> Confirm/Reject -> Complete as a UI state
projection over the existing normalized RCLootCouncil history/reconciliation services.
Confirmation and rejection continue through existing protected actions; B11 adds no RC
history writes and does not change evidence semantics.

**Rationale**: Existing tests and architecture already provide bounded preview rows,
immutable evidence, idempotent confirmation, and protected history actions. The design
should improve discoverability and diagnostics without duplicating or weakening those
contracts.

**Alternatives considered**:

- Rebuild history reconciliation in the UI: rejected because UI callbacks must not own
  accounting or evidence semantics.
- Read raw RCLootCouncil history directly from each screen: rejected because normalized
  adapter state is the established integration boundary.

## Decision 6: Coalesce refreshes at the UI controller/component boundary

State changes mark a window dirty and schedule one bounded refresh through the existing
runtime/event scheduling path. Components update their projections when possible rather
than reconstructing every complex window for each event.

**Rationale**: This meets B11's performance requirement while preserving existing combat
and lifecycle deferral. It also gives tests a deterministic dirty/refresh counter.

**Alternatives considered**:

- Refresh on every event: rejected because roster, readiness, integration, and request
  changes can arrive in bursts.
- Introduce broad list virtualization immediately: rejected because bounded guild and
  history sizes do not justify the complexity until measurements show a need.

## Decision 7: Validate with deterministic fixtures plus Retail smoke checks

Add focused unit, contract, and integration tests using `tests/helpers/load_addon.lua` and
existing WoW/Ace/RCLootCouncil doubles. Run the complete Fengari suite, static whitespace
validation, and manual Retail checks for window sizing, adapter fallback, combat deferral,
reload, sandbox isolation, and one/two-client authority boundaries.

**Rationale**: The repository's test harness already models standalone, Officer/GM,
RCLootCouncil capability, protected actions, UI widgets, and history fixtures. Retail is
still required for real WoW protected-frame behavior, media availability, and multi-client
observation.

**Alternatives considered**:

- Use only Retail manual testing: rejected because provider isolation and no-write-back
  invariants need repeatable automated assertions.
- Use only the Lua harness: rejected because protected UI, LibSharedMedia, LibWindow, and
  external UI adapter behavior require client validation.
