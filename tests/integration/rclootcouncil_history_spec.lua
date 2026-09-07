local loader = require("helpers.load_addon")

describe("RCLootCouncil history boundary", function()
  it("preserves unrelated history identifiers and marks only Dibs-originated rows", function()
    local unrelated = { id = "rc-original-17", itemID = 19019, response = "Need" }
    local history = { ["Other-Realm"] = { unrelated } }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.GetHistoryDB = function() return history end
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })

    assert_equal("rc-original-17", history["Other-Realm"][1].id)
    assert_equal("Need", history["Other-Realm"][1].response)

    local logged = dibs.RCLootCouncil.LogPreDibRequest({
      requestId = "predib-42",
      playerName = "Tester-Realm",
      itemID = 19019,
      itemName = "|cffffffff|Hitem:19019::::::::::::|h[Test item]|h|r",
      source = "History test",
    }, "History test")
    assert_true(logged)
    assert_equal("rc-original-17", history["Other-Realm"][1].id)
    assert_equal("RCLootCouncil_dibs", history["Tester-Realm"][1].dibsOrigin)
  end)
end)
