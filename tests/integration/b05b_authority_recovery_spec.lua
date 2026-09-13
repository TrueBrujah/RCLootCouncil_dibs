local loader = require("helpers.load_addon")

local function load()
  return select(2, loader.load({ withAce3 = true, wow = {
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Coordinator-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 1, [4] = 3 },
  } }))
end

local function baseline(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "B05b governance" }))
  local value, reason = dibs.LegacyBaseline.FinalizeBaseline(nil)
  assert_not_nil(value, tostring(reason))
  return value
end

local function authority(dibs, coordinator, epoch, transition)
  local member = assert(dibs.Identity.CreateSnapshot(coordinator))
  return { schema = 1, state = "ACTIVE", coordinator = member, ledgerEpoch = epoch, transition = transition }
end

local function activate(dibs)
  local approved = baseline(dibs)
  local record, reason = dibs.Governance.Change(nil, { future = { authority = authority(dibs, "Coordinator-Realm", 7, {
    kind = "INITIAL", baselineHash = approved.legacyBaselineHash,
  }) } })
  assert_true(record, tostring(reason))
  return approved
end

describe("B05b fenced authority and recovery", function()
  it("persists ACTIVE authority only through an explicit GM governance change", function()
    local dibs = load(); activate(dibs)
    local state = dibs.Governance.GetAuthorityState()
    assert_equal("ACTIVE", state.state); assert_equal(7, state.ledgerEpoch)
    assert_equal("coordinator-realm", state.coordinator.memberKey)
    assert_equal("INITIAL", state.transition.kind)
  end)

  it("requires the active coordinator closure and exact parent tuple for normal handoff", function()
    local dibs = load(); activate(dibs)
    assert_nil(dibs.Governance.BeginHandoff("Officer-Realm", { finalSeq = 2, rootHash = "root-7" }))
    local closure = assert(dibs.Governance.BeginHandoff("Coordinator-Realm", { finalSeq = 2, rootHash = "root-7" }))
    assert_equal("HANDOFF_CLOSING", dibs.Governance.GetAuthorityState().state)
    local wrong = authority(dibs, "Officer-Realm", 8, { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = "wrong" })
    assert_false(dibs.Governance.Change(nil, { future = { authority = wrong } }))
    local next = authority(dibs, "Officer-Realm", 8, { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash })
    assert_true(dibs.Governance.Change(nil, { future = { authority = next } }))
    assert_equal("ACTIVE", dibs.Governance.GetAuthorityState().state)
    assert_equal(8, dibs.Governance.GetAuthorityState().ledgerEpoch)
  end)

  it("fails closed during coordinator loss and records a zero-effect proposal", function()
    local dibs = load(); activate(dibs)
    assert_not_nil(dibs.Seasons.Create("B05b")); local season = dibs.GetCurrentSeasonId()
    assert_not_nil(dibs.Ledger.Grant("Player-Realm", 2, "setup", "test", season))
    local before = dibs.Ledger.GetBalance("Player-Realm", season)
    assert_not_nil(dibs.Governance.MarkCoordinatorUnavailable(nil, "disconnect"))
    local tx, reason = dibs.Ledger.Use("Player-Realm", 1, "award", "test", season)
    assert_nil(tx); assert_equal("COORDINATOR_UNAVAILABLE", reason)
    assert_equal(before, dibs.Ledger.GetBalance("Player-Realm", season))
    local proposals = dibs.Governance.GetAwardProposals()
    assert_equal(1, #proposals); assert_equal("PENDING_RECONCILIATION", proposals[1].status)
  end)

  it("requires the current GM and B05a baseline for forced recovery", function()
    local dibs = load(); local approved = activate(dibs)
    assert_nil(dibs.Governance.EnterRecoveryPending("Officer-Realm", "lost"))
    assert_not_nil(dibs.Governance.EnterRecoveryPending(nil, "lost"))
    local absent = authority(dibs, "Officer-Realm", 8, { kind = "FORCED_RECOVERY", baselineHash = "wrong", recoveryAudit = { reason = "lost" } })
    assert_false(dibs.Governance.Change(nil, { future = { authority = absent } }))
    local recovered = authority(dibs, "Officer-Realm", 8, { kind = "FORCED_RECOVERY", baselineHash = approved.legacyBaselineHash, recoveryAudit = { reason = "lost" } })
    assert_true(dibs.Governance.Change(nil, { future = { authority = recovered } }))
    assert_equal("ACTIVE", dibs.Governance.GetAuthorityState().state)
  end)

  it("keeps B05a review state distinct and classifies excluded late evidence as orphaned", function()
    local dibs = load(); local approved = activate(dibs)
    assert_not_nil(dibs.Governance.EnterRecoveryPending(nil, "lost"))
    local recovered = authority(dibs, "Officer-Realm", 8, { kind = "FORCED_RECOVERY", baselineHash = approved.legacyBaselineHash, recoveryAudit = { reason = "lost" } })
    assert_true(dibs.Governance.Change(nil, { future = { authority = recovered } }))
    assert_false(dibs.Governance.ClassifyLateEvidence({ eventId = "late-7-2", epoch = 7, seq = 2 }))
    assert_equal("ORPHANED_EVIDENCE", select(2, dibs.Governance.ClassifyLateEvidence({ eventId = "late-7-2", epoch = 7, seq = 2 })))
    assert_equal("BASELINE_APPROVED", dibs.LegacyBaseline.GetState().status)
    assert_true(dibs.Governance.GetAuthorityState().state ~= "RECOVERY_PENDING_REVIEW")
  end)

  it("blocks authority activation while SYNC_BEHIND and rejects evidence beyond a closed sequence", function()
    local dibs = load(); local approved = baseline(dibs)
    dibs.Sync.MarkSyncBehind("test-gap")
    local blocked, reason = dibs.Governance.Change(nil, { future = { authority = authority(dibs, "Coordinator-Realm", 7, {
      kind = "INITIAL", baselineHash = approved.legacyBaselineHash,
    }) } })
    assert_false(blocked); assert_equal("SYNC_BEHIND", reason)
    dibs.Sync.ClearSyncBehind()
    local activated = authority(dibs, "Coordinator-Realm", 7, { kind = "INITIAL", baselineHash = approved.legacyBaselineHash })
    assert_true(dibs.Governance.Change(nil, { future = { authority = activated } }))
    assert_not_nil(dibs.Governance.BeginHandoff("Coordinator-Realm", { finalSeq = 1, rootHash = "root" }))
    assert_false(dibs.Governance.ClassifyLateEvidence({ eventId = "future", epoch = 7, seq = 2 }))
    assert_equal("EVENT_BEYOND_CLOSED_FINAL_SEQ", select(2, dibs.Governance.ClassifyLateEvidence({ eventId = "future", epoch = 7, seq = 2 })))
  end)

  it("preserves fenced states across reload without inferring a new coordinator", function()
    local dibs = load(); activate(dibs)
    assert_not_nil(dibs.Governance.BeginHandoff("Coordinator-Realm", { finalSeq = 0, rootHash = "root" }))
    local saved = _G.RCLootCouncil_dibsDB
    local reloaded = select(2, loader.load({ savedVariables = saved, withAce3 = true, wow = {
      guildLeader = true, guildMembers = { "Tester-Realm", "Coordinator-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 1, [4] = 3 },
    } }))
    assert_equal("HANDOFF_CLOSING", reloaded.Governance.GetAuthorityState().state)
    assert_equal("coordinator-realm", reloaded.Governance.GetAuthorityState().coordinator.memberKey)
  end)
end)
