local addonName, RCLootCouncil_dibs = ...

RCLootCouncil_dibs = RCLootCouncil_dibs or {}
_G.RCLootCouncil_dibs = RCLootCouncil_dibs

Dibs = _G.Dibs or RCLootCouncil_dibs
_G.Dibs = Dibs

Dibs.ADDON_NAME = addonName or "RCLootCouncil_dibs"
Dibs.MODULE_NAME = "RCLootCouncil_dibs"
Dibs.VERSION = "0.1.0-dev"
Dibs.PROTOCOL_VERSION = 1
Dibs.DEFAULT_DIBS_PER_RANK = 1
Dibs.SAVED_VARIABLE_NAME = "RCLootCouncil_dibsDB"

if Dibs ~= RCLootCouncil_dibs then
  RCLootCouncil_dibs = Dibs
  _G.RCLootCouncil_dibs = Dibs
end

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, item in pairs(value) do
    copy[key] = deepcopy(item)
  end
  return copy
end

local function mergeDefaults(target, defaults)
  if type(target) ~= "table" then
    target = {}
  end

  for key, value in pairs(defaults) do
    if type(value) == "table" and type(target[key]) == "table" then
      mergeDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = deepcopy(value)
    end
  end

  return target
end

local defaultDB = {
  version = 1,
  currentSeasonId = nil,
  seasons = {},
  rankRules = {},
  ledger = {
    transactions = {},
    playerStates = {},
  },
  preDibs = {
    requests = {},
  },
  sync = {
    seenTransactions = {},
    peerStates = {},
  },
  settings = {
    defaultAllocation = 1,
    allowPublicPreDibs = true,
    defaultSyncInterval = 5,
  },
}

local function ensureDB()
  local dbName = Dibs.SAVED_VARIABLE_NAME or "RCLootCouncil_dibsDB"
  local persisted = _G[dbName]

  if type(persisted) ~= "table" and type(_G.DibsDB) == "table" then
    persisted = _G.DibsDB
  end

  if type(persisted) ~= "table" then
    persisted = {}
  end

  Dibs.db = persisted
  mergeDefaults(Dibs.db, defaultDB)
  _G[dbName] = Dibs.db
  _G.DibsDB = Dibs.db
end

function Dibs.GetDB()
  ensureDB()
  return Dibs.db
end

function Dibs.NewId(prefix)
  local timestamp = tostring(time() or 0)
  local randomPart = tostring(math.random(100000, 999999))
  return (prefix or "dibs") .. "-" .. timestamp .. "-" .. randomPart
end

function Dibs.GetCurrentSeasonId()
  ensureDB()
  if Dibs.db.currentSeasonId and Dibs.db.currentSeasonId ~= "" then
    return Dibs.db.currentSeasonId
  end

  if Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault then
    local season = Dibs.Seasons.GetOrCreateDefault()
    if season then
      Dibs.db.currentSeasonId = season.id
    end
  end

  return Dibs.db.currentSeasonId
end

function Dibs.GetPlayerName()
  return UnitName("player") or "UnknownPlayer"
end

function Dibs.GetTimestamp()
  return time()
end

function Dibs.Message(text)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff8b5cf6Dibs|r " .. tostring(text))
  end
end

function Dibs.ApplyDefaultRules()
  ensureDB()
  local season = Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault()
  if not season then
    return
  end

  for rankIndex = 0, 5 do
    local existing = Dibs.RankRules and Dibs.RankRules.GetAllocation(season.id, rankIndex)
    if existing == nil or existing == 0 then
      Dibs.RankRules.SetAllocation(season.id, rankIndex, "Rank " .. tostring(rankIndex), 1)
    end
  end

  local playerState = Dibs.Ledger and Dibs.Ledger.GetPlayerState(Dibs.GetPlayerName(), season.id)
  if playerState and (tonumber(playerState.allocation) or 0) == 0 then
    Dibs.Ledger.RegisterSeasonAllocation(Dibs.GetPlayerName(), season.id, 1, "Initial season allocation")
  end
end

function Dibs.HandleSlashCommand(msg)
  local command = (msg or ""):match("^%s*(.-)%s*$")
  local action = command:match("^(%S+)") or ""
  local args = {}
  for token in string.gmatch(command, "%S+") do
    table.insert(args, token)
  end

  if action == "" or action == "help" then
    Dibs.Message("Dibs commands: /dibs help | /dibs balance | /dibs ui | /dibs officer | /dibs grant <player> <amount> | /dibs use <player> <amount> | /dibs pre <itemID> [itemName] | /dibs season create [name] | /dibs season set <id> | /dibs rank set <index> <amount> [name]")
    return
  end

  if action == "balance" then
    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
    local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(Dibs.GetPlayerName(), season and season.id) or 0
    Dibs.Message("Current balance: " .. tostring(balance))
    return
  end

  if action == "ui" then
    if Dibs.PlayerUI and Dibs.PlayerUI.Show then
      Dibs.PlayerUI.Show()
    end
    return
  end

  if action == "officer" then
    if Dibs.OfficerUI and Dibs.OfficerUI.Show then
      Dibs.OfficerUI.Show()
    end
    return
  end

  if action == "grant" then
    if not Dibs.Permissions or not Dibs.Permissions.CanManageDibs() then
      Dibs.Message("You do not have permission to grant Dibs.")
      return
    end

    local playerName = args[2]
    local amount = tonumber(args[3]) or 1
    Dibs.Ledger.Grant(playerName, amount, "Officer grant", "slash", Dibs.GetCurrentSeasonId())
    Dibs.Message("Granted " .. tostring(amount) .. " Dibs to " .. tostring(playerName or "player"))
    return
  end

  if action == "use" then
    if not Dibs.Permissions or not Dibs.Permissions.CanManageDibs() then
      Dibs.Message("You do not have permission to consume Dibs.")
      return
    end

    local playerName = args[2]
    local amount = tonumber(args[3]) or 1
    Dibs.Ledger.Use(playerName, amount, "Officer consumption", "slash", Dibs.GetCurrentSeasonId())
    Dibs.Message("Consumed " .. tostring(amount) .. " Dibs from " .. tostring(playerName or "player"))
    return
  end

  if action == "pre" then
    local itemID = tonumber(args[2]) or 0
    local itemName = table.concat(args, " ", 3)
    local request = Dibs.PreDibs.Create(Dibs.GetPlayerName(), itemID, itemName ~= "" and itemName or "Item " .. tostring(itemID), Dibs.GetCurrentSeasonId())
    Dibs.Message("Pre-Dib created for item " .. tostring(itemID) .. " (status: " .. tostring(request.status) .. ")")
    return
  end

  if action == "season" then
    local mode = args[2] or "show"
    if mode == "create" then
      local name = table.concat(args, " ", 3)
      local season = Dibs.Seasons and Dibs.Seasons.Create(name ~= "" and name or nil)
      if season then
        Dibs.Message("Created season: " .. tostring(season.name) .. " (" .. tostring(season.id) .. ")")
      else
        Dibs.Message("Failed to create season.")
      end
      return
    end

    if mode == "set" then
      local seasonId = args[3]
      if Dibs.Seasons and Dibs.Seasons.SetCurrent(seasonId) then
        Dibs.Message("Current season set to: " .. tostring(seasonId))
      else
        Dibs.Message("Season not found: " .. tostring(seasonId))
      end
      return
    end

    if mode == "list" then
      local list = Dibs.Seasons and Dibs.Seasons.List() or {}
      local text = "Seasons: "
      for _, season in ipairs(list) do
        text = text .. tostring(season.name) .. ", "
      end
      Dibs.Message(text)
      return
    end

    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent()
    Dibs.Message("Current season: " .. tostring(season and season.name or "None"))
    return
  end

  if action == "rank" then
    local mode = args[2] or "list"
    if mode == "set" then
      local rankIndex = tonumber(args[3]) or 0
      local allocation = tonumber(args[4]) or 1
      local rankName = table.concat(args, " ", 5)
      if Dibs.RankRules and Dibs.RankRules.SetAllocation then
        local rule = Dibs.RankRules.SetAllocation(Dibs.GetCurrentSeasonId(), rankIndex, rankName ~= "" and rankName or "Rank " .. tostring(rankIndex), allocation)
        Dibs.Message("Rank " .. tostring(rankIndex) .. " set to " .. tostring(rule.allocation) .. " Dibs")
      end
      return
    end

    if mode == "list" then
      local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
      local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason(season and season.id or Dibs.GetCurrentSeasonId()) or {}
      local text = "Rank rules: "
      local items = {}
      for _, rule in pairs(rules) do
        table.insert(items, "R" .. tostring(rule.rankIndex) .. "=" .. tostring(rule.allocation))
      end
      table.sort(items)
      text = text .. table.concat(items, ", ")
      Dibs.Message(text)
      return
    end
  end

  Dibs.Message("Unknown Dibs command. Use /dibs help.")
end

function Dibs.SetupSlashCommands()
  if _G.SlashCmdList and not _G.SlashCmdList["DIBS"] then
    _G.SlashCmdList["DIBS"] = function(msg)
      Dibs.HandleSlashCommand(msg)
    end
    _G.SLASH_DIBS1 = "/dibs"
    _G.SLASH_DIBS2 = "/dib"
    _G.SLASH_DIBS3 = "/dids"
  end
end

function Dibs.RegisterOptionsPanel()
  if _G.DibsOptionsPanel then
    return _G.DibsOptionsPanel
  end

  local panel = CreateFrame("Frame", "DibsOptionsPanel", UIParent)
  panel.name = "RCLootCouncil_dibs"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("RCLootCouncil_dibs")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetWidth(520)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Use this panel to open Dibs windows quickly. Commands: /dibs ui, /dibs officer.")

  local openPlayerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openPlayerButton:SetSize(140, 24)
  openPlayerButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
  openPlayerButton:SetText("Open Player UI")
  openPlayerButton:SetScript("OnClick", function()
    if Dibs.PlayerUI and Dibs.PlayerUI.Toggle then
      Dibs.PlayerUI.Toggle(true)
    end
  end)

  local openOfficerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openOfficerButton:SetSize(140, 24)
  openOfficerButton:SetPoint("LEFT", openPlayerButton, "RIGHT", 12, 0)
  openOfficerButton:SetText("Open Officer UI")
  openOfficerButton:SetScript("OnClick", function()
    if Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
      Dibs.OfficerUI.Toggle(true)
    end
  end)

  if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
    local category = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    _G.Settings.RegisterAddOnCategory(category)
  elseif _G.InterfaceOptions_AddCategory then
    _G.InterfaceOptions_AddCategory(panel)
  end

  _G.DibsOptionsPanel = panel
  return panel
end

function Dibs.Initialize()
  if Dibs.initialized then
    return true
  end

  ensureDB()

  if Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault then
    Dibs.Seasons.GetOrCreateDefault()
  end

  if Dibs.RankRules then
    Dibs.ApplyDefaultRules()
  end

  if Dibs.PlayerUI and Dibs.PlayerUI.CreateWindow then
    Dibs.PlayerUI.CreateWindow()
  end

  if Dibs.OfficerUI and Dibs.OfficerUI.CreateWindow then
    Dibs.OfficerUI.CreateWindow()
  end

  if Dibs.RCLootCouncil and Dibs.RCLootCouncil.Initialize then
    Dibs.RCLootCouncil.Initialize()
  end

  Dibs.SetupSlashCommands()
  Dibs.RegisterOptionsPanel()
  Dibs.initialized = true
  Dibs.Message("Dibs initialized")
  return true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    if Dibs.RCLootCouncil and Dibs.RCLootCouncil.TryUseRCModule and Dibs.RCLootCouncil.TryUseRCModule() then
      return
    end

    Dibs.Initialize()
  end
end)

ensureDB()
