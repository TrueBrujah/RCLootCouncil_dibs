local Dibs = _G.Dibs
Dibs.DebugLogs = Dibs.DebugLogs or { entries = {}, maxEntries = 300 }

local function canViewDebugLogs(actor)
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return false
  end
  local ok, role = pcall(Dibs.Permissions.GetGuildRole, actor)
  return ok and (role == "gm" or role == "officer")
end

function Dibs.DebugLogs.Add(module, level, message)
  local severity = ({ [1] = "ERROR", [2] = "WARNING", [3] = "INFO", [4] = "DEBUG", [5] = "VERBOSE" })[tonumber(level) or 3] or "INFO"
  table.insert(Dibs.DebugLogs.entries, { timestamp = time(), module = tostring(module or "core"), level = tonumber(level) or 3, severity = severity, message = tostring(message or "") })
  while #Dibs.DebugLogs.entries > Dibs.DebugLogs.maxEntries do table.remove(Dibs.DebugLogs.entries, 1) end
end

function Dibs.DebugLogs.Clear(actor)
  if not canViewDebugLogs(actor) then return false, "GUILD_ADMIN_REQUIRED" end
  Dibs.DebugLogs.entries = {}
  return true
end

function Dibs.DebugLogs.Open(actor)
  if not canViewDebugLogs(actor) then return false, "GUILD_ADMIN_REQUIRED" end
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local shell = Dibs.AceGUI.CreateWindow("Dibs Debug Logs", 900, 650, { "CENTER", 0, 0 })
  if not shell then return false end
  local query, sortKey, descending = "", "timestamp", true
  local filterLevel
  local refresh
  local tabs = Dibs.AceGUI.AddTabs(shell, {
    { text = "All", value = "all" }, { text = "Errors", value = "1" }, { text = "Warnings", value = "2" }, { text = "Info", value = "3" }, { text = "Debug", value = "4" }, { text = "Verbose", value = "5" },
  }, function(value) filterLevel = value == "all" and nil or tonumber(value); if refresh then refresh() end end)
  refresh = function()
    Dibs.AceGUI.Clear(tabs)
    local integration = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or nil
    if integration then
      Dibs.AceGUI.AddLabel(shell, tabs, "RCLootCouncil: " .. tostring(integration.status or integration.availability or "absent") ..
        " | " .. tostring(integration.reasonCode or "UNKNOWN") .. "\n" .. tostring(integration.diagnostic or ""), true)
    end
    if Dibs.Readiness and type(Dibs.Readiness.GetStatusText) == "function" then
      Dibs.AceGUI.AddLabel(shell, tabs, "Raid readiness: " .. Dibs.Readiness.GetStatusText(true), true)
      local report = Dibs.AceGUI.AddButton(shell, tabs, "Copy readiness report", function()
        Dibs.Readiness.CopyReport("detailed")
      end, 180)
      Dibs.AceGUI.AddTooltip(report, "Readiness report", "Prints bounded Officer diagnostics without live candidates, votes or private loot state.")
    end
    local searchBox = Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value) query = value; refresh() end, 420)
    Dibs.AceGUI.AddTooltip(searchBox, "Search logs", "Search module names, severity labels and message text.")
    local sort = Dibs.AceGUI.AddDropdown(shell, tabs, "Sort by", { timestamp = "Time", module = "Module", level = "Severity" }, function(value) sortKey = value; refresh() end, 180)
    Dibs.AceGUI.SetValue(sort, sortKey)
    Dibs.AceGUI.AddButton(shell, tabs, descending and "Descending" or "Ascending", function() descending = not descending; refresh() end, 120)
    local rows = {}
    for _, entry in ipairs(Dibs.DebugLogs.entries) do
      if (not filterLevel or entry.level == filterLevel) and (query == "" or string.find(string.lower(entry.module .. " " .. entry.severity .. " " .. entry.message), string.lower(query), 1, true)) then
        rows[#rows + 1] = string.format("%s | %-8s | %-18s | %s", date("%Y-%m-%d %H:%M:%S", entry.timestamp), entry.severity, entry.module, entry.message)
      end
    end
    table.sort(rows, function(a, b) return descending and a > b or a < b end)
    if #rows == 0 then rows[1] = "No matching debug logs." end
    Dibs.AceGUI.AddLabel(shell, tabs, table.concat(rows, "\n"), true)
    local clear = Dibs.AceGUI.AddButton(shell, tabs, "Clear logs", function() Dibs.DebugLogs.Clear(); refresh() end, 130)
    Dibs.AceGUI.AddTooltip(clear, "Clear logs", "Deletes the in-memory diagnostic log. This does not change the Dibs ledger.")
  end
  refresh()
  shell.window:Show()
  return true
end
