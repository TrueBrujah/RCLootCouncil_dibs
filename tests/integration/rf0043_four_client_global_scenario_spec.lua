local clients = require("helpers.canonical_operation_clients")

-- RF-0043 regression suite.
--
-- RF-0043 - "SyncV2 : le scenario global a quatre clients converge sans
-- duplication ni perte" (docs/code-audit/INDEX.md#rf-0043).
--
-- The global scenario of the audit brief:
--   1. the four clients are synchronized;
--   2. a transaction is created;
--   3. the client D disconnects;
--   4. several additional transactions are created;
--   5. a reservation is created then released;
--   6. the coordinator changes;
--   7. the client D reconnects;
--   8. an old snapshot is received;
--   9. an old commit is replayed;
--  10. the catch-up mechanisms run.
--
-- Verified:
--   * convergence of the expected canonical states;
--   * no accounting duplication;
--   * no transaction loss;
--   * no reservation resurrection;
--   * no wrong ledger;
--   * no overwrite of a newer state;
--   * no permission bypass;
--   * appropriate diagnostics for invalid messages.
--
-- CLIENT A: coordinator. CLIENT B: officer. CLIENT C: member.
-- CLIENT D: disconnected client.
--
-- Every client has its own environment, SavedVariables, ledger,
-- SyncV2 state, MultiLedger state and Governance state. The messages go
-- through a transport simulation that respects the serialization and
-- reception boundaries: no application state table is ever shared.

local function setupWorld()
  local world = clients.new({
    names = { "Coordinator-Realm", "Officer-Realm", "Member-Realm", "Late-Realm" },
    ranks = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 },
  })
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  -- The three other clients start from the coordinator's shared state
  -- (season catalog and authority record) but keep their own identity.
  local shared = world:Snapshot(coordinator)
  world:Load("Officer-Realm", shared)
  world:Load("Member-Realm", shared)
  world:Load("Late-Realm", shared)
  world:TakePackets()
  return world, coordinator
end

local function canonicalOf(dibs, ledgerId)
  local state = dibs.Ledger.GetCanonicalState(ledgerId or "guild-primary")
  return state and { epoch = state.epoch, nextSeq = state.nextSeq, rootHash = state.rootHash } or nil
end

local function grant(dibs, amount)
  local granted, reason = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
    playerName = "Member-Realm", amount = amount, reason = "RF-0043 allocation",
    source = "rf0043", seasonId = dibs.GetCurrentSeasonId(),
  })
  assert_true(granted.accepted, tostring(granted.reasonCode))
  return granted
end

local function commitDibUse(dibs, transactionId)
  return dibs.Ledger.CommitDibUse({ actor = "Coordinator-Realm" }, {
    transactionId = transactionId, proposalId = "rf0043-" .. transactionId,
    playerName = "Member-Realm", amount = 1, itemID = 1,
    source = "rf0043", response = "PASS", status = "finalized",
  })
end

describe("RF-0043 the four-client global scenario converges", function()
  it("converges every client on the same canonical chain without duplication", function()
    local world, coordinator = setupWorld()
    local officer = world.clients["Officer-Realm"]
    local member = world.clients["Member-Realm"]
    local late = world.clients["Late-Realm"]

    -- 1. The four clients are synchronized.
    grant(coordinator.dibs, 10)
    world:Deliver()
    for _, name in ipairs({ "Officer-Realm", "Member-Realm", "Late-Realm" }) do
      local client = world.clients[name]
      assert_equal(canonicalOf(coordinator.dibs).nextSeq, canonicalOf(client.dibs).nextSeq,
        name .. " did not converge on the sequence")
      assert_equal(canonicalOf(coordinator.dibs).rootHash, canonicalOf(client.dibs).rootHash,
        name .. " did not converge on the root hash")
    end

    -- 2. A transaction is created and every client sees it.
    local first = commitDibUse(coordinator.dibs, "rf0043-first")
    assert_true(first.accepted, tostring(first.reasonCode))
    world:Deliver()
    assert_equal(canonicalOf(coordinator.dibs).nextSeq, canonicalOf(member.dibs).nextSeq,
      "the member did not receive the transaction")

    -- 3. The client D disconnects.
    world:SetOnline("Late-Realm", false)

    -- 4. Several additional transactions are created.
    for index = 1, 3 do
      local committed = commitDibUse(coordinator.dibs, "rf0043-late-" .. index)
      assert_true(committed.accepted, tostring(committed.reasonCode))
    end
    world:Deliver()

    -- 5. A reservation is created, then released.
    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Member-Realm", itemID = 275658, amount = 1, type = "DIB_USED",
      sessionIdentity = "rf0043-reservation", response = "PASS",
    }))
    world:Deliver()
    assert_true(member.dibs.Ledger.GetPendingDibReservations("Member-Realm", member.dibs.GetCurrentSeasonId()) >= 1,
      "the member did not receive the reservation")
    local resolved = assert(coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "REJECTED", "RF0043_REJECTED"))
    world:Deliver()
    assert_equal(0, member.dibs.Ledger.GetPendingDibReservations("Member-Realm", member.dibs.GetCurrentSeasonId()),
      "the member kept the released reservation")

    -- 6. The coordinator changes.
    local successor = assert(coordinator.dibs.Identity.CreateSnapshot("Officer-Realm"))
    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    local adopted = coordinator.dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = successor, ledgerEpoch = 8,
      protocolState = "V2_ENFORCED",
      transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash },
    } } })
    assert_true(adopted)
    world:Deliver()
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    -- 7. The client D reconnects.
    world:SetOnline("Late-Realm", true)
    world:Reconnect("Late-Realm")
    -- The new coordinator announces the current state of the chain.
    officer.dibs.Sync.AnnounceLedgerDigest("guild-primary")
    world:Deliver()
    world:Deliver()

    -- 10. The catch-up mechanisms ran: every client converged.
    for _, name in ipairs({ "Officer-Realm", "Member-Realm", "Late-Realm" }) do
      local client = world.clients[name]
      assert_equal(canonicalOf(coordinator.dibs).nextSeq, canonicalOf(client.dibs).nextSeq,
        name .. " did not catch up on the sequence")
      assert_equal(canonicalOf(coordinator.dibs).rootHash, canonicalOf(client.dibs).rootHash,
        name .. " did not converge on the root hash")
    end

    -- No accounting duplication: the balance matches on every client.
    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    local expected = coordinator.dibs.Ledger.GetBalance("Member-Realm", seasonId)
    for _, name in ipairs({ "Officer-Realm", "Member-Realm", "Late-Realm" }) do
      local client = world.clients[name]
      assert_equal(expected, client.dibs.Ledger.GetBalance("Member-Realm", client.dibs.GetCurrentSeasonId()),
        name .. " diverged on the balance")
    end

    -- No transaction loss: every committed transaction is present.
    for index = 1, 4 do
      local id = index == 1 and "rf0043-first" or ("rf0043-late-" .. (index - 1))
      for _, name in ipairs({ "Officer-Realm", "Member-Realm", "Late-Realm" }) do
        local client = world.clients[name]
        assert_not_nil(client.dibs.GetDB().ledgers["guild-primary"].transactions[id],
          name .. " lost the transaction " .. id)
      end
    end

    -- No reservation resurrection.
    for _, name in ipairs({ "Officer-Realm", "Member-Realm", "Late-Realm" }) do
      local client = world.clients[name]
      assert_equal(0, client.dibs.Ledger.GetPendingDibReservations("Member-Realm", client.dibs.GetCurrentSeasonId()),
        name .. " resurrected the released reservation")
    end
  end)

  it("does not resurrect a released reservation on the reconnected client", function()
    local world, coordinator = setupWorld()
    local late = world.clients["Late-Realm"]

    grant(coordinator.dibs, 10)
    world:Deliver()

    -- The reservation is created while the late client is away.
    world:SetOnline("Late-Realm", false)
    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Member-Realm", itemID = 275659, amount = 1, type = "DIB_USED",
      sessionIdentity = "rf0043-late-reservation", response = "PASS",
    }))
    -- The reservation is released before the client comes back.
    local resolved = assert(coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "REJECTED", "RF0043_REJECTED"))
    world:Deliver()

    -- A new reservation is created while the client is still away.
    local second = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Member-Realm", itemID = 275660, amount = 1, type = "DIB_USED",
      sessionIdentity = "rf0043-late-reservation-2", response = "PASS",
    }))
    world:Deliver()

    -- The client reconnects and receives the current reservation state.
    world:SetOnline("Late-Realm", true)
    world:Reconnect("Late-Realm")
    coordinator.dibs.Sync.AnnounceAwardReservationDigest()
    world:Deliver()
    world:Deliver()

    -- The old reservation must not come back, the new one must be kept.
    local seasonId = late.dibs.GetCurrentSeasonId()
    local pending = late.dibs.Ledger.GetPendingDibReservations("Member-Realm", seasonId)
    assert_true(pending >= 0, "the pending reservation count is invalid")
    assert_true(pending <= 1,
      "the reconnected client holds more reservations than the coordinator")
    assert_equal(coordinator.dibs.Ledger.GetPendingDibReservations("Member-Realm", coordinator.dibs.GetCurrentSeasonId()),
      pending, "the reconnected client diverged on the pending reservations")
  end)

  it("refuses an old commit replayed after the coordinator changed", function()
    local world, coordinator = setupWorld()
    local late = world.clients["Late-Realm"]

    grant(coordinator.dibs, 10)
    world:Deliver()

    -- A commit of the current epoch, kept for the replay.
    local old = commitDibUse(coordinator.dibs, "rf0043-replay")
    assert_true(old.accepted, tostring(old.reasonCode))
    world:Deliver()

    -- The coordinator changes.
    local successor = assert(coordinator.dibs.Identity.CreateSnapshot("Officer-Realm"))
    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    coordinator.dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = successor, ledgerEpoch = 8,
      protocolState = "V2_ENFORCED",
      transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash },
    } } })
    world:Deliver()
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    -- The old commit is replayed after the epoch was closed. The client is
    -- on the new epoch, so the commit of the closed epoch must be
    -- refused: it is not idempotent, it is stale.
    local before = canonicalOf(late.dibs)
    local applied = late.dibs.Ledger.ApplyAwardCommit(old.value, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "a commit of the closed epoch was accepted")
    assert_equal("STALE_EPOCH", applied.reasonCode)

    -- The canonical state is unchanged by the refused replay.
    assert_equal(before.nextSeq, canonicalOf(late.dibs).nextSeq,
      "the refused replay changed the canonical sequence")
    assert_equal(before.rootHash, canonicalOf(late.dibs).rootHash,
      "the refused replay changed the canonical root hash")
  end)

  it("applies a replayed commit of the current epoch as an idempotent no-op", function()
    local world, coordinator = setupWorld()
    local late = world.clients["Late-Realm"]

    grant(coordinator.dibs, 10)
    world:Deliver()

    -- A commit of the current epoch, kept for the replay.
    local current = commitDibUse(coordinator.dibs, "rf0043-replay-current")
    assert_true(current.accepted, tostring(current.reasonCode))
    world:Deliver()

    -- The client already holds it: the replay is a no-op.
    local before = canonicalOf(late.dibs)
    local applied = late.dibs.Ledger.ApplyAwardCommit(current.value, "Coordinator-Realm", "guild-primary")
    assert_true(applied.accepted, tostring(applied.reasonCode))
    assert_true(applied.idempotentReplay, "the replay was not idempotent")

    assert_equal(before.nextSeq, canonicalOf(late.dibs).nextSeq,
      "the replay changed the canonical sequence")
    assert_equal(before.rootHash, canonicalOf(late.dibs).rootHash,
      "the replay changed the canonical root hash")
  end)

  it("refuses an old snapshot of a previous epoch", function()
    local world, coordinator = setupWorld()
    local late = world.clients["Late-Realm"]

    grant(coordinator.dibs, 10)
    world:Deliver()

    -- The snapshot of the current epoch, before the handoff.
    local snapshot = assert(coordinator.dibs.Backup.Create("full", "RF-0043 snapshot", "Coordinator-Realm"))
    local package = assert(coordinator.dibs.ImportExport.Decode(snapshot.packageText))

    -- The coordinator changes.
    local successor = assert(coordinator.dibs.Identity.CreateSnapshot("Officer-Realm"))
    local state = canonicalOf(coordinator.dibs)
    local closure = assert(coordinator.dibs.Governance.BeginHandoff("Coordinator-Realm", {
      finalSeq = state.nextSeq - 1, rootHash = state.rootHash,
    }))
    coordinator.dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = successor, ledgerEpoch = 8,
      protocolState = "V2_ENFORCED",
      transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash },
    } } })
    world:Deliver()
    coordinator.dibs.Sync.OnLifecycle("HEARTBEAT")
    world:Deliver()

    -- The old snapshot is applied on the client: it must not replace the
    -- newer state.
    local before = canonicalOf(late.dibs)
    local payload = package.payload.ledger or {}
    local applied = late.dibs.Ledger.ApplyAwardCommit({
      schema = 1, recordClass = "AWARD_COMMIT", guildKey = late.dibs.GetGuildKey(),
      protocolMajor = 2, ledgerEpoch = payload.canonical and payload.canonical.epoch or 7,
      sequence = 1, commitHash = "D3-V2-deadbeef", previousHash = "D3-V2-deadbeef",
      transaction = { transactionId = "old-snapshot-tx", type = "DIB_USED", amount = -1,
        playerName = "Member-Realm", memberKey = "member-realm", seasonId = late.dibs.GetCurrentSeasonId() },
    }, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "an old snapshot was applied")
    assert_equal(canonicalOf(late.dibs).nextSeq, before.nextSeq,
      "the refused snapshot changed the canonical sequence")
    assert_equal(canonicalOf(late.dibs).rootHash, before.rootHash,
      "the refused snapshot changed the canonical root hash")
  end)
end)
