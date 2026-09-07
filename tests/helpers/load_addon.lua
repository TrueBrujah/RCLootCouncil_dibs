local wow = require("helpers.wow_api")

local M = {}

local TOC_FILES = {
  "Core.lua",
  "locales/enUS.lua",
  "locales/frFR.lua",
  "modules/Seasons.lua",
  "modules/RankRules.lua",
  "modules/Ledger.lua",
  "modules/Permissions.lua",
  "modules/ProtectedActions.lua",
  "modules/PreDibs.lua",
  "modules/LootPipeline.lua",
  "modules/Sync.lua",
  "modules/RaidRelay.lua",
  "modules/RaidPrompts.lua",
  "integrations/Ace3.lua",
  "integrations/DeveloperMode.lua",
  "integrations/EncounterJournal.lua",
  "integrations/RCLootCouncil.lua",
  "ui/AceGUI.lua",
  "ui/PlayerUI.lua",
  "ui/OfficerUI.lua",
  "integrations/RCLootCouncilOptions.lua",
}

local function installLibStub(rc, ace3, asCallableTable)
  local aceAddon = {
    GetAddon = function(_, name)
      if name == "RCLootCouncil" then
        return rc
      end
      return nil
    end,
  }

  local function resolveLibrary(name, silent)
    if name == "AceAddon-3.0" then
      return aceAddon
    end
    if ace3 and ace3[name] then return ace3[name] end
    if not silent then error("unknown lib: " .. tostring(name)) end
    return nil
  end
  if asCallableTable then
    _G.LibStub = setmetatable({}, { __call = function(_, name, silent) return resolveLibrary(name, silent) end })
  else
    _G.LibStub = resolveLibrary
  end
end

local function makeAce3()
  local encoded = {}
  local nextId = 0
  local comm = { handlers = {}, sent = {} }
  function comm:Embed(target)
    target.RegisterComm = function(owner, prefix, callback) comm.handlers[prefix] = callback return true end
    target.SendCommMessage = function(owner, prefix, payload, channel, targetName)
      table.insert(comm.sent, { prefix = prefix, payload = payload, channel = channel, target = targetName })
      return true
    end
  end
  local serializer = {}
  function serializer:Serialize(value)
    nextId = nextId + 1
    encoded[nextId] = value
    return true, "ACE:" .. tostring(nextId)
  end
  function serializer:Deserialize(payload)
    local value = encoded[tonumber(tostring(payload):match("^ACE:(%d+)$"))]
    return value ~= nil, value
  end
  local event = { handlers = {} }
  function event:Embed(target)
    target.RegisterEvent = function(owner, eventName, callback) event.handlers[eventName] = callback return true end
  end
  local timer = { scheduled = {} }
  function timer:Embed(target)
    target.ScheduleTimer = function(owner, callback, delay)
      table.insert(timer.scheduled, { callback = callback, delay = delay })
      return #timer.scheduled
    end
  end
  local config = { tables = {} }
  function config:RegisterOptionsTable(name, options) config.tables[name] = options return true end
  local dialog = { added = {} }
  function dialog:AddToBlizOptions(name, displayName, parent, group)
    table.insert(dialog.added, { name = name, displayName = displayName, parent = parent, group = group })
    return dialog.added[#dialog.added]
  end
  local gui = {}
  function gui:Create(kind)
    local frame = _G.CreateFrame("Frame")
    local widget = { frame = frame, kind = kind, children = {}, callbacks = {} }
    table.insert(_G.__dibsAceWidgets, widget)
    function widget:SetTitle(value) self.title = value end
    function widget:SetWidth(value) self.width = value end
    function widget:SetHeight(value) self.height = value end
    function widget:SetLayout(value) self.layout = value end
    function widget:SetFullWidth(value) self.fullWidth = value end
    function widget:SetFullHeight(value) self.fullHeight = value end
    function widget:SetTabs(value) self.tabs = value end
    function widget:SetList(value) self.list = value end
    function widget:SetLabel(value) self.label = value end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text or "" end
    function widget:SetValue(value) self.value = value end
    function widget:SetDisabled(value) self.disabled = value == true end
    function widget:SetCallback(name, callback) self.callbacks[name] = callback end
    function widget:AddChild(child) table.insert(self.children, child) end
    function widget:ReleaseChildren() self.children = {} end
    function widget:Hide() self.frame:Hide() end
    function widget:Show() self.frame:Show() end
    return widget
  end
  return {
    ["AceComm-3.0"] = comm,
    ["AceSerializer-3.0"] = serializer,
    ["AceEvent-3.0"] = event,
    ["AceTimer-3.0"] = timer,
    ["AceGUI-3.0"] = gui,
    ["AceConfig-3.0"] = config,
    ["AceConfigDialog-3.0"] = dialog,
  }
end

local function makeRC(opts)
  opts = opts or {}
  local currentSessionId = opts.currentSessionId
  if currentSessionId == nil then
    currentSessionId = "test-session-1"
  end
  return {
    enabled = opts.enabled ~= false,
    optionsFrame = opts.optionsFrame,
    masterLooter = opts.masterLooter or { guid = "Player-1-TESTER", name = "Tester-Realm" },
    currentSessionId = currentSessionId,
    sessionID = opts.sessionID,
    lootSessionId = opts.lootSessionId,
    _handlers = {},
    RegisterMessage = function(self, event, fn)
      self._handlers[event] = fn
    end,
    Emit = function(self, event, ...)
      local fn = self._handlers[event]
      if fn then fn(self, ...) end
    end,
  }
end

function M.makeRCLootCouncil(opts)
  return makeRC(opts)
end

function M.load(opts)
  opts = opts or {}
  wow.resetGlobals()
  wow.install(opts.wow)

  if type(opts.savedVariables) == "table" then
    _G.RCLootCouncil_dibsDB = opts.savedVariables
  end

  local rc = opts.rclootcouncil
  if rc then
    _G.RCLootCouncil = rc
  end

  if opts.libStub then
    _G.LibStub = opts.libStub
  elseif opts.withLibStub ~= false then
    installLibStub(rc, opts.withAce3 and makeAce3() or nil, opts.libStubAsCallableTable == true)
  end

  local tocFiles = TOC_FILES
  for _, relative in ipairs(tocFiles) do
    local sourcePath = "src/" .. relative
    local chunk, err = loadfile(sourcePath)
    if not chunk then
      error("failed to load " .. sourcePath .. ": " .. tostring(err))
    end
    local addonTable = _G.RCLootCouncil_dibs or {}
    local ok, runErr = pcall(chunk, "RCLootCouncil_dibs", addonTable)
    if not ok then
      error("failed to execute " .. sourcePath .. ": " .. tostring(runErr))
    end
  end

  local dibs = _G.Dibs
  if dibs and dibs.Initialize then
    dibs.Initialize()
  end

  return rc, dibs
end

register_reset(function()
  wow.resetGlobals()
end)

return M
