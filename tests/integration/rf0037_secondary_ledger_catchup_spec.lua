local clients = require("helpers.canonical_operation_clients")

-- RF-0037 regression suite.
--
-- RF-0037 - "SyncV2 : le rattrapage d'un Secondary Ledger" (verification du
-- chemin de reprise, sans defaut confirme) — voir
-- docs/code-audit/INDEX.md.
--
-- The brief asks for the Secondary Ledger catch-up to be verified:
--   * `requestLedgerBatch` must target the right ledger;
--   * a commit of another ledger must stay refused;
--   * the balances of the two ledgers must stay separate.
--
-- Every client has its own Lua environment, its own SavedVariables, its
-- own ledger, its own SyncV2 state and its own Governance state.

local function setupV2()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  world:Load("Player-Realm", world:Snapshot(coordinator))
  world:TakePackets()
  return world, coordinator
end

local function canonicalOf(dibs, ledgerId)
  local state = dibs.Ledger.GetCanonicalState(ledgerId or "guild-primary")
  return state and { epoch = state.epoch, nextSeq = state.nextSeq, rootHash = state.rootHash } or nil
end

-- Creates and approves a Secondary Ledger on the coordinator.
local function secondaryLedger(coordinator)
  local proposed = assert(coordinator.dibs.MultiLedger.ProposeLedger("Coordinator-Realm", "Raid Ledger"))
  local approval = coordinator.dibs.MultiLedger.ApproveLedger("Coordinator-Realm", proposed.ledgerId)
  assert_true(approval.ok, tostring(approval.reasonCode))
  return proposed.ledgerId
end

local function seedSecondary(coordinator, ledgerId, amount)
  local seeded = coordinator.dibs.Ledger.CommitSeasonAllocation(
    { actor = "Coordinator-Realm", ledgerId = ledgerId }, {
      playerName = "Player-Realm", amount = amount, reason = "RF-0037 allocation",
      source = "rf0037", seasonId = coordinator.dibs.GetCurrentSeasonId(),
    })
  assert_true(seeded.accepted, tostring(seeded.reasonCode))
  return seeded
end

local function commitOn(dibs, ledgerId, transactionId)
  return dibs.Ledger.CommitDibUse({ actor = "Coordinator-Realm", ledgerId = ledgerId }, {
    transactionId = transactionId, proposalId = "rf0037-" .. transactionId,
    playerName = "Player-Realm", amount = 1, itemID = 1,
    source = "rf0037", response = "PASS", status = "finalized",
  })
end

describe("RF-0037 Secondary Ledger catch-up", function()
  it("replicates an approved Secondary Ledger to the peers", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]

    local ledgerId = secondaryLedger(coordinator)
    seedSecondary(coordinator, ledgerId, 5)
    world:Deliver()

    assert_not_nil(player.dibs.MultiLedger.GetLedgerById(ledgerId),
      "the peer did not learn the Secondary Ledger")
    assert_equal("APPROVED", player.dibs.MultiLedger.GetLedgerById(ledgerId).status,
      "the peer did not learn the approval")
    assert_equal(1, canonicalOf(player.dibs, ledgerId).nextSeq - 1,
      "the peer did not learn the Secondary Ledger chain")
  end)

  it("catches up a Secondary Ledger after a reconnection", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]

    local ledgerId = secondaryLedger(coordinator)
    seedSecondary(coordinator, ledgerId, 5)
    world:Deliver()
    local before = canonicalOf(player.dibs, ledgerId).nextSeq - 1

    -- The peer is offline while two commits land on the Secondary Ledger.
    world:SetOnline("Player-Realm", false)
    for index = 1, 2 do
      local committed = commitOn(coordinator.dibs, ledgerId, "rf0037-secondary-" .. index)
      assert_true(committed.accepted, tostring(committed.reasonCode))
    end
    world:Deliver()
    assert_equal(before, canonicalOf(player.dibs, ledgerId).nextSeq - 1,
      "the offline peer advanced on the Secondary Ledger")

    -- The peer reconnects and catches up.
    world:SetOnline("Player-Realm", true)
    world:Reconnect("Player-Realm")
    world:Deliver()

    assert_equal(canonicalOf(coordinator.dibs, ledgerId).nextSeq - 1,
      canonicalOf(player.dibs, ledgerId).nextSeq - 1,
      "the peer did not catch up on the Secondary Ledger")
    assert_equal(canonicalOf(coordinator.dibs, ledgerId).rootHash,
      canonicalOf(player.dibs, ledgerId).rootHash,
      "the peer did not converge on the Secondary Ledger root hash")
    assert_equal(coordinator.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId(), ledgerId),
      player.dibs.Ledger.GetBalance("Player-Realm", coordinator.dibs.GetCurrentSeasonId(), ledgerId),
      "the Secondary Ledger balance diverged")
  end)

  it("keeps the Primary and the Secondary Ledger balances separate", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]

    local ledgerId = secondaryLedger(coordinator)
    seedSecondary(coordinator, ledgerId, 5)
    world:Deliver()

    local committed = commitOn(coordinator.dibs, ledgerId, "rf0037-separate")
    assert_true(committed.accepted, tostring(committed.reasonCode))
    world:Deliver()

    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    assert_equal(4, coordinator.dibs.Ledger.GetBalance("Player-Realm", seasonId, ledgerId),
      "the Secondary Ledger balance is wrong on the coordinator")
    assert_equal(1, coordinator.dibs.Ledger.GetBalance("Player-Realm", seasonId, "guild-primary"),
      "the Primary Ledger balance changed with a Secondary Ledger operation")
    assert_equal(4, player.dibs.Ledger.GetBalance("Player-Realm", seasonId, ledgerId),
      "the Secondary Ledger balance is wrong on the peer")
    assert_equal(1, player.dibs.Ledger.GetBalance("Player-Realm", seasonId, "guild-primary"),
      "the peer Primary Ledger balance changed with a Secondary Ledger operation")
  end)

  it("refuses a Secondary Ledger commit applied to the Primary Ledger", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]

    local ledgerId = secondaryLedger(coordinator)
    seedSecondary(coordinator, ledgerId, 5)
    world:Deliver()

    local committed = commitOn(coordinator.dibs, ledgerId, "rf0037-scope")
    assert_true(committed.accepted, tostring(committed.reasonCode))

    -- The commit belongs to the Secondary Ledger and must not be applied to
    -- the Primary Ledger.
    local applied = player.dibs.Ledger.ApplyAwardCommit(committed.value, "Coordinator-Realm", "guild-primary")
    assert_false(applied.accepted, "a Secondary Ledger commit was applied to the Primary Ledger")
    assert_equal("LEDGER_SCOPE_MISMATCH", applied.reasonCode)
  end)

  it("refuses a Secondary Ledger commit from a client that is not approved", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]

    local proposed = assert(coordinator.dibs.MultiLedger.ProposeLedger("Coordinator-Realm", "Draft Ledger"))
    local committed = commitOn(coordinator.dibs, proposed.ledgerId, "rf0037-unapproved")
    assert_false(committed.accepted, "an unapproved Secondary Ledger accepted a commit")
    assert_equal("LEDGER_NOT_APPROVED", committed.reasonCode)
  end)
end)
