--[[
Module: Dibs.DataUI
Layer: UI / persistence administration
Purpose: Present backups, profiles, and import/export workflows in a compact data window.
Responsibilities: Permission-filtered controls and preview-first actions.
Non-responsibilities: It does not implement backup/profile business rules.
Dependencies: AceGUI, Backup, Profiles, ImportExport, ProtectedActions.
Blizzard events: None directly.
Internal events/messages: Widget callbacks to data services.
SavedVariables: Accessed indirectly through domain modules.
RCLootCouncil: None directly.
Combat safety: Window creation/refresh obeys PLAYER_REGEN_ENABLED deferral.
Related docs: docs/officer/auditing.md.
]]

local Dibs = _G.Dibs
Dibs.DataUI = Dibs.DataUI or {}
local UI = Dibs.DataUI
local helpText = Dibs.L or {}

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
  selectedSnapshotScope = nil,
  snapshotExportText = nil,
  snapshotExportInfo = nil,
  snapshotExportConfirmed = false,
  snapshotExportContext = nil,
  snapshotExportMetadata = nil,
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

local function clearSnapshotExport()
  state.snapshotExportText = nil
  state.snapshotExportInfo = nil
  state.snapshotExportConfirmed = false
  state.snapshotExportContext = nil
  state.snapshotExportMetadata = nil
  if state.status == (helpText.DATA_SNAPSHOT_EXPORT_READY or "Selected backup exported. Copy the complete historical package below.") then
    state.status = ""
  end
end

local function snapshotExportContext()
  return table.concat({ tostring(Dibs.currentGuildKey or ""),
    tostring(Dibs.GetPlayerName and Dibs.GetPlayerName() or ""),
    tostring(type(GetRealmName) == "function" and GetRealmName() or "") }, "\031")
end

local function selectedSnapshotMetadata(snapshots)
  for _, snapshot in ipairs(snapshots or {}) do
    if snapshot.snapshotId == state.selectedSnapshot then
      return { snapshotId = snapshot.snapshotId, scope = snapshot.scope, guildScope = snapshot.guildScope,
        characterScope = snapshot.characterScope, schemaVersion = snapshot.schemaVersion,
        addonVersion = snapshot.addonVersion, createdAt = snapshot.createdAt, size = snapshot.size,
        checksum = snapshot.checksum, packageChecksum = snapshot.packageChecksum, payloadChecksum = snapshot.payloadChecksum }
    end
  end
end

local function sameSnapshotMetadata(first, second)
  if not first or not second then return first == second end
  for key, value in pairs(first) do if second[key] ~= value then return false end end
  for key, value in pairs(second) do if first[key] ~= value then return false end end
  return true
end

local function showStatus(gui, shell, parent)
  if state.status ~= "" then gui.AddLabel(shell, parent, state.status, true) end
end

local function compressionAvailable()
  return Dibs.BackupTransport and Dibs.BackupTransport.GetStatus().available == true
end

local function showTransportFormat(gui, shell, parent, info)
  if info then
    gui.AddLabel(shell, parent, string.format(helpText.DATA_TRANSPORT_SIZES
      or "Compressed package: %d characters; original package: %d bytes.", info.encodedBytes, info.rawBytes), true)
  else
    gui.AddLabel(shell, parent, compressionAvailable()
      and (helpText.DATA_TRANSPORT_COMPRESSED or "Exports use compressed portable text. Imports also accept older packages.")
      or (helpText.DATA_TRANSPORT_UNAVAILABLE or "Compression is unavailable. Legacy text export remains available within its size limit."), true)
  end
end

local function addDatabaseSummary(gui, shell, parent)
  local diagnostics = Dibs.ImportExport and Dibs.ImportExport.GetSizeDiagnostics and Dibs.ImportExport.GetSizeDiagnostics()
  if not diagnostics then return end
  local formatSize = Dibs.ImportExport.FormatSize or tostring
  gui.AddHeading(shell, parent, "Database size", helpText.UI_HELP_DATABASE_SIZE)
  gui.AddLabel(shell, parent,
    "Serialized DB: " .. formatSize(diagnostics.databaseBytes) ..
    " | Full payload: " .. formatSize(diagnostics.fullPayloadBytes) ..
    " | Full backup package: " .. formatSize(diagnostics.fullPackageBytes) .. " / " .. formatSize(diagnostics.backupLimitBytes) ..
    "\nPortable export limit: " .. formatSize(diagnostics.portableLimitBytes), true)
end

local function addChoice(gui, shell, parent, label, values, callback, width, value)
  local control
  if gui.AddDropdown then control = gui.AddDropdown(shell, parent, label, values, callback, width, false) end
  if not control and gui.AddMSADropdown then control = gui.AddMSADropdown(shell, parent, label, values, callback, width) end
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

local function tableRows(snapshots)
  local rows = {}
  for _, snapshot in ipairs(snapshots) do
    rows[#rows + 1] = {
      labelDate(snapshot.createdAt), tostring(snapshot.scope or ""), tostring(snapshot.size or 0),
      tostring(snapshot.checksum or ""), "Select", id = snapshot.snapshotId, scope = snapshot.scope,
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
    gui.AddHeading(shell, parent, title, helpText.UI_HELP_RESTORE_PREVIEW)
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
  if preview.recoveryClass then
    rows[#rows + 1] = {
      helpText.DATA_IMPORT_RECOVERY_BEHAVIOR or "Recovery behavior",
      preview.recoveryClass == "LEGACY_DIAGNOSTIC_ONLY"
        and (helpText.DATA_FULL_IMPORT_LIMIT or "Compatibility import only; unknown canonical history cannot be recovered here.")
        or tostring(preview.recoveryClass),
    }
  end
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
  local snapshots = Dibs.Backup.List(nil, nil)
  local context = snapshotExportContext()
  if state.snapshotExportContext and state.snapshotExportContext ~= context then clearSnapshotExport() end
  local metadata = selectedSnapshotMetadata(snapshots)
  if state.snapshotExportMetadata and not sameSnapshotMetadata(state.snapshotExportMetadata, metadata) then clearSnapshotExport() end
  state.snapshotExportMetadata = metadata
  if metadata then state.selectedSnapshotScope = metadata.scope end
  local exportAllowed, unavailableReason
  if state.selectedSnapshot and Dibs.Backup.ValidateSnapshotExport then
    exportAllowed, unavailableReason = Dibs.Backup.ValidateSnapshotExport(state.selectedSnapshot,
      { compressed = compressionAvailable(), confirmedSensitive = state.snapshotExportConfirmed == true, expectedPackageText = state.snapshotExportText })
  end
  if not exportAllowed and unavailableReason ~= "SENSITIVE_CONFIRMATION_REQUIRED" then clearSnapshotExport() end
  gui.AddHeading(shell, parent, "Safety backups", helpText.UI_HELP_BACKUPS)
  gui.AddLabel(shell, parent, helpText.DATA_BACKUP_LOCAL_STORAGE
    or "These snapshots are stored locally. Select a backup to export its retained historical package; Import / Export captures current data.", true)
  addDatabaseSummary(gui, shell, parent)
  showStatus(gui, shell, parent)
  local controls = addStack(gui, shell, parent, "Create a backup", "Choose which Dibs data should be captured before a restore or import.")
  local backupScope = addChoice(gui, shell, controls, "Backup scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.backupScope = value or "local" end, 280, state.backupScope)
  gui.AddTooltip(backupScope, "Backup scope", helpText.UI_HELP_BACKUP_SCOPE)
  local createBackup = gui.AddButton(shell, controls, "Create backup", function()
    clearSnapshotExport()
    local snapshot, prunedOrReason = Dibs.Backup.Create(state.backupScope, "manual", nil)
    if snapshot then
      state.selectedSnapshot = snapshot.snapshotId
      state.selectedSnapshotScope = snapshot.scope
      local pruned = type(prunedOrReason) == "table" and #prunedOrReason or 0
      setStatus("Backup created: " .. tostring(snapshot.snapshotId) .. " (" .. tostring(snapshot.scope) .. ", " .. tostring(snapshot.size or 0) .. " characters, checksum " .. tostring(snapshot.checksum or "unknown") .. (pruned > 0 and "; " .. tostring(pruned) .. " older backup(s) pruned" or "") .. ").")
    else
      setStatus("Backup failed: " .. tostring(prunedOrReason or "UNKNOWN_ERROR"))
    end
    UI.Refresh()
  end, 150)
  gui.AddTooltip(createBackup, "Create backup", helpText.UI_HELP_BACKUP_CREATE)
  local tablePanel = addStack(gui, shell, parent, "Available backups", "Newest recovery points appear first. Select one to preview its restore.")
  gui.AddTable(shell, tablePanel, {
    { title = "Date", width = 145, tooltip = helpText.UI_HELP_BACKUP_DATE },
    { title = "Scope", width = 120, tooltip = helpText.UI_HELP_BACKUP_SCOPE_COLUMN },
    { title = "Size", width = 75, tooltip = helpText.UI_HELP_BACKUP_SIZE },
    { title = "Checksum", width = 220, tooltip = helpText.UI_HELP_BACKUP_CHECKSUM },
    { title = "Action", width = 90, action = true, tooltip = helpText.UI_HELP_BACKUP_SELECT },
  }, tableRows(snapshots), 350, function(row)
    if not row.id then return nil end
    return { text = "Select", callback = function()
      clearSnapshotExport()
      state.selectedSnapshot = row.id
      state.selectedSnapshotScope = row.scope
      state.restorePreviewId = nil
      setStatus("Selected backup: " .. tostring(row.id))
      UI.Refresh()
    end }
  end, { defaultSortColumn = 1, widthHint = tableWidthHint(shell) })
  if state.selectedSnapshot then
    local selectedPanel = addStack(gui, shell, parent, "Selected backup", "Preview the changes before restoring this recovery point.")
    gui.AddLabel(shell, selectedPanel, tostring(state.selectedSnapshot), true)
    local previewRestore = gui.AddButton(shell, selectedPanel, "Preview restore", function()
      local preview, reason = Dibs.Backup.PreviewRestore(state.selectedSnapshot, nil)
      if preview then state.restorePreviewId = preview.previewId; setStatus("Restore preview ready. Review it before confirming.")
      else setStatus("Restore preview failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 150)
    gui.AddTooltip(previewRestore, "Preview restore", helpText.UI_HELP_RESTORE_PREVIEW)

    local exportPanel = addStack(gui, shell, parent,
      helpText.DATA_SNAPSHOT_EXPORT_TITLE or "Export selected backup",
      helpText.DATA_SNAPSHOT_EXPORT_HELP or "Copy the original package retained with this backup. Current settings are not captured again.")
    gui.AddLabel(shell, exportPanel, helpText.DATA_SNAPSHOT_EXPORT_HELP
      or "Copy the original package retained with this backup. Current settings are not captured again.", true)
    showTransportFormat(gui, shell, exportPanel, state.snapshotExportInfo)
    if not exportAllowed and unavailableReason ~= "SENSITIVE_CONFIRMATION_REQUIRED" then
      gui.AddLabel(shell, exportPanel, (helpText.DATA_SNAPSHOT_EXPORT_UNAVAILABLE or "Selected backup cannot be exported: ")
        .. tostring(unavailableReason or "SNAPSHOT_EXPORT_UNAVAILABLE"), true)
    else
      if state.selectedSnapshotScope == "full" then
        gui.AddLabel(shell, exportPanel, helpText.DATA_SNAPSHOT_EXPORT_SENSITIVE
          or "This backup contains player identities, ledger and award history. Treat the copied package as sensitive.", true)
        gui.AddLabel(shell, exportPanel, helpText.DATA_FULL_IMPORT_LIMIT
          or "Compatibility import only; unknown canonical history cannot be recovered here.", true)
        gui.AddCheckBox(shell, exportPanel, helpText.DATA_SNAPSHOT_EXPORT_CONSENT
          or "I understand and confirm exporting the sensitive contents of this selected backup.",
          state.snapshotExportConfirmed, function(checked)
            state.snapshotExportText = nil
            state.snapshotExportInfo = nil
            state.snapshotExportConfirmed = checked == true
            state.snapshotExportContext = context
            UI.Refresh()
          end)
      end
      gui.AddButton(shell, exportPanel, helpText.DATA_SNAPSHOT_EXPORT_ACTION or "Export selected backup", function()
        local expectedPackageText = state.snapshotExportText
        state.snapshotExportText = nil
        if state.snapshotExportContext and state.snapshotExportContext ~= snapshotExportContext() then clearSnapshotExport() end
        local currentMetadata = selectedSnapshotMetadata(Dibs.Backup.List(nil, nil))
        if not sameSnapshotMetadata(state.snapshotExportMetadata, currentMetadata) then
          clearSnapshotExport()
          setStatus((helpText.DATA_SNAPSHOT_EXPORT_FAILED or "Selected backup export failed: ") .. "SNAPSHOT_EXPORT_CHANGED")
          UI.Refresh()
          return
        end
        local options = { compressed = compressionAvailable(), actor = nil, reason = "selected backup export confirmed by user", expectedPackageText = expectedPackageText }
        if state.snapshotExportConfirmed == true then options.confirmedSensitive = true end
        local text, packageOrReason, transportInfo = Dibs.Backup.ExportSnapshot(state.selectedSnapshot, options)
        if text then
          state.snapshotExportText = text
          state.snapshotExportInfo = transportInfo
          state.snapshotExportContext = snapshotExportContext()
          setStatus(helpText.DATA_SNAPSHOT_EXPORT_READY or "Selected backup exported. Copy the complete historical package below.")
        else
          clearSnapshotExport()
          setStatus((helpText.DATA_SNAPSHOT_EXPORT_FAILED or "Selected backup export failed: ") .. tostring(packageOrReason or "UNKNOWN_ERROR"))
        end
        UI.Refresh()
      end, 220)
      if state.snapshotExportText then
        gui.AddSelectableText(shell, exportPanel, helpText.DATA_SNAPSHOT_EXPORT_PACKAGE
          or "Historical backup package", state.snapshotExportText, 700, 180)
      end
    end
  end
  if state.restorePreviewId then
    local preview = Dibs.GetDB().pendingRestores and Dibs.GetDB().pendingRestores[state.restorePreviewId] and Dibs.GetDB().pendingRestores[state.restorePreviewId].preview
    if not preview then
      state.restorePreviewId = nil
      gui.AddLabel(shell, parent, helpText.DATA_PREVIEW_UNAVAILABLE or "This preview is no longer available. Create a new preview before confirming.", true)
      return
    end
    local previewPanel = addStack(gui, shell, parent, "Restore preview", "This is read-only until you explicitly confirm the restore.")
    addPreview(gui, shell, previewPanel, "", preview)
    gui.AddLabel(shell, previewPanel, "No active data has changed yet.", true)
    local confirmRestore = gui.AddButton(shell, previewPanel, "Confirm restore", function()
      local result, reason = Dibs.Backup.Restore(state.restorePreviewId, true, "confirmed by user", nil)
      if result then
        local kept = result.keptLocal or {}
        if #kept > 0 then
          setStatus(string.format((Dibs.L or {}).RESTORE_KEPT_SHARED or "Restore completed. Newer guild-synced data was kept (%s); sync will catch up the rest.", table.concat(kept, ", ")))
        else setStatus("Restore completed.") end
        state.restorePreviewId = nil
      else setStatus("Restore failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 150)
    gui.AddTooltip(confirmRestore, "Confirm restore", helpText.UI_HELP_CONFIRM_RESTORE)
    local cancelRestore = gui.AddButton(shell, previewPanel, "Cancel restore", function()
      local result, reason = Dibs.Backup.Restore(state.restorePreviewId, false, "cancelled by user", nil)
      if result then setStatus("Restore cancelled."); state.restorePreviewId = nil
      else setStatus("Unable to cancel restore: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 135)
    gui.AddTooltip(cancelRestore, "Cancel restore", helpText.UI_HELP_CANCEL_RESTORE)
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
  gui.AddHeading(shell, parent, "Configuration profiles", helpText.UI_HELP_PROFILES)
  showStatus(gui, shell, parent)
  local tablePanel = addStack(gui, shell, parent, "Saved profiles", "Name, scope, last update and activation are shown together in this table.")
  gui.AddTable(shell, tablePanel, {
    { title = "Name", width = 220, tooltip = helpText.UI_HELP_PROFILE_NAME },
    { title = "Scope", width = 100, tooltip = helpText.UI_HELP_PROFILE_SCOPE },
    { title = "Updated", width = 145, tooltip = helpText.UI_HELP_DATE },
    { title = "Action", width = 105, action = true, tooltip = helpText.UI_HELP_PROFILE_ACTIVATE },
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
      gui.AddTooltip(activate, "Activate selected", helpText.UI_HELP_PROFILE_ACTIVATE)
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
      local deleteProfile = gui.AddButton(shell, selectedPanel, "Delete selected", function()
        local value, reason = Dibs.Profiles.Delete(state.selectedProfileName, state.selectedProfileScope, nil)
        if value then state.selectedProfileName, state.selectedProfileScope = nil, nil; setStatus("Profile deleted.")
        else setStatus("Profile deletion failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
        UI.Refresh()
      end, 125)
      gui.AddTooltip(deleteProfile, "Delete selected", helpText.UI_HELP_PROFILE_DELETE)
    end
  end
  local createPanel = addStack(gui, shell, parent, "Create a profile", "Save the current presentation settings under a name you can activate later.")
  local profileNameBox = gui.AddEditBox(shell, createPanel, "Profile name", function(value) state.profileName = tostring(value or "") end, 360)
  if profileNameBox and state.profileName ~= "" and profileNameBox.SetText then pcall(profileNameBox.SetText, profileNameBox, state.profileName) end
  local profileScope = addChoice(gui, shell, createPanel, "Profile scope", {
    ["local"] = "Local presentation",
    guild = "Guild policy (Officer)",
  }, function(value) state.profileScope = value or "local" end, 360, state.profileScope)
  gui.AddTooltip(profileScope, "Profile scope", helpText.UI_HELP_PROFILE_SCOPE)
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
  local canViewExport = state.exportScope == "local" or (Dibs.Permissions and Dibs.Permissions.Can
    and Dibs.Permissions.Can("settings.modify", nil) == true)
  if not canViewExport or (state.exportContext and state.exportContext ~= snapshotExportContext() .. ":" .. state.exportScope) then
    state.exportText, state.exportInfo, state.exportConfirmed, state.exportContext = nil, nil, false, nil
  end
  gui.AddHeading(shell, parent, "Import / export", helpText.UI_HELP_IMPORT_EXPORT)
  gui.AddLabel(shell, parent, helpText.DATA_EXPORT_CURRENT_STATE
    or "Export copies current data. It does not export a selected historical backup or create a portable restore point.", true)
  addDatabaseSummary(gui, shell, parent)
  showStatus(gui, shell, parent)
  local exportPanel = addStack(gui, shell, parent, "Export package", "Choose what to copy out of this character or guild.")
  addChoice(gui, shell, exportPanel, "Export scope", {
    ["local"] = "Local presentation",
    guild = "Guild configuration (Officer)",
    full = "Full Dibs data (GM/Officer)",
  }, function(value) state.exportScope = value or "local"; state.exportConfirmed = false; state.exportText = nil; state.exportInfo = nil end, 280, state.exportScope)
  if state.exportScope == "full" then
    gui.AddLabel(shell, exportPanel, "Full export contains guild ledger, award history and player identities. Treat the copied text as sensitive.", true)
    gui.AddLabel(shell, exportPanel, helpText.DATA_FULL_IMPORT_LIMIT
      or "Compatibility import only; unknown canonical history cannot be recovered here.", true)
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
    state.exportText, state.exportInfo = nil, nil
    local text, packageOrReason, transportInfo = Dibs.ImportExport.Export(state.exportScope, { redacted = false, compressed = compressionAvailable() })
    if text then
      state.exportText = text
      state.exportInfo = transportInfo
      state.exportContext = snapshotExportContext() .. ":" .. state.exportScope
      setStatus(helpText.DATA_TRANSPORT_COPY or "Package exported. Copy the complete text, including its format prefix.")
    else
      setStatus("Export failed: " .. tostring(packageOrReason or "UNKNOWN_ERROR"))
    end
    UI.Refresh()
  end, 150)
  if state.exportScope ~= "local" then
    gui.AddButton(shell, exportPanel, "Export redacted config", function()
      state.exportText, state.exportInfo = nil, nil
      local text, packageOrReason, transportInfo = Dibs.ImportExport.Export(state.exportScope, { redacted = true, compressed = compressionAvailable() })
      if text then
        state.exportText = text
        state.exportInfo = transportInfo
        state.exportContext = snapshotExportContext() .. ":" .. state.exportScope
        setStatus("Redacted configuration exported. Player identities, ledger transactions and evidence are omitted.")
      else
        setStatus("Redacted export failed: " .. tostring(packageOrReason or "UNKNOWN_ERROR"))
      end
      UI.Refresh()
    end, 175)
  end
  showTransportFormat(gui, shell, exportPanel, state.exportInfo)
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
  local validateImport = gui.AddButton(shell, importPanel, "Validate and preview", function()
    local preview, reason = Dibs.ImportExport.Preview(state.importText, state.importScope, state.strategy, nil)
    if preview then state.importPreviewId = preview.previewId; setStatus("Import preview ready. Review the scope and impact before confirming.")
    else setStatus("Import preview failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
    UI.Refresh()
  end, 175)
  gui.AddTooltip(validateImport, "Validate and preview", helpText.UI_HELP_RESTORE_PREVIEW)
  if state.importPreviewId then
    local preview = Dibs.GetDB().pendingImports and Dibs.GetDB().pendingImports[state.importPreviewId] and Dibs.GetDB().pendingImports[state.importPreviewId].preview
    if not preview then
      state.importPreviewId = nil
      gui.AddLabel(shell, parent, helpText.DATA_PREVIEW_UNAVAILABLE or "This preview is no longer available. Create a new preview before confirming.", true)
      return
    end
    local previewPanel = addStack(gui, shell, parent, "Import preview", "This is read-only until you explicitly confirm the import.")
    addPreview(gui, shell, previewPanel, "", preview)
    gui.AddLabel(shell, previewPanel, "No active data has changed yet.", true)
    local confirmImport = gui.AddButton(shell, previewPanel, "Confirm import", function()
      local result, reason = Dibs.ImportExport.Apply(state.importPreviewId, true, "confirmed by user", nil)
      if result then setStatus("Import completed."); state.importPreviewId = nil
      else setStatus("Import failed: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 145)
    gui.AddTooltip(confirmImport, "Confirm import", helpText.UI_HELP_CONFIRM_RESTORE)
    local cancelImport = gui.AddButton(shell, previewPanel, "Cancel import", function()
      local result, reason = Dibs.ImportExport.Apply(state.importPreviewId, false, "cancelled by user", nil)
      if result then setStatus("Import cancelled."); state.importPreviewId = nil
      else setStatus("Unable to cancel import: " .. tostring(reason or "UNKNOWN_ERROR")) end
      UI.Refresh()
    end, 130)
    gui.AddTooltip(cancelImport, "Cancel import", helpText.UI_HELP_CANCEL_RESTORE)
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
  clearSnapshotExport()
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
    gui.AddButton(shell, nav, "Backups", function() clearSnapshotExport(); state.tab = "backups"; setStatus(""); UI.Refresh() end, 110)
    gui.AddButton(shell, nav, "Profiles", function() clearSnapshotExport(); state.tab = "profiles"; setStatus(""); UI.Refresh() end, 110)
    gui.AddButton(shell, nav, "Import / Export", function() clearSnapshotExport(); state.tab = "transfer"; setStatus(""); UI.Refresh() end, 145)
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
    clearSnapshotExport()
    currentShell.window:Hide()
    currentShell = nil
    return nil
  end
  return UI.Open(tab)
end

return UI
