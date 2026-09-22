# Data Model: Data Health Dashboard

The feature adds no persisted entity. `HealthReport` is transient and contains:

- `status`: `READY`, `DEGRADED`, `BLOCKED`, `UNAVAILABLE`, or `DENIED`.
- `role`: local presentation role.
- `version` and `schemaVersion`: bounded version metadata.
- `checks`: bounded `{ id, state, reason, detail }` entries.
- `blockingCount` and `warningCount`.
- `persistence`, `readiness`, `rclootcouncil`, `sync`, and `backup` status projections without raw payloads.

No SavedVariables or SyncV2 schema changes are part of this feature.
