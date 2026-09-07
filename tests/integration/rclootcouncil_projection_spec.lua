local loader = require("helpers.load_addon")

describe("RCLootCouncil Dibs projections", function()
  it("accepts partial optional award metadata without mutating RC data", function()
    local history = { ["Tester-Realm"] = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = "projection-session" })
    rc.GetHistoryDB = function() return history end
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local statusBefore = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019)
    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, nil, "Tester-Realm", "normal", "item:19019", "DIB")
    local statusAfter = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019)

    assert_true(result and result.ok)
    assert_equal(statusBefore.balance - 1, statusAfter.balance)
    assert_equal(0, #history["Tester-Realm"])
  end)

  it("keeps projection reads side-effect free", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = #dibs.Ledger.GetAllTransactions()
    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019, "MOUNTS")
    local capabilities = dibs.RCLootCouncil.GetCapabilities()
    assert_true(type(status) == "table")
    assert_true(type(capabilities) == "table")
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
