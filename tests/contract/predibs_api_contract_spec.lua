local loader = require("helpers.load_addon")

describe("Pre-Dib API contract", function()
  it("exposes lifecycle operations with stable outcomes", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 21031, "Item 21031", dibs.GetCurrentSeasonId())

    assert_not_nil(request)
    assert_not_nil(dibs.PreDibs.Confirm(request.requestId))
    assert_not_nil(dibs.PreDibs.Cancel(request.requestId))
    local reactivated, reason = dibs.PreDibs.Confirm(request.requestId)
    assert_nil(reactivated)
    assert_equal("INVALID_STATUS_TRANSITION", reason)
  end)

  it("returns stable validation reasons", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request, reason = dibs.PreDibs.CreatePublic("Tester-Realm", 0, "Invalid", dibs.GetCurrentSeasonId(), "test")
    assert_nil(request)
    assert_equal("INVALID_ITEM", reason)
  end)

  it("stores a versioned mode policy per season", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()

    assert_equal("WILD_OPEN", dibs.PreDibs.GetModePolicy(seasonId).mode)
    local policy = dibs.PreDibs.SetModePolicy(seasonId, "ENCOUNTER", "Tester-Realm")

    assert_equal("ENCOUNTER", policy.mode)
    assert_equal("Tester-Realm", policy.changedBy)
  end)

  it("merges only newer revisions while preserving immutable request origin", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21032, "Item 21032", dibs.GetCurrentSeasonId(), "test")
    local incoming = {
      requestId = request.requestId,
      playerName = "Tester-Realm",
      itemID = 99999,
      seasonId = "other-season",
      modeAtCreation = "ENCOUNTER",
      createdAt = 0,
      revision = request.revision + 1,
      status = "cancelled",
      updatedAt = request.updatedAt + 1,
    }

    local merged = dibs.PreDibs.UpsertFromSync(incoming, "Tester-Realm")
    local stale = dibs.PreDibs.UpsertFromSync(incoming, "Tester-Realm")

    assert_not_nil(merged)
    assert_nil(stale)
    assert_equal("Tester-Realm", request.playerName)
    assert_equal(21032, request.itemID)
    assert_equal("cancelled", request.status)
    assert_equal("WILD_OPEN", request.modeAtCreation)
  end)
end)
