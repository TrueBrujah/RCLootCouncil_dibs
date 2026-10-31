local loader = require("helpers.load_addon")

local function activateV2(wow)
  local _, dibs = loader.load({ wow = wow })
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "rank reconciliation test" }))
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 1,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
  return dibs
end

local function setRule(dibs, seasonId, rankIndex, rankName, allocation, enabled)
  local result = dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = seasonId, rankIndex = rankIndex, rankName = rankName, allocation = allocation, enabled = enabled,
  })
  assert_true(result.ok, tostring(result.diagnostic))
end

describe("Rank allocation reconciliation", function()
  it("lists expected, assigned, missing, and surplus allocations for guild members", function()
    local _, dibs = loader.load({
      wow = {
        guildLeader = true,
        guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3, [3] = 1 },
      },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 0, "Guild Master", 5)
    dibs.RankRules.SetAllocation(seasonId, 1, "Officer", 3)
    dibs.RankRules.SetAllocation(seasonId, 3, "Member", 1)
    dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Existing allocation", {
      action = "rank.reconcile", actor = "Tester-Realm",
    })
    assert_equal(1, dibs.Ledger.GetPlayerAllocation("Alice-Realm", seasonId))
    local rows = dibs.RankRules.GetAllocationReconciliation(seasonId)
    local byName = {}
    for _, row in ipairs(rows) do byName[row.playerName] = row end

    assert_equal(5, byName["Tester-Realm"].expectedAllocation)
    assert_equal(1, byName["Tester-Realm"].assignedAllocation)
    assert_equal(4, byName["Tester-Realm"].missingAllocation)
    assert_equal("MISSING", byName["Tester-Realm"].status)
    assert_equal(1, byName["Alice-Realm"].assignedAllocation)
    assert_equal(0, byName["Alice-Realm"].missingAllocation)
    assert_equal(3, byName["Bob-Realm"].expectedAllocation)
    assert_equal(3, byName["Bob-Realm"].missingAllocation)
  end)

  it("uses the shared cached history summary across a large roster", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm" },
      guildRankIndices = { [1] = 0, [2] = 4, [3] = 4 },
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 4, "Member", 2)
    local members = {}
    for index = 1, 60 do
      members[index] = { playerName = "Member" .. index .. "-Realm", rankIndex = 4, rankName = "Member" }
    end

    local originalSummary = dibs.Ledger.GetPlayerHistorySummary
    local originalState = dibs.Ledger.GetPlayerState
    local originalBalance = dibs.Ledger.GetBalance
    local summaryCalls, slowReads = 0, 0
    dibs.Ledger.GetPlayerHistorySummary = function(...)
      summaryCalls = summaryCalls + 1
      return originalSummary(...)
    end
    dibs.Ledger.GetPlayerState = function(...) slowReads = slowReads + 1; return originalState(...) end
    dibs.Ledger.GetBalance = function(...) slowReads = slowReads + 1; return originalBalance(...) end

    local rows = dibs.RankRules.GetAllocationReconciliation(seasonId, members)
    dibs.Ledger.GetPlayerHistorySummary = originalSummary
    dibs.Ledger.GetPlayerState = originalState
    dibs.Ledger.GetBalance = originalBalance

    assert_equal(60, #rows)
    assert_equal(60, summaryCalls)
    assert_equal(0, slowReads)
    assert_equal(2, rows[1].missingAllocation)
  end)

  it("reads lightweight roster allocations in one ledger batch", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm" },
      guildRankIndices = { [1] = 0, [2] = 4, [3] = 4 },
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 4, "Member", 2)
    local members = {
      { playerName = "Alice-Realm", rankIndex = 4, rankName = "Member" },
      { playerName = "Bob-Realm", rankIndex = 4, rankName = "Member" },
    }
    dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Existing allocation", {
      action = "rank.reconcile", actor = "Tester-Realm",
    })
    assert_equal(1, dibs.Ledger.GetPlayerAllocation("Alice-Realm", seasonId))
    local bulkCheck = dibs.Ledger.GetPlayerAllocations(members, seasonId)
    local aliceKey = dibs.Identity.CanonicalMemberKey("Alice-Realm")
    assert_equal(1, bulkCheck[aliceKey], "bulk key " .. tostring(aliceKey))

    local originalBatch = dibs.Ledger.GetPlayerAllocations
    local batchCalls = 0
    dibs.Ledger.GetPlayerAllocations = function(...)
      batchCalls = batchCalls + 1
      return originalBatch(...)
    end
    local originalSingle = dibs.Ledger.GetPlayerAllocation
    dibs.Ledger.GetPlayerAllocation = function() error("unexpected per-member allocation read") end

    local ok, rows = pcall(dibs.RankRules.GetAllocationReconciliation, seasonId, members, { includeBalance = false })

    dibs.Ledger.GetPlayerAllocations = originalBatch
    dibs.Ledger.GetPlayerAllocation = originalSingle
    assert_true(ok, tostring(rows))
    assert_equal(1, batchCalls)
    assert_equal(2, #rows)
    local byName = {}
    for _, row in ipairs(rows) do byName[row.playerName] = row end
    assert_equal(1, byName["Alice-Realm"].assignedAllocation)
    assert_equal(1, byName["Alice-Realm"].missingAllocation)
    assert_equal(0, byName["Bob-Realm"].assignedAllocation)
    assert_equal(2, byName["Bob-Realm"].missingAllocation)
  end)

  it("rolls up rank counts without reading each member history", function()
    local members = { "Tester-Realm" }
    local ranksByIndex = { [1] = 0 }
    for index = 1, 60 do
      members[#members + 1] = "Member" .. index .. "-Realm"
      ranksByIndex[index + 1] = 4
    end
    local _, dibs = loader.load({ wow = {
      guildLeader = true, guildMembers = members, guildRankIndices = ranksByIndex,
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 4, "Member", 2)
    local originalSummary, summaryCalls = dibs.Ledger.GetPlayerHistorySummary, 0
    dibs.Ledger.GetPlayerHistorySummary = function(...)
      summaryCalls = summaryCalls + 1
      return originalSummary(...)
    end

    local rows = dibs.RankRules.GetRankConfigurationSummary(seasonId)
    dibs.Ledger.GetPlayerHistorySummary = originalSummary
    local memberRank
    for _, row in ipairs(rows) do if row.rankIndex == 4 then memberRank = row end end

    assert_equal(0, summaryCalls)
    assert_not_nil(memberRank)
    assert_equal(60, memberRank.pendingReconciliation)
  end)

  it("builds dashboard transaction diagnostics without copying the full transaction list", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local before = #dibs.Ledger.GetAllTransactions()
    local diagnostics = dibs.Ledger.GetTransactionDiagnostics()
    assert_equal(before, diagnostics.transactionCount)

    local originalGetAll = dibs.Ledger.GetAllTransactions
    dibs.Ledger.GetAllTransactions = function() error("unexpected full transaction copy") end
    local ok, statusText = pcall(dibs.OfficerUI.BuildStatusText)
    dibs.Ledger.GetAllTransactions = originalGetAll

    assert_true(ok, tostring(statusText))
    assert_true(statusText:find("Ledger transactions (all seasons): " .. tostring(before), 1, true) ~= nil)
    local result = dibs.ProtectedActions.Execute("ledger.grant", nil, {
      playerName = "Tester-Realm", amount = 1, reason = "Dashboard cache invalidation",
    })
    assert_true(result.ok, tostring(result.diagnostic))
    assert_equal(before + 1, dibs.Ledger.GetTransactionDiagnostics().transactionCount)
  end)

  it("grants only the missing delta and remains idempotent after a rank increase", function()
    local dibs = activateV2({
      guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, seasonId, 3, "Member", 1)
    local first = dibs.RankRules.GetAllocationReconciliation(seasonId)
    local alice = first[2].playerName == "Alice-Realm" and first[2] or first[1]
    local grant = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = alice.playerName,
      seasonId = seasonId,
      amount = alice.missingAllocation,
      reason = "Initial rank reconciliation",
    })

    assert_true(grant.ok)
    assert_equal(1, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
    assert_equal(0, dibs.RankRules.GetAllocationReconciliation(seasonId)[1].missingAllocation)

    setRule(dibs, seasonId, 3, "Member", 3)
    local increased = dibs.RankRules.GetAllocationReconciliation(seasonId)
    local updated = increased[1].playerName == "Alice-Realm" and increased[1] or increased[2]
    assert_equal(2, updated.missingAllocation)
    local second = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = "Alice-Realm", seasonId = seasonId, amount = 2, reason = "Rank increase reconciliation",
    })
    assert_true(second.ok)
    assert_equal(3, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
  end)

  it("keeps an existing allocation as surplus when a member rank decreases", function()
    local dibs = activateV2({ guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 } })
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, seasonId, 3, "Member", 1)
    local reconciliation = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = "Alice-Realm", seasonId = seasonId, amount = 1, reason = "Initial allocation",
    })
    assert_true(reconciliation.ok, tostring(reconciliation.diagnostic))
    setRule(dibs, seasonId, 3, "Member", 0)

    local rows = dibs.RankRules.GetAllocationReconciliation(seasonId)
    local alice = rows[1].playerName == "Alice-Realm" and rows[1] or rows[2]
    assert_equal(0, alice.missingAllocation)
    assert_equal(1, alice.surplusAllocation)
    assert_equal(-1, alice.difference)
    assert_equal("KEEP_GRANTED", alice.behavior)
    assert_equal("SURPLUS", alice.status)
  end)

  it("excludes disabled ranks from reconciliation without changing existing allocations", function()
    local dibs = activateV2({
      guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, seasonId, 0, "Guild Master", 1)
    setRule(dibs, seasonId, 3, "Member", 3)
    dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Existing allocation", {
      action = "rank.reconcile", actor = "Tester-Realm",
    })
    assert_equal(1, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)

    setRule(dibs, seasonId, 3, "Member", 3, false)
    assert_equal(false, dibs.RankRules.GetRankAllocation(seasonId, 3).enabled)
    assert_equal(0, dibs.RankRules.GetAllocationForRank(seasonId, 3))
    local rows = dibs.RankRules.GetAllocationReconciliation(seasonId)
    assert_equal(1, #rows)
    assert_equal("Tester-Realm", rows[1].playerName)

    local summary = dibs.RankRules.GetRankConfigurationSummary(seasonId)
    assert_equal("OPTIONAL", summary[2].status)
    assert_equal(false, summary[2].enabled)
    assert_equal(0, summary[2].pendingReconciliation)

    setRule(dibs, seasonId, 3, "Member", 4)
    assert_equal(false, dibs.RankRules.GetRankAllocation(seasonId, 3).enabled)
    assert_equal(0, dibs.RankRules.GetAllocationForRank(seasonId, 3))
    assert_equal(1, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
  end)

  it("keeps valid rank configuration ready when a member needs a top-up", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 } } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 0, "Guild Master", 2)
    dibs.RankRules.SetAllocation(seasonId, 3, "Member", 2)
    dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Existing allocation", {
      action = "rank.reconcile", actor = "Tester-Realm",
    })

    local summary = dibs.RankRules.GetRankConfigurationSummary(seasonId)
    local memberRule
    for _, row in ipairs(summary) do
      if row.rankIndex == 3 then memberRule = row end
    end

    assert_equal("READY", memberRule.status)
    assert_equal(1, memberRule.pendingReconciliation)
  end)
end)
