local loader = require("helpers.load_addon")

describe("RCLootCouncil Dibs projections", function()
  it("rejects partial optional award metadata without mutating RC data", function()
    local history = { ["Tester-Realm"] = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true, currentSessionId = "projection-session" })
    rc.GetHistoryDB = function() return history end
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    dibs.GetDB().settings.allowPublicPreDibs = false
    local statusBefore = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019)
    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, nil, "Tester-Realm", "normal", "item:19019", "DIB")
    local statusAfter = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019)

    assert_true(result and result.ignored)
    assert_equal("RC_VERSION_UNSUPPORTED", result.reasonCode)
    assert_equal(statusBefore.balance, statusAfter.balance)
    assert_equal(0, #history["Tester-Realm"])
  end)

  it("keeps projection reads side-effect free", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = #dibs.Ledger.GetAllTransactions()
    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019, "MOUNTS")
    local capabilities = dibs.RCLootCouncil.GetCapabilities()
    assert_true(type(status) == "table")
    assert_true(type(capabilities) == "table")
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("projects the indexed balance without scanning or sorting ledger history", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local memberKey = dibs.Identity.CanonicalMemberKey("Tester-Realm")
    dibs.GetDB().ledger.playerStates[seasonId][memberKey] = { allocation = 2, balance = 2, transactions = {} }
    dibs.RankRules.SetAllocation(seasonId, 0, "Guild Master", 3)

    local original = {}
    for _, methodName in ipairs({ "GetTransactions", "GetPlayerSeasonState", "GetPlayerState", "GetBalance" }) do
      original[methodName] = dibs.Ledger[methodName]
      dibs.Ledger[methodName] = function() error(methodName .. " must not be used by the projection") end
    end
    original.GetPendingDibReservations = dibs.Ledger.GetPendingDibReservations
    dibs.Ledger.GetPendingDibReservations = function() return 1 end

    local ok, projection = pcall(dibs.Ledger.GetCanonicalPlayerDibsState, seasonId, "Tester-Realm")
    for methodName, method in pairs(original) do dibs.Ledger[methodName] = method end
    assert_true(ok, tostring(projection))
    assert_true(projection.available)
    assert_equal("Tester-Realm", projection.canonicalName)
    assert_equal(2, projection.canonicalBalance)
    assert_equal(2, projection.balance)
    assert_equal(1, projection.pendingDibReservations)
    assert_equal(1, projection.availableBalance)
    assert_equal(3, projection.rankMaximum)
  end)

  it("reads balance and reservations once when computing candidate availability", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local balanceCalls, reservationCalls = 0, 0
    dibs.Ledger.GetBalance = function() balanceCalls = balanceCalls + 1; return 2 end
    dibs.Ledger.GetPendingDibReservations = function() reservationCalls = reservationCalls + 1; return 1 end
    dibs.Ledger.GetAvailableBalance = function() error("availability should reuse the values already read") end

    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 19019)

    assert_equal(1, balanceCalls)
    assert_equal(1, reservationCalls)
    assert_equal(1, status.availableBalance)
  end)

  it("scans Pre-Dib history once to derive candidate request and item priority", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local requests = {
      { requestId = "other-player", playerName = "Officer-Realm", itemID = 280001, seasonId = seasonId, status = "confirmed" },
      { requestId = "candidate-confirmed", playerName = "Tester-Realm", itemID = 280001, seasonId = seasonId, status = "confirmed" },
      { requestId = "candidate-pending", playerName = "Tester-Realm", itemID = 280001, seasonId = seasonId, status = "pending" },
      { requestId = "candidate-other-season", playerName = "Tester-Realm", itemID = 280001, seasonId = "old-season", status = "confirmed" },
      { requestId = "other-item", playerName = "Tester-Realm", itemID = 280002, seasonId = seasonId, status = "confirmed" },
    }
    dibs.GetDB().preDibs.requests = requests

    local originalIpairs = ipairs
    local requestListScans = 0
    ipairs = function(target)
      if target == requests then requestListScans = requestListScans + 1 end
      return originalIpairs(target)
    end
    local ok, status = pcall(dibs.RCLootCouncil.GetStatusForCandidate, "Tester-Realm", 280001, "INVTYPE_HEAD")
    ipairs = originalIpairs

    assert_true(ok, tostring(status))
    assert_equal(1, requestListScans)
    assert_true(status.hasPreDib)
    assert_true(status.hasAnyConfirmedPreDib)
    assert_equal("candidate-confirmed", status.preDibRequest.requestId)
  end)

  it("reuses Vote Frame and tooltip projections and invalidates them after relevant changes", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local rankInfo = dibs.Identity.ResolveRosterMember("Tester-Realm")
    dibs.RankRules.GetRulesForSeason(seasonId)[tostring(rankInfo.rankIndex)] = nil
    local pendingReads = 0
    local originalPending = dibs.Ledger.GetPendingDibReservations
    dibs.Ledger.GetPendingDibReservations = function() pendingReads = pendingReads + 1; return 0 end

    local initial = dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId)
    local repeated = dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId)
    assert_equal(initial.canonicalBalance, repeated.canonicalBalance)
    assert_equal(1, pendingReads)
    dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" })
    dibs.RCLootCouncil.GetDibsColumnTooltip({ name = "Tester-Realm" })
    assert_equal(1, pendingReads)

    dibs.GetDB().settings.defaultAllocation = 11
    assert_equal(11, dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId).rankMaximum)
    assert_equal(2, pendingReads)
    dibs.RankRules.SetAllocation(seasonId, rankInfo.rankIndex, rankInfo.rankName, 7)
    assert_equal(7, dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId).rankMaximum)
    assert_equal(3, pendingReads)
    dibs.Identity.InvalidateRoster("PROJECTION_CACHE_TEST")
    dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId)
    assert_equal(4, pendingReads)

    local oldSeasonGeneration = dibs.Seasons.GetCurrentSeasonGeneration()
    local nextSeason = dibs.Seasons.Create("Projection cache test")
    assert_true(dibs.Seasons.GetCurrentSeasonGeneration() > oldSeasonGeneration)
    dibs.Ledger.GetPlayerDibsProjection("Tester-Realm")
    assert_equal(5, pendingReads)
    assert_true(dibs.Seasons.SetCurrent(seasonId))
    dibs.Ledger.GetPlayerDibsProjection("Tester-Realm")
    assert_equal(6, pendingReads)

    local grant, grantReason = dibs.Ledger.Grant("Tester-Realm", 2, "Cache test grant", "cache-test", seasonId,
      { transactionId = "projection-cache-grant" })
    assert_not_nil(grant, tostring(grantReason))
    assert_equal(initial.canonicalBalance + 2, dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId).canonicalBalance)
    assert_equal(7, pendingReads)
    local used, useReason = dibs.Ledger.Use("Tester-Realm", 1, "Cache test use", "cache-test", seasonId,
      { transactionId = "projection-cache-use" })
    assert_not_nil(used, tostring(useReason))
    assert_equal(initial.canonicalBalance + 1, dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId).canonicalBalance)
    assert_equal(8, pendingReads)
    local refunded, refundReason = dibs.Ledger.Refund("Tester-Realm", 1, "Cache test refund", "cache-test", seasonId,
      { transactionId = "projection-cache-refund" })
    assert_not_nil(refunded, tostring(refundReason))
    assert_equal(initial.canonicalBalance + 2, dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId).canonicalBalance)
    assert_equal(9, pendingReads)
    local adjusted, adjustmentReason = dibs.Ledger.AdminAdjust("Tester-Realm", -1, "Cache test adjustment", "cache-test", seasonId,
      { transactionId = "projection-cache-adjustment" })
    assert_not_nil(adjusted, tostring(adjustmentReason))
    assert_equal(initial.canonicalBalance + 1, dibs.Ledger.GetPlayerDibsProjection("Tester-Realm", seasonId).canonicalBalance)
    assert_equal(10, pendingReads)
    assert_nil(dibs.GetDB().projectionCache)
    assert_nil(dibs.GetDB().ledger.projectionCache)
    dibs.Ledger.GetPendingDibReservations = originalPending
  end)
end)
