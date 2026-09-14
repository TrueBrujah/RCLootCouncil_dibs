local loader = require("helpers.load_addon")

describe("B11f reconciliation actions", function()
  it("delegates confirm and reject without writing RCLootCouncil history", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "action-1", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded" },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local search = dibs.LogsUI.SearchHistory({ seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" } })
    local candidate = search.view.candidates[1]
    local sourceResponse = history["Tester-Realm"][1].response
    local confirmCalls, rejectCalls = 0, 0
    local originalConfirm = dibs.RCLootCouncil.ConfirmReconciliationCandidate
    local originalReject = dibs.RCLootCouncil.RejectReconciliationCandidate
    dibs.RCLootCouncil.ConfirmReconciliationCandidate = function(sessionId, candidateId, payload, actor)
      confirmCalls = confirmCalls + 1
      assert_equal(search.session.sessionId, sessionId)
      assert_equal(candidate.candidateId, candidateId)
      assert_true(payload.confirmation)
      return { ok = true, outcome = "awarded", value = { transactionId = "tx-1" } }
    end
    dibs.RCLootCouncil.RejectReconciliationCandidate = function(sessionId, candidateId, reason, actor)
      rejectCalls = rejectCalls + 1
      assert_equal(search.session.sessionId, sessionId)
      assert_equal(candidate.candidateId, candidateId)
      assert_true(reason ~= "")
      return { ok = true, outcome = "rejected" }
    end

    local confirmed = dibs.LogsUI.ConfirmCandidate(search.session.sessionId, candidate.candidateId, "Verified archive", { confirmation = true })
    local rejected = dibs.LogsUI.RejectCandidate(search.session.sessionId, candidate.candidateId, "Duplicate record")
    dibs.RCLootCouncil.ConfirmReconciliationCandidate = originalConfirm
    dibs.RCLootCouncil.RejectReconciliationCandidate = originalReject

    assert_true(confirmed.ok)
    assert_true(rejected.ok)
    assert_equal(1, confirmCalls)
    assert_equal(1, rejectCalls)
    assert_equal(sourceResponse, history["Tester-Realm"][1].response)
    assert_equal(1, #dibs.Ledger.GetAllTransactions())
  end)

  it("does not offer confirmation for ambiguous or stale candidates", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "stale-1", itemID = 19019, lootWon = "item:19019", response = "DIB", responseID = 1, status = "awarded" },
        { id = "stale-2", itemID = 19020, lootWon = "item:19020", response = "DIB", responseID = 2, status = "awarded" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local search = dibs.LogsUI.SearchHistory({ seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" } })
    local blocked = dibs.LogsUI.ConfirmCandidate(search.session.sessionId, search.view.candidates[1].candidateId, "should not confirm", { confirmation = true })
    assert_false(blocked.ok)
    assert_equal("HISTORY_CANDIDATE_NOT_CONFIRMABLE", blocked.reasonCode)

    local stale = dibs.LogsUI.RejectCandidate("missing-session", "missing-candidate", "Not found")
    assert_false(stale.ok)
    assert_equal("HISTORY_SESSION_NOT_FOUND", stale.reasonCode)
  end)

  it("keeps normal players outside the reconciliation surface", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } }, withAce3 = true })
    assert_false(dibs.LogsUI.CanViewReconciliation())
    local result = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    assert_false(result.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", result.reasonCode)
  end)
end)
