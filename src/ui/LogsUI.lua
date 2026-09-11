local Dibs = _G.Dibs
Dibs.LogsUI = Dibs.LogsUI or {}

local function canViewOfficerLogs()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return false
  end
  local ok, role = pcall(Dibs.Permissions.GetGuildRole, nil)
  return ok and (role == "gm" or role == "officer")
end

local function formatDate(timestamp)
  local value = tonumber(timestamp) or 0
  if value > 0 and type(date) == "function" then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", value)
    if ok and formatted then return tostring(formatted) end
  end
  return value > 0 and tostring(value) or "Unknown"
end

local function splitLine(line, expected)
  local cells = {}
  for cell in (tostring(line or "") .. "|"):gmatch("(.-)|") do
    cells[#cells + 1] = cell:match("^%s*(.-)%s*$")
  end
  while #cells < (expected or 1) do cells[#cells + 1] = "" end
  return cells
end

local function setControlText(control, value)
  if control and control.SetText then control:SetText(value or "") end
end

local function openTable(title, columns, rows, width, height)
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local shell = Dibs.AceGUI.CreateWindow(title or "Dibs Logs", width or 900, height or 620, { "CENTER", 0, 0 })
  if not shell then return false end
  local page = Dibs.AceGUI.AddScrollableList(shell, shell.window, (height or 620) - 110)
  Dibs.AceGUI.AddHeading(shell, page, title or "Dibs Logs", "Click a column header to sort. Right-click a row or header for more choices.")
  Dibs.AceGUI.AddTable(shell, page, columns, rows, (height or 620) - 170)
  shell.window:Show()
  return true
end

function Dibs.LogsUI.Open(title, lines)
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local shell = Dibs.AceGUI.CreateWindow(title or "Dibs Logs", 760, 560, { "CENTER", 0, 0 })
  if not shell then return false end
  local scroll = Dibs.AceGUI.AddScrollableList(shell, shell.window, 460)
  Dibs.AceGUI.AddHeading(shell, scroll, title or "Dibs Logs", "Select the text with Ctrl+A, then copy with Ctrl+C.")
  Dibs.AceGUI.AddSelectableText(shell, scroll, "", table.concat(lines or { "No log entries." }, "\n"), 700, 420)
  shell.window:Show()
  return true
end

function Dibs.LogsUI.OpenPlayerHistory()
  local rows = {}
  for _, tx in ipairs(Dibs.PlayerUI.GetHistory()) do
    rows[#rows + 1] = {
      formatDate(tx.createdAt or tx.timestamp),
      tostring(tx.type or tx.actionType or "UNKNOWN"),
      tostring(tx.amount or tx.quantityDelta or 0),
      tostring(tx.reason or ""),
    }
  end
  if #rows == 0 then rows[1] = { "", "No history entries", "", "" } end
  return openTable("Player History", {
    { title = "Date", width = 150, tooltip = "When the ledger entry was recorded." },
    { title = "Action", width = 150, tooltip = "The ledger operation." },
    { title = "Amount", width = 80, align = "RIGHT", tooltip = "Dibs gained or spent." },
    { title = "Reason", width = 360, tooltip = "Why the entry was created." },
  }, rows, 900, 560)
end

function Dibs.LogsUI.OpenPlayerAcquisitions()
  local rows = {}
  for _, record in ipairs(Dibs.PlayerUI.GetSummary().acquisitions or {}) do
    rows[#rows + 1] = {
      formatDate(record.acquiredAt or record.createdAt),
      tostring(record.itemLink or record.itemName or ("Item " .. tostring(record.itemID))),
      tostring(record.difficulty or "UNKNOWN"),
      tostring(record.source or "VAULT"),
    }
  end
  if #rows == 0 then rows[1] = { "", "No acquisitions", "", "" } end
  return openTable("Player Acquisitions", {
    { title = "Date", width = 150, tooltip = "When the acquisition was recorded." },
    { title = "Item", width = 330, tooltip = "Acquired item." },
    { title = "Difficulty", width = 120, tooltip = "Normal, Heroic, Mythic or Vault tier." },
    { title = "Source", width = 180, tooltip = "Where the acquisition was recorded." },
  }, rows, 900, 560)
end

function Dibs.LogsUI.OpenOfficer(view, seasonId, query)
  if not canViewOfficerLogs() then return false, "GUILD_ADMIN_REQUIRED" end
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local shell = Dibs.AceGUI.CreateWindow("Officer Logs", 1020, 700, { "CENTER", 0, 0 })
  if not shell then return false end
  local selectedView, search, pageNumber = view or "players", query or "", 1
  local refresh
  local tabs = Dibs.AceGUI.AddTabs(shell, {
    { text = "Players", value = "players" }, { text = "Pre-Dibs", value = "predibs" }, { text = "History", value = "actions" },
  }, function(value) selectedView, pageNumber = value, 1; refresh() end)
  refresh = function()
    Dibs.AceGUI.Clear(tabs)
    local page = Dibs.OfficerUI.GetPagedView(selectedView, seasonId, pageNumber, 25, search)
    Dibs.AceGUI.AddHeading(shell, tabs, page.title .. "  |  " .. tostring(page.totalCount) .. " entries", "Click a column header to sort ascending or descending. Right-click for the same choices in a menu.")
    local searchBox = Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value)
      search, pageNumber = value or "", 1
      refresh()
    end, 360)
    setControlText(searchBox, search)
    Dibs.AceGUI.AddButton(shell, tabs, "Clear", function() search, pageNumber = "", 1; refresh() end, 70)
    local expected, columns
    if selectedView == "actions" then
      expected = 5
      columns = {
        { title = "Date", width = 155, tooltip = "When the ledger entry was recorded." },
        { title = "Player", width = 160, tooltip = "Guild member affected." },
        { title = "Action", width = 150, tooltip = "Ledger operation." },
        { title = "Amount", width = 85, align = "RIGHT", tooltip = "Dibs gained or spent." },
        { title = "Reason", width = 360, tooltip = "Audit context." },
      }
    elseif selectedView == "predibs" then
      expected = 7
      columns = {
        { title = "Date", width = 155, tooltip = "Request creation time." },
        { title = "Player", width = 145, tooltip = "Player who requested the item." },
        { title = "Status", width = 100, tooltip = "Request lifecycle state." },
        { title = "Item", width = 240, tooltip = "Reserved item." },
        { title = "Difficulty", width = 100, tooltip = "Requested difficulty." },
        { title = "Mode", width = 110, tooltip = "Wild Open or Encounter." },
        { title = "Sync", width = 120, tooltip = "Delivery acknowledgement." },
      }
    else
      expected = 3
      columns = {
        { title = "Player", width = 300, tooltip = "Guild member." },
        { title = "Balance", width = 130, align = "RIGHT", tooltip = "Current Dibs balance." },
        { title = "Actions", width = 130, align = "RIGHT", tooltip = "Number of ledger entries." },
      }
    end
    local rows = {}
    for _, line in ipairs(page.lines or {}) do rows[#rows + 1] = splitLine(line, expected) end
    Dibs.AceGUI.AddTable(shell, tabs, columns, rows, 500)
    local previous = Dibs.AceGUI.AddButton(shell, tabs, "Previous", function() pageNumber = math.max(1, pageNumber - 1); refresh() end, 95)
    Dibs.AceGUI.AddLabel(shell, tabs, "Page " .. tostring(page.page) .. "/" .. tostring(page.totalPages))
    local nextButton = Dibs.AceGUI.AddButton(shell, tabs, "Next", function() pageNumber = math.min(page.totalPages, pageNumber + 1); refresh() end, 75)
    Dibs.AceGUI.SetDisabled(previous, page.page <= 1)
    Dibs.AceGUI.SetDisabled(nextButton, page.page >= page.totalPages)
  end
  refresh()
  shell.window:Show()
  return true
end
