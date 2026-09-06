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
    local request = dibs.PreDibs.Create("Tester-Realm", 21002, "Item 21002", dibs.GetCurrentSeasonId())
    assert_not_nil(request)

    local cancelled = dibs.PreDibs.Cancel(request.requestId)
    local reactivated = dibs.PreDibs.Confirm(request.requestId)

    assert_equal("cancelled", cancelled.status)
    assert_nil(reactivated)
    assert_equal("cancelled", dibs.PreDibs.GetHistory()[1].status)
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
end)
