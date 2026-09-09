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
| Restore | Safety snapshot → preview → confirm | Replace only declared scope |
| Configuration import | Validate → preview → merge/replace confirm | Policy changes audited |
| Full-data import | Validate each record → preview → append confirm | New valid records only |
| Profile switch/reset/delete | Scope check → confirm if policy | Never deletes ledger |

## Validation invariants

- Invalid checksum, schema, size, structure, identity, or scope blocks application.
- Imported content is data only; no functions, commands, links, or actions are executed.
- Existing transactions and award references are immutable and deduplicated.
- Cross-guild sensitive packages are blocked unless a declared non-sensitive new-guild path
  is selected.
- A failed or cancelled operation leaves a usable pre-operation restore point.
- Every operation records actor, scope, time, outcome, and reason.
