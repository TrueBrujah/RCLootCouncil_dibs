--[[
Module: Dibs.DeveloperMode
Layer: Test/developer support
Purpose: Gate diagnostic and test slash commands.
Responsibilities: Developer-mode status, toggles, and test item command dispatch.
Non-responsibilities: It does not change production allocation rules.
Dependencies: Permissions, Core, EncounterJournal, DryRun.
Blizzard events: None directly.  Internal events/messages: Debug output only.
SavedVariables: db.settings.developerModeEnabled.
RCLootCouncil: Test helpers can inspect integration capabilities.
Combat safety: Test commands must not bypass ProtectedActions.
Related docs: docs/developer/testing.md.
]]

local Dibs = _G.Dibs
Dibs.DeveloperMode = Dibs.DeveloperMode or {}

local function ensureDB()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings() or {}
  if settings.developerModeEnabled == nil then
    settings.developerModeEnabled = false
  end
  return settings
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function devMessage(text)
  Dibs.Message("[Dibs DEV] " .. tostring(text))
end

function Dibs.DeveloperMode.IsEnabled()
  local settings = ensureDB()
  return settings.developerModeEnabled == true
end

function Dibs.DeveloperMode.SetEnabled(enabled)
  local settings = ensureDB()
  settings.developerModeEnabled = enabled == true
  return settings.developerModeEnabled
end

function Dibs.DeveloperMode.GetStatusText()
  if Dibs.DeveloperMode.IsEnabled() then
    return "ENABLED"
  end
  return "DISABLED"
end

local function sandboxStatusText()
  if Dibs.DeveloperSandbox and Dibs.DeveloperSandbox.GetStatus then
    local status = Dibs.DeveloperSandbox.GetStatus()
    return "sandbox=" .. (status.active and "ACTIVE" or "INACTIVE")
      .. ", provider=" .. tostring(status.provider)
      .. ", role=" .. tostring(status.role or "none")
      .. ", warning=" .. tostring(status.warning)
  end
  return "sandbox=UNAVAILABLE"
end

function Dibs.DeveloperMode.HandleDevSlash(args)
  local mode = string.lower(tostring(args and args[2] or "status"))
  if mode == "on" then
    Dibs.DeveloperMode.SetEnabled(true)
    devMessage("Developer Mode ENABLED")
    return true
  end
  if mode == "off" then
    if Dibs.DeveloperSandbox and Dibs.DeveloperSandbox.IsActive and Dibs.DeveloperSandbox.IsActive() then
      Dibs.DeveloperSandbox.ExitSandbox()
    end
    Dibs.DeveloperMode.SetEnabled(false)
    devMessage("Developer Mode DISABLED")
    return true
  end
  if mode == "status" or mode == "" then
    devMessage("Developer Mode is " .. Dibs.DeveloperMode.GetStatusText() .. " (" .. sandboxStatusText() .. ")")
    return true
  end

  if mode == "sandbox" then
    local operation = string.lower(tostring(args and args[3] or "status"))
    local sandbox = Dibs.DeveloperSandbox
    if not sandbox then
      devMessage("Developer sandbox is unavailable.")
      return true
    end
    local ok, result
    if operation == "enter" then ok, result = sandbox.EnterSandbox({ clone = args[4] == "clone" })
    elseif operation == "refresh" then ok, result = sandbox.RefreshSandbox()
    elseif operation == "reset" then ok, result = sandbox.ResetSandbox()
    elseif operation == "exit" then ok, result = sandbox.ExitSandbox()
    elseif operation == "status" or operation == "" then
      devMessage(sandboxStatusText())
      return true
    else
      devMessage("Usage: /dibs dev sandbox enter|refresh|reset|exit|status")
      return true
    end
    devMessage(ok and ("Sandbox " .. operation .. " OK") or ("Sandbox " .. operation .. " failed: " .. tostring(result)))
    return true
  end

  devMessage("Usage: /dibs dev on | off | status | sandbox enter|refresh|reset|exit|status")
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
