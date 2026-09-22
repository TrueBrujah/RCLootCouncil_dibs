local loader = require("helpers.load_addon")

describe("B12 historical candidate projection", function()
  it("filters exact aliases before applying the bounded candidate limit", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "a-need", itemID = 19018, lootWon = "item:19018", response = "Need", status = "success" },
        { id = "b-dib", itemID = 19019, lootWon = "item:19019", response = "  dib  ", status = "success" },
        { id = "c-dib", itemID = 19020, lootWon = "item:19020", response = "DIB", status = "success" },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" }, limit = 1 }, nil)

    assert_equal(3, session.counts.sourceScanned)
    assert_equal(1, session.counts.hiddenNonDib)
    assert_equal(1, session.counts.eligible)
    assert_equal(1, #session.candidates)
    assert_equal("history:b-dib", session.candidates[1].historyRef)
    assert_equal("DIB", session.candidates[1].normalizedResponse)
    assert_equal("DIB", session.candidates[1].aliasUsed)
  end)

  it("projects stable identity and related winner and difficulty context", function()
    local history = {
      ["Heroic-Winner"] = {
        { id = "heroic-identity", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", difficultyName = "Heroic" },
      },
      ["Normal-Winner"] = {
        { id = "normal-identity", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", difficultyName = "Normal" },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local byRef = {}
    for _, candidate in ipairs(session.candidates) do byRef[candidate.historyRef] = candidate end
    local candidate = byRef["history:heroic-identity"]

    assert_not_nil(candidate.candidateId)
    assert_equal(candidate.historyRef, candidate.awardRef)
    assert_equal("reconciliation:" .. candidate.candidateId, candidate.evidenceId)
    assert_equal(1, candidate.relatedHistoryCount)
    assert_true(candidate.relatedWinners:find("Heroic-Winner", 1, true) ~= nil)
    assert_true(candidate.relatedWinners:find("Normal-Winner", 1, true) ~= nil)
    assert_true(candidate.relatedDifficulties:find("Heroic", 1, true) ~= nil)
    assert_true(candidate.relatedDifficulties:find("Normal", 1, true) ~= nil)
  end)

  it("blocks rows with conflicting response identities as ambiguous", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "identity-one", itemID = 19019, lootWon = "item:19019", response = "DIB", responseID = 1, status = "success" },
        { id = "identity-two", itemID = 19020, lootWon = "item:19020", response = " DIB ", responseID = 2, status = "success" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)

    for _, candidate in ipairs(session.candidates) do
      assert_equal("ambiguous", candidate.classification)
      assert_equal("HISTORY_RESPONSE_IDENTITY_AMBIGUOUS", candidate.reasonCode)
    end
    assert_equal(2, session.counts.ambiguous)
    assert_equal(0, session.counts.eligible)
  end)

  it("marks a previously imported stable identity as already accounted", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "already-accounted", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success" },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local first = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local candidate = first.candidates[1]
    local imported = dibs.RCLootCouncil.ConfirmReconciliationCandidate(first.sessionId, candidate.candidateId, {
      mode = "guided", confirmation = true, reason = "Historical import",
    }, nil)
    assert_true(imported and imported.ok)

    local second = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local projected = second.candidates[1]
    assert_equal(candidate.evidenceId, projected.evidenceId)
    assert_equal(candidate.awardRef, projected.awardRef)
    assert_equal("already_accounted", projected.classification)
    assert_equal("HISTORY_ALREADY_ACCOUNTED", projected.reasonCode)
    assert_equal(1, second.counts.already_accounted)
  end)

  it("preserves bounded date scans and fail-closed unknown or non-final classifications", function()
    local history = { ["Tester-Realm"] = {} }
    for index = 1, 3 do
      history["Tester-Realm"][index] = {
        id = "bounded-" .. tostring(index), itemID = 19020 + index, lootWon = "item:" .. tostring(19020 + index),
        response = "DIB", status = "success", timestamp = 1700000000 + index * 100,
      }
    end
    history["Tester-Realm"][4] = {
      id = "pending-row", itemID = 19030, lootWon = "item:19030", response = "DIB", status = "pending", timestamp = 1700000500,
    }
    history["Tester-Realm"][5] = {
      id = "unknown-row", response = "DIB", status = "success", timestamp = 1700000600,
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows, reason, metadata = dibs.RCLootCouncil.GetHistoryRows({ aliases = { "DIB" }, limit = 999, fromTime = 1700000100, toTime = 1700000400 })
    assert_nil(reason)
    assert_equal(3, metadata.scanned)
    assert_equal(3, #rows)

    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" }, limit = 500 }, nil)
    local byRef = {}
    for _, candidate in ipairs(session.candidates) do byRef[candidate.historyRef] = candidate end
    assert_equal("rejected", byRef["history:pending-row"].classification)
    assert_equal("HISTORY_NON_FINAL", byRef["history:pending-row"].reasonCode)
    assert_equal("unsupported", byRef["history:unknown-row"].classification)
    assert_equal("HISTORY_UNSUPPORTED", byRef["history:unknown-row"].reasonCode)
    local view = dibs.LogsUI.BuildReconciliationView(session.sessionId)
    for _, candidate in ipairs(view.candidates) do
      if candidate.candidateId == byRef["history:unknown-row"].candidateId then
        assert_equal("Unavailable", candidate.item)
        assert_equal("Tester-Realm", candidate.winner)
        assert_false(candidate.canConfirm)
      end
    end
  end)
end)
