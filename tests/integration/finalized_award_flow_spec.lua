local loader = require("helpers.load_addon")

describe("Finalize award flow", function()
  it("does not consume on non-final status", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local before = #dibs.Ledger.GetAllTransactions()

    local result = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "r1",
      playerName = "Tester-Realm",
      itemID = 19019,
      sourceStatus = "pending",
    })

    assert_false(result.ok)
    local after = #dibs.Ledger.GetAllTransactions()
    assert_equal(before, after)
  end)

  it("consumes once and fulfills confirmed predib", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 19019, "Item", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)

    local first = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "award-1",
      playerName = "Tester-Realm",
      itemID = 19019,
      sourceStatus = "awarded",
      finalized = true,
    })
    assert_true(first.ok)

    local second = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "award-1",
      playerName = "Tester-Realm",
      itemID = 19019,
      sourceStatus = "awarded",
      finalized = true,
    })
    assert_true(second.ok)
    assert_equal(first.value.transactionId, second.value.transactionId)

    local fulfilled = dibs.PreDibs.GetHistory()[1]
    assert_equal("fulfilled", fulfilled.status)
  end)

  it("uses award difficulty when available and retains legacy matching when absent", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local normal = dibs.PreDibs.CreatePublic("Tester-Realm", 19020, "Normal", seasonId, "test", { difficulty = "Normal" })
    local heroic = dibs.PreDibs.CreatePublic("Tester-Realm", 19020, "Heroic", seasonId, "test", { difficulty = "Heroic" })

    local result = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "award-difficulty", playerName = "Tester-Realm", itemID = 19020,
      sourceStatus = "awarded", finalized = true, difficulty = 15,
    })

    assert_true(result.ok)
    assert_equal("confirmed", normal.status)
    assert_equal("fulfilled", heroic.status)
  end)

  it("requires a DIB response for RCLootCouncil awards and ignores test awards", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.Ledger.GetBalance("Tester-Realm")

    dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19021", "Need")
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))

    dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "test_mode", "item:19022", "Dib")
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))

    dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19023", "Dib")
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
    dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19023", "Dib")
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("rejects a personal Catalyst award even when an old DIB response exists", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" } })
    rc.lootTable = {
      [1] = { itemGUID = "catalyst-guid", item = { link = "item:19027", typeCode = "CATALYST" } },
    }
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.Ledger.GetBalance("Tester-Realm")

    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19027", "Dib")
    assert_false(result.ok)
    assert_equal("AWARD_PERSONAL_ITEM", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("does not consume from a degraded or explicitly standalone RC callback", function()
    local degraded = { enabled = true, masterLooter = nil }
    local _, dibs = loader.load({ rclootcouncil = degraded, wow = { guildLeader = true } })
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19024", "DIB")
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))

    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" } })
    local _, standalone = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    standalone.ProtectedActions.Execute("installation.mode.set", nil, { mode = "STANDALONE" })
    local standaloneBefore = standalone.Ledger.GetBalance("Tester-Realm")
    standalone.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19025", "DIB")
    assert_equal(standaloneBefore, standalone.Ledger.GetBalance("Tester-Realm"))
  end)

  it("does not let a non-ML client replay the ML callback into its local ledger", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-2-ML", name = "Other-Realm" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      guildLeader = false,
      guildMembers = { "Tester-Realm" },
      guildRankIndices = { [1] = 3 },
    } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.Ledger.GetBalance("Tester-Realm")

    dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "normal", "item:19026", "DIB")

    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)
end)
