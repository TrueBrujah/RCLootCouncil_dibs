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
end)