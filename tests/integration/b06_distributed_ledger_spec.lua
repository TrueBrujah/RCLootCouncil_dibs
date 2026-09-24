local loader = require("helpers.load_addon")

local roster = { "Coordinator-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "Coordinator-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function activateV2()
  local dibs = load("Coordinator-Realm")
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "B06 governance" }))
  local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Coordinator-Realm"))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 7,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { "Coordinator-Realm" }))
  assert_true(dibs.Governance.IsV2Enforced())
  assert_equal("V2_ENFORCED", dibs.Sync.GetProtocolState())
  assert_not_nil(dibs.Seasons.Create("B06"))
  assert_not_nil(dibs.Ledger.Grant("Player-Realm", 1, "B06 setup", "test", dibs.GetCurrentSeasonId()))
  return dibs
end

describe("B06 coordinator distributed ledger", function()
  it("allows only the active local coordinator to create one ordered AWARD_COMMIT", function()
    local dibs = activateV2(); local season = dibs.GetCurrentSeasonId()
    local commit = dibs.Ledger.CommitDibUse(nil, { transactionId = "b06-1", proposalId = "proposal-1", playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 1, source = "b06" })
    assert_true(commit.accepted, tostring(commit.reasonCode)); assert_equal("CANONICAL_COMMITTED", commit.reasonCode)
    assert_equal(7, commit.value.ledgerEpoch); assert_equal(1, commit.value.sequence)
    assert_equal(commit.value.commitHash, dibs.Ledger.GetCanonicalState().rootHash)
    assert_equal(0, dibs.Ledger.GetBalance("Player-Realm", season))
    local replay = dibs.Ledger.CommitDibUse(nil, { transactionId = "b06-1", proposalId = "proposal-1", playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 1, source = "b06" })
    assert_true(replay.accepted); assert_true(replay.idempotentReplay)
    local unstable = dibs.Ledger.CommitDibUse(nil, { playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 2, source = "b06" })
    assert_false(unstable.accepted); assert_equal("STABLE_AWARD_ID_REQUIRED", unstable.reasonCode)
  end)

  it("keeps non-coordinator work as a zero-effect proposal after V2 cutover", function()
    local coordinator = activateV2(); local saved = coordinator.DeepCopy(_G.RCLootCouncil_dibsDB)
    local follower = load("Officer-Realm", saved); local before = follower.Ledger.GetBalance("Player-Realm", follower.GetCurrentSeasonId())
    local result = follower.Ledger.CommitDibUse(nil, { transactionId = "b06-officer", playerName = "Player-Realm", seasonId = follower.GetCurrentSeasonId(), amount = 1, itemID = 1, source = "b06" })
    assert_false(result.accepted); assert_equal("CURRENT_COORDINATOR_REQUIRED", result.reasonCode)
    assert_equal(before, follower.Ledger.GetBalance("Player-Realm", follower.GetCurrentSeasonId()))
    assert_equal("PENDING_RECONCILIATION", result.proposal.status)
  end)

  it("rejects a gap or competing canonical position before mutating follower state", function()
    local dibs = activateV2(); local season = dibs.GetCurrentSeasonId()
    local first = assert(dibs.Ledger.CommitDibUse(nil, { transactionId = "b06-first", playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 1, source = "b06" }).value)
    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB); saved.guilds["realm:testguild"].ledger.canonical.commits = {}; saved.guilds["realm:testguild"].ledger.canonical.positions = {}; saved.guilds["realm:testguild"].ledger.canonical.transactionIndex = {}; saved.guilds["realm:testguild"].ledger.canonical.nextSeq = 1; saved.guilds["realm:testguild"].ledger.canonical.rootHash = first.previousHash; saved.guilds["realm:testguild"].ledger.transactions[first.canonicalTransactionId] = nil
    local follower = load("Officer-Realm", saved)
    local gap = follower.DeepCopy(first); gap.sequence = 2; gap.commitHash = follower.Ledger.CalculateCanonicalCommitHash and follower.Ledger.CalculateCanonicalCommitHash(gap) or "bad"
    local before = #follower.Ledger.GetAllTransactions(); local applied = follower.Ledger.ApplyAwardCommit(gap, "Coordinator-Realm")
    assert_false(applied.accepted); assert_equal("SYNC_BEHIND", applied.reasonCode); assert_equal(before, #follower.Ledger.GetAllTransactions())
  end)

  it("applies a coordinator commit atomically once on a follower and rejects a wrong root", function()
    local coordinator = activateV2(); local beforeCommit = coordinator.DeepCopy(_G.RCLootCouncil_dibsDB); local season = coordinator.GetCurrentSeasonId()
    local commit = assert(coordinator.Ledger.CommitDibUse(nil, { transactionId = "b06-follower", playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 1, source = "b06" }).value)
    local follower = load("Officer-Realm", beforeCommit)
    local applied = follower.Ledger.ApplyAwardCommit(commit, "Coordinator-Realm")
    assert_true(applied.accepted, tostring(applied.reasonCode)); assert_equal(0, follower.Ledger.GetBalance("Player-Realm", season))
    assert_true(follower.Ledger.ApplyAwardCommit(commit, "Coordinator-Realm").idempotentReplay)
    local bad = follower.DeepCopy(commit); bad.sequence = 2; bad.previousHash = "wrong"; bad.commitHash = follower.Ledger.CalculateCanonicalCommitHash(bad)
    local count = #follower.Ledger.GetAllTransactions(); local rejected = follower.Ledger.ApplyAwardCommit(bad, "Coordinator-Realm")
    assert_false(rejected.accepted); assert_equal("PREVIOUS_HASH_MISMATCH", rejected.reasonCode); assert_equal(count, #follower.Ledger.GetAllTransactions())
  end)

  it("publishes follower ledger revision for peer synchronization status", function()
    local coordinator = activateV2()
    local saved = coordinator.DeepCopy(_G.RCLootCouncil_dibsDB)
    local follower = load("Officer-Realm", saved)
    local sentBefore = #follower.Ace3.libs.comm.sent

    follower.Sync.OnLifecycle("TEST")
    local digest
    for index = sentBefore + 1, #follower.Ace3.libs.comm.sent do
      local message = follower.Ace3.Deserialize(follower.Ace3.libs.comm.sent[index].payload)
      if message and message.type == "LEDGER_DIGEST" then digest = message end
    end
    assert_not_nil(digest)

    local envelope = assert(coordinator.Sync.BuildEnvelope(digest))
    envelope.senderNameRealm, envelope.senderMemberKey = "Officer-Realm", "officer-realm"
    local accepted, reason = coordinator.Sync.Receive(envelope, "Officer-Realm")
    assert_true(accepted, tostring(reason))
    assert_equal("LEDGER_STATUS_ONLY", reason)
    local peerLedgerRevision
    for _, peer in ipairs(coordinator.Sync.GetPeerStatuses()) do
      if peer.playerName == "Officer-Realm" then peerLedgerRevision = peer.ledgerRevision end
    end
    assert_equal(digest.lastSeq, peerLedgerRevision)
  end)

  it("requests a bounded batch when catching up multiple canonical commits", function()
    local coordinator = activateV2()
    local season = coordinator.GetCurrentSeasonId()
    assert_not_nil(coordinator.Ledger.Grant("Player-Realm", 2, "B06 batch top-up", "test", season))
    local saved = coordinator.DeepCopy(_G.RCLootCouncil_dibsDB)
    for sequence = 1, 3 do
      local commit = coordinator.Ledger.CommitDibUse(nil, {
        transactionId = "b06-batch-" .. tostring(sequence), playerName = "Player-Realm",
        seasonId = season, amount = 1, itemID = sequence, source = "b06-batch",
      })
      assert_true(commit.accepted, tostring(commit.reasonCode))
    end
    local digest = coordinator.Sync.BuildLedgerDigest()
    local envelope = assert(coordinator.Sync.BuildEnvelope(digest))
    local follower = load("Officer-Realm", saved)
    local accepted, reason = follower.Sync.Receive(envelope, "Coordinator-Realm")
    assert_true(accepted, tostring(reason))
    assert_equal("LEDGER_DETAIL_REQUESTED", reason)

    local request
    for _, sent in ipairs(follower.Ace3.libs.comm.sent) do
      local message = follower.Ace3.Deserialize(sent.payload)
      if message and message.type == "DETAIL_FETCH" then request = message end
    end
    assert_not_nil(request)
    assert_equal(3, #request.requests)
    assert_equal("7:1", request.requests[1].entityId)
    assert_equal("7:3", request.requests[3].entityId)
  end)

  it("serializes competing proposals against the coordinator's current balance and blocks local bypass", function()
    local dibs = activateV2(); local season = dibs.GetCurrentSeasonId()
    local first = dibs.Ledger.CommitDibUse(nil, { transactionId = "b06-race-1", playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 1, source = "b06" })
    local second = dibs.Ledger.CommitDibUse(nil, { transactionId = "b06-race-2", playerName = "Player-Realm", seasonId = season, amount = 1, itemID = 2, source = "b06" })
    assert_true(first.accepted); assert_false(second.accepted); assert_equal("INSUFFICIENT_BALANCE", second.reasonCode)
    local localTx, localReason = dibs.Ledger.Use("Player-Realm", 1, "bypass", "test", season)
    assert_nil(localTx); assert_equal("DISTRIBUTED_COMMIT_REQUIRED", localReason)
    assert_equal(1, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("keeps enforced cutover across a normal handoff and fences the old coordinator", function()
    local dibs = activateV2(); local before = dibs.Governance.GetAuthorityState().transition.baselineHash
    local closure = assert(dibs.Governance.BeginHandoff(nil, { finalSeq = 0, rootHash = before }))
    local successor = assert(dibs.Identity.CreateSnapshot("Officer-Realm"))
    assert_true(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = successor, ledgerEpoch = 8, protocolState = "V2_ENFORCED",
      transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash },
    } } }))
    assert_true(dibs.Governance.IsV2Enforced())
    local result = dibs.Ledger.CommitDibUse(nil, { transactionId = "b06-stale", playerName = "Player-Realm", seasonId = dibs.GetCurrentSeasonId(), amount = 1, itemID = 1 })
    assert_false(result.accepted); assert_equal("CURRENT_COORDINATOR_REQUIRED", result.reasonCode)
  end)
end)
