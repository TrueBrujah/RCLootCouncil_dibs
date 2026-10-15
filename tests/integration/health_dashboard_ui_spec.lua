local loader = require("helpers.load_addon")

describe("Health dashboard UI", function()
  it("keeps Diagnostics as one Officer-owned page", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.HealthUI.Evaluate = function()
      return {
        status = "DEGRADED", version = "0.8.1", schemaVersion = 7,
        blockingCount = 0, warningCount = 1,
        checks = {
          { id = "persistence", state = "ready", reason = "VALID", detail = "SavedVariables are ready." },
          { id = "readiness", state = "unavailable", reason = { REASON_Z = true, REASON_A = true }, detail = "Readiness is unavailable." },
        },
        persistence = { state = "VALID" }, sync = { state = "SYNC_READY" },
        rclootcouncil = { status = "absent" },
      }
    end
    local serviceTable
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if columns[1] and columns[1].title == "Service" then
        serviceTable = { columns = columns, rows = rows, options = options }
      end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.OfficerUI.CreateWindow("diagnostics")
    assert_equal("diagnostics", frame.selectedRoute)
    assert_equal("diagnostics", frame.mountedPage)
    assert_equal(1, frame.primaryPageCount)
    assert_true(frame.contentHost._dibsCurrentPageRoot ~= nil)

    assert_not_nil(serviceTable)
    assert_equal(3, #serviceTable.columns)
    assert_equal("State", serviceTable.columns[2].title)
    assert_equal("CENTER", serviceTable.columns[2].align)
    assert_true(serviceTable.columns[3].wrap)
    assert_equal(2, #serviceTable.rows)
    assert_equal("SavedVariables", serviceTable.rows[1][1])
    assert_equal("READY", serviceTable.rows[1][2])
    assert_true(serviceTable.rows[2][3]:find("REASON A, REASON Z", 1, true) ~= nil)
    assert_false(serviceTable.rows[2][3]:find("table:", 1, true) ~= nil, tostring(serviceTable.rows[2][3]))
    local healthDetailsButton, runtimeDetailsButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == "Show technical health details" then healthDetailsButton = widget end
      if widget.kind == "Button" and widget.text == "Show runtime diagnostics" then runtimeDetailsButton = widget end
    end
    assert_not_nil(healthDetailsButton)
    assert_not_nil(runtimeDetailsButton)
    assert_equal(healthDetailsButton.parent, runtimeDetailsButton.parent)
  end)

  it("renders grouped findings and routes Vault review through the existing page", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.HealthUI.Evaluate = function()
      return { status = "READY", version = "test", schemaVersion = 7, checks = {}, blockingCount = 0, warningCount = 0 }
    end
    dibs.HealthUI.ScanAnomalies = function()
      return {
        status = "REVIEW_REQUIRED",
        count = 1,
        sources = { vaultConflicts = { status = "AVAILABLE" } },
        anomalies = {
          { id = "internal-conflict-1", category = "VAULT_CONFLICT", status = "REVIEW_REQUIRED", action = "OPEN_VAULT_REVIEW", detail = "A Vault conflict needs Officer review." },
        },
      }
    end
    dibs.HealthUI.BuildCorrectionPreview = function(id)
      assert_equal("internal-conflict-1", id)
      return {
        status = "PREVIEW",
        mutation = "NONE",
        nextAction = "OPEN_VAULT_REVIEW",
        finding = { category = "VAULT_CONFLICT", detail = "A Vault conflict needs Officer review." },
      }
    end
    local findingTable
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if columns[1] and columns[1].title == "Category" then
        findingTable = { columns = columns, rows = rows }
      end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end

    local frame = dibs.OfficerUI.CreateWindow("diagnostics")

    assert_not_nil(findingTable)
    assert_equal(1, #findingTable.rows)
    assert_equal(dibs.L.HEALTH_REVIEW_CATEGORY_VAULT_CONFLICT, findingTable.rows[1][1])
    assert_equal("REVIEW_REQUIRED", findingTable.rows[1][2])
    assert_false(tostring(findingTable.rows[1][3]):find("internal-conflict-1", 1, true) ~= nil)
    local previewButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == "Preview finding" then previewButton = widget end
    end
    assert_not_nil(previewButton)
    previewButton.callbacks.OnClick(previewButton, "OnClick")
    assert_true(frame.healthFindingPreview ~= nil)
    assert_equal("NONE", frame.healthFindingPreview.mutation)

    local reviewButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == "Open Vault review" then reviewButton = widget end
    end
    assert_not_nil(reviewButton)
    reviewButton.callbacks.OnClick(reviewButton, "OnClick")
    assert_equal("vault", frame.selectedRoute)
  end)

  it("shows an explicit empty state and an export copy surface", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.HealthUI.Evaluate = function()
      return { status = "READY", version = "test", schemaVersion = 7, checks = {}, blockingCount = 0, warningCount = 0 }
    end
    dibs.HealthUI.ScanAnomalies = function()
      return { status = "HEALTHY", count = 0, sources = {}, anomalies = {} }
    end
    dibs.HealthUI.ExportAnomalies = function()
      return "DIBS-HEALTH-1|encoded-report", { totalCount = 0 }
    end
    local frame = dibs.OfficerUI.CreateWindow("diagnostics")
    local exportButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == "Export health report" then exportButton = widget end
    end

    assert_not_nil(exportButton)
    local emptyStateVisible = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" and widget.text == "No data findings need review." then emptyStateVisible = true end
    end
    assert_true(emptyStateVisible)
    exportButton.callbacks.OnClick(exportButton, "OnClick")
    assert_equal("DIBS-HEALTH-1|encoded-report", frame.healthFindingExport)
    local copySurface
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "MultiLineEditBox" or widget.kind == "EditBox" then
        if widget.text == "DIBS-HEALTH-1|encoded-report" then copySurface = widget end
      end
    end
    assert_not_nil(copySurface)

    dibs.HealthUI.ExportAnomalies = function() return nil, "ENCODER_UNAVAILABLE" end
    exportButton.callbacks.OnClick(exportButton, "OnClick")
    assert_nil(frame.healthFindingExport)
    assert_true(frame.statusMessage:find("ENCODER_UNAVAILABLE", 1, true) ~= nil)
  end)

  it("shows when one of the anomaly sources is unavailable", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.HealthUI.Evaluate = function()
      return { status = "READY", version = "test", schemaVersion = 7, checks = {}, blockingCount = 0, warningCount = 0 }
    end
    dibs.HealthUI.ScanAnomalies = function()
      return {
        status = "UNAVAILABLE", count = 0, anomalies = {},
        sources = { vaultConflicts = { status = "UNAVAILABLE" } },
      }
    end

    dibs.OfficerUI.CreateWindow("diagnostics")

    local unavailableVisible = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" and widget.text == "Some review sources are unavailable; this is not a clean scan." then
        unavailableVisible = true
      end
    end
    assert_true(unavailableVisible)
  end)
end)