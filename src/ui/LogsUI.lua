local Dibs = _G.Dibs
Dibs.LogsUI = Dibs.LogsUI or {}

local function canViewOfficerLogs()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return false
  end
  local ok, role = pcall(Dibs.Permissions.GetGuildRole, nil)
  return ok and (role == "gm" or role == "officer")
end

function Dibs.LogsUI.Open(title, lines)
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local shell = Dibs.AceGUI.CreateWindow(title or "Dibs Logs", 760, 560, { "CENTER", 0, 0 })
  if not shell then return false end
  local scroll = Dibs.AceGUI.AddScrollableList(shell, shell.window, 460)
  Dibs.AceGUI.AddLabel(shell, scroll, table.concat(lines or { "No log entries." }, "\n"), true)
  shell.window:Show()
  return true
end

function Dibs.LogsUI.OpenPlayerHistory()
  local lines = {}
  for _, tx in ipairs(Dibs.PlayerUI.GetHistory()) do
    lines[#lines + 1] = tostring(tx.createdAt or tx.timestamp or "") .. " | " .. tostring(tx.type) .. " | " .. tostring(tx.amount or tx.quantityDelta or 0) .. " | " .. tostring(tx.reason or "")
  end
  return Dibs.LogsUI.Open("Player History", lines)
end

function Dibs.LogsUI.OpenPlayerAcquisitions()
  local lines = { "Great Vault acquisitions" }
  for _, record in ipairs(Dibs.PlayerUI.GetSummary().acquisitions or {}) do
    lines[#lines + 1] = tostring(record.itemID) .. " | " .. tostring(record.difficulty or "UNKNOWN") .. " | Acquired"
  end
  return Dibs.LogsUI.Open("Player Acquisitions", lines)
end

function Dibs.LogsUI.OpenOfficer(view, seasonId, query)
  if not canViewOfficerLogs() then return false, "GUILD_ADMIN_REQUIRED" end
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local shell = Dibs.AceGUI.CreateWindow("Officer Logs", 900, 650, { "CENTER", 0, 0 })
  if not shell then return false end
  local selectedView, search, pageNumber = view or "players", query or "", 1
  local refresh
  local tabs = Dibs.AceGUI.AddTabs(shell, {
    { text = "Players", value = "players" }, { text = "Pre-Dibs", value = "predibs" }, { text = "History", value = "actions" },
  }, function(value) selectedView, pageNumber = value, 1; refresh() end)
  refresh = function()
    Dibs.AceGUI.Clear(tabs)
    local page = Dibs.OfficerUI.GetPagedView(selectedView, seasonId, pageNumber, 15, search)
    Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value) search, pageNumber = value, 1; refresh() end, 360)
    Dibs.AceGUI.AddLabel(shell, tabs, table.concat(page.lines, "\n"), true)
    Dibs.AceGUI.AddButton(shell, tabs, "Previous", function() pageNumber = math.max(1, pageNumber - 1); refresh() end, 120)
    Dibs.AceGUI.AddLabel(shell, tabs, "Page " .. page.page .. "/" .. page.totalPages)
    Dibs.AceGUI.AddButton(shell, tabs, "Next", function() pageNumber = math.min(page.totalPages, pageNumber + 1); refresh() end, 120)
  end
  refresh()
  shell.window:Show()
  return true
end
