local Dibs = _G.Dibs
Dibs.DataUI = Dibs.DataUI or {}
local UI = Dibs.DataUI
local currentShell
local state = { tab = "backups", scope = "local", strategy = "merge", importText = "", selectedSnapshot = nil, selectedPreview = nil, status = "" }

local function labelDate(value)
  if not value then return "Unknown" end
  return date("%Y-%m-%d %H:%M", tonumber(value) or 0)
end
local function clear(shell) if Dibs.AceGUI and Dibs.AceGUI.Clear then Dibs.AceGUI.Clear(shell.pageHost or shell.window) end end
local function tableRows()
  local rows = {}
  for _, snapshot in ipairs(Dibs.Backup.List()) do
    table.insert(rows, { labelDate(snapshot.createdAt), snapshot.scope, tostring(snapshot.size or 0), tostring(snapshot.checksum or ""), "Select", id = snapshot.snapshotId })
  end
  return rows
end
local function addBackups(shell, parent)
  local gui = Dibs.AceGUI; gui.AddHeading(shell, parent, "Safety backups", "A backup is created automatically before restore and full-data import.")
  gui.AddButton(shell, parent, "Create backup", function() local snap = Dibs.Backup.Create("full", "manual", nil); state.selectedSnapshot = snap and snap.snapshotId; UI.Refresh() end, 140)
  gui.AddButton(shell, parent, "Retention: " .. tostring(Dibs.Backup.DEFAULT_RETENTION), function() end, 140)
  gui.AddTable(shell, parent, {
    { name = "Date", key = "date", width = 145 }, { name = "Scope", key = "scope", width = 90 }, { name = "Size", key = "size", width = 70 }, { name = "Checksum", key = "checksum", width = 100 }, { name = "Action", key = "action", width = 80, action = true },
  }, tableRows(), 360, function(row) return { text = "Select", callback = function() state.selectedSnapshot = row.id; UI.Refresh() end } end, { defaultSortColumn = 1 })
  if state.selectedSnapshot then
    gui.AddLabel(shell, parent, "Selected: " .. tostring(state.selectedSnapshot), true)
    gui.AddButton(shell, parent, "Preview restore", function() local preview = Dibs.Backup.PreviewRestore(state.selectedSnapshot); state.selectedPreview = preview and preview.previewId; UI.Refresh() end, 140)
  end
  if state.selectedPreview then
    gui.AddLabel(shell, parent, "Restore preview " .. tostring(state.selectedPreview) .. ": no active data changes yet.", true)
    gui.AddButton(shell, parent, "Confirm restore", function() Dibs.Backup.Restore(state.selectedPreview, true, "confirmed by user", nil); state.selectedPreview = nil; UI.Refresh() end, 140)
    gui.AddButton(shell, parent, "Cancel restore", function() Dibs.Backup.Restore(state.selectedPreview, false, "cancelled", nil); state.selectedPreview = nil; UI.Refresh() end, 120)
  end
end
local function addProfiles(shell, parent)
  local gui = Dibs.AceGUI; gui.AddHeading(shell, parent, "Configuration profiles", "Profiles never delete or rewrite the append-only Dibs ledger.")
  if state.status ~= "" then gui.AddLabel(shell, parent, state.status, true) end
  gui.AddTable(shell, parent, { { name = "Name", key = "name", width = 180 }, { name = "Scope", key = "scope", width = 90 }, { name = "Updated", key = "updated", width = 150 }, { name = "Action", key = "action", width = 90, action = true } }, (function() local rows = {}; for _, scope in ipairs({ "local", "guild" }) do for _, p in ipairs(Dibs.Profiles.List(scope)) do table.insert(rows, { p.name, scope, labelDate(p.updatedAt), "Activate", profile = p, name = p.name, scope = scope }) end end; return rows end)(), function(row) return { text = "Activate", callback = function() local value, reason, preview = Dibs.Profiles.Activate(row.name, row.scope, nil, state.profileConfirm == row.name); if value then state.status = "Profile activated: " .. row.name; state.profileConfirm = nil elseif reason == "POLICY_CONFIRM_REQUIRED" then state.status = "Policy changes in " .. row.name .. ": " .. table.concat(preview and preview.policyChanges or {}, ", ") .. ". Click Activate again to confirm."; state.profileConfirm = row.name else state.status = tostring(reason) end; UI.Refresh() end } end, { defaultSortColumn = 3 })
  gui.AddButton(shell, parent, "Create local profile", function() Dibs.Profiles.Create("New profile", "local"); UI.Refresh() end, 160)
end
local function addTransfer(shell, parent)
  local gui = Dibs.AceGUI; gui.AddHeading(shell, parent, "Import / export", "Choose a scope, review the preview, then explicitly confirm changes.")
  gui.AddMSADropdown(shell, parent, "Export scope", { ["local"] = "Local presentation", guild = "Guild configuration", full = "Full Dibs data (sensitive)" }, function(value) state.scope = value end, 260)
  gui.AddButton(shell, parent, "Export package", function() local text = Dibs.ImportExport.Export(state.scope, { redacted = state.scope ~= "local" }); state.exportText = text; UI.Refresh() end, 140)
  if state.exportText then gui.AddSelectableText(shell, parent, "Package (copy this text)", state.exportText, 700, 180) end
  gui.AddEditBox(shell, parent, "Paste package to import", function(value) state.importText = value end, 700)
  gui.AddMSADropdown(shell, parent, "Import strategy", { merge = "Merge settings", replace = "Replace settings", append = "Append ledger (deduplicate)" }, function(value) state.strategy = value end, 260)
  gui.AddButton(shell, parent, "Validate and preview", function() local preview = Dibs.ImportExport.Preview(state.importText, state.scope, state.strategy); state.selectedPreview = preview and preview.previewId; UI.Refresh() end, 170)
  if state.selectedPreview then gui.AddLabel(shell, parent, "Preview " .. tostring(state.selectedPreview) .. " is ready. Confirm only after reviewing the scope and impact.", true); gui.AddButton(shell, parent, "Confirm import", function() Dibs.ImportExport.Apply(state.selectedPreview, true, "confirmed by user", nil); state.selectedPreview = nil; UI.Refresh() end, 140); gui.AddButton(shell, parent, "Cancel import", function() Dibs.ImportExport.Apply(state.selectedPreview, false, "cancelled", nil); state.selectedPreview = nil; UI.Refresh() end, 120) end
end
function UI.Refresh()
  if not currentShell then return end
  clear(currentShell); local parent = currentShell.window; if state.tab == "profiles" then addProfiles(currentShell, parent) elseif state.tab == "transfer" then addTransfer(currentShell, parent) else addBackups(currentShell, parent) end
end
function UI.Open(tab)
  if currentShell and currentShell.frame then state.tab = tab or state.tab; currentShell.window:Show(); UI.Refresh(); return currentShell end
  local shell = Dibs.AceGUI and Dibs.AceGUI.CreateWindow and Dibs.AceGUI.CreateWindow("RCLootCouncil - Dibs | Data", 900, 680, { "CENTER", 0, 0 }); if not shell then return nil end
  currentShell = shell; state.tab = tab or "backups"; local gui = Dibs.AceGUI; gui.AddTabs(shell, { { value = "backups", text = "Backups" }, { value = "profiles", text = "Profiles" }, { value = "transfer", text = "Import / Export" } }, function(value) state.tab = value; UI.Refresh() end); shell.pageHost = gui.Create(shell, "SimpleGroup", shell.window); if shell.pageHost then shell.pageHost:SetFullWidth(true); shell.pageHost:SetFullHeight(true); shell.pageHost:SetLayout("Flow") end; UI.Refresh(); shell.window:Show(); return shell
end
function UI.Toggle(tab) if currentShell and currentShell.frame then currentShell.window:Hide(); currentShell = nil; return nil end; return UI.Open(tab) end
return UI
