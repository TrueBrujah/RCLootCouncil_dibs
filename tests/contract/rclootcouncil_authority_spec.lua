local loader = require("helpers.load_addon")

describe("RCLootCouncil authority contract", function()
  it("keeps guild administration separate from the current Master Looter", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-2-ML", name = "Other-Realm" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      guildLeader = false,
      guildMembers = { "Tester-Realm", "Other-Realm" },
      guildRankIndices = { [1] = 3, [2] = 3 },
    } })

    local mlDecision = dibs.Permissions.Evaluate("settings.modify", { guid = "Player-2-ML", name = "Other-Realm" })
    local playerDecision = dibs.Permissions.Evaluate("settings.modify", nil)

    assert_false(mlDecision.allowed)
    assert_equal("GUILD_ADMIN_REQUIRED", mlDecision.reasonCode)
    assert_false(playerDecision.allowed)
  end)

  it("allows only a local verified ML to use the award exception", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })

    local localDecision = dibs.Permissions.Evaluate("award.finalize", { guid = "Player-1-TESTER", name = "Tester-Realm" })
    local remoteDecision = dibs.Permissions.Evaluate("award.finalize", { guid = "Player-2-OTHER", name = "Other-Realm" })

    assert_true(localDecision.allowed)
    assert_equal("rclootcouncil", localDecision.authority)
    assert_false(remoteDecision.allowed)
    assert_equal("RC_ACTOR_NOT_LOCAL", remoteDecision.reasonCode)
  end)

  it("rejects a forged RCLootCouncil payload without stable provenance", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = "authority-session" })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = dibs.ProtectedActions.FinalizeAward(rc.masterLooter, {
      awardRef = "forged-ref",
      playerName = "Tester-Realm",
      itemID = 19019,
      itemLink = "item:19019",
      sourceStatus = "normal",
      source = "rclootcouncil",
      response = "DIB",
      responseValidated = true,
    })
    assert_false(result and result.ok)
    assert_equal("AWARD_PROVENANCE_INVALID", result and result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)
end)
