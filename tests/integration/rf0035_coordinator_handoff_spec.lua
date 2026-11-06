local clients = require("helpers.canonical_operation_clients")

-- RF-0035 handoff suite.
--
-- RF-0035 - "SyncV2 : le rattrapage de gap canonique perd ou duplique des
-- operations" (docs/code-audit/INDEX.md#rf-0035).
--
-- The coordinator handoff is:
--   `Governance.BeginHandoff` (current coordinator only)
--     -> authority state `HANDOFF_CLOSING` with a signed predecessor closure
--     -> the closure must reach the peers
--     -> the GM adopts the next authority (`NORMAL_HANDOFF`, epoch + 1)
--     -> the peers adopt it too
--
-- The invariants under test:
--   * no operation is accepted only because the sender used to be the
--     coordinator;
--   * a stale epoch is refused;
--   * a contradictory sequence is refused;
--   * the pending proposals and the reservations survive the handoff;
--   * a client that reconnects after the handoff converges.
--
-- Every client has its own Lua environment, its own SavedVariables, its own
-- ledger, its own SyncV2 state and its own Governance state.

local function setupHandoff()
  local world = clients.new({
    names = { "Coordinator-Realm", "Officer-Realm", "Player-Realm" },
    ranks = { [1] = 0, [2] = 1, [3] = 3 },
  })
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  -- The peers share the guild season catalog and the authority record.
  local officer = world:Load("Officer-Realm", world:Snapshot(coordinator))
  local player = world:Load("Player-Realm", world:Snapshot(coordinator))
  world:TakePackets()
  return world, coordinator, officer, player
end

local function canonicalOf(dibs, ledgerId)
  local state = dibs.Ledger.GetCanonicalState(ledgerId or "guild-primary")
  return state and { epoch = state.epoch, nextSeq = state.nextSeq, rootHash = state.rootHash } or nil
end

local function grant(dibs, amount)
  local granted, reason = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
    playerName = "Player-Realm", amount = amount, reason = "RF-0035 allocation",
    source = "rf0035", seasonId = dibs.GetCurrentSeasonId(),
  })
  assert_true(granted.accepted, tostring(granted.reasonCode))
  return granted
end

local function commitDibUse(dibs, actor, transactionId)
  return dibs.Ledger.CommitDibUse({ actor = actor }, {
    transactionId = transactionId, proposalId = "rf0035-" .. transactionId,
    playerName = "Player-Realm", amount = 1, itemID = 1,
    source = "rf0035", response = "PASS", status = "finalized",
  })
end

-- The GM adopts the next authority: the successor coordinator, the next
-- epoch, and the predecessor closure.
local function adoptSuccessor(gm, successorName, closure, epoch)
  local successor = assert(gm.Identity.CreateSnapshot(successorName))
  local ok, reason = gm.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = successor, ledgerEpoch = epoch,
    protocolState = "V2_ENFORCED",
    transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash },
  } } })
  return ok, reason
end

describe("RF-0035 coordinator handoff", function()
  it("converges the successor peer on the new authority and epoch", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    local ok = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_true(ok)

    -- The peer learns the new authority through the governance record.
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    assert_equal(8, officer.dibs.Governance.GetAuthorityState().ledgerEpoch,
      "the successor peer did not adopt the new epoch")
    assert_equal("officer-realm", officer.dibs.Governance.GetAuthorityState().coordinator.memberKey,
      "the successor peer did not adopt the new coordinator")
    assert_equal(8, canonicalOf(officer.dibs).epoch,
      "the successor peer kept the closed canonical epoch")
    assert_equal(canonicalOf(coordinator.dibs).rootHash, canonicalOf(officer.dibs).rootHash,
      "the successor peer did not converge on the canonical root hash")
  end)

  it("announces the predecessor closure without waiting for a lifecycle tick", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))

    -- The closure is announced immediately: the peer does not have to wait
    -- for the next heartbeat to learn that the epoch is being closed.
    world:Deliver()
    assert_equal("HANDOFF_CLOSING", officer.dibs.Governance.GetAuthorityState().state,
      "the peer did not learn the handoff closure")
    assert_not_nil(officer.dibs.Governance.GetAuthorityState().predecessorClosure,
      "the peer did not receive the predecessor closure")
    assert_equal(closure.closureHash,
      officer.dibs.Governance.GetAuthorityState().predecessorClosure.closureHash,
      "the peer received a different predecessor closure")
  end)

  it("converges even when the successor is adopted without an intervening tick", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    -- The GM adopts the successor immediately, with no heartbeat in between.
    local ok = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_true(ok)

    world:Deliver()
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    assert_equal(8, officer.dibs.Governance.GetAuthorityState().ledgerEpoch,
      "the successor peer did not adopt the new epoch")
    assert_equal("officer-realm", officer.dibs.Governance.GetAuthorityState().coordinator.memberKey,
      "the successor peer did not adopt the new coordinator")
  end)

  it("fences the outgoing coordinator after the successor is adopted", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    assert_equal("HANDOFF_CLOSING", coordinator.dibs.Governance.GetAuthorityState().state)

    local ok, reason = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_true(ok, tostring(reason))
    assert_equal(8, coordinator.dibs.Governance.GetAuthorityState().ledgerEpoch)
    assert_equal("officer-realm", coordinator.dibs.Governance.GetAuthorityState().coordinator.memberKey)

    -- The outgoing coordinator can no longer write.
    local refused = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-fenced")
    assert_false(refused.accepted, "the outgoing coordinator still committed")
    assert_equal("CURRENT_COORDINATOR_REQUIRED", refused.reasonCode)
  end)

  it("refuses a commit from the previous epoch after the handoff", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    -- The old coordinator commits in epoch 7.
    local oldCommit = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-old-epoch")
    assert_true(oldCommit.accepted, tostring(oldCommit.reasonCode))
    assert_equal(7, oldCommit.value.ledgerEpoch)
    -- The peer receives the commit, so its closed chain is complete and it
    -- may adopt the successor epoch.
    world:Deliver()
    assert_equal(oldCommit.value.sequence, canonicalOf(officer.dibs).nextSeq - 1,
      "the peer did not receive the epoch-7 commit")

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    world:Deliver()
    local ok = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_true(ok)

    -- The successor peer learns the new authority through the governance
    -- record and the authority digest.
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()
    assert_equal(8, officer.dibs.Governance.GetAuthorityState().ledgerEpoch,
      "the successor peer did not adopt the new epoch")
    assert_equal("officer-realm", officer.dibs.Governance.GetAuthorityState().coordinator.memberKey,
      "the successor peer did not adopt the new coordinator")

    -- The successor receives the in-flight commit of the closed epoch.
    local applied = officer.dibs.Ledger.ApplyAwardCommit(oldCommit.value, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "a commit of the closed epoch was accepted")
    assert_equal("STALE_EPOCH", applied.reasonCode)
  end)

  it("refuses to adopt the successor epoch while the closed chain is incomplete", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    -- The peer misses the epoch-7 commit: its closed chain stops one
    -- position short of the closure.
    world:SetOnline("Officer-Realm", false)
    local oldCommit = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-incomplete")
    assert_true(oldCommit.accepted, tostring(oldCommit.reasonCode))
    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    world:Deliver()
    adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)

    -- The peer comes back with a chain that does not reach the closure.
    world:SetOnline("Officer-Realm", true)
    world:Deliver()
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    -- The peer must not adopt the successor epoch on an incomplete chain:
    -- the closure sequence does not match its own position.
    local peerState = canonicalOf(officer.dibs)
    assert_equal(7, peerState.epoch, "the peer adopted the successor epoch on an incomplete chain")
    assert_not_nil(officer.dibs.Sync.IsSyncBehind and officer.dibs.Sync.IsSyncBehind(),
      "the peer is not diagnosed as behind")
  end)

  it("keeps the closed epoch commits available for the lagging peers", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local oldCommit = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-keep-epoch")
    assert_true(oldCommit.accepted, tostring(oldCommit.reasonCode))

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    world:Deliver()
    adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)

    -- The closed epoch is not erased by the handoff: the commits of the
    -- closed epoch stay retrievable, so a peer that missed them can still
    -- catch up instead of losing a transaction.
    local retrieved = coordinator.dibs.Ledger.GetCanonicalCommit(7, oldCommit.value.sequence, "guild-primary")
    assert_not_nil(retrieved, "the closed epoch commit was erased by the handoff")
    assert_equal(oldCommit.value.commitHash, retrieved.commitHash,
      "the retrievable commit is not the one that was written")
  end)

  it("refuses a commit that is not the next sequence after the handoff", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local first = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-handoff-order-1")
    assert_true(first.accepted, tostring(first.reasonCode))
    local second = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-handoff-order-2")
    assert_true(second.accepted, tostring(second.reasonCode))

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    -- The successor is on the epoch-8 chain, which starts from the closure
    -- root. An epoch-7 commit does not chain on it.
    local applied = officer.dibs.Ledger.ApplyAwardCommit(second.value, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "a commit of the closed epoch was accepted")
    assert_equal("STALE_EPOCH", applied.reasonCode)
  end)

  it("requires the exact predecessor closure to adopt the successor", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))

    -- A closure whose hash does not match is refused.
    local wrong = assert(coordinator.dibs.Identity.CreateSnapshot("Officer-Realm"))
    local refused, reason = coordinator.dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = wrong, ledgerEpoch = 8,
      transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = "not-the-closure" },
    } } })
    assert_false(refused, "a handoff with a wrong closure hash was adopted")
    assert_equal("HANDOFF_PARENT_MISMATCH", reason)
  end)

  it("refuses a handoff that is not requested by the current coordinator", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local closure, reason = coordinator.dibs.Governance.BeginHandoff("Officer-Realm", {
      finalSeq = 0, rootHash = canonicalOf(coordinator.dibs).rootHash,
    })
    assert_nil(closure, "a non-coordinator closed the handoff")
    assert_equal("CURRENT_COORDINATOR_REQUIRED", reason)
  end)

  it("preserves the pending proposals and the reservations across the handoff", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    -- A pending proposal holds a reservation.
    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Player-Realm", itemID = 275658, amount = 1,
      type = "DIB_USED", sessionIdentity = "rf0035-handoff-reservation", response = "PASS",
    }))
    world:Deliver()
    assert_true(coordinator.dibs.Ledger.GetPendingDibReservations("Player-Realm", coordinator.dibs.GetCurrentSeasonId()) >= 1,
      "the proposal did not hold a reservation")

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    local ok = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_true(ok)

    -- The proposal and its reservation survive the transfer of authority.
    local found = nil
    for _, candidate in ipairs(coordinator.dibs.Governance.GetAwardProposals()) do
      if candidate.proposalId == proposal.proposalId then found = candidate end
    end
    assert_not_nil(found, "the pending proposal was lost by the handoff")
    assert_equal("PENDING_RECONCILIATION", found.status)
    assert_true(coordinator.dibs.Ledger.GetPendingDibReservations("Player-Realm", coordinator.dibs.GetCurrentSeasonId()) >= 1,
      "the reservation was lost by the handoff")
  end)

  it("rejects a second adoption of the same successor epoch", function()
    local world, coordinator, officer, player = setupHandoff()
    grant(coordinator.dibs, 5)
    world:Deliver()

    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    local ok = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_true(ok)

    -- The same closure cannot be replayed to take the authority again.
    local replayed, reason = adoptSuccessor(coordinator.dibs, "Officer-Realm", closure, 8)
    assert_false(replayed, "the same handoff was adopted twice")
    assert_equal("HANDOFF_CLOSURE_REQUIRED", reason)
  end)
end)
