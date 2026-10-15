# Data Model: Data Health Review Center

No persistent entity is added. All objects are transient projections of the active guild's existing data.

## HealthFinding

- `id`: stable, local identifier used only to open a preview.
- `category`: stable issue type such as `INVALID_SEASON_REFERENCE`, `INCOMPLETE_ACQUISITION`, `DUPLICATE_ACQUISITION`, `ACQUISITION_REVIEW_REQUIRED`, or `VAULT_CONFLICT`.
- `status`: `REVIEW_REQUIRED` or `UNAVAILABLE`.
- `action`: existing workflow hint such as `OPEN_VAULT_REVIEW` or `INVESTIGATE`.
- `detail`: bounded, localized-safe explanation; no raw evidence or player identity.

The visible and exported projections must not expose nested source records. Export omits `id` and all record identifiers.

## Source availability

The scan reports `AVAILABLE`, `UNAVAILABLE`, `INVALID_SOURCE`, or `SOURCE_ERROR` for each source. A missing source makes the overall scan `UNAVAILABLE`, even if other sources contain findings.

## ReviewPreview

- `status`: `PREVIEW`, `NOT_FOUND`, `DENIED`, or `UNAVAILABLE`.
- `finding`: the safe HealthFinding projection, when available.
- `mutation`: always `NONE`.
- `nextAction`: a supported existing workflow or `INVESTIGATE`.

## FindingsReport

- `format` and `version`: identify the non-importable report.
- `createdAt`: report generation timestamp.
- `findingCounts`: sorted category/count pairs.
- `sourceStatuses`: sorted source/status pairs, without payloads.
- `scanStatus`: the scan's `HEALTHY`, `REVIEW_REQUIRED`, or `UNAVAILABLE` result.
- `totalCount`: total findings represented.
- `identityIncluded`: always false.
- `executableTransactionsIncluded`: always false.

The report contains no player names, player IDs, transaction IDs, acquisition IDs, private evidence, raw synchronization payloads, or executable transaction objects.
