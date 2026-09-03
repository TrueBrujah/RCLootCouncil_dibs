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
  "modules/Sync.lua",
  "modules/RaidRelay.lua",
  "integrations/EncounterJournal.lua",
  "integrations/RCLootCouncil.lua",
  "ui/PlayerUI.lua",
  "ui/OfficerUI.lua",
}

local function installLibStub(rc)
  local aceAddon = {
    GetAddon = function(_, name)
      if name == "RCLootCouncil" then
        return rc
      end
      return nil
    end,
  }

  _G.LibStub = function(name, silent)
    if name == "AceAddon-3.0" then
      return aceAddon
    end
    if not silent then error("unknown lib: " .. tostring(name)) end
    return nil
  end
end

local function makeRC(opts)
  opts = opts or {}
  return {
    enabled = opts.enabled ~= false,
    masterLooter = opts.masterLooter or { guid = "Player-1-TESTER", name = "Tester-Realm" },
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

  local rc = opts.rclootcouncil
  if rc then
    _G.RCLootCouncil = rc
  end

  if opts.withLibStub ~= false then
    installLibStub(rc)
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
