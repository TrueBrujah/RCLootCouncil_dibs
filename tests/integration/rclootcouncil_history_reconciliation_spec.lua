local loader = require("helpers.load_addon")

describe("RCLootCouncil history reconciliation", function()
  it("builds a read-only preview with exact aliases and classifies duplicates", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "old-1", itemID = 19019, lootWon = "item:19019", response = "  dib  ", status = "awarded", timestamp = 1700000100 },
        { id = "old-2", itemID = 19020, lootWon = "item:19020", response = "Need", status = "awarded", timestamp = 1700000200 },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local session, reason = dibs.RCLootCouncil.CreateReconciliationSession({
      seasonId = seasonId, aliases = "DIB", mode = "guided", limit = 20,
    }, nil)
    assert_true(session ~= nil, reason)
    assert_equal(1, session.counts.scanned)
    assert_equal(2, session.counts.sourceScanned)
    assert_equal(1, session.counts.hiddenNonDib)
    assert_equal(1, session.counts.eligible)
    assert_equal(0, session.counts.rejected)
    assert_equal(1, #session.candidates)
    assert_equal("DIB", session.candidates[1].aliasUsed)
    assert_equal(1, #dibs.Ledger.GetAllTransactions()) -- season allocation only
  end)

  it("confirms an eligible row once and keeps immutable evidence", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "old-1", itemID = 19019, lootWon = "item:19019", response = "Dib", status = "success", timestamp = 1700000100 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local candidate = session.candidates[1]
    local first = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "guided", reason = "Guild history import", confirmation = true,
    }, nil)
    assert_true(first and first.ok)
    local second = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "guided", reason = "Repeated click", confirmation = true,
    }, nil)
    assert_true(second and second.ok)
    assert_true(second.duplicate)
    assert_equal(2, #dibs.Ledger.GetAllTransactions()) -- season allocation + historical debit
    local evidence = dibs.GetDB().reconciliation.evidence[candidate.evidenceId]
    assert_true(evidence and evidence.immutable)
    assert_equal("Dib", evidence.responseText)
    assert_equal("RCMLAwardSuccess", evidence.sourceEvent)
    assert_equal("FinalizeAward", evidence.accountingAction)
    assert_equal("old-1", tostring(evidence.historyRef):gsub("^history:", ""))
  end)

  it("uses the history bucket player as winner instead of the original loot owner", function()
    local history = {
      ["Meatyfajita-Ysera"] = {
        {
          id = "1788395568-7",
          itemID = 270167,
          lootWon = "item:270167",
          response = "Dibs",
          status = "success",
          owner = "Leetah-Durotan",
          timestamp = 1788395568,
        },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal(1, #rows)
    assert_equal("Meatyfajita-Ysera", rows[1].winner)
    assert_equal("Meatyfajita-Ysera", rows[1].playerName)
    assert_equal("Leetah-Durotan", rows[1].originalOwner)
  end)

  it("normalizes compact item tokens into selectable rich links", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Meatyfajita-Ysera"] = {
        {
          id = "1788395568-8",
          itemID = 270167,
          lootWon = "item:270167::::::::::::",
          itemName = "Wavecaller's Seastone",
          response = "Dibs",
          status = "success",
        },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_true(rows[1].itemLink:find("|Hitem:270167", 1, true) ~= nil)
    assert_true(rows[1].itemLink:find("[Wavecaller's Seastone]", 1, true) ~= nil)
    rows[1].itemName = "changed by the preview"
    local secondRows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal("Wavecaller's Seastone", secondRows[1].itemName)
  end)

  it("keeps zero award timestamps unavailable", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "zero-time", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", timestamp = 0, date = "0" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_nil(rows[1].originalAwardTime)
    assert_nil(rows[1].originalAwardTimeText)
  end)

  it("requires acknowledgement and a reason for ambiguous manual rows", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" }, mode = "manual" }, nil)
    local candidate = session.candidates[1]
    assert_equal("ambiguous", candidate.classification)
    local denied = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", confirmation = true, manualAcknowledgement = false,
    }, nil)
    assert_false(denied and denied.ok)
    local accepted = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", confirmation = true, manualAcknowledgement = true, reason = "Verified against guild archive",
    }, nil)
    assert_true(accepted and accepted.ok)
  end)

  it("renders the Officer reconciliation page without exposing it to players", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {} })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true, withAce3 = true } })
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame ~= nil)
    frame.SelectTab("reconciliation")
    assert_equal("reconciliation", frame.activeTab)
  end)
end)
