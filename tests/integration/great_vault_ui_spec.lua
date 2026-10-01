local loader = require("helpers.load_addon")
local uiMocks = require("helpers.b11_ui_mocks")

describe("Great Vault UI acceptance", function()
  it("documents the manual Vault fallback in slash command help", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.HandleSlashCommand("help")
    local found = false
    for _, message in ipairs(_G.__dibsMessages or {}) do
      if message:find("/dibs vault <itemID> [difficulty]", 1, true) then
        found = true
      end
    end
    assert_true(found)
  end)

  it("keeps player projections private while exposing status and reset context", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.PreDibs.GetAcquisitionsForPlayer = function()
      return {
        {
          itemID = 275658,
          itemName = "Primeval Skyfriend",
          verificationState = "AUTOMATIC_CONFIRMED",
          resetId = "week-42",
          acquiredAt = 1700000100,
          source = "RETAIL_CLAIM",
          syncState = "SYNCED",
          evidence = { privateToken = "hidden" },
        },
      }
    end
    local summary = dibs.PlayerUI.GetSummary()
    assert_equal(1, #summary.acquisitions)
    assert_equal("AUTOMATIC_CONFIRMED", summary.acquisitions[1].verificationState)
    assert_equal("week-42", summary.acquisitions[1].resetId)
    assert_nil(summary.acquisitions[1].evidence)
    assert_nil(summary.acquisitions[1].privateToken)
  end)

  it("sorts bounded Officer history and keeps date and search values visible", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    dibs.PreDibs.GetAcquisitions = function()
      return {
        { acquisitionId = "old", playerName = "Tester-Realm", itemID = 100, itemName = "Old Item", acquiredAt = 1700000000, verificationState = "LEGACY_RECORDED", resetId = "week-41", source = "MIGRATED" },
        { acquisitionId = "new", playerName = "Officer-Realm", itemID = 200, itemName = "New Item", acquiredAt = 1700000200, verificationState = "MANUAL_RECORDED", resetId = "week-42", source = "MANUAL" },
      }
    end
    local page = dibs.OfficerUI.GetPagedView("vault", nil, 1, 1)
    assert_equal(2, page.totalCount)
    assert_equal(2, page.totalPages)
    assert_true(page.lines[1]:find("New Item", 1, true) ~= nil)
    assert_true(page.lines[1]:find("2026", 1, true) ~= nil)

    local filtered = dibs.OfficerUI.GetPagedView("vault", nil, 1, 8, "Old Item")
    assert_equal(1, filtered.totalCount)
    assert_true(filtered.lines[1]:find("Old Item", 1, true) ~= nil)

    local empty = dibs.OfficerUI.GetPagedView("vault", nil, 1, 8, "missing")
    assert_equal(0, empty.totalCount)
    assert_equal("No Great Vault records for this season.", empty.lines[1])
  end)

  it("preserves responsive minimums for the Vault table window", function()
    local _, dibs = loader.load({ withAce3 = true })
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    local shell = dibs.AceGUI.CreateWindow("Vault Review", 240, 180)
    assert_equal(metrics.minWidth, shell.layout.width)
    assert_equal(metrics.minHeight, shell.layout.height)
    assert_true(metrics.maxWidth >= metrics.minWidth)
    assert_true(metrics.maxHeight >= metrics.minHeight)
  end)

  it("keeps Vault Review headers on one row when the Officer content area is narrow", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    dibs.PreDibs.GetAcquisitions = function()
      return {
        {
          acquisitionId = "compact-vault", playerName = "Tester-Realm", itemID = 275658,
          itemName = "Primeval Skyfriend", acquiredAt = 1700000100,
          verificationState = "MANUAL_RECORDED", resetId = "week-42",
          source = "MANUAL", syncState = "SYNCED", review = { reason = "Verified in game" },
        },
      }
    end
    local captured
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      captured = { columns = columns, rows = rows, options = options }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.OfficerUI.CreateWindow("vault")
    assert_equal(4, #captured.columns)
    assert_equal("Date", captured.columns[1].title)
    assert_equal("Player", captured.columns[2].title)
    assert_equal("Status", captured.columns[3].title)
    assert_equal("Item", captured.columns[4].title)
    assert_true(captured.options.fluidColumns)
    assert_equal("Tester-Realm", captured.rows[1][2])
    assert_equal("Primeval Skyfriend", captured.rows[1][4])
    assert_true(captured.options.cellTooltip(captured.rows[1], 4):find("week-42", 1, true) ~= nil)
    frame.contentHost.frame.GetWidth = function() return 1240 end
    frame:Refresh()
    assert_equal(8, #captured.columns)
    assert_equal("CENTER", captured.columns[1].align)
    assert_equal("CENTER", captured.columns[3].align)
    assert_not_nil(frame.ledgerTablePage)
  end)

  it("uses the shared AceGUI dropdown style for Vault review controls", function()
    local msaNames = {
      "MSA_DropDownMenu_Create", "MSA_DropDownMenu_Initialize", "MSA_DropDownMenu_CreateInfo",
      "MSA_DropDownMenu_AddButton", "MSA_ToggleDropDownMenu", "MSA_DropDownMenu_SetText",
      "MSA_DropDownMenu_SetWidth", "MSA_DropDownMenu_JustifyText", "MSA_DropDownMenu_SetSelectedValue",
    }
    local previous = {}
    for _, name in ipairs(msaNames) do previous[name] = _G[name] end
    local msaState = uiMocks.installMSA()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("vault")

    assert_equal("Dropdown", frame.vaultAcquisition.kind)
    assert_equal("Dropdown", frame.vaultDecision.kind)
    assert_equal("Dropdown", frame.vaultStatusControl.kind)
    assert_equal(0, msaState.created)

    for _, name in ipairs(msaNames) do _G[name] = previous[name] end
  end)
end)
