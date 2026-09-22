# Notification Contract

## Input

`eventId` and `kind` are required. Payload may contain `playerName`, `targetPlayer`, `itemName`, `itemLink`, or `itemID`.

## Privacy

A target that is not the local player is ignored before it is recorded. Notifications never expose audit evidence, ledger rows, or remote sync payloads.

## Idempotency

The event identity is recorded before display. Replays return `DUPLICATE` and do not call `Dibs.Message`. The map is bounded to the newest 128 timestamps.

## Disablement

`Dibs.Notifications.SetEnabled(false)` suppresses local display and returns `DISABLED`; domain operations continue normally.
