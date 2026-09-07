local M = {}

local baseTime = 1700000000
local now = baseTime
local currentPlayerName = "Tester-Realm"
local currentPlayerGUID = "Player-1-TESTER"
local inGuild = true
local guildName = "TestGuild"
local guildLeader = true
local inCombat = false
local guildMembers = { "Tester-Realm" }
local guildRankIndices = {}
local inRaid = false
local raidLeader = false
local raidAssistant = false
local masterLooter = false
local raidDibsChannel = false
local instanceName, instanceType, instanceId = nil, nil, nil
local frames = {}

local itemCache = {
  [275658] = {
    name = "Primeval Skyfriend",
    link = "|cffa335ee|Hitem:275658::::::::::::|h[Primeval Skyfriend]|h|r",
  },
}

local function makeFrame()
  local scripts = {}
  return {
    _scripts = scripts,
    SetSize = function() end,
    SetPoint = function() end,
    Hide = function(self) self._shown = false end,
    Show = function(self) self._shown = true end,
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
    SetText = function(self, value) self._text = tostring(value or "") end,
    GetText = function(self) return self._text or "" end,
    IsShown = function(self) return self._shown == true end,
    RegisterEvent = function(self, event) self._events = self._events or {}; self._events[event] = true end,
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
  guildName = opts.guildName or "TestGuild"
  guildLeader = opts.guildLeader ~= false
  inCombat = opts.inCombat == true
  guildMembers = opts.guildMembers or { currentPlayerName }
  guildRankIndices = opts.guildRankIndices or {}
  inRaid = opts.inRaid == true
  raidLeader = opts.raidLeader == true
  raidAssistant = opts.raidAssistant == true
  masterLooter = opts.masterLooter == true
  raidDibsChannel = opts.raidDibsChannel == true
  instanceName, instanceType, instanceId = opts.instanceName, opts.instanceType, opts.instanceId
  frames = {}
  _G.__dibsFrameCreations = {}
  _G.__dibsAceWidgets = {}

  _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  _G.__dibsMessages = {}
  _G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text)
      table.insert(_G.__dibsMessages, tostring(text))
    end,
  }
  _G.__sentChatMessages = {}
  _G.SlashCmdList = {}
  _G.UIParent = {}

  _G.time = function()
    now = now + 1
    return now
  end

  _G.date = function(format)
    if format == "*t" then
      return { year = 2026, month = 9, day = 6, hour = 12, min = 0, sec = 0 }
    end
    return "2026-09-06 12:00:00"
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
  _G.GetGuildInfo = function(unit)
    if unit == "player" and inGuild then return guildName end
    return nil
  end
  _G.IsGuildLeader = function() return guildLeader end
  _G.InCombatLockdown = function() return inCombat end
  _G.IsInRaid = function() return inRaid end
  _G.IsInGroup = function() return inRaid end
  _G.GetChannelName = function(channel)
    if channel == "Raid Dibs" and raidDibsChannel then return 7, "Raid Dibs" end
    if channel == 7 and raidDibsChannel then return 7, "Raid Dibs" end
    return 0, nil
  end
  _G.UnitIsGroupLeader = function() return raidLeader end
  _G.UnitIsGroupAssistant = function() return raidAssistant end
  _G.GetLootMethod = function() return masterLooter and "master" or "group" end
  _G.GetInstanceInfo = function() return instanceName, instanceType, nil, nil, nil, nil, nil, instanceId end
  _G.GetNumGuildMembers = function() return #guildMembers, #guildMembers, #guildMembers end
  _G.GetGuildRosterInfo = function(index)
    local memberName = guildMembers[index]
    if not memberName then return nil end
    local rankIndex = guildRankIndices[index]
    if rankIndex == nil then rankIndex = index == 1 and 0 or 3 end
    local rankName = rankIndex == 0 and "Guild Master" or (rankIndex <= 1 and "Officer" or "Member")
    return memberName, rankName, rankIndex
  end

  _G.CreateFrame = function(kind, name, parent, template)
    local frame = makeFrame()
    frame.kind, frame.name, frame.parent, frame.template = kind, name, parent, template
    table.insert(frames, frame)
    table.insert(_G.__dibsFrameCreations, frame)
    return frame
  end

  _G.C_Timer = {
    After = function(_, fn)
      return fn
    end,
  }

  _G.GetItemInfo = function(input)
    local id = tonumber(input)
    if not id and type(input) == "string" then
      id = tonumber(input:match("item:(%d+)"))
    end
    local entry = id and itemCache[id] or nil
    if not entry then
      return nil, nil
    end
    return entry.name, entry.link
  end

  _G.GetItemInfoInstant = function(input)
    local id = tonumber(input)
    if not id and type(input) == "string" then
      id = tonumber(input:match("item:(%d+)"))
    end
    local entry = id and itemCache[id] or nil
    if not entry then
      return nil
    end
    return entry.name
  end

  _G.Item = {
    CreateFromItemID = function(itemID)
      local id = tonumber(itemID)
      if not id or not itemCache[id] then
        return nil
      end
      return {
        ContinueOnItemLoad = function(_, callback)
          if type(callback) == "function" then
            callback()
          end
        end,
      }
    end,
  }

  _G.SendChatMessage = function(message, channel, language, target)
    table.insert(_G.__sentChatMessages, { message = tostring(message), channel = tostring(channel), target = target })
    return true
  end
  _G.__sentAddonMessages = {}
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) return prefix == "DIBS" end,
    SendAddonMessage = function(prefix, message, channel, target)
      table.insert(_G.__sentAddonMessages, { prefix = prefix, message = message, channel = channel, target = target })
      return true
    end,
  }
  _G.C_Club = {
    GetSubscribedClubs = function()
      if not raidDibsChannel then return {} end
      return {
        [100] = { clubName = "Another Community" },
        [2044801] = { clubName = "Still Alive" },
      }
    end,
    GetStreams = function(clubId)
      if raidDibsChannel and clubId == 2044801 then
        return { [3] = { streamName = " Raid Dibs " } }
      end
      return {}
    end,
    SendMessage = function(clubId, streamId, message)
      table.insert(_G.__sentChatMessages, { message = tostring(message), channel = "CLUB", clubId = clubId, streamId = streamId })
      return true
    end,
  }
  _G.EJ_SelectInstance = function(id) _G.__ejNavigation = { instanceId = id } end
  _G.EJ_SelectEncounter = function(id) _G.__ejNavigation = { encounterId = id } end
  _G.EncounterJournal_LoadUI = function() _G.__ejLoaded = true end

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
  _G.DibsPlayerFrame = nil
  _G.DibsOfficerFrame = nil
  _G.DibsOptionsPanel = nil
  _G.RCLootCouncil = nil
  _G.LibStub = nil
  _G.Item = nil
  _G.C_Timer = nil
  _G.__dibsMessages = nil
  _G.__sentChatMessages = nil
  _G.__sentAddonMessages = nil
  _G.__dibsFrameCreations = nil
  _G.__dibsAceWidgets = nil
  _G.__ejNavigation = nil
  _G.C_ChatInfo = nil
end

function M.dispatch(event, ...)
  for _, frame in ipairs(frames) do
    if frame._events and frame._events[event] and frame._scripts and frame._scripts.OnEvent then
      frame._scripts.OnEvent(frame, event, ...)
    end
  end
end

function M.makeRCLootCouncilAward(opts)
  opts = opts or {}
  return {
    session = opts.session,
    winner = opts.winner or currentPlayerName,
    status = opts.status or "normal",
    itemLink = opts.itemLink or "item:19019",
    response = opts.response or "DIB",
  }
end

function M.replayRCLootCouncilAward(callback, event, count)
  if type(callback) ~= "function" or type(event) ~= "table" then return 0 end
  local deliveries = math.max(1, tonumber(count) or 1)
  for _ = 1, deliveries do
    callback(nil, event.session, event.winner, event.status, event.itemLink, event.response)
  end
  return deliveries
end

function M.setCombat(value) inCombat = value == true end

function M.installEncounterJournalContext(opts)
  opts = opts or {}
  local raidInstanceID = tonumber(opts.raidInstanceID)
  local dungeonInstanceID = tonumber(opts.dungeonInstanceID)
  local currentInstanceID = raidInstanceID or dungeonInstanceID

  _G.EJ_GetCurrentInstance = function()
    return currentInstanceID
  end

  _G.EJ_GetInstanceByIndex = function(_, isRaid)
    if isRaid == true then return raidInstanceID end
    if isRaid == false then return dungeonInstanceID end
    return nil
  end
end

return M
