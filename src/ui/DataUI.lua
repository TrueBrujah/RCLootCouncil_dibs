local Dibs = _G.Dibs
Dibs.DataUI = Dibs.DataUI or {}
local UI = Dibs.DataUI

local currentShell
local state = {
  tab = "backups",
  backupScope = "local",
  exportScope = "local",
  importScope = "local",
  strategy = "merge",
  importText = "",
  exportText = nil,
  selectedSnapshot = nil,
  restorePreviewId = nil,
  importPreviewId = nil,
  selectedProfileName = nil,
  selectedProfileScope = nil,
  profileName = "New profile",
  profileScope = "local",
  profileConfirm = nil,
  exportConfirmed = false,
  status = "",
}

local function labelDate(value)
  local timestamp = tonumber(value) or 0
  if timestamp <= 0 then return "Unknown" end
  if type(date) == "function" then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M", timestamp)
    if ok and formatted then return tostring(formatted) end
  end
  return tostring(timestamp)
end

local function pageParent(shell)
  return shell and (shell.contentHost or shell.pageHost or shell.window) or nil
end

local function clear(shell)
  local parent = pageParent(shell)
  if Dibs.AceGUI and Dibs.AceGUI.Clear and parent then Dibs.AceGUI.Clear(parent) end
end

local function setStatus(message)
  state.status = tostring(message or "")
end

local function showStatus(gui, shell, parent)
  if state.status ~= "" then gui.AddLabel(shell, parent, state.status, true) end
end

local function addChoice(gui, shell, parent, label, values, callback, width, value)
  local control
  if gui.AddMSADropdown then control = gui.AddMSADropdown(shell, parent, label, values, callback, width) end
  if not control and gui.AddDropdown then control = gui.AddDropdown(shell, parent, label, values, callback, width) end
  if control and value ~= nil and gui.SetValue then gui.SetValue(control, value) end
  return control
end

local function tableRows()
  local rows = {}
  for _, snapshot in ipairs(Dibs.Backup.List(nil, nil)) do
    rows[#rows + 1] = {
      labelDate(snapshot.createdAt), tostring(snapshot.scope or ""), tostring(snapshot.size or 0),
      tostring(snapshot.checksum or ""), "Select", id = snapshot.snapshotId,
    }
  end
  if #rows == 0 then rows[1] = { "", "No backups yet.", "", "", "" } end
  return rows
end

local function profileRows()
  local rows = {}
  for _, scope in ipairs({ "local", "guild" }) do
    for _, profile in ipairs(Dibs.Profiles.List(scope, nil)) do
      rows[#rows + 1] = {
        tostring(profile.name or ""), scope, labelDate(profile.updatedAt),
        profile.active and "Active" or "Select", name = profile.name, scope = scope,
      }
    end
  end
  table.sort(rows, function(a, b)
    return tostring(a[3] or "") > tostring(b[3] or "")
  end)
  if #rows == 0 then rows[1] = { "", "No profiles yet.", "", "", "" } end
  return rows
end

local function addPreview(gui, shell, parent, title, preview)
  if not preview then return end
  gui.AddHeading(shell, parent, title, "Review this read-only preview before confirming the operation.")
  local rows = {
    { "Preview", tostring(preview.previewId or "") },
    { "Created", labelDate(preview.createdAt) },
    { "Scope", tostring(preview.targetScope or "") },
    { "Strategy", tostring(preview.strategy or "") },
    { "Additions", tostring(preview.additions or 0) },
    { "Expected ledger impact", tostring(preview.expectedLedgerImpact and (preview.expectedLedgerImpact.additions or preview.expectedLedgerImpact.replace or 0) or 0) },
    { "Duplicate ledger records", tostring(preview.expectedLedgerImpact and preview.expectedLedgerImpact.duplicates or 0) },
  }
  local function append(label, values)
    if type(values) ~= "table" or #values == 0 then return end
    rows[#rows + 1] = { label, table.concat(values, ", ") }
  end
  append("Changes", preview.changes)
  append("Omissions", preview.omissions)
  append("Conflicts", preview.conflicts)
  append("Migrations", preview.migrations)
  append("Sensitive fields", preview.sensitiveFields)
  gui.AddPropertyTable(shell, parent, rows, 190)
end

local function addBackups(shell, parent)
  local gui = Dibs.AceGUI
  gui.AddHeading(shell, parent, "Safety backups", "Create a dated recovery point before restoring or importing data.")
  showStatus(gui, shell, parent)
  addChoice(gui, shell, parent, "Backup scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.backupScope = value or "local" end, 280, state.backupScope)
  gui.AddButton(shell, parent, "Create backup", function()
    local snapshot, prunedOrReason = Dibs.Backup.Create(state.backupScope, "manual", nil)
    if snapshot then
      state.selectedSnapshot = snapshot.snapshotId
      local pruned = type(prunedOrReason) == "table" and #prunedOrReason or 0
      setStatus("Backup created: " .. tostring(snapshot.snapshotId) .. " (" .. tostring(snapshot.scope) .. ", " .. tostring(snapshot.size or 0) .. " characters, checksum " .. tostring(snapshot.checksum or "unknown") .. (pruned > 0 and "; " .. tostring(pruned) .. " older backup(s) pruned" or "") .. ").")
    else
      setStatus("Backup failed: " .. tostring(prunedOrReason or "UNKNOWN_ERROR"))
    end
    UI.Refresh()
  end, 150)
  gui.AddTable(shell, parent, {
    { title = "Date", width = 145, tooltip = "Creation date." },
    { title = "Scope", width = 120, tooltip = "Data included in the snapshot." },
    { title = "Size", width = 75, tooltip = "Package size in characters." },
    { title = "Checksum", width = 220, tooltip = "Integrity checksum." },
    { title = "Action", width = 90, action = true, tooltip = "Select a snapshot." },
  }, tableRows(), 350, function(row)
    if not row.id then return nil end
    return { text = "Select", callback = function()
      state.selectedSnapshot = row.id
      state.restorePreviewId = nil
      setStatus("Selected backup: " .. tostring(row.id))
      UI.Refresh()
    end }
  end, { defaultSortColumn = 1 })
  if state.selectedSnapshot then
    gui.AddLabel(shell, parent, "Selected backup: " .. tostring(state.selectedSnapshot), true)
    gui.AddButton(shell, parent, "Preview restore", function()
      local preview, reason = Dibs.Backup.PreviewRestore(state.selectedSnapshot, nil)
      if preview then state.restorePreviewId = preview.previewId; setStatus("Restore preview ready. Review it before confirming.")
      else setStatus("Restore preview failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 150)
  end
  if state.restorePreviewId then
    local preview = Dibs.GetDB().pendingRestores and Dibs.GetDB().pendingRestores[state.restorePreviewId] and Dibs.GetDB().pendingRestores[state.restorePreviewId].preview
    addPreview(gui, shell, parent, "Restore preview", preview)
    gui.AddLabel(shell, parent, "This restore is pending confirmation. No active data has changed.", true)
    gui.AddButton(shell, parent, "Confirm restore", function()
      local result, reason = Dibs.Backup.Restore(state.restorePreviewId, true, "confirmed by user", nil)
      if result then setStatus("Restore completed."); state.restorePreviewId = nil
      else setStatus("Restore failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 150)
    gui.AddButton(shell, parent, "Cancel restore", function()
      local result, reason = Dibs.Backup.Restore(state.restorePreviewId, false, "cancelled by user", nil)
      if result then setStatus("Restore cancelled."); state.restorePreviewId = nil
      else setStatus("Unable to cancel restore: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 135)
  end
end

local function addProfiles(shell, parent)
  local gui = Dibs.AceGUI
  gui.AddHeading(shell, parent, "Configuration profiles", "Profiles store presentation settings separately from the append-only ledger.")
  showStatus(gui, shell, parent)
  gui.AddTable(shell, parent, {
    { title = "Name", width = 220, tooltip = "Profile name." },
    { title = "Scope", width = 100, tooltip = "Local character or guild policy." },
    { title = "Updated", width = 145, tooltip = "Last profile change." },
    { title = "Action", width = 105, action = true, tooltip = "Activate this profile." },
  }, profileRows(), 300, function(row)
    if not row.name then return nil end
    return { text = "Select", callback = function()
      state.selectedProfileName = row.name
      state.selectedProfileScope = row.scope
      state.profileConfirm = nil
      setStatus("Selected profile: " .. tostring(row.name) .. " (" .. tostring(row.scope) .. ").")
      UI.Refresh()
    end }
  end, { defaultSortColumn = 3 })
  if state.selectedProfileName and state.selectedProfileScope then
    local selected = Dibs.Profiles.Get(state.selectedProfileName, state.selectedProfileScope)
    if selected then
      gui.AddLabel(shell, parent, "Selected profile: " .. tostring(state.selectedProfileName) .. " (" .. tostring(state.selectedProfileScope) .. ")", true)
      local activate = gui.AddButton(shell, parent, "Activate selected", function()
        local value, reason, preview = Dibs.Profiles.Activate(state.selectedProfileName, state.selectedProfileScope, nil, state.profileConfirm == state.selectedProfileName)
        if value then
          state.profileConfirm = nil
          setStatus("Profile activated: " .. tostring(state.selectedProfileName) .. ".")
        elseif reason == "POLICY_CONFIRM_REQUIRED" then
          state.profileConfirm = state.selectedProfileName
          setStatus("This profile changes guild policy: " .. table.concat(preview and preview.policyChanges or {}, ", ") .. ". Click Activate selected again to confirm.")
        else
          setStatus("Profile activation failed: " .. tostring(reason or "UNKNOWN_ERROR"))
        end
        UI.Refresh()
      end, 150)
      if selected.active and activate then gui.SetDisabled(activate, true) end
      gui.AddButton(shell, parent, "Copy selected", function()
        local value, reason = Dibs.Profiles.Copy(state.selectedProfileName, state.profileName, state.selectedProfileScope, nil)
        setStatus(value and ("Profile copied as " .. tostring(value.name) .. ".") or ("Profile copy failed: " .. tostring(reason or "UNKNOWN_ERROR")))
        UI.Refresh()
      end, 130)
      gui.AddButton(shell, parent, "Rename selected", function()
        local value, reason = Dibs.Profiles.Rename(state.selectedProfileName, state.profileName, state.selectedProfileScope, nil)
        if value then state.selectedProfileName = value.name; setStatus("Profile renamed to " .. tostring(value.name) .. ".")
        else setStatus("Profile rename failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
        UI.Refresh()
      end, 140)
      gui.AddButton(shell, parent, "Reset selected", function()
        local value, reason = Dibs.Profiles.Reset(state.selectedProfileName, state.selectedProfileScope, nil)
        setStatus(value and "Profile reset." or ("Profile reset failed: " .. tostring(reason or "UNKNOWN_ERROR")))
        UI.Refresh()
      end, 125)
      gui.AddButton(shell, parent, "Delete selected", function()
        local value, reason = Dibs.Profiles.Delete(state.selectedProfileName, state.selectedProfileScope, nil)
        if value then state.selectedProfileName, state.selectedProfileScope = nil, nil; setStatus("Profile deleted.")
        else setStatus("Profile deletion failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
        UI.Refresh()
      end, 125)
    end
  end
  local profileNameBox = gui.AddEditBox(shell, parent, "New name (create, copy or rename)", function(value) state.profileName = tostring(value or "") end, 300)
  if profileNameBox and state.profileName ~= "" and profileNameBox.SetText then pcall(profileNameBox.SetText, profileNameBox, state.profileName) end
  gui.AddButton(shell, parent, "Create profile", function()
    local profile, reason = Dibs.Profiles.Create(state.profileName, state.profileScope, nil, nil)
    setStatus(profile and ("Profile created: " .. tostring(profile.name) .. ".") or ("Profile creation failed: " .. tostring(reason or "UNKNOWN_ERROR")))
    UI.Refresh()
  end, 145)
  addChoice(gui, shell, parent, "New profile scope", {
    ["local"] = "Local presentation",
    guild = "Guild policy (Officer)",
  }, function(value) state.profileScope = value or "local" end, 260, state.profileScope)
end

local function addTransfer(shell, parent)
  local gui = Dibs.AceGUI
  gui.AddHeading(shell, parent, "Import / export", "Copy a package, paste it on another character, validate the preview, then confirm explicitly.")
  showStatus(gui, shell, parent)
  addChoice(gui, shell, parent, "Export scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.exportScope = value or "local"; state.exportConfirmed = false; state.exportText = nil end, 280, state.exportScope)
  if state.exportScope == "full" then
    gui.AddLabel(shell, parent, "Full export contains guild ledger, award history and player identities. Treat the copied text as sensitive.", true)
  elseif state.exportScope == "guild" then
    gui.AddLabel(shell, parent, "Guild export contains policy and profile settings. Review the scope before sharing it.", true)
  end
  gui.AddButton(shell, parent, "Export package", function()
    if state.exportScope == "full" and not state.exportConfirmed then
      state.exportConfirmed = true
      setStatus("Full export is sensitive. Click Export package again to confirm, or use Export redacted config.")
      UI.Refresh()
      return
    end
    local text, packageOrReason = Dibs.ImportExport.Export(state.exportScope, { redacted = false })
    if text then
      state.exportText = text
      setStatus("Package exported. Copy the complete text, including the DIBS-PKG-1 prefix.")
    else
      setStatus("Export failed: " .. tostring(packageOrReason or "UNKNOWN_ERROR"))
    end
    UI.Refresh()
  end, 150)
  if state.exportScope ~= "local" then
    gui.AddButton(shell, parent, "Export redacted config", function()
      local text, packageOrReason = Dibs.ImportExport.Export(state.exportScope, { redacted = true })
      if text then
        state.exportText = text
        setStatus("Redacted configuration exported. Player identities, ledger transactions and evidence are omitted.")
      else
        setStatus("Redacted export failed: " .. tostring(packageOrReason or "UNKNOWN_ERROR"))
      end
      UI.Refresh()
    end, 175)
  end
  if state.exportText then gui.AddSelectableText(shell, parent, "Package (copy this text)", state.exportText, 700, 180) end
  local importBox = gui.AddEditBox(shell, parent, "Paste package to import", function(value) state.importText = tostring(value or "") end, 700)
  if importBox and state.importText ~= "" and importBox.SetText then pcall(importBox.SetText, importBox, state.importText) end
  addChoice(gui, shell, parent, "Import scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.importScope = value or "local" end, 280, state.importScope)
  addChoice(gui, shell, parent, "Import strategy", {
    merge = "Merge settings",
    replace = "Replace settings",
    append = "Append ledger (deduplicate)",
  }, function(value) state.strategy = value or "merge" end, 280, state.strategy)
  gui.AddButton(shell, parent, "Validate and preview", function()
    local preview, reason = Dibs.ImportExport.Preview(state.importText, state.importScope, state.strategy, nil)
    if preview then state.importPreviewId = preview.previewId; setStatus("Import preview ready. Review the scope and impact before confirming.")
    else setStatus("Import preview failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
    UI.Refresh()
  end, 175)
  if state.importPreviewId then
    local preview = Dibs.GetDB().pendingImports and Dibs.GetDB().pendingImports[state.importPreviewId] and Dibs.GetDB().pendingImports[state.importPreviewId].preview
    addPreview(gui, shell, parent, "Import preview", preview)
    gui.AddLabel(shell, parent, "This import is pending confirmation. No active data has changed.", true)
    gui.AddButton(shell, parent, "Confirm import", function()
      local result, reason = Dibs.ImportExport.Apply(state.importPreviewId, true, "confirmed by user", nil)
      if result then setStatus("Import completed."); state.importPreviewId = nil
      else setStatus("Import failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 145)
    gui.AddButton(shell, parent, "Cancel import", function()
      local result, reason = Dibs.ImportExport.Apply(state.importPreviewId, false, "cancelled by user", nil)
      if result then setStatus("Import cancelled."); state.importPreviewId = nil
      else setStatus("Unable to cancel import: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 130)
  end
end

function UI.Refresh()
  if not currentShell then return end
  clear(currentShell)
  local parent = pageParent(currentShell)
  if not parent then return end
  if currentShell.contentHost and currentShell.contentHost.SetHeight then
    local height = currentShell.frame and currentShell.frame.GetHeight and currentShell.frame:GetHeight() or 680
    currentShell.contentHost:SetHeight(math.max(320, height - 105))
  end
  if state.tab == "profiles" then addProfiles(currentShell, parent)
  elseif state.tab == "transfer" then addTransfer(currentShell, parent)
  else addBackups(currentShell, parent) end
end

function UI.Open(tab)
  if currentShell and currentShell.frame then
    state.tab = tab or state.tab
    currentShell.window:Show()
    UI.Refresh()
    return currentShell
  end
  local gui = Dibs.AceGUI
  local shell = gui and gui.CreateWindow and gui.CreateWindow("RCLootCouncil - Dibs | Data", 900, 680, { "CENTER", 0, 0 })
  if not shell then return nil end
  currentShell = shell
  state.tab = tab or state.tab
  shell.pageHost = gui.Create(shell, "SimpleGroup", shell.window)
  if shell.pageHost then
    shell.pageHost:SetFullWidth(true)
    shell.pageHost:SetFullHeight(true)
    -- List keeps the navigation row and the content panel in separate stable
    -- rows. Flow treats a full-height child as the final row and can collapse
    -- the page on Retail when the window is resized or first shown.
    shell.pageHost:SetLayout("List")
  end
  local nav = gui.AddInlineGroup(shell, shell.pageHost or shell.window)
  if nav then
    gui.AddButton(shell, nav, "Backups", function() state.tab = "backups"; UI.Refresh() end, 110)
    gui.AddButton(shell, nav, "Profiles", function() state.tab = "profiles"; UI.Refresh() end, 110)
    gui.AddButton(shell, nav, "Import / Export", function() state.tab = "transfer"; UI.Refresh() end, 145)
  end
  shell.contentHost = gui.Create(shell, "SimpleGroup", shell.pageHost or shell.window)
  if shell.contentHost then
    shell.contentHost:SetFullWidth(true)
    shell.contentHost:SetLayout("Flow")
    local height = shell.frame and shell.frame.GetHeight and shell.frame:GetHeight() or 680
    shell.contentHost:SetHeight(math.max(320, height - 105))
  end
  UI.Refresh()
  shell.window:Show()
  return shell
end

function UI.Toggle(tab)
  if currentShell and currentShell.frame then
    currentShell.window:Hide()
    currentShell = nil
    return nil
  end
  return UI.Open(tab)
end

return UI
