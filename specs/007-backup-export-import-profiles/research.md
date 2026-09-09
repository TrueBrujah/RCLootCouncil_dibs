# Research: Dibs Backups, Data Transfer, and Configuration Profiles

## Decision 1: Scope and sensitivity are explicit

Every backup/package declares local presentation, guild policy, or full Dibs data scope.
Configuration-only export is the safe default; names, award history, ledger, and notes are
marked sensitive and require an explicit warning before generation.

## Decision 2: Preview, snapshot, then apply

Restore and full-data import create a safety snapshot before mutation. Preview and cancel
are read-only. A failed apply leaves both active data usable and the pre-operation snapshot
available.

## Decision 3: Data-only, versioned packages

The format accepts plain serialized data fields only. It rejects functions, commands,
executable-looking payloads, invalid checksums, unsupported versions, malformed structure,
and unsafe identity fields before application.

## Decision 4: Profiles never hide ledger operations

Presentation settings and authoritative policy settings are separate. Switching, resetting,
or deleting a profile cannot change balances or permissions. Activating a policy profile
requires a visible warning, confirmation, authority, and audit event.

## Decision 5: Append and deduplicate full data

Existing ledger transactions and award references remain immutable. A valid full package
adds only unseen authorized records; duplicate imports return an already-present status.
Cross-guild full sensitive import is blocked by default.

## Rejected alternatives

- Replace the entire SavedVariables root on restore: rejected because it can destroy newer
  transactions and bypass guild isolation.
- Trust package text because it came from an Officer: rejected because copied text can be
  truncated, tampered with, or pasted into the wrong guild.
- Let profiles grant permissions: rejected because configuration is not identity or role.
- Encrypt inside the addon and imply secure transport: rejected because WoW text transfer
  is not a secret channel; the UI must warn about sensitive exports instead.
