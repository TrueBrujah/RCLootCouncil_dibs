# Events, callbacks, and messages

## Blizzard events consumed

`Core.lua` handles `ADDON_LOADED`, `PLAYER_LOGIN`, `GROUP_ROSTER_UPDATE`,
`GUILD_ROSTER_UPDATE`, `CHAT_MSG_SYSTEM`, `PLAYER_ENTERING_WORLD`,
`ZONE_CHANGED_NEW_AREA`, `PLAYER_REGEN_ENABLED`, and `CHAT_MSG_ADDON`.
Roster/world/zone changes invalidate readiness and can trigger recovery.
`GUILD_ROSTER_UPDATE` refreshes identity/presence for authority and delivery;
readable localized player-not-found feedback can pause whisper retries.
Secret system text is ignored before string operations and never logged.
`PLAYER_REGEN_ENABLED` resumes UI work deferred by combat lockdown.
`EncounterJournal.lua` and `RCLootCouncilOptions.lua` register bootstrap handlers
for `PLAYER_LOGIN`, `ADDON_LOADED`, and (where applicable) `PLAYER_REGEN_ENABLED`.

`GreatVault.lua` hooks `C_WeeklyRewards.ClaimReward` when available and listens
for `CHAT_MSG_LOOT`, `WEEKLY_REWARDS_UPDATE`, and `WEEKLY_REWARDS_ITEM_CHANGED`,
in addition to login/addon bootstrap. A completed automatic acquisition
requires correlated claim, exact item receipt, and exhausted reward availability;
opening the Vault alone is not a claim. Real Retail validation remains separate.

## Internal callbacks

AceEvent callbacks are registered through `Dibs.Ace3.RegisterEvent`; AceComm callbacks are registered through `Dibs.Ace3.RegisterComm`. `Dibs.DebugLogs` is an in-memory diagnostic sink, not an event bus. UI callbacks invoke domain APIs and refresh their owning controller.

## RCLootCouncil callbacks

When available, `Dibs.RCLootCouncil.Initialize` registers `RCMLAwardSuccess`. The callback receives RC session/winner/status/item/response context, validates authority and semantics, and then delegates accounting. RC availability is optional and capability-probed.

## Addon communication

The registered prefix is `DIBS`. Serialized messages use the AceSerializer adapter when available; the fallback compact envelope starts with `DIBS1:`. Legacy message names and validation are defined in `modules/Sync.lua`;
`modules/SyncV2.lua` extends that namespace for V2 guild state, canonical commits,
and private detail transport. `RequestDelivery.lua` handles private request
operations. See [sync-protocol.md](sync-protocol.md).
