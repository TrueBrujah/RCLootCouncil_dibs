# Events, callbacks, and messages

## Blizzard events consumed

`Core.lua` handles `ADDON_LOADED`, `PLAYER_LOGIN`, `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_REGEN_ENABLED`, and `CHAT_MSG_ADDON`. Roster/world/zone changes invalidate readiness and can trigger sync manifest recovery. `PLAYER_REGEN_ENABLED` resumes UI work deferred by combat lockdown. `EncounterJournal.lua` and `RCLootCouncilOptions.lua` register bootstrap handlers for `PLAYER_LOGIN`, `ADDON_LOADED`, and (where applicable) `PLAYER_REGEN_ENABLED`.

## Internal callbacks

AceEvent callbacks are registered through `Dibs.Ace3.RegisterEvent`; AceComm callbacks are registered through `Dibs.Ace3.RegisterComm`. `Dibs.DebugLogs` is an in-memory diagnostic sink, not an event bus. UI callbacks invoke domain APIs and refresh their owning controller.

## RCLootCouncil callbacks

When available, `Dibs.RCLootCouncil.Initialize` registers `RCMLAwardSuccess`. The callback receives RC session/winner/status/item/response context, validates authority and semantics, and then delegates accounting. RC availability is optional and capability-probed.

## Addon communication

The registered prefix is `DIBS`. Serialized messages use the AceSerializer adapter when available; the fallback compact envelope starts with `DIBS1:`. Message names and payload validation are defined in `modules/Sync.lua`; see [sync-protocol.md](sync-protocol.md).
