--[[
Module: Dibs.LootPipeline
Layer: Application / loot adapter
Purpose: Normalize item context and connect Pre-Dibs requests to award validation.
Responsibilities: Resolve semantic item families and process qualifying award context.
Non-responsibilities: It does not transfer loot or replace RC voting.
Dependencies: RCLootCouncil, PreDibs, CharacterEligibility, Ledger.
Blizzard events: None directly.
Internal events/messages: Uses RC award callbacks through the integration.
SavedVariables: Indirectly through Ledger and PreDibs.
RCLootCouncil: Primary optional integration point for item/award context.
Combat safety: Award finalization obeys ProtectedActions and DIBS-RULE-009.
Related docs: docs/developer/rclc-integration.md.
]]

local Dibs = _G.Dibs
Dibs.LootPipeline = Dibs.LootPipeline or {}

local function buildItemLink(itemID, itemName)
  local id = tonumber(itemID) or 0
  local label = itemName or ("Item " .. tostring(id))
  return string.format("|cffffffff|Hitem:%d::::::::::::|h[%s]|h|r", id, tostring(label))
end

local function ensureRuntimeState()
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.dev = Dibs.runtime.dev or {}
  Dibs.runtime.dev.requests = Dibs.runtime.dev.requests or {}
end

local function cloneContext(context)
  local copy = {}
  for key, value in pairs(context or {}) do
    copy[key] = value
  end
  return copy
end

local function markDevMessage(text)
  if Dibs and Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() then
    Dibs.Message("[Dibs DEV] " .. tostring(text))
  end
end

function Dibs.LootPipeline.ResolveItem(input, callback)
  local done = callback
  if type(done) ~= "function" then
    return false
  end

  local token = tostring(input or ""):match("^%s*(.-)%s*$")
  local fromLink = tonumber(token:match("item:(%d+)"))
  local fromNumber = tonumber(token:match("^(%d+)$"))
  local itemID = tonumber(fromLink or fromNumber)
  if (not itemID or itemID <= 0) and type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    local _, guessedLink = C_Item.GetItemInfo(token)
    if type(guessedLink) == "string" then
      itemID = tonumber(guessedLink:match("item:(%d+)"))
    end
  end
  if not itemID or itemID <= 0 then
    done(nil, "INVALID_ITEM")
    return true
  end

  local function finalize(name, link)
    local itemName = name
    local itemLink = link

    if (itemName == nil or itemName == "") and type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
      local liveName, liveLink = C_Item.GetItemInfo(itemID)
      itemName = liveName or itemName
      itemLink = liveLink or itemLink
    end

    local hasName = type(itemName) == "string" and itemName ~= ""
    local hasLink = type(itemLink) == "string" and itemLink ~= ""
    if not hasName and not hasLink then
      done(nil, "ITEM_LOAD_FAILED")
      return
    end

    if not hasName then
      itemName = "Item " .. tostring(itemID)
    end
    if not hasLink then
      itemLink = buildItemLink(itemID, itemName)
    end

    done({ itemID = itemID, itemName = itemName, itemLink = itemLink }, nil)
  end

  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    local instantName, instantLink = C_Item.GetItemInfo(itemID)
    if instantName or instantLink then
      finalize(instantName, instantLink)
      return true
    end
  end

  if type(Item) == "table" and type(Item.CreateFromItemID) == "function" then
    local ok, itemObject = pcall(Item.CreateFromItemID, itemID)
    if ok and type(itemObject) == "table" and type(itemObject.ContinueOnItemLoad) == "function" then
      itemObject:ContinueOnItemLoad(function()
        local loadedName, loadedLink = nil, nil
        if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
          loadedName, loadedLink = C_Item.GetItemInfo(itemID)
        end
        finalize(loadedName, loadedLink)
      end)
      return true
    end
  end

  done(nil, "ITEM_LOAD_FAILED")
  return true
end

function Dibs.LootPipeline.ProcessLootItem(context)
  if type(context) ~= "table" then
    return nil, "INVALID_CONTEXT"
  end

  local itemID = tonumber(context.itemID)
  if not itemID or itemID <= 0 then
    return nil, "INVALID_ITEM"
  end

  local eventContext = cloneContext(context)
  eventContext.itemID = itemID
  eventContext.itemName = eventContext.itemName or ("Item " .. tostring(itemID))
  eventContext.itemLink = eventContext.itemLink or buildItemLink(itemID, eventContext.itemName)
  eventContext.owner = eventContext.owner or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "UnknownPlayer")
  eventContext.source = eventContext.source or "UNKNOWN"
  eventContext.isTest = eventContext.isTest == true

  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.lastLootContext = eventContext
  if eventContext.isTest then
    ensureRuntimeState()
    Dibs.runtime.dev.pendingLootContext = eventContext
    markDevMessage("Source: " .. tostring(eventContext.source))
    markDevMessage("Request Dib opened for item " .. tostring(eventContext.itemID))
  end

  if Dibs.PlayerUI and Dibs.PlayerUI.Show then
    Dibs.PlayerUI.Show()
  end
  if Dibs.PlayerUI and Dibs.PlayerUI.SetDevContext then
    Dibs.PlayerUI.SetDevContext(eventContext)
  end

  return eventContext, nil
end

function Dibs.LootPipeline.RequestDibFromContext(context)
  if type(context) ~= "table" then
    return nil, "INVALID_CONTEXT"
  end

  local itemID = tonumber(context.itemID)
  if not itemID or itemID <= 0 then
    return nil, "INVALID_ITEM"
  end

  local itemName = context.itemLink or context.itemName or ("Item " .. tostring(itemID))
  local seasonId = context.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local playerName = context.owner or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)

  if context.isTest == true then
    if not (Dibs.PreDibs and Dibs.PreDibs.CreateTest) then
      return nil, "PREDIB_UNAVAILABLE"
    end
    local request = Dibs.PreDibs.CreateTest(playerName, itemID, itemName, seasonId, context.source or "DEV", context)
    if request then
      return request, nil
    end
    return nil, "REQUEST_FAILED"
  end

  if Dibs.PreDibs and Dibs.PreDibs.CreatePublic and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() then
    return Dibs.PreDibs.CreatePublic(playerName, itemID, itemName, seasonId, context.source or "loot-pipeline", context)
  end

  if Dibs.PreDibs and Dibs.PreDibs.Create then
    local request = Dibs.PreDibs.Create(playerName, itemID, itemName, seasonId)
    if request then
      return request, nil
    end
    return nil, "REQUEST_FAILED"
  end

  return nil, "PREDIB_UNAVAILABLE"
end

function Dibs.LootPipeline.GetPendingDevContext()
  ensureRuntimeState()
  return Dibs.runtime.dev.pendingLootContext
end
