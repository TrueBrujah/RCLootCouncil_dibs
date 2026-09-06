local Dibs = _G.Dibs
Dibs.DeveloperMode = Dibs.DeveloperMode or {}

local function ensureDB()
  local db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  db.settings = db.settings or {}
  if db.settings.developerModeEnabled == nil then
    db.settings.developerModeEnabled = false
  end
  return db
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function devMessage(text)
  Dibs.Message("[Dibs DEV] " .. tostring(text))
end

function Dibs.DeveloperMode.IsEnabled()
  local db = ensureDB()
  return db.settings.developerModeEnabled == true
end

function Dibs.DeveloperMode.SetEnabled(enabled)
  local db = ensureDB()
  db.settings.developerModeEnabled = enabled == true
  return db.settings.developerModeEnabled
end

function Dibs.DeveloperMode.GetStatusText()
  if Dibs.DeveloperMode.IsEnabled() then
    return "ENABLED"
  end
  return "DISABLED"
end

function Dibs.DeveloperMode.HandleDevSlash(args)
  local mode = string.lower(tostring(args and args[2] or "status"))
  if mode == "on" then
    Dibs.DeveloperMode.SetEnabled(true)
    devMessage("Developer Mode ENABLED")
    return true
  end
  if mode == "off" then
    Dibs.DeveloperMode.SetEnabled(false)
    devMessage("Developer Mode DISABLED")
    return true
  end
  if mode == "status" or mode == "" then
    devMessage("Developer Mode is " .. Dibs.DeveloperMode.GetStatusText())
    return true
  end

  devMessage("Usage: /dibs dev on | off | status")
  return true
end

function Dibs.DeveloperMode.HandleTestItemSlash(rawArgument)
  if Dibs.DeveloperMode.IsEnabled() ~= true then
    Dibs.Message("Developer Mode is disabled. Use /dibs dev on to enable test commands.")
    return true
  end

  local input = trim(rawArgument)
  if input == "" then
    devMessage("Usage: /dibs testitem <itemID or itemLink>")
    return true
  end

  if not (Dibs.LootPipeline and Dibs.LootPipeline.ResolveItem and Dibs.LootPipeline.ProcessLootItem) then
    devMessage("Loot pipeline is unavailable.")
    return true
  end

  Dibs.LootPipeline.ResolveItem(input, function(item, reason)
    if not item then
      if reason == "INVALID_ITEM" then
        devMessage("Invalid item input.")
      else
        local target = tonumber(tostring(input):match("item:(%d+)")) or tonumber(input) or tostring(input)
        devMessage("Unable to load item " .. tostring(target))
      end
      return
    end

    devMessage("Injecting test item: " .. tostring(item.itemName) .. " (" .. tostring(item.itemID) .. ")")
    local context = {
      source = "DEV",
      isTest = true,
      itemID = item.itemID,
      itemName = item.itemName,
      itemLink = item.itemLink,
      lootSlot = nil,
      owner = Dibs.GetPlayerName and Dibs.GetPlayerName() or UnitName("player"),
      seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil,
      createdAt = time(),
    }

    local eventContext, processReason = Dibs.LootPipeline.ProcessLootItem(context)
    if not eventContext then
      devMessage("Injection failed: " .. tostring(processReason or "unknown"))
      return
    end

    if Dibs.PlayerUI and Dibs.PlayerUI.SetDevContext then
      Dibs.PlayerUI.SetDevContext(eventContext)
    end
  end)

  return true
end
