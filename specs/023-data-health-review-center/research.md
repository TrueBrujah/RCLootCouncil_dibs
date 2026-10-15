# Research: Data Health Review Center

## Decisions

### Reuse the operational Diagnostics route and add a separate review section

- **Decision**: Keep the existing operational status report intact and add a distinct findings table/actions to the same Officer Diagnostics route.
- **Rationale**: The current page already verifies Officer access and presents service status; a separate route would duplicate navigation and fragment troubleshooting.
- **Alternatives considered**: Replace the existing dashboard (rejected because it would remove readiness/persistence context); add a new Officer route (rejected because it duplicates the Diagnostics entry point).

### Treat anomaly discovery and preview as read-only

- **Decision**: Findings are projections over current guild-scoped data. The center will not persist acknowledgements, rewrite ledger entries, or synchronize health findings.
- **Rationale**: Existing ledger transactions are append-only, while safe Vault decisions already have a dedicated audited service and UI.
- **Alternatives considered**: Add new ignore/acknowledgement persistence (rejected because it introduces new authorization, audit, and synchronization semantics); correct records directly (rejected because it violates append-only accounting).

### Reuse existing Great Vault review actions

- **Decision**: Surface unresolved conflicts and incomplete/review-required acquisition states, then route Officers to the existing Vault page to resolve supported cases.
- **Rationale**: `PreDibs.ResolveVaultConflict` already enforces authority, a required reason, and an audit record. Reimplementing those actions in Diagnostics would create a second policy path.
- **Alternatives considered**: Duplicate conflict resolution in HealthUI (rejected because it bypasses or duplicates the established audit workflow).

### Export only finding categories and aggregate counts

- **Decision**: Keep the health export non-importable and project only a bounded timestamp, schema/version, finding category, and counts; omit transaction/acquisition identifiers and source payloads.
- **Rationale**: The report is for troubleshooting, not data recovery, and identifiers are not needed to explain aggregate health.
- **Alternatives considered**: Export full finding objects (rejected because identifiers and nested data may disclose personal or guild information).

## Repository Evidence

- `src/ui/HealthUI.lua` already exposes `Evaluate`, `ScanAnomalies`, `BuildCorrectionPreview`, and `ExportAnomalies`.
- `src/ui/OfficerUI.lua` renders the operational health report on the Officer `diagnostics` route and has a separate `vault` route.
- `src/modules/PreDibs.lua` stores unresolved Vault conflicts in the active ledger projection and `ResolveVaultConflict` requires guild authority and a non-empty reason and is audited. The scanner reads the existing projection directly so it does not trigger lazy state initialization.
- `specs/015-data-health-dashboard/` defines the existing read-only operational report and has a separate pending Retail validation task.
- The existing tests include `health_anomaly_contract_spec.lua` and `health_dashboard_ui_spec.lua`; the work should extend these contracts instead of inventing a new testing framework.

## Risks and Mitigations

- **False clean state if a data source is unavailable**: represent unavailable sources explicitly; do not infer an empty result.
- **Identifier leakage in exported reports**: export aggregate categories/counts only and test synthetic player names, IDs, and payload markers for absence.
- **Unsafe duplicated correction path**: only navigate to the existing Vault review workflow; other findings remain inspect/export-only.
- **Unbounded work on large saves**: scan on demand, avoid extra full copies, and validate against representative large fixtures.
