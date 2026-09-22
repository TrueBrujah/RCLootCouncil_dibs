local loader = require("helpers.load_addon")

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

  it("grants only the missing delta and remains idempotent after a rank increase", function()
    local _, dibs = loader.load({
      wow = {
        guildLeader = true,
        guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 },
      },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 3, "Member", 1)
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

    dibs.RankRules.SetAllocation(seasonId, 3, "Member", 3)
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
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 } } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 3, "Member", 1)
    dibs.ProtectedActions.Execute("rank.reconcile", nil, { playerName = "Alice-Realm", seasonId = seasonId, amount = 1, reason = "Initial allocation" })
    dibs.RankRules.SetAllocation(seasonId, 3, "Member", 0)

    local rows = dibs.RankRules.GetAllocationReconciliation(seasonId)
    local alice = rows[1].playerName == "Alice-Realm" and rows[1] or rows[2]
    assert_equal(0, alice.missingAllocation)
    assert_equal(1, alice.surplusAllocation)
    assert_equal("SURPLUS", alice.status)
  end)
end)
