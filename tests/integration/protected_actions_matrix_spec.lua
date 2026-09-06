local loader = require("helpers.load_addon")

describe("ProtectedActions matrix", function()
  it("allows season/rank/ledger/admin actions for standalone guild master", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, playerName = "Tester-Realm", playerGUID = "Player-1-TESTER" } })

    local seasonResult = dibs.ProtectedActions.Execute("season.create", nil, { name = "Sx" })
    assert_true(seasonResult.ok)

    local rankResult = dibs.ProtectedActions.Execute("rank.set", nil, { seasonId = seasonResult.value.id, rankIndex = 2, rankName = "Officer", allocation = 2 })
    assert_true(rankResult.ok)

    local grantResult = dibs.ProtectedActions.Execute("ledger.grant", nil, { playerName = "Tester-Realm", amount = 1, reason = "test" })
    assert_true(grantResult.ok)

    local listResult = dibs.ProtectedActions.Execute("admin.list", nil, {})
    assert_true(listResult.ok)
  end)

  it("denies Dibs administration when actor is not a guild admin", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-ML", name = "ML-Realm" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })

    local result = dibs.ProtectedActions.Execute("ledger.grant", { guid = "Player-1-OTHER", name = "Other-Realm" }, { playerName = "Tester-Realm", amount = 1 })
    assert_false(result.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", result.reasonCode)
  end)
end)
