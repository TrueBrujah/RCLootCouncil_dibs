# Data Model: Dibs Backups, Data Transfer, and Configuration Profiles

## Backup Snapshot

```text
snapshotId, scope, guildScope?, characterScope?, schemaVersion, addonVersion,
createdAt, createdBy, size, checksum, retentionState, payload
```

Snapshots are local, bounded, and available as restore points before risky operations.

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
