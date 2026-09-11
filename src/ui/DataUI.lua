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
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", timestamp)
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
  if shell then shell.contentPage = nil end
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

-- Data pages are deliberately stacked. A Flow parent is useful for compact
-- button rows, but it lets a fixed-width control share a row with the next
-- label while AceGUI is still measuring the page. Each Data section gets a
-- titled List container so labels, fields, buttons and tables keep a stable
-- vertical rhythm at every supported window size.
local function addStack(gui, shell, parent, title, description)
  local section = gui and gui.Create and gui.Create(shell, "InlineGroup", parent)
  if not section and gui and gui.Create then section = gui.Create(shell, "SimpleGroup", parent) end
  if not section then return parent end
  if section.SetFullWidth then section:SetFullWidth(true) end
  if section.SetLayout then section:SetLayout("List") end
  if title and title ~= "" and section.SetTitle then section:SetTitle(title) end
  if gui.AddTooltip then gui.AddTooltip(section, title, description) end
  return section
end

local function tableWidthHint(shell)
  local width = shell and shell.frame and shell.frame.GetWidth and shell.frame:GetWidth() or 760
  return math.max(360, (tonumber(width) or 760) - 50)
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
  if title and title ~= "" then
    gui.AddHeading(shell, parent, title, "Review this read-only preview before confirming the operation.")
  end
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
  local controls = addStack(gui, shell, parent, "Create a backup", "Choose which Dibs data should be captured before a restore or import.")
  addChoice(gui, shell, controls, "Backup scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.backupScope = value or "local" end, 280, state.backupScope)
  gui.AddButton(shell, controls, "Create backup", function()
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
  local tablePanel = addStack(gui, shell, parent, "Available backups", "Newest recovery points appear first. Select one to preview its restore.")
  gui.AddTable(shell, tablePanel, {
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
  end, { defaultSortColumn = 1, widthHint = tableWidthHint(shell) })
  if state.selectedSnapshot then
    local selectedPanel = addStack(gui, shell, parent, "Selected backup", "Preview the changes before restoring this recovery point.")
    gui.AddLabel(shell, selectedPanel, tostring(state.selectedSnapshot), true)
    gui.AddButton(shell, selectedPanel, "Preview restore", function()
      local preview, reason = Dibs.Backup.PreviewRestore(state.selectedSnapshot, nil)
      if preview then state.restorePreviewId = preview.previewId; setStatus("Restore preview ready. Review it before confirming.")
      else setStatus("Restore preview failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 150)
  end
  if state.restorePreviewId then
    local preview = Dibs.GetDB().pendingRestores and Dibs.GetDB().pendingRestores[state.restorePreviewId] and Dibs.GetDB().pendingRestores[state.restorePreviewId].preview
    local previewPanel = addStack(gui, shell, parent, "Restore preview", "This is read-only until you explicitly confirm the restore.")
    addPreview(gui, shell, previewPanel, "", preview)
    gui.AddLabel(shell, previewPanel, "No active data has changed yet.", true)
    gui.AddButton(shell, previewPanel, "Confirm restore", function()
      local result, reason = Dibs.Backup.Restore(state.restorePreviewId, true, "confirmed by user", nil)
      if result then setStatus("Restore completed."); state.restorePreviewId = nil
      else setStatus("Restore failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 150)
    gui.AddButton(shell, previewPanel, "Cancel restore", function()
      local result, reason = Dibs.Backup.Restore(state.restorePreviewId, false, "cancelled by user", nil)
      if result then setStatus("Restore cancelled."); state.restorePreviewId = nil
      else setStatus("Unable to cancel restore: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 135)
  end
end

local function createContentPage(shell)
  local gui = Dibs.AceGUI
  if not gui or not shell or not shell.contentHost then return shell and shell.contentHost end
  local height = shell.contentHost.height or 560
  local page = gui.AddScrollableList(shell, shell.contentHost, math.max(320, height - 8)) or shell.contentHost
  shell.contentPage = page
  -- The ScrollFrame is added after the List parent has been laid out. Ask
  -- both containers to recalculate now so Retail does not retain AceGUI's
  -- 300px SimpleGroup default for the page and its tables.
  if shell.contentHost.DoLayout then shell.contentHost:DoLayout() end
  if page and page.DoLayout then page:DoLayout() end
  return page
end

local function addProfiles(shell, parent)
  local gui = Dibs.AceGUI
  gui.AddHeading(shell, parent, "Configuration profiles", "Profiles store presentation settings separately from the append-only ledger.")
  showStatus(gui, shell, parent)
  local tablePanel = addStack(gui, shell, parent, "Saved profiles", "Name, scope, last update and activation are shown together in this table.")
  gui.AddTable(shell, tablePanel, {
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
  end, { defaultSortColumn = 3, widthHint = tableWidthHint(shell) })
  if state.selectedProfileName and state.selectedProfileScope then
    local selected = Dibs.Profiles.Get(state.selectedProfileName, state.selectedProfileScope)
    if selected then
      local selectedPanel = addStack(gui, shell, parent, "Selected profile", "Choose an action for the profile selected above.")
      gui.AddLabel(shell, selectedPanel, tostring(state.selectedProfileName) .. " (" .. tostring(state.selectedProfileScope) .. ")", true)
      local activate = gui.AddButton(shell, selectedPanel, "Activate selected", function()
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
      gui.AddButton(shell, selectedPanel, "Copy selected", function()
        local value, reason = Dibs.Profiles.Copy(state.selectedProfileName, state.profileName, state.selectedProfileScope, nil)
        setStatus(value and ("Profile copied as " .. tostring(value.name) .. ".") or ("Profile copy failed: " .. tostring(reason or "UNKNOWN_ERROR")))
        UI.Refresh()
      end, 130)
      gui.AddButton(shell, selectedPanel, "Rename selected", function()
        local value, reason = Dibs.Profiles.Rename(state.selectedProfileName, state.profileName, state.selectedProfileScope, nil)
        if value then state.selectedProfileName = value.name; setStatus("Profile renamed to " .. tostring(value.name) .. ".")
        else setStatus("Profile rename failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
        UI.Refresh()
      end, 140)
      gui.AddButton(shell, selectedPanel, "Reset selected", function()
        local value, reason = Dibs.Profiles.Reset(state.selectedProfileName, state.selectedProfileScope, nil)
        setStatus(value and "Profile reset." or ("Profile reset failed: " .. tostring(reason or "UNKNOWN_ERROR")))
        UI.Refresh()
      end, 125)
      gui.AddButton(shell, selectedPanel, "Delete selected", function()
        local value, reason = Dibs.Profiles.Delete(state.selectedProfileName, state.selectedProfileScope, nil)
        if value then state.selectedProfileName, state.selectedProfileScope = nil, nil; setStatus("Profile deleted.")
        else setStatus("Profile deletion failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
        UI.Refresh()
      end, 125)
    end
  end
  local createPanel = addStack(gui, shell, parent, "Create a profile", "Save the current presentation settings under a name you can activate later.")
  local profileNameBox = gui.AddEditBox(shell, createPanel, "Profile name", function(value) state.profileName = tostring(value or "") end, 360)
  if profileNameBox and state.profileName ~= "" and profileNameBox.SetText then pcall(profileNameBox.SetText, profileNameBox, state.profileName) end
  addChoice(gui, shell, createPanel, "Profile scope", {
    ["local"] = "Local presentation",
    guild = "Guild policy (Officer)",
  }, function(value) state.profileScope = value or "local" end, 360, state.profileScope)
  gui.AddButton(shell, createPanel, "Create profile", function()
    local profile, reason = Dibs.Profiles.Create(state.profileName, state.profileScope, nil, nil)
    setStatus(profile and ("Profile created: " .. tostring(profile.name) .. ".") or ("Profile creation failed: " .. tostring(reason or "UNKNOWN_ERROR")))
    if profile then
      state.selectedProfileName, state.selectedProfileScope = profile.name, profile.scope
    end
    UI.Refresh()
  end, 145)
end

local function addTransfer(shell, parent)
  local gui = Dibs.AceGUI
  gui.AddHeading(shell, parent, "Import / export", "Copy a package, paste it on another character, validate the preview, then confirm explicitly.")
  showStatus(gui, shell, parent)
  local exportPanel = addStack(gui, shell, parent, "Export package", "Choose what to copy out of this character or guild.")
  addChoice(gui, shell, exportPanel, "Export scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.exportScope = value or "local"; state.exportConfirmed = false; state.exportText = nil end, 280, state.exportScope)
  if state.exportScope == "full" then
    gui.AddLabel(shell, exportPanel, "Full export contains guild ledger, award history and player identities. Treat the copied text as sensitive.", true)
  elseif state.exportScope == "guild" then
    gui.AddLabel(shell, exportPanel, "Guild export contains policy and profile settings. Review the scope before sharing it.", true)
  end
  gui.AddButton(shell, exportPanel, "Export package", function()
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
    gui.AddButton(shell, exportPanel, "Export redacted config", function()
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
  if state.exportText then gui.AddSelectableText(shell, exportPanel, "Package (copy this text)", state.exportText, 700, 180) end
  local importPanel = addStack(gui, shell, parent, "Import package", "Paste a Dibs package, validate it, then confirm the read-only preview.")
  local importBox = gui.AddEditBox(shell, importPanel, "Paste package to import", function(value) state.importText = tostring(value or "") end, 700)
  if importBox and state.importText ~= "" and importBox.SetText then pcall(importBox.SetText, importBox, state.importText) end
  addChoice(gui, shell, importPanel, "Import scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.importScope = value or "local" end, 280, state.importScope)
  addChoice(gui, shell, importPanel, "Import strategy", {
    merge = "Merge settings",
    replace = "Replace settings",
    append = "Append ledger (deduplicate)",
  }, function(value) state.strategy = value or "merge" end, 280, state.strategy)
  gui.AddButton(shell, importPanel, "Validate and preview", function()
    local preview, reason = Dibs.ImportExport.Preview(state.importText, state.importScope, state.strategy, nil)
    if preview then state.importPreviewId = preview.previewId; setStatus("Import preview ready. Review the scope and impact before confirming.")
    else setStatus("Import preview failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
    UI.Refresh()
  end, 175)
  if state.importPreviewId then
    local preview = Dibs.GetDB().pendingImports and Dibs.GetDB().pendingImports[state.importPreviewId] and Dibs.GetDB().pendingImports[state.importPreviewId].preview
    local previewPanel = addStack(gui, shell, parent, "Import preview", "This is read-only until you explicitly confirm the import.")
    addPreview(gui, shell, previewPanel, "", preview)
    gui.AddLabel(shell, previewPanel, "No active data has changed yet.", true)
    gui.AddButton(shell, previewPanel, "Confirm import", function()
      local result, reason = Dibs.ImportExport.Apply(state.importPreviewId, true, "confirmed by user", nil)
      if result then setStatus("Import completed."); state.importPreviewId = nil
      else setStatus("Import failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 145)
    gui.AddButton(shell, previewPanel, "Cancel import", function()
      local result, reason = Dibs.ImportExport.Apply(state.importPreviewId, false, "cancelled by user", nil)
      if result then setStatus("Import cancelled."); state.importPreviewId = nil
      else setStatus("Unable to cancel import: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 130)
  end
end

local function relayout(shell)
  if not shell then return end
  local height = shell.frame and shell.frame.GetHeight and shell.frame:GetHeight() or 560
  local contentHeight = math.max(320, height - 105)
  if shell.contentHost and shell.contentHost.SetHeight then shell.contentHost:SetHeight(contentHeight) end
  if shell.contentPage and shell.contentPage ~= shell.contentHost and shell.contentPage.SetHeight then
    shell.contentPage:SetHeight(math.max(320, contentHeight - 8))
  end
  if shell.window and shell.window.DoLayout then shell.window:DoLayout() end
  if shell.pageHost and shell.pageHost.DoLayout then shell.pageHost:DoLayout() end
  if shell.contentHost and shell.contentHost.DoLayout then shell.contentHost:DoLayout() end
  if shell.contentPage and shell.contentPage.DoLayout then shell.contentPage:DoLayout() end
end

function UI.Refresh()
  if not currentShell then return end
  clear(currentShell)
  local parent = pageParent(currentShell)
  if not parent then return end
  relayout(currentShell)
  local page = createContentPage(currentShell) or parent
  if state.tab == "profiles" then addProfiles(currentShell, page)
  elseif state.tab == "transfer" then addTransfer(currentShell, page)
  else addBackups(currentShell, page) end
  relayout(currentShell)
end

function UI.Open(tab)
  if currentShell and currentShell.frame then
    state.tab = tab or state.tab
    currentShell.window:Show()
    UI.Refresh()
    return currentShell
  end
  local gui = Dibs.AceGUI
  local shell = gui and gui.CreateWindow and gui.CreateWindow("RCLootCouncil - Dibs | Data", 760, 560, { "CENTER", 0, 0 })
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
    gui.AddButton(shell, nav, "Backups", function() state.tab = "backups"; setStatus(""); UI.Refresh() end, 110)
    gui.AddButton(shell, nav, "Profiles", function() state.tab = "profiles"; setStatus(""); UI.Refresh() end, 110)
    gui.AddButton(shell, nav, "Import / Export", function() state.tab = "transfer"; setStatus(""); UI.Refresh() end, 145)
  end
  shell.contentHost = gui.Create(shell, "SimpleGroup", shell.pageHost or shell.window)
  if shell.contentHost then
    shell.contentHost:SetFullWidth(true)
    shell.contentHost:SetLayout("Flow")
    local height = shell.frame and shell.frame.GetHeight and shell.frame:GetHeight() or 680
    shell.contentHost:SetHeight(math.max(320, height - 105))
  end
  if shell.AddResizeHandler then
    shell:AddResizeHandler(function(resizedShell)
      if currentShell == resizedShell then relayout(resizedShell) end
    end)
  end
  if shell.pageHost and shell.pageHost.DoLayout then shell.pageHost:DoLayout() end
  if shell.window and shell.window.DoLayout then shell.window:DoLayout() end
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
