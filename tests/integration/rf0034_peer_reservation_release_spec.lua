local clients = require("helpers.canonical_operation_clients")

-- RF-0034 regression suite.
--
-- RF-0034 - "SyncV2 : une reservation diffusee a la guilde n'est jamais
-- liberee chez les pairs quand la proposition se termine sans commit
-- canonique" (docs/code-audit/INDEX.md#rf-0034).
--
-- `specs/017-guild-sync-reliability/spec.md` FR-011 states that a
-- reservation MUST be "removed when the matching canonical commit is
-- applied".
--
-- The coordinator announces an `AWARD_RESERVATION_DIGEST` to the guild when
-- a proposal is recorded. A peer stores the entry in
-- `state.awardReservations` and counts it in
-- `Ledger.GetPendingDibReservations`, which reduces the player's *available*
-- balance.
--
-- The peer only removes the reservation when the canonical commit arrives
-- (`reservationHasCanonicalCommit`). But a proposal can end WITHOUT a
-- canonical commit: `Governance.ResolveAwardProposal(proposalId, "STALE" or
-- "REJECTED")` ends the attempt with no transaction at all.
--
-- On the coordinator the local release works (RF-0031). On the peers, the
-- reservation entry stays in `state.awardReservations` forever, because:
--   * the coordinator's next digest no longer contains the proposal (it is
--     terminal), but the digest is a *replacement* list, not a delta, so the
--     peer never learns that the entry must be dropped;
--   * no `RELEASED` tombstone is ever broadcast, because the tombstone is
--     only written locally by `Sync.ClearAwardReservation`.
--
-- Consequence: on every peer client, the player's available balance stays
-- permanently reduced by a reservation that no accounting movement explains.

local function setupV2()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  -- The peers are separate clients with their own SavedVariables. They share
  -- the guild season catalog and the authority record, which the season and
  -- authority syncs replicate; only their own identity differs.
  local shared = world:Snapshot(coordinator)
  world:Load("Player-Realm", shared)
  world:Load("Officer-Realm", shared)
  world:TakePackets()
  return world, coordinator
end

-- A peer that receives a reservation digest stores it as a PENDING
-- reservation for the player. The message identifier is unique per
-- delivery so the replay guard never masks the tombstone logic.
local deliveryCounter = 0
local function deliverReservationDigest(world, senderName, records)
  local sender = world.clients[senderName]
  deliveryCounter = deliveryCounter + 1
  local message = {
    type = "AWARD_RESERVATION_DIGEST", entityType = "AWARD_RESERVATION", entityId = "pending",
    revision = 1, records = records,
    contentHash = sender.dibs.Sync.CalculateContentHash(records),
    messageId = "rf0034-digest-" .. tostring(deliveryCounter),
  }
  local envelope = assert(sender.dibs.Sync.BuildEnvelope(message))
  for name, client in pairs(world.clients) do
    if name ~= senderName then
      local accepted, reason = client.dibs.Sync.OnAddonMessage(
        "DIBS", client.dibs.Ace3.Serialize(envelope), "GUILD", senderName)
      assert_true(accepted, "the reservation digest was refused by " .. name .. ": " .. tostring(reason))
    end
  end
end

-- Delivers every queued packet of the world until the queue is quiescent.
local function pump(world)
  local packets = world:TakePackets()
  for _, packet in ipairs(packets) do
    local recipients = {}
    if packet.channel == "GUILD" then
      for name in pairs(world.clients) do
        if name ~= packet.sender then recipients[#recipients + 1] = name end
      end
    elseif packet.channel == "WHISPER" then
      for name in pairs(world.clients) do
        if name:lower() == tostring(packet.target):lower() then recipients[#recipients + 1] = name end
      end
    end
    table.sort(recipients)
    for _, name in ipairs(recipients) do
      world.clients[name].dibs.Sync.OnAddonMessage(
        packet.prefix, packet.payload, packet.channel, packet.sender)
    end
  end
end

local function reservationRecord(playerMemberKey, amount, proposalId, seasonId)
  return {
    proposalId = proposalId, playerMemberKey = playerMemberKey,
    actorMemberKey = "coordinator-realm", seasonId = seasonId or "rf0034-season",
    amount = amount, state = "PENDING", updatedAt = 1,
  }
end

describe("RF-0034 a peer releases a reservation when the proposal ends without a commit", function()
  it("counts a delivered reservation in the peer's pending reservations", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]
    local seasonId = player.dibs.GetCurrentSeasonId()

    deliverReservationDigest(world, "Coordinator-Realm", { reservationRecord("player-realm", 1, "AP5-rf0034-a", seasonId) })

    assert_equal(1, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the delivered reservation was not counted on the peer")
  end)

  it("releases the peer reservation when the coordinator resolves the proposal", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]
    local seasonId = player.dibs.GetCurrentSeasonId()

    -- The coordinator records a proposal and announces the reservation.
    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Player-Realm", itemID = 275658, amount = 1,
      type = "DIB_USED", sessionIdentity = "rf0034-resolve", response = "PASS",
    }))
    world:TakePackets()

    -- The peer applies the coordinator's reservation digest.
    local records = {}
    for _, record in ipairs(coordinator.dibs.Sync.BuildAwardReservationDigest().records or {}) do
      if record.proposalId == proposal.proposalId then records[#records + 1] = record end
    end
    assert_equal(1, #records, "the coordinator did not announce the reservation")
    deliverReservationDigest(world, "Coordinator-Realm", records)

    assert_true(player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId) >= 1,
      "the peer did not hold the announced reservation")

    -- The coordinator ends the attempt without any canonical commit.
    local resolved, reason = coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "REJECTED", "RF0034_REJECTED")
    assert_true(resolved, tostring(reason))

    -- The coordinator is now clean.
    assert_equal(0, coordinator.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the coordinator kept a phantom reservation")

    -- The release is announced to the guild.
    pump(world)

    -- The peer must converge: the reservation no longer exists.
    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the peer kept a phantom reservation after the proposal was resolved")
  end)

  it("releases the peer reservation when the coordinator resolves the proposal as stale", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]
    local seasonId = player.dibs.GetCurrentSeasonId()

    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Player-Realm", itemID = 275659, amount = 1,
      type = "DIB_USED", sessionIdentity = "rf0034-stale", response = "PASS",
    }))
    world:TakePackets()

    local records = {}
    for _, record in ipairs(coordinator.dibs.Sync.BuildAwardReservationDigest().records or {}) do
      if record.proposalId == proposal.proposalId then records[#records + 1] = record end
    end
    deliverReservationDigest(world, "Coordinator-Realm", records)

    local resolved, reason = coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "STALE", "RF0034_STALE")
    assert_true(resolved, tostring(reason))

    pump(world)

    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the peer kept a phantom reservation after the proposal became stale")
  end)

  it("does not release a peer reservation that is still pending", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]
    local seasonId = player.dibs.GetCurrentSeasonId()

    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Player-Realm", itemID = 275660, amount = 1,
      type = "DIB_USED", sessionIdentity = "rf0034-pending", response = "PASS",
    }))
    world:TakePackets()

    local records = {}
    for _, record in ipairs(coordinator.dibs.Sync.BuildAwardReservationDigest().records or {}) do
      if record.proposalId == proposal.proposalId then records[#records + 1] = record end
    end
    deliverReservationDigest(world, "Coordinator-Realm", records)

    assert_true(player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId) >= 1,
      "the peer lost a reservation that is still pending")
  end)

  it("does not resurrect a released reservation from a late digest", function()
    local world, coordinator = setupV2()
    local player = world.clients["Player-Realm"]
    local seasonId = player.dibs.GetCurrentSeasonId()

    local proposal = assert(coordinator.dibs.Governance.RecordAwardProposal("Coordinator-Realm", {
      playerName = "Player-Realm", itemID = 275661, amount = 1,
      type = "DIB_USED", sessionIdentity = "rf0034-reorder", response = "PASS",
    }))
    world:TakePackets()

    local records = {}
    for _, record in ipairs(coordinator.dibs.Sync.BuildAwardReservationDigest().records or {}) do
      if record.proposalId == proposal.proposalId then records[#records + 1] = record end
    end
    deliverReservationDigest(world, "Coordinator-Realm", records)
    assert_true(player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId) >= 1,
      "the peer did not hold the announced reservation")

    -- The coordinator ends the attempt and announces the release.
    local resolved, reason = coordinator.dibs.Governance.ResolveAwardProposal(
      proposal.proposalId, "REJECTED", "RF0034_REJECTED")
    assert_true(resolved, tostring(reason))
    pump(world)
    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "the peer kept a phantom reservation after the release")

    -- A late digest that still carries the proposal must NOT resurrect the
    -- released reservation: the peer tombstone is newer than the record.
    deliverReservationDigest(world, "Coordinator-Realm", records)
    assert_equal(0, player.dibs.Ledger.GetPendingDibReservations("Player-Realm", seasonId),
      "a late digest resurrected a released reservation")
  end)
end)
