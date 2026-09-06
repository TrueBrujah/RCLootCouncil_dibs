# Contract: Raid Mode and Prompt UI

## Officer Mode Control

- The officer settings view displays the active season's Pre-Dib mode: `Wild Open` or `Encounter`.
- Only an authorized GM or officer can change it.
- The view records who last changed the mode and when.
- A mode change affects future request validation only.

## Player Request Feedback

- The player view identifies the active mode before submission.
- In Wild Open, supported raid items can be requested in the active season without current raid presence.
- In Encounter mode, rejected requests identify whether the player is outside a raid, in a dungeon, or targeting loot outside the current raid.
- Request history exposes mode, validation context, status, creation time, and acknowledgement state to authorized officers.

## Reminder

- Authorized senders can issue one explicit Dib reminder while in a raid.
- The reminder is informational only and does not open a UI, create a request, or consume Dibs.
- The sender sees a clear rejection reason when not eligible or outside a raid.

## Raid-Entry Prompt

- Each player has an opt-in preference, disabled by default.
- On entering a supported raid, an opted-in player is offered an explicit choice to open the Adventure Guide for that raid.
- The player may decline without changing their preference.
- When a boss is known, the prompt may open that boss's loot view; otherwise it opens the raid overview.
- Prompts and Adventure Guide navigation are deferred during combat and revalidated after combat.
