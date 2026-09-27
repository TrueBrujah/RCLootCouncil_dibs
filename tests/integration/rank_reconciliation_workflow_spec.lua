local loader = require("helpers.load_addon")

local DEFAULT_WOW = {
  playerName = "Tester-Realm",
  guildLeader = true,
  guildMembers = { "Tester-Realm", "Officer-Realm", "Alice-Realm", "Bob-Realm" },
  guildRankIndices = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 },
}

local function setup(wow, enableV2)
  local options = {}
  for key, value in pairs(DEFAULT_WOW) do options[key] = value end
  for key, value in pairs(wow or {}) do options[key] = value end
  local _, dibs = loader.load({ wow = options })
  if enableV2 ~= false then
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "rank reconciliation workflow test" }))
    local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
    local coordinator = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
    assert_true(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 1,
      transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
    } } }))
    assert_true(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
  end
  return dibs
end

local function setRule(dibs, rankIndex, allocation, rankName)
  local result = dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = dibs.GetCurrentSeasonId(), rankIndex = rankIndex,
    rankName = rankName or (rankIndex == 0 and "Guild Master" or (rankIndex == 1 and "Officer" or "Member")),
    allocation = allocation,
  })
  assert_true(result.ok, tostring(result.diagnostic))
end

local function rowFor(dibs, seasonId, playerName)
  for _, row in ipairs(dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId).rows) do
    if row.plainPlayerName == playerName then return row end
  end
  error("Missing reconciliation row for " .. playerName)
end

local function reconcile(dibs, row, reason, actor)
  return dibs.OfficerUI.ReconcileRankAllocation(row, reason, actor)
end

local function propose(dibs, row)
  local preview = row.reconciliationSnapshot
  local requester = assert(dibs.Identity.CreateSnapshot("Officer-Realm"))
  local reconciliation = {
    schema = 1, targetMemberKey = preview.targetMemberKey, seasonId = preview.seasonId,
    currentSeasonId = preview.currentSeasonId, requestedBySnapshot = requester,
    assignedBefore = preview.assignedBefore, expectedAllocation = preview.expectedAllocation,
    currentRankIndex = preview.currentRankIndex, currentRankName = preview.currentRankName,
    seasonCatalogRevision = preview.seasonCatalogRevision, seasonCatalogHash = preview.seasonCatalogHash,
    governanceRevision = preview.governanceRevision, operationalPolicyRevision = preview.operationalPolicyRevision,
    reconciliationMode = "MANUAL", trigger = "MANUAL_RECONCILIATION",
    authorityEpoch = preview.authorityEpoch, coordinatorMemberKey = preview.coordinatorMemberKey,
    operationKey = preview.operationKey,
  }
  local _, _, result = dibs.Ledger.RegisterSeasonAllocation(row.plainPlayerName, row.seasonId,
    row.difference, "Officer review", {
      action = "rank.reconcile", actorName = "Officer-Realm", source = "rank_reconciliation",
      rankIndex = row.rankIndex, rankName = row.rankName, expectedAllocation = row.expected,
      reconciliation = reconciliation,
    })
  assert_not_nil(result and result.proposal)
  return result.proposal
end

describe("Rank allocation reconciliation workflow", function()
  it("uses a signed difference and marks only positive differences for confirmation", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    assert_equal(2, row.difference)
    assert_equal("REQUIRE_CONFIRMATION", dibs.RankRules.GetRankReconciliationBehavior(row.difference))
    assert_equal("Reconciliation required", row.action)
  end)

  it("binds the preview to identity, rank, catalog, governance, policy, and coordinator state", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    local snapshot = rowFor(dibs, seasonId, "Alice-Realm").reconciliationSnapshot
    for _, field in ipairs({ "targetMemberKey", "seasonId", "currentSeasonId", "currentRankIndex", "currentRankName",
      "expectedAllocation", "assignedBefore", "seasonCatalogRevision", "seasonCatalogHash", "governanceRevision",
      "operationalPolicyRevision", "authorityEpoch", "coordinatorMemberKey", "operationKey" }) do
      assert_not_nil(snapshot[field], "Missing snapshot field: " .. field)
    end
  end)

  it("commits exactly the missing positive amount through one canonical allocation transaction", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 3)
    dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Existing allocation", {
      action = "rank.reconcile", actor = "Tester-Realm", source = "test_fixture",
    })
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local before = dibs.Ledger.GetCanonicalState()
    local result = reconcile(dibs, row, "Initial top-up")
    local after = dibs.Ledger.GetCanonicalState()
    assert_true(result.ok, tostring(result.diagnostic))
    assert_equal("COMMITTED", result.outcome)
    assert_equal(2, result.value.transaction.amount)
    assert_equal("SEASON_ALLOCATION", result.value.transaction.type)
    assert_equal(before.commitCount + 1, after.commitCount)
    assert_equal(3, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
  end)

  it("requires a nonblank reason and makes no ledger change when absent", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local missingReason = reconcile(dibs, row, nil)
    assert_false(missingReason.ok)
    assert_equal("REASON_REQUIRED", missingReason.reasonCode)
    for _, reason in ipairs({ "", "   \t " }) do
      local result = reconcile(dibs, row, reason)
      assert_false(result.ok)
      assert_equal("REASON_REQUIRED", result.reasonCode)
    end
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("trims the recorded reason at the authoritative transaction boundary", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local result = reconcile(dibs, rowFor(dibs, seasonId, "Alice-Realm"), "  Promotion  ")
    assert_true(result.ok)
    assert_equal("Promotion", result.value.transaction.reason)
  end)

  it("rejects a caller-supplied amount that differs from the fresh positive delta", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local result = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = "Alice-Realm", seasonId = seasonId, amount = 1, reason = "Incorrect amount",
    })
    assert_false(result.ok)
    assert_equal("INVALID_ALLOCATION_DELTA", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("rejects a target that cannot be resolved to a unique guild member", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local result = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = "Not-In-Guild-Realm", seasonId = seasonId, amount = 1, reason = "Unknown target",
    })
    assert_false(result.ok)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("rejects an old preview after the published rank allocation changes", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    setRule(dibs, 3, 2)
    local result = reconcile(dibs, row, "Old preview")
    assert_false(result.ok)
    assert_equal("STALE_PREVIEW", result.reasonCode)
  end)

  it("rejects an old preview after another canonical allocation changes assigned-before", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local first = reconcile(dibs, row, "First confirmation")
    assert_true(first.ok)
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local retry = reconcile(dibs, row, "Stale confirmation")
    assert_false(retry.ok)
    assert_equal("STALE_PREVIEW", retry.reasonCode)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("rejects an old preview after the target changes guild rank", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local getRosterInfo = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(index)
      if index == 3 then return "Alice-Realm", "Officer", 1 end
      return getRosterInfo(index)
    end
    local result = reconcile(dibs, row, "Old rank preview")
    assert_false(result.ok)
    assert_equal("STALE_PREVIEW", result.reasonCode)
  end)

  it("rejects reconciliation for a season other than the current season", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local result = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = "Alice-Realm", seasonId = seasonId .. "-old", amount = 1, reason = "Old season",
    })
    assert_false(result.ok)
    assert_equal("STALE_SEASON", result.reasonCode)
  end)

  it("keeps previously granted allocations when a member is demoted", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    assert_true(reconcile(dibs, rowFor(dibs, seasonId, "Alice-Realm"), "Initial allocation").ok)
    setRule(dibs, 3, 0)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local result = reconcile(dibs, row, "No clawback")
    assert_equal(-2, row.difference)
    assert_equal("KEEP_GRANTED", dibs.RankRules.GetRankReconciliationBehavior(row.difference))
    assert_false(result.ok)
    assert_equal("POSITIVE_DELTA_REQUIRED", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
    assert_equal(2, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
  end)

  it("does not create debt or claw back spent Dibs after demotion", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    assert_true(reconcile(dibs, rowFor(dibs, seasonId, "Alice-Realm"), "Starting allocation").ok)
    local spend = dibs.Ledger.CommitDibUse({ action = "ledger.use", actor = "Tester-Realm" }, {
      playerName = "Alice-Realm", amount = 1, reason = "Spent before demotion",
      source = "test", seasonId = seasonId, awardRef = "spent-before-demotion",
    })
    assert_true(spend.accepted, tostring(spend.reasonCode))
    setRule(dibs, 3, 0)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local before = dibs.Ledger.GetCanonicalState().commitCount
    assert_equal(-1, row.difference)
    assert_equal("KEEP_GRANTED", dibs.RankRules.GetRankReconciliationBehavior(row.difference))
    assert_equal(0, dibs.Ledger.GetBalance("Alice-Realm", seasonId))
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
    assert_equal(1, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
  end)

  it("includes reconciliation metadata in the canonical transaction hash", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local result = reconcile(dibs, rowFor(dibs, seasonId, "Alice-Realm"), "Audited allocation")
    assert_true(result.ok)
    local transaction = result.value.transaction
    assert_equal("MANUAL_RECONCILIATION", transaction.reconciliation.trigger)
    assert_equal(transaction.reconciliation.operationKey, transaction.transactionId:match("rank%-reconcile%-1%-(.+)"))
    assert_equal(transaction.canonicalContentHash, dibs.Ledger.GetCanonicalCommit(1, 1).transactionHash)
    assert_equal(0, transaction.reconciliation.assignedBefore)
    assert_equal(1, transaction.reconciliation.expectedAllocation)
    assert_equal(assert(dibs.Identity.CreateSnapshot("Tester-Realm")).memberKey, transaction.reconciliation.coordinatorMemberKey)
  end)

  it("fails closed while the local ledger is behind", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    dibs.Sync.MarkSyncBehind("TEST_GAP")
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    assert_nil(row.reconciliationSnapshot)
    assert_equal("SYNC_BEHIND", row.blockedReason)
  end)

  it("fails closed when V2 governance is not enforced", function()
    local dibs = setup(nil, false)
    local result = dibs.ProtectedActions.Execute("rank.reconcile", nil, {
      playerName = "Alice-Realm", amount = 1, reason = "Legacy authority",
    })
    assert_false(result.ok)
    assert_equal("V2_ENFORCED_REQUIRED", result.reasonCode)
  end)

  it("denies reconciliation requested by a non-officer", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local result = dibs.ProtectedActions.Execute("rank.reconcile", "Alice-Realm", {
      playerName = "Bob-Realm", seasonId = seasonId, amount = 1, reason = "Unauthorized",
    })
    assert_false(result.ok)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("records a non-coordinator request as a proposal with hashed reconciliation metadata", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local proposal = propose(dibs, rowFor(dibs, seasonId, "Alice-Realm"))
    assert_equal("PENDING_RECONCILIATION", proposal.status)
    assert_equal("MANUAL_RECONCILIATION", proposal.reconciliation.trigger)
    assert_not_nil(proposal.reconciliation.operationKey)
    assert_not_nil(proposal.contentHash)
  end)

  it("reuses the existing pending proposal for a duplicate reconciliation operation", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local row = rowFor(dibs, seasonId, "Alice-Realm")
    local first = propose(dibs, row)
    local second = propose(dibs, row)
    assert_equal(first.proposalId, second.proposalId)
    assert_equal(1, #dibs.Governance.GetAwardProposals())
  end)

  it("revalidates a relayed proposal at the coordinator and terminally marks a stale rank", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local proposal = propose(dibs, rowFor(dibs, seasonId, "Alice-Realm"))
    local getRosterInfo = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(index)
      if index == 3 then return "Alice-Realm", "Officer", 1 end
      return getRosterInfo(index)
    end
    local result = dibs.Ledger.CommitAwardProposal({ actor = "Tester-Realm" }, proposal.proposalId, {})
    assert_false(result.accepted)
    assert_equal("STALE_RANK", result.reasonCode)
    assert_equal("STALE", dibs.Governance.GetAwardProposals()[1].status)
    assert_equal(0, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("revalidates catalog state at the coordinator before committing a proposal", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local proposal = propose(dibs, rowFor(dibs, seasonId, "Alice-Realm"))
    setRule(dibs, 2, 1)
    local result = dibs.Ledger.CommitAwardProposal({ actor = "Tester-Realm" }, proposal.proposalId, {})
    assert_false(result.accepted)
    assert_equal("STALE_CATALOG", result.reasonCode)
    assert_equal("STALE", dibs.Governance.GetAwardProposals()[1].status)
    assert_equal(0, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("rejects a proposal when assigned-before changes before coordinator commit", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 2)
    local proposal = propose(dibs, rowFor(dibs, seasonId, "Alice-Realm"))
    local allocation, reasonCode, command = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1,
      "Independent allocation", { action = "rank.reconcile", actorName = "Tester-Realm", source = "test_fixture" })
    assert_not_nil(allocation)
    assert_equal("CANONICAL_COMMITTED", reasonCode)
    assert_true(command.accepted)
    local result = dibs.Ledger.CommitAwardProposal({ actor = "Tester-Realm" }, proposal.proposalId, {})
    assert_false(result.accepted)
    assert_equal("STALE_ASSIGNMENT", result.reasonCode)
    assert_equal("STALE", dibs.Governance.GetAwardProposals()[1].status)
  end)

  it("rejects a proposal when its season is no longer active", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local proposal = propose(dibs, rowFor(dibs, seasonId, "Alice-Realm"))
    local getCurrentSeasonId = dibs.GetCurrentSeasonId
    dibs.GetCurrentSeasonId = function() return seasonId .. "-next" end
    local result = dibs.Ledger.CommitAwardProposal({ actor = "Tester-Realm" }, proposal.proposalId, {})
    dibs.GetCurrentSeasonId = getCurrentSeasonId
    assert_false(result.accepted)
    assert_equal("STALE_SEASON", result.reasonCode)
    assert_equal("STALE", dibs.Governance.GetAwardProposals()[1].status)
  end)

  it("rejects a pending proposal after its requester loses the officer role", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    local proposal = propose(dibs, rowFor(dibs, seasonId, "Alice-Realm"))
    local getRosterInfo = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(index)
      if index == 2 then return "Officer-Realm", "Member", 3 end
      return getRosterInfo(index)
    end
    local result = dibs.Ledger.CommitAwardProposal({ actor = "Tester-Realm" }, proposal.proposalId, {})
    assert_false(result.accepted)
    assert_equal("REQUESTER_AUTHORITY_CHANGED", result.reasonCode)
    assert_equal("REJECTED", dibs.Governance.GetAwardProposals()[1].status)
  end)

  it("commits independent Reconcile All rows and reports stale rows without aborting", function()
    local dibs = setup({
      guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm" },
      guildRankIndices = { [1] = 0, [2] = 3, [3] = 2 },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 0, 0)
    setRule(dibs, 3, 1)
    setRule(dibs, 2, 1)
    local rows = dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId).rows
    local getRosterInfo = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(index)
      if index == 3 then return "Bob-Realm", "Other Member", 4 end
      return getRosterInfo(index)
    end
    local report = dibs.OfficerUI.ReconcileAllAllocations(seasonId, "Bulk reconciliation", rows)
    assert_equal(1, report.succeeded)
    assert_equal(1, report.stale)
    assert_equal(1, report.skipped)
    assert_equal(1, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
    assert_equal(0, dibs.Ledger.GetPlayerState("Bob-Realm", seasonId).allocation)
  end)

  it("reports each failed Reconcile All row and continues processing", function()
    local dibs = setup({ guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm" },
      guildRankIndices = { [1] = 0, [2] = 3, [3] = 3 } })
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 0, 0)
    setRule(dibs, 3, 1)
    local rows = dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId).rows
    local report = dibs.OfficerUI.ReconcileAllAllocations(seasonId, "", rows)
    assert_equal(2, report.failed)
    assert_equal(0, report.succeeded)
    assert_equal(3, #report.results)
  end)

  it("reports a surplus as skipped and never writes a negative adjustment", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    setRule(dibs, 3, 1)
    assert_true(reconcile(dibs, rowFor(dibs, seasonId, "Alice-Realm"), "Initial allocation").ok)
    setRule(dibs, 3, 0)
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local report = dibs.OfficerUI.ReconcileAllAllocations(seasonId, "Demotion", { rowFor(dibs, seasonId, "Alice-Realm") })
    assert_equal(1, report.skipped)
    assert_equal("KEEP_GRANTED", report.results[1].reasonCode)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
    assert_equal(1, dibs.Ledger.GetPlayerState("Alice-Realm", seasonId).allocation)
  end)
end)