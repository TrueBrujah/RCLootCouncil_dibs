local loader = require("helpers.load_addon")

describe("Pre-Dib lifecycle", function()
  it("rejects creation when no season is available", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.GetCurrentSeasonId = function() return nil end

    local request, reason = dibs.PreDibs.CreatePublic("Tester-Realm", 21001, "Item 21001", nil, "test")

    assert_nil(request)
    assert_equal("NO_ACTIVE_SEASON", reason)
    assert_equal(0, #dibs.PreDibs.GetHistory())
  end)

  it("does not reactivate terminal requests", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local initialRevision = dibs.PreDibs.GetHistoryRevision()
    local request = dibs.PreDibs.Create("Tester-Realm", 21002, "Item 21002", dibs.GetCurrentSeasonId())
    assert_not_nil(request)
    local createdRevision = dibs.PreDibs.GetHistoryRevision()

    local cancelled = dibs.PreDibs.Cancel(request.requestId)
    local reactivated = dibs.PreDibs.Confirm(request.requestId)

    assert_true(createdRevision > initialRevision)
    assert_true(dibs.PreDibs.GetHistoryRevision() > createdRevision,
      "request status changes should invalidate request-index projections")
    assert_equal("cancelled", cancelled.status)
    assert_nil(reactivated)
    assert_equal("cancelled", dibs.PreDibs.GetHistory()[1].status)
  end)

  it("announces a changed request index immediately", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local sentBefore = #dibs.Ace3.libs.comm.sent
    local request = dibs.PreDibs.Create("Tester-Realm", 21021, "Sync item", dibs.GetCurrentSeasonId())
    assert_not_nil(request)

    local announced = false
    for index = sentBefore + 1, #dibs.Ace3.libs.comm.sent do
      local sent = dibs.Ace3.libs.comm.sent[index]
      local message = dibs.Ace3.Deserialize(sent.payload)
      if sent.channel == "GUILD" and message and message.type == "DIGEST" and message.entityType == "PREDIB_INDEX" then
        announced = true
      end
    end
    assert_true(announced)
  end)

  it("allows a player to cancel only their own active request", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local own = dibs.PreDibs.CreatePublic("Tester-Realm", 21005, "Own item", dibs.GetCurrentSeasonId(), "test")
    local other = dibs.PreDibs.CreatePublic("Other-Realm", 21006, "Other item", dibs.GetCurrentSeasonId(), "test")

    local denied, deniedReason = dibs.PreDibs.CancelForPlayer(other.requestId, "Tester-Realm")
    local cancelled = dibs.PreDibs.CancelForPlayer(own.requestId, "Tester-Realm")

    assert_nil(denied)
    assert_equal("NOT_REQUEST_OWNER", deniedReason)
    assert_equal("cancelled", cancelled.status)
    assert_equal("confirmed", other.status)
  end)

  it("shows pending and confirmed requests in officer details", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.PreDibs.Create("Tester-Realm", 21003, "Pending item", seasonId)
    dibs.PreDibs.CreatePublic("Tester-Realm", 21004, "Confirmed item", seasonId, "test")

    local details = dibs.OfficerUI.BuildPreDibDetails(seasonId)
    local summary = table.concat(details.requests, "\n")

    assert_equal(2, #details.requests)
    assert_equal(2, details.activeRequestCount)
    assert_true(string.find(summary, "pending | Pending item", 1, true) ~= nil)
    assert_true(string.find(summary, "confirmed | Confirmed item", 1, true) ~= nil)
  end)

  it("builds the Wizard summary from one resolved Pre-Dibs store", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local db = dibs.GetDB()
    local seasonId = dibs.GetCurrentSeasonId()
    db.preDibs.modePolicies[seasonId] = { mode = "ENCOUNTER" }
    db.settings.allowPublicPreDibs = false

    local summary = dibs.PreDibs.GetStatusSummary(seasonId)
    assert_equal("ENCOUNTER", summary.mode)
    assert_equal(false, summary.publicEnabled)
    assert_equal(0, summary.activeRequestCount)
    assert_equal(0, summary.historyCount)
  end)

  it("reads the Wizard summary from the resolved guild DB without re-running DB resolution", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local getDB = dibs.GetDB
    local getPolicySummary = dibs.OperationalPolicy.GetPreDibSummary
    dibs.GetDB = function() error("read-only Wizard summary should use the resolved guild DB") end
    dibs.OperationalPolicy.GetPreDibSummary = function() return { adopted = false } end

    local ok, summary = pcall(dibs.PreDibs.GetStatusSummary, seasonId, "guild-primary")
    dibs.GetDB = getDB
    dibs.OperationalPolicy.GetPreDibSummary = getPolicySummary
    assert_true(ok, tostring(summary))
    assert_equal(0, summary.historyCount)
  end)

  it("reuses the resolved guild DB when reading initialized Pre-Dibs history", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local history = dibs.PreDibs.GetHistory("guild-primary")
    local getDB = dibs.GetDB
    dibs.GetDB = function() error("initialized Pre-Dibs history should reuse the resolved guild DB") end

    local ok, result = pcall(dibs.PreDibs.GetHistory, "guild-primary")
    dibs.GetDB = getDB

    assert_true(ok, tostring(result))
    assert_equal(history, result, "history read should return the same initialized request array")
  end)

  it("reads legacy Wizard history without migrating SavedVariables", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local db = dibs.GetDB()
    local root = db.preDibs
    local seasonId = dibs.GetCurrentSeasonId()
    root.ledgerStorageVersion = nil
    root.ledgers = {}
    root.requests = { { requestId = "legacy-request", status = "pending", seasonId = seasonId } }
    root.modePolicies = { [seasonId] = { mode = "ENCOUNTER" } }

    local summary = dibs.PreDibs.GetStatusSummary(seasonId)
    assert_equal("ENCOUNTER", summary.mode)
    assert_equal(1, summary.historyCount)
    assert_equal(nil, root.ledgerStorageVersion)
    assert_equal(nil, root.ledgers["guild-primary"])
    assert_equal(nil, root.requests[1].ledgerId)
    assert_equal(1, #dibs.PreDibs.GetHistory())
  end)

  it("reuses the resolved request index for a cached Player summary", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local history = dibs.PreDibs.GetHistory("guild-primary")
    history[#history + 1] = {
      requestId = "summary-index-cache", playerName = "Tester-Realm",
      seasonId = dibs.GetCurrentSeasonId(), status = "pending", createdAt = 10,
    }
    dibs.PreDibs.MarkHistoryChanged("guild-primary")
    local first = dibs.PreDibs.GetPlayerSeasonRequestSummary(
      "Tester-Realm", dibs.GetCurrentSeasonId(), "guild-primary")
    assert_equal(1, #first.active)

    local getHistoryLookup = dibs.PreDibs.GetHistoryLookup
    local getActiveLedgerId = dibs.MultiLedger.GetActiveLedgerId
    local lookupCalls, activeLedgerCalls = 0, 0
    dibs.PreDibs.GetHistoryLookup = function(...)
      lookupCalls = lookupCalls + 1
      return getHistoryLookup(...)
    end
    dibs.MultiLedger.GetActiveLedgerId = function(...)
      activeLedgerCalls = activeLedgerCalls + 1
      return getActiveLedgerId(...)
    end

    local second = dibs.PreDibs.GetPlayerSeasonRequestSummary(
      "Tester-Realm", dibs.GetCurrentSeasonId(), "guild-primary")
    dibs.PreDibs.GetHistoryLookup, dibs.MultiLedger.GetActiveLedgerId = getHistoryLookup, getActiveLedgerId
    assert_equal(first, second)
    assert_equal(0, lookupCalls, "the validated history index should be reused directly")
    assert_equal(0, activeLedgerCalls, "an explicit read-only ledger should not be resolved again")
  end)
end)
