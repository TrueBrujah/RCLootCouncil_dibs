# Research: Data Health Dashboard

## Existing anchors

- `Dibs.Readiness.Evaluate()` already owns runtime readiness, probes, reason codes, context, and RCLootCouncil status.
- `Dibs.GetPersistenceStatus()` already reports valid, migratable, recoverable-invalid, and future-schema read-only states.
- `Dibs.Sync.GetStatus()` reports unavailable, ready, and sync-behind states.
- `Dibs.Backup.List()` exposes bounded backup metadata without requiring payload display.
- `OfficerUI` already owns the Diagnostics route and debug report lifecycle.

## Decisions

- Add a read-only `Dibs.HealthUI` projection rather than duplicating domain rules in `OfficerUI`.
- Keep raw diagnostic details behind an existing UI disclosure control.
- Reuse the current Diagnostics route; do not add a second navigation owner.
- Do not add persisted health state, repair actions, or new permissions in this increment.
- Treat Fengari as evidence for projection and lifecycle behavior only; Retail protected-frame and combat behavior remains manual.
