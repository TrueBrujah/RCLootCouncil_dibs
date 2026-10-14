local loader = require("helpers.load_addon")

describe("Pre-Dib migration", function()
  it("preserves requests and settings while upgrading the schema", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local db = dibs.GetDB()
    local request = {
      requestId = "legacy-predib-1",
      playerName = "Tester-Realm",
      itemID = 21061,
      seasonId = "season-legacy",
      status = "confirmed",
      createdAt = 1,
      updatedAt = 1,
    }
    db.version = 1
    db.preDibs.requests = { request }
    db.settings.allowPublicPreDibs = false

    local migrated = dibs.GetDB()

    assert_equal(7, migrated.version)
    assert_equal(request.requestId, migrated.preDibs.requests[1].requestId)
    assert_equal(request.playerName, migrated.preDibs.requests[1].playerName)
    assert_equal(request.itemID, migrated.preDibs.requests[1].itemID)
    assert_equal(request.seasonId, migrated.preDibs.requests[1].seasonId)
    assert_equal("Normal", migrated.preDibs.requests[1].difficulty)
    assert_false(migrated.settings.allowPublicPreDibs)
    assert_not_nil(migrated.ledger)
    assert_not_nil(migrated.ledger.transactions)
  end)

  it("migrates legacy requests to Normal while separating new difficulty variants", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local legacy = dibs.PreDibs.Create("Tester-Realm", 21062, "Legacy", seasonId)
    local heroic = dibs.PreDibs.CreatePublic("Tester-Realm", 21062, "Heroic", seasonId, "test", { difficulty = "Heroic" })
    local db = dibs.GetDB()
    db.version = 4
    legacy.difficulty = "UNKNOWN"

    local migrated = dibs.GetDB()

    assert_equal("Normal", migrated.preDibs.requests[1].difficulty)
    assert_equal("Heroic", heroic.difficulty)
    assert_equal(2, #migrated.preDibs.requests)
  end)

  it("migrates legacy requests appended by a later snapshot", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
    local proposal = dibs.MultiLedger.ProposeLedger("Tester-Realm", "Alt Raid")
    assert_true(proposal.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposal.ledgerId).ok)
    assert_true(dibs.MultiLedger.SetActiveLedger(proposal.ledgerId))
    local request = {
      requestId = "snapshot-legacy-request",
      playerName = "Tester-Realm",
      itemID = 21063,
      seasonId = dibs.GetCurrentSeasonId(),
      status = "confirmed",
    }

    assert_true(dibs.Sync.ApplySnapshot({ transactions = {}, preDibs = { request } }))
    local primaryHistory = dibs.PreDibs.GetHistory("guild-primary")
    local alternateHistory = dibs.PreDibs.GetHistory(proposal.ledgerId)
    assert_equal(1, #primaryHistory)
    assert_equal("guild-primary", primaryHistory[1].ledgerId)
    assert_equal(0, #alternateHistory)
    assert_equal(0, #dibs.GetDB().preDibs.requests)
    assert_equal(proposal.ledgerId, dibs.MultiLedger.GetActiveLedgerId())
  end)
end)
