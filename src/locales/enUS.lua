local Dibs = _G.Dibs
Dibs.L = Dibs.L or {}

local L = Dibs.L

L.AUTHORITY_INVALID_ACTION = "Unknown protected action."
L.AUTHORITY_INVALID_ACTOR = "Unable to identify the actor."
L.AUTHORITY_RC_UNVERIFIABLE = "RCLootCouncil authority could not be verified."
L.AUTHORITY_RC_STATE_CHANGED = "RCLootCouncil authority changed during evaluation."
L.AUTHORITY_RC_AUTHORIZED = "Authorized by RCLootCouncil."
L.AUTHORITY_RC_NOT_MASTER_LOOTER = "Only the current RCLootCouncil Master Looter may perform this action."
L.AUTHORITY_STANDALONE_GUILD_MASTER = "Authorized as guild master."
L.AUTHORITY_STANDALONE_APPOINTED_ADMIN = "Authorized as a Dibs administrator."
L.AUTHORITY_STANDALONE_NOT_AUTHORIZED = "You are not authorized to perform this Dibs action."
L.STANDALONE_ADMIN_GM_ONLY = "Only the guild master can manage Dibs administrators."
L.PROTECTED_ACTION_DENIED = "Action denied."
L.PROTECTED_ACTION_UNAVAILABLE = "Required module unavailable."
L.SEASON_CREATE_FAILED = "Failed to create season."
L.SEASON_NOT_FOUND = "Season not found."
L.AWARD_NOT_FINAL = "Award is not finalized; no Dib consumed."
L.AWARD_INVALID = "Award payload is missing required fields."
L.AWARD_CONSUME_FAILED = "Unable to consume Dib for award."
L.UI_DEFERRED_COMBAT = "Officer UI will open after combat."
L.RC_STATUS_UNAVAILABLE = "RCLootCouncil status is unavailable."
L.RC_COMPATIBILITY_FALLBACK = "RCLootCouncil candidate integration is unavailable; using the local Dibs display."
