local loader = require("helpers.load_addon")

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
end)
