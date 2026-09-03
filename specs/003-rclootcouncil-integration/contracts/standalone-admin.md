# Contract: Standalone Administrator Governance

Standalone authority applies only when RC is absent.

## Policy

- Guild master is authorized.
- Explicitly appointed standalone admins are authorized.
- Raid leader/assistant alone are not authorized.

## Admin mutation invariant

`admin.appoint` and `admin.revoke` additionally require verified guild master identity even when RC path authorizes the caller.

## Persistence

- Admin changes append immutable admin events.
- Active admin set is derived/indexed from event history.
