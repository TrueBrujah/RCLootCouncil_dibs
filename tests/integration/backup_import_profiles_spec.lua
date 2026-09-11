describe("Backup, import/export and profiles", function()
  local loader, dibs
  before_each(function()
    loader = require("helpers.load_addon")
    _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
  end)

  it("exports a versioned local package and validates its checksum", function()
    local text, package = dibs.ImportExport.Export("local")
    assert_not_nil(text); assert_equal("local", package.scope)
    local decoded = dibs.ImportExport.Decode(text)
    assert_not_nil(decoded); assert_equal(package.checksum, decoded.checksum)
    local bad = text:sub(1, -2) .. "x"
    assert_nil(dibs.ImportExport.Decode(bad))
  end)

  it("rejects malformed, truncated and future package fixtures", function()
    local fixtures = require("helpers.package_fixtures")
    assert_nil(dibs.ImportExport.Decode(fixtures.invalidPrefix))
    assert_nil(dibs.ImportExport.Decode(fixtures.emptyPackage))
    assert_nil(dibs.ImportExport.Decode(fixtures.truncatedPackage))
    assert_nil(dibs.ImportExport.Decode(fixtures.futureSchema))
  end)

  it("rejects executable-looking package content", function()
    local text = dibs.ImportExport.Export("local")
    assert_not_nil(text)
    local package = dibs.ImportExport.Decode(text)
    package.payload.presentation.theme = "/run evil"
    local body = "DIBS-PKG-1|" .. "{}"
    assert_nil(dibs.ImportExport.Decode(body))
  end)

  it("creates a safety snapshot before restoring a preview", function()
    local db = dibs.GetDB(); db.settings.theme = "before"
    local snapshot = dibs.Backup.Create("local", "test")
    assert_not_nil(snapshot)
    db.settings.theme = "after"
    local preview = dibs.Backup.PreviewRestore(snapshot.snapshotId)
    assert_not_nil(preview); assert_equal("after", db.settings.theme)
    dibs.Backup.Restore(preview.previewId, true, "test")
    assert_equal("before", db.settings.theme)
    assert_true(#dibs.Backup.List() >= 2)
  end)

  it("keeps profile operations independent from ledger balances", function()
    local season = dibs.GetCurrentSeasonId(); dibs.Ledger.Grant("Tester-Realm", 1, "test", "test", season)
    local before = #dibs.Ledger.GetAllTransactions()
    local profile = dibs.Profiles.Create("Test profile", "local")
    assert_not_nil(profile)
    assert_not_nil(dibs.Profiles.PreviewActivation("Test profile", "local"))
    assert_not_nil(dibs.Profiles.Activate("Test profile", "local"))
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
    assert_not_nil(dibs.Profiles.Copy("Test profile", "Copied profile", "local"))
    assert_not_nil(dibs.Profiles.Rename("Copied profile", "Renamed profile", "local"))
    assert_not_nil(dibs.Profiles.Reset("Renamed profile", "local"))
    assert_true(dibs.Profiles.Delete("Renamed profile", "local"))
    assert_true(dibs.Profiles.Delete("Test profile", "local"))
  end)

  it("previews and applies a guild configuration package", function()
    local text = dibs.ImportExport.Export("guild")
    assert_not_nil(text)
    local preview = dibs.ImportExport.Preview(text, "guild", "merge")
    assert_not_nil(preview)
    assert_equal("pending", preview.decision)
    local result = dibs.ImportExport.Apply(preview.previewId, true, "test")
    assert_equal("confirmed", result.decision)
  end)

  it("appends full ledger data idempotently", function()
    local season = dibs.GetCurrentSeasonId()
    dibs.Ledger.Grant("Tester-Realm", 1, "portable", "test", season)
    local text = dibs.ImportExport.Export("full")
    local preview = dibs.ImportExport.Preview(text, "full", "append")
    local count = #dibs.Ledger.GetAllTransactions()
    local applied = dibs.ImportExport.Apply(preview.previewId, true, "test")
    assert_equal("confirmed", applied.decision)
    assert_equal(count, #dibs.Ledger.GetAllTransactions())
  end)

  it("renders the Data control center into a persistent content host", function()
    local shell = dibs.DataUI.Open("backups")
    assert_not_nil(shell)
    assert_not_nil(shell.pageHost)
    assert_not_nil(shell.contentHost)
    assert_equal(760, shell.window.width)
    assert_equal("List", shell.pageHost.layout)
    assert_true((shell.contentHost.height or 0) >= 320)
    assert_not_nil(shell.contentPage)
    assert_true((shell.contentPage.height or 0) >= 320)
    assert_true(#(shell.pageHost.children or {}) >= 2)
    assert_true(#(shell.contentHost.children or {}) > 0)
    dibs.DataUI.Open("transfer")
    assert_true(#(shell.contentHost.children or {}) > 0)
  end)

  it("wires the visible backup and transfer actions", function()
    local before = #dibs.Backup.List()
    dibs.DataUI.Open("backups")
    local clicked = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.text == "Create backup" and widget.callbacks and widget.callbacks.OnClick then
        widget.callbacks.OnClick(widget)
        clicked = true
        break
      end
    end
    assert_true(clicked)
    assert_true(#dibs.Backup.List() > before)

    dibs.DataUI.Open("transfer")
    local exported = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.text == "Export package" and widget.callbacks and widget.callbacks.OnClick then
        widget.callbacks.OnClick(widget)
        exported = true
        break
      end
    end
    assert_true(exported)
    local hasPackageText = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if type(widget.text) == "string" and widget.text:find("DIBS%-PKG%-1%|", 1, false) then
        hasPackageText = true
        break
      end
    end
    assert_true(hasPackageText)
  end)
end)
