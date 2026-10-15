# Health Review Contract

## Access and source scope

- Every read and action requires current verified Guild Master or Officer authority.
- Sources are limited to the current guild's existing SavedVariables and existing review projections.
- Findings are transient and are not written to SavedVariables or sent through synchronization.

## Scan result

`ScanAnomalies()` returns:

- `status`: `HEALTHY`, `REVIEW_REQUIRED`, `UNAVAILABLE`, or `DENIED`.
- `anomalies`: a deterministically sorted list of safe finding projections.
- `count`: number of findings.
- `sources`: per-source `AVAILABLE`, `UNAVAILABLE`, `INVALID_SOURCE`, or `SOURCE_ERROR` status.

Each finding has a stable local `id`, `category`, `status`, `action`, and bounded localized `detail`. Supported categories include invalid season references, incomplete or duplicate acquisitions, acquisitions requiring verification, and unresolved Vault conflicts. The public projection must not contain the original transaction, acquisition, conflict, evidence, or synchronization payload.

The scan reads the active guild and active ledger projections without changing ledger or acquisition records. Any unavailable source makes the overall scan `UNAVAILABLE`, even when findings from other sources are present.

## Preview result

`BuildCorrectionPreview(findingId)` returns a read-only result:

- `PREVIEW` with safe finding details, `mutation = "NONE"`, and the supported existing next action;
- `NOT_FOUND` for an absent finding;
- `DENIED` when the caller lacks current guild authority; or
- `UNAVAILABLE` when required data cannot be evaluated.

The function MUST NOT itself perform a correction. Vault conflicts are resolved only through the existing Vault review page and service.

## Export

`ExportAnomalies()` returns a versioned health-specific encoded report, not a package accepted by the normal import path. The exported payload contains only a timestamp, bounded version/schema metadata, scan status, source/status pairs, total count, and sorted category counts. It excludes identifiers, names, notes, raw records, private evidence, raw sync payloads, and executable transactions.

If authorization or encoding fails, the function returns an explicit failure and no encoded report.
