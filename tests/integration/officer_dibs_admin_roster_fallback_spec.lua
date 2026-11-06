local loader = require("helpers.load_addon")

describe("Officer Dibs Administration roster fallback", function()
  it("reads multiple player history summaries with one ledger resolution", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true, guildMembers = { "Tester-Realm" },
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local memberKey = dibs.Identity.CanonicalMemberKey("Tester-Realm")
    ledger.transactions["summary-test-tx"] = { transactionId = "summary-test-tx",
      type = "DIB_GRANTED", amount = 4, createdAt = 1 }
    ledger.playerStates[seasonId] = ledger.playerStates[seasonId] or {}
    ledger.playerStates[seasonId][memberKey] = { allocation = 2, transactions = { "summary-test-tx" } }

    local originalGetDB, dbReads = dibs.GetDB, 0
    dibs.GetDB = function(...)
      dbReads = dbReads + 1
      return originalGetDB(...)
    end
    local summaries = dibs.Ledger.GetPlayerHistorySummaries({
      { playerName = "Tester-Realm", memberKey = memberKey }, "Offline-Realm",
    }, seasonId, "guild-primary")
    dibs.GetDB = originalGetDB

    assert_equal(1, dbReads, "the batch should normalize/resolve the ledger once")
    assert_equal(6, summaries[1].balance)
    assert_equal(1, summaries[1].count)
    assert_equal(0, summaries[2].balance)
  end)

  it("renders the native guild roster while the shared identity snapshot is empty", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true, guildMembers = { "Tester-Realm" },
    } })
    local originalSnapshot = dibs.Identity.GetRosterSnapshot
    local originalCount, originalInfo, originalRealm = _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.GetRealmName
    local originalSummary, originalBalance = dibs.Ledger.GetPlayerHistorySummary, dibs.Ledger.GetBalance
    local originalBatchSummaries = dibs.Ledger.GetPlayerHistorySummaries
    dibs.Ledger.GetPlayerHistorySummaries = nil
    dibs.Identity.GetRosterSnapshot = function() return {} end
    _G.GetNumGuildMembers = function() return 1 end
    _G.GetGuildRosterInfo = function(index)
      if index == 1 then return "Tester-Realm", "Guild Master", 0 end
    end
    _G.GetRealmName = function() return "Realm" end
    dibs.Ledger.GetPlayerHistorySummary = function() return { balance = 7 } end
    dibs.Ledger.GetBalance = function() error("cached summary should supply the balance") end

    local ok, roster = pcall(dibs.OfficerUI.BuildDibsAdministrationRoster, dibs.GetCurrentSeasonId())

    dibs.Identity.GetRosterSnapshot = originalSnapshot
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo, _G.GetRealmName = originalCount, originalInfo, originalRealm
    dibs.Ledger.GetPlayerHistorySummary, dibs.Ledger.GetBalance = originalSummary, originalBalance
    dibs.Ledger.GetPlayerHistorySummaries = originalBatchSummaries

    assert_true(ok, tostring(roster))
    assert_equal("ready", roster.state)
    assert_equal(1, #roster.rows)
    assert_equal("Tester-Realm", roster.rows[1].playerName)
    assert_equal(7, roster.rows[1].balance)
  end)
end)
