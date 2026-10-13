# Research: Turnkey Guided Setup

## Decision 1: Keep `Dibs.Wizard` as a projection and orchestration layer

**Decision**: Extend the existing Wizard module with profile descriptions, preview,
apply, and grouped verification projections. Continue deriving truth from Installation,
OperationalPolicy, SetupAssistant, Readiness, Seasons, RankRules, PreDibs, Sync, and
RCLootCouncil adapters.

**Rationale**: The module already exists specifically to compose those systems and
owns no authoritative SavedVariables. Reusing it avoids a second readiness engine and
keeps corrections visible immediately after authoritative state changes.

**Alternatives considered**:

- Store a separate wizard checklist: rejected because it can become stale.
- Move setup policy into OfficerUI: rejected because UI must not own policy or mutations.
- Replace SetupAssistant/Readiness: rejected because those are existing authorities.

## Decision 2: Use three user stages while preserving all checks

**Decision**: Present Choose, Configure, and Verify. Existing checks become grouped
verification results rather than fourteen navigation buttons.

**Rationale**: Most current steps are status checks, not user decisions. Grouping
preserves coverage while meeting the two-minute setup goal.

**Alternatives considered**:

- Keep fourteen steps and add more text: rejected because it increases cognitive load.
- One-click setup with no preview: rejected because users could not understand effects.
- Hide successful checks entirely: rejected because users need reassurance and auditability.

## Decision 3: Reuse approved loot-rule presets

**Decision**: The progression and broad profiles reuse the existing semantic presets
already exposed by the RCLootCouncil options adapter. Custom mode applies nothing and
routes users to advanced pages.

**Rationale**: These presets already encode project-approved safe categories, Catalyst
blocking, and standalone fallback behavior.

**Alternatives considered**:

- Invent new profile rules: rejected because no new business rules were requested.
- Require RCLootCouncil: rejected because integration is optional.

## Decision 4: Preview and apply must be explicit and idempotent

**Decision**: Profile application returns an ordered per-action result. It skips work
already satisfied, stops success claims on failures, and never mutates ledgers.

**Rationale**: Existing guilds must not be overwritten, and repeated setup must not
create duplicate revisions or allocations.

**Alternatives considered**:

- Blindly invoke every operation: rejected because it can create needless revisions.
- Roll back successful authoritative actions after a later failure: rejected because
  several operations are append-only or synchronized; explicit partial results are safer.

## Decision 5: Reserve red for true blockers

**Decision**: Map authoritative impossible/denied/blocking states to red. Use warning
for recoverable or recommended conditions, success for ready, and muted/info for optional.
Every state also has a text label and explanation.

**Rationale**: Color alone is inaccessible and overusing red makes valid setups look
broken. The user explicitly requested red pointers for required missing work.

**Alternatives considered**:

- Render all non-ready checks red: rejected because raid-context and optional integration
  checks are expected to be unavailable outside raids.

## Decision 6: Progressive documentation

**Decision**: Show a short purpose and outcome at all times, plus expandable or clearly
separated details for effects, preserved data, authority, and troubleshooting.

**Rationale**: This provides substantial documentation without recreating the current
wall of technical status text.

**Alternatives considered**:

- External documentation links only: rejected because users need help in context.
- Always show every paragraph: rejected because it undermines a turnkey workflow.
