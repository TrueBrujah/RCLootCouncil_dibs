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

    assert_equal(6, migrated.version)
    assert_equal(request, migrated.preDibs.requests[1])
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
end)
