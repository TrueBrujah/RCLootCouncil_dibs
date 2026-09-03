local M = {}

local baseTime = 1700000000
local now = baseTime
local currentPlayerName = "Tester-Realm"
local currentPlayerGUID = "Player-1-TESTER"
local inGuild = true
local guildLeader = true
local inCombat = false

local function makeFrame()
  local scripts = {}
  return {
    SetSize = function() end,
    SetPoint = function() end,
    Hide = function() end,
    Show = function() end,
    Raise = function() end,
    SetClampedToScreen = function() end,
    SetToplevel = function() end,
    SetFrameStrata = function() end,
    SetMovable = function() end,
    EnableMouse = function() end,
    RegisterForDrag = function() end,
    StartMoving = function() end,
    StopMovingOrSizing = function() end,
    SetWidth = function() end,
    SetJustifyH = function() end,
    SetText = function() end,
    IsShown = function() return false end,
    RegisterEvent = function() end,
    SetScript = function(_, name, fn) scripts[name] = fn end,
    HookScript = function(_, name, fn) scripts[name] = fn end,
    CreateFontString = function()
      return {
        SetPoint = function() end,
        SetText = function() end,
        SetWidth = function() end,
        SetJustifyH = function() end,
      }
    end,
  }
end

function M.install(opts)
  opts = opts or {}
  now = tonumber(opts.now) or baseTime
  currentPlayerName = opts.playerName or "Tester-Realm"
  currentPlayerGUID = opts.playerGUID or "Player-1-TESTER"
  inGuild = opts.inGuild ~= false
  guildLeader = opts.guildLeader ~= false
  inCombat = opts.inCombat == true

  _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  _G.SlashCmdList = {}
  _G.UIParent = {}

  _G.time = function()
    now = now + 1
    return now
  end

  _G.UnitName = function(unit)
    if unit == "player" then return currentPlayerName end
    return "UnknownPlayer"
  end

  _G.UnitGUID = function(unit)
    if unit == "player" then return currentPlayerGUID end
    return nil
  end

  _G.GetRealmName = function() return "Realm" end
  _G.IsInGuild = function() return inGuild end
  _G.IsGuildLeader = function() return guildLeader end
  _G.InCombatLockdown = function() return inCombat end
  _G.GetNumGuildMembers = function() return 1 end
  _G.GetGuildRosterInfo = function(index)
    if index == 1 then return currentPlayerName, "Guild Master", 0 end
    return nil
  end

  _G.CreateFrame = function()
    return makeFrame()
  end

  _G.C_AddOns = {
    IsAddOnLoaded = function(name)
      if name == "RCLootCouncil" and _G.RCLootCouncil then
        return true, true
      end
      return false, false
    end,
  }

  _G.Settings = {
    RegisterCanvasLayoutCategory = function(panel)
      return { panel = panel }
    end,
    RegisterAddOnCategory = function() end,
  }
end

function M.resetGlobals()
  _G.Dibs = nil
  _G.RCLootCouncil_dibs = nil
  _G.DibsDB = nil
  _G.RCLootCouncil_dibsDB = nil
  _G.RCLootCouncil = nil
  _G.LibStub = nil
end

return M
