local loader = require("helpers.load_addon")

describe("Historical backup export controls", function()
  local dibs, start

  local function widget(property, value)
    local widgets = _G.__dibsAceWidgets or {}
    for index = #widgets, start + 1, -1 do
      if widgets[index][property] == value then return widgets[index] end
    end
  end

  local function refresh(action)
    start = #(_G.__dibsAceWidgets or {})
    if action then action() else dibs.DataUI.Refresh() end
  end

  local function click(text)
    local button = assert_not_nil(widget("text", text), "missing button " .. text)
    refresh(function() button.callbacks.OnClick(button) end)
  end

  local function navigate(text)
    for _, button in ipairs(_G.__dibsAceWidgets or {}) do
      if button.text == text then refresh(function() button.callbacks.OnClick(button) end); return end
    end
    error("missing navigation " .. text)
  end

  local function consent(checked)
    local box = assert_not_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_CONSENT))
    refresh(function() box.callbacks.OnValueChanged(box, "OnValueChanged", checked) end)
  end

  local function output()
    return widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_PACKAGE)
  end

  local function select(snapshotId)
    local widgets = _G.__dibsAceWidgets or {}
    for index = #widgets, start + 1, -1 do
      local grid = widgets[index]._dibsDataGrid
      if grid then
        local rowIndex
        for position, row in ipairs(grid.rows) do if row.id == snapshotId then rowIndex = position; break end end
        if rowIndex then
          local position = 0
          for _, group in ipairs(widgets[index].children or {}) do
            if group._dibsDataGridRow then
              position = position + 1
              if position == rowIndex then
                for _, child in ipairs(group.children or {}) do
                  if child.text == "Select" then
                    refresh(function() child.callbacks.OnClick(child) end)
                    return
                  end
                end
              end
            end
          end
        end
      end
    end
    error("missing snapshot selection " .. tostring(snapshotId))
  end

  local function create(scope)
    local choice = assert_not_nil(widget("label", "Backup scope"))
    choice.callbacks.OnValueChanged(choice, "OnValueChanged", scope)
    click("Create backup")
    local selected
    for _, snapshot in ipairs(dibs.Backup.List()) do selected = snapshot end
    -- Creation selects its new ID; locate the visible ID rather than relying on timestamps.
    for _, snapshot in ipairs(dibs.Backup.List()) do
      if widget("text", snapshot.snapshotId) then selected = snapshot; break end
    end
    return assert_not_nil(selected)
  end

  local function setup(locale)
    local _, loaded = loader.load({ withAce3 = true, wow = { guildLeader = true, locale = locale } })
    dibs = loaded
    refresh(function() dibs.DataUI.Open("backups") end)
  end

  it("exports retained historical local content through the real controls without re-exporting on refresh", function()
    setup()
    dibs.GetDB().settings.uiScale = 0.8
    local snapshot = create("local")
    dibs.GetDB().settings.uiScale = 1.2
    local calls, original = 0, dibs.Backup.ExportSnapshot
    dibs.Backup.ExportSnapshot = function(id, options)
      calls = calls + 1
      assert_nil(options.confirmedSensitive)
      return original(id, options)
    end
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_equal(snapshot.packageText, assert_not_nil(output()).text)
    local package = assert(dibs.ImportExport.Decode(output().text))
    assert_equal(0.8, package.payload.presentation.uiScale)
    assert_equal(1.2, dibs.GetDB().settings.uiScale)
    refresh()
    assert_equal(snapshot.packageText, assert_not_nil(output()).text)
    assert_equal(1, calls)
    refresh(function() dibs.DataUI.Open("transfer") end)
    assert_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_PACKAGE))
  end)

  it("requires a checked sensitive-data consent for full export and shows the recovery restriction", function()
    setup()
    local snapshot = create("full")
    assert_not_nil(widget("text", dibs.L.DATA_FULL_IMPORT_LIMIT))
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_FAILED .. "SENSITIVE_CONFIRMATION_REQUIRED"))
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_equal(snapshot.packageText, assert_not_nil(output()).text)
    consent(false)
    assert_nil(output())
  end)

  it("exports a historical guild configuration without a full-data consent control", function()
    setup()
    local snapshot = create("guild")
    assert_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_CONSENT))
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_equal(snapshot.packageText, assert_not_nil(output()).text)
    assert_equal("guild", assert(dibs.ImportExport.Decode(output().text)).scope)
  end)

  it("discards sensitive consent and text when a different snapshot is selected", function()
    setup()
    local first = create("full")
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_not_nil(output())
    local nextSnapshot = assert(dibs.Backup.Create("full", "second test snapshot"))
    refresh()
    select(nextSnapshot.snapshotId)
    assert_nil(output())
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    select(first.snapshotId)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
  end)

  it("clears a prior result on export failure and does not fall back to live export", function()
    setup()
    create("local")
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_not_nil(output())
    dibs.Backup.ExportSnapshot = function() return nil, "SNAPSHOT_PACKAGE_MISSING" end
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_FAILED .. "SNAPSHOT_PACKAGE_MISSING"))
  end)

  it("rechecks integrity without displaying a cached package after its source becomes invalid", function()
    setup()
    local snapshot = create("local")
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    dibs.Backup.Get(snapshot.snapshotId).packageText = nil
    refresh()
    assert_nil(output())
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_UNAVAILABLE .. "SNAPSHOT_PACKAGE_MISSING"))
  end)

  local function replaceRetainedSnapshot(snapshot, scope)
    dibs.GetDB().settings.uiScale = 1.37
    local replacement = assert(dibs.Backup.Create(scope, "replacement test snapshot"))
    local retained = dibs.Backup.Get(snapshot.snapshotId)
    for key in pairs(retained) do retained[key] = nil end
    for key, value in pairs(replacement) do retained[key] = dibs.DeepCopy(value) end
    retained.snapshotId = snapshot.snapshotId
    assert_true(dibs.Backup.ValidateSnapshotExport(snapshot.snapshotId, { confirmedSensitive = true }))
  end

  it("discards text and consent when a valid snapshot replaces the selected ID", function()
    setup()
    local snapshot = create("full")
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    replaceRetainedSnapshot(snapshot, "full")
    refresh()
    assert_nil(output())
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_FAILED .. "SENSITIVE_CONFIRMATION_REQUIRED"))
  end)

  it("refreshes scope and rejects stale control consent when a local snapshot becomes full", function()
    setup()
    local snapshot = create("local")
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    replaceRetainedSnapshot(snapshot, "full")
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_FAILED .. "SNAPSHOT_EXPORT_CHANGED"))
    assert_not_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_CONSENT))
    assert_not_nil(widget("text", dibs.L.DATA_FULL_IMPORT_LIMIT))
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
  end)

  it("clears cached full text and consent after Officer authority is lost", function()
    setup()
    create("full")
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    local can = dibs.Permissions.Can
    dibs.Permissions.Can = function(action, actor)
      if action == "settings.modify" then return false end
      return can(action, actor)
    end
    refresh()
    assert_nil(output())
    assert_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_CONSENT))
    dibs.Permissions.Can = can
    refresh()
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
  end)

  it("clears cached text on character or guild changes and never restores old consent", function()
    setup()
    create("full")
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    local name = dibs.GetPlayerName
    dibs.GetPlayerName = function() return "Other-Realm" end
    refresh()
    assert_nil(output())
    dibs.GetPlayerName = name
    refresh()
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    local guildInfo = _G.GetGuildInfo
    _G.GetGuildInfo = function() return "Other Guild" end
    dibs.GetDB()
    refresh()
    assert_nil(output())
    _G.GetGuildInfo = guildInfo
    dibs.GetDB()
    refresh()
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
  end)

  it("resets historical output on page reopen, navigation, and new backup creation", function()
    setup()
    create("full")
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    refresh(function() dibs.DataUI.Open("backups") end)
    assert_nil(output())
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    navigate("Profiles")
    navigate("Backups")
    assert_nil(output())
    consent(true)
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    create("full")
    assert_nil(output())
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_nil(output())
  end)

  it("renders the historical controls and warnings in French", function()
    setup("frFR")
    create("full")
    assert_equal("Exporter la sauvegarde sélectionnée", dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_ACTION))
    assert_not_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_CONSENT))
    assert_not_nil(widget("text", dibs.L.DATA_SNAPSHOT_EXPORT_SENSITIVE))
    assert_not_nil(widget("text", dibs.L.DATA_FULL_IMPORT_LIMIT))
  end)
end)
