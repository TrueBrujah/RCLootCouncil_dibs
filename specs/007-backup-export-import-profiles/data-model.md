# Data Model: Dibs Backups, Data Transfer, and Configuration Profiles

## Backup Snapshot

```text
snapshotId, scope, guildScope?, characterScope?, schemaVersion, addonVersion,
createdAt, createdBy, size, checksum, retentionState, payload
```

Snapshots are local, bounded, and available as restore points before risky operations.

Current snapshots additionally retain `characterScope`, `packageChecksum` and
`payloadChecksum`; `packageText` is retained only for snapshots fitting the existing
portable limit. New larger snapshots may retain optional `compressedPackageText`
when its versioned envelope fits the same 250,000-character cap; uncompressed data
stays within the existing 32 MiB budget. Decoding recovers the exact original package.
This is an additive optional representation: no migration or rewriting of existing
snapshots occurs. Local restore validates payload/checksum without requiring this
optional transport or an available codec. Historical export returns the original package, after
validating its context, checksum and payload against the selected snapshot. Inner
package/schema versions stay unchanged. Older snapshots missing these attestations remain usable
under their existing restore contract but are unavailable for historical export.
Older clients ignore the optional compressed transport and can still validate and
restore the retained local payload; they cannot export the new compressed representation.

Historical-export consent and copyable output are transient UI state, bound to the
selected snapshot and current guild/character/authority, not SavedVariables fields.
External packages do not become raw `Backup Snapshot` records in this slice.

## Compressed transport envelope

`DIBS-COMP-1|rawLength|rawChecksum|standardBase64Deflate` wraps the unchanged
`DIBS-PKG-1` package. The inner package/schema/checksums and canonical record hashes
stay unchanged. Raw legacy exports remain supported. Envelope length and actual
DEFLATE expansion are bounded before decompression; decoded length and checksum
are verified before parsing. Compression does not provide confidentiality.

## Configuration Profile

```text
profileId, name, scope(local|guild), ownerScope, presentation,
authoritativePolicy?, schemaVersion, createdAt, updatedAt, active
```

Authoritative policy fields are visibly separated from presentation fields.

## Export Package

```text
packageVersion, scope, sourceGuild?, sourceCharacter?, sourceProfile?,
addonVersion, schemaVersion, createdAt, sensitivity, checksum, payload
```

Payload is data only; unknown optional fields may be preserved when safe.

## Import Preview and Decision

```text
previewId, packageId, targetScope, strategy(merge|replace|append),
additions, changes, omissions, conflicts, migrations, sensitiveFields,
expectedLedgerImpact, createdAt, actor, decision, reason
```

No active state changes before an authorized decision.

## Restore Point

A `Backup Snapshot` automatically created immediately before restore, full-data import,
authoritative profile reset, or destructive profile operation.
