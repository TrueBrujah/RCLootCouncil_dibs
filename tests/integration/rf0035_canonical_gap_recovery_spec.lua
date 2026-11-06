local clients = require("helpers.canonical_operation_clients")

-- RF-0035 regression suite.
--
-- RF-0035 - "SyncV2 : le rattrapage de gap canonique perd ou duplique des
-- operations" (docs/code-audit/INDEX.md#rf-0035).
--
-- The gap recovery path is:
--   `LEDGER_DIGEST` (coordinator -> guild)
--     -> `requestLedgerBatch` (follower -> coordinator, DETAIL_FETCH)
--     -> `DETAIL_FETCH` answered with `Sync.SendAwardCommit` /
--        `Sync.SendOperationCommit` (a TRANSFER of the stored record)
--     -> `applyTransferEntity` -> `applyLedgerCommit`
--     -> `Ledger.ApplyAwardCommit` / `Ledger.ApplyOperationCommit`
--     -> `clearResolvedLedgerGap` decides whether the gap is closed.
--
-- The invariants under test:
--   * no transaction is counted twice;
--   * no transaction is lost;
--   * a valid local state is never silently replaced;
--   * a contradictory sequence is never accepted;
--   * the canonical root hash never changes without a validated commit.
--
-- Every client has its own Lua environment, its own SavedVariables, its own
-- ledger, its own SyncV2 state and its own Governance state. Nothing is
-- shared except the serialized wire payloads.

local function setupV2(options)
  options = options or {}
  local world = clients.new(options)
  local coordinator = world:Load(options.names and options.names[1] or "Coordinator-Realm")
  world:ActivateV2()
  return world, coordinator
end

-- Every client that is not the coordinator shares the guild season catalog
-- and the authority record, which the season and authority syncs replicate.
local function addPeer(world, name, coordinator)
  local peer = world:Load(name, world:Snapshot(coordinator))
  world:TakePackets()
  return peer
end

local function canonicalOf(dibs, ledgerId)
  local state = dibs.Ledger.GetCanonicalState(ledgerId or "guild-primary")
  return state and { epoch = state.epoch, nextSeq = state.nextSeq, rootHash = state.rootHash } or nil
end

-- The fixture seeds one Dib. The tests need room for several commits, so
-- the coordinator grants a known extra allocation through the canonical
-- path, exactly like a real season allocation.
local function grant(dibs, amount)
  local granted, reason = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
    playerName = "Player-Realm", amount = amount, reason = "RF-0035 allocation",
    source = "rf0035", seasonId = dibs.GetCurrentSeasonId(),
  })
  assert_true(granted.accepted, tostring(granted.reasonCode))
  return granted
end

local function commitDibUse(dibs, actor, transactionId, itemID)
  return dibs.Ledger.CommitDibUse({ actor = actor }, {
    transactionId = transactionId, proposalId = "rf0035-" .. transactionId,
    playerName = "Player-Realm", amount = 1, itemID = itemID or 1,
    source = "rf0035", response = "PASS", status = "finalized",
  })
end

describe("RF-0035 canonical gap recovery", function()
  it("recovers a single missed commit after a reconnection", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    world:SetOnline("Player-Realm", false)
    local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-single")
    assert_true(committed.accepted, tostring(committed.reasonCode))

    -- The peer was offline: it did not receive the announcement.
    world:Deliver()
    assert_equal(1, canonicalOf(player.dibs).nextSeq - 1,
      "the offline peer received the commit")

    -- The peer comes back and learns the state from the coordinator digest.
    world:Reconnect("Player-Realm")
    world:Deliver()

    local peerState = canonicalOf(player.dibs)
    local coordinatorState = canonicalOf(coordinator.dibs)
    assert_equal(coordinatorState.nextSeq, peerState.nextSeq,
      "the peer did not catch up to the coordinator sequence")
    assert_equal(coordinatorState.rootHash, peerState.rootHash,
      "the peer did not converge on the canonical root hash")
    assert_equal(5, player.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId()),
      "the peer did not recover the transaction")
  end)

  it("recovers several missed commits without losing or duplicating one", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    world:SetOnline("Player-Realm", false)
    for index = 1, 3 do
      local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-multi-" .. index)
      assert_true(committed.accepted, tostring(committed.reasonCode))
    end
    world:Deliver()

    world:Reconnect("Player-Realm")
    world:Deliver()

    local coordinatorState = canonicalOf(coordinator.dibs)
    local peerState = canonicalOf(player.dibs)
    assert_equal(coordinatorState.nextSeq, peerState.nextSeq,
      "the peer did not catch up on the full batch")
    assert_equal(coordinatorState.rootHash, peerState.rootHash,
      "the peer did not converge on the canonical root hash")
    assert_equal(coordinator.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId()),
      player.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId()),
      "the peer did not recover every missed transaction")
  end)

  it("never counts a recovered transaction twice", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    world:SetOnline("Player-Realm", false)
    local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-duplicate")
    assert_true(committed.accepted, tostring(committed.reasonCode))
    world:Deliver()

    world:Reconnect("Player-Realm")
    world:Deliver()

    -- The peer holds exactly the two canonical positions: the allocation and
    -- the single recovered commit. A duplicated application would show a
    -- third position.
    local peerState = canonicalOf(player.dibs)
    assert_equal(3, peerState.nextSeq, "the peer applied the commit more than once")
    assert_equal(coordinator.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId()),
      player.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId()),
      "the peer counted the recovered transaction twice")
  end)

  it("applies a replayed commit as an idempotent no-op", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-replay")
    assert_true(committed.accepted, tostring(committed.reasonCode))
    world:Deliver()

    local before = canonicalOf(player.dibs)
    local beforeBalance = player.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId())

    -- The very same commit is applied a second time.
    local replay = player.dibs.Ledger.ApplyAwardCommit(committed.value, "Coordinator-Realm", "guild-primary")
    assert_true(replay.accepted, tostring(replay.reasonCode))
    assert_true(replay.idempotentReplay, "the replay was not reported as idempotent")

    local after = canonicalOf(player.dibs)
    assert_equal(before.nextSeq, after.nextSeq, "the replay advanced the canonical sequence")
    assert_equal(before.rootHash, after.rootHash, "the replay changed the canonical root hash")
    assert_equal(beforeBalance, player.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId()),
      "the replay changed the balance")
  end)

  it("refuses a commit that contradicts the canonical chain", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-contradiction")
    assert_true(committed.accepted, tostring(committed.reasonCode))
    world:Deliver()

    local before = canonicalOf(player.dibs)

    -- A commit whose payload was altered keeps a valid shape but no longer
    -- matches its own hash: it must be refused without any mutation.
    local tampered = {}
    for key, value in pairs(committed.value) do tampered[key] = value end
    tampered.transaction = {}
    for key, value in pairs(committed.value.transaction) do tampered.transaction[key] = value end
    tampered.transaction.amount = 999

    local applied = player.dibs.Ledger.ApplyAwardCommit(tampered, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "a tampered commit was accepted")
    assert_equal("COMMIT_HASH_MISMATCH", applied.reasonCode)

    local after = canonicalOf(player.dibs)
    assert_equal(before.nextSeq, after.nextSeq, "the refused commit advanced the canonical sequence")
    assert_equal(before.rootHash, after.rootHash, "the refused commit changed the canonical root hash")
  end)

  it("refuses an out-of-order commit without advancing the canonical state", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    -- The peer stays offline, so it never receives the two commits.
    world:SetOnline("Player-Realm", false)
    local first = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-order-1")
    assert_true(first.accepted, tostring(first.reasonCode))
    local second = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-order-2")
    assert_true(second.accepted, tostring(second.reasonCode))
    world:Deliver()

    local before = canonicalOf(player.dibs)

    -- The second commit is applied alone: the chain expects the first one.
    local applied = player.dibs.Ledger.ApplyAwardCommit(second.value, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "an out-of-order commit was accepted")
    assert_equal("SYNC_BEHIND", applied.reasonCode)

    local after = canonicalOf(player.dibs)
    assert_equal(before.nextSeq, after.nextSeq, "the refused commit advanced the canonical sequence")
    assert_equal(before.rootHash, after.rootHash, "the refused commit changed the canonical root hash")
  end)

  it("refuses a commit that does not chain on the local chain", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)

    -- The peer stays offline, so it never receives the allocation: its
    -- chain is one position behind the coordinator.
    world:SetOnline("Player-Realm", false)
    world:Deliver()

    local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-root-conflict")
    assert_true(committed.accepted, tostring(committed.reasonCode))
    world:Deliver()

    -- The commit does not chain on the peer's local chain: it is not the
    -- next sequence. The peer must refuse it and must not invent the
    -- missing position.
    local before = canonicalOf(player.dibs)
    local applied = player.dibs.Ledger.ApplyAwardCommit(committed.value, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "a commit that does not chain was accepted")
    assert_equal("SYNC_BEHIND", applied.reasonCode)

    local after = canonicalOf(player.dibs)
    assert_equal(before.nextSeq, after.nextSeq, "the refused commit advanced the canonical sequence")
    assert_equal(before.rootHash, after.rootHash, "the refused commit changed the canonical root hash")
  end)

  it("diagnoses the gap instead of guessing it", function()
    local world, coordinator = setupV2()
    local player = addPeer(world, "Player-Realm", coordinator)
    grant(coordinator.dibs, 5)
    world:Deliver()

    local coordinatorLast = canonicalOf(coordinator.dibs).nextSeq - 1

    world:SetOnline("Player-Realm", false)
    local committed = commitDibUse(coordinator.dibs, "Coordinator-Realm", "rf0035-behind")
    assert_true(committed.accepted, tostring(committed.reasonCode))
    world:Deliver()

    -- The peer never learned the new state: it is still where it was.
    assert_equal(coordinatorLast, canonicalOf(player.dibs).nextSeq - 1, "the offline peer advanced anyway")

    -- The peer comes back and receives the coordinator digest. It detects
    -- the gap, asks for the missing detail, and does not guess it: the
    -- first round delivers the digest, the peer marks itself behind and
    -- requests the missing detail.
    world:SetOnline("Player-Realm", true)
    local held = world.held or {}
    world.held = {}
    for _, packet in ipairs(held) do world.packets[#world.packets + 1] = packet end
    world:DeliverOnce()
    assert_true(player.dibs.Sync.IsSyncBehind(), "the peer is not flagged as behind")
    assert_equal(coordinatorLast, canonicalOf(player.dibs).nextSeq - 1, "the peer advanced before the detail arrived")

    -- The catch-up completes and the diagnostic is cleared.
    world:Deliver()
    assert_equal(canonicalOf(coordinator.dibs).nextSeq, canonicalOf(player.dibs).nextSeq,
      "the peer did not catch up")
    assert_false(player.dibs.Sync.IsSyncBehind(), "the peer is still flagged as behind")
  end)
end)
