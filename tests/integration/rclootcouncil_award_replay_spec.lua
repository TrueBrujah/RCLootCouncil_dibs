local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function countAwardTransactions(dibs)
  local count = 0
  for _, tx in pairs(dibs.GetDB().ledger.transactions or {}) do
    if tx.awardRef then count = count + 1 end
  end
  return count
end

describe("RCLootCouncil award replay protection", function()
  it("reuses the same accounting result after a reload", function()
    local rc = loader.makeRCLootCouncil({
      enabled = true,
      currentSessionId = "reload-session-9",
      masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" },
    })
    local _, first = loader.load({
      rclootcouncil = rc,
      wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } },
    })
    first.GetDB().settings.allowPublicPreDibs = false
    local resultOne = first.RCLootCouncil.OnAwardSuccess(nil, 3, "Tester-Realm", "normal", "item:19019", "DIB")
    local persisted = _G.RCLootCouncil_dibsDB

    local rcAfterReload = loader.makeRCLootCouncil({
      enabled = true,
      currentSessionId = "reload-session-9",
      masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" },
    })
    local _, second = loader.load({
      rclootcouncil = rcAfterReload,
      savedVariables = persisted,
      wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } },
    })
    second.GetDB().settings.allowPublicPreDibs = false
    local resultTwo = second.RCLootCouncil.OnAwardSuccess(nil, 3, "Tester-Realm", "normal", "item:19019", "DIB")

    assert_true(resultOne and resultOne.ok)
    assert_true(resultTwo and resultTwo.ok)
    assert_equal(resultOne.value.transactionId, resultTwo.value.transactionId)
    assert_equal(1, countAwardTransactions(second))
    assert_equal(0, second.Ledger.GetBalance("Tester-Realm"))
  end)

  it("rejects a stale actor after the Master Looter changes", function()
    local rc = loader.makeRCLootCouncil({
      enabled = true,
      currentSessionId = "ml-change-session",
      masterLooter = { guid = "Player-2-ML", name = "Other-Realm" },
    })
    local _, dibs = loader.load({
      rclootcouncil = rc,
      wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } },
    })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = dibs.ProtectedActions.FinalizeAward({ guid = "Player-1-TESTER", name = "Tester-Realm" }, {
      awardRef = "session:ml-change-session:1:tester-realm:19019",
      playerName = "Tester-Realm",
      itemID = 19019,
      itemLink = "item:19019",
      sourceStatus = "normal",
      source = "rclootcouncil",
      response = "DIB",
      responseValidated = true,
    })

    assert_false(result and result.ok)
    assert_equal("RC_NOT_MASTER_LOOTER", result and result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("does not debit for non-DIB, test, or incomplete callbacks", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = "rejection-session" })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = dibs.Ledger.GetBalance("Tester-Realm")

    local nonDibEvent = wow.makeRCLootCouncilAward({ session = 1, response = "Need" })
    local nonDib
    wow.replayRCLootCouncilAward(function(_, session, winner, status, itemLink, response)
      nonDib = dibs.RCLootCouncil.OnAwardSuccess(nil, session, winner, status, itemLink, response)
    end, nonDibEvent, 1)
    local testAward = dibs.RCLootCouncil.OnAwardSuccess(nil, 2, "Tester-Realm", "test_mode", "item:19019", "DIB")
    local missingItem = dibs.RCLootCouncil.OnAwardSuccess(nil, 3, "Tester-Realm", "normal", "not-an-item", "DIB")

    assert_equal("NON_DIB_RESPONSE", nonDib.reasonCode)
    assert_true(testAward and testAward.ignored)
    assert_true(missingItem and missingItem.ignored)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)
end)
