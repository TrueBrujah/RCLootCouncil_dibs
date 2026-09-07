local loader = require("helpers.load_addon")

describe("RCLootCouncil finalized-award contract", function()
  it("rejects a callback when no stable award identity is available", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = false })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19019", "DIB")

    assert_true(result and result.ignored)
    assert_equal("AWARD_IDENTITY_UNAVAILABLE", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("uses a stable session identity for duplicate delivery", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = "loot-42", masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.Ledger.GetBalance("Tester-Realm")

    local first = dibs.RCLootCouncil.OnAwardSuccess(nil, 7, "Tester-Realm", "normal", "item:19019", "DIB")
    local second = dibs.RCLootCouncil.OnAwardSuccess(nil, 7, "Tester-Realm", "normal", "item:19019", "DIB")

    assert_true(first and first.ok)
    assert_true(second and second.ok)
    assert_equal("awarded", first.outcome)
    assert_equal("duplicate", second.outcome)
    assert_true(second.duplicate)
    assert_equal(first.value.transactionId, second.value.transactionId)
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("rejects ambiguous history identity instead of guessing", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = false })
    rc.GetHistoryDB = function()
      return {
        ["Tester-Realm"] = {
          { id = "history-1", itemID = 19019 },
          { id = "history-2", itemID = 19019 },
        },
      }
    end
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19019", "DIB")

    assert_true(result and result.ignored)
    assert_equal("AWARD_IDENTITY_AMBIGUOUS", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)
end)
