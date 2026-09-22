# Research: First Installation Assistant

## Decision: Reuse existing readiness and protected-action boundaries

**Rationale**: `Dibs.Readiness` already evaluates season, policy, authority, installation mode, RCLootCouncil capability, raid context, channel context, and local services. `Dibs.ProtectedActions` already owns administrative mutation checks. The assistant should compose these services instead of duplicating authority or persistence logic.

**Alternatives considered**: A new setup database or wizard-completion SavedVariables flag was rejected because the roadmap requires operation without manual SavedVariables editing and the constitution forbids redundant authority state.

## Decision: Keep completion derived and transient

**Rationale**: A readiness report must reflect the current guild, season, roster, integration, and channel state each time it opens. A persisted completion flag would become stale after guild or configuration changes.

**Alternatives considered**: Persisting completed steps was rejected for the first increment; it adds migration and synchronization scope without improving the readiness criterion.

## Decision: Use the existing local dry-run

**Rationale**: `Dibs.DryRun` already provides a local validation path that is distinct from finalized awards and ledger accounting.

**Alternatives considered**: Creating a second simulation engine was rejected because it would risk divergence from the live validation boundary.

## Decision: Treat optional capabilities explicitly

**Rationale**: RCLootCouncil, raid channels, and live raid context may be absent outside a raid. The assistant must distinguish blocked Dibs administration from unavailable optional live integration.

**Alternatives considered**: Treating every missing optional capability as failure was rejected because standalone Dibs is a supported installation mode.
