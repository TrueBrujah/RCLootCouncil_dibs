local Dibs = _G.Dibs
Dibs.RCOptions = Dibs.RCOptions or {}

local OPTIONS_APP_NAME = "RCLootCouncil_dibs"
local OPTIONS_DISPLAY_NAME = "Dibs"
local DEFAULT_MAX_ATTEMPTS = 240
local PRE_DIB_CHANNEL_VALUES = {
  NONE = "None",
  RAID = "Raid",
  RAID_WARNING = "Raid Warning",
  RAID_DIBS = "Raid Dibs",
  GUILD = "Guild",
  OFFICER = "Officer",
  PARTY = "Party",
  INSTANCE_CHAT = "Instance",
  SAY = "Say",
  YELL = "Yell",
}

local setStatus

local function debugMessage(message)
  if Dibs and Dibs.RCOptions and Dibs.RCOptions.debug == true and Dibs.Message then
    Dibs.Message("[RCOptions] " .. tostring(message))
  end
end

local function getRCAddon()
  local addon = _G.RCLootCouncil
  if LibStub ~= nil then
    local okStub, aceAddon = pcall(LibStub, "AceAddon-3.0", true)
    if okStub and aceAddon and type(aceAddon.GetAddon) == "function" then
      local okAddon, resolved = pcall(aceAddon.GetAddon, aceAddon, "RCLootCouncil", true)
      if okAddon then addon = resolved or addon end
    end
  end
  return addon
end

local function trimText(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function getDBSettings()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.settings = db.settings or {}
  if db.settings.preDibAnnouncementChannel == nil then
    db.settings.preDibAnnouncementChannel = "GUILD"
  end
  if db.settings.preDibOfficerAnnouncementChannel == nil then
    db.settings.preDibOfficerAnnouncementChannel = "OFFICER"
  end
  if db.settings.raidReminderMessage == nil then
    db.settings.raidReminderMessage = "[Dibs] Review your eligible Pre-Dibs before the encounter."
  end
  return db.settings
end

local function canEditDibsSettings()
  return type(Dibs.Permissions) == "table" and type(Dibs.Permissions.Can) == "function"
    and Dibs.Permissions.Can("settings.modify") == true
end

local function getDibTypeSettings()
  local settings = getDBSettings()
  settings.dibAllowedTypes = settings.dibAllowedTypes or {}
  return settings.dibAllowedTypes
end

local function getRCButtonsTable()
  local rc = getRCAddon()
  if type(rc) ~= "table" then
    return nil
  end
  if type(rc.GetModule) == "function" then
    local ok, ml = pcall(rc.GetModule, rc, "RCLootCouncilML", true)
    if ok and type(ml) == "table" and type(ml.db) == "table" and type(ml.db.profile) == "table" and type(ml.db.profile.buttons) == "table" then
      return ml.db.profile.buttons
    end
  end
  local profile = nil
  if type(rc.Getdb) == "function" then
    local ok, db = pcall(rc.Getdb, rc)
    if ok and type(db) == "table" then
      profile = db
    end
  end
  if profile == nil and type(rc.mldb) == "table" then
    profile = rc.mldb
  end
  if profile and type(profile.buttons) == "table" then
    return profile.buttons
  end
  return nil
end

-- RCLootCouncil exposes two different concepts in the Additional Buttons
-- menu: semantic item families (for example Armor Token) and equipment-slot
-- overrides (for example Head or Trinket). Dibs policies stay semantic; slot
-- sets only control which RCLC response group receives the injected button.
local RCLC_BUTTON_SET_DEFINITIONS = {
  { key = "CATALYST_ITEMS", label = "Catalyst Items", dibsType = nil, state = "resolved", note = "RCLC group is item-dependent: personal Catalyst is blocked, while Curios and Tier Set tokens are classified as TOKEN or TOKEN_SET." },
  { key = "ARMOR_TOKEN", label = "Armor Token", dibsType = "TOKEN_SET", state = "semantic", note = "Class-based Tier Set token." },
  { key = "MOUNTS", label = "Mounts", dibsType = "MOUNTS", state = "semantic", note = "Mount collection item." },
  { key = "PETS", label = "Pets", dibsType = "PETS", state = "semantic", note = "Battle pet or companion item." },
  { key = "RECIPES", label = "Recipes", dibsType = "RECIPE", state = "semantic", note = "Profession recipe, pattern, plan or formula." },
  { key = "DECOR", label = "Decor", dibsType = "DECOR", state = "semantic", note = "Housing decor; disabled by the default Encounter Journal matrix." },
  { key = "COSMETIC_ITEMS", label = "Cosmetic Items", dibsType = "COSMETIC", state = "blocked", note = "Cosmetic-only item; not a Dibs progression category." },
  { key = "RARE_ITEMS", label = "Rare items", dibsType = "OTHER", state = "alias", note = "RCLC rarity group; Dibs treats it as the configurable Other family." },
  { key = "SPECIAL_EFFECTS_ITEMS", label = "Items /w special effects", dibsType = "OTHER", state = "alias", note = "RCLC qualifier; Dibs treats it as the configurable Other family." },
  { key = "SLOTS", label = "Chest, Back, Feet, Finger, Hands, Head, Legs, Neck, Shoulder, Trinket, Waist, Wrist, Weapon", dibsType = nil, state = "slot", note = "Equipment-slot specificity only; it inherits the semantic Dibs decision." },
}

-- RCLootCouncil has used both INVTYPE_* keys and readable labels for the
-- equipment-slot button sets. Keep every spelling in the compatibility guide
-- so a profile created by an older release is still explained correctly.
local RCLC_SLOT_SET_KEYS = {
  BACK = true, CLOAK = true, CHEST = true, FEET = true, FINGER = true,
  HAND = true, HANDS = true, HEAD = true, HOLDABLE = true, LEGS = true,
  NECK = true, QUIVER = true, RANGED = true, RANGEDRIGHT = true,
  RELIC = true, ROBE = true, SHIELD = true, SHOULDER = true, THROWN = true,
  TRINKET = true, WAIST = true, WEAPON = true, WEAPONS = true,
  WEAPONMAINHAND = true, WEAPONOFFHAND = true, WEAPONPET = true,
  TWOHWEAPON = true, ["2H_WEAPON"] = true, ["2HWEAPON"] = true,
}

local RCLC_BUTTON_SET_ALIASES = {
  CATALYST = "CATALYST_ITEMS",
  CATALYSTS = "CATALYST_ITEMS",
  CATALYSTITEMS = "CATALYST_ITEMS",
  ARMORTOKEN = "ARMOR_TOKEN",
  MOUNT = "MOUNTS",
  PET = "PETS",
  RECIPE = "RECIPES",
  RECIPE_PATTERN = "RECIPES",
  DECORS = "DECOR",
  COSMETIC = "COSMETIC_ITEMS",
  COSMETICITEMS = "COSMETIC_ITEMS",
  RARE = "RARE_ITEMS",
  SPECIAL_EFFECTS = "SPECIAL_EFFECTS_ITEMS",
  SPECIALEFFECTSITEMS = "SPECIAL_EFFECTS_ITEMS",
}

local RCLC_BUTTON_SET_BY_KEY = {}
for _, definition in ipairs(RCLC_BUTTON_SET_DEFINITIONS) do
  RCLC_BUTTON_SET_BY_KEY[definition.key] = definition
end

local function normalizeButtonSetKey(value)
  local key = string.upper(tostring(value or ""))
  key = key:gsub("[%s%-]", "_"):gsub("_+", "_")
  return key
end

local function canonicalSemanticTypeKey(value)
  local key = normalizeButtonSetKey(value)
  local compact = key:gsub("_", "")
  if key == "" or key == "DEFAULT" then return "default" end
  if key == "CATALYST" or key == "CATALYSTS" or key == "CATALYST_ITEMS" or key == "CATALYSTITEMS" then
    return nil
  end
  if key == "COSMETIC" or key == "COSMETIC_ITEMS" or key == "COSMETICITEMS" then
    return nil
  end
  if key == "ARMOR_TOKEN" or compact == "ARMORTOKEN" then return "TOKEN_SET" end
  if key == "MOUNT" or key == "MOUNTS" then return "MOUNTS" end
  if key == "PET" or key == "PETS" then return "PETS" end
  if key == "RECIPE" or key == "RECIPES" or key == "RECIPE_PATTERN" then return "RECIPE" end
  if key == "DECORS" then return "DECOR" end
  if key == "RARE_ITEMS" or key == "RARE" or key == "SPECIAL_EFFECTS" or key == "SPECIAL_EFFECTS_ITEMS" or compact == "SPECIALEFFECTSITEMS" then return "OTHER" end
  if key == "TOKEN" or key == "TOKENS" then return "TOKEN" end
  if key == "TOKEN_SET" or key == "TOKEN_SETS" or key == "TOKENSET" then return "TOKEN_SET" end
  if key == "OTHER" or key == "OTHERS" then return "OTHER" end
  return tostring(value)
end

local function getButtonSetDefinition(value)
  local normalized = normalizeButtonSetKey(value)
  local compact = normalized:gsub("_", "")
  local canonical = RCLC_BUTTON_SET_ALIASES[normalized] or RCLC_BUTTON_SET_ALIASES[compact] or normalized
  if canonical:match("^INVTYPE_") or RCLC_SLOT_SET_KEYS[canonical] or RCLC_SLOT_SET_KEYS[compact] then
    return RCLC_BUTTON_SET_BY_KEY.SLOTS
  end
  return RCLC_BUTTON_SET_BY_KEY[canonical]
end

local function getDibTypeLabel(value)
  local key = normalizeButtonSetKey(value)
  if key == "DEFAULT" then return "Default fallback" end
  if key == "TOKEN" then return "Curio tokens (TOKEN)" end
  if key == "TOKEN_SET" then return "Tier Set tokens (TOKEN_SET)" end
  if key == "MOUNTS" then return "Mounts (MOUNTS)" end
  if key == "PETS" then return "Pets (PETS)" end
  if key == "RECIPE" or key == "RECIPES" then return "Recipes (RECIPE)" end
  if key == "DECOR" then return "Decor (DECOR)" end
  if key == "OTHER" then return "Other (OTHER)" end
  local definition = getButtonSetDefinition(value)
  if definition and definition.dibsType then
    if definition.state == "blocked" then
      return definition.label .. " (blocked: personal/cosmetic)"
    end
    return definition.label .. " -> " .. tostring(definition.dibsType)
  end
  if definition and definition.state == "slot" then
    return key:gsub("^INVTYPE_", "") .. " (RCLC slot)"
  end
  if key:match("^INVTYPE_") then
    return key:gsub("^INVTYPE_", "") .. " (RCLC slot)"
  end
  return tostring(value)
end

local function buildButtonSetMappingText()
  local lines = {
    "RCLootCouncil button sets choose where the Dibs response is displayed; Dibs eligibility remains semantic.",
    "Curio = TOKEN  |  Tier Set class token = TOKEN_SET  |  Catalyst = personal and always blocked.",
  }
  for _, definition in ipairs(RCLC_BUTTON_SET_DEFINITIONS) do
    local target = definition.dibsType and (" -> " .. definition.dibsType) or ""
    local marker = definition.state == "blocked" and " [blocked]"
      or (definition.state == "slot" and " [compatibility]")
      or (definition.state == "resolved" and " [resolved]")
      or ""
    table.insert(lines, definition.label .. target .. marker .. " -> " .. definition.note)
  end
  return table.concat(lines, "\n")
end

local function buildConfiguredButtonSetsText()
  local buttons = getRCButtonsTable()
  if type(buttons) ~= "table" then
    return "Configured RCLootCouncil sets: unavailable until the Master Looter profile is loaded."
  end
  local keys = {}
  for key, spec in pairs(buttons) do
    if key ~= "default" and key ~= "*" and type(spec) == "table" then
      table.insert(keys, tostring(key))
    end
  end
  table.sort(keys)
  if #keys == 0 then
    return "Configured RCLootCouncil sets: Default only."
  end
  local labels = { "Default" }
  for _, key in ipairs(keys) do table.insert(labels, getDibTypeLabel(key)) end
  return "Configured RCLootCouncil sets: " .. table.concat(labels, ", ")
end

local function getDibTypeValues()
  local values = {
    default = "Default fallback",
  }

  local function addValue(key)
    if key == nil then return end
    local text = canonicalSemanticTypeKey(key)
    if text == nil then return end
    if text == "" or text == "*" then return end
    if values[text] ~= nil then return end
    values[text] = getDibTypeLabel(text)
  end

  -- Always expose core categories even when RC has not populated per-type button sets yet.
  addValue("MOUNTS")
  addValue("PETS")
  addValue("TOKEN")
  addValue("TOKEN_SET")
  addValue("RECIPE")
  addValue("DECOR")
  addValue("OTHER")

  -- Keep persisted keys visible so users can recover from old hidden false values.
  for key in pairs(getDibTypeSettings()) do
    addValue(key)
  end

  local buttons = getRCButtonsTable()
  if type(buttons) == "table" then
    for key, spec in pairs(buttons) do
      if key ~= "default" and key ~= "*" and type(spec) == "table" then
        addValue(key)
      end
    end
  end
  return values
end

local function setDibTypeEnabled(typeKey, enabled)
  if not canEditDibsSettings() then
    setStatus("Only the guild master or an officer may change Dibs settings.")
    return false
  end
  local semanticKey = canonicalSemanticTypeKey(typeKey)
  if semanticKey == nil then
    setStatus("This RCLootCouncil item family is not eligible for Dibs.")
    return false, "PERSONAL_ITEM_TYPE"
  end
  typeKey = semanticKey
  if Dibs.RCLootCouncil and Dibs.RCLootCouncil.SetDibEnabledForType then
    local ok, reason = Dibs.RCLootCouncil.SetDibEnabledForType(typeKey, enabled == true)
    return ok ~= nil, reason
  else
    getDibTypeSettings()[tostring(typeKey)] = enabled == true
    return true
  end
end

local function applyDibTypePreset(allEnabled)
  if not canEditDibsSettings() then
    setStatus("Only the guild master or an officer may change Dibs settings.")
    return
  end
  local values = getDibTypeValues()
  local settings = getDibTypeSettings()

  if allEnabled then
    for key in pairs(settings) do
      settings[key] = nil
    end
    for key in pairs(values) do
      setDibTypeEnabled(key, true)
    end
    setStatus("DIB policy preset applied: All enabled.")
    return
  end

  for key in pairs(values) do
    if tostring(key) == "default" then
      setDibTypeEnabled(key, true)
    else
      setDibTypeEnabled(key, false)
    end
  end
  setStatus("DIB policy preset applied: All disabled except default.")
end

local DIBS_SEMANTIC_TEMPLATE_KEYS = {
  "default", "TOKEN", "TOKEN_SET", "MOUNTS", "PETS", "RECIPE", "DECOR", "OTHER",
}

local DIBS_SEMANTIC_TEMPLATES = {
  progression = {
    label = "Curio + Tier Set",
    enabled = { TOKEN = true, TOKEN_SET = true },
    description = "Only Curio and class-based Tier Set tokens can create a Dibs action. Unknown, cosmetic and personal items stay out.",
  },
  broad = {
    label = "Standard loot",
    enabled = { TOKEN = true, TOKEN_SET = true, MOUNTS = true, PETS = true, RECIPE = true, OTHER = true },
    description = "Enables Curio, Tier Set, mounts, pets, recipes and Other. Decor remains disabled until an officer enables it.",
  },
}

local function applyDibSemanticTemplate(templateKey)
  if not canEditDibsSettings() then
    setStatus("Only the guild master or an officer may change Dibs settings.")
    return false
  end
  local template = DIBS_SEMANTIC_TEMPLATES[templateKey]
  if not template then
    setStatus("Unknown Dibs semantic template.")
    return false
  end

  for _, key in ipairs(DIBS_SEMANTIC_TEMPLATE_KEYS) do
    local enabled = template.enabled[key] == true
    local ok, reason = setDibTypeEnabled(key, enabled)
    if not ok then
      setStatus(reason or ("Unable to apply template to " .. tostring(key) .. "."))
      return false
    end
  end
  setStatus("DIB semantic template applied: " .. template.label .. ".")
  return true
end

-- The installation assistant applies a Dibs policy and then asks the
-- integration to refresh its locked DIB projection.  It deliberately does
-- not rewrite RCLootCouncil's existing response text, colours or ordering;
-- the projection only adds/reuses the dedicated DIB entry in sets that the
-- Master Looter already configured.
local function applyInstallationPreset(templateKey)
  if not applyDibSemanticTemplate(templateKey) then
    return false
  end

  local integration = Dibs.RCLootCouncil
  if integration and type(integration.RefreshConfigProjection) == "function" then
    local available, changed = integration.RefreshConfigProjection()
    if available then
      setStatus((templateKey == "progression" and "Curio + Tier Set" or "Standard loot") ..
        " preset applied; the Dibs button is prepared in the configured RCLootCouncil sets." ..
        (changed == true and "" or " Existing button configuration was already ready."))
      return true
    end
  end

  setStatus((templateKey == "progression" and "Curio + Tier Set" or "Standard loot") ..
    " preset applied. RCLootCouncil is unavailable, so Dibs will use its standalone controls.")
  return true
end

local function buildSetupAssistantStatus()
  local integration = Dibs.RCLootCouncil
  if not integration or type(integration.GetConfigProjectionStatus) ~= "function" then
    return "RCLootCouncil is not loaded. Choose a Dibs preset now; the button will be prepared automatically when RCLootCouncil becomes available."
  end

  local ok, projection = pcall(integration.GetConfigProjectionStatus)
  if not ok or type(projection) ~= "table" or projection.addonFound ~= true then
    return "RCLootCouncil is unavailable. Dibs remains usable in Standalone mode."
  end

  local default = projection.default
  local defaultReady = default and default.buttonDibIndex and default.responseDibIndex
  local enabledAdditional, readyAdditional = 0, 0
  for _, entry in pairs(projection.additional or {}) do
    if entry.enabled == true then
      enabledAdditional = enabledAdditional + 1
      if entry.buttonDibIndex and entry.responseDibIndex then
        readyAdditional = readyAdditional + 1
      end
    end
  end
  return "Dibs button: " .. (defaultReady and "ready in the default set" or "not ready in the default set") ..
    ". Additional sets ready: " .. tostring(readyAdditional) .. "/" .. tostring(enabledAdditional) .. "."
end

local function getEJSubCategoryValues()
  if Dibs.EncounterJournal and Dibs.EncounterJournal.GetSubCategoryMatrixValues then
    return Dibs.EncounterJournal.GetSubCategoryMatrixValues()
  end
  return {}
end

local function isEJSubCategoryAllowed(key)
  if Dibs.EncounterJournal and Dibs.EncounterJournal.IsSubCategoryAllowed then
    return Dibs.EncounterJournal.IsSubCategoryAllowed(key) == true
  end
  return true
end

local function setEJSubCategoryAllowed(key, value)
  if Dibs.EncounterJournal and Dibs.EncounterJournal.SetSubCategoryAllowed then
    Dibs.EncounterJournal.SetSubCategoryAllowed(key, value == true)
  else
    setStatus("Encounter Journal matrix module unavailable.")
  end
end

local function getSeasonList()
  local seasons = Dibs.Seasons and Dibs.Seasons.List and Dibs.Seasons.List() or {}
  table.sort(seasons, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)
  return seasons
end

local function getCurrentSeasonLabel()
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent and Dibs.Seasons.GetCurrent() or nil
  if not season then
    return "None"
  end
  return tostring(season.name) .. " (" .. tostring(season.id) .. ")"
end

local function getSeasonValues()
  local values = {}
  local currentId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
  for _, season in ipairs(getSeasonList()) do
    local marker = season.id == currentId and " [ACTIVE]" or ""
    values[season.id] = tostring(season.name) .. marker
  end
  return values
end

local function getGuildRankNames()
  local names = {}

  if type(_G.GuildControlGetNumRanks) == "function" and type(_G.GuildControlGetRankName) == "function" then
    local okCount, rankCount = pcall(_G.GuildControlGetNumRanks)
    if okCount and tonumber(rankCount) then
      for i = 1, tonumber(rankCount) do
        local okName, rankName = pcall(_G.GuildControlGetRankName, i)
        if okName and rankName and rankName ~= "" then
          names[i - 1] = tostring(rankName)
        end
      end
    end
  end

  if names[0] == nil then names[0] = "Guild Master" end
  if names[1] == nil then names[1] = "Officer" end
  if names[2] == nil then names[2] = "Veteran" end
  if names[3] == nil then names[3] = "Member" end
  return names
end

local function getRankValues()
  local values = {}
  local names = getGuildRankNames()
  local maxRank = 9

  if type(_G.GuildControlGetNumRanks) == "function" then
    local okCount, rankCount = pcall(_G.GuildControlGetNumRanks)
    if okCount and tonumber(rankCount) then
      maxRank = math.max(maxRank, tonumber(rankCount) - 1)
    end
  end

  for idx = 0, maxRank do
    values[idx] = tostring(idx) .. " - " .. tostring(names[idx] or ("Rank " .. tostring(idx)))
  end
  return values
end

local function seasonIsValid(seasonId)
  if not seasonId then
    return false
  end
  return Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId) ~= nil
end

local getState

local function getSelectedSeasonId()
  local state = getState()
  if seasonIsValid(state.selectedSeasonId) then
    return state.selectedSeasonId
  end
  return Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
end

local function getRankAllocationForSeason(seasonId, rankIndex)
  local allocation = nil
  if Dibs.RankRules and Dibs.RankRules.GetAllocation then
    allocation = Dibs.RankRules.GetAllocation(seasonId, rankIndex)
  end
  allocation = tonumber(allocation)
  if allocation == nil then
    return tonumber(getDBSettings().defaultAllocation) or 1
  end
  return allocation
end

local function buildRankSummaryText(seasonId)
  local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason and Dibs.RankRules.GetRulesForSeason(seasonId) or {}
  local entries = {}
  for _, rule in pairs(rules) do
    local idx = tonumber(rule.rankIndex) or 0
    local name = getGuildRankNames()[idx] or rule.rankName or ("Rank " .. tostring(idx))
    local amount = tonumber(rule.allocation) or 0
    table.insert(entries, { idx = idx, text = tostring(idx) .. " - " .. tostring(name) .. " = " .. tostring(amount) })
  end

  table.sort(entries, function(a, b)
    return a.idx < b.idx
  end)

  if #entries == 0 then
    return "No custom rank rules yet. Choose a rank and save an allocation."
  end

  local lines = {}
  for _, entry in ipairs(entries) do
    table.insert(lines, entry.text)
  end
  return "Current rank rules:\n" .. table.concat(lines, "\n")
end

getState = function()
  Dibs.RCOptions.state = Dibs.RCOptions.state or {
    selectedSeasonId = nil,
    createSeasonName = "",
    renameSeasonName = "",
    rankIndex = 0,
    rankAllocation = 1,
    status = "Ready",
  }
  return Dibs.RCOptions.state
end

setStatus = function(message)
  local state = getState()
  state.status = tostring(message or "")
  if Dibs.Message then
    Dibs.Message(state.status)
  end
end

local optionsTable = {
  type = "group",
  name = "RCLootCouncil",
  args = {
    dibsSettings = {
      type = "group",
      name = OPTIONS_DISPLAY_NAME,
      childGroups = "tab",
      args = {
        overview = {
          order = 1,
          type = "group",
          name = "Overview",
          inline = true,
          args = {
            intro = {
              order = 1,
              type = "description",
              width = "full",
              name = "Manage Dibs directly here.",
            },
            activeSeason = {
              order = 2,
              type = "description",
              width = "full",
              name = function()
                return "Active season: " .. getCurrentSeasonLabel()
              end,
            },
            status = {
              order = 3,
              type = "description",
              width = "full",
              name = function()
                local status = tostring(getState().status or "Ready")
                local lower = string.lower(status)
                local bad = lower:find("denied", 1, true) or lower:find("not authorized", 1, true)
                  or lower:find("error", 1, true) or lower:find("unavailable", 1, true)
                  or lower:find("pas autor", 1, true) or lower:find("refus", 1, true)
                  or lower:find("erreur", 1, true) or lower:find("indispon", 1, true)
                return "|c" .. (bad and "ffff3333" or "ff66ff99") .. "Status: " .. status .. "|r"
              end,
            },
          },
        },
        seasons = {
          order = 2,
          type = "group",
          name = "Seasons",
          args = {
            selectedSeason = {
              order = 1,
              type = "select",
              name = "Selected season",
              width = "double",
              values = function()
                return getSeasonValues()
              end,
              get = function()
                local state = getState()
                if seasonIsValid(state.selectedSeasonId) then
                  return state.selectedSeasonId
                end
                return Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
              end,
              set = function(_, value)
                local state = getState()
                state.selectedSeasonId = tostring(value)
                local season = Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(state.selectedSeasonId)
                if season then
                  state.renameSeasonName = season.name
                end
              end,
            },
            activateSeason = {
              order = 2,
              type = "execute",
              name = "Set Active",
              func = function()
                local state = getState()
                local seasonId = seasonIsValid(state.selectedSeasonId) and state.selectedSeasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
                local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = seasonId }) or { ok = false, diagnostic = "Protected actions unavailable." }
                setStatus(result.ok and ("Active season: " .. tostring(seasonId)) or (result.diagnostic or "Unable to set active season."))
              end,
            },
            createSeasonName = {
              order = 3,
              type = "input",
              width = "double",
              name = "New season name",
              get = function()
                return tostring(getState().createSeasonName or "")
              end,
              set = function(_, value)
                getState().createSeasonName = trimText(value)
              end,
            },
            createSeason = {
              order = 4,
              type = "execute",
              name = "Create",
              func = function()
                local state = getState()
                local payloadName = trimText(state.createSeasonName)
                local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("season.create", nil, { name = payloadName ~= "" and payloadName or nil }) or { ok = false, diagnostic = "Protected actions unavailable." }
                if result.ok and result.value then
                  state.selectedSeasonId = result.value.id
                  state.renameSeasonName = result.value.name
                  state.createSeasonName = ""
                  setStatus("Created season: " .. tostring(result.value.name))
                else
                  setStatus(result.diagnostic or "Failed to create season.")
                end
              end,
            },
            renameSeasonName = {
              order = 5,
              type = "input",
              width = "double",
              name = "Rename selected to",
              get = function()
                local state = getState()
                if state.renameSeasonName and state.renameSeasonName ~= "" then
                  return state.renameSeasonName
                end
                local seasonId = seasonIsValid(state.selectedSeasonId) and state.selectedSeasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
                local season = seasonId and Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId)
                return season and tostring(season.name) or ""
              end,
              set = function(_, value)
                getState().renameSeasonName = trimText(value)
              end,
            },
            renameSeason = {
              order = 6,
              type = "execute",
              name = "Rename",
              func = function()
                local state = getState()
                local seasonId = seasonIsValid(state.selectedSeasonId) and state.selectedSeasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
                local newName = trimText(state.renameSeasonName)
                if not seasonId or newName == "" then
                  setStatus("Select a season and enter a new name first.")
                  return
                end
                 local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("season.rename", nil, { seasonId = seasonId, name = newName }) or { ok = false, diagnostic = "Protected actions unavailable." }
                 if result.ok and result.value then
                   setStatus("Season renamed: " .. tostring(result.value.name))
                 else
                   setStatus(result.diagnostic or "Unable to rename season.")
                 end
              end,
            },
            archiveSeason = {
              order = 7,
              type = "execute",
              name = "Delete (Archive)",
              func = function()
                local seasons = getSeasonList()
                if #seasons <= 1 then
                  setStatus("At least one season must remain.")
                  return
                end

                local state = getState()
                local seasonId = seasonIsValid(state.selectedSeasonId) and state.selectedSeasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
                 local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("season.archive", nil, { seasonId = seasonId }) or { ok = false, diagnostic = "Protected actions unavailable." }
                 if result.ok and result.value then
                   state.selectedSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
                   setStatus("Season archived: " .. tostring(result.value.name))
                 else
                   setStatus(result.diagnostic or "Unable to archive season.")
                 end
              end,
            },
          },
        },
        ranks = {
          order = 3,
          type = "group",
          name = "Rank Rules",
          args = {
            rankSummary = {
              order = 1,
              type = "description",
              width = "full",
              name = function()
                return buildRankSummaryText(getSelectedSeasonId())
              end,
            },
            rankIndex = {
              order = 2,
              type = "select",
              name = "Guild rank",
              width = "full",
              values = function()
                return getRankValues()
              end,
              get = function()
                return tonumber(getState().rankIndex) or 0
              end,
              set = function(_, value)
                local state = getState()
                state.rankIndex = tonumber(value) or 0
                state.rankAllocation = getRankAllocationForSeason(getSelectedSeasonId(), state.rankIndex)
              end,
            },
            rankAllocation = {
              order = 3,
              type = "range",
              name = "Dibs allocation",
              width = "full",
              min = 0,
              max = 20,
              step = 1,
              get = function()
                local state = getState()
                if state.rankAllocation == nil then
                  return getRankAllocationForSeason(getSelectedSeasonId(), state.rankIndex)
                end
                return tonumber(state.rankAllocation) or 1
              end,
              set = function(_, value)
                getState().rankAllocation = tonumber(value) or 1
              end,
            },
            applyRank = {
              order = 4,
              type = "execute",
              width = "full",
              name = "Save rule for selected season",
              func = function()
                local state = getState()
                local seasonId = getSelectedSeasonId()
                local rankIndex = tonumber(state.rankIndex) or 0
                local allocation = tonumber(state.rankAllocation) or 1
                local rankName = getGuildRankNames()[rankIndex] or ("Rank " .. tostring(rankIndex))
                local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("rank.set", nil, {
                  seasonId = seasonId,
                  rankIndex = rankIndex,
                  rankName = rankName,
                  allocation = allocation,
                }) or { ok = false, diagnostic = "Protected actions unavailable." }
                setStatus(result.ok and ("Saved rule: " .. tostring(rankName) .. " = " .. tostring(allocation)) or (result.diagnostic or "Failed to set rank allocation."))
              end,
            },
          },
        },
        settings = {
          order = 4,
          type = "group",
          name = "Settings",
          args = {
            language = {
              order = 0, type = "select", name = "Language", desc = "Choose Auto, English or French. English is used as the fallback.",
              values = { AUTO = "Auto (WoW client)", enUS = "English", frFR = "Français" },
              get = function() return getDBSettings().language or "AUTO" end,
              set = function(_, value)
                if canEditDibsSettings() then
                  getDBSettings().language = tostring(value)
                  setStatus("Language preference saved; reload to refresh text.")
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            defaultAllocation = {
              order = 1,
              type = "range",
              name = "Default allocation",
              desc = "Fallback Dibs amount used when a season/rank has no explicit rule yet.",
              min = 0,
              max = 20,
              step = 1,
              get = function()
                return tonumber(getDBSettings().defaultAllocation) or 1
              end,
              set = function(_, value)
                if canEditDibsSettings() then
                  getDBSettings().defaultAllocation = tonumber(value) or 1
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            officerMaxRankIndex = {
              order = 1.25,
              type = "range",
              name = "Highest officer rank index",
              desc = "Guild rank 0 is the GM. Ranks 1 through this value are treated as Dibs officers unless explicit rank indices are configured.",
              min = 1,
              max = 9,
              step = 1,
              get = function()
                return math.max(1, math.min(9, tonumber(getDBSettings().officerMaxRankIndex) or 1))
              end,
              set = function(_, value)
                if canEditDibsSettings() then
                  getDBSettings().officerMaxRankIndex = math.max(1, math.min(9, math.floor(tonumber(value) or 1)))
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            installationMode = {
              order = 1.5,
              type = "select",
              name = "Installation mode",
              desc = "AUTO detects RCLootCouncil; Standalone keeps Dibs independent; RCLootCouncil requires the adapter.",
              values = { AUTO = "Automatic", STANDALONE = "Standalone", RCLootCouncil = "RCLootCouncil integration" },
              get = function()
                return Dibs.Permissions and Dibs.Permissions.GetInstallationMode and Dibs.Permissions.GetInstallationMode() or "AUTO"
              end,
              set = function(_, value)
                local result = Dibs.ProtectedActions.Execute("installation.mode.set", nil, { mode = value, source = "ace-config" })
                setStatus(result.ok and ("Installation mode: " .. tostring(result.value)) or (result.diagnostic or "Installation mode update denied."))
              end,
            },
            defaultSyncInterval = {
              order = 2,
              type = "range",
              name = "Default sync interval (minutes)",
              min = 1,
              max = 60,
              step = 1,
              get = function()
                return tonumber(getDBSettings().defaultSyncInterval) or 5
              end,
              set = function(_, value)
                if canEditDibsSettings() then
                  getDBSettings().defaultSyncInterval = tonumber(value) or 5
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            raidEntryDibPromptsEnabled = {
              order = 3,
              type = "toggle",
              name = "Show raid entry Dib prompt",
              get = function()
                return Dibs.RaidPrompts and Dibs.RaidPrompts.IsEnabled and Dibs.RaidPrompts.IsEnabled() or false
              end,
              set = function(_, value)
                if not canEditDibsSettings() then
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                  return
                end
                if Dibs.RaidPrompts and Dibs.RaidPrompts.SetEnabled then
                  local ok, reason = Dibs.RaidPrompts.SetEnabled(value)
                  if not ok then setStatus(reason or "Unable to update raid prompts.") end
                end
              end,
            },
            raidReminderMessage = {
              order = 4,
              type = "input",
              width = "full",
              name = "Raid reminder message",
              get = function()
                if Dibs.PreDibs and Dibs.PreDibs.GetAnnouncementTemplates then
                  return Dibs.PreDibs.GetAnnouncementTemplates().reminder
                end
                return tostring(getDBSettings().raidReminderTemplate or getDBSettings().raidReminderMessage or "")
              end,
              set = function(_, value)
                local reminder = tostring(value or "")
                if canEditDibsSettings() then
                  Dibs.PreDibs.SetAnnouncementTemplates(nil, reminder)
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            sendRaidReminder = {
              order = 5,
              type = "execute",
              name = "Send raid reminder",
              func = function()
                local ok, reason = false, "REMINDER_UNAVAILABLE"
                if Dibs.RaidRelay and Dibs.RaidRelay.SendReminder then
                  ok, reason = Dibs.RaidRelay.SendReminder(Dibs.PreDibs.GetAnnouncementTemplates().reminder)
                end
                setStatus(ok and "Raid reminder sent." or tostring(reason))
              end,
            },
            ejSubCategoryPolicyIntro = {
              order = 6,
              type = "description",
              width = "full",
              name = "Adventure Guide (Raids) Dib matrix: allow or block the Dib button by detected loot sub-category.",
            },
            ejSubCategoryPolicy = {
              order = 7,
              type = "multiselect",
              width = "full",
              name = "Allow Dib for these Adventure Guide raid sub-categories",
              values = function()
                return getEJSubCategoryValues()
              end,
              get = function(_, key)
                return isEJSubCategoryAllowed(key)
              end,
              set = function(_, key, value)
                if canEditDibsSettings() then
                  setEJSubCategoryAllowed(key, value == true)
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            ejSubCategoryMatrixApply = {
              order = 8,
              type = "execute",
              width = "half",
              name = "Preset: EJ recommended",
              func = function()
                if not canEditDibsSettings() then setStatus("Only the guild master or an officer may change Dibs settings.") return end
                if Dibs.EncounterJournal and Dibs.EncounterJournal.ApplyRecommendedSubCategoryMatrix then
                  Dibs.EncounterJournal.ApplyRecommendedSubCategoryMatrix()
                  setStatus("Encounter Journal matrix preset applied.")
                else
                  setStatus("Encounter Journal matrix module unavailable.")
                end
              end,
            },
            ejSubCategoryScanNow = {
              order = 9,
              type = "execute",
              width = "half",
              name = "Scan EJ now",
              func = function()
                if Dibs.EncounterJournal and Dibs.EncounterJournal.DumpVisibleLootDebug then
                  Dibs.EncounterJournal.DumpVisibleLootDebug()
                  setStatus("Encounter Journal scan completed. Open chat for detailed EJDBG rows.")
                else
                  setStatus("Encounter Journal scan is unavailable.")
                end
              end,
            },
          },
        },
        preDibs = {
          order = 5,
          type = "group",
          name = "Pre-Dibs",
          args = {
            intro = {
              order = 1,
              type = "description",
              width = "full",
              name = "Public pre-dibs let players reserve items in advance. Confirmed reservations lock non-reserved candidates on drop.",
            },
            mode = {
              order = 2,
              type = "select",
              name = "Active season request mode",
              values = { WILD_OPEN = "Wild Open", ENCOUNTER = "Encounter" },
              get = function()
                local policy = Dibs.PreDibs and Dibs.PreDibs.GetModePolicy and Dibs.PreDibs.GetModePolicy(getSelectedSeasonId()) or {}
                return policy.mode or "WILD_OPEN"
              end,
              set = function(_, value)
                local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("predib.mode.set", nil, {
                  seasonId = getSelectedSeasonId(), mode = value, source = "ace-config",
                }) or { ok = false, diagnostic = "Protected actions unavailable." }
                setStatus(result.ok and "Pre-Dib mode updated." or (result.diagnostic or "Mode update denied."))
              end,
            },
            allowPublicPreDibs = {
              order = 3,
              type = "toggle",
              name = "Allow public pre-dibs",
              get = function()
                return getDBSettings().allowPublicPreDibs ~= false
              end,
              set = function(_, value)
                if canEditDibsSettings() then
                  getDBSettings().allowPublicPreDibs = value == true
                else
                  setStatus("Only the guild master or an officer may change Dibs settings.")
                end
              end,
            },
            preDibAnnouncementChannel = {
              order = 4,
              type = "select",
              name = "Public pre-dib announce channel",
              desc = "Channel used to announce player pre-dibs (raid/guild).",
              values = PRE_DIB_CHANNEL_VALUES,
              get = function()
                local settings = getDBSettings()
                if Dibs.PreDibs and Dibs.PreDibs.GetAnnouncementSettings then
                  return Dibs.PreDibs.GetAnnouncementSettings().publicChannel
                end
                return tostring(settings.preDibAnnouncementChannel or "GUILD")
              end,
              set = function(_, value)
                if not canEditDibsSettings() then setStatus("Only the guild master or an officer may change Dibs settings.") return end
                local settings = getDBSettings()
                if Dibs.PreDibs and Dibs.PreDibs.SetAnnouncementChannels then
                  Dibs.PreDibs.SetAnnouncementChannels(value, settings.preDibOfficerAnnouncementChannel)
                end
              end,
            },
            preDibOfficerAnnouncementChannel = {
              order = 5,
              type = "select",
              name = "Officer pre-dib announce channel",
              desc = "Extra channel for officer visibility on pre-dibs.",
              values = PRE_DIB_CHANNEL_VALUES,
              get = function()
                local settings = getDBSettings()
                if Dibs.PreDibs and Dibs.PreDibs.GetAnnouncementSettings then
                  return Dibs.PreDibs.GetAnnouncementSettings().officerChannel
                end
                return tostring(settings.preDibOfficerAnnouncementChannel or "OFFICER")
              end,
              set = function(_, value)
                if not canEditDibsSettings() then setStatus("Only the guild master or an officer may change Dibs settings.") return end
                local settings = getDBSettings()
                if Dibs.PreDibs and Dibs.PreDibs.SetAnnouncementChannels then
                  Dibs.PreDibs.SetAnnouncementChannels(settings.preDibAnnouncementChannel, value)
                end
              end,
            },
          },
        },
      },
    },
  },
}

-- Every surface reads the same services and SavedVariables.
local groups = optionsTable.args.dibsSettings.args
local function description(order, name)
  return { type = "description", order = order, width = "full", name = name }
end
local function execute(order, name, callback)
  return { type = "execute", order = order, name = name, width = "full", func = callback }
end
local function integrationStatusText()
  local status = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or {
    status = "absent", reasonCode = "RC_ABSENT", diagnostic = "RCLootCouncil is absent; Dibs is running in Standalone mode.", capabilities = {},
  }
  local capabilities = status.capabilities or {}
  local verified = {}
  for _, key in ipairs({ "discovery", "enabledState", "masterLooter", "awardCallback", "awardIdentity", "responseValidation" }) do
    if capabilities[key] == true then table.insert(verified, key) end
  end
  return "RCLootCouncil: " .. tostring(status.status or status.availability or "absent") ..
    " | reason: " .. tostring(status.reasonCode or "UNKNOWN") ..
    "\n" .. tostring(status.diagnostic or "") ..
    "\nVerified capabilities: " .. (#verified > 0 and table.concat(verified, ", ") or "none")
end
local function auditAction(action, scope, detail)
  local db = Dibs.GetDB()
  db.settings.actionAudit = db.settings.actionAudit or {}
  table.insert(db.settings.actionAudit, { action = tostring(action), scope = tostring(scope), detail = tostring(detail or ""), actor = Dibs.GetPlayerName(), createdAt = time() })
  while #db.settings.actionAudit > 200 do table.remove(db.settings.actionAudit, 1) end
end
local function officerOnly()
  return not Dibs.RCOptions.IsOfficerPreview()
end
function Dibs.RCOptions.IsOfficerPreview()
  if Dibs.Permissions and Dibs.Permissions.IsOfficer and Dibs.Permissions.IsOfficer() then return true end
  local name = type(UnitName) == "function" and UnitName("player") or ""
  local realm = type(GetRealmName) == "function" and GetRealmName() or ""
  return string.lower(tostring(name)) == "nanarus" and string.lower(tostring(realm)):gsub("%s+", "") == "durotan"
end
function Dibs.RCOptions.IsOfficerPreviewOnly()
  return Dibs.RCOptions.IsOfficerPreview() and not (Dibs.Permissions and Dibs.Permissions.IsOfficer and Dibs.Permissions.IsOfficer())
end
-- Window actions live in their corresponding tabs, not in Overview.
groups.overview.args.player = nil
groups.overview.args.officer = nil
groups.overview.args.integrationStatus = description(4, integrationStatusText)
groups.overview.args.operationalNote = description(5,
  "Live data, searches, history and statistics open in separate Dibs windows so Blizzard and RCLootCouncil settings remain usable beside them.")
groups.overview.args.openPlayerWindow = execute(6, "Open Player window", function()
  if Dibs.PlayerUI and Dibs.PlayerUI.Toggle then Dibs.PlayerUI.Toggle(true) end
end)
groups.overview.args.openOfficerWindow = execute(7, "Open Officer control center", function()
  if Dibs.OfficerUI and Dibs.OfficerUI.Toggle then Dibs.OfficerUI.Toggle(true) end
end)
groups.announcements = { type = "group", name = "Announcements", order = 6, args = {
  publicChannel = groups.preDibs.args.preDibAnnouncementChannel,
  officerChannel = groups.preDibs.args.preDibOfficerAnnouncementChannel,
  variables = description(6, "Variables: %player %item %itemID %difficulty %mode %status %season %date %time %requestID %source %channel"),
  preDibTemplate = { type = "input", name = "Pre-Dib announcement", order = 7, width = "full",
    get = function() return Dibs.PreDibs.GetAnnouncementTemplates().preDib end,
    set = function(_, value) Dibs.PreDibs.SetAnnouncementTemplates(value, nil) end },
  reminderTemplate = groups.settings.args.raidReminderMessage,
  sendReminder = groups.settings.args.sendRaidReminder,
  raidDibsStatus = description(10, function()
    local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
    return clubId and ("Raid Dibs: available (club " .. tostring(clubId) .. ", stream " .. tostring(streamId) .. ")")
      or "Raid Dibs: channel not found for this character. Join the community/channel, then refresh."
  end),
  refresh = execute(11, "Refresh", function() end),
  preview = description(14, function()
    local templates = Dibs.PreDibs.GetAnnouncementTemplates()
    return "Pre-Dib: " .. Dibs.PreDibs.FormatAnnouncement(templates.preDib, {
      playerName = Dibs.GetPlayerName(), itemName = "Example item", itemID = 12345,
      difficulty = "Mythic", modeAtCreation = "WILD_OPEN", status = "confirmed",
      seasonId = getSelectedSeasonId(), requestId = "example", source = "Preview",
    }) .. "\nReminder: " .. Dibs.PreDibs.FormatAnnouncement(templates.reminder, { source = "Raid reminder" })
  end),
  reset = execute(15, "Reset templates", function()
    Dibs.PreDibs.SetAnnouncementTemplates("[Dibs] %player requested %item (%difficulty) - %date %time",
      "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]")
  end),
} }
for index, channelKind in ipairs({ "publicChannel", "officerChannel" }) do
  groups.announcements.args["test" .. channelKind] = execute(11 + index, "Test " .. (index == 1 and "public channel" or "officer channel"), function()
    local ok, reason = Dibs.PreDibs.SendTestAnnouncement(Dibs.PreDibs.GetAnnouncementSettings()[channelKind], "Dibs options")
    setStatus(ok and "Announcement test sent." or ((reason == "RAID_DIBS_NOT_JOINED" or reason == "RAID_DIBS_UNAVAILABLE") and "Raid Dibs is not joined on this character." or tostring(reason)))
  end)
end
groups.player = { type = "group", name = "Player", order = 7, args = {
  summary = description(1, function()
    local summary = Dibs.PlayerUI.GetSummary()
    return "Season: " .. tostring(summary.season and summary.season.name or "None") .. "\nDibs: " .. tostring(summary.balance)
  end),
  readiness = description(1.5, function()
    if Dibs.Readiness and type(Dibs.Readiness.Evaluate) == "function" then
      local result = Dibs.Readiness.Evaluate({ allowPlayer = true })
      return "Raid readiness (safe summary): " .. tostring(result and result.status or "Unavailable") ..
        " | Live Dibs consumption: " .. (result and result.liveConsumptionAllowed and "allowed after revalidation" or "blocked or unavailable")
    end
    return "Raid readiness (safe summary): Unavailable"
  end),
  item = { type = "input", name = "Pre-Dib item ID or link", order = 2,
    get = function() return getState().playerItem or "" end,
    set = function(_, value) getState().playerItem = value end },
  submit = execute(3, "I want to DIB this", function()
    local request, reason = Dibs.PlayerUI.SubmitPreDib(getState().playerItem)
    auditAction("predib.submit", "player", getState().playerItem)
    setStatus(request and "Pre-Dib saved." or tostring(reason))
  end),
  request = { type = "select", name = "My active Pre-Dibs", order = 4, width = "double",
    values = function()
      local values = {}
      for _, request in ipairs(Dibs.PlayerUI.GetSummary().activePreDibs or {}) do
        values[request.requestId or request.id] = tostring(request.itemName or request.itemID) .. " | " .. tostring(request.difficulty or "UNKNOWN") .. " | " .. tostring(request.status)
      end
      return values
    end,
    get = function() return getState().playerRequest end,
    set = function(_, value) getState().playerRequest = value end },
  cancel = execute(5, "Cancel selected Pre-Dib", function()
    local request, reason = Dibs.PreDibs.CancelForPlayer(getState().playerRequest, Dibs.GetPlayerName())
    auditAction("predib.cancel", "player", getState().playerRequest)
    setStatus(request and "Pre-Dib cancelled." or tostring(reason))
    getState().playerRequest = nil
  end),
  history = description(6, function()
    return "Use Open history log below."
  end),
  openHistory = execute(7, "Open history log", function() Dibs.LogsUI.OpenPlayerHistory() end),
  openAcquisitions = execute(8, "Open acquisitions log", function() Dibs.LogsUI.OpenPlayerAcquisitions() end),
  reviewRequests = description(9, "Review a Dibs or loot history problem from the Player window."),
  openRequests = execute(10, "Open my review requests", function()
    local frame = Dibs.PlayerUI.CreateWindow()
    if frame and frame.SelectTab then frame.SelectTab("requests") end
    if frame then frame:Show(); frame:Raise() end
  end),
} }
-- Blizzard Settings is a configuration surface. Personal history, reports and
-- searchable data live in the modeless Player window opened below.
for _, key in ipairs({ "summary", "readiness", "item", "submit", "request", "cancel", "history", "openHistory", "openAcquisitions" }) do
  if groups.player.args[key] then groups.player.args[key].hidden = true end
end
groups.player.args.intro = description(1, "Personal balances, history, acquisitions and review requests open in the separate Player window.")
groups.officer = { type = "group", name = function() return Dibs.RCOptions.IsOfficerPreviewOnly() and "Officer *" or "Officer" end, order = 8, args = {
  previewNotice = description(1, function()
    return Dibs.RCOptions.IsOfficerPreviewOnly() and "|cffffcc00* Preview mode|r  Nanarus-Durotan — officer permissions remain enforced." or "|cff66ff99Authorized officer controls|r"
  end),
  openWindow = execute(2, function() return Dibs.RCOptions.IsOfficerPreviewOnly() and "Open officer window *" or "Open officer window" end, function() Dibs.OfficerUI.Toggle(true) end),
  season = groups.seasons.args.selectedSeason,
  -- The season summary is shown once in Overview; Officer starts with controls.
  dashboard = nil,
  openLogs = execute(5, "Open logs window", function()
    Dibs.LogsUI.OpenOfficer("players", getSelectedSeasonId(), "")
  end),
  statistics = description(8, function()
    local stats = Dibs.OfficerUI.BuildSeasonStatistics(getSelectedSeasonId())
    return "Players: " .. stats.players .. " | Transactions: " .. stats.transactions .. " | Dibs used: " .. stats.used .. " | Active Pre-Dibs: " .. stats.activePreDibs
  end),
} }
groups.officer.args.season.order = 3
groups.officer.args.season.width = "full"
groups.officer.args.openWindow.width = "half"
groups.officer.args.openLogs.order = 2
groups.officer.args.openWindow.desc = "Open the complete Officer management window."
groups.officer.args.openLogs.width = "half"
groups.officer.args.openLogs.desc = "Open a separate logs window with Players, Pre-Dibs and History views, search and pagination."
groups.officer.args.disputes = { type = "group", name = "Review Requests", order = 4, args = {
  intro = description(1, "Player reports are private to the owner and guild Officers. Evidence is read-only; every resolution records a reason."),
  open = execute(2, "Open review queue", function()
    local frame = Dibs.OfficerUI.CreateWindow()
    if frame and frame.SelectTab then frame.SelectTab("disputes") end
    if frame and frame.Refresh then frame:Refresh() end
    if frame then frame:Show(); frame:Raise() end
  end),
  counts = description(3, function()
    local counts = Dibs.Disputes and Dibs.Disputes.GetCounts and Dibs.Disputes.GetCounts(nil) or {}
    return "Open: " .. tostring(counts.Open or 0) .. " | Under review: " .. tostring(counts["Under review"] or 0) ..
      " | Need information: " .. tostring(counts["Need information"] or 0) .. " | Closed: " .. tostring((counts.Resolved or 0) + (counts.Rejected or 0))
  end),
} }
groups.officer.args.statistics.hidden = true
groups.officer.args.intro = description(1, "Policies stay in Blizzard Settings. The separate Officer control center owns live searches, review, history reconciliation and statistics.")
groups.officer.args.intro.order = 1.5
groups.officer.args.reconciliation = { type = "group", name = "RC History", order = 4.5, args = {
  intro = description(1, "Preview RCLootCouncil history and reconcile old DIB responses. Scanning is read-only; only a GM or Officer confirmation appends a ledger debit."),
  aliases = { type = "input", name = "Exact DIB response aliases", desc = "Comma-separated aliases. Matching trims whitespace and ignores case; fuzzy matching is never used.", order = 2,
    get = function()
      local seasonId = getSelectedSeasonId()
      return table.concat(Dibs.RCLootCouncil.GetReconciliationAliases(seasonId) or {}, ", ")
    end,
    set = function(_, value)
      local seasonId = getSelectedSeasonId()
      local saved, reason = Dibs.RCLootCouncil.SetReconciliationAliases(seasonId, value, nil)
      setStatus(saved and "History aliases saved." or ("Unable to save history aliases: " .. tostring(reason or "unknown")))
    end,
  },
  open = execute(3, "Open history reconciliation", function()
    local frame = Dibs.OfficerUI.CreateWindow()
    if frame and frame.SelectTab then frame.SelectTab("reconciliation") end
    if frame and frame.Refresh then frame:Refresh() end
    if frame then frame:Show(); frame:Raise() end
  end),
} }
-- Operational queues and reconciliation are rendered by the modeless Officer
-- control center. Keep the option entries as compatibility aliases for code
-- and older profiles, but do not expose their long-running views in Blizzard
-- Settings where they compete with the configuration pages.
groups.officer.args.disputes.hidden = true
groups.officer.args.reconciliation.hidden = true
groups.overview.args.seasonSummary = nil
groups.data = { type = "group", name = "Data", order = 12, args = {
  intro = description(1, "Backups, profiles and portable packages use a preview-first workflow. Imported text is treated as data only and never executed."),
  openBackups = execute(2, "Open backups", function() if Dibs.DataUI then Dibs.DataUI.Open("backups") end end),
  openProfiles = execute(3, "Open profiles", function() if Dibs.DataUI then Dibs.DataUI.Open("profiles") end end),
  openTransfer = execute(4, "Open import / export", function() if Dibs.DataUI then Dibs.DataUI.Open("transfer") end end),
  retention = { type = "range", name = "Safety backup retention", min = 1, max = 25, step = 1, order = 5,
    get = function() return tonumber(Dibs.GetDB().backupRetention or 5) end,
    set = function(_, value) local saved, reason = Dibs.Backup.SetRetention(value); setStatus(saved and ("Backup retention: " .. tostring(saved)) or tostring(reason)) end },
} }
groups.developer = { type = "group", name = "Developer", order = 9, args = {
  enabled = { type = "toggle", name = "Developer Mode", order = 1,
    get = function() return Dibs.DeveloperMode.IsEnabled() end,
    set = function(_, value) Dibs.DeveloperMode.SetEnabled(value) end },
  item = { type = "input", name = "Test item ID or link", order = 2,
    get = function() return getState().testItem or "" end,
    set = function(_, value) getState().testItem = value end },
  inject = execute(3, "Inject test item", function() Dibs.DeveloperMode.HandleTestItemSlash(getState().testItem) end),
  request = execute(4, "Request Dib (DEV)", function()
    local context = Dibs.LootPipeline.GetPendingDevContext()
    if not Dibs.DeveloperMode.IsEnabled() or not context then setStatus("Enable Developer Mode and inject a test item first."); return end
    local request, reason = Dibs.LootPipeline.RequestDibFromContext(context)
    setStatus(request and "Test request created." or tostring(reason))
  end),
} }
groups.integration = { type = "group", name = "RCLootCouncil", order = 10, args = {
  status = description(0, integrationStatusText),
  setup = { type = "group", name = "Installation assistant", order = 0, inline = true, args = {
    intro = description(1, "Choose a starting policy for your guild. The assistant configures Dibs semantic loot families and prepares the locked Dibs button in RCLootCouncil sets that are already enabled."),
    status = description(2, buildSetupAssistantStatus),
    progression = execute(3, "Recommended: Curio + Tier Set", function() applyInstallationPreset("progression") end),
    standard = execute(4, "Standard loot + collections", function() applyInstallationPreset("broad") end),
    refresh = execute(5, "Refresh Dibs buttons", function()
      local integration = Dibs.RCLootCouncil
      if integration and type(integration.RefreshConfigProjection) == "function" then
        local available, changed = integration.RefreshConfigProjection()
        setStatus(available and (changed == true and "Dibs buttons refreshed in RCLootCouncil." or "Dibs buttons were already ready.") or "RCLootCouncil is unavailable; standalone Dibs controls remain active.")
      else
        setStatus("RCLootCouncil integration is unavailable; standalone Dibs controls remain active.")
      end
    end),
  } },
  mapping = { type = "group", name = "RCLootCouncil button-set mapping", order = 1, inline = true, args = {
    guide = description(1, buildButtonSetMappingText),
    configured = description(2, buildConfiguredButtonSetsText),
  } },
  types = { type = "multiselect", name = "Dib semantic loot types", order = 2, width = "full",
    values = getDibTypeValues,
    get = function(_, key)
      local semanticKey = canonicalSemanticTypeKey(key)
      if semanticKey == nil then return false end
      local settings = getDibTypeSettings()
      if settings[key] ~= nil then return settings[key] ~= false end
      if settings[semanticKey] ~= nil then return settings[semanticKey] ~= false end
      if Dibs.RCLootCouncil and Dibs.RCLootCouncil.IsDibEnabledForType then
        return Dibs.RCLootCouncil.IsDibEnabledForType(semanticKey) == true
      end
      return true
    end,
    set = function(_, key, value) setDibTypeEnabled(key, value) end },
  templates = { type = "group", name = "Recommended semantic templates", order = 3, inline = true, args = {
    templateHelp = description(1, "Templates set Dibs semantic families only. The Installation assistant also refreshes the locked Dibs button projection."),
    progression = execute(2, "Curio + Tier Set", function() applyDibSemanticTemplate("progression") end),
    broad = execute(3, "Standard loot", function() applyDibSemanticTemplate("broad") end),
  } },
  readiness = { type = "group", name = "Raid Readiness & Dry-Run", order = 3.5, inline = true, args = {
    intro = description(1, "Run a read-only readiness check before raid. The dry-run uses local validation only and never calls RCMLAwardSuccess, FinalizeAward, loot controls, chat traffic, or ledger accounting."),
    status = description(2, function()
      if Dibs.Readiness and Dibs.Readiness.GetStatusText then
        return Dibs.Readiness.GetStatusText(true)
      end
      return "Raid readiness is unavailable."
    end),
    check = execute(3, "Run readiness check", function()
      local result, reason = Dibs.Readiness and Dibs.Readiness.Run and Dibs.Readiness.Run() or nil, "UNAVAILABLE"
      setStatus(result and ("Readiness: " .. tostring(result.status)) or ("Readiness unavailable: " .. tostring(reason)))
    end),
    safeReport = execute(4, "Open selectable safe report", function()
      local shell, report, reason
      if Dibs.Readiness and Dibs.Readiness.OpenReport then
        shell, report, reason = Dibs.Readiness.OpenReport("safe")
      else
        reason = "UNAVAILABLE"
      end
      setStatus(shell and "Safe readiness report opened." or (report and "Safe readiness report opened in chat fallback." or ("Report unavailable: " .. tostring(reason))))
    end),
    dryRunItem = { type = "input", name = "Dry-run item ID or link", order = 5,
      get = function() return getState().dryRunItem or "19019" end,
      set = function(_, value) getState().dryRunItem = trimText(value) end },
    dryRunWinner = { type = "input", name = "Dry-run winner", order = 6,
      get = function() return getState().dryRunWinner or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "") end,
      set = function(_, value) getState().dryRunWinner = trimText(value) end },
    dryRunResponse = { type = "input", name = "Dry-run response", order = 7,
      get = function() return getState().dryRunResponse or "DIB" end,
      set = function(_, value) getState().dryRunResponse = trimText(value) end },
    dryRunStatus = { type = "select", name = "Dry-run finalization status", order = 8,
      values = { finalized = "Finalized", awarded = "Awarded", pending = "Pending", test_mode = "Test mode" },
      get = function() return getState().dryRunStatus or "finalized" end,
      set = function(_, value) getState().dryRunStatus = value end },
    dryRunSession = { type = "input", name = "Dry-run session identity", order = 9,
      get = function() return getState().dryRunSession or "dry-run-session" end,
      set = function(_, value) getState().dryRunSession = trimText(value) end },
    runDryRun = execute(10, "Run local dry-run", function()
      local state = getState()
      local result, reason = Dibs.DryRun and Dibs.DryRun.Run and Dibs.DryRun.Run({
        item = state.dryRunItem or "19019",
        winner = state.dryRunWinner or (Dibs.GetPlayerName and Dibs.GetPlayerName() or ""),
        response = state.dryRunResponse or "DIB",
        status = state.dryRunStatus or "finalized",
        sessionIdentity = state.dryRunSession or "dry-run-session",
      }) or nil, "UNAVAILABLE"
      if result then
        state.lastDryRun = result
        local last = Dibs.Readiness and Dibs.Readiness.GetLast and Dibs.Readiness.GetLast()
        if last then
          last.lastDryRunOutcome = result.outcome
          last.simulationCount = (tonumber(last.simulationCount) or 0) + 1
        end
        setStatus(Dibs.DryRun.Format(result))
      else
        setStatus("Dry-run unavailable: " .. tostring(reason))
      end
    end),
    dryRunResult = description(11, function()
      local result = getState().lastDryRun
      return result and Dibs.DryRun.Format(result) or "No dry-run has been executed in this session."
    end),
  } },
  enable = execute(4, "Enable all loot types", function() applyDibTypePreset(true) end),
  disable = execute(5, "Default loot type only", function() applyDibTypePreset(false) end),
} }
groups.debug = { type = "group", name = "Debug", order = 11, args = {
  intro = description(1, "Levels: 0 hides a module, 1 normal, 5 maximum diagnostics. Changes apply immediately."),
  all = { type = "range", name = "All modules", min = 0, max = 5, step = 1, order = 2,
    get = function() return tonumber(Dibs.GetDebugLevels().all) or 1 end,
    set = function(_, value) Dibs.SetDebugLevel("all", value) end },
  announce = { type = "range", name = "Announcements", min = 0, max = 5, step = 1, order = 3,
    get = function() return tonumber(Dibs.GetDebugLevels().announce) or tonumber(Dibs.GetDebugLevels().all) or 1 end,
    set = function(_, value) Dibs.SetDebugLevel("announce", value) end },
  sync = { type = "range", name = "Sync", min = 0, max = 5, step = 1, order = 4,
    get = function() return tonumber(Dibs.GetDebugLevels().sync) or tonumber(Dibs.GetDebugLevels().all) or 1 end,
    set = function(_, value) Dibs.SetDebugLevel("sync", value) end },
  ui = { type = "range", name = "UI", min = 0, max = 5, step = 1, order = 5,
    get = function() return tonumber(Dibs.GetDebugLevels().ui) or tonumber(Dibs.GetDebugLevels().all) or 1 end,
    set = function(_, value) Dibs.SetDebugLevel("ui", value) end },
  encounterJournal = { type = "range", name = "Adventure Guide tooltip", min = 0, max = 5, step = 1, order = 6,
    get = function() return tonumber(Dibs.GetDebugLevels().encounter_journal) or tonumber(Dibs.GetDebugLevels().all) or 1 end,
    set = function(_, value) Dibs.SetDebugLevel("encounter_journal", value) end },
} }
groups.debug.args.openLogs = execute(7, "Open debug logs", function() Dibs.DebugLogs.Open() end)

-- Main navigation is intentionally split into Player and Officer tabs. Officer
-- owns the administrative sub-sections; Player only exposes personal actions.
groups.player.childGroups = "tree"
groups.player.args.openWindow = execute(2, "Open player window", function() Dibs.PlayerUI.Toggle(true) end)
groups.player.args.reviewRequests.order = 3
groups.player.args.openRequests.order = 4
-- Player keeps personal request actions below; the Pre-Dibs policy group is Officer-only.
groups.player.args.preDibs = nil
groups.officer.childGroups = "tree"
local function nestedGroup(group)
  local copy = {}
  for key, value in pairs(group) do copy[key] = value end
  copy.hidden = nil
  return copy
end
for _, key in ipairs({ "seasons", "ranks", "settings", "preDibs", "announcements", "developer", "integration", "debug" }) do
  if groups[key] then groups.officer.args[key] = nestedGroup(groups[key]) end
end
local officerSeasons = groups.officer.args.seasons
if officerSeasons and officerSeasons.args then
  officerSeasons.childGroups = "tree"
  officerSeasons.args.selectedSeason.order = 1
  officerSeasons.args.selectedSeason.width = "full"
  officerSeasons.args.activateSeason.order = 2
  officerSeasons.args.activateSeason.width = "full"
  officerSeasons.args.createSeasonName.order = 3
  officerSeasons.args.createSeasonName.width = "full"
  officerSeasons.args.createSeason.order = 4
  officerSeasons.args.createSeason.width = "full"
  officerSeasons.args.renameSeasonName.order = 5
  officerSeasons.args.renameSeasonName.width = "full"
  officerSeasons.args.renameSeason.order = 6
  officerSeasons.args.renameSeason.width = "half"
  officerSeasons.args.archiveSeason.order = 7
  officerSeasons.args.archiveSeason.width = "half"
end
local officerRanks = groups.officer.args.ranks
if officerRanks and officerRanks.args then
  for _, key in ipairs({ "rankSummary", "rankIndex", "rankAllocation", "applyRank" }) do
    if officerRanks.args[key] then officerRanks.args[key].hidden = function() return true end end
  end
  officerRanks.args.rows = { type = "group", name = "", order = 1, inline = true, childGroups = "tree", args = {} }
  local rowArgs = officerRanks.args.rows.args
  for rankIndex = 0, 9 do
    local key = "rank" .. tostring(rankIndex)
    rowArgs[key] = { type = "group", name = function() return "Rank " .. tostring(rankIndex) .. " — " .. tostring(getGuildRankNames()[rankIndex] or "Rank " .. tostring(rankIndex)) end, order = rankIndex + 1, inline = true, args = {
      allocation = { type = "range", name = "Dibs", min = 0, max = 20, step = 1, width = "double",
        get = function() return getRankAllocationForSeason(getSelectedSeasonId(), rankIndex) end,
        set = function(_, value)
          local result = Dibs.ProtectedActions.Execute("rank.set", nil, { seasonId = getSelectedSeasonId(), rankIndex = rankIndex, rankName = getGuildRankNames()[rankIndex] or ("Rank " .. tostring(rankIndex)), allocation = tonumber(value) or 0 })
          setStatus(result.ok and "Rank rule saved." or result.diagnostic)
        end },
    } }
  end
  rowArgs.addRank = { type = "description", name = "Use guild rank data to add additional ranks.", order = 11, width = "full" }
end
-- Prevent administrative sections from appearing as duplicate top-level tabs.
for _, key in ipairs({ "seasons", "ranks", "settings", "preDibs", "announcements", "developer", "integration", "debug" }) do
  if groups[key] then groups[key].hidden = function() return true end end
end
groups.officer.hidden = officerOnly
groups.overview.hidden = nil
groups.player.hidden = nil

function Dibs.RCOptions.GetLootTypeOptions()
  return groups.integration.args
end

function Dibs.RCOptions.GetOptionsTable()
  return optionsTable
end

function Dibs.RCOptions.Open()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    Dibs.RCOptions.pendingOpen = true
    return false
  end
  Dibs.RCOptions.pendingOpen = nil
  local ace3 = Dibs.Ace3
  if not ace3 or not ace3.RegisterOptionsTable(OPTIONS_APP_NAME, optionsTable) then return false end
  local addon = getRCAddon()
  local panel = addon and addon.optionsFrame and addon.optionsFrame.dibs
  if panel and _G.Settings and type(_G.Settings.OpenToCategory) == "function" then
    _G.Settings.OpenToCategory(Dibs.RCOptions.categoryId or panel.name or OPTIONS_DISPLAY_NAME)
    return true
  end
  local dialog = ace3.libs and ace3.libs.dialog
  if dialog and type(dialog.Open) == "function" then dialog:Open(OPTIONS_APP_NAME); return true end
  return false
end

local function reorderCategoryBeforeMaster()
  -- Retail's Settings API owns the category/subcategory tree.  Mutating the
  -- legacy Interface Options array after a canvas subcategory is registered
  -- can leave the selected panel and its AceConfig tab state out of sync (the
  -- Master Looter tabs then appear clickable but immediately return to the
  -- first page).  Let Settings keep its native ordering on modern clients.
  local settings = _G.Settings
  if type(settings) == "table"
    and type(settings.GetCategory) == "function"
    and type(settings.RegisterCanvasLayoutSubcategory) == "function"
  then
    return
  end

  local categories = _G.INTERFACEOPTIONS_ADDONCATEGORIES
  if type(categories) ~= "table" then
    return
  end

  local dibsIndex, dibsCategory = nil, nil
  local mlIndex = nil
  for i, category in ipairs(categories) do
    if category and category.parent == "RCLootCouncil" then
      if category.name == OPTIONS_DISPLAY_NAME then
        dibsIndex = i
        dibsCategory = category
      elseif category.name == "Master Looter" then
        mlIndex = i
      end
    end
  end

  if dibsIndex and dibsCategory and mlIndex and dibsIndex > mlIndex then
    table.remove(categories, dibsIndex)
    table.insert(categories, mlIndex, dibsCategory)
  end
end

local function registerOptions()
  if Dibs.RCOptions.registered then
    return true
  end

  local addon = getRCAddon()
  if type(addon) ~= "table" then
    debugMessage("RCLootCouncil addon handle not available yet.")
    return false
  end

  if not addon.optionsFrame then
    debugMessage("RCLootCouncil optionsFrame not ready yet.")
    return false
  end

  local ace3 = Dibs.Ace3
  if not ace3 or not ace3.RegisterOptionsTable or not ace3.AddToBlizOptions then
    debugMessage("AceConfig libs unavailable for RC options attach.")
    return false
  end

  local okRegister, registerErr = ace3.RegisterOptionsTable(OPTIONS_APP_NAME, optionsTable)
  if not okRegister and not tostring(registerErr):find("already registered", 1, true) then
    debugMessage("RegisterOptionsTable failed: " .. tostring(registerErr))
    return false
  end

  if addon.optionsFrame.dibs then
    Dibs.RCOptions.registered = true
    debugMessage("Dibs already attached under RCLootCouncil.")
    return true
  end

  local okAttach, attachedFrameOrErr, categoryId = ace3.AddToBlizOptions(OPTIONS_APP_NAME, OPTIONS_DISPLAY_NAME, "RCLootCouncil", "dibsSettings")
  if not okAttach then
    local err = tostring(attachedFrameOrErr)
    if not err:find("already been added", 1, true) then
      debugMessage("AddToBlizOptions failed: " .. err)
      return false
    end
  else
    addon.optionsFrame.dibs = attachedFrameOrErr
    Dibs.RCOptions.categoryId = categoryId
  end

  reorderCategoryBeforeMaster()
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0.2, reorderCategoryBeforeMaster)
    C_Timer.After(1.0, reorderCategoryBeforeMaster)
  end

  Dibs.RCOptions.registered = true
  debugMessage("Dibs options attached to RCLootCouncil.")
  return true
end

function Dibs.RCOptions.EnsureRegistered(maxAttempts)
  if Dibs.RCOptions.registered then
    return true
  end
  if registerOptions() then return true end

  local timerApi = type(C_Timer) == "table" and C_Timer or nil
  if not timerApi or type(timerApi.After) ~= "function" then
    debugMessage("C_Timer unavailable; cannot retry RC options attach.")
    return false
  end

  if Dibs.RCOptions.retryActive then
    return false
  end

  local attempts = tonumber(maxAttempts) or DEFAULT_MAX_ATTEMPTS
  Dibs.RCOptions.retryActive = true

  local function retry(step)
    if registerOptions() then
      Dibs.RCOptions.retryActive = false
      return
    end
    if step >= attempts then
      Dibs.RCOptions.retryActive = false
      debugMessage("Dibs options could not attach to RCLootCouncil yet.")
      return
    end
    timerApi.After(0.5, function()
      retry(step + 1)
    end)
  end

  retry(0)
  return false
end

local bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
bootstrapFrame:SetScript("OnEvent", function(_, event, loadedAddon)
  if event == "PLAYER_REGEN_ENABLED" then
    if Dibs.RCOptions.pendingOpen then
      Dibs.RCOptions.pendingOpen = nil
      Dibs.RCOptions.Open()
    end
    return
  end
  if event == "ADDON_LOADED" then
    local dibsName = Dibs and Dibs.ADDON_NAME or "RCLootCouncil_dibs"
    if loadedAddon ~= "RCLootCouncil" and loadedAddon ~= dibsName and loadedAddon ~= "RCLootCouncil_dibs" then
      return
    end
  end

  Dibs.RCOptions.EnsureRegistered(DEFAULT_MAX_ATTEMPTS)
end)
