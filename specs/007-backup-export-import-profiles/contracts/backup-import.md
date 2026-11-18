# Contract: Dibs Backups, Data Transfer, and Configuration Profiles

## Package scopes

| Scope | Contains | Default authority |
| --- | --- | --- |
| Local presentation | Character UI/profile settings | Character owner |
| Guild configuration | Guild policy and allowed profile fields | Verified GM/Officer |
| Full Dibs data | Ledger, evidence, audit, and policy | Verified GM/Officer; sensitive |

## Operation contract

| Operation | Required sequence | Mutation rule |
| --- | --- | --- |
| Backup | Create, checksum, list | Never changes active state |
| Restore | Preview → confirm → safety snapshot → apply | Replace only declared scope |
| Configuration import | Validate → preview → merge/replace confirm | Policy changes audited |
| Full-data import | Validate each record → preview → append confirm | Legacy compatibility; unknown canonical history refused |
| Profile switch/reset/delete | Scope check → confirm if policy | Never deletes ledger |

## Validation invariants

- Invalid checksum, schema, size, structure, identity, or scope blocks application.
- Imported content is data only; no functions, commands, links, or actions are executed.
- Existing transactions and award references are immutable and deduplicated.
- Cross-guild sensitive packages are blocked unless a declared non-sensitive new-guild path
  is selected.
- A failed or cancelled operation leaves a usable pre-operation restore point.
- Every operation records actor, scope, time, outcome, and reason.

## Local snapshots and portable recovery

Local snapshots are stored in the addon's SavedVariables and restored by their local
snapshot ID. Current-state export does not export the selected historical snapshot.
Selected-snapshot export is the separate operation specified below (T035). Import
of an external snapshot as a recovery point remains unimplemented (T036).

Full import reports `LEGACY_DIAGNOSTIC_ONLY`: it may append validated legacy records
under the existing compatibility rules, but cannot adopt unknown canonical commits
or orphaned operation rows. Reimporting an existing package into the same populated
client does not prove recovery of a fresh installation. Canonical recovery must use
the approved Feature 026 authority/recovery path; this stabilization does not alter
T049 or create another canonical writer.

## Temporary preview lifecycle

Each of `pendingImports` and `pendingRestores` retains at most 16 previews. Creation
and confirmation prune expired entries (age at least 1,800 seconds), malformed
entries, and entries whose creation timestamp is invalid or in the future. Capacity
eviction orders by creation timestamp, then preview ID, oldest first.

A missing or expired preview returns `PREVIEW_NOT_FOUND` before business-state
application; the user must create and review a new preview. Pruning only affects
these disposable stores, never backup snapshots, accepted history, audit records,
governance or ledger state. Existing confirmation, authority, checksum and scope
checks still apply. Backup creation captures its payload once, and the stored
detached snapshot and checksum attest that same capture.

## Selected historical snapshot export

`Backup.ExportSnapshot(snapshotId, {actor?, confirmedSensitive?, reason?, expectedPackageText?, compressed?})`
returns the original package text and decoded package, or `nil, reasonCode`.
`Backup.ValidateSnapshotExport(snapshotId, {actor?, confirmedSensitive?, expectedPackageText?, compressed?})` returns
`true` or `nil, reasonCode` using the same checks without auditing or producing text;
the UI uses it to recheck cached output before display. Actor, when supplied, must
identify the logged-in character rather than impersonate another guild member.
When `expectedPackageText` is supplied, the retained package must match it byte for
byte, otherwise `SNAPSHOT_EXPORT_CHANGED` is returned. The UI uses this check for
cached output and binds pre-export consent to selected snapshot metadata, invalidating
both if the same snapshot ID acquires different metadata/content.
It requires current scope permissions and guild context; local snapshots additionally
require the logged-in character to own both the snapshot and its source package.
`confirmedSensitive == true` is mandatory for full scope. Checksums are integrity
checks, not proof of remote author identity or authority to adopt canonical records.

An original retained package is mandatory: `packageText`, or the optional compressed
original described below. Legacy raw output must fit `MAX_PACKAGE_SIZE` (250,000 characters
including prefix); compressed output follows the encoded/raw budgets below. It must match the selected snapshot's scope, source context,
package checksum and payload attestation. Unattested snapshots and snapshots with no
retained original text in either format are unavailable for export. No inner-package re-encoding, redaction, live
capture, chunking or limit increase is allowed. Success records an export audit event
with snapshot ID, scope, actor and reason, without embedding package content.

The UI produces copyable text for the selected backup after explicit action; no file
is written by the addon. Full export displays the existing compatibility/recovery
restriction. Consent and text are discarded when selection/context changes; failed
exports cannot leave a previous successful package visible as the current result.

Historical local/guild configurations may be imported through the existing
`ImportExport.Preview` → `Apply` workflow. They are not inserted into `db.backups` as
raw external restore points: ordinary restore does not share Apply's scope filtering.
T036 remains open for a normalized external restore-point contract and canonical
recovery, including the Feature 026/T049 dependency.

## Compressed portable transport — 2026-11-15

The opt-in `compressed=true` option on current-state and selected-snapshot export
wraps the unchanged package in `DIBS-COMP-1|<rawLength>|<rawChecksum>|<base64Deflate>`.
`rawChecksum` uses the existing package checksum function on the original text.
The entire envelope fits 250,000 characters; its decoded original package fits
32 MiB, including prefix. Legacy raw export behavior remains the API default and
legacy imports remain supported. Compressed import automatically unwraps, then
uses existing Decode/Preview/Apply validation, depth/node budgets and authority.
It never sets allowUnsafe or adopts unknown canonical history.

`BackupTransport.Wrap(rawText)` returns envelope/metadata or nil/reason;
`Unwrap(envelope)` returns original text/metadata or nil/reason;
`GetStatus()` returns `{available=boolean, backend='native'|'libdeflate'|nil}`.
Metadata contains rawBytes, encodedBytes and backend. Native C_EncodingUtil with
raw Deflate and standard Base64 is preferred when its required functions exist;
the existing bundled LibDeflate may be loaded unchanged as a fallback. No dependency
update, library edit, Sync quota change or canonical format/hash change is permitted.

Input length, strict Base64, envelope fields and versions are checked first. A
non-output-allocating DEFLATE structural pass counts produced bytes with bounded
work, checks distances/block structure, rejects trailing data, and enforces the
declared raw length and 32 MiB budget BEFORE calling any native/library decompressor.
Returned length and checksum are checked again. Nested compressed envelopes and
non-package decoded text are refused. API errors are caught and surfaced as codes.

For new large snapshots, Create may retain `compressedPackageText` if it fits the
portable cap; the original payload/package attestations remain unchanged. Historical
export validates its restored original bytes against the stored payload; absent
original text in both formats remains unavailable. Optional compressed text requires
no migration of existing snapshots; legacy restore behavior remains unchanged.
Local restore continues validating its retained payload/checksum independently of
optional compressed transport. Losing a codec or corrupting that optional transport
must not prevent restoring an otherwise valid local payload; historical export
still refuses unavailable or corrupt original transport.
Compressed cached output is unwrapped and compared byte-for-byte to the attested
original during revalidation; sensitive consent remains bound to snapshot metadata.

Without a codec, compressed API requests fail explicitly, local backup creation
still succeeds, and the UI offers legacy export with a localized explanation.
Compression is not encryption. Full exports retain sensitive confirmation and
LEGACY_DIAGNOSTIC_ONLY restrictions. Real C_EncodingUtil execution and UI behavior
in the targeted Retail builds must remain manual gates until tested in game.
