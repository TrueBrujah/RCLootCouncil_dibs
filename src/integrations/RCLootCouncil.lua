local Dibs = _G.Dibs
Dibs.RCLootCouncil = Dibs.RCLootCouncil or {}

local function text(key, fallback) return (Dibs.L and Dibs.L[key]) or fallback end

local function getRCAddon()
  if LibStub == nil then return nil end
  local aceAddon = LibStub("AceAddon-3.0", true)
  if not aceAddon or type(aceAddon.GetAddon) ~= "function" then return nil end
  return aceAddon:GetAddon("RCLootCouncil", true)
end

local function isLoaded()
  if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
    local first, second = C_AddOns.IsAddOnLoaded("RCLootCouncil")
    return second == true or first == true
  end
  return type(_G.RCLootCouncil) == "table" or type(getRCAddon()) == "table"
end

local function getRC()
  return getRCAddon() or _G.RCLootCouncil
end

local function normalizeButtonLabel(value)
  return string.upper(tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeTypeKey(value)
  local text = tostring(value or "default")
  if text == "" then
    text = "default"
  end
  return text
end

local function getDibTypeSettings()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.settings = db.settings or {}
  db.settings.dibAllowedTypes = db.settings.dibAllowedTypes or {}
  return db.settings.dibAllowedTypes
end

local typeAllowanceCache = {}
local TYPE_ALLOWANCE_CACHE_TTL = 300
local typePolicyRevision = 1

local function nowSeconds()
  if type(GetTime) == "function" then
    return tonumber(GetTime()) or 0
  end
  return tonumber(time and time() or 0) or 0
end

function Dibs.RCLootCouncil.IsDibEnabledForType(responseType)
  local key = normalizeTypeKey(responseType)
  local rules = getDibTypeSettings()
  local value = rules[key]
  if value == nil then
    return true
  end
  return value == true
end

function Dibs.RCLootCouncil.SetDibEnabledForType(responseType, enabled, actor)
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local key = normalizeTypeKey(responseType)
  local rules = getDibTypeSettings()
  rules[key] = enabled == true
  typePolicyRevision = typePolicyRevision + 1
  typeAllowanceCache = {}
  return true
end

function Dibs.RCLootCouncil.GetTypePolicyRevision()
  return typePolicyRevision
end

local function addTypeCandidate(target, seen, value)
  if value == nil then return end
  local text = tostring(value)
  if text == "" then return end
  if seen[text] then return end
  seen[text] = true
  table.insert(target, text)
end

local function normalizeKey(value)
  return string.lower(tostring(value or ""))
end

local function canonicalPolicyKey(value)
  local key = string.upper(tostring(value or ""))
  key = key:gsub("[%s%-]", "_")
  if key == "MOUNT" or key == "MOUNTS" then
    return "MOUNTS"
  end
  if key == "PET" or key == "PETS" then
    return "PETS"
  end
  if key == "RECIPE" or key == "RECIPES" then
    return "RECIPE"
  end
  if key == "DECOR" or key == "DECORS" then
    return "DECOR"
  end
  if key == "TOKEN" or key == "TOKENS" then
    return "TOKEN"
  end
  if key == "CATALYSTS" then
    return "CATALYST"
  end
  if key == "OTHER" or key == "OTHERS" then
    return "OTHER"
  end
  return key
end

local function hasConfiguredTypePolicy(rules)
  for key, value in pairs(rules or {}) do
    if key ~= nil and value ~= nil then
      return true
    end
  end
  return false
end

local function readRuleValueCaseInsensitive(rules, key)
  if type(rules) ~= "table" then return nil end
  local canonicalNeedle = canonicalPolicyKey(key)
  if rules[key] ~= nil then return rules[key] end
  if rules[canonicalNeedle] ~= nil then return rules[canonicalNeedle] end

  local needle = normalizeKey(canonicalNeedle)
  for existingKey, value in pairs(rules) do
    if normalizeKey(canonicalPolicyKey(existingKey)) == needle then
      return value
    end
  end
  return nil
end

local function collectItemTypeCandidates(itemID, responseType)
  local values = {}
  local seen = {}

  local function addFromTooltip(id)
    if not tonumber(id) or type(C_TooltipInfo) ~= "table" then return end
    local info = nil
    if type(C_TooltipInfo.GetHyperlink) == "function" then
      local ok, value = pcall(C_TooltipInfo.GetHyperlink, string.format("item:%d", tonumber(id)))
      if ok and type(value) == "table" then
        info = value
      end
    end
    if info == nil and type(C_TooltipInfo.GetItemByID) == "function" then
      local ok, value = pcall(C_TooltipInfo.GetItemByID, tonumber(id))
      if ok and type(value) == "table" then
        info = value
      end
    end
    local lines = info and info.lines
    if type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
      local left = string.lower(tostring(line and (line.leftText or line.text or "") or ""))
      if left ~= "" then
        if left:find("housing decor", 1, true)
          or left:find("furnishing", 1, true)
          or left:find("decoration", 1, true)
        then
          addTypeCandidate(values, seen, "DECOR")
        end
        if left:find("pattern:", 1, true)
          or left:find("recipe:", 1, true)
          or left:find("plans:", 1, true)
          or left:find("formula:", 1, true)
          or left:find("schematic:", 1, true)
        then
          addTypeCandidate(values, seen, "RECIPE")
        end
        if left:find("soulbound set item appropriate for your class", 1, true)
          or left:find("create a soulbound set", 1, true)
          or left:find("armor token", 1, true)
          or left:find("classes:", 1, true)
        then
          addTypeCandidate(values, seen, "TOKEN")
          addTypeCandidate(values, seen, "CATALYST")
        end
        if left:find("summon and dismiss this companion", 1, true)
          or left:find("teach.*companion")
          or left:find("mount", 1, true)
        then
          addTypeCandidate(values, seen, "MOUNTS")
        end
        if left:find("battle pet", 1, true)
          or left:find("pet", 1, true)
        then
          addTypeCandidate(values, seen, "PETS")
        end
      end
    end
  end

  addTypeCandidate(values, seen, responseType)
  if type(responseType) == "string" then
    addTypeCandidate(values, seen, string.upper(responseType))
    addTypeCandidate(values, seen, string.lower(responseType))
  end

  local targetItem = tonumber(itemID)
  if targetItem and type(GetItemInfoInstant) == "function" then
    local _, itemClassName, itemSubClassName, equipLoc, _, classID, subClassID = GetItemInfoInstant(targetItem)
    addTypeCandidate(values, seen, equipLoc)
    addTypeCandidate(values, seen, itemClassName)
    addTypeCandidate(values, seen, itemSubClassName)
    addTypeCandidate(values, seen, classID and ("CLASS_" .. tostring(classID)) or nil)
    addTypeCandidate(values, seen, subClassID and ("SUBCLASS_" .. tostring(subClassID)) or nil)

    if tonumber(classID) == 9 then
      addTypeCandidate(values, seen, "RECIPE")
      addTypeCandidate(values, seen, "Recipe")
      addTypeCandidate(values, seen, "recipe")
      addTypeCandidate(values, seen, "RECETTE")
      addTypeCandidate(values, seen, "Recette")
      addTypeCandidate(values, seen, "recette")
    end

    if tonumber(classID) == 15 then
      addTypeCandidate(values, seen, "MOUNT")
      addTypeCandidate(values, seen, "MOUNTS")
      addTypeCandidate(values, seen, "Mount")
      addTypeCandidate(values, seen, "Mounts")
      addTypeCandidate(values, seen, "mount")
      addTypeCandidate(values, seen, "mounts")
      addTypeCandidate(values, seen, "MONTURE")
      addTypeCandidate(values, seen, "Monture")
      addTypeCandidate(values, seen, "monture")
    end

    if tonumber(classID) == 17 then
      addTypeCandidate(values, seen, "PET")
      addTypeCandidate(values, seen, "PETS")
      addTypeCandidate(values, seen, "Pet")
      addTypeCandidate(values, seen, "Pets")
      addTypeCandidate(values, seen, "pet")
      addTypeCandidate(values, seen, "pets")
      addTypeCandidate(values, seen, "FAMILIER")
      addTypeCandidate(values, seen, "FAMILIERS")
      addTypeCandidate(values, seen, "familier")
      addTypeCandidate(values, seen, "familiers")
    end

    local classLower = string.lower(tostring(itemClassName or ""))
    local subclassLower = string.lower(tostring(itemSubClassName or ""))
    if classLower:find("decor", 1, true)
      or subclassLower:find("decor", 1, true)
      or classLower:find("cosmetic", 1, true)
      or subclassLower:find("cosmetic", 1, true)
      or classLower:find("housing", 1, true)
      or subclassLower:find("housing", 1, true)
    then
      addTypeCandidate(values, seen, "DECOR")
      addTypeCandidate(values, seen, "Decor")
      addTypeCandidate(values, seen, "decor")
    end
    if classLower:find("mount", 1, true) or subclassLower:find("mount", 1, true) then
      addTypeCandidate(values, seen, "MOUNTS")
    end
    if classLower:find("pet", 1, true) or subclassLower:find("pet", 1, true) then
      addTypeCandidate(values, seen, "PETS")
    end
  end

  if targetItem and type(C_MountJournal) == "table" and type(C_MountJournal.GetMountFromItem) == "function" then
    local ok, mountID = pcall(C_MountJournal.GetMountFromItem, targetItem)
    if ok and tonumber(mountID) and tonumber(mountID) > 0 then
      addTypeCandidate(values, seen, "MOUNT")
      addTypeCandidate(values, seen, "MOUNTS")
      addTypeCandidate(values, seen, "Mount")
      addTypeCandidate(values, seen, "Mounts")
      addTypeCandidate(values, seen, "mount")
      addTypeCandidate(values, seen, "mounts")
    end
  end

  addFromTooltip(targetItem)

  addTypeCandidate(values, seen, "default")
  return values
end

local PRIORITY_CATEGORY_KEYS = {
  MOUNTS = true,
  PETS = true,
  DECOR = true,
  TOKEN = true,
  CATALYST = true,
  RECIPE = true,
  OTHER = true,
}

local PRIORITY_CATEGORY_ORDER = {
  "MOUNTS",
  "PETS",
  "TOKEN",
  "CATALYST",
  "RECIPE",
  "DECOR",
  "OTHER",
}

local function resolvePriorityCategoryRule(rules, candidates)
  local present = {}
  for _, candidate in ipairs(candidates or {}) do
    local canonical = canonicalPolicyKey(candidate)
    if PRIORITY_CATEGORY_KEYS[canonical] then
      present[canonical] = true
    end
  end

  for _, category in ipairs(PRIORITY_CATEGORY_ORDER) do
    if present[category] then
      local value = readRuleValueCaseInsensitive(rules, category)
      if value ~= nil then
        return value == true, true
      end
    end
  end
  return nil, false
end

function Dibs.RCLootCouncil.IsItemDibTypeAllowed(itemID, responseType, options)
  options = type(options) == "table" and options or {}
  local strictWhitelist = options.strictWhitelist == true
  local cacheKey = tostring(itemID or "0") .. "|" .. tostring(responseType or "default") .. "|" .. tostring(strictWhitelist) .. "|" .. tostring(typePolicyRevision)
  local now = nowSeconds()
  local cached = typeAllowanceCache[cacheKey]
  if cached and (now - (cached.at or 0)) <= TYPE_ALLOWANCE_CACHE_TTL then
    return cached.value == true
  end

  local candidates = collectItemTypeCandidates(itemID, responseType)
  local rules = getDibTypeSettings()
  local policyConfigured = hasConfiguredTypePolicy(rules)

  local priorityDecision, hasPriorityRule = resolvePriorityCategoryRule(rules, candidates)
  if hasPriorityRule then
    typeAllowanceCache[cacheKey] = { value = priorityDecision == true, at = now }
    return priorityDecision == true
  end

  if strictWhitelist and not policyConfigured then
    typeAllowanceCache[cacheKey] = { value = true, at = now }
    return true
  end

  local explicitTrue = false
  local explicitFalse = false

  for _, key in ipairs(candidates) do
    if strictWhitelist and normalizeKey(key) == "default" then
      -- In strict mode, unknown items should not be allowed by default fallback.
    else
      local value = readRuleValueCaseInsensitive(rules, key)
      if value ~= nil then
        if value == true then
          explicitTrue = true
        else
          explicitFalse = true
        end
      end
    end
  end

  if explicitTrue then
    typeAllowanceCache[cacheKey] = { value = true, at = now }
    return true
  end
  if explicitFalse then
    typeAllowanceCache[cacheKey] = { value = false, at = now }
    return false
  end

  if strictWhitelist then
    typeAllowanceCache[cacheKey] = { value = false, at = now }
    return false
  end

  local hasExplicitRule = false
  for _, key in ipairs(candidates) do
    if readRuleValueCaseInsensitive(rules, key) ~= nil then
      hasExplicitRule = true
      if readRuleValueCaseInsensitive(rules, key) == true then
        typeAllowanceCache[cacheKey] = { value = true, at = now }
        return true
      end
    end
  end

  if hasExplicitRule then
    typeAllowanceCache[cacheKey] = { value = false, at = now }
    return false
  end

  for _, key in ipairs(candidates) do
    if Dibs.RCLootCouncil.IsDibEnabledForType(key) then
      typeAllowanceCache[cacheKey] = { value = true, at = now }
      return true
    end
  end

  local fallback = Dibs.RCLootCouncil.IsDibEnabledForType("default")
  typeAllowanceCache[cacheKey] = { value = fallback == true, at = now }
  return fallback
end

local FORCED_DIB_BUTTON_INDEX = 1
local FORCED_DIB_TEXT = "Dib"
local FORCED_DIB_WHISPER_KEY = "dib"
local FORCED_DIB_COLOR = { 0.15, 0.85, 1, 1 }
local FORCED_DIB_SORT = 1

local function getRCMLModule(rc)
  if type(rc) ~= "table" or type(rc.GetModule) ~= "function" then return nil end
  local ok, ml = pcall(rc.GetModule, rc, "RCLootCouncilML", true)
  if ok and type(ml) == "table" then
    return ml
  end
  return nil
end

local function collectRCDBs(rc)
  local list = {}
  local seen = {}

  local function add(candidate)
    if type(candidate) ~= "table" then return end
    if seen[candidate] then return end
    seen[candidate] = true
    table.insert(list, candidate)
  end

  local ml = getRCMLModule(rc)
  if ml and type(ml.db) == "table" and type(ml.db.profile) == "table" then
    add(ml.db.profile)
  end

  if type(rc) == "table" and type(rc.Getdb) == "function" then
    local ok, db = pcall(rc.Getdb, rc)
    if ok and type(db) == "table" then add(db) end
  end

  if type(rc) == "table" and type(rc.mldb) == "table" then
    add(rc.mldb)
  end

  if type(rc) == "table" and type(rc.db) == "table" and type(rc.db.profile) == "table" then
    add(rc.db.profile)
  end

  return list
end

local function collectRCOptionTables(rc)
  local list = {}
  local seen = {}
  local function add(candidate)
    if type(candidate) ~= "table" then return end
    if seen[candidate] then return end
    seen[candidate] = true
    table.insert(list, candidate)
  end

  if type(rc) == "table" and type(rc.options) == "table" then
    add(rc.options)
  end
  local ml = getRCMLModule(rc)
  if ml and type(ml.options) == "table" then
    add(ml.options)
  end
  return list
end

local function sameColor(color)
  return type(color) == "table"
    and tonumber(color[1]) == FORCED_DIB_COLOR[1]
    and tonumber(color[2]) == FORCED_DIB_COLOR[2]
    and tonumber(color[3]) == FORCED_DIB_COLOR[3]
    and tonumber(color[4]) == FORCED_DIB_COLOR[4]
end

local function isDibLabel(value)
  local label = normalizeButtonLabel(value)
  return label == "DIB" or label == "DIBS"
end

function Dibs.RCLootCouncil.IsDibResponse(value)
  return isDibLabel(value)
end

local function removeArrayIndex(list, index)
  if type(list) ~= "table" or type(index) ~= "number" then return end
  for i = index, #list - 1 do
    list[i] = list[i + 1]
  end
  list[#list] = nil
end

local function insertAtFront(list, value)
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do
    list[i + 1] = list[i]
  end
  list[1] = value
end

local function findDibButtonIndex(buttons)
  if type(buttons) ~= "table" then return nil end
  for index = 1, #buttons do
    local button = buttons[index]
    if type(button) == "table" and (button.dibsLocked == true or isDibLabel(button.text)) then
      return index
    end
  end
  return nil
end

local function findDibResponseIndex(responses)
  if type(responses) ~= "table" then return nil end
  for index = 1, #responses do
    local response = responses[index]
    if type(response) == "table" and isDibLabel(response.text) then
      return index
    end
  end
  return nil
end

local function ensureForcedDibForSet(buttons, responses)
  if type(buttons) ~= "table" or type(responses) ~= "table" then return false end
  local changed = false

  local existingButtonIndex = findDibButtonIndex(buttons)
  if existingButtonIndex and existingButtonIndex ~= FORCED_DIB_BUTTON_INDEX then
    local existing = buttons[existingButtonIndex]
    removeArrayIndex(buttons, existingButtonIndex)
    insertAtFront(buttons, existing)
    changed = true
  end

  local existingResponseIndex = findDibResponseIndex(responses)
  if existingResponseIndex and existingResponseIndex ~= FORCED_DIB_BUTTON_INDEX then
    local existing = responses[existingResponseIndex]
    removeArrayIndex(responses, existingResponseIndex)
    insertAtFront(responses, existing)
    changed = true
  end

  local button = buttons[FORCED_DIB_BUTTON_INDEX]
  if type(button) ~= "table" then
    button = {}
    insertAtFront(buttons, button)
    changed = true
  end
  if button.text ~= FORCED_DIB_TEXT then
    button.text = FORCED_DIB_TEXT
    changed = true
  end
  if button.whisperKey ~= FORCED_DIB_WHISPER_KEY then
    button.whisperKey = FORCED_DIB_WHISPER_KEY
    changed = true
  end
  if button.requireNotes ~= false then
    button.requireNotes = false
    changed = true
  end
  if button.dibsLocked ~= true then
    button.dibsLocked = true
    changed = true
  end

  local response = responses[FORCED_DIB_BUTTON_INDEX]
  if type(response) ~= "table" then
    response = {}
    insertAtFront(responses, response)
    changed = true
  end
  if response.text ~= FORCED_DIB_TEXT then
    response.text = FORCED_DIB_TEXT
    changed = true
  end
  if not sameColor(response.color) then
    response.color = { FORCED_DIB_COLOR[1], FORCED_DIB_COLOR[2], FORCED_DIB_COLOR[3], FORCED_DIB_COLOR[4] }
    changed = true
  end
  if tonumber(response.sort) ~= FORCED_DIB_SORT then
    response.sort = FORCED_DIB_SORT
    changed = true
  end

  if type(responses.DIB) ~= "table" then
    responses.DIB = {
      text = FORCED_DIB_TEXT,
      color = { FORCED_DIB_COLOR[1], FORCED_DIB_COLOR[2], FORCED_DIB_COLOR[3], FORCED_DIB_COLOR[4] },
      sort = FORCED_DIB_SORT,
    }
    changed = true
  end

  local buttonCount = tonumber(buttons.numButtons) or 0
  if buttonCount < FORCED_DIB_BUTTON_INDEX then
    buttons.numButtons = FORCED_DIB_BUTTON_INDEX
    changed = true
  end

  return changed
end

local function ensureForcedDibConfigForDB(db)
  if type(db) ~= "table" then return false end

  db.buttons = db.buttons or {}
  db.responses = db.responses or {}
  db.buttons.default = db.buttons.default or {}
  db.responses.default = db.responses.default or {}

  local changed = false

  if ensureForcedDibForSet(db.buttons.default, db.responses.default) then
    changed = true
  end

  for typeKey, typeButtons in pairs(db.buttons) do
    if type(typeKey) == "string" and typeKey ~= "default" and typeKey ~= "*" and type(typeButtons) == "table" then
      if Dibs.RCLootCouncil.IsDibEnabledForType(typeKey) then
        db.responses[typeKey] = db.responses[typeKey] or {}
        if ensureForcedDibForSet(typeButtons, db.responses[typeKey]) then
          changed = true
        end
      end
    end
  end

  return changed
end

local function forceDisableOption(option)
  if type(option) ~= "table" then return false end
  option.disabled = function()
    return true
  end
  return true
end

local function lockButtonOptionArgs(args, index)
  if type(args) ~= "table" then return false end
  local changed = false
  local keys = {
    "button" .. tostring(index),
    "picker" .. tostring(index),
    "text" .. tostring(index),
    "requireNotes" .. tostring(index),
    "move_up" .. tostring(index),
    "move_down" .. tostring(index),
  }
  for _, key in ipairs(keys) do
    if forceDisableOption(args[key]) then
      changed = true
    end
  end
  return changed
end

local function lockForcedDibOptionsForTable(options)
  if type(options) ~= "table" or type(options.args) ~= "table" then return false end
  local changed = false
  local mlSettings = options.args.mlSettings
  local buttonsTab = mlSettings and mlSettings.args and mlSettings.args.buttonsTab
  local buttonsArgs = buttonsTab and buttonsTab.args

  local buttonOptions = buttonsArgs and buttonsArgs.buttonOptions
  if buttonOptions and type(buttonOptions.args) == "table" then
    if lockButtonOptionArgs(buttonOptions.args, FORCED_DIB_BUTTON_INDEX) then
      changed = true
    end
  end

  if type(buttonsArgs) == "table" then
    for groupKey, groupOption in pairs(buttonsArgs) do
      if type(groupKey) == "string"
        and groupKey ~= "buttonOptions"
        and groupKey ~= "moreButtons"
        and groupKey ~= "timeoutOptions"
        and groupKey ~= "responseFromChat"
        and groupKey ~= "reset"
        and groupKey ~= "optionsDesc"
        and type(groupOption) == "table"
        and type(groupOption.args) == "table"
        and Dibs.RCLootCouncil.IsDibEnabledForType(groupKey)
      then
        if lockButtonOptionArgs(groupOption.args, FORCED_DIB_BUTTON_INDEX) then
          changed = true
        end
      end
    end
  end

  local responseFromChat = buttonsArgs and buttonsArgs.responseFromChat
  if responseFromChat and type(responseFromChat.args) == "table" then
    if forceDisableOption(responseFromChat.args["whisperKey" .. tostring(FORCED_DIB_BUTTON_INDEX)]) then
      changed = true
    end
  end

  return changed
end

local function ensureForcedDibOptionsLock(rc)
  local changed = false
  for _, options in ipairs(collectRCOptionTables(rc)) do
    if lockForcedDibOptionsForTable(options) then
      changed = true
    end
  end
  return changed
end

local ensureForcedDibConfig

local function startForcedConfigWatcher()
  if Dibs.RCLootCouncil.configWatcherActive then return end
  if not C_Timer or type(C_Timer.After) ~= "function" then return end

  Dibs.RCLootCouncil.configWatcherActive = true
  local function tick()
    if not Dibs.RCLootCouncil.configWatcherActive then
      return
    end
    local rc = getRC()
    if type(rc) == "table" then
      ensureForcedDibConfig(rc, true)
      ensureForcedDibOptionsLock(rc)
      for _, db in ipairs(collectRCDBs(rc)) do
        local buttons = db.buttons and db.buttons.default
        local responses = db.responses and db.responses.default
        if type(buttons) == "table" and type(buttons[FORCED_DIB_BUTTON_INDEX]) == "table" then
          buttons[FORCED_DIB_BUTTON_INDEX].text = FORCED_DIB_TEXT
          buttons[FORCED_DIB_BUTTON_INDEX].dibsLocked = true
          buttons[FORCED_DIB_BUTTON_INDEX].whisperKey = FORCED_DIB_WHISPER_KEY
        end
        if type(responses) == "table" and type(responses[FORCED_DIB_BUTTON_INDEX]) == "table" then
          responses[FORCED_DIB_BUTTON_INDEX].text = FORCED_DIB_TEXT
          responses[FORCED_DIB_BUTTON_INDEX].sort = FORCED_DIB_SORT
        end
      end
    end
    C_Timer.After(0.75, tick)
  end
  C_Timer.After(0.75, tick)
end

ensureForcedDibConfig = function(rc, suppressNotify)
  if type(rc) ~= "table" then return false end
  local changed = false
  for _, db in ipairs(collectRCDBs(rc)) do
    if ensureForcedDibConfigForDB(db) then
      changed = true
    end
  end

  if changed and not suppressNotify then
    if type(rc.ConfigTableChanged) == "function" then
      pcall(rc.ConfigTableChanged, rc, "buttons")
      pcall(rc.ConfigTableChanged, rc, "responses")
    end
    local ml = getRCMLModule(rc)
    if ml and type(ml.ConfigTableChanged) == "function" then
      pcall(ml.ConfigTableChanged, ml, "buttons")
      pcall(ml.ConfigTableChanged, ml, "responses")
    end
  end

  return changed
end

local function hookConfigChanged(owner, rc)
  if type(owner) ~= "table" or type(hooksecurefunc) ~= "function" then return false end
  if owner.__dibsConfigHooked then return true end
  if type(owner.ConfigTableChanged) ~= "function" then return false end

  hooksecurefunc(owner, "ConfigTableChanged", function()
    ensureForcedDibConfig(rc, true)
    if C_Timer and type(C_Timer.After) == "function" then
      C_Timer.After(0, function()
        ensureForcedDibConfig(rc, true)
        ensureForcedDibOptionsLock(rc)
      end)
    end
  end)
  owner.__dibsConfigHooked = true
  return true
end

local function installForcedDibConfigHook()
  local rc = getRC()
  if type(rc) ~= "table" then return false end

  ensureForcedDibConfig(rc, false)
  ensureForcedDibOptionsLock(rc)
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, function()
      ensureForcedDibConfig(rc, true)
      ensureForcedDibOptionsLock(rc)
    end)
  end
  startForcedConfigWatcher()
  local rcHooked = hookConfigChanged(rc, rc)
  local mlHooked = hookConfigChanged(getRCMLModule(rc), rc)
  return rcHooked or mlHooked
end

local function parseItemID(itemLink)
  if not itemLink then return nil end
  return tonumber(tostring(itemLink):match("item:(%d+)"))
end

local function formatCount(value)
  local number = tonumber(value) or 0
  if number == math.floor(number) then
    return tostring(number)
  end
  return string.format("%.1f", number)
end

local function isDibsButton(button)
  if type(button) ~= "table" then return false end
  if button.dibsButton == true then return true end
  if type(button.GetText) ~= "function" then return false end
  local label = normalizeButtonLabel(button:GetText())
  return label == "DIB" or label == "DIBS"
end

local function setButtonEnabled(button, enabled)
  if type(button) ~= "table" then return end
  if type(button.Enable) == "function" and type(button.Disable) == "function" then
    if enabled then
      button:Enable()
    else
      button:Disable()
    end
  end
  if type(button.SetAlpha) == "function" then
    button:SetAlpha(enabled and 1 or 0.45)
  end
end

local function getButtonEnabled(button)
  if type(button) ~= "table" or type(button.IsEnabled) ~= "function" then
    return nil
  end
  local ok, enabled = pcall(button.IsEnabled, button)
  if not ok then return nil end
  return enabled == true
end

local function applyVoteLockToEntry(entry, locked)
  if type(entry) ~= "table" or type(entry.buttons) ~= "table" then return end
  for _, button in ipairs(entry.buttons) do
    if type(button) == "table" then
      if locked then
        if button.__dibsVoteLocked ~= true then
          button.__dibsVoteLocked = true
          button.__dibsPrevEnabled = getButtonEnabled(button)
        end
        if type(button.Disable) == "function" then
          button:Disable()
        end
        if type(button.SetAlpha) == "function" then
          button:SetAlpha(0.35)
        end
      elseif button.__dibsVoteLocked == true then
        if button.__dibsPrevEnabled ~= false and type(button.Enable) == "function" then
          button:Enable()
        end
        if type(button.SetAlpha) == "function" then
          button:SetAlpha(1)
        end
        button.__dibsVoteLocked = nil
        button.__dibsPrevEnabled = nil
      end
    end
  end
end

local function supportsNativeDibResponse(entry)
  local rc = getRC()
  if type(rc) ~= "table" or type(rc.GetResponse) ~= "function" then return false end
  local buttonType = entry and entry.item and (entry.item.typeCode or entry.item.equipLoc) or "default"
  local ok, response = pcall(rc.GetResponse, rc, buttonType, "DIB")
  return ok and type(response) == "table" and response.text ~= nil
end

local function sendDibResponseFallback(entry)
  local rc = getRC()
  if type(rc) ~= "table" or type(rc.SendResponse) ~= "function" then return end
  local sessions = entry and entry.item and entry.item.sessions
  if type(sessions) ~= "table" then return end
  for _, session in ipairs(sessions) do
    pcall(rc.SendResponse, rc, "group", session, "DIB", nil, nil, entry.item.note)
  end
end

local function clickDibsButton(lootFrame, entry)
  local playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
  local itemID = parseItemID(entry and entry.item and entry.item.link)
  local responseType = entry and entry.item and (entry.item.typeCode or entry.item.equipLoc) or "default"
  local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID, responseType)
  if status.canUseDib ~= true then
    return
  end

  if type(lootFrame) == "table" and type(lootFrame.OnRoll) == "function" and supportsNativeDibResponse(entry) then
    local ok = pcall(lootFrame.OnRoll, lootFrame, entry, "DIB")
    if ok then return end
  end

  sendDibResponseFallback(entry)
  if entry and entry.item then
    entry.item.rolled = true
  end
  if type(lootFrame) == "table" and type(lootFrame.Update) == "function" then
    pcall(lootFrame.Update, lootFrame)
  end
end

local function installDibsClickGuard(button)
  if type(button) ~= "table" then return end
  if button.__dibsClickGuardInstalled then return end
  if type(button.SetScript) ~= "function" then return end

  local originalOnClick = nil
  if type(button.GetScript) == "function" then
    originalOnClick = button:GetScript("OnClick")
  end
  button.__dibsOriginalOnClick = originalOnClick

  button:SetScript("OnClick", function(self, ...)
    local entry = self and self.__dibsEntry
    local lootFrame = self and self.__dibsLootFrame
    local playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
    local itemID = parseItemID(entry and entry.item and entry.item.link)
    local responseType = entry and entry.item and (entry.item.typeCode or entry.item.equipLoc) or "default"
    local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID, responseType)

    if not status or status.canUseDib ~= true then
      setButtonEnabled(self, false)
      return
    end

    if self.dibsInjected == true then
      clickDibsButton(lootFrame, entry)
      return
    end

    if type(self.__dibsOriginalOnClick) == "function" then
      pcall(self.__dibsOriginalOnClick, self, ...)
      return
    end

    clickDibsButton(lootFrame, entry)
  end)

  button.__dibsClickGuardInstalled = true
end

local function installDibsTooltip(button, entry)
  if not button or type(button.SetScript) ~= "function" then return end
  if button.__dibsTooltipInstalled then return end
  local function show(self)
    local itemID = parseItemID(entry and entry.item and entry.item.link)
    local responseType = entry and entry.item and (entry.item.typeCode or entry.item.equipLoc) or "default"
    local playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
    local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID, responseType) or {}
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Dibs", 1, 0.84, 0)
    GameTooltip:AddDoubleLine("Balance", tostring(status.balance or 0), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Status", tostring(status.status or "none"), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Can use Dib", status.canUseDib and "Yes" or "No", 1, 1, 1, status.canUseDib and 0.2 or 1, status.canUseDib and 1 or 0.2, 0.2)
    GameTooltip:Show()
  end
  local function hide() GameTooltip:Hide() end
  if type(button.HookScript) == "function" then
    button:HookScript("OnEnter", show)
    button:HookScript("OnLeave", hide)
  else
    button:SetScript("OnEnter", show)
    button:SetScript("OnLeave", hide)
  end
  button.__dibsTooltipInstalled = true
end

local function isPassButton(button)
  if type(button) ~= "table" then return false end
  if type(button.GetText) ~= "function" then return false end
  return normalizeButtonLabel(button:GetText()) == "PASS"
end

local function placeDibButtonFirst(entry, dibButton)
  if type(entry) ~= "table" or type(dibButton) ~= "table" then return end
  if entry.type == "roll" or type(entry.buttons) ~= "table" then return end
  if type(dibButton.ClearAllPoints) ~= "function" or type(dibButton.SetPoint) ~= "function" then return end
  if type(entry.icon) ~= "table" then return end

  local passButton = nil
  local others = {}
  for _, button in ipairs(entry.buttons) do
    if button ~= dibButton then
      if isPassButton(button) then
        passButton = button
      else
        table.insert(others, button)
      end
    end
  end

  local ordered = { dibButton }
  for _, button in ipairs(others) do
    table.insert(ordered, button)
  end
  if passButton then
    table.insert(ordered, passButton)
  end

  local prev = nil
  for _, button in ipairs(ordered) do
    if type(button) == "table" and type(button.ClearAllPoints) == "function" and type(button.SetPoint) == "function" then
      button:ClearAllPoints()
      if prev == nil then
        button:SetPoint("BOTTOMLEFT", entry.icon, "BOTTOMRIGHT", 5, -6)
      else
        button:SetPoint("LEFT", prev, "RIGHT", 5, 0)
      end
      prev = button
    end
  end
end

local function createDibsButton(entry, lootFrame)
  if type(entry) ~= "table" or type(entry.frame) ~= "table" then return nil end
  if type(CreateFrame) ~= "function" then return nil end

  local button = CreateFrame("Button", nil, entry.frame, "UIPanelButtonTemplate")
  if type(button.SetText) == "function" then
    button:SetText("Dib")
  end
  if type(button.SetSize) == "function" then
    button:SetSize(44, 20)
  end
  if type(button.SetPoint) == "function" then
    button:SetPoint("TOPRIGHT", entry.frame, "TOPRIGHT", -36, -28)
  end
  if type(button.SetScript) == "function" then
    button:SetScript("OnClick", function()
      clickDibsButton(lootFrame, entry)
    end)
  end
  button.dibsButton = true
  button.dibsInjected = true
  entry.dibsButton = button
  table.insert(entry.buttons, button)
  installDibsTooltip(button, entry)
  return button
end

local function ensureDibsButton(entry, lootFrame)
  if type(entry) ~= "table" then return nil end
  if entry.type == "roll" then return nil end
  if type(entry.buttons) ~= "table" then return nil end
  for _, button in ipairs(entry.buttons) do
    if isDibsButton(button) then
      button.dibsButton = true
      entry.dibsButton = button
      installDibsTooltip(button, entry)
      return button
    end
  end

  if type(entry.UpdateButtons) == "function" then
    pcall(entry.UpdateButtons, entry)
    for _, button in ipairs(entry.buttons) do
      if isDibsButton(button) and button.dibsInjected ~= true then
        button.dibsButton = true
        entry.dibsButton = button
        installDibsTooltip(button, entry)
        return button
      end
    end
  end

  return createDibsButton(entry, lootFrame)
end

local function getLootFrameModule(rc)
  if type(rc) ~= "table" then return nil end
  if type(rc.GetActiveModule) == "function" then
    local ok, module = pcall(rc.GetActiveModule, rc, "lootframe")
    if ok and type(module) == "table" then return module end
  end
  if type(rc.GetModule) == "function" then
    local ok, module = pcall(rc.GetModule, rc, "RCLootFrame", true)
    if ok and type(module) == "table" then return module end
  end
  if type(rc.modules) == "table" and type(rc.modules.RCLootFrame) == "table" then
    return rc.modules.RCLootFrame
  end
  return nil
end

local function getVotingFrameModule(rc)
  if type(rc) ~= "table" then return nil end
  if type(rc.GetActiveModule) == "function" then
    local ok, module = pcall(rc.GetActiveModule, rc, "votingframe")
    if ok and type(module) == "table" then return module end
  end
  if type(rc.GetModule) == "function" then
    local ok, module = pcall(rc.GetModule, rc, "RCVotingFrame", true)
    if ok and type(module) == "table" then return module end
  end
  if type(rc.modules) == "table" and type(rc.modules.RCVotingFrame) == "table" then
    return rc.modules.RCVotingFrame
  end
  if type(rc.modules) == "table" then
    for _, key in ipairs({ "RCLootCouncilVotingFrame", "VotingFrame", "votingframe" }) do
      if type(rc.modules[key]) == "table" then return rc.modules[key] end
    end
  end
  if type(rc.votingFrame) == "table" then return rc.votingFrame end
  return nil
end

local function getHistoryModule(rc)
  if type(rc) ~= "table" then return nil end
  if type(rc.GetActiveModule) == "function" then
    local ok, module = pcall(rc.GetActiveModule, rc, "history")
    if ok and type(module) == "table" then return module end
  end
  if type(rc.GetModule) == "function" then
    local ok, module = pcall(rc.GetModule, rc, "RCLootHistory", true)
    if ok and type(module) == "table" then return module end
  end
  if type(rc.modules) == "table" and type(rc.modules.RCLootHistory) == "table" then
    return rc.modules.RCLootHistory
  end
  return nil
end

local function sanitizeRCLootCouncilHistory(rc)
  if type(rc) ~= "table" or type(rc.GetHistoryDB) ~= "function" then return false end
  local ok, historyDB = pcall(rc.GetHistoryDB, rc)
  if not ok or type(historyDB) ~= "table" then return false end
  local changed = false
  for _, entries in pairs(historyDB) do
    if type(entries) == "table" then
      for index, entry in ipairs(entries) do
        if type(entry) == "table" and entry.dibsOrigin == "RCLootCouncil_dibs" then
          local id = tostring(entry.id or "")
          local timestamp, counter = id:match("^(%d+)%-(%d+)$")
          if not timestamp or not counter then
            local first = id:match("^(%d+)") or tostring(time())
            entry.id = first .. "-" .. tostring(index)
            changed = true
          end
        end
      end
    end
  end
  return changed
end

local function buildFallbackItemLink(itemID)
  local id = tonumber(itemID) or 0
  return string.format("|cffffffff|Hitem:%d::::::::::::|h[Item %d]|h|r", id, id)
end

local function getDateParts()
  local now = time()
  local stamp = date("*t", now)
  if type(stamp) ~= "table" then
    return "1970/01/01", "00:00:00"
  end
  local dateValue = string.format("%04d/%02d/%02d", stamp.year or 1970, stamp.month or 1, stamp.day or 1)
  local timeValue = string.format("%02d:%02d:%02d", stamp.hour or 0, stamp.min or 0, stamp.sec or 0)
  return dateValue, timeValue
end

function Dibs.RCLootCouncil.LogPreDibRequest(request, sourceLabel)
  local rc = getRC()
  if type(rc) ~= "table" then return false end

  local history = getHistoryModule(rc)
  local playerName = request and request.playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "Unknown")
  local itemID = tonumber(request and request.itemID) or 0
  local itemLink = request and request.itemName
  if type(itemLink) ~= "string" or not itemLink:find("|Hitem:", 1, true) then
    itemLink = buildFallbackItemLink(itemID)
  end

  local dateValue, timeValue = getDateParts()
  local classTag = select(2, UnitClass and UnitClass("player") or nil) or "PRIEST"
  local groupSize = (GetNumGroupMembers and tonumber(GetNumGroupMembers()) or 0)
  local eventId = request and request.requestId or Dibs.NewId and Dibs.NewId("predib") or tostring(time())
  local numericCounter = tonumber(tostring(eventId):match("%d+")) or 0
  local sourceText = tostring(sourceLabel or request and request.source or "Adventure Guide")
  local historyEntry = {
    dibsOrigin = "RCLootCouncil_dibs",
    date = dateValue,
    time = timeValue,
    id = tostring(time()) .. "-" .. tostring(numericCounter),
    lootWon = itemLink,
    response = "Pre-Dib",
    responseID = FORCED_DIB_BUTTON_INDEX,
    votes = 0,
    class = classTag,
    instance = "Pre-Dibs",
    boss = sourceText,
    difficultyID = 0,
    mapID = 0,
    groupSize = groupSize,
    itemReplaced1 = "",
    itemReplaced2 = "",
    isAwardReason = false,
    typeCode = "default",
    color = { FORCED_DIB_COLOR[1], FORCED_DIB_COLOR[2], FORCED_DIB_COLOR[3], FORCED_DIB_COLOR[4] },
    note = "[Dibs] Pre-Dib reservation",
    owner = playerName,
  }

  if history and type(history.OnHistoryReceived) == "function" then
    local ok = pcall(history.OnHistoryReceived, history, playerName, historyEntry)
    return ok == true
  end

  if type(rc.GetHistoryDB) == "function" then
    local ok, historyDB = pcall(rc.GetHistoryDB, rc)
    if ok and type(historyDB) == "table" then
      historyDB[playerName] = historyDB[playerName] or {}
      table.insert(historyDB[playerName], historyEntry)
      if history and type(history.BuildData) == "function" and type(history.frame) == "table" and type(history.frame.IsVisible) == "function" and history.frame:IsVisible() then
        pcall(history.BuildData, history)
      end
      return true
    end
  end

  return false
end

local function applyDibsButtonState(lootFrame)
  if type(lootFrame) ~= "table" then return end
  installForcedDibConfigHook()
  local manager = lootFrame.EntryManager
  local entries = manager and manager.entries
  if type(entries) ~= "table" then return end

  local showDibs = Dibs.RCLootCouncil.IsAvailable and Dibs.RCLootCouncil.IsAvailable() == true

  local playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
  for _, entry in pairs(entries) do
    if type(entry) == "table" and type(entry.buttons) == "table" then
      local dibButton = ensureDibsButton(entry, lootFrame)
      local itemID = parseItemID(entry.item and entry.item.link)
      local responseType = entry.item and (entry.item.typeCode or entry.item.equipLoc) or "default"
      local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID, responseType)
      applyVoteLockToEntry(entry, status.lockedOutByPreDib == true)
      if dibButton and type(dibButton.Show) == "function" and type(dibButton.Hide) == "function" then
        dibButton.__dibsEntry = entry
        dibButton.__dibsLootFrame = lootFrame
        installDibsClickGuard(dibButton)
        if showDibs then
          placeDibButtonFirst(entry, dibButton)
          dibButton:Show()
          setButtonEnabled(dibButton, status.canUseDib == true)
        else
          applyVoteLockToEntry(entry, false)
          dibButton:Hide()
        end
      end
    end
  end
end

local function installLootFrameHook()
  if type(hooksecurefunc) ~= "function" then return false end
  local rc = getRC()
  local lootFrame = getLootFrameModule(rc)
  if type(lootFrame) ~= "table" then return false end
  if lootFrame.__dibsButtonHooked then
    applyDibsButtonState(lootFrame)
    return true
  end
  if type(lootFrame.Update) ~= "function" then return false end

  hooksecurefunc(lootFrame, "Update", function(self)
    applyDibsButtonState(self)
  end)
  lootFrame.__dibsButtonHooked = true
  applyDibsButtonState(lootFrame)
  return true
end

local function getRemainingDibsText(playerName)
  if not Dibs.Ledger or type(Dibs.Ledger.GetPlayerSeasonState) ~= "function" then
    return "0/0", 0
  end
  local seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
  local state = Dibs.Ledger.GetPlayerSeasonState(seasonId, playerName)
  local remaining = tonumber(state and state.remainingBalance) or 0
  local maximum = tonumber(state and state.baseAllocation) or 0
  return formatCount(remaining) .. "/" .. formatCount(maximum), remaining
end

local function setDibsColumnCell(frame, data, cols, row, realrow, column)
  if not data or not data[realrow] or not frame or not frame.text then return end
  local candidateName = data[realrow].name
  local textValue, sortValue = getRemainingDibsText(candidateName)
  frame.text:SetText(textValue)
  frame.text:SetTextColor(1, 1, 1, 1)
  if data[realrow].cols and data[realrow].cols[column] then
    data[realrow].cols[column].value = sortValue
  end
end

local function getVotingSessionInfo(votingFrame)
  if type(votingFrame) ~= "table" then return nil, nil end
  local session
  if type(votingFrame.GetCurrentSession) == "function" then
    local ok, value = pcall(votingFrame.GetCurrentSession, votingFrame)
    if ok then
      session = tonumber(value)
    end
  end
  if not session then return nil, nil end

  local lootTable
  if type(votingFrame.GetLootTable) == "function" then
    local ok, tableData = pcall(votingFrame.GetLootTable, votingFrame)
    if ok and type(tableData) == "table" then
      lootTable = tableData
    end
  end

  local current = lootTable and lootTable[session] or nil
  return session, current
end

local function responseIsDib(rc, typeCode, responseValue)
  if responseValue == nil then return false end
  if type(responseValue) == "string" and isDibLabel(responseValue) then return true end
  if type(rc) ~= "table" or type(rc.GetResponse) ~= "function" then return false end
  local ok, response = pcall(rc.GetResponse, rc, typeCode or "default", responseValue)
  return ok and type(response) == "table" and isDibLabel(response.text)
end

local function getFirstNormalResponse(rc, typeCode)
  if type(rc) ~= "table" or type(rc.GetNumButtons) ~= "function" or type(rc.GetResponse) ~= "function" then
    return nil
  end
  local okNum, numButtons = pcall(rc.GetNumButtons, rc, typeCode)
  if not okNum then return nil end
  for i = 1, tonumber(numButtons) or 0 do
    local okResponse, response = pcall(rc.GetResponse, rc, typeCode, i)
    if okResponse and type(response) == "table" and not isDibLabel(response.text) then
      return i
    end
  end
  return nil
end

local function convertCandidateToNormal(votingFrame, candidateName)
  local rc = getRC()
  local session, current = getVotingSessionInfo(votingFrame)
  if not session or not current or not candidateName then return end
  local typeCode = current.typeCode or current.equipLoc or "default"
  local replacement = getFirstNormalResponse(rc, typeCode)
  if not replacement then return end

  if type(rc) == "table" and type(rc.Send) == "function" then
    pcall(rc.Send, rc, "group", "change_response", session, candidateName, replacement)
  end
  if type(votingFrame.OnChangeResponseReceived) == "function" then
    pcall(votingFrame.OnChangeResponseReceived, votingFrame, session, candidateName, replacement)
  elseif type(votingFrame.SetCandidateData) == "function" then
    pcall(votingFrame.SetCandidateData, votingFrame, session, candidateName, "response", replacement)
    if type(votingFrame.Update) == "function" then
      pcall(votingFrame.Update, votingFrame, true)
    end
  end
end

local function setDibConvertCell(frame, data, cols, row, realrow, column, fShow, tableArg)
  if not data or not data[realrow] or type(frame) ~= "table" then return end
  local rc = getRC()
  local votingFrame = getVotingFrameModule(rc)
  if type(votingFrame) ~= "table" then return end
  local session, current = getVotingSessionInfo(votingFrame)
  if not session or not current then return end

  local candidateName = data[realrow].name
  local responseValue = type(votingFrame.GetCandidateData) == "function" and votingFrame:GetCandidateData(session, candidateName, "response") or nil
  local typeCode = current.typeCode or current.equipLoc or "default"
  local canConvert = responseIsDib(rc, typeCode, responseValue)
  local normalResponse = getFirstNormalResponse(rc, typeCode)

  local button = frame.convertBtn
  if not button then
    button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.convertBtn = button
  end

  button:SetText("Normal")
  button:SetScript("OnClick", function()
    convertCandidateToNormal(votingFrame, candidateName)
  end)

  if canConvert then
    button:Show()
    if type(button.Enable) == "function" and type(button.Disable) == "function" then
      if normalResponse and (rc and rc.isMasterLooter ~= false) then
        button:Enable()
      else
        button:Disable()
      end
    end
  else
    button:Hide()
  end

  if data[realrow].cols and data[realrow].cols[column] then
    data[realrow].cols[column].value = canConvert and 1 or 0
  end
end

local function refreshVotingColumns(votingFrame)
  if type(votingFrame) ~= "table" then return end
  if not votingFrame.frame and type(votingFrame.GetFrame) == "function" then
    pcall(votingFrame.GetFrame, votingFrame)
  end
  local frame = votingFrame.frame
  if frame and frame.st and type(frame.st.SetDisplayCols) == "function" then
    pcall(frame.st.SetDisplayCols, frame.st, votingFrame.scrollCols)
    if type(frame.st.Refresh) == "function" then pcall(frame.st.Refresh, frame.st) end
  elseif frame and type(frame.UpdateSt) == "function" then
    pcall(frame.UpdateSt, frame)
  end
end

local function installVotingFrameColumn()
  local rc = getRC()
  local votingFrame = getVotingFrameModule(rc)
  if type(votingFrame) ~= "table" then return false end
  -- Do not trust the marker alone: RCLootCouncil can rebuild scrollCols.

  local hasColumn = false
  if type(votingFrame.scrollCols) == "table" then
    for _, column in ipairs(votingFrame.scrollCols) do
      if type(column) == "table" and column.colName == "dibsRemaining" then
        hasColumn = true
        break
      end
    end
  end
  if hasColumn then
    local rendered = false
    local tableView = votingFrame.frame and votingFrame.frame.st
    if tableView and type(tableView.cols) == "table" then
      for _, column in ipairs(tableView.cols) do
        if type(column) == "table" and column.colName == "dibsRemaining" then
          rendered = true
          break
        end
      end
    end
    refreshVotingColumns(votingFrame)
    votingFrame.__dibsRemainingColumnInstalled = true
    return true
  end

  local spec = {
    colName = "dibsRemaining",
    name = "Dibs",
    width = 75,
    align = "CENTER",
    sortnext = "response",
    DoCellUpdate = setDibsColumnCell,
  }

  local added = false
  if type(votingFrame.scrollCols) == "table" then
    local insertAt = #votingFrame.scrollCols + 1
    for index, column in ipairs(votingFrame.scrollCols) do
      if type(column) == "table" and column.colName == "response" then
        insertAt = index + 1
        break
      end
    end
    table.insert(votingFrame.scrollCols, insertAt, spec)
    refreshVotingColumns(votingFrame)
    if not votingFrame.frame and type(votingFrame.RefreshColumnLayout) == "function" then
      pcall(votingFrame.RefreshColumnLayout, votingFrame)
    end
    added = true
  end

  votingFrame.__dibsRemainingColumnInstalled = hasColumn or added
  return added
end

local function installDibConvertColumn()
  local rc = getRC()
  local votingFrame = getVotingFrameModule(rc)
  if type(votingFrame) ~= "table" then return false end
  -- Do not trust the marker alone: RCLootCouncil can rebuild scrollCols.

  local hasColumn = false
  if type(votingFrame.scrollCols) == "table" then
    for _, column in ipairs(votingFrame.scrollCols) do
      if type(column) == "table" and column.colName == "dibsConvert" then
        hasColumn = true
        break
      end
    end
  end
  if hasColumn then
    local rendered = false
    local tableView = votingFrame.frame and votingFrame.frame.st
    if tableView and type(tableView.cols) == "table" then
      for _, column in ipairs(tableView.cols) do
        if type(column) == "table" and column.colName == "dibsConvert" then
          rendered = true
          break
        end
      end
    end
    refreshVotingColumns(votingFrame)
    votingFrame.__dibsConvertColumnInstalled = true
    return true
  end

  local spec = {
    colName = "dibsConvert",
    name = "Convert",
    width = 66,
    align = "CENTER",
    sortnext = "response",
    DoCellUpdate = setDibConvertCell,
  }

  local added = false
  if type(votingFrame.scrollCols) == "table" then
    local insertAt = #votingFrame.scrollCols + 1
    for index, column in ipairs(votingFrame.scrollCols) do
      if type(column) == "table" and column.colName == "dibsRemaining" then
        insertAt = index + 1
        break
      end
    end
    table.insert(votingFrame.scrollCols, insertAt, spec)
    refreshVotingColumns(votingFrame)
    if not votingFrame.frame and type(votingFrame.RefreshColumnLayout) == "function" then
      pcall(votingFrame.RefreshColumnLayout, votingFrame)
    end
    added = true
  end

  votingFrame.__dibsConvertColumnInstalled = hasColumn or added
  return added
end

local function installVotingFrameColumns()
  local statusCol = installVotingFrameColumn()
  local convertCol = installDibConvertColumn()
  local votingFrame = getVotingFrameModule(getRC())
  if type(votingFrame) == "table" and not votingFrame.__dibsOnEnableHooked and type(hooksecurefunc) == "function" then
    hooksecurefunc(votingFrame, "OnEnable", function()
      if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
          installVotingFrameColumn()
          installDibConvertColumn()
        end)
      else
        installVotingFrameColumn()
        installDibConvertColumn()
      end
    end)
    votingFrame.__dibsOnEnableHooked = true
  end
  if type(votingFrame) == "table" and not votingFrame.__dibsOnUpdateHooked and type(hooksecurefunc) == "function" then
    hooksecurefunc(votingFrame, "Update", function()
      if not votingFrame.__dibsUpdatePending then
        votingFrame.__dibsUpdatePending = true
        local function apply()
          votingFrame.__dibsUpdatePending = nil
          installVotingFrameColumn()
          installDibConvertColumn()
        end
        if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, apply) else apply() end
      end
    end)
    votingFrame.__dibsOnUpdateHooked = true
  end
  return statusCol and convertCol
end

function Dibs.RCLootCouncil.GetVotingIntegrationStatus()
  local rc = getRC()
  local voting = getVotingFrameModule(rc)
  local scrollCount = 0
  local scrollHasDibs = false
  local renderedHasDibs = false
  if type(voting) == "table" and type(voting.scrollCols) == "table" then
    scrollCount = #voting.scrollCols
    for _, column in ipairs(voting.scrollCols) do
      if type(column) == "table" and column.colName == "dibsRemaining" then
        scrollHasDibs = true
        break
      end
    end
  end
  if type(voting) == "table" and type(voting.frame) == "table" and type(voting.frame.st) == "table" and type(voting.frame.st.cols) == "table" then
    for _, column in ipairs(voting.frame.st.cols) do
      if type(column) == "table" and column.colName == "dibsRemaining" then
        renderedHasDibs = true
        break
      end
    end
  end
  return {
    moduleFound = type(voting) == "table",
    addColumn = type(voting) == "table" and type(voting.AddColumn) == "function",
    scrollColumns = type(voting) == "table" and type(voting.scrollCols) == "table",
    scrollColumnCount = scrollCount,
    scrollHasDibs = scrollHasDibs,
    renderedHasDibs = renderedHasDibs,
    dibsColumnInstalled = type(voting) == "table" and voting.__dibsRemainingColumnInstalled == true,
    convertColumnInstalled = type(voting) == "table" and voting.__dibsConvertColumnInstalled == true,
  }
end

local function ensureRuntimeHooks(maxAttempts)
  local attempts = 0
  local limit = tonumber(maxAttempts) or 120

  local function tick()
    attempts = attempts + 1
    local configReady = installForcedDibConfigHook()
    local lootReady = installLootFrameHook()
    local votingReady = installVotingFrameColumns()
    if (configReady and lootReady and votingReady) or attempts >= limit then
      Dibs.RCLootCouncil.runtimeHooksReady = configReady and lootReady and votingReady
      Dibs.RCLootCouncil.runtimeHookRetryActive = false
      return
    end
    if C_Timer and type(C_Timer.After) == "function" then
      C_Timer.After(1, tick)
    else
      Dibs.RCLootCouncil.runtimeHookRetryActive = false
    end
  end

  if Dibs.RCLootCouncil.runtimeHookRetryActive then return end
  Dibs.RCLootCouncil.runtimeHookRetryActive = true
  tick()
end

local function playerIdentity(value)
  if type(value) == "table" then
    if type(value.GetGUID) == "function" then
      local ok, guid = pcall(value.GetGUID, value)
      if ok and guid then return tostring(guid) end
    end
    if type(value.GetName) == "function" then
      local ok, name = pcall(value.GetName, value)
      if ok then value = name end
    else
      value = value.guid or value.name
    end
  end
  if value == nil then return nil end
  return Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId(value) or nil
end

local function playerNameIdentity(value)
  if type(value) == "table" then
    if type(value.GetName) == "function" then
      local ok, name = pcall(value.GetName, value)
      if ok then value = name end
    else value = value.name or value.playerName end
    if value == nil then return nil end
  end
  if value == nil and Dibs.GetPlayerName then value = Dibs.GetPlayerName() end
  if not value then return nil end
  local text = tostring(value)
  if not text:find("-", 1, true) and type(GetRealmName) == "function" then
    local realm = tostring(GetRealmName() or ""):gsub("[%s%-]", "")
    if realm ~= "" then text = text .. "-" .. realm end
  end
  return string.lower(text)
end

function Dibs.RCLootCouncil.GetAvailability()
  if not isLoaded() then return "absent" end
  local rc = getRC()
  if type(rc) ~= "table" then return "degraded" end
  if rc.enabled == false then return "absent" end
  if rc.enabled ~= true then return "degraded" end
  if not playerIdentity(rc.masterLooter) then return "degraded" end
  return "operational"
end

function Dibs.RCLootCouncil.IsAvailable()
  return Dibs.RCLootCouncil.GetAvailability() == "operational"
end

function Dibs.RCLootCouncil.EvaluateAuthority(actionId, actor)
  local before = Dibs.RCLootCouncil.GetAvailability()
  local actorId = actor == nil and Dibs.Permissions.CanonicalPlayerId(nil) or playerIdentity(actor)
  if before ~= "operational" or not actorId then
    return { allowed = false, authority = "rclootcouncil", availability = before, actionId = actionId, actorId = actorId, reasonCode = actorId and "RC_AUTHORITY_UNVERIFIABLE" or "INVALID_ACTOR", diagnostic = text("AUTHORITY_RC_UNVERIFIABLE", "RCLootCouncil authority could not be verified.") }
  end
  local rc = getRC()
  local masterId = rc and playerIdentity(rc.masterLooter)
  local localId = Dibs.Permissions.CanonicalPlayerId(nil)
  local localNameId = Dibs.Permissions.CanonicalPlayerId(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  local actorIsLocal = (localId and string.lower(tostring(actorId)) == string.lower(tostring(localId)))
    or (localNameId and string.lower(tostring(actorId)) == string.lower(tostring(localNameId)))
  if not actorIsLocal then
    return { allowed = false, authority = "rclootcouncil", availability = before, actionId = actionId, actorId = actorId, reasonCode = "RC_ACTOR_NOT_LOCAL", diagnostic = text("AUTHORITY_RC_NOT_LOCAL", "Only the local RCLootCouncil Master Looter may finalize this action.") }
  end
  local after = Dibs.RCLootCouncil.GetAvailability()
  local currentRC = getRC()
  local currentMasterId = currentRC and playerIdentity(currentRC.masterLooter)
  if after ~= before or not masterId or currentMasterId ~= masterId then
    return { allowed = false, authority = "rclootcouncil", availability = "degraded", actionId = actionId, actorId = actorId, reasonCode = "RC_STATE_CHANGED", diagnostic = text("AUTHORITY_RC_STATE_CHANGED", "RCLootCouncil authority changed during evaluation.") }
  end
  local actorName = playerNameIdentity(actor)
  local masterName = playerNameIdentity(rc.masterLooter)
  local allowed = actorId == masterId or (actorName ~= nil and masterName ~= nil and actorName == masterName)
  return { allowed = allowed, authority = "rclootcouncil", availability = before, actionId = actionId, actorId = actorId, reasonCode = allowed and "RC_AUTHORIZED" or "RC_NOT_MASTER_LOOTER", diagnostic = allowed and text("AUTHORITY_RC_AUTHORIZED", "Authorized by RCLootCouncil.") or text("AUTHORITY_RC_NOT_MASTER_LOOTER", "Only the current RCLootCouncil Master Looter may perform this action.") }
end

function Dibs.RCLootCouncil.CanUseDibResponse(playerName, itemID)
  local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  return status.canUseDib == true
end

function Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID, responseType, options)
  options = type(options) == "table" and options or {}
  local name = playerName or Dibs.GetPlayerName()
  local targetItem = tonumber(itemID)
  local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(name) or 0
  local typeKey = normalizeTypeKey(responseType)
  local typeEnabled = Dibs.RCLootCouncil.IsDibEnabledForType(typeKey)
  local publicPreDibsEnabled = Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() == true
  local preDib = targetItem and Dibs.PreDibs and Dibs.PreDibs.GetConfirmedRequestForPlayer(name, targetItem) or nil
  local hasPriority = false
  if targetItem and Dibs.PreDibs then
    for _, request in ipairs(Dibs.PreDibs.GetRequestsForItem(targetItem)) do
      if request.status == "confirmed" then hasPriority = true break end
    end
  end
  local lockedOutByPreDib = hasPriority and preDib == nil
  local eligible = false
  if typeEnabled and not lockedOutByPreDib then
    if publicPreDibsEnabled and options.ignorePublicPreDibRequirement ~= true then
      eligible = preDib ~= nil
    else
      eligible = ((tonumber(balance) or 0) > 0 or preDib ~= nil)
    end
  end
  local state = "none"
  if not typeEnabled then
    state = "type-disabled"
  elseif lockedOutByPreDib then
    state = "pre-dib-locked"
  elseif publicPreDibsEnabled and preDib == nil then
    state = "pre-dib-required"
  elseif preDib then
    state = "pre-dib"
  elseif eligible then
    state = "dib-available"
  elseif (tonumber(balance) or 0) > 0 then
    state = "ineligible"
  end
  return {
    playerName = name,
    itemID = targetItem,
    responseType = typeKey,
    dibTypeEnabled = typeEnabled,
    balance = tonumber(balance) or 0,
    hasDibs = (tonumber(balance) or 0) > 0,
    hasPreDib = preDib ~= nil,
    hasAnyConfirmedPreDib = hasPriority,
    publicPreDibsEnabled = publicPreDibsEnabled,
    lockedOutByPreDib = lockedOutByPreDib,
    canUseDib = eligible,
    status = state,
    preDibRequest = preDib,
  }
end

function Dibs.RCLootCouncil.ValidateResponse(playerName, itemID, response)
  if response ~= "DIB" then return true end
  return Dibs.RCLootCouncil.CanUseDibResponse(playerName, itemID)
end

local function getAwardIdentity(rc, session, winner, itemID, itemLink)
  local sources = { rc, getRCMLModule(rc) }
  local entry
  for _, source in ipairs(sources) do
    local lootTable = source and source.lootTable
    if type(lootTable) == "table" and lootTable[tonumber(session)] then
      entry = lootTable[tonumber(session)]
      break
    end
  end

  local unique = entry and (entry.itemGUID or entry.itemGuid or entry.guid or entry.lootGUID or entry.id)
  if unique then
    return "entry:" .. tostring(unique)
  end

  -- RCLootCouncil writes an immutable history id for completed awards. Prefer it
  -- when the callback is delivered after the history row is persisted, because a
  -- raid/instance name is not a unique loot-session identifier.
  if rc and type(rc.GetHistoryDB) == "function" then
    local ok, historyDB = pcall(rc.GetHistoryDB, rc)
    if ok and type(historyDB) == "table" then
      local winnerId = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(winner)
      for playerKey, entries in pairs(historyDB) do
        if type(entries) == "table" and (not winnerId or not Dibs.Permissions or not Dibs.Permissions.CanonicalPlayerId
          or Dibs.Permissions.CanonicalPlayerId(playerKey) == winnerId) then
          for index = #entries, 1, -1 do
            local historyEntry = entries[index]
            if type(historyEntry) == "table" and historyEntry.id then
              local historyItem = historyEntry.lootWon or historyEntry.itemLink or historyEntry.item
              local historyItemId = tonumber(historyEntry.itemID) or parseItemID(historyItem)
              if historyItemId == tonumber(itemID) then
                return "history:" .. tostring(historyEntry.id)
              end
            end
          end
        end
      end
    end
  end

  local sessionKey = rc and (rc.currentSessionId or rc.lootSessionId or rc.sessionID or rc.lastEncounterID)
  if sessionKey then
    return "session:" .. tostring(sessionKey) .. ":" .. tostring(session) .. ":" .. tostring(winner) .. ":" .. tostring(itemID) .. ":" .. tostring(itemLink)
  end

  -- The event does not always expose a persistent loot identity. Keep a runtime
  -- reference in that case so duplicate callbacks in one session remain idempotent.
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.rclcAwardRefs = Dibs.runtime.rclcAwardRefs or {}
  local key = table.concat({ tostring(session), tostring(winner), tostring(itemID), tostring(itemLink) }, ":")
  if not Dibs.runtime.rclcAwardRefs[key] then
    Dibs.runtime.rclcAwardRefs[key] = Dibs.NewId("award")
  end
  return Dibs.runtime.rclcAwardRefs[key]
end

function Dibs.RCLootCouncil.OnAwardSuccess(_, session, winner, status, itemLink, responseText)
  if not Dibs.ProtectedActions or not winner or not itemLink then return end
  if not isDibLabel(responseText) then return end
  local mode = Dibs.Permissions and Dibs.Permissions.GetInstallationMode and Dibs.Permissions.GetInstallationMode() or "AUTO"
  if mode == "STANDALONE" then return end
  if type(Dibs.RCLootCouncil.GetAvailability) ~= "function" or Dibs.RCLootCouncil.GetAvailability() ~= "operational" then return end
  local itemID = tonumber(tostring(itemLink):match("item:(%d+)"))
  if not itemID then return end
  local rc = getRC()
  local actor = rc and rc.masterLooter
  if not actor then return end
  local ref = getAwardIdentity(rc, session, winner, itemID, itemLink)
  Dibs.ProtectedActions.FinalizeAward(actor, { awardRef = ref, playerName = winner, itemID = itemID, itemLink = itemLink, sourceStatus = status, source = "rclootcouncil", response = responseText, responseValidated = true })
end

function Dibs.RCLootCouncil.Initialize()
  if Dibs.RCLootCouncil.initialized then return true end
  local rc = getRC()
  if type(rc) ~= "table" then return false end
  sanitizeRCLootCouncilHistory(rc)
  if type(rc.RegisterMessage) == "function" then
    pcall(rc.RegisterMessage, rc, "RCMLAwardSuccess", Dibs.RCLootCouncil.OnAwardSuccess)
  end
  installForcedDibConfigHook()
  installLootFrameHook()
  installVotingFrameColumns()
  ensureRuntimeHooks(120)
  Dibs.RCLootCouncil.initialized = true
  return true
end

function Dibs.RCLootCouncil.TryUseRCModule()
  Dibs.RCLootCouncil.Initialize()
  return false
end

function Dibs.RCLootCouncil.GetLocalStatus()
  return { availability = Dibs.RCLootCouncil.GetAvailability(), protocolVersion = Dibs.PROTOCOL_VERSION, initialized = Dibs.RCLootCouncil.initialized == true }
end
