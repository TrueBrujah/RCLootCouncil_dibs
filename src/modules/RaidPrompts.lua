--[[
Module: Dibs.RaidPrompts
Layer: Player workflow
Purpose: Present optional encounter prompts for eligible Pre-Dibs requests.
Responsibilities: Prompt enablement, request/accept/decline state, and event bridge.
Non-responsibilities: It does not award loot or consume Dibs.
Dependencies: PreDibs, EncounterJournal, Readiness.
Blizzard events: Encounter/roster events are routed by the owning UI/runtime.
Internal events/messages: None beyond PreDibs request calls.
SavedVariables: db.settings.raidEntryDibPromptsEnabled and reminder text.
RCLootCouncil: Prompt context may be sourced from RC encounter data.
Combat safety: Prompt display is deferred during combat lockdown.
Invariants: DIBS-RULE-002 and DIBS-RULE-003.
Related docs: docs/player/README.md.
]]

local Dibs = _G.Dibs
Dibs.RaidPrompts = Dibs.RaidPrompts or {}

local function settings()
  local db = Dibs.GetDB()
  db.settings = db.settings or {}
  if db.settings.raidEntryDibPromptsEnabled == nil then db.settings.raidEntryDibPromptsEnabled = false end
  return db.settings
end

function Dibs.RaidPrompts.IsEnabled()
  return settings().raidEntryDibPromptsEnabled == true
end

function Dibs.RaidPrompts.SetEnabled(enabled, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  settings().raidEntryDibPromptsEnabled = enabled == true
  return Dibs.RaidPrompts.IsEnabled(), nil
end

function Dibs.RaidPrompts.GetRaidContext()
  if type(IsInRaid) ~= "function" or IsInRaid() ~= true then return nil end
  if type(GetInstanceInfo) ~= "function" then return nil end
  local name, instanceType, _, _, _, _, _, instanceId = GetInstanceInfo()
  if instanceType ~= "raid" or not instanceId then return nil end
  return { raidId = instanceId, raidName = name, encounterId = nil }
end

function Dibs.RaidPrompts.Request(context)
  if Dibs.RaidPrompts.IsEnabled() ~= true then return false, "PROMPTS_DISABLED" end
  local current = Dibs.RaidPrompts.GetRaidContext()
  if not current or (context and context.raidId and context.raidId ~= current.raidId) then return false, "RAID_CONTEXT_CHANGED" end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    Dibs.RaidPrompts.pendingContext = current
    return false, "DEFERRED_COMBAT"
  end
  Dibs.RaidPrompts.lastPromptedRaid = tostring(current.raidId) .. ":" .. tostring(current.encounterId or "")
  Dibs.RaidPrompts.visibleContext = current
  return true, current
end

function Dibs.RaidPrompts.Accept()
  local context = Dibs.RaidPrompts.visibleContext
  Dibs.RaidPrompts.visibleContext = nil
  if not context then return false, "NO_PROMPT" end
  if Dibs.EncounterJournal and Dibs.EncounterJournal.OpenForRaidContext then
    return Dibs.EncounterJournal.OpenForRaidContext(context)
  end
  return false, "JOURNAL_UNAVAILABLE"
end

function Dibs.RaidPrompts.Decline()
  Dibs.RaidPrompts.visibleContext = nil
  return true
end

function Dibs.RaidPrompts.OnEvent(event)
  if event == "PLAYER_REGEN_ENABLED" and Dibs.RaidPrompts.pendingContext then
    local context = Dibs.RaidPrompts.pendingContext
    Dibs.RaidPrompts.pendingContext = nil
    return Dibs.RaidPrompts.Request(context)
  end
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    local context = Dibs.RaidPrompts.GetRaidContext()
    if context and Dibs.RaidPrompts.lastPromptedRaid ~= tostring(context.raidId) .. ":" then
      return Dibs.RaidPrompts.Request(context)
    end
  end
  return false
end
