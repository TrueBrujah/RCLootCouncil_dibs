# Data Model: Player Notifications

## Local State

```lua
RCLootCouncil_dibsLocalDB = {
  notifications = {
    enabled = true,
    seen = {
      [eventId] = timestamp,
    },
  },
}
```

The state is per character, bounded to 128 event identities, and is not synchronized or included in officer projections.

## Notification Contract

```lua
Dibs.Notifications.Notify(eventId, kind, payload)
-- returns true when emitted
-- returns false, reasonCode when ignored
```

Supported kinds are `PREDIB_CONFIRMED`, `PREDIB_CANCELLED`, `AWARD_FINALIZED`, `DIB_CONSUMED`, `REQUEST_RESOLVED`, and `VAULT_RECORDED`.
