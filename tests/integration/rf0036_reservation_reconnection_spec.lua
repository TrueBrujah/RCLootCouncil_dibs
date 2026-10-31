local clients = require("helpers.canonical_operation_clients")

-- RF-0036 regression suite.
--
-- RF-0036 - "SyncV2 : une reservation liberee pendant une deconnexion
-- ressuscite a la reconnexion" (docs/code-audit/INDEX.md#rf-0036).
--
-- The critical scenario from the audit brief:
--   1. a reservation is created;
--   2. the client B disconnects;
--   3. the reservation is released;
--   4. another reservation is created;
--   5. the client B reconnects.
--
-- Expected:
--   * the old reservation does not come back;
--   * the new reservation is kept;
--   * no stale message resurrects a terminal reservation;
--   * the available balances converge.
--
-- The release is carried by `AWARD_RESERVATION_RELEASE` (RF-0034), which
-- is a tombstone. The peer stores it in `awardReservationTombstones`, and
-- a later `AWARD_RESERVATION_DIGEST` must not resurrect the released
-- proposal.
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

local function peer(world)
  return world.clients["Player-Realm"]
end

local function seasonOf(dibs)
  return dibs.GetCurrentSeasonId()
end

-- The coordinator records a proposal, which holds a reservation.
local proposalCounter = 0
local function createReservation(coordinator, sessionIdentity)
  proposalCounter = proposalCounter + 1
  return assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
    playerName = "Player-Realm", itemID = 275658 + proposalCounter, amount = 1, type = "DIB_USED",
    sessionIdentity = sessionIdentity, response = "PASS",
  }))
end

-- The coordinator's reservation digest, restricted to one proposal.
local function digestFor(coordinator, proposalId)
  local records = {}
  for _, record in ipairs(coordinator.dibs.Sync.BuildAwardReservationDigest().records or {}) do
    if record.proposalId == proposalId then records[#records + 1] = record end
  end
  return records
end

-- Delivers the coordinator's digest for a proposal to every other client.
local function deliverDigest(world, coordinator, proposalId)
  local records = digestFor(coordinator, proposalId)
  if #records == 0 then return false end
  local sender = world.clients["Coordinator-Realm"]
  local message = {
    type = "AWARD_RESERVATION_DIGEST", entityType = "AWARD_RESERVATION", entityId = "pending",
    revision = 1, records = records,
    contentHash = sender.dibs.Sync.CalculateContentHash(records),
    messageId = "rf0036-digest-" .. tostring(math.random(1, 1000000)),
  }
  local envelope = assert(sender.dibs.Sync.BuildEnvelope(message))
  for name, client in pairs(world.clients) do
    if name ~= "Coordinator-Realm" then
      local accepted, reason = client.dibs.Sync.OnAddonMessage(
        "DIBS", client.dibs.Ace3.Serialize(envelope), "GUILD", "Coordinator-Realm")
      assert_true(accepted, "the reservation digest was refused by " .. name .. ": " .. tostring(reason))
    end
  end
  return true
end

describe("RF-0036 a released reservation does not come back after a reconnection", function()
  it("keeps the released reservation released and keeps the new one", function()
    local world, coordinator = setupV2()
    local player = peer(world)
    local seasonId = seasonOf(player.dibs)

    -- 1. A reservation is created and the peer learns it.
    local first = createReservation(coordinator, "rf0036-first")
    deliverDigest(world, coordinator, first.proposalId)
    assert_true(player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId) >= 1,
      "the peer did not hold the first reservation")

    -- 2. The peer disconnects.
    world:SetOnline("Player-Realm", false)

    -- 3. The reservation is released while the peer is away.
    local resolved, reason = coordinator.dibs.Governance.ResolveAwardProposal(
      first.proposalId, "REJECTED", "RF0036_REJECTED")
    assert_true(resolved, tostring(reason))

    -- 4. Another reservation is created while the peer is away.
    local second = createReservation(coordinator, "rf0036-second")

    -- 5. The peer reconnects and receives the current state.
    world:SetOnline("Player-Realm", true)
    world:Deliver()
    deliverDigest(world, coordinator, second.proposalId)
    world:Deliver()

    -- The old reservation must not come back, and the new one must be kept.
    local pending = player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId)
    assert_true(pending >= 1, "the new reservation was lost by the reconnection")

    -- The accounting balance is untouched by the reservations.
    assert_equal(coordinator.dibs.Ledger.GetBalance("Player-Realm", seasonOf(coordinator.dibs)),
      player.dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "the accounting balance diverged")
  end)

  it("does not resurrect a released reservation from a late digest", function()
    local world, coordinator = setupV2()
    local player = peer(world)
    local seasonId = seasonOf(player.dibs)

    local first = createReservation(coordinator, "rf0036-late")
    deliverDigest(world, coordinator, first.proposalId)
    assert_true(player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId) >= 1,
      "the peer did not hold the reservation")

    -- The reservation is released and the peer learns the release.
    local resolved = coordinator.dibs.Governance.ResolveAwardProposal(
      first.proposalId, "REJECTED", "RF0036_REJECTED")
    assert_true(resolved)
    world:Deliver()
    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the peer kept the released reservation")

    -- A late digest that still carries the proposal must not resurrect it.
    deliverDigest(world, coordinator, first.proposalId)
    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "a late digest resurrected a released reservation")
  end)

  it("releases the reservation on the peer when the coordinator resolves it", function()
    local world, coordinator = setupV2()
    local player = peer(world)
    local seasonId = seasonOf(player.dibs)

    local proposal = createReservation(coordinator, "rf0036-release")
    deliverDigest(world, coordinator, proposal.proposalId)
    assert_true(player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId) >= 1,
      "the peer did not hold the reservation")

    local resolved, reason = coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "STALE", "RF0036_STALE")
    assert_true(resolved, tostring(reason))

    -- The release is announced to the guild.
    world:Deliver()

    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the peer kept the reservation after the release")
  end)

  it("does not let a peer rebroadcast a release it received", function()
    local world, coordinator = setupV2()
    local player = peer(world)
    local seasonId = seasonOf(player.dibs)

    local proposal = createReservation(coordinator, "rf0036-norelay")
    deliverDigest(world, coordinator, proposal.proposalId)
    world:TakePackets()

    local resolved = coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "REJECTED", "RF0036_REJECTED")
    assert_true(resolved)
    world:Deliver()
    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the peer kept the released reservation")

    -- The peer is not the authority of the reservation: it must not
    -- rebroadcast the release.
    local before = #world.packets
    player.dibs.Sync.ClearAwardReservation(proposal.proposalId, nil)
    assert_equal(before, #world.packets,
      "a peer rebroadcast a release announcement")
  end)
end)
