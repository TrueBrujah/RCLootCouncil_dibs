local H = require("helpers.season_activation")
describe("seasonal allocation drift", function()
  it("appends signed adjustments without resetting spent balance and supports exact replay", function()
    local dibs, id = H.make()
    H.activate(dibs, id)
    local used = dibs.Ledger.CommitDibUse(nil, { transactionId = "spent-before-drift", playerName = H.members[1],
      seasonId = id, amount = 1, source = "test" })
    assert_true(used.accepted, used.reasonCode)
    local manifestHash = dibs.SeasonalRoster.GetActivationManifest(id).contentHash
    local revision = dibs.SeasonalRoster.GetCurrentRevision(id)
    dibs.GetDB().rankRules[id]["0"].allocation = 5
    local published = dibs.SeasonalRoster.PublishRankAllocations(id, revision,
      "drift-new-config", "Reviewed allocation update", H.members[1])
    assert_true(published.ok, published.code)
    local preview = assert(dibs.SeasonalRoster.PreviewSeasonReconciliation(id, H.members[1]))
    assert_true(preview.ready)
    assert_equal(2, preview.rows[1].delta)
    local expected = { seasonId = id, seasonRevision = preview.seasonRevision,
      rosterRevision = preview.rosterRevision, sourceLedgerRevision = preview.sourceLedgerRevision }
    local result = dibs.SeasonalRoster.ApplySeasonReconciliation(H.members[1], preview.previewId,
      expected, "apply-drift", "Apply reviewed rank drift", true)
    assert_true(result.ok, result.code)
    assert_equal(5, dibs.Ledger.GetPlayerAllocation(H.members[1], id))
    assert_equal(4, dibs.Ledger.GetBalance(H.members[1], id))
    assert_equal(manifestHash, dibs.SeasonalRoster.GetActivationManifest(id).contentHash)
    assert_true(dibs.SeasonalRoster.ApplySeasonReconciliation(H.members[1], preview.previewId,
      expected, "apply-drift", "Apply reviewed rank drift", true).idempotent)
    dibs.GetDB().rankRules[id]["0"].allocation = 2
    assert_true(dibs.SeasonalRoster.PublishRankAllocations(id, published.revision,
      "drift-reduce", "Reduced rank allocation", H.members[1]).ok)
    local reduced = dibs.SeasonalRoster.PreviewSeasonReconciliation(id, H.members[1])
    expected.seasonRevision, expected.sourceLedgerRevision = reduced.seasonRevision, reduced.sourceLedgerRevision
    assert_true(dibs.SeasonalRoster.ApplySeasonReconciliation(H.members[1], reduced.previewId,
      expected, "apply-negative-drift", "Apply negative drift", true).ok)
    assert_equal(1, dibs.Ledger.GetBalance(H.members[1], id))
  end)
  it("refuses stale ledger previews", function()
    local dibs, id = H.make()
    H.activate(dibs, id)
    local preview = dibs.SeasonalRoster.PreviewSeasonReconciliation(id, H.members[1])
    assert_true(dibs.Ledger.CommitDibUse(nil, { transactionId = "stale-spend", playerName = H.members[1],
      seasonId = id, amount = 1, source = "test" }).accepted)
    local result = dibs.SeasonalRoster.ApplySeasonReconciliation(H.members[1], preview.previewId,
      { seasonId = id, seasonRevision = preview.seasonRevision, rosterRevision = preview.rosterRevision,
        sourceLedgerRevision = preview.sourceLedgerRevision }, "stale-apply", "Stale preview", true)
    assert_false(result.ok); assert_equal("STALE_RECONCILIATION_PREVIEW", result.code)
  end)
end)
