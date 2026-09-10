local Dibs = _G.Dibs
Dibs.RCLootCouncil = Dibs.RCLootCouncil or {}

-- Change log 0.4.0-dev (2026-09-10): add backup/import/profile data tools and
-- keep operational searches, history,
-- reports, and statistics in modeless control-center windows; preserve item
-- context for explicit Adventure Guide navigation from reconciliation rows.
-- Change log 0.3.13-dev (2026-09-09): use MSA dropdowns for lightweight
-- Officer choices, normalize compact history item tokens, cache bounded
-- history indexes, and page reconciliation rows to keep previews responsive.
-- Change log 0.3.12-dev (2026-09-09): use the RCLootCouncil history bucket
-- (the awarded player) as the winner; preserve the original loot owner as
-- separate evidence so traded awards cannot be attributed to the looter.
-- Change log 0.3.5 (2026-09-09): keep personal Catalyst items outside
-- the Dibs policy, resolve the broader RCLC Catalyst Items group by metadata,
-- and classify class set tokens as TOKEN_SET.
-- Change log 0.3.4-dev (2026-09-07): add the addon logo to metadata and
-- AceGUI windows while keeping the original source image in docs/assets.
-- Change log 0.3.3-dev (2026-09-07): treat wildcard AceDB defaults as
-- inherited values instead of repeatedly deleting a phantom legacy DIB key.
-- Change log 0.3.2-dev (2026-09-07): keep native Retail Settings category
-- ownership intact so RCLootCouncil Master Looter tabs remain selectable.
-- Also keep the eagerly-created Dibs windows hidden until explicitly opened,
-- preventing their dialog frame from intercepting Settings clicks.
-- Change log 0.3.1-dev (2026-09-07): reuse injected loot buttons after RC
-- rebuilds its entry list and avoid repeated frame creation during updates.
-- Change log 0.3.0-dev (2026-09-07): correct lib-st cell arguments, release
-- UI references after refresh, and keep slash/status output visible.
-- Change log 0.2.7-dev (2026-09-07): stabilize the options refresh path,
-- resolve candidate identities for the Dibs voting column, and bound malformed
-- response counts before iterating saved configuration.

local function text(key, fallback) return (Dibs.L and Dibs.L[key]) or fallback end

local function getRCAddon()
  if type(LibStub) == "function" or type(LibStub) == "table" then
    local okStub, aceAddon = pcall(LibStub, "AceAddon-3.0", true)
    if okStub and aceAddon and type(aceAddon.GetAddon) == "function" then
      for _, addonName in ipairs({ "RCLootCouncil", "RCLootCouncil2" }) do
        local okAddon, addon = pcall(aceAddon.GetAddon, aceAddon, addonName, true)
        if okAddon and type(addon) == "table" then
          return addon
        end
      end
    end
  end
  -- Some packaged builds do not expose AceAddon through LibStub, while the
  -- global addon object is still available. Keep that supported fallback.
  return type(_G.RCLootCouncil) == "table" and _G.RCLootCouncil
    or (type(_G.RCLootCouncil2) == "table" and _G.RCLootCouncil2 or nil)
end

local function isLoaded()
  if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
    local ok, first, second = pcall(C_AddOns.IsAddOnLoaded, "RCLootCouncil")
    if ok and (second == true or first == true) then return true end
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
  local valueText = tostring(value or "default")
  if valueText == "" then
    valueText = "default"
  end
  return valueText
end

local canonicalPolicyKey

local function isCatalystButtonSetType(value)
  local key = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  key = string.upper(key)
  key = key:gsub("[%s%-]", "_")
  return key == "CATALYST_ITEMS" or key == "CATALYSTITEMS"
end

local function isPersonalNonDibType(value)
  local key = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  key = string.upper(key)
  key = key:gsub("[%s%-]", "_")
  return key == "CATALYST" or key == "CATALYSTS"
end

local function isCosmeticNonDibType(value)
  local key = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  key = string.upper(key)
  key = key:gsub("[%s%-]", "_")
  return key == "COSMETIC" or key == "COSMETIC_ITEMS" or key == "COSMETICITEMS"
end

local function isPersonalOrCosmeticNonDibType(value)
  return isPersonalNonDibType(value) or isCosmeticNonDibType(value)
end

local function isNonDibPolicyType(value)
  return isPersonalOrCosmeticNonDibType(value) or isCatalystButtonSetType(value)
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
  -- Catalyst currency is personal to the player. It can never be a Dibs
  -- response, consume a ledger entry, or be enabled by a saved policy.
  if isNonDibPolicyType(responseType) then
    return false
  end
  local key = canonicalPolicyKey(responseType)
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
  if isNonDibPolicyType(responseType) then
    return nil, "PERSONAL_ITEM_TYPE"
  end
  local key = canonicalPolicyKey(responseType)
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
  local valueText = tostring(value)
  if valueText == "" then return end
  if seen[valueText] then return end
  seen[valueText] = true
  table.insert(target, valueText)
end

local function normalizeKey(value)
  return string.lower(tostring(value or ""))
end

canonicalPolicyKey = function(value)
  local key = string.upper(tostring(value or ""))
  key = key:gsub("[%s%-]", "_")
  if key == "" or key == "DEFAULT" then
    return "default"
  end
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
  if key == "TOKEN_SET" or key == "TOKEN_SETS" or key == "TOKENSET" then
    return "TOKEN_SET"
  end
  if key == "CATALYST" or key == "CATALYSTS" then
    return "CATALYST"
  end
  if key == "OTHER" or key == "OTHERS" then
    return "OTHER"
  end
  if key == "ARMOR_TOKEN" or key == "ARMORTOKEN" then
    return "TOKEN_SET"
  end
  if key == "RECIPE_PATTERN" or key == "RECIPEPATTERN" then
    return "RECIPE"
  end
  if key == "RARE_ITEMS" or key == "RAREITEMS" or key == "SPECIAL_EFFECTS" or key == "SPECIAL_EFFECTS_ITEMS" or key == "SPECIALEFFECTSITEMS" then
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
          addTypeCandidate(values, seen, "TOKEN_SET")
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
  if targetItem and type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
    local _, itemClassName, itemSubClassName, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(targetItem)
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

    -- Miscellaneous (class 15) also contains Tier Set tokens on Retail. Let
    -- RCLootCouncil's token table win before treating the remaining items as
    -- mount collection entries.
    local isKnownTierSetToken = targetItem and type(_G.RCTokenTable) == "table"
      and _G.RCTokenTable[targetItem] ~= nil
    if tonumber(classID) == 15 and not isKnownTierSetToken then
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
    -- Retail exposes Curios as Context Tokens. Use the stable numeric item
    -- class/subclass pair as well as localized names so French and other
    -- clients classify the item identically.
    if (tonumber(classID) == 5 and tonumber(subClassID) == 2)
      or classLower:find("context token", 1, true)
      or subclassLower:find("context token", 1, true)
    then
      addTypeCandidate(values, seen, "TOKEN")
    end

    -- RCLootCouncil's token table is the authoritative class-token list when
    -- it is available. This covers tier tokens whose localized tooltip text
    -- is not available yet or differs between clients.
    if targetItem and type(_G.RCTokenTable) == "table" and _G.RCTokenTable[targetItem] then
      addTypeCandidate(values, seen, "TOKEN_SET")
    end
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

    -- Equipment-slot groups are compatibility routing hints, not separate
    -- Dibs families. Give ordinary weapons, armor and other unclassified
    -- tradeable loot the configurable OTHER family so the Standard loot
    -- preset actually covers normal gear while a slot-specific rule can still
    -- override it when a guild needs one.
    local hasSemanticFamily = false
    for _, candidate in ipairs(values) do
      local canonical = canonicalPolicyKey(candidate)
      if canonical == "TOKEN" or canonical == "TOKEN_SET"
        or canonical == "MOUNTS" or canonical == "PETS"
        or canonical == "RECIPE" or canonical == "DECOR"
        or canonical == "OTHER" or canonical == "COSMETIC"
      then
        hasSemanticFamily = true
        break
      end
    end
    if not hasSemanticFamily then
      addTypeCandidate(values, seen, "OTHER")
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
  TOKEN_SET = true,
  RECIPE = true,
  OTHER = true,
}

local PRIORITY_CATEGORY_ORDER = {
  "TOKEN",
  "TOKEN_SET",
  "MOUNTS",
  "PETS",
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
  local hasProgressionToken = false
  for _, candidate in ipairs(candidates) do
    local canonical = canonicalPolicyKey(candidate)
    if canonical == "TOKEN" or canonical == "TOKEN_SET" then
      hasProgressionToken = true
      break
    end
  end
  for _, candidate in ipairs(candidates) do
    -- Some RCLootCouncil releases use the label `CATALYST` for the broader
    -- button group. Keep that path available only when stable item metadata
    -- already classified the item as a Curio or Tier Set token; a personal
    -- Catalyst item never receives either progression candidate.
    if isCosmeticNonDibType(candidate) then
      typeAllowanceCache[cacheKey] = { value = false, at = now }
      return false
    end
    if isPersonalNonDibType(candidate) and not hasProgressionToken then
      typeAllowanceCache[cacheKey] = { value = false, at = now }
      return false
    end
    -- RCLootCouncil's Catalyst Items button set is broader than the personal
    -- Catalyst resource: Context-token Curios and class Tier Set tokens may be
    -- assigned to that set. Let their semantic candidates win, but fail closed
    -- when the item has no recognised progression token family.
    if isCatalystButtonSetType(candidate) and not hasProgressionToken then
      typeAllowanceCache[cacheKey] = { value = false, at = now }
      return false
    end
  end
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
local FORCED_DIB_MAX_BUTTONS = 10

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

  local function addContainer(candidate)
    if type(candidate) ~= "table" then return end
    if type(candidate.profile) == "table" then
      add(candidate.profile)
    end
    -- Older forks expose the active profile directly on `db` or `profile`.
    if candidate.buttons ~= nil or candidate.responses ~= nil or candidate.enabledButtons ~= nil then
      add(candidate)
    end
  end

  local ml = getRCMLModule(rc)
  if ml then
    addContainer(ml.db)
    addContainer(ml.profile)
    for _, methodName in ipairs({ "Getdb", "GetDB" }) do
      if type(ml[methodName]) == "function" then
        local ok, db = pcall(ml[methodName], ml)
        if ok then addContainer(db) end
      end
    end
  end

  if type(rc) == "table" then
    for _, methodName in ipairs({ "Getdb", "GetDB" }) do
      if type(rc[methodName]) == "function" then
        local ok, db = pcall(rc[methodName], rc)
        if ok then addContainer(db) end
      end
    end
    addContainer(rc.db)
    addContainer(rc.profile)
  end

  if type(rc) == "table" and type(rc.mldb) == "table" then
    addContainer(rc.mldb)
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
  -- Accept the canonical response with harmless display punctuation (for
  -- example "[DIB]") while rejecting descriptive or mixed responses that
  -- could be mistaken for an explicit DIB decision.
  label = label:gsub("^[%p%s]+", ""):gsub("[%p%s]+$", "")
  return label == "DIB" or label == "DIBS"
end

local function responseFieldValues(value)
  if type(value) ~= "table" then return { value } end
  local values = {}
  for _, key in ipairs({ "text", "responseText", "response", "name", "label", "value" }) do
    if value[key] ~= nil then table.insert(values, value[key]) end
  end
  return values
end

local function normalizeDibResponse(value, rc, responseType)
  local candidate = value
  if (type(candidate) == "number" or (type(candidate) == "string" and candidate:match("^%s*%d+%s*$")))
    and type(rc) == "table" and type(rc.GetResponse) == "function" then
    local ok, response = pcall(rc.GetResponse, rc, responseType or "default", tonumber(candidate))
    if ok then candidate = response end
  end

  local found = nil
  local values = responseFieldValues(candidate)
  for _, item in ipairs(values) do
    if isDibLabel(item) then
      if found and found ~= "DIB" then return nil, "AMBIGUOUS_RESPONSE" end
      found = "DIB"
    elseif type(item) == "string" and normalizeButtonLabel(item) ~= "" then
      if found then return nil, "AMBIGUOUS_RESPONSE" end
      found = false
    end
  end
  if found == "DIB" then return "DIB" end
  if found == false then return nil, "NON_DIB_RESPONSE" end
  return nil, "EMPTY_RESPONSE"
end

function Dibs.RCLootCouncil.NormalizeDibResponse(value, responseType)
  return normalizeDibResponse(value, getRC(), responseType)
end

function Dibs.RCLootCouncil.IsDibResponse(value)
  local normalized = normalizeDibResponse(value, nil)
  return normalized == "DIB"
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

local function trimArrayToCount(list, count)
  if type(list) ~= "table" then return end
  while #list > count do
    list[#list] = nil
  end
end

local function findDibButtonIndex(buttons, activeCount)
  if type(buttons) ~= "table" then return nil end
  local count = tonumber(activeCount) or math.max(#buttons, tonumber(buttons.numButtons) or 0)
  for index = 1, count do
    local button = buttons[index]
    if type(button) == "table" and (button.dibsLocked == true or isDibLabel(button.text)) then
      return index
    end
  end
  return nil
end

local function findDibResponseIndex(responses, activeCount)
  if type(responses) ~= "table" then return nil end
  local count = tonumber(activeCount) or math.max(#responses, tonumber(responses.numButtons) or 0)
  for index = 1, count do
    local response = responses[index]
    if type(response) == "table" and isDibLabel(response.text) then
      return index
    end
  end
  return nil
end

local function ensureForcedDibForSet(buttons, responses, maxButtons)
  if type(buttons) ~= "table" or type(responses) ~= "table" then return false end
  local changed = false
  -- RCLootCouncil keeps default entries for all maxButtons slots even when
  -- only the first few are active. Use numButtons as the active count so those
  -- inactive defaults do not falsely report a full configuration.
  maxButtons = math.max(1, math.min(FORCED_DIB_MAX_BUTTONS, math.floor(tonumber(maxButtons) or FORCED_DIB_MAX_BUTTONS)))
  local configuredCount = tonumber(buttons.numButtons)
  if configuredCount == nil then
    configuredCount = math.max(#buttons, #responses)
  end
  configuredCount = math.max(0, math.min(maxButtons, math.floor(configuredCount)))
  -- SavedVariables are user-editable and may contain a stale or corrupted
  -- button count. Bound it before iterating so malformed data cannot make the
  -- adapter spend unbounded time allocating response entries.
  if tonumber(buttons.numButtons) ~= configuredCount then
    buttons.numButtons = configuredCount
    changed = true
  end

  -- A newly enabled additional set can have only its `enabledButtons` marker.
  -- Populate the active prefix before the DIB insertion so RCLootCouncil's
  -- dynamic options builder can safely read every parallel entry.
  for index = 1, configuredCount do
    if type(buttons[index]) ~= "table" then
      buttons[index] = { text = "Button " .. tostring(index), whisperKey = tostring(index) }
      changed = true
    end
    if type(responses[index]) ~= "table" then
      responses[index] = {
        text = buttons[index].text or ("Button " .. tostring(index)),
        color = { 0.7, 0.7, 0.7, 1 },
        sort = index,
      }
      changed = true
    end
  end

  -- Buttons and responses are parallel arrays. Move the pair together so an
  -- existing response can never be associated with the wrong button.
  local existingIndex = findDibButtonIndex(buttons, configuredCount)
    or findDibResponseIndex(responses, configuredCount)
  if existingIndex and existingIndex ~= FORCED_DIB_BUTTON_INDEX then
    local existingButton = buttons[existingIndex]
    local existingResponse = responses[existingIndex]
    removeArrayIndex(buttons, existingIndex)
    removeArrayIndex(responses, existingIndex)
    if existingButton ~= nil then insertAtFront(buttons, existingButton) end
    if existingResponse ~= nil then insertAtFront(responses, existingResponse) end
    changed = true
  elseif not existingIndex then
    -- Never overwrite a user response just to make room for DIB. RCLootCouncil
    -- exposes maxButtons (normally 10); when that limit is full, the runtime
    -- button remains the safe fallback and the user's configured responses are
    -- left untouched.
    if configuredCount >= maxButtons then return false, "DIB_BUTTON_CAPACITY" end
    buttons.numButtons = configuredCount + 1
    configuredCount = configuredCount + 1
    insertAtFront(buttons, {})
    insertAtFront(responses, {})
    -- Keep the inactive default tail bounded by RCLootCouncil's own limit;
    -- all active entries are before this boundary and remain intact.
    trimArrayToCount(buttons, maxButtons)
    trimArrayToCount(responses, maxButtons)
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

  -- RCLootCouncil reads the indexed response array. A keyed `responses.DIB`
  -- entry is not part of its schema and makes the additional-button discovery
  -- code treat DIB as a loot slot, so remove the legacy projection if present.
  -- AceDB wildcard defaults can make `responses.DIB` look present through a
  -- metatable even when no raw legacy entry exists.  Use rawget so the
  -- cleanup is idempotent; otherwise every watcher pass would report a
  -- change, notify AceConfig, and reset the Settings scroll position.
  if rawget(responses, "DIB") ~= nil then
    responses.DIB = nil
    changed = true
  end

  local buttonCount = tonumber(buttons.numButtons) or 0
  if buttonCount < configuredCount then
    buttons.numButtons = configuredCount
    changed = true
  elseif buttonCount < FORCED_DIB_BUTTON_INDEX then
    buttons.numButtons = FORCED_DIB_BUTTON_INDEX
    changed = true
  end

  -- RCLootCouncil treats response sort as the stable array order. Keep the
  -- surviving active responses ordered after moving/inserting DIB.
  for index = 1, configuredCount do
    if type(responses[index]) == "table" and tonumber(responses[index].sort) ~= index then
      responses[index].sort = index
      changed = true
    end
  end

  return changed, nil
end

local removeDibFromSet

local function ensureForcedDibConfigForDB(db)
  if type(db) ~= "table" then return false end

  db.buttons = db.buttons or {}
  db.responses = db.responses or {}
  db.buttons.default = db.buttons.default or {}
  db.responses.default = db.responses.default or {}

  local changed = false
  local maxButtons = math.max(1, math.min(FORCED_DIB_MAX_BUTTONS, math.floor(tonumber(db.maxButtons) or FORCED_DIB_MAX_BUTTONS)))

  if ensureForcedDibForSet(db.buttons.default, db.responses.default, maxButtons) then
    changed = true
  end

  -- Additional button sets are enabled through `enabledButtons` and may be
  -- created lazily by RCLootCouncil's options page. Walk the union of all
  -- three registries so a newly enabled slot receives a complete pair of
  -- arrays even when one side has not been initialized yet.
  local typeKeys = {}
  local function collectTypeKeys(source, onlyEnabled)
    if type(source) ~= "table" then return end
    for typeKey, value in pairs(source) do
      if type(typeKey) == "string"
        and typeKey ~= "default"
        and typeKey ~= "*"
        and typeKey ~= "**"
        and (not onlyEnabled or value == true)
      then
        typeKeys[typeKey] = true
      end
    end
  end
  collectTypeKeys(db.enabledButtons, true)
  collectTypeKeys(db.buttons, false)
  collectTypeKeys(db.responses, false)

  for typeKey in pairs(typeKeys) do
    local typeButtons = db.buttons[typeKey]
    local typeResponses = db.responses[typeKey]
    if isPersonalOrCosmeticNonDibType(typeKey) then
      -- Do not create or retain an adapter-owned DIB response in a personal
      -- Catalyst button set. Existing stale projections are removed once.
      if removeDibFromSet(typeButtons, typeResponses) then
        changed = true
      end
    else
      if type(typeButtons) ~= "table" then
        typeButtons = {}
        db.buttons[typeKey] = typeButtons
      end
      if type(typeResponses) ~= "table" then
        typeResponses = {}
        db.responses[typeKey] = typeResponses
      end
      if tonumber(typeButtons.numButtons) == nil then
        local existingEntries = math.max(#typeButtons, #typeResponses)
        local defaultCount = tonumber(db.buttons.default.numButtons) or 1
        -- A newly enabled set should have the same final active count as the
        -- default set. Reserve one slot for the DIB that is added below.
        typeButtons.numButtons = existingEntries > 0
          and existingEntries
          or math.max(0, defaultCount - 1)
        changed = true
      end
      if ensureForcedDibForSet(typeButtons, typeResponses, maxButtons) then
        changed = true
      end
    end
  end

  return changed
end

local function alwaysDisabled()
  return true
end

local FORCED_DIB_OPTION_KEYS = {
  "button1", "picker1", "text1", "requireNotes1", "move_up1", "move_down1",
}

local function forceDisableOption(option)
  if type(option) ~= "table" then return false end
  -- The options lock is checked by the lifecycle watcher.  Do not allocate a
  -- new closure on every pass: that retained one closure per option and made
  -- the addon grow continuously while the game was running.
  if option.__dibsForcedDisabled == true and option.disabled == alwaysDisabled then
    return false
  end
  option.disabled = alwaysDisabled
  option.__dibsForcedDisabled = true
  return true
end

local function lockButtonOptionArgs(args, index)
  if type(args) ~= "table" then return false end
  local changed = false
  local keys = index == FORCED_DIB_BUTTON_INDEX and FORCED_DIB_OPTION_KEYS or {
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
        and not isPersonalOrCosmeticNonDibType(groupKey)
        and type(groupOption) == "table"
        and type(groupOption.args) == "table"
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
local deferForcedDibRefresh

local function notifyForcedDibConfigChanged(rc)
  local changedKeys = { buttons = true, responses = true }
  local ml = getRCMLModule(rc)
  -- Prefer the core method: it broadcasts the change to the ML module after
  -- it is enabled. Calling ML:ConfigTableChanged directly during startup can
  -- run UpdateMLdb before its runtime state exists.
  local owner = type(rc.ConfigTableChanged) == "function" and rc or ml
  if type(owner) == "table" and type(owner.ConfigTableChanged) == "function" then
    pcall(owner.ConfigTableChanged, owner, changedKeys)
    return true
  end
  return false
end

local function startForcedConfigWatcher()
  if Dibs.RCLootCouncil.configWatcherActive or Dibs.RCLootCouncil.configWatcherStopped then return end
  if not C_Timer or type(C_Timer.After) ~= "function" then return end

  Dibs.RCLootCouncil.configWatcherActive = true
  local attempts = 0
  local maxAttempts = 40
  local function tick()
    if not Dibs.RCLootCouncil.configWatcherActive then
      return
    end
    attempts = attempts + 1
    local rc = getRC()
    if type(rc) == "table" then
      local changed = ensureForcedDibConfig(rc, true)
      if changed then notifyForcedDibConfigChanged(rc) end
      ensureForcedDibOptionsLock(rc)
    end
    if attempts >= maxAttempts then
      Dibs.RCLootCouncil.configWatcherActive = false
      Dibs.RCLootCouncil.configWatcherStopped = true
      return
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

  if changed then
    -- Keep this bit separate from the RC message.  RCLootCouncil may rebuild
    -- its AceConfig table after the message has fired, so the deferred pass
    -- can request exactly one registry refresh without doing it every tick.
    Dibs.RCLootCouncil.forcedDibOptionsRefreshPending = true
  end

  if changed and not suppressNotify then
    -- ConfigTableChanged expects a table of changed keys. Passing a string
    -- works in neither the core nor ML module (both iterate it with pairs),
    -- which previously made the projection fail silently in the live addon.
    notifyForcedDibConfigChanged(rc)
  end

  return changed
end

local function getProjectionSetStatus(buttons, responses)
  if type(buttons) ~= "table" or type(responses) ~= "table" then
    return nil
  end
  local activeCount = tonumber(buttons.numButtons) or math.max(#buttons, #responses)
  activeCount = math.max(0, math.min(FORCED_DIB_MAX_BUTTONS, math.floor(activeCount)))
  return {
    activeButtons = activeCount,
    buttonDibIndex = findDibButtonIndex(buttons, activeCount),
    responseDibIndex = findDibResponseIndex(responses, activeCount),
    buttonOneText = type(buttons[1]) == "table" and buttons[1].text or nil,
    responseOneText = type(responses[1]) == "table" and responses[1].text or nil,
  }
end

local function getProjectionStatus(rc)
  local status = {
    addonFound = type(rc) == "table",
    profileCount = 0,
    default = nil,
    additional = {},
  }
  if not status.addonFound then return status end

  local function addAdditionalKeys(target, source)
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
      if type(key) == "string" and key ~= "default" and key ~= "*" and key ~= "**" then
        target[key] = value
      end
    end
  end

  for _, db in ipairs(collectRCDBs(rc)) do
    status.profileCount = status.profileCount + 1
    if not status.default then
      status.default = getProjectionSetStatus(db.buttons and db.buttons.default, db.responses and db.responses.default)
    end
    local keys = {}
    addAdditionalKeys(keys, db.enabledButtons)
    addAdditionalKeys(keys, db.buttons)
    addAdditionalKeys(keys, db.responses)
    for key in pairs(keys) do
      local entry = getProjectionSetStatus(db.buttons and db.buttons[key], db.responses and db.responses[key])
      if entry then
        entry.enabled = db.enabledButtons and db.enabledButtons[key] == true or false
        status.additional[key] = entry
      end
    end
  end
  return status
end

function Dibs.RCLootCouncil.GetConfigProjectionStatus()
  return getProjectionStatus(getRC())
end

function Dibs.RCLootCouncil.RefreshConfigProjection()
  local rc = getRC()
  if type(rc) ~= "table" then
    return false, "RC_INSTANCE_UNAVAILABLE"
  end
  local changed = ensureForcedDibConfig(rc, false)
  ensureForcedDibOptionsLock(rc)
  deferForcedDibRefresh(rc, true)
  return true, changed == true
end

deferForcedDibRefresh = function(rc, notifyConfig)
  if Dibs.RCLootCouncil.forcedDibRefreshPending then return end
  Dibs.RCLootCouncil.forcedDibRefreshPending = true
  local function refresh()
    Dibs.RCLootCouncil.forcedDibRefreshPending = nil
    local changed = ensureForcedDibConfig(rc, true)
    if changed and notifyConfig ~= false then
      notifyForcedDibConfigChanged(rc)
    end
    ensureForcedDibOptionsLock(rc)
    local pendingOptionsRefresh = Dibs.RCLootCouncil.forcedDibOptionsRefreshPending == true
    Dibs.RCLootCouncil.forcedDibOptionsRefreshPending = nil
    if notifyConfig == false or not pendingOptionsRefresh
      or (type(LibStub) ~= "function" and type(LibStub) ~= "table") then return end
    local okRegistry, registry = pcall(LibStub, "AceConfigRegistry-3.0", true)
    if okRegistry and type(registry) == "table" and type(registry.NotifyChange) == "function" then
      -- A late-loaded RC may have already built its options table before the
      -- profile became available. Ask AceConfig to rebuild those dynamic
      -- button fields after the safe deferred mutation.
      pcall(registry.NotifyChange, registry, "RCLootCouncil")
    end
  end
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, refresh)
  else
    refresh()
  end
end

local function hookForcedDibLifecycle(owner, methodName, rc)
  if type(owner) ~= "table" or type(hooksecurefunc) ~= "function" then return false end
  if type(owner[methodName]) ~= "function" then return false end
  local marker = "__dibsForcedDibHooked_" .. tostring(methodName)
  if owner[marker] then return true end

  local ok = pcall(hooksecurefunc, owner, methodName, function()
    -- RCLootCouncil rebuilds its AceDB profile and ML database from these
    -- lifecycle methods. Reapply after the original method has completed so
    -- the projection survives profile changes, /reload, and late module load.
    deferForcedDibRefresh(rc, true)
  end)
  if not ok then return false end
  owner[marker] = true
  return true
end

local function hookConfigChanged(owner, rc)
  if type(owner) ~= "table" or type(hooksecurefunc) ~= "function" then return false end
  if owner.__dibsConfigHooked then return true end
  if type(owner.ConfigTableChanged) ~= "function" then return false end

  hooksecurefunc(owner, "ConfigTableChanged", function() deferForcedDibRefresh(rc) end)
  owner.__dibsConfigHooked = true
  return true
end

local function installForcedDibConfigHook()
  local rc = getRC()
  if type(rc) ~= "table" then return false end

  -- Loot-frame Update can run once per visible item.  Once the current RC
  -- profile has been found and lifecycle hooks are installed, do not schedule
  -- another deferred projection pass from every update.
  if Dibs.RCLootCouncil.forcedConfigHookOwner == rc
    and Dibs.RCLootCouncil.forcedConfigHookReady == true
  then
    return true
  end

  local ml = getRCMLModule(rc)
  local configReady = #collectRCDBs(rc) > 0
  local lifecycleHooked = false
  for _, methodName in ipairs({ "OnInitialize", "OnEnable", "UpdateDB", "OptionsTable" }) do
    lifecycleHooked = hookForcedDibLifecycle(rc, methodName, rc) or lifecycleHooked
    lifecycleHooked = hookForcedDibLifecycle(ml, methodName, rc) or lifecycleHooked
  end

  ensureForcedDibConfig(rc, false)
  ensureForcedDibOptionsLock(rc)
  deferForcedDibRefresh(rc, true)
  startForcedConfigWatcher()
  local rcHooked = hookConfigChanged(rc, rc)
  local mlHooked = hookConfigChanged(ml, rc)
  local ready = configReady or lifecycleHooked or rcHooked or mlHooked
  if ready then
    Dibs.RCLootCouncil.forcedConfigHookOwner = rc
    Dibs.RCLootCouncil.forcedConfigHookReady = true
  end
  return ready
end

local function parseItemID(itemLink)
  if not itemLink then return nil end
  return tonumber(tostring(itemLink):match("item:(%d+)"))
end

-- Pure award validation shared by the live callback and local dry-run.  This
-- function deliberately reads the current policy only; it never consumes a
-- Dib, writes history, sends an RCLootCouncil response, or invokes a protected
-- action.
function Dibs.RCLootCouncil.ValidateAwardInput(payload)
  payload = type(payload) == "table" and payload or {}
  local itemID = tonumber(payload.itemID) or parseItemID(payload.itemLink or payload.item)
  if not itemID then return { ok = false, reasonCode = "AWARD_INVALID_ITEM" } end
  if payload.winner == nil or tostring(payload.winner) == "" then
    return { ok = false, reasonCode = "AWARD_INVALID_WINNER" }
  end
  local status = string.lower(tostring(payload.status or ""))
  if status == "test" or status == "test_mode" then
    return { ok = false, reasonCode = "AWARD_TEST_MODE", itemID = itemID }
  end
  local normalized, responseReason = normalizeDibResponse(payload.response or payload.responseText, getRC(), payload.responseType)
  if normalized ~= "DIB" then
    return { ok = false, reasonCode = responseReason or "NON_DIB_RESPONSE", itemID = itemID }
  end
  if not Dibs.RCLootCouncil.IsItemDibTypeAllowed(itemID, payload.responseType) then
    return { ok = false, reasonCode = "AWARD_PERSONAL_ITEM", itemID = itemID, response = normalized }
  end
  if payload.requireIdentity == true then
    local identity = payload.awardRef or payload.sessionIdentity or payload.sessionId
    if identity == nil or tostring(identity) == "" then
      return { ok = false, reasonCode = "AWARD_IDENTITY_UNAVAILABLE", itemID = itemID, response = normalized }
    end
  end
  return {
    ok = true,
    itemID = itemID,
    winner = tostring(payload.winner),
    response = normalized,
    responseType = payload.responseType,
    status = status,
  }
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

  -- RCLootCouncil may rebuild `entry.buttons` on every loot-frame update.
  -- Keep the injected frame attached to the entry and restore it to the new
  -- list instead of creating another button (and another closure) each time.
  local remembered = entry.dibsButton
  if isDibsButton(remembered) then
    local present = false
    for _, button in ipairs(entry.buttons) do
      if button == remembered then
        present = true
        break
      end
    end
    if not present then
      table.insert(entry.buttons, 1, remembered)
    end
    remembered.dibsButton = true
    installDibsTooltip(remembered, entry)
    return remembered
  end

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

local function buildFallbackItemLink(itemID, itemName)
  local id = tonumber(itemID) or 0
  local label = tostring(itemName or ("Item " .. tostring(id)))
  return string.format("|cffffffff|Hitem:%d::::::::::::|h[%s]|h|r", id, label)
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
        if showDibs and status.dibTypeEnabled == true then
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

local function cleanCandidateIdentity(value)
  if value == nil then return nil end
  local valueText = tostring(value)
  if valueText == "" then return nil end

  -- RCLootCouncil normally stores a plain name, but some versions expose a
  -- class-coloured or player-hyperlink value in the scrolling table.  Ledger
  -- keys must use the actual player identity, never the display markup.
  local linkedName = valueText:match("|Hplayer:([^:|]+)")
  if linkedName and linkedName ~= "" then
    return linkedName
  end
  valueText = valueText:gsub("|c%x%x%x%x%x%x%x%x", "")
    :gsub("|r", "")
    :gsub("|T.-|t", "")
    :gsub("|H.-|h", "")
    :gsub("|h", "")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
  valueText = valueText:gsub("^%[(.-)%]$", "%1")
  return valueText ~= "" and valueText or nil
end

local CANDIDATE_IDENTITY_KEYS = {
  "name", "playerName", "player", "playerGuid", "guid", "playerKey", "key", "id",
}

local function getCandidateIdentity(rowData)
  if type(rowData) == "string" then
    return cleanCandidateIdentity(rowData)
  end
  if type(rowData) ~= "table" then return nil end

  -- `name` is the official RCLootCouncil row key.  The other fields keep the
  -- integration compatible with forks that expose the GUID under a different
  -- field while building the same scrolling table.
  for _, key in ipairs(CANDIDATE_IDENTITY_KEYS) do
    local identity = cleanCandidateIdentity(rowData[key])
    if identity then return identity end
  end
  return nil
end

local function getRemainingDibsText(playerName)
  if not playerName or not Dibs.Ledger then
    return "0/0", 0
  end
  local seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
  local state
  if type(Dibs.Ledger.GetPlayerSeasonState) == "function" then
    local ok, value = pcall(Dibs.Ledger.GetPlayerSeasonState, seasonId, playerName)
    if ok and type(value) == "table" then state = value end
  end
  local remaining = tonumber(state and state.remainingBalance)
  local maximum = tonumber(state and state.baseAllocation)
  local historyCount = tonumber(state and state.historySummary and state.historySummary.count) or 0
  -- A guild member can appear in the RCLootCouncil voting table before the
  -- Dibs ledger has created a per-player state.  In that case the rank rule is
  -- the authoritative initial allocation and should be visible immediately.
  if maximum == 0 and historyCount == 0
    and Dibs.RankRules and type(Dibs.RankRules.GetAllocationForPlayer) == "function"
  then
    local ok, rankAllocation = pcall(Dibs.RankRules.GetAllocationForPlayer, playerName, seasonId)
    if ok and tonumber(rankAllocation) then
      maximum = tonumber(rankAllocation)
      remaining = maximum
    end
  end
  if remaining == nil and type(Dibs.Ledger.GetBalance) == "function" then
    local ok, value = pcall(Dibs.Ledger.GetBalance, playerName, seasonId)
    if ok then remaining = tonumber(value) end
  end
  remaining = remaining or 0
  maximum = maximum or 0
  return formatCount(remaining) .. "/" .. formatCount(maximum), remaining
end

local function setDibsColumnCell(rowFrame, cellFrame, data, cols, row, realrow, column, fShow, tableArg)
  if not fShow or not data or not data[realrow] or not cellFrame or not cellFrame.text then return end
  local textValue, sortValue = Dibs.RCLootCouncil.GetDibsColumnValue(data[realrow])
  cellFrame.text:SetText(textValue)
  cellFrame.text:SetTextColor(1, 1, 1, 1)
  if data[realrow].cols and data[realrow].cols[column] then
    data[realrow].cols[column].value = sortValue
  end
end

-- Read-only adapter used by the voting-frame cell and diagnostics/tests.  It
-- deliberately accepts the complete row so the display keeps working when a
-- RCLootCouncil fork adds a GUID or hyperlink beside the official `name` key.
function Dibs.RCLootCouncil.GetDibsColumnValue(rowData)
  local candidateName = getCandidateIdentity(rowData)
  local textValue, sortValue = getRemainingDibsText(candidateName)
  return textValue, sortValue, candidateName
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

local function setDibConvertCell(rowFrame, cellFrame, data, cols, row, realrow, column, fShow, tableArg)
  if not fShow or not data or not data[realrow] or type(cellFrame) ~= "table" then return end
  local rc = getRC()
  local votingFrame = getVotingFrameModule(rc)
  if type(votingFrame) ~= "table" then return end
  local session, current = getVotingSessionInfo(votingFrame)
  if not session or not current then return end

  local candidateName = getCandidateIdentity(data[realrow])
  if not candidateName then return end
  local responseValue = type(votingFrame.GetCandidateData) == "function" and votingFrame:GetCandidateData(session, candidateName, "response") or nil
  local typeCode = current.typeCode or current.equipLoc or "default"
  local canConvert = responseIsDib(rc, typeCode, responseValue)
  local normalResponse = getFirstNormalResponse(rc, typeCode)

  local button = cellFrame.convertBtn
  if not button then
    button = CreateFrame("Button", nil, cellFrame, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", cellFrame, "TOPLEFT", 0, 0)
    button:SetPoint("BOTTOMRIGHT", cellFrame, "BOTTOMRIGHT", 0, 0)
    cellFrame.convertBtn = button
  end

  button:SetText("Normal")
  button.__dibsVotingFrame = votingFrame
  button.__dibsCandidateName = candidateName
  if not button.__dibsConvertHandlerInstalled then
    button:SetScript("OnClick", function(self)
      convertCandidateToNormal(self.__dibsVotingFrame, self.__dibsCandidateName)
    end)
    button.__dibsConvertHandlerInstalled = true
  end

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
    -- RCLootCouncil calls Update frequently while a session is active.  Once
    -- the scrolling table already uses this spec, refreshing it on every
    -- Update only rebuilds rows and creates avoidable garbage.
    if not rendered then
      refreshVotingColumns(votingFrame)
    end
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
    if not rendered then
      refreshVotingColumns(votingFrame)
    end
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
      local hasDibsColumn, hasConvertColumn = false, false
      for _, column in ipairs(votingFrame.scrollCols or {}) do
        if type(column) == "table" then
          hasDibsColumn = hasDibsColumn or column.colName == "dibsRemaining"
          hasConvertColumn = hasConvertColumn or column.colName == "dibsConvert"
        end
      end
      local tableHasDibs, tableHasConvert = false, false
      local tableView = votingFrame.frame and votingFrame.frame.st
      for _, column in ipairs(tableView and tableView.cols or {}) do
        if type(column) == "table" then
          tableHasDibs = tableHasDibs or column.colName == "dibsRemaining"
          tableHasConvert = tableHasConvert or column.colName == "dibsConvert"
        end
      end
      if hasDibsColumn and hasConvertColumn and tableHasDibs and tableHasConvert then
        return
      end
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
  local valueText = tostring(value)
  if not valueText:find("-", 1, true) and type(GetRealmName) == "function" then
    local realm = tostring(GetRealmName() or ""):gsub("[%s%-]", "")
    if realm ~= "" then valueText = valueText .. "-" .. realm end
  end
  return string.lower(valueText)
end

local function stableSessionIdentity(rc)
  if type(rc) ~= "table" then return nil end
  for _, key in ipairs({ "currentSessionId", "lootSessionId", "sessionID" }) do
    local value = rc[key]
    if (type(value) == "string" or type(value) == "number") and tostring(value) ~= "" then
      return tostring(value)
    end
  end
  return nil
end

local function hasHistoryIdentitySurface(rc)
  if type(rc) ~= "table" or type(rc.GetHistoryDB) ~= "function" then return false end
  local ok, historyDB = pcall(rc.GetHistoryDB, rc)
  return ok and type(historyDB) == "table"
end

local REASON_DIAGNOSTIC_KEYS = {
  RC_ABSENT = "RC_REASON_ABSENT",
  RC_DISABLED = "RC_REASON_DISABLED",
  RC_INSTANCE_UNAVAILABLE = "RC_REASON_INSTANCE_UNAVAILABLE",
  RC_ENABLED_STATE_UNVERIFIABLE = "RC_REASON_ENABLED_STATE_UNVERIFIABLE",
  RC_MASTER_LOOTER_UNVERIFIABLE = "RC_REASON_MASTER_LOOTER_UNVERIFIABLE",
  RC_AWARD_CALLBACK_UNAVAILABLE = "RC_REASON_AWARD_CALLBACK_UNAVAILABLE",
  RC_AWARD_IDENTITY_UNAVAILABLE = "RC_REASON_AWARD_IDENTITY_UNAVAILABLE",
  RC_RESPONSE_UNSUPPORTED = "RC_REASON_RESPONSE_UNSUPPORTED",
  RC_OPERATIONAL = "RC_REASON_OPERATIONAL",
  AWARD_INVALID = "AWARD_INVALID",
  NON_DIB_RESPONSE = "AWARD_NON_DIB_RESPONSE",
  AMBIGUOUS_RESPONSE = "AWARD_AMBIGUOUS_RESPONSE",
  EMPTY_RESPONSE = "AWARD_EMPTY_RESPONSE",
  AWARD_TEST_MODE = "AWARD_TEST_MODE",
  AWARD_INVALID_ITEM = "AWARD_INVALID_ITEM",
  AWARD_PERSONAL_ITEM = "AWARD_PERSONAL_ITEM",
  STANDALONE_MODE = "AWARD_STANDALONE_MODE",
  AWARD_IDENTITY_UNAVAILABLE = "AWARD_IDENTITY_UNAVAILABLE",
  AWARD_IDENTITY_AMBIGUOUS = "AWARD_IDENTITY_AMBIGUOUS",
  READINESS_BLOCKED = "READINESS_BLOCKED",
  HISTORY_IDENTITY_REQUIRED = "HISTORY_IDENTITY_REQUIRED",
  HISTORY_GUIDED_CONFIRM_REQUIRED = "HISTORY_GUIDED_CONFIRM_REQUIRED",
  HISTORY_MANUAL_ACK_REQUIRED = "HISTORY_MANUAL_ACK_REQUIRED",
  HISTORY_REASON_REQUIRED = "HISTORY_REASON_REQUIRED",
  HISTORY_NO_HISTORY = "HISTORY_NO_HISTORY",
  HISTORY_NO_ALIASES = "HISTORY_NO_ALIASES",
  HISTORY_INVALID_DATE_RANGE = "HISTORY_INVALID_DATE_RANGE",
  HISTORY_ALREADY_ACCOUNTED = "HISTORY_ALREADY_ACCOUNTED",
  HISTORY_NON_FINAL = "HISTORY_NON_FINAL",
  HISTORY_UNSUPPORTED = "HISTORY_UNSUPPORTED",
  HISTORY_RESPONSE_IDENTITY_AMBIGUOUS = "HISTORY_RESPONSE_IDENTITY_AMBIGUOUS",
  HISTORY_REJECTED_BY_OFFICER = "HISTORY_REJECTED_BY_OFFICER",
  HISTORY_FINAL_STATUS_UNKNOWN = "HISTORY_FINAL_STATUS_UNKNOWN",
}

local REASON_DIAGNOSTIC_FALLBACKS = {
  RC_ABSENT = "RCLootCouncil is absent; Dibs is running in Standalone mode.",
  RC_DISABLED = "RCLootCouncil is disabled; Dibs is running in Standalone mode.",
  RC_INSTANCE_UNAVAILABLE = "RCLootCouncil was detected but its addon instance is unavailable.",
  RC_ENABLED_STATE_UNVERIFIABLE = "RCLootCouncil enabled state could not be verified.",
  RC_MASTER_LOOTER_UNVERIFIABLE = "The current RCLootCouncil Master Looter could not be verified.",
  RC_AWARD_CALLBACK_UNAVAILABLE = "RCLootCouncil does not expose the required award callback.",
  RC_AWARD_IDENTITY_UNAVAILABLE = "RCLootCouncil did not expose a stable award identity.",
  RC_RESPONSE_UNSUPPORTED = "RCLootCouncil response mapping is unsupported.",
  RC_OPERATIONAL = "RCLootCouncil integration is operational.",
  AWARD_INVALID = "The finalized award payload is incomplete.",
  NON_DIB_RESPONSE = "The award response was not an explicit DIB.",
  AMBIGUOUS_RESPONSE = "The award response contained conflicting values.",
  EMPTY_RESPONSE = "The award response was empty.",
  AWARD_TEST_MODE = "Test awards cannot consume production Dibs.",
  AWARD_INVALID_ITEM = "The award item identity is missing or malformed.",
  AWARD_PERSONAL_ITEM = "Personal Catalyst items cannot consume Dibs.",
  STANDALONE_MODE = "Automatic award accounting is disabled in Standalone mode.",
  AWARD_IDENTITY_UNAVAILABLE = "The finalized award identity could not be verified.",
  AWARD_IDENTITY_AMBIGUOUS = "More than one history entry matched this award; no Dib was consumed.",
  READINESS_BLOCKED = "Raid readiness blocked automatic Dibs consumption until the live award can be verified.",
  HISTORY_IDENTITY_REQUIRED = "A stable history identity is required.",
  HISTORY_GUIDED_CONFIRM_REQUIRED = "Guided confirmation requires a final award and an explicit response alias.",
  HISTORY_MANUAL_ACK_REQUIRED = "Manual confirmation requires explicit acknowledgement.",
  HISTORY_REASON_REQUIRED = "A reason is required for manual historical confirmation.",
  HISTORY_NO_HISTORY = "RCLootCouncil history is unavailable in this session.",
  HISTORY_NO_ALIASES = "Add at least one exact response alias before searching.",
  HISTORY_INVALID_DATE_RANGE = "The history date range is invalid.",
  HISTORY_ALREADY_ACCOUNTED = "This historical award is already accounted for.",
  HISTORY_NON_FINAL = "This history row is not a finalized award.",
  HISTORY_UNSUPPORTED = "This history row is missing a required identity.",
  HISTORY_RESPONSE_IDENTITY_AMBIGUOUS = "The response label maps to more than one RCLootCouncil response identity.",
  HISTORY_REJECTED_BY_OFFICER = "Rejected by an Officer during reconciliation.",
  HISTORY_FINAL_STATUS_UNKNOWN = "The finalization status is unavailable; manual review is required.",
}

local function reasonDiagnostic(reasonCode)
  local key = REASON_DIAGNOSTIC_KEYS[reasonCode]
  return text(key, REASON_DIAGNOSTIC_FALLBACKS[reasonCode] or tostring(reasonCode or "Integration action ignored."))
end

local function capabilitySnapshot()
  local snapshot = {
    state = "absent",
    checkedAt = nowSeconds(),
    addonLoaded = false,
    capabilities = {},
    reasonCode = nil,
    observedVersion = nil,
    compatibility = {
      supportedRelease = "RCLootCouncil Retail 3.x-shaped capability surface",
      historyReadOnly = true,
      liveSessionSync = false,
    },
  }

  if not isLoaded() then
    snapshot.reasonCode = "RC_ABSENT"
    return snapshot
  end
  snapshot.addonLoaded = true

  local rc = getRC()
  if type(rc) ~= "table" then
    snapshot.state = "degraded"
    snapshot.reasonCode = "RC_INSTANCE_UNAVAILABLE"
    return snapshot
  end
  snapshot.observedVersion = rc.version or rc.VERSION or rc.revision
  if rc.enabled == false then
    snapshot.reasonCode = "RC_DISABLED"
    return snapshot
  end
  if rc.enabled ~= true then
    snapshot.state = "degraded"
    snapshot.reasonCode = "RC_ENABLED_STATE_UNVERIFIABLE"
    return snapshot
  end

  snapshot.capabilities.discovery = true
  snapshot.capabilities.enabledState = true
  snapshot.capabilities.masterLooter = playerIdentity(rc.masterLooter) ~= nil
  snapshot.capabilities.awardCallback = type(rc.RegisterMessage) == "function"
    and Dibs.RCLootCouncil.callbackOwner == rc
  snapshot.capabilities.awardIdentity = hasHistoryIdentitySurface(rc)
    or stableSessionIdentity(rc) ~= nil
  snapshot.capabilities.responseValidation = type(Dibs.RCLootCouncil.IsDibResponse) == "function"

  if not snapshot.capabilities.masterLooter then
    snapshot.state = "degraded"
    snapshot.reasonCode = "RC_MASTER_LOOTER_UNVERIFIABLE"
  elseif not snapshot.capabilities.awardCallback then
    snapshot.state = "degraded"
    snapshot.reasonCode = "RC_AWARD_CALLBACK_UNAVAILABLE"
  elseif not snapshot.capabilities.awardIdentity then
    snapshot.state = "degraded"
    snapshot.reasonCode = "RC_AWARD_IDENTITY_UNAVAILABLE"
  elseif not snapshot.capabilities.responseValidation then
    snapshot.state = "unsupported"
    snapshot.reasonCode = "RC_RESPONSE_UNSUPPORTED"
  else
    snapshot.state = "operational"
    snapshot.reasonCode = "RC_OPERATIONAL"
  end
  return snapshot
end

function Dibs.RCLootCouncil.GetCapabilities()
  return capabilitySnapshot()
end

function Dibs.RCLootCouncil.GetAvailability()
  return capabilitySnapshot().state
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
  -- Resolve the semantic item family as well as the RCLC response type. This
  -- prevents a personal Catalyst item from falling through an equip-slot or
  -- default policy and receiving a Dibs action.
  local typeEnabled = Dibs.RCLootCouncil.IsItemDibTypeAllowed(targetItem, typeKey)
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

  local sessionKey = stableSessionIdentity(rc)
  local winnerId = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId
    and Dibs.Permissions.CanonicalPlayerId(winner) or playerNameIdentity(winner)
  if sessionKey and winnerId and tonumber(itemID) then
    return "session:" .. sessionKey .. ":" .. tostring(session or "unknown") .. ":"
      .. tostring(winnerId) .. ":" .. tostring(tonumber(itemID))
  end

  -- RCLootCouncil writes an immutable history id for completed awards. Use it only
  -- when exactly one matching row exists; choosing the newest matching row can map
  -- a delayed callback to a different award of the same item.
  if rc and type(rc.GetHistoryDB) == "function" then
    local ok, historyDB = pcall(rc.GetHistoryDB, rc)
    if ok and type(historyDB) == "table" then
      local matches = {}
      for playerKey, entries in pairs(historyDB) do
        if type(entries) == "table" and (not winnerId or not Dibs.Permissions or not Dibs.Permissions.CanonicalPlayerId
          or Dibs.Permissions.CanonicalPlayerId(playerKey) == winnerId) then
          for _, historyEntry in ipairs(entries) do
            if type(historyEntry) == "table" and historyEntry.id then
              local historyItem = historyEntry.lootWon or historyEntry.itemLink or historyEntry.item
              local historyItemId = tonumber(historyEntry.itemID) or parseItemID(historyItem)
              if historyItemId == tonumber(itemID) then
                table.insert(matches, "history:" .. tostring(historyEntry.id))
              end
            end
          end
        end
      end
      if #matches == 1 then
        return matches[1]
      elseif #matches > 1 then
        return nil, "AWARD_IDENTITY_AMBIGUOUS"
      end
    end
  end

  return nil, "AWARD_IDENTITY_UNAVAILABLE"
end

local function ignoredAward(reasonCode)
  local diagnostic = reasonDiagnostic(reasonCode)
  if Dibs.DebugLogs and type(Dibs.DebugLogs.Add) == "function" then
    Dibs.DebugLogs.Add("RCLootCouncil", 3, tostring(reasonCode or "INTEGRATION_IGNORED"))
  end
  return { ok = false, ignored = true, outcome = "ignored", reasonCode = reasonCode, diagnostic = diagnostic }
end

local function getAwardResponseType(rc, session)
  local sources = { rc, getRCMLModule(rc) }
  for _, source in ipairs(sources) do
    local lootTable = source and source.lootTable
    local entry = type(lootTable) == "table" and lootTable[tonumber(session)] or nil
    local item = entry and entry.item
    if type(item) == "table" then
      return item.typeCode or item.equipLoc or item.responseType
    end
  end
  return nil
end

removeDibFromSet = function(buttons, responses)
  if type(buttons) ~= "table" and type(responses) ~= "table" then return false end
  local activeCount = tonumber(buttons and buttons.numButtons)
    or tonumber(responses and responses.numButtons)
    or math.max(#(buttons or {}), #(responses or {}))
  local buttonIndex = findDibButtonIndex(buttons, activeCount)
  local responseIndex = findDibResponseIndex(responses, activeCount)
  if not buttonIndex and not responseIndex then return false end
  if buttonIndex then removeArrayIndex(buttons, buttonIndex) end
  if responseIndex then removeArrayIndex(responses, responseIndex) end
  if type(buttons) == "table" then buttons.numButtons = math.max(0, activeCount - 1) end
  if type(responses) == "table" then responses.numButtons = math.max(0, activeCount - 1) end
  return true
end

function Dibs.RCLootCouncil.OnAwardSuccess(_, session, winner, status, itemLink, responseText)
  if not Dibs.ProtectedActions or not winner or not itemLink then
    return ignoredAward("AWARD_INVALID")
  end
  local rc = getRC()
  local normalizedResponse, responseReason = normalizeDibResponse(responseText, rc)
  if not normalizedResponse then
    return ignoredAward(responseReason or "NON_DIB_RESPONSE")
  end
  local statusKey = string.lower(tostring(status or ""))
  if statusKey == "test_mode" or statusKey == "test" then
    return ignoredAward("AWARD_TEST_MODE")
  end
  local mode = Dibs.Permissions and Dibs.Permissions.GetInstallationMode and Dibs.Permissions.GetInstallationMode() or "AUTO"
  if mode == "STANDALONE" then return ignoredAward("STANDALONE_MODE") end
  local capabilities = capabilitySnapshot()
  if capabilities.state ~= "operational" then
    local reasonCode = capabilities.reasonCode == "RC_AWARD_IDENTITY_UNAVAILABLE"
      and "AWARD_IDENTITY_UNAVAILABLE" or (capabilities.reasonCode or "RC_AWARD_PATH_UNAVAILABLE")
    return ignoredAward(reasonCode)
  end
  if Dibs.Readiness and type(Dibs.Readiness.CanProcessLiveAward) == "function" then
    local allowed, readiness = Dibs.Readiness.CanProcessLiveAward()
    if allowed == false then
      local reasonCode = "READINESS_BLOCKED"
      if readiness and readiness.reasonCodes then
        for code in pairs(readiness.reasonCodes) do
          reasonCode = tostring(code)
          break
        end
      end
      return ignoredAward(reasonCode)
    end
  end
  local itemID = tonumber(tostring(itemLink):match("item:(%d+)"))
  if not itemID then return ignoredAward("AWARD_INVALID_ITEM") end
  local responseType = getAwardResponseType(rc, session)
  local sharedValidation = Dibs.RCLootCouncil.ValidateAwardInput({
    itemID = itemID,
    itemLink = itemLink,
    winner = winner,
    response = normalizedResponse,
    responseType = responseType,
    status = status,
  })
  if not sharedValidation.ok then
    return ignoredAward(sharedValidation.reasonCode or "AWARD_INVALID")
  end
  local actor = rc and rc.masterLooter
  if not actor then return ignoredAward("RC_MASTER_LOOTER_UNVERIFIABLE") end
  local ref, identityReason = getAwardIdentity(rc, session, winner, itemID, itemLink)
  if not ref then
    return ignoredAward(identityReason or "AWARD_IDENTITY_UNAVAILABLE")
  end
  local result = Dibs.ProtectedActions.FinalizeAward(actor, { awardRef = ref, playerName = winner, itemID = itemID, itemLink = itemLink, sourceStatus = status, source = "rclootcouncil", response = normalizedResponse, responseType = responseType, responseValidated = true })
  if result and result.ok == false and Dibs.DebugLogs and type(Dibs.DebugLogs.Add) == "function" then
    Dibs.DebugLogs.Add("RCLootCouncil", 2, tostring(result.reasonCode or "AWARD_REJECTED"))
  end
  return result
end

function Dibs.RCLootCouncil.Initialize()
  local rc = getRC()
  if type(rc) ~= "table" then return false end
  if Dibs.RCLootCouncil.initialized then
    -- Re-run only idempotent probes when RC modules or frames become
    -- available after Dibs.  No Dibs state is recreated or migrated here.
    installForcedDibConfigHook()
    installLootFrameHook()
    installVotingFrameColumns()
    ensureRuntimeHooks(120)
    return true
  end
  sanitizeRCLootCouncilHistory(rc)
  if type(rc.RegisterMessage) == "function" and Dibs.RCLootCouncil.callbackOwner ~= rc then
    local ok, result = pcall(rc.RegisterMessage, rc, "RCMLAwardSuccess", Dibs.RCLootCouncil.OnAwardSuccess)
    if ok and result ~= false then
      Dibs.RCLootCouncil.callbackOwner = rc
    else
      Dibs.RCLootCouncil.callbackOwner = nil
    end
  end
  installForcedDibConfigHook()
  installLootFrameHook()
  installVotingFrameColumns()
  ensureRuntimeHooks(120)
  Dibs.RCLootCouncil.initialized = true
  return true
end

function Dibs.RCLootCouncil.TryUseRCModule()
  return Dibs.RCLootCouncil.Initialize()
end

function Dibs.RCLootCouncil.GetLocalStatus()
  local capabilities = capabilitySnapshot()
  return {
    availability = capabilities.state,
    status = capabilities.state,
    reasonCode = capabilities.reasonCode,
    capabilities = capabilities.capabilities,
    compatibility = capabilities.compatibility,
    diagnostic = reasonDiagnostic(capabilities.reasonCode),
    observedVersion = capabilities.observedVersion,
    protocolVersion = Dibs.PROTOCOL_VERSION,
    initialized = Dibs.RCLootCouncil.initialized == true,
  }
end

-- Build a read-only evidence link for a dispute.  This adapter deliberately
-- copies only stable award metadata supplied by the caller; it never exposes
-- live candidates/votes and never mutates RCLootCouncil history.
function Dibs.RCLootCouncil.GetAwardEvidence(context)
  context = type(context) == "table" and context or {}
  local status = Dibs.RCLootCouncil.GetLocalStatus()
  return {
    source = "rclootcouncil",
    awardRef = context.awardRef,
    historyRef = context.historyRef,
    transactionRef = context.transactionRef,
    itemID = tonumber(context.itemID or context.itemId),
    itemLink = context.itemLink,
    itemName = context.itemName,
    playerName = context.winner or context.playerName,
    response = context.response or context.responseText,
    status = context.status or context.sourceStatus,
    seasonId = context.seasonId,
    timestamp = context.timestamp or context.createdAt,
    confidence = (context.awardRef or context.historyRef) and "high" or "medium",
    unavailableFields = status.availability == "operational" and {} or { "live_integration" },
    integrationStatus = status.availability,
    integrationReason = status.reasonCode,
  }
end

Dibs.RCLootCouncil.BuildAwardEvidence = Dibs.RCLootCouncil.GetAwardEvidence

-- Historical reconciliation -------------------------------------------------
-- This surface is deliberately read-only until an Officer explicitly confirms
-- an individual candidate through ProtectedActions.history.confirm.
local HISTORY_FINAL_STATES = {
  awarded = true, success = true, complete = true, finalized = true,
  normal = true, indirect = true, manually_added = true,
}

local function trimHistoryText(value)
  local textValue = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  return textValue
end

function Dibs.RCLootCouncil.NormalizeResponseAlias(value)
  return string.upper(trimHistoryText(value))
end

local function splitAliases(value)
  local result, seen = {}, {}
  local function add(alias)
    local normalized = Dibs.RCLootCouncil.NormalizeResponseAlias(alias)
    if normalized ~= "" and not seen[normalized] then
      seen[normalized] = true
      table.insert(result, normalized)
    end
  end
  if type(value) == "table" then
    for _, alias in ipairs(value) do add(alias) end
  else
    for alias in tostring(value or ""):gmatch("[^,;\n]+") do add(alias) end
  end
  table.sort(result)
  return result
end

function Dibs.RCLootCouncil.NormalizeResponseAliases(value)
  return splitAliases(value)
end

local function reconciliationState()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.reconciliation = db.reconciliation or {
    version = 1, sessions = {}, aliases = {}, aliasHistory = {}, decisions = {}, evidence = {}, evidenceIndex = {},
  }
  local state = db.reconciliation
  state.sessions = state.sessions or {}
  state.aliases = state.aliases or {}
  state.aliasHistory = state.aliasHistory or {}
  state.decisions = state.decisions or {}
  state.evidence = state.evidence or {}
  state.evidenceIndex = state.evidenceIndex or {}
  return state
end

function Dibs.RCLootCouncil.GetReconciliationAliases(seasonId)
  local state = reconciliationState()
  local aliases = state.aliases[tostring(seasonId or "")] or {}
  local result = {}
  for _, alias in ipairs(aliases) do result[#result + 1] = alias end
  return result
end

function Dibs.RCLootCouncil.SetReconciliationAliases(seasonId, aliases, actor)
  if not seasonId or not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(seasonId) then
    return nil, "SEASON_NOT_FOUND"
  end
  if not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("history.confirm", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local normalized = splitAliases(aliases)
  if #normalized == 0 then return nil, "HISTORY_NO_ALIASES" end
  local state = reconciliationState()
  state.aliases[tostring(seasonId)] = normalized
  state.aliasHistory[#state.aliasHistory + 1] = {
    seasonId = tostring(seasonId), aliases = normalized,
    actorId = Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or tostring(actor or ""),
    createdAt = time(),
  }
  return normalized
end

-- RCLootCouncil history can contain both rich WoW hyperlinks and compact
-- `item:ID...` tokens. Native history resolves the latter while rendering;
-- normalize them once for Dibs so the Officer table never exposes raw Hitem
-- strings and repeated searches do not ask the item API again.
local historyItemLinkCache = {}

local function isRichHistoryItemLink(value)
  return type(value) == "string" and value:find("|Hitem:", 1, true) ~= nil
end

local function historyItemInfo(row, itemID, rawLink)
  local link = type(rawLink) == "string" and rawLink or nil
  local name = row.itemName or row.itemDisplayName
  if isRichHistoryItemLink(link) then
    name = name or link:match("|h%[([^%]]+)%]|h")
    return link, name
  end
  -- Compact `item:ID...` values are identifiers, not renderable links. Keep
  -- the name for the fallback below but never pass the raw token to the UI.
  link = nil

  local id = tonumber(itemID)
  if id and historyItemLinkCache[id] then
    local cached = historyItemLinkCache[id]
    return cached.link, name or cached.name
  end

  -- GetItemInfo is normally immediate for an item already present in the
  -- RCLootCouncil history. Use it only for compact links and cache the result;
  -- this keeps a large reconciliation search from repeatedly triggering item
  -- lookups while still producing the same rich link as native history.
  if not name and id then
    local getter = type(_G.C_Item) == "table" and _G.C_Item.GetItemInfo or _G.GetItemInfo
    if type(getter) == "function" then
      local ok, resolvedName, resolvedLink = pcall(getter, id)
      if ok then
        name = resolvedName or name
        link = resolvedLink or link
      end
    end
  end

  local bracketName = type(rawLink) == "string" and rawLink:match("%[([^%]]+)%]") or nil
  if not name and bracketName and not bracketName:match("^H?item:") then
    name = bracketName
  end
  if id and not link then
    link = buildFallbackItemLink(id, name)
  end
  if id then
    historyItemLinkCache[id] = { link = link, name = name }
  end
  return link, name
end

local function historyItemId(row)
  return tonumber(row.itemID or row.itemId or row.itemIDValue) or parseItemID(row.lootWon or row.itemLink or row.item or row.link)
end

local function historyWinner(row, playerKey)
  -- RCLootCouncil stores each history entry under the awarded player's name,
  -- while `owner` is the original loot owner.  They are often different (for
  -- example, a tradeable item can be looted by the ML and awarded to another
  -- raider).  Treating `owner` as the winner makes every reconciliation row
  -- point at the looter instead of the person who actually won the item.
  return row.winner or row.winnerName or row.playerName or row.player or row.recipient or row.awardedTo or playerKey
end

local function historyStatus(row)
  return row.finalStatus or row.sourceStatus or row.awardStatus or row.status or (row.isAwarded and "awarded" or nil)
end

local function historyTimestamp(row)
  for _, key in ipairs({ "originalAwardTime", "timestamp", "createdAt", "timeStamp", "dateValue" }) do
    local value = tonumber(row[key])
    if value then return value end
  end
  return nil
end

local function historyTimestampText(row)
  local dateText, timeText = row.date or row.dateText or row.awardDate, row.clock or row.timeText or row.awardTime
  if dateText and timeText then return trimHistoryText(dateText) .. " " .. trimHistoryText(timeText) end
  if dateText then return trimHistoryText(dateText) end
  return nil
end

local function historyResponse(row)
  local value = row.responseText or row.responseName or row.response or row.responseType or row.responseID
  if type(value) == "table" then value = value.name or value.text or value.label or value.id end
  return value
end

local function historyRowsFromDB(historyDB)
  local rows = {}
  local function add(playerKey, index, row)
    if type(row) ~= "table" then return end
    local historyRef = row.id and "history:" .. tostring(row.id) or nil
    local rawItemLink = row.lootWon or row.itemLink or row.item or row.link
    local responseText = historyResponse(row)
    local winner = historyWinner(row, playerKey)
    local itemID = historyItemId(row)
    local sourceStatus = historyStatus(row)
    local rowKey = historyRef or ("row:" .. tostring(playerKey or "unknown") .. ":" .. tostring(index))
    rows[#rows + 1] = {
      candidateId = rowKey,
      historyRef = historyRef,
      awardRef = historyRef,
      evidenceId = "reconciliation:" .. rowKey,
      historySource = row.source or row.dibsOrigin or "RCLootCouncil",
      historyEvent = row.event or row.eventName or row.sourceEvent,
      playerName = winner,
      winner = winner,
      originalOwner = row.owner or row.originalOwner or row.lootOwner,
      itemID = itemID,
      -- Resolve compact item tokens only after the result limit and date
      -- filters have been applied. This keeps the first preview responsive on
      -- a long history while preserving the original read-only row data.
      itemLink = rawItemLink,
      itemName = row.itemName or row.itemDisplayName or row.name,
      instanceID = tonumber(row.instanceID or row.raidId or row.instanceId),
      encounterID = tonumber(row.encounterID or row.bossID or row.encounterId),
      responseText = responseText,
      response = responseText,
      responseIdentity = row.responseID or row.responseId or row.responseIdentity,
      sourceStatus = sourceStatus,
      finalStatus = sourceStatus,
      difficulty = row.difficulty or row.difficultyID,
      finalized = row.finalized == true or HISTORY_FINAL_STATES[string.lower(tostring(sourceStatus or ""))] == true,
      originalAwardTime = historyTimestamp(row),
      originalAwardTimeText = historyTimestampText(row),
      sessionIdentity = row.sessionID or row.sessionId or row.session,
      rawIndex = index,
    }
  end
  if type(historyDB) ~= "table" then return rows end
  local isArray = #historyDB > 0
  if isArray then
    for index, row in ipairs(historyDB) do
      -- An array has no winner key to fall back to.  Keep the winner unknown
      -- unless the record carries an explicit awarded-player field; `owner`
      -- is the original looter and must never be promoted to winner.
      add(nil, index, row)
    end
  else
    for playerKey, entries in pairs(historyDB) do
      if type(entries) == "table" then
        if entries.id or entries.itemID or entries.lootWon then
          add(playerKey, 1, entries)
        else
          for index, row in ipairs(entries) do add(playerKey, index, row) end
        end
      end
    end
  end
  table.sort(rows, function(a, b) return tostring(a.candidateId) < tostring(b.candidateId) end)
  return rows
end

local HISTORY_ROWS_CACHE_LIMIT = 2500
local historyRowsCache = { db = nil, signature = nil, rows = nil }

local function historyRowMarker(row)
  if type(row) ~= "table" then return "" end
  return tostring(row.id or row.itemID or row.itemId or row.timestamp or row.date or row.lootWon or "")
end

-- RCLootCouncil keeps one long-lived history table and appends to its player
-- buckets. A small structural signature lets repeated previews reuse the
-- indexed rows without retaining more than a bounded amount of data.
local function historyDBSignature(historyDB)
  if type(historyDB) ~= "table" then return "" end
  local buckets, entries = 0, 0
  local firstMarker, lastMarker = "", ""
  if #historyDB > 0 then
    entries = #historyDB
    firstMarker = historyRowMarker(historyDB[1])
    lastMarker = historyRowMarker(historyDB[#historyDB])
  else
    for key, bucket in pairs(historyDB) do
      buckets = buckets + 1
      if type(bucket) == "table" then
        if bucket.id or bucket.itemID or bucket.itemId or bucket.lootWon then
          entries = entries + 1
          firstMarker = firstMarker == "" and (tostring(key) .. ":" .. historyRowMarker(bucket)) or firstMarker
          lastMarker = tostring(key) .. ":" .. historyRowMarker(bucket)
        else
          entries = entries + #bucket
          if #bucket > 0 then
            firstMarker = firstMarker == "" and (tostring(key) .. ":" .. historyRowMarker(bucket[1])) or firstMarker
            lastMarker = tostring(key) .. ":" .. historyRowMarker(bucket[#bucket])
          end
        end
      end
    end
  end
  return tostring(buckets) .. ":" .. tostring(entries) .. ":" .. firstMarker .. ":" .. lastMarker
end

local function copyHistoryRow(row)
  local copy = {}
  for key, value in pairs(row or {}) do copy[key] = value end
  return copy
end

function Dibs.RCLootCouncil.GetHistoryRows(options)
  options = type(options) == "table" and options or {}
  if Dibs.Permissions and Dibs.Permissions.Can and not Dibs.Permissions.Can("history.confirm", options.actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local rc = getRC()
  if type(rc) ~= "table" or type(rc.GetHistoryDB) ~= "function" then return nil, "HISTORY_UNAVAILABLE" end
  local ok, historyDB = pcall(rc.GetHistoryDB, rc)
  if not ok or type(historyDB) ~= "table" then return nil, "HISTORY_UNAVAILABLE" end
  local signature = historyDBSignature(historyDB)
  local rows
  if historyRowsCache.db == historyDB and historyRowsCache.signature == signature and historyRowsCache.rows then
    rows = historyRowsCache.rows
  else
    rows = historyRowsFromDB(historyDB)
    if #rows <= HISTORY_ROWS_CACHE_LIMIT then
      historyRowsCache = { db = historyDB, signature = signature, rows = rows }
    else
      historyRowsCache = { db = historyDB, signature = signature, rows = nil }
    end
  end
  local maxRows = math.floor(tonumber(options.limit) or 200)
  if maxRows < 1 then maxRows = 1 end
  if maxRows > 500 then maxRows = 500 end
  local filtered = {}
  local fromTime, toTime = tonumber(options.fromTime), tonumber(options.toTime)
  for _, sourceRow in ipairs(rows) do
    local stamp = sourceRow.originalAwardTime
    if (not fromTime or not stamp or stamp >= fromTime) and (not toTime or not stamp or stamp <= toTime) then
      local row = copyHistoryRow(sourceRow)
      row.itemLink, row.itemName = historyItemInfo(row, row.itemID, row.itemLink)
      filtered[#filtered + 1] = row
      if #filtered >= maxRows then break end
    end
  end
  return filtered
end

local function classifyHistoryRow(row, aliases, seasonId, identityMap)
  local normalizedResponse = Dibs.RCLootCouncil.NormalizeResponseAlias(row.responseText)
  local aliasUsed
  for _, alias in ipairs(aliases or {}) do
    if normalizedResponse == alias then aliasUsed = alias break end
  end
  local classification, reasonCode = "eligible", nil
  if normalizedResponse == "" then classification, reasonCode = "rejected", "NON_DIB_RESPONSE"
  elseif not aliasUsed then classification, reasonCode = "rejected", "NON_DIB_RESPONSE"
  elseif (function()
    local state = string.lower(tostring(row.sourceStatus or ""))
    return state == "test" or state == "test_mode" or state == "pending" or state == "rejected" or state == "open" or state == "in_progress"
  end)() then classification, reasonCode = "rejected", "HISTORY_NON_FINAL"
  elseif not row.finalized and not HISTORY_FINAL_STATES[string.lower(tostring(row.sourceStatus or ""))] then classification, reasonCode = "ambiguous", "HISTORY_FINAL_STATUS_UNKNOWN"
  elseif not row.itemID or not row.playerName then classification, reasonCode = "unsupported", "HISTORY_UNSUPPORTED"
  elseif not row.awardRef then classification, reasonCode = "ambiguous", "HISTORY_IDENTITY_REQUIRED"
  end
  if classification == "eligible" and aliasUsed and identityMap and identityMap[aliasUsed] and identityMap[aliasUsed].ambiguous then
    classification, reasonCode = "ambiguous", "HISTORY_RESPONSE_IDENTITY_AMBIGUOUS"
  end
  local existing = Dibs.Ledger and Dibs.Ledger.GetTransactionForEvidence and Dibs.Ledger.GetTransactionForEvidence(row.evidenceId)
  existing = existing or (Dibs.Ledger and Dibs.Ledger.GetTransactionForAward and Dibs.Ledger.GetTransactionForAward(row.awardRef))
  if existing then classification, reasonCode = "already_accounted", "HISTORY_ALREADY_ACCOUNTED" end
  row.targetSeasonId = seasonId
  row.normalizedResponse = normalizedResponse
  row.aliasUsed = aliasUsed
  row.classification = classification
  row.reasonCode = reasonCode
  return row
end

function Dibs.RCLootCouncil.CreateReconciliationSession(options, actor)
  options = type(options) == "table" and options or {}
  local seasonId = options.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId())
  if not seasonId or not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(seasonId) then return nil, "HISTORY_NO_SEASON" end
  if not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("history.confirm", actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local aliases = splitAliases(options.aliases or options.responseAliases)
  if #aliases == 0 then return nil, "HISTORY_NO_ALIASES" end
  local fromTime, toTime = options.fromTime and tonumber(options.fromTime), options.toTime and tonumber(options.toTime)
  if (options.fromTime and not fromTime) or (options.toTime and not toTime) or (fromTime and toTime and fromTime > toTime) then
    return nil, "HISTORY_INVALID_DATE_RANGE"
  end
  local scanOptions = {}
  for key, value in pairs(options) do scanOptions[key] = value end
  scanOptions.actor = actor
  local rows, reason = Dibs.RCLootCouncil.GetHistoryRows(scanOptions)
  if not rows then return nil, reason or "HISTORY_UNAVAILABLE" end
  local candidates = {}
  local counts = { scanned = #rows, eligible = 0, already_accounted = 0, ambiguous = 0, rejected = 0, unsupported = 0 }
  local identityMap = {}
  for _, row in ipairs(rows) do
    local response = Dibs.RCLootCouncil.NormalizeResponseAlias(row.responseText)
    if response ~= "" and row.responseIdentity ~= nil then
      local entry = identityMap[response] or { values = {} }
      entry.values[tostring(row.responseIdentity)] = true
      identityMap[response] = entry
    end
  end
  for _, entry in pairs(identityMap) do
    local count = 0
    for _ in pairs(entry.values) do count = count + 1 end
    entry.ambiguous = count > 1
  end
  for _, row in ipairs(rows) do
    local candidate = classifyHistoryRow(row, aliases, seasonId, identityMap)
    candidates[#candidates + 1] = candidate
    counts[candidate.classification] = (counts[candidate.classification] or 0) + 1
  end
  local session = {
    sessionId = Dibs.NewId and Dibs.NewId("reconciliation") or ("reconciliation-" .. tostring(time())),
    targetSeasonId = seasonId,
    aliases = aliases,
    mode = tostring(options.mode or "guided"):lower() == "manual" and "manual" or "guided",
    createdAt = time(),
    actorId = Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or tostring(actor or ""),
    previewOnly = true,
    counts = counts,
    candidates = candidates,
    source = "RCLootCouncil history",
    fromTime = fromTime, toTime = toTime,
  }
  reconciliationState().sessions[session.sessionId] = session
  return session
end

function Dibs.RCLootCouncil.GetReconciliationSession(sessionId, actor)
  local session = reconciliationState().sessions[tostring(sessionId or "")]
  if not session then return nil, "HISTORY_SESSION_NOT_FOUND" end
  if Dibs.Permissions and Dibs.Permissions.Can and not Dibs.Permissions.Can("history.confirm", actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  return session
end

function Dibs.RCLootCouncil.ListReconciliationSessions(actor)
  if Dibs.Permissions and Dibs.Permissions.Can and not Dibs.Permissions.Can("history.confirm", actor) then
    return {}, "GUILD_ADMIN_REQUIRED"
  end
  local sessions = {}
  for _, session in pairs(reconciliationState().sessions or {}) do sessions[#sessions + 1] = session end
  table.sort(sessions, function(a, b) return (tonumber(a.createdAt) or 0) > (tonumber(b.createdAt) or 0) end)
  return sessions
end

function Dibs.RCLootCouncil.ConfirmReconciliationCandidate(sessionId, candidateId, options, actor)
  local session, reason = Dibs.RCLootCouncil.GetReconciliationSession(sessionId, actor)
  if not session then return nil, reason end
  local candidate
  for _, row in ipairs(session.candidates or {}) do if tostring(row.candidateId) == tostring(candidateId) then candidate = row break end end
  if not candidate then return nil, "HISTORY_CANDIDATE_NOT_FOUND" end
  options = type(options) == "table" and options or {}
  local payload = {}
  for key, value in pairs(candidate) do payload[key] = value end
  for key, value in pairs(options) do payload[key] = value end
  payload.reconciliationSessionId = session.sessionId
  payload.candidateId = candidate.candidateId
  payload.seasonId = session.targetSeasonId
  payload.mode = options.mode or session.mode
  payload.responseValidated = candidate.aliasUsed ~= nil and candidate.normalizedResponse == candidate.aliasUsed
  payload.source = "rclootcouncil_history"
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute and Dibs.ProtectedActions.Execute("history.confirm", actor, payload)
  if not result then return nil, "PROTECTED_ACTION_UNAVAILABLE" end
  local state = reconciliationState()
  local decision = {
    decisionId = Dibs.NewId and Dibs.NewId("reconciliation-decision") or tostring(time()),
    sessionId = session.sessionId, candidateId = candidate.candidateId,
    outcome = result.outcome or (result.ok and "awarded" or "rejected"),
    reasonCode = result.reasonCode, actorId = result.decision and result.decision.actorId,
    createdAt = time(), evidenceId = candidate.evidenceId,
  }
  state.decisions[decision.decisionId] = decision
  if result.ok and result.value then
    candidate.classification = "already_accounted"
    candidate.reasonCode = "HISTORY_ALREADY_ACCOUNTED"
    candidate.transactionId = result.value.transactionId
    candidate.confirmedAt = time()
    if not state.evidence[candidate.evidenceId] then state.evidence[candidate.evidenceId] = {
      evidenceId = candidate.evidenceId, immutable = true,
      source = candidate.historySource or "unknown", historyRef = candidate.historyRef or "unknown",
      sourceEvent = candidate.historyEvent or "RCMLAwardSuccess", accountingAction = "FinalizeAward",
      sessionId = candidate.sessionIdentity or "unknown", itemID = candidate.itemID or "unknown",
      itemLink = candidate.itemLink or "unknown", playerName = candidate.playerName or "unknown",
      originalOwner = candidate.originalOwner or "unknown",
      responseText = candidate.responseText or "unknown", responseIdentity = candidate.responseIdentity or "unknown",
      finalStatus = candidate.sourceStatus or "unknown", difficulty = candidate.difficulty or "unknown", aliasUsed = candidate.aliasUsed or "unknown",
      targetSeasonId = session.targetSeasonId or "unknown", originalAwardTime = candidate.originalAwardTime or candidate.originalAwardTimeText or "unknown",
      importedAt = time(), importedBy = decision.actorId, reason = options.reason,
      transactionId = result.value.transactionId,
    } end
    state.evidenceIndex[candidate.evidenceId] = decision.decisionId
  end
  return result, decision
end

function Dibs.RCLootCouncil.RejectReconciliationCandidate(sessionId, candidateId, reason, actor)
  local session, sessionReason = Dibs.RCLootCouncil.GetReconciliationSession(sessionId, actor)
  if not session then return nil, sessionReason end
  local result = Dibs.ProtectedActions.Execute("history.reject", actor, {
    reconciliationSessionId = sessionId, candidateId = candidateId, reason = reason,
  })
  if result and result.ok then
    local state = reconciliationState()
    for _, candidate in ipairs(session.candidates or {}) do
      if tostring(candidate.candidateId) == tostring(candidateId) then
        candidate.classification = "rejected"
        candidate.reasonCode = "HISTORY_REJECTED_BY_OFFICER"
        candidate.rejectedAt = time()
        break
      end
    end
    local decisionId = Dibs.NewId and Dibs.NewId("reconciliation-decision") or tostring(time())
    state.decisions[decisionId] = { decisionId = decisionId, sessionId = sessionId, candidateId = candidateId, outcome = "rejected", reason = reason, createdAt = time(), actorId = result.decision and result.decision.actorId }
  end
  return result
end

-- Descriptive aliases keep the public adapter easy to discover for integrations
-- and allow future UI clients to use the same controlled workflow.
Dibs.RCLootCouncil.StartHistoryReconciliation = Dibs.RCLootCouncil.CreateReconciliationSession
Dibs.RCLootCouncil.GetHistoryReconciliationPreview = Dibs.RCLootCouncil.GetReconciliationSession
Dibs.RCLootCouncil.ConfirmHistoryCandidate = Dibs.RCLootCouncil.ConfirmReconciliationCandidate
