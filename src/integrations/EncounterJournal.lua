local Dibs = _G.Dibs
Dibs.EncounterJournal = Dibs.EncounterJournal or {}
local EJ_RETRY_MAX_ATTEMPTS = 120
local EJ_REFRESH_INTERVAL = 1.0
local EJ_BUTTON_ANCHOR_X = 0
local EJ_BUTTON_ANCHOR_Y = -19
local EJ_ITEM_DEBUG_CACHE_TTL = 120
local EJ_TOOLTIP_MAX_DEBUG_LINES = 60

local EJ_SUBCATEGORY_MATRIX = {
  CATALYST = { allow = false, note = "Personal player item; never a Dibs category" },
  COSMETIC = { allow = false, note = "Cosmetic-only item" },
  DECOR = { allow = false, note = "Housing decor item" },
  MOUNT = { allow = false, note = "Mount item" },
  PET = { allow = false, note = "Pet item" },
  RECIPE = { allow = false, note = "Profession recipe" },
  RECIPE_PATTERN = { allow = false, note = "Pattern/plans recipe" },
  TOKEN = { allow = true, note = "General token" },
  TOKEN_SET = { allow = true, note = "Class set token" },
  UNKNOWN = { allow = true, note = "Unknown category, keep visible" },
}

local itemDebugCache = {}

local function getNowSeconds()
  if type(GetTime) == "function" then
    return tonumber(GetTime()) or 0
  end
  return tonumber(time and time() or 0) or 0
end

local function extractItemFromLink(link)
  if type(link) ~= "string" then return nil, nil end
  local itemID = tonumber(link:match("item:(%d+)"))
  local itemName = link
  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    local name = C_Item.GetItemInfo(link)
    if name then itemName = name end
  end
  return itemID, itemName
end

local function safeLower(value)
  return string.lower(tostring(value or ""))
end

local function normalizeSubCategoryKey(value)
  local text = tostring(value or "")
  text = text:match("^%s*(.-)%s*$") or ""
  text = string.upper(text)
  if text == "" then
    return "UNKNOWN"
  end
  return text
end

local function getSubCategorySettings()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.settings = db.settings or {}
  db.settings.ejKnownSubCategories = db.settings.ejKnownSubCategories or {}
  db.settings.ejBlockedSubCategories = db.settings.ejBlockedSubCategories or {}
  return db.settings.ejKnownSubCategories, db.settings.ejBlockedSubCategories
end

local function canModifyDibsSettings(actor)
  return type(Dibs.Permissions) == "table" and type(Dibs.Permissions.Can) == "function"
    and Dibs.Permissions.Can("settings.modify", actor) == true
end

local function rememberKnownSubCategory(value)
  local key = normalizeSubCategoryKey(value)
  local known = getSubCategorySettings()
  known[key] = true
  return key
end

local function isSubCategoryBlocked(value)
  local key = normalizeSubCategoryKey(value)
  -- Catalyst progress is personal to the player and cannot be converted into
  -- a guild Dibs request, even when an old saved override says otherwise.
  if key == "CATALYST" or key == "CATALYSTS" then
    return true
  end
  local _, blocked = getSubCategorySettings()
  if blocked[key] ~= nil then
    return blocked[key] == true
  end
  local recommended = EJ_SUBCATEGORY_MATRIX[key]
  return type(recommended) == "table" and recommended.allow ~= true
end

local function setSubCategoryBlocked(value, shouldBlock)
  local key = rememberKnownSubCategory(value)
  local _, blocked = getSubCategorySettings()
  blocked[key] = shouldBlock == true
  return key
end

local function listSubCategories()
  local known, blocked = getSubCategorySettings()
  local values = {}
  for key in pairs(known) do
    table.insert(values, tostring(key))
  end
  table.sort(values)

  if Dibs and Dibs.Message then
    if #values == 0 then
      Dibs.Message("EJ sub-categories: none known yet. Run /dibs ejdebug on a loot page first.")
      return values
    end

    Dibs.Message("EJ sub-categories (blocked marked with X):")
    for _, key in ipairs(values) do
      local marker = blocked[key] == true and "[X]" or "[ ]"
      Dibs.Message("  " .. marker .. " " .. key)
    end
  end

  return values
end

local function getMatrixDecision(subCategory)
  local key = normalizeSubCategoryKey(subCategory)
  local rule = EJ_SUBCATEGORY_MATRIX[key]
  if type(rule) == "table" then
    return rule.allow == true, tostring(rule.note or "")
  end
  return true, "No explicit matrix rule"
end

local function printSubCategoryMatrix()
  local known = getSubCategorySettings()
  local keys = {}
  local seen = {}

  for key in pairs(EJ_SUBCATEGORY_MATRIX) do
    local normalized = normalizeSubCategoryKey(key)
    if not seen[normalized] then
      seen[normalized] = true
      table.insert(keys, normalized)
    end
  end
  for key in pairs(known) do
    local normalized = normalizeSubCategoryKey(key)
    if not seen[normalized] then
      seen[normalized] = true
      table.insert(keys, normalized)
    end
  end

  table.sort(keys)

  if Dibs and Dibs.Message then
    Dibs.Message("EJ matrix (allow/block recommendation):")
    for _, key in ipairs(keys) do
      local allow, note = getMatrixDecision(key)
      local marker = allow and "ALLOW" or "BLOCK"
      Dibs.Message("  " .. marker .. " " .. tostring(key) .. " - " .. tostring(note))
    end
  end
end

local function applyRecommendedSubCategoryMatrix()
  local known = getSubCategorySettings()
  local applied = 0

  for key in pairs(EJ_SUBCATEGORY_MATRIX) do
    local normalized = normalizeSubCategoryKey(key)
    rememberKnownSubCategory(normalized)
    local allow = getMatrixDecision(normalized)
    setSubCategoryBlocked(normalized, allow ~= true)
    applied = applied + 1
  end

  for key in pairs(known) do
    local normalized = normalizeSubCategoryKey(key)
    local allow = getMatrixDecision(normalized)
    setSubCategoryBlocked(normalized, allow ~= true)
  end

  if Dibs and Dibs.Message then
    Dibs.Message("EJ matrix applied. Rules=" .. tostring(applied))
  end
end

local function buildTooltipLineList(itemID, itemLink)
  local lines = {}
  if type(C_TooltipInfo) ~= "table" then
    return lines
  end

  local info = nil
  local targetLink = type(itemLink) == "string" and itemLink or nil
  local targetItemID = tonumber(itemID)

  if targetLink and type(C_TooltipInfo.GetHyperlink) == "function" then
    local ok, value = pcall(C_TooltipInfo.GetHyperlink, targetLink)
    if ok and type(value) == "table" then
      info = value
    end
  end

  if info == nil and targetItemID and type(C_TooltipInfo.GetItemByID) == "function" then
    local ok, value = pcall(C_TooltipInfo.GetItemByID, targetItemID)
    if ok and type(value) == "table" then
      info = value
    end
  end

  if type(info) ~= "table" or type(info.lines) ~= "table" then
    return lines
  end

  for _, line in ipairs(info.lines) do
    local text = tostring(line and (line.leftText or line.text or "") or "")
    if text ~= "" then
      table.insert(lines, text)
    end
  end

  return lines
end

local function stringifyDebugValue(value)
  local valueType = type(value)
  if valueType == "nil" then
    return "nil"
  end
  if valueType == "boolean" then
    return value and "true" or "false"
  end
  if valueType == "number" then
    return tostring(value)
  end
  if valueType == "string" then
    return value
  end
  if valueType == "table" then
    return "<table>"
  end
  return "<" .. valueType .. ">"
end

local function addTableDebugLines(targetLines, prefix, value, depth, maxDepth, maxLines)
  if #targetLines >= maxLines then return end

  local valueType = type(value)
  if valueType ~= "table" then
    table.insert(targetLines, tostring(prefix) .. "=" .. stringifyDebugValue(value))
    return
  end

  if depth >= maxDepth then
    table.insert(targetLines, tostring(prefix) .. "=<table...>")
    return
  end

  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  for _, key in ipairs(keys) do
    if #targetLines >= maxLines then
      return
    end
    local child = value[key]
    local childPrefix = tostring(prefix) .. "." .. tostring(key)
    if type(child) == "table" then
      addTableDebugLines(targetLines, childPrefix, child, depth + 1, maxDepth, maxLines)
    else
      table.insert(targetLines, childPrefix .. "=" .. stringifyDebugValue(child))
    end
  end
end

local function collectExtendedItemFacts(item)
  local facts = {}
  if type(item) ~= "table" or not tonumber(item.itemID) then
    return facts
  end

  local itemID = tonumber(item.itemID)
  local itemLink = item.itemLink

  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    local ok, name, link, quality, iLevel, reqLevel, itemClass, itemSubClass, maxStack, equipLoc, icon, sellPrice, classID, subClassID, bindType, expacID, setID, isCraftingReagent = pcall(C_Item.GetItemInfo, itemLink or itemID)
    if ok then
      facts.name = name
      facts.link = link
      facts.quality = quality
      facts.itemLevel = iLevel
      facts.requiredLevel = reqLevel
      facts.itemClass = itemClass
      facts.itemSubClass = itemSubClass
      facts.maxStack = maxStack
      facts.equipLoc = equipLoc
      facts.icon = icon
      facts.sellPrice = sellPrice
      facts.classID = classID
      facts.subClassID = subClassID
      facts.bindType = bindType
      facts.expacID = expacID
      facts.setID = setID
      facts.isCraftingReagent = isCraftingReagent
    end
  end

  if type(GetDetailedItemLevelInfo) == "function" then
    local ok, detailed = pcall(GetDetailedItemLevelInfo, itemLink or itemID)
    if ok then
      facts.detailedItemLevel = detailed
    end
  end

  return facts
end

local function inferItemSubCategory(item, tooltipLines)
  local responseType = safeLower(item and item.responseType)
  local itemID = item and tonumber(item.itemID) or nil

  local className = ""
  local subClassName = ""
  local equipLoc = ""
  local classID = nil
  local subClassID = nil
  if itemID and type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
    local _, cName, scName, eLoc, _, cID, scID = C_Item.GetItemInfoInstant(itemID)
    className = safeLower(cName)
    subClassName = safeLower(scName)
    equipLoc = safeLower(eLoc)
    classID = tonumber(cID)
    subClassID = tonumber(scID)
  end

  for _, rawLine in ipairs(tooltipLines or {}) do
    local line = safeLower(rawLine)
    if line:find("cosmetic", 1, true) then
      return "COSMETIC"
    end
    if line:find("pattern:", 1, true)
      or line:find("recipe:", 1, true)
      or line:find("plans:", 1, true)
      or line:find("formula:", 1, true)
      or line:find("schematic:", 1, true)
    then
      return "RECIPE_PATTERN"
    end
    if line:find("soulbound set item", 1, true)
      or line:find("create a soulbound set", 1, true)
      or line:find("armor token", 1, true)
      or line:find("classes:", 1, true)
    then
      return "TOKEN_SET"
    end
    if line:find("mount", 1, true) then
      return "MOUNT"
    end
    if line:find("battle pet", 1, true) or line:find("companion", 1, true) then
      return "PET"
    end
  end

  -- Retail Curios use the stable Context Token class/subclass pair and
  -- class-set tokens are registered by RCLootCouncil's token table. Resolve
  -- those before the broad Miscellaneous (class 15) mount fallback.
  if classID == 5 and subClassID == 2 then
    return "TOKEN"
  end
  if itemID and type(_G.RCTokenTable) == "table" and _G.RCTokenTable[itemID] then
    return "TOKEN_SET"
  end
  if classID == 9 then
    return "RECIPE"
  end
  if classID == 15 then
    return "MOUNT"
  end
  if classID == 17 then
    return "PET"
  end
  if className:find("cosmetic", 1, true) or subClassName:find("cosmetic", 1, true) then
    return "COSMETIC"
  end
  if className:find("decor", 1, true) or subClassName:find("decor", 1, true) then
    return "DECOR"
  end
  if className:find("token", 1, true) or subClassName:find("token", 1, true) then
    return "TOKEN"
  end
  if responseType:find("invtype_head", 1, true) and classID == 15 then
    return "MOUNT_HEAD_STYLE"
  end

  return "UNKNOWN"
end

local function buildItemDebugDetails(item)
  local details = {
    detectedType = tostring(item and item.responseType or "default"),
    subCategory = "UNKNOWN",
    className = "",
    subClassName = "",
    equipLoc = "",
    classID = nil,
    subClassID = nil,
    tooltipLines = {},
  }

  if type(item) ~= "table" or not tonumber(item.itemID) then
    return details
  end

  local itemID = tonumber(item.itemID)
  if type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
    local _, cName, scName, eLoc, _, cID, scID = C_Item.GetItemInfoInstant(itemID)
    details.className = tostring(cName or "")
    details.subClassName = tostring(scName or "")
    details.equipLoc = tostring(eLoc or "")
    details.classID = tonumber(cID)
    details.subClassID = tonumber(scID)
  end

  details.tooltipLines = buildTooltipLineList(itemID, item.itemLink)
  details.subCategory = inferItemSubCategory(item, details.tooltipLines)
  rememberKnownSubCategory(details.subCategory)
  return details
end

local function getItemDebugDetailsCached(item)
  if type(item) ~= "table" or not tonumber(item.itemID) then
    return buildItemDebugDetails(item)
  end

  local itemID = tonumber(item.itemID)
  local cacheKey = tostring(itemID) .. "|" .. tostring(item.itemLink or "")
  local cached = itemDebugCache[cacheKey]
  local now = getNowSeconds()
  if cached and (now - (cached.at or 0)) <= EJ_ITEM_DEBUG_CACHE_TTL then
    return cached.value
  end

  local details = buildItemDebugDetails(item)
  itemDebugCache[cacheKey] = {
    value = details,
    at = now,
  }
  return details
end

local function getLootScrollButtons()
  local ej = _G.EncounterJournal
  local info = ej and ej.encounter and ej.encounter.info
  if type(info) ~= "table" then return nil end

  local found = {}
  local seen = {}

  local function addButton(button)
    if type(button) ~= "table" then return end
    if seen[button] then return end

    local looksLikeLootRow = (button.link ~= nil)
      or (button.itemLink ~= nil)
      or (button.itemHyperlink ~= nil)
      or (button.itemID ~= nil)
      or (button.info ~= nil)
      or (button.icon ~= nil)
      or (button.Icon ~= nil)
      or (button.name ~= nil)
      or (button.Name ~= nil)
      or (button.itemName ~= nil)

    if looksLikeLootRow then
      seen[button] = true
      table.insert(found, button)
    end
  end

  local function addFromCollection(collection)
    if type(collection) ~= "table" then return end
    for _, entry in pairs(collection) do
      addButton(entry)
    end
  end

  local function addFromEnumerator(pool)
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for entry in pool:EnumerateActive() do
      addButton(entry)
    end
  end

  local function addFromChildren(frame)
    if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return end
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
      addButton(child)
    end
  end

  local function scanContainer(container)
    if type(container) ~= "table" then return end
    addFromCollection(container.buttons)
    addFromCollection(container.Buttons)
    addFromCollection(container.frames)

    local scrollBox = container.ScrollBox or container.scrollBox
    if type(scrollBox) == "table" then
      if type(scrollBox.GetFrames) == "function" then
        local ok, frames = pcall(scrollBox.GetFrames, scrollBox)
        if ok and type(frames) == "table" then
          for _, frame in ipairs(frames) do
            addButton(frame)
          end
        end
      end
      addFromChildren(scrollBox)
      addFromEnumerator(scrollBox.framePool)
      addFromEnumerator(scrollBox.buttonPool)
      local view = scrollBox.view
      if type(view) == "table" then
        addFromEnumerator(view.framePool)
        addFromEnumerator(view.buttonPool)
      end
    end

    addFromEnumerator(container.buttonPool)
    addFromEnumerator(container.framePool)
    addFromChildren(container.scrollTarget)
    addFromChildren(container.ScrollTarget)
  end

  -- `lootScroll` is a legacy implementation detail and is intentionally not
  -- part of the current Encounter Journal frame contract. Keep the optional
  -- probe dynamic so current API annotations do not treat it as guaranteed.
  scanContainer(info["lootScroll"])
  scanContainer(info["lootContainer"])
  scanContainer(info["LootContainer"])
  scanContainer(info["lootFrame"])

  if #found == 0 then
    return nil
  end
  return found
end

local function getLootButtonItem(button)
  if type(button) ~= "table" then return nil end
  local function resolveResponseType(id)
    local fromButton = button.typeCode
      or button.responseType
      or button.equipLoc
      or (button.info and (button.info.typeCode or button.info.responseType or button.info.equipLoc))
    if type(fromButton) == "string" and fromButton ~= "" then
      return fromButton
    end

    if type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" and tonumber(id) then
      local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(tonumber(id))
      if type(equipLoc) == "string" and equipLoc ~= "" then
        return equipLoc
      end
      if tonumber(classID) == 9 then
        return "RECIPE"
      end
    end

    return "default"
  end

  local link = button.link
    or button.itemLink
    or button.itemHyperlink
    or (button.icon and button.icon.itemLink)
    or (button.info and (button.info.link or button.info.itemLink or button.info.itemHyperlink))
  local itemID, itemName = extractItemFromLink(link)
  if itemID then
    local item = {
      itemID = itemID,
      itemName = itemName,
      itemLink = link,
      responseType = resolveResponseType(itemID),
    }
    button.__dibsLastItem = item
    return item
  end

  local directId = tonumber(button.itemID)
    or tonumber(button.id)
    or tonumber(button.indexedItemID)
    or (button.info and tonumber(button.info.itemID))
  if directId then
    local item = {
      itemID = directId,
      itemName = "Item " .. tostring(directId),
      itemLink = string.format("|cffffffff|Hitem:%d::::::::::::|h[Item %d]|h|r", directId, directId),
      responseType = resolveResponseType(directId),
    }
    button.__dibsLastItem = item
    return item
  end

  if type(C_EncounterJournal) == "table" and type(C_EncounterJournal.GetLootInfoByIndex) == "function" then
    local lootIndex = tonumber(button.index)
      or tonumber(button.lootIndex)
      or tonumber(button.displayIndex)
      or tonumber(button.itemIndex)
    if lootIndex then
      local ok, info = pcall(C_EncounterJournal.GetLootInfoByIndex, lootIndex)
      if ok and type(info) == "table" then
        local apiLink = info.link or info.itemLink or info.itemHyperlink
        local apiItemID, apiItemName = extractItemFromLink(apiLink)
        apiItemID = apiItemID or tonumber(info.itemID)
        if apiItemID then
          local item = {
            itemID = apiItemID,
            itemName = apiItemName or (info.name or ("Item " .. tostring(apiItemID))),
            itemLink = apiLink or string.format("|cffffffff|Hitem:%d::::::::::::|h[Item %d]|h|r", apiItemID, apiItemID),
            responseType = resolveResponseType(apiItemID),
          }
          button.__dibsLastItem = item
          return item
        end
      end
    end
  end

  if type(button.__dibsLastItem) == "table" and tonumber(button.__dibsLastItem.itemID) then
    return button.__dibsLastItem
  end

  return nil
end

local function lootRowHasVisibleItem(lootButton)
  if type(lootButton) ~= "table" then return false end
  if type(lootButton.IsShown) == "function" and lootButton:IsShown() ~= true then
    return false
  end

  local nameRegion = lootButton.name or lootButton.Name or lootButton.itemName
  if type(nameRegion) == "table" and type(nameRegion.GetText) == "function" then
    local text = nameRegion:GetText()
    if type(text) == "string" and text ~= "" then
      return true
    end
  end

  return false
end

local function isLikelyLootEntryRow(lootButton)
  if type(lootButton) ~= "table" then return false end

  local iconRegion = lootButton.icon or lootButton.Icon
  local hasIcon = type(iconRegion) == "table"

  local nameRegion = lootButton.name or lootButton.Name or lootButton.itemName
  if type(nameRegion) == "table" and type(nameRegion.GetText) == "function" then
    local text = tostring(nameRegion:GetText() or "")
    if text == "" then
      return false
    end
    local lower = string.lower(text)
    if string.find(lower, "bonus loot", 1, true) then
      return false
    end
  else
    return false
  end

  return hasIcon
end

local function scheduleRetry(step)
  if step >= EJ_RETRY_MAX_ATTEMPTS then return end
  local function retry()
    Dibs.EncounterJournal.AddActionIfAvailable(step + 1)
  end
  if Dibs.Ace3 and type(Dibs.Ace3.ScheduleTimer) == "function" then
    Dibs.Ace3.ScheduleTimer(retry, 0.5)
  elseif type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0.5, retry)
  end
end

local function getCurrentJournalInstanceID()
  if type(EJ_GetCurrentInstance) == "function" then
    local ok, value = pcall(EJ_GetCurrentInstance)
    if ok and tonumber(value) and tonumber(value) > 0 then
      return tonumber(value)
    end
  end

  local ej = _G.EncounterJournal
  local id = ej and (ej.instanceID or (ej.instanceSelect and ej.instanceSelect.instanceID))
  if tonumber(id) and tonumber(id) > 0 then
    return tonumber(id)
  end

  return nil
end

local function getJournalInstanceByIndex(index, isRaid)
  if type(EJ_GetInstanceByIndex) ~= "function" then return nil end

  local ok, instanceID = pcall(EJ_GetInstanceByIndex, index, isRaid)
  if ok and tonumber(instanceID) and tonumber(instanceID) > 0 then
    return tonumber(instanceID)
  end

  ok, instanceID = pcall(EJ_GetInstanceByIndex, index)
  if ok and tonumber(instanceID) and tonumber(instanceID) > 0 then
    return tonumber(instanceID)
  end

  return nil
end

local function instanceExistsInJournalList(targetInstanceID, isRaid)
  if not tonumber(targetInstanceID) then return false end
  for index = 1, 200 do
    local instanceID = getJournalInstanceByIndex(index, isRaid)
    if not instanceID then
      break
    end
    if tonumber(instanceID) == tonumber(targetInstanceID) then
      return true
    end
  end
  return false
end

local function isRaidEncounterJournalContext()
  local instanceID = getCurrentJournalInstanceID()
  if not instanceID then
    return true
  end

  if instanceExistsInJournalList(instanceID, true) then
    return true
  end
  if instanceExistsInJournalList(instanceID, false) then
    return false
  end

  return true
end

local function updateButtonState(button)
  if type(button) ~= "table" then return end
  if type(button.Enable) ~= "function" or type(button.Disable) ~= "function" then return end
  if Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() then
    button:Enable()
    if type(button.SetAlpha) == "function" then button:SetAlpha(1) end
  else
    button:Disable()
    if type(button.SetAlpha) == "function" then button:SetAlpha(0.5) end
  end
end

local function getDetectedTypeLabel(item)
  if type(item) ~= "table" then
    return "default"
  end
  local responseType = tostring(item.responseType or "default")
  if responseType == "" then
    return "default"
  end
  return responseType
end

local function setActionButtonTypeInfo(actionButton, item, debugInfo)
  if type(actionButton) ~= "table" then return end

  if type(item) == "table" and tonumber(item.itemID) then
    actionButton.__dibsDetectedType = getDetectedTypeLabel(item)
    actionButton.__dibsDetectedSubCategory = tostring(debugInfo and debugInfo.subCategory or "UNKNOWN")
    actionButton.__dibsItemID = tonumber(item.itemID)
    actionButton.__dibsItemName = tostring(item.itemName or item.itemLink or ("Item " .. tostring(item.itemID)))
  else
    actionButton.__dibsDetectedType = "unknown"
    actionButton.__dibsDetectedSubCategory = "UNKNOWN"
    actionButton.__dibsItemID = nil
    actionButton.__dibsItemName = nil
  end
end

local function showActionButtonTooltip(actionButton)
  if type(actionButton) ~= "table" then return end
  if type(GameTooltip) ~= "table" then return end
  if type(GameTooltip.SetOwner) ~= "function" then return end

  GameTooltip:SetOwner(actionButton, "ANCHOR_RIGHT")
  if type(GameTooltip.ClearLines) == "function" then
    GameTooltip:ClearLines()
  end

  local host = actionButton.__dibsHostButton
  local item = getLootButtonItem(host)
  local debugInfo = getItemDebugDetailsCached(item)
  local extendedFacts = collectExtendedItemFacts(item)
  setActionButtonTypeInfo(actionButton, item, debugInfo)

  local typeLabel = tostring(actionButton.__dibsDetectedType or "unknown")
  local subCategory = tostring(actionButton.__dibsDetectedSubCategory or "UNKNOWN")
  local itemName = actionButton.__dibsItemName
  local itemID = actionButton.__dibsItemID
  local request = actionButton.__dibsRequest

  if type(GameTooltip.AddLine) == "function" then
    GameTooltip:AddLine(request and "Requested" or "Dib")
    if itemName and itemName ~= "" then
      GameTooltip:AddLine(tostring(itemName), 1, 0.82, 0)
    end
    if request then
      GameTooltip:AddLine("Request difficulty: " .. tostring(request.difficulty or "Normal"), 1, 0.8, 0.2)
      GameTooltip:AddLine("Status: " .. tostring(request.status or "confirmed"), 0.7, 1, 0.7)
      if actionButton.__dibsJournalDifficulty then
        GameTooltip:AddLine("Journal difficulty: " .. tostring(actionButton.__dibsJournalDifficulty), 0.7, 0.85, 1)
      end
    end
    local detailLevel = Dibs.DebugEnabled and (Dibs.DebugEnabled("encounter_journal", 5) and 5 or (Dibs.DebugEnabled("encounter_journal", 3) and 3 or 1)) or 1
    if detailLevel >= 3 then
      GameTooltip:AddLine("Detected type: " .. typeLabel, 0.75, 0.9, 1)
      GameTooltip:AddLine("Detected sub-category: " .. subCategory, 0.75, 1, 0.8)
      if tonumber(itemID) then GameTooltip:AddLine("Item ID: " .. tostring(itemID), 0.6, 0.6, 0.6) end
      if debugInfo.className ~= "" or debugInfo.subClassName ~= "" then
        GameTooltip:AddLine("Class/Subclass: " .. tostring(debugInfo.className ~= "" and debugInfo.className or "n/a") .. " / " .. tostring(debugInfo.subClassName ~= "" and debugInfo.subClassName or "n/a"), 0.7, 0.7, 1)
      end
      if debugInfo.equipLoc ~= "" then GameTooltip:AddLine("EquipLoc: " .. tostring(debugInfo.equipLoc), 0.7, 0.7, 1) end
    end

    local debugLines = {}
    addTableDebugLines(debugLines, "item", item or {}, 0, 3, EJ_TOOLTIP_MAX_DEBUG_LINES)
    addTableDebugLines(debugLines, "debug", debugInfo or {}, 0, 3, EJ_TOOLTIP_MAX_DEBUG_LINES)
    addTableDebugLines(debugLines, "facts", extendedFacts or {}, 0, 3, EJ_TOOLTIP_MAX_DEBUG_LINES)

    if detailLevel < 5 then debugLines = {} end
    for lineIndex, lineText in ipairs(debugLines) do
      if lineIndex > EJ_TOOLTIP_MAX_DEBUG_LINES then
        break
      end
      GameTooltip:AddLine(tostring(lineText), 0.8, 0.8, 0.8)
    end
    if #debugLines > EJ_TOOLTIP_MAX_DEBUG_LINES then
      GameTooltip:AddLine("...(" .. tostring(#debugLines - EJ_TOOLTIP_MAX_DEBUG_LINES) .. " more)", 0.8, 0.8, 0.8)
    end
  end

  if type(GameTooltip.Show) == "function" then
    GameTooltip:Show()
  end
end

function Dibs.EncounterJournal.DumpVisibleLootDebug()
  local count = 0
  local fromApiCount = 0
  local seen = {}

  local function emitItem(item, sourceTag)
    if type(item) ~= "table" or not tonumber(item.itemID) then
      return false
    end

    local itemID = tonumber(item.itemID)
    if seen[itemID] then
      return false
    end
    seen[itemID] = true

    count = count + 1
    local info = getItemDebugDetailsCached(item)
    local blocked = isSubCategoryBlocked(info.subCategory)
    if Dibs and Dibs.Message then
      Dibs.Message("EJDBG [" .. tostring(count) .. "] " .. tostring(item.itemName or ("Item " .. tostring(itemID))) .. " | src=" .. tostring(sourceTag) .. " | id=" .. tostring(itemID) .. " | type=" .. tostring(item.responseType or "default") .. " | sub=" .. tostring(info.subCategory or "UNKNOWN") .. " | blocked=" .. tostring(blocked) .. " | equip=" .. tostring(info.equipLoc ~= "" and info.equipLoc or "n/a") .. " | class=" .. tostring(info.className ~= "" and info.className or "n/a") .. " | subclass=" .. tostring(info.subClassName ~= "" and info.subClassName or "n/a"))
      for lineIndex, tooltipLine in ipairs(info.tooltipLines or {}) do
        Dibs.Message("EJDBG    tip[" .. tostring(lineIndex) .. "] " .. tostring(tooltipLine))
      end
    end
    return true
  end

  local function getLootInfoByIndex(index)
    if type(C_EncounterJournal) == "table" and type(C_EncounterJournal.GetLootInfoByIndex) == "function" then
      local ok, info = pcall(C_EncounterJournal.GetLootInfoByIndex, index)
      if ok and type(info) == "table" then
        return info
      end
    end
    return nil
  end

  local scannedByEncounter = false
  if type(EJ_GetCurrentInstance) == "function"
    and type(EJ_GetEncounterInfoByIndex) == "function"
    and type(EJ_SelectEncounter) == "function"
    and type(EJ_GetNumLoot) == "function"
  then
    local instanceID = getCurrentJournalInstanceID()
    if tonumber(instanceID) and tonumber(instanceID) > 0 then
      scannedByEncounter = true
      local currentInfo = _G.EncounterJournal
        and _G.EncounterJournal.encounter
        and _G.EncounterJournal.encounter.info
      local previousEncounter = type(currentInfo) == "table" and tonumber(currentInfo["encounterID"]) or nil

      for encounterIndex = 1, 200 do
        local okEncounter, encounterID = pcall(EJ_GetEncounterInfoByIndex, encounterIndex, instanceID)
        if not okEncounter or not tonumber(encounterID) or tonumber(encounterID) <= 0 then
          break
        end

        pcall(EJ_SelectEncounter, tonumber(encounterID))
        local okNum, numLoot = pcall(EJ_GetNumLoot)
        numLoot = okNum and tonumber(numLoot) or 0
        if numLoot and numLoot > 0 then
          for lootIndex = 1, numLoot do
            local apiInfo = getLootInfoByIndex(lootIndex)
            if type(apiInfo) == "table" then
              local apiLink = apiInfo.link or apiInfo.itemLink or apiInfo.itemHyperlink
              local apiItemID, apiItemName = extractItemFromLink(apiLink)
              apiItemID = apiItemID or tonumber(apiInfo.itemID)
              if apiItemID then
                local apiItem = {
                  itemID = apiItemID,
                  itemName = apiItemName or apiInfo.name or ("Item " .. tostring(apiItemID)),
                  itemLink = apiLink or string.format("|cffffffff|Hitem:%d::::::::::::|h[Item %d]|h|r", apiItemID, apiItemID),
                  responseType = "default",
                }
                if emitItem(apiItem, "encounter:" .. tostring(encounterID) .. ":loot:" .. tostring(lootIndex)) then
                  fromApiCount = fromApiCount + 1
                end
              end
            end
          end
        end
      end

      if previousEncounter then
        pcall(EJ_SelectEncounter, previousEncounter)
      end
    end
  end

  if fromApiCount == 0 then
    local apiFn = type(C_EncounterJournal) == "table" and C_EncounterJournal.GetLootInfoByIndex or nil

    if type(apiFn) == "function" then
      local emptyStreak = 0
      for lootIndex = 1, 600 do
        local apiInfo = getLootInfoByIndex(lootIndex)
        if type(apiInfo) ~= "table" then
          emptyStreak = emptyStreak + 1
        else
          local apiLink = apiInfo.link or apiInfo.itemLink or apiInfo.itemHyperlink
          local apiItemID, apiItemName = extractItemFromLink(apiLink)
          apiItemID = apiItemID or tonumber(apiInfo.itemID)
          if apiItemID then
            local apiItem = {
              itemID = apiItemID,
              itemName = apiItemName or apiInfo.name or ("Item " .. tostring(apiItemID)),
              itemLink = apiLink or string.format("|cffffffff|Hitem:%d::::::::::::|h[Item %d]|h|r", apiItemID, apiItemID),
              responseType = "default",
            }
            if emitItem(apiItem, "api:" .. tostring(lootIndex)) then
              fromApiCount = fromApiCount + 1
            end
            emptyStreak = 0
          else
            emptyStreak = emptyStreak + 1
          end
        end

        if emptyStreak >= 40 then
          break
        end
      end
    end
  end

  local buttons = getLootScrollButtons()
  if type(buttons) == "table" then
    for _, lootButton in ipairs(buttons) do
      if type(lootButton) == "table" and lootRowHasVisibleItem(lootButton) then
        local item = getLootButtonItem(lootButton)
        emitItem(item, "visible")
      end
    end
  end

  if Dibs and Dibs.Message then
    Dibs.Message("EJ debug scan complete. Items=" .. tostring(count) .. " (api=" .. tostring(fromApiCount) .. ", encounterScan=" .. tostring(scannedByEncounter) .. ")")
  end
  return count
end

local refreshLootRowButtons

function Dibs.EncounterJournal.HandleSubCategorySlash(rest)
  local command = tostring(rest or "")
  local args = {}
  for token in string.gmatch(command, "%S+") do
    table.insert(args, token)
  end

  local subAction = string.lower(tostring(args[1] or "list"))
  local rawKey = table.concat(args, " ", 2)
  local key = normalizeSubCategoryKey(rawKey)

  if subAction == "list" then
    listSubCategories()
    return
  end

  if subAction == "matrix" then
    printSubCategoryMatrix()
    return
  end

  if subAction == "apply" or subAction == "preset" then
    if not canModifyDibsSettings() then
      Dibs.Message("Only the guild master or an officer may change Dibs settings.")
      return
    end
    local preset = string.lower(tostring(args[2] or "recommended"))
    if preset == "recommended" or preset == "default" then
      applyRecommendedSubCategoryMatrix()
      refreshLootRowButtons(true)
      listSubCategories()
      return
    end
    Dibs.Message("Usage: /dibs ejsub apply recommended")
    return
  end

  if subAction == "scan" then
    Dibs.EncounterJournal.DumpVisibleLootDebug()
    listSubCategories()
    return
  end

  if subAction == "block" then
    if not canModifyDibsSettings() then
      Dibs.Message("Only the guild master or an officer may change Dibs settings.")
      return
    end
    if key == "UNKNOWN" and rawKey == "" then
      Dibs.Message("Usage: /dibs ejsub block <SUB_CATEGORY>")
      return
    end
    local saved = setSubCategoryBlocked(key, true)
    Dibs.Message("EJ sub-category blocked: " .. tostring(saved))
    refreshLootRowButtons(true)
    return
  end

  if subAction == "allow" then
    if not canModifyDibsSettings() then
      Dibs.Message("Only the guild master or an officer may change Dibs settings.")
      return
    end
    if key == "UNKNOWN" and rawKey == "" then
      Dibs.Message("Usage: /dibs ejsub allow <SUB_CATEGORY>")
      return
    end
    if key == "CATALYST" or key == "CATALYSTS" then
      Dibs.Message("EJ sub-category CATALYST is personal and always blocked from Dibs.")
      refreshLootRowButtons(true)
      return
    end
    local saved = setSubCategoryBlocked(key, false)
    Dibs.Message("EJ sub-category allowed: " .. tostring(saved))
    refreshLootRowButtons(true)
    return
  end

  if subAction == "clear" then
    if not canModifyDibsSettings() then
      Dibs.Message("Only the guild master or an officer may change Dibs settings.")
      return
    end
    local _, blocked = getSubCategorySettings()
    for blockedKey in pairs(blocked) do
      blocked[blockedKey] = nil
    end
    Dibs.Message("EJ sub-category denylist cleared.")
    refreshLootRowButtons(true)
    return
  end

  Dibs.Message("Usage: /dibs ejsub list|scan|matrix|apply recommended|block <SUB>|allow <SUB>|clear")
end

local function hideActionButtonTooltip()
  if type(GameTooltip) ~= "table" then return end
  if type(GameTooltip.Hide) == "function" then
    GameTooltip:Hide()
  end
end

local function onUseDibsClick(actionButton)
  local function submitForItem(host, item)
    local request, reason = Dibs.EncounterJournal.SubmitPreDib(item.itemID, item.itemLink or item.itemName)
    if request then
      host.__dibsRequestedForItemID = request.itemID
      actionButton.__dibsRequest = request
      if type(actionButton.SetText) == "function" then
        actionButton:SetText("Requested")
      end
      if type(actionButton.Disable) == "function" then
        actionButton:Disable()
      end
      if type(actionButton.SetAlpha) == "function" then
        actionButton:SetAlpha(0.75)
      end
      if Dibs and Dibs.Message then
        Dibs.Message("Pre-Dib request sent for item " .. tostring(request.itemID) .. ".")
      end
    else
      if Dibs and Dibs.Message then
        if reason == "PUBLIC_PRE_DIBS_DISABLED" then
          Dibs.Message("Public pre-dibs are disabled.")
        else
          Dibs.Message("Unable to submit pre-dib request.")
        end
      end
    end
  end

  local host = actionButton and actionButton.__dibsHostButton
  local item = getLootButtonItem(host)
  local debugInfo = getItemDebugDetailsCached(item)
  local subCategory = tostring(debugInfo and debugInfo.subCategory or "UNKNOWN")

  if isRaidEncounterJournalContext() ~= true then
    if Dibs and Dibs.Message then
      Dibs.Message("Dib from Adventure Guide is available only for raid loot.")
    end
    if type(actionButton.Disable) == "function" then
      actionButton:Disable()
    end
    if type(actionButton.SetAlpha) == "function" then
      actionButton:SetAlpha(0.6)
    end
    return
  end

  if not item or not tonumber(item.itemID) then
    if Dibs and Dibs.Message then
      Dibs.Message("No valid loot item found on this row.")
    end
    if type(actionButton.Disable) == "function" then
      actionButton:Disable()
    end
    if type(actionButton.SetAlpha) == "function" then
      actionButton:SetAlpha(0.6)
    end
    return
  end

  if isSubCategoryBlocked(subCategory) then
    if Dibs and Dibs.Message then
      Dibs.Message("Dib is blocked for sub-category: " .. tostring(subCategory))
    end
    if type(actionButton.Disable) == "function" then
      actionButton:Disable()
    end
    if type(actionButton.SetAlpha) == "function" then
      actionButton:SetAlpha(0.6)
    end
    return
  end

  local itemLabel = tostring(item.itemName or item.itemLink or ("Item " .. tostring(item.itemID)))
  if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
    if not StaticPopupDialogs.DIBS_CONFIRM_USE_DIBS_EJ then
      StaticPopupDialogs.DIBS_CONFIRM_USE_DIBS_EJ = {
        text = "Use Dib for %s? This action is monitored and a message can be sent to bids channels.",
        button1 = "Confirm",
        button2 = "Cancel",
        OnAccept = function(self)
          local data = self and self.data
          if type(data) == "table" and data.actionButton and data.host and data.item then
            submitForItem(data.host, data.item)
          end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
    end
    local popup = StaticPopup_Show("DIBS_CONFIRM_USE_DIBS_EJ", itemLabel)
    if type(popup) == "table" then
      popup.data = {
        actionButton = actionButton,
        host = host,
        item = item,
      }
    end
  else
    submitForItem(host, item)
  end
end

local function ensureRowActionButton(lootButton)
  if type(lootButton) ~= "table" then return nil end
  local actionButton = lootButton.__dibsActionButton
  if type(actionButton) == "table" then
    actionButton.__dibsHostButton = lootButton
    return actionButton
  end

  if type(CreateFrame) ~= "function" then return nil end
  actionButton = CreateFrame("Button", nil, lootButton, "UIPanelButtonTemplate")
  if type(actionButton.SetSize) == "function" then
    actionButton:SetSize(72, 18)
  end
  if type(actionButton.SetPoint) == "function" then
    actionButton:SetPoint("RIGHT", lootButton, "RIGHT", EJ_BUTTON_ANCHOR_X, EJ_BUTTON_ANCHOR_Y)
  end
  if type(actionButton.SetText) == "function" then
    actionButton:SetText("Dib")
  end
  if type(actionButton.SetFrameStrata) == "function" then
    actionButton:SetFrameStrata("DIALOG")
  end
  if type(actionButton.SetFrameLevel) == "function" and type(lootButton.GetFrameLevel) == "function" then
    actionButton:SetFrameLevel(lootButton:GetFrameLevel() + 5)
  end
  actionButton.__dibsHostButton = lootButton
  actionButton:SetScript("OnClick", function(self)
    onUseDibsClick(self)
  end)
  actionButton:SetScript("OnEnter", function(self)
    showActionButtonTooltip(self)
  end)
  actionButton:SetScript("OnLeave", function()
    hideActionButtonTooltip()
  end)

  lootButton.__dibsActionButton = actionButton
  return actionButton
end

local function buildVisibleLootSignature(buttons)
  local parts = {}
  for _, lootButton in ipairs(buttons or {}) do
    if type(lootButton) == "table" and type(lootButton.IsShown) == "function" and lootButton:IsShown() == true then
      local item = getLootButtonItem(lootButton)
      if item and item.itemID then
        table.insert(parts, tostring(item.itemID) .. ":" .. tostring(item.responseType or "default"))
      else
        local nameRegion = lootButton.name or lootButton.Name or lootButton.itemName
        local nameText = ""
        if type(nameRegion) == "table" and type(nameRegion.GetText) == "function" then
          nameText = tostring(nameRegion:GetText() or "")
        end
        table.insert(parts, "name:" .. string.lower(nameText))
      end
    end
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

refreshLootRowButtons = function(force)
  local now = getNowSeconds()
  if not force and Dibs.EncounterJournal.lastRefreshAt and (now - Dibs.EncounterJournal.lastRefreshAt) < EJ_REFRESH_INTERVAL then
    return
  end

  local buttons = getLootScrollButtons()
  if type(buttons) ~= "table" or #buttons == 0 then return end

  if isRaidEncounterJournalContext() ~= true then
    for _, lootButton in ipairs(buttons) do
      local actionButton = type(lootButton) == "table" and lootButton.__dibsActionButton or nil
      if type(actionButton) == "table" and type(actionButton.Hide) == "function" then
        actionButton:Hide()
      end
    end
    Dibs.EncounterJournal.lastRefreshAt = now
    Dibs.EncounterJournal.lastStateSignature = "non-raid-context"
    return
  end

  local publicEnabled = Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() == true
  local policyRev = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetTypePolicyRevision and Dibs.RCLootCouncil.GetTypePolicyRevision() or 0
  local signature = buildVisibleLootSignature(buttons)
  local stateSignature = tostring(signature) .. "|public:" .. tostring(publicEnabled) .. "|rev:" .. tostring(policyRev)
  if not force and Dibs.EncounterJournal.lastStateSignature == stateSignature then
    Dibs.EncounterJournal.lastRefreshAt = now
    return
  end
  Dibs.EncounterJournal.lastStateSignature = stateSignature
  Dibs.EncounterJournal.lastRefreshAt = now
  local journalDifficulty = type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() or nil

  for _, lootButton in ipairs(buttons) do
    if type(lootButton) == "table" then
      local actionButton = ensureRowActionButton(lootButton)
      if type(actionButton) == "table" and type(actionButton.ClearAllPoints) == "function" and type(actionButton.SetPoint) == "function" then
        actionButton:ClearAllPoints()
        actionButton:SetPoint("RIGHT", lootButton, "RIGHT", EJ_BUTTON_ANCHOR_X, EJ_BUTTON_ANCHOR_Y)
      end
      local item = getLootButtonItem(lootButton)
      local debugInfo = getItemDebugDetailsCached(item)
      setActionButtonTypeInfo(actionButton, item, debugInfo)
      if type(actionButton) == "table" and type(actionButton.Show) == "function" and type(actionButton.Hide) == "function" then
        if item and item.itemID then
          if isSubCategoryBlocked(debugInfo and debugInfo.subCategory) then
            actionButton:Hide()
          else
            local request = Dibs.PreDibs and Dibs.PreDibs.GetConfirmedRequestForPlayer
              and Dibs.PreDibs.GetConfirmedRequestForPlayer(
                Dibs.GetPlayerName and Dibs.GetPlayerName() or nil,
                item.itemID,
                Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil,
                journalDifficulty
              ) or nil
            local hasRequest = request ~= nil
            actionButton.__dibsRequest = request
            actionButton.__dibsJournalDifficulty = journalDifficulty
            local acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitionsForItem and Dibs.PreDibs.GetAcquisitionsForItem(item.itemID) or {}
            local isAcquired = false
            for _, record in ipairs(acquisitions) do
              if Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId
                and Dibs.Permissions.CanonicalPlayerId(record.playerName) == Dibs.Permissions.CanonicalPlayerId(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil) then
                isAcquired = true
                break
              end
            end
            if type(actionButton.SetText) == "function" then
              actionButton:SetText(isAcquired and "Acquired" or (hasRequest and "Requested" or "Dib"))
            end
            if hasRequest or isAcquired then
              lootButton.__dibsRequestedForItemID = item.itemID
              if type(actionButton.Disable) == "function" then
                actionButton:Disable()
              end
              if type(actionButton.SetAlpha) == "function" then
                actionButton:SetAlpha(0.75)
              end
            else
              updateButtonState(actionButton)
            end
            actionButton:Show()
          end
        elseif lootRowHasVisibleItem(lootButton) then
          if isLikelyLootEntryRow(lootButton) then
            if type(actionButton.SetText) == "function" then
              actionButton:SetText("Dib")
            end
            if type(actionButton.Disable) == "function" then
              actionButton:Disable()
            end
            if type(actionButton.SetAlpha) == "function" then
              actionButton:SetAlpha(0.6)
            end
            actionButton:Show()
          else
            actionButton:Hide()
          end
        else
          actionButton:Hide()
        end
      end
    end
  end
end

function Dibs.EncounterJournal.GetSubCategoryMatrixValues()
  local known = getSubCategorySettings()
  local values = {}
  local seen = {}

  local function addKey(raw)
    local key = normalizeSubCategoryKey(raw)
    if seen[key] then return end
    seen[key] = true
    local allow, note = getMatrixDecision(key)
    local label = key
    if tostring(note or "") ~= "" then
      label = key .. " - " .. tostring(note)
    end
    label = label .. (allow and " [recommended allow]" or " [recommended block]")
    values[key] = label
  end

  for key in pairs(EJ_SUBCATEGORY_MATRIX) do
    addKey(key)
  end
  for key in pairs(known) do
    addKey(key)
  end

  return values
end

function Dibs.EncounterJournal.IsSubCategoryAllowed(subCategory)
  return isSubCategoryBlocked(subCategory) ~= true
end

function Dibs.EncounterJournal.SetSubCategoryAllowed(subCategory, allowed, actor)
  if not canModifyDibsSettings(actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local key = setSubCategoryBlocked(subCategory, allowed ~= true)
  refreshLootRowButtons(true)
  return key
end

function Dibs.EncounterJournal.ApplyRecommendedSubCategoryMatrix(actor)
  if not canModifyDibsSettings(actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  applyRecommendedSubCategoryMatrix()
  refreshLootRowButtons(true)
  return true
end

local function startRefreshLoop()
  if Dibs.EncounterJournal.refreshLoopActive then return end
  if not (Dibs.Ace3 and type(Dibs.Ace3.ScheduleTimer) == "function")
    and not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then
    return
  end
  Dibs.EncounterJournal.refreshLoopActive = true
  local function tick()
    if not Dibs.EncounterJournal.refreshLoopActive then return end
    local ej = _G.EncounterJournal
    if type(ej) ~= "table" or type(ej.IsShown) ~= "function" then
      Dibs.EncounterJournal.refreshLoopActive = false
      return
    end
    if ej:IsShown() ~= true then
      Dibs.EncounterJournal.refreshLoopActive = false
      return
    end
    refreshLootRowButtons(false)
    if Dibs.Ace3 and type(Dibs.Ace3.ScheduleTimer) == "function" then
      Dibs.Ace3.ScheduleTimer(tick, 0.5)
    else
      C_Timer.After(0.5, tick)
    end
  end
  if Dibs.Ace3 and type(Dibs.Ace3.ScheduleTimer) == "function" then
    Dibs.Ace3.ScheduleTimer(tick, 0.5)
  else
    C_Timer.After(0.5, tick)
  end
end

function Dibs.EncounterJournal.AddActionIfAvailable(attempt)
  attempt = tonumber(attempt) or 0
  if not _G.EncounterJournal then
    if type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" then
      pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
    scheduleRetry(attempt)
    return false
  end

  if type(Dibs.EncounterJournal.button) == "table" and type(Dibs.EncounterJournal.button.Hide) == "function" then
    Dibs.EncounterJournal.button:Hide()
  end

  if type(_G.EncounterJournal.HookScript) == "function" then
    if _G.EncounterJournal.__dibsHooked ~= true then
      _G.EncounterJournal:HookScript("OnShow", function()
        refreshLootRowButtons(true)
        startRefreshLoop()
      end)
      _G.EncounterJournal:HookScript("OnHide", function()
        Dibs.EncounterJournal.refreshLoopActive = false
      end)
      _G.EncounterJournal.__dibsHooked = true
    end
  end

  refreshLootRowButtons(true)
  startRefreshLoop()

  Dibs.EncounterJournal.actionInstalled = true
  return true
end

function Dibs.EncounterJournal.BuildActionLabel()
  return "I want to Dib this"
end

function Dibs.EncounterJournal.OpenForRaidContext(context)
  if type(context) ~= "table" or not tonumber(context.raidId) then return false, "RAID_CONTEXT_UNAVAILABLE" end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "DEFERRED_COMBAT" end
  if type(EncounterJournal_LoadUI) == "function" then pcall(EncounterJournal_LoadUI) end
  if context.encounterId and type(EJ_SelectEncounter) == "function" then
    local ok = pcall(EJ_SelectEncounter, context.encounterId)
    if ok then return true end
  end
  if type(EJ_SelectInstance) == "function" then
    local ok = pcall(EJ_SelectInstance, context.raidId)
    if ok then return true end
  end
  return false, "JOURNAL_UNAVAILABLE"
end

function Dibs.EncounterJournal.CanPreDib(itemID)
  if type(itemID) ~= "number" or itemID <= 0 then
    return false, "INVALID_ITEM"
  end
  if isRaidEncounterJournalContext() ~= true then
    return false, "EJ_NON_RAID_CONTEXT"
  end
  if Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled then
    if Dibs.PreDibs.IsPublicEnabled() ~= true then
      return false, "PUBLIC_PRE_DIBS_DISABLED"
    end
  end
  return true, nil
end

function Dibs.EncounterJournal.SubmitPreDib(itemID, itemName)
  local canPreDib, reason = Dibs.EncounterJournal.CanPreDib(itemID)
  if not canPreDib then
    return nil, reason
  end
  if Dibs.LootPipeline and Dibs.LootPipeline.RequestDibFromContext then
    local instanceType, instanceDifficulty, instanceId = nil, nil, nil
    if type(GetInstanceInfo) == "function" then
      local _, currentType, currentDifficulty, _, _, _, _, currentInstanceId = GetInstanceInfo()
      instanceType, instanceDifficulty, instanceId = currentType, currentDifficulty, currentInstanceId
    end
    local selectedDifficulty = type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() or nil
    local seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
    local policy = Dibs.PreDibs and Dibs.PreDibs.GetModePolicy and Dibs.PreDibs.GetModePolicy(seasonId) or nil
    return Dibs.LootPipeline.RequestDibFromContext({
      source = "encounter-journal",
      isTest = false,
      itemID = itemID,
      itemLink = itemName,
      itemName = itemName,
      owner = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil,
      seasonId = seasonId,
      inRaid = instanceType == "raid",
      raidId = instanceId,
      itemRaidId = getCurrentJournalInstanceID(),
      difficulty = policy and policy.mode == "ENCOUNTER" and instanceDifficulty or selectedDifficulty,
    })
  end
  if Dibs.PreDibs and Dibs.PreDibs.CreatePublic then
    return Dibs.PreDibs.CreatePublic(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, itemID, itemName, Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil, "encounter-journal")
  end
  if Dibs.PreDibs and Dibs.PreDibs.Create then
    return Dibs.PreDibs.Create(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, itemID, itemName, Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  end
  return nil, "PREDIB_UNAVAILABLE"
end

do
  local function handleBootstrapEvent(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= "Blizzard_EncounterJournal" then
      return
    end
    Dibs.EncounterJournal.AddActionIfAvailable(0)
  end

  local registeredWithAce = Dibs.Ace3 and type(Dibs.Ace3.RegisterEvent) == "function"
      and Dibs.Ace3.RegisterEvent("PLAYER_LOGIN", handleBootstrapEvent)
      and Dibs.Ace3.RegisterEvent("ADDON_LOADED", handleBootstrapEvent)
  if not registeredWithAce then
    local bootstrap = CreateFrame("Frame")
    bootstrap:RegisterEvent("PLAYER_LOGIN")
    bootstrap:RegisterEvent("ADDON_LOADED")
    bootstrap:SetScript("OnEvent", handleBootstrapEvent)
  end
end
