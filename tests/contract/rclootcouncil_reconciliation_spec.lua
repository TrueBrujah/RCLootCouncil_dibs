local loader = require("helpers.load_addon")

describe("RCLootCouncil reconciliation contract", function()
  it("exposes read-only history rows without changing the source table", function()
    local source = { ["Tester-Realm"] = { { id = "proof-1", itemID = 19019, response = " DIB ", status = "complete" } } }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = source })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal(1, #rows)
    assert_equal("history:proof-1", rows[1].historyRef)
    assert_equal(" DIB ", source["Tester-Realm"][1].response)
    assert_equal("DIB", dibs.RCLootCouncil.NormalizeResponseAlias(rows[1].responseText))
  end)

  it("keeps reconciliation actions restricted to guild administration", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = { { id = "proof-2", itemID = 19019, response = "DIB", status = "awarded" } },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 },
    } })
    local session, reason = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    assert_equal(nil, session)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)

  it("marks one visible label with conflicting response identities ambiguous", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "proof-3", itemID = 19019, response = "DIB", responseID = 1, status = "awarded" },
        { id = "proof-4", itemID = 19020, response = "DIB", responseID = 2, status = "awarded" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    assert_equal("ambiguous", session.candidates[1].classification)
    assert_equal("HISTORY_RESPONSE_IDENTITY_AMBIGUOUS", session.candidates[1].reasonCode)
  end)

  it("does not expose the complete history rows to an ordinary player", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Other-Realm"] = { { id = "private-1", itemID = 19019, response = "DIB", status = "awarded" } },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      guildLeader = false, guildMembers = { "Tester-Realm", "Other-Realm" }, guildRankIndices = { [1] = 3, [2] = 3 },
    } })
    local rows, reason = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal(nil, rows)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)
end)
