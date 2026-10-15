local clients = require("helpers.request_client_fixture")

describe("Private request delivery between simulated production clients", function()
  local COORDINATOR, PLAYER, OFFICER = "Coordinator-Realm", "Player-Realm", "Officer-Realm"
  local function setup()
    local world = clients.new()
    world:Hello(COORDINATOR); world:Hello(PLAYER); world:Hello(OFFICER)
    local dibs = world:Activate(PLAYER)
    local request = dibs.Disputes.CreateReport({ category = "other", note = "Synthetic player report" })
    assert_not_nil(request)
    world:TakePackets()
    world:Advance(61)
    dibs.RequestDelivery.Pump()
    local packets = world:TakePackets()
    return world, request, packets
  end

  it("persists an offline outbox across reload without whispering or claiming receipt", function()
    local world = clients.new()
    world.online[COORDINATOR] = false
    local dibs = world:Activate(PLAYER)
    local request = dibs.Disputes.CreateReport({ note = "Offline report" })
    world:TakePackets()
    dibs.RequestDelivery.Pump()
    assert_equal(0, #world:TakePackets())
    assert_equal("queued", dibs.RequestDelivery.GetStatus(request.requestId).state)
    world:Advance(61)
    dibs = world:Activate(PLAYER)
    assert_equal("queued", dibs.RequestDelivery.GetStatus(request.requestId).state)
    assert_equal(1, #dibs.Disputes.ListForPlayer(PLAYER))
    assert_not_nil(next(dibs.GetLocalDB().requestDelivery[dibs.GetGuildKey()].pending))
  end)

  it("delivers one dossier, privately acknowledges it and deduplicates ten replayed transfers", function()
    local world, request, packets = setup()
    assert_true(#packets >= 3)
    for _, packet in ipairs(packets) do assert_equal("WHISPER", packet.channel) end
    local officer, results = world:Deliver(COORDINATOR, packets)
    assert_true(results[#results][1], tostring(results[#results][2]))
    for _ = 1, 10 do
      world:Advance(61)
      local player = world:Activate(PLAYER)
      player.RequestDelivery.Pump()
      officer = world:Deliver(COORDINATOR, world:TakePackets())
    end
    assert_equal(1, #officer.Disputes.ListForOfficer(nil))
    assert_equal(1, #officer.Disputes.GetTimeline(request.requestId, nil))
    local receiptPackets = world:TakePackets()
    local player = world:Deliver(PLAYER, receiptPackets)
    assert_equal("received", player.RequestDelivery.GetStatus(request.requestId).state)
    assert_equal("Open", player.Disputes.GetRequest(request.requestId, PLAYER).status)
  end)

  it("keeps unsupported peers pending rather than reporting success", function()
    local world = clients.new()
    local dibs = world:Activate(PLAYER)
    local request = dibs.Disputes.CreateReport({ note = "Old peer" })
    world:TakePackets()
    dibs.RequestDelivery.Pump()
    assert_equal(0, #world:TakePackets())
    assert_equal("REQUEST_PEER_UNSUPPORTED", dibs.RequestDelivery.GetStatus(request.requestId).reason)
  end)

  it("sends safe owner state and private officer replicas, then delivers the owner reply", function()
    local world, request, packets = setup()
    local coordinator = world:Deliver(COORDINATOR, packets)
    coordinator.Disputes.UpdateFollowUp(request.requestId, { assignedTo = OFFICER, reason = "PRIVATE staff evidence", followUpAt = time() + 3600 })
    assert_true(coordinator.Disputes.AskForInformation(request.requestId, "Which raid?").ok)
    coordinator.Disputes.AddOfficerReply(request.requestId, "We are investigating.")
    world:Advance(61); coordinator.RequestDelivery.Pump()
    local updates = world:TakePackets()
    local player = world:Deliver(PLAYER, updates)
    local safe = player.Disputes.GetRequest(request.requestId, PLAYER)
    assert_equal("Need information", safe.status)
    assert_equal("Which raid?", safe.question)
    assert_equal("We are investigating.", safe.replies[1].boundedText)
    assert_nil(safe.timeline); assert_nil(safe.assignedTo); assert_nil(safe.guildScope)
    local duplicate, duplicateReason = player.Disputes.CreateReport({ category = "other", note = "Synthetic player report" })
    assert_equal(request.requestId, duplicate.requestId); assert_equal("DUPLICATE_ACTIVE", duplicateReason)
    local queued = player.Disputes.AddReply(request.requestId, "Wednesday", PLAYER)
    assert_true(queued.queued)
    world:Advance(61); player.RequestDelivery.Pump()
    local replyPackets = world:TakePackets()
    coordinator = world:Deliver(COORDINATOR, replyPackets)
    local actual = coordinator.Disputes.GetRequest(request.requestId, nil)
    assert_equal("Open", actual.status)
    assert_equal("Wednesday", actual.replies[2].boundedText)
    local replica = world:Deliver(OFFICER, updates)
    assert_equal(1, #replica.Disputes.ListForOfficer(nil))
    local denied, reason = replica.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "Competing correction" })
    assert_nil(denied); assert_equal("CURRENT_COORDINATOR_REQUIRED", reason)
  end)

  it("rejects forged ownership and epoch changes at actual acceptance", function()
    local world, request = setup()
    local player = world:Activate(PLAYER)
    local pending = select(2, next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    local forged = player.DeepCopy(pending.message)
    forged.body.playerName = OFFICER
    local coordinator = world:Activate(COORDINATOR)
    local accepted, reason = coordinator.RequestDelivery.Receive(forged, PLAYER)
    assert_false(accepted); assert_equal("PLAYER_SCOPE_REQUIRED", reason)
    assert_equal(0, #coordinator.Disputes.ListForOfficer(nil))
    world.epoch = 2
    accepted, reason = coordinator.RequestDelivery.Receive(pending.message, PLAYER)
    assert_false(accepted); assert_equal("REQUEST_AUTHORITY_CHANGED", reason)
    assert_nil(coordinator.GetDB().disputes.requests[request.requestId])
  end)

  it("rejects public-channel ticket transfers and isolated developer traffic", function()
    local world, request, packets = setup()
    local coordinator = world:Activate(COORDINATOR)
    local accepted, reason = coordinator.Sync.OnAddonMessage("DIBS", packets[1].payload, "GUILD", PLAYER)
    assert_false(accepted); assert_equal("INVALID_TRANSPORT_CHANNEL", reason)
    coordinator.DeveloperMode.IsEnabled = function() return true end
    local player = world:Activate(PLAYER)
    local pending = select(2, next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    coordinator = world:Activate(COORDINATOR)
    coordinator.DeveloperMode.IsEnabled = function() return true end
    accepted, reason = coordinator.RequestDelivery.Receive(pending.message, PLAYER)
    assert_false(accepted); assert_equal("REQUEST_CONTEXT_ISOLATED", reason)
    assert_nil(coordinator.GetDB().disputes.requests[request.requestId])
    assert_false(coordinator.RequestDelivery.Pump())
  end)

  it("retains oversize work as an error without silently deleting it", function()
    local world = clients.new()
    world:Hello(COORDINATOR)
    local player = world:Activate(PLAYER)
    local request = player.Disputes.CreateReport({ note = "Oversize transport fixture" })
    player.Ace3.Serialize = function() return string.rep("x", 8193) end
    world:Advance(61); player.RequestDelivery.Pump()
    assert_equal("error", player.RequestDelivery.GetStatus(request.requestId).state)
    assert_equal("PAYLOAD_TOO_LARGE", player.RequestDelivery.GetStatus(request.requestId).reason)
    assert_not_nil(next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
  end)

  it("recovers persisted offline work when a capable coordinator reconnects", function()
    local world = clients.new()
    world.online[COORDINATOR] = false
    local player = world:Activate(PLAYER)
    local request = player.Disputes.CreateReport({ note = "Reconnect recovery" })
    player.RequestDelivery.Pump()
    world:TakePackets()
    world.online[COORDINATOR] = true
    world:Hello(COORDINATOR)
    world:Hello(PLAYER)
    player = world:Activate(PLAYER)
    world:TakePackets()
    world:Advance(61); player.RequestDelivery.Pump()
    local coordinator = world:Deliver(COORDINATOR, world:TakePackets())
    assert_not_nil(coordinator.Disputes.GetRequest(request.requestId, nil))
    local acks = world:TakePackets()
    player = world:Deliver(PLAYER, acks)
    assert_equal("received", player.RequestDelivery.GetStatus(request.requestId).state)
  end)

  it("fences pending reports on another officer before receipt", function()
    local world = clients.new()
    world:Hello(COORDINATOR)
    local officer = world:Activate(OFFICER)
    local request = officer.Disputes.CreateReport({ note = "My own queued officer report" })
    local denied, reason = officer.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "Do not race coordinator" })
    assert_nil(denied); assert_equal("CURRENT_COORDINATOR_REQUIRED", reason)
    assert_equal("Open", officer.Disputes.GetRequest(request.requestId, nil).status)
  end)

  it("allows only one compensation across stale replicas and blocks epoch takeover", function()
    local world, request, packets = setup()
    local coordinator = world:Deliver(COORDINATOR, packets)
    world:Advance(61); coordinator.RequestDelivery.Pump()
    local originalSnapshots = world:TakePackets()
    local replica = world:Deliver(OFFICER, originalSnapshots)
    assert_not_nil(replica.Disputes.GetRequest(request.requestId, nil))
    coordinator = world:Activate(COORDINATOR)
    local before = #coordinator.Ledger.GetAllTransactions()
    local correction, reason = coordinator.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "Synthetic verified correction" })
    assert_not_nil(correction, tostring(reason))
    assert_equal(before + 1, #coordinator.Ledger.GetAllTransactions())
    assert_nil(coordinator.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "Repeated decision" }))
    replica = world:Activate(OFFICER)
    local denied, denyReason = replica.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "Stale competing replica" })
    assert_nil(denied); assert_equal("CURRENT_COORDINATOR_REQUIRED", denyReason)
    coordinator = world:Activate(COORDINATOR)
    world.epoch = 2
    denied, denyReason = coordinator.Disputes.Resolve(request.requestId, "close", { reason = "Cannot take over pinned dossier" })
    assert_nil(denied); assert_equal("REQUEST_AUTHORITY_CHANGED", denyReason)
    assert_equal(before + 1, #coordinator.Ledger.GetAllTransactions())
  end)

  it("never includes administrative audit in owner wire chunks and notifies a coalesced conclusion", function()
    local world, request, packets = setup()
    local coordinator = world:Deliver(COORDINATOR, packets)
    coordinator.Disputes.UpdateFollowUp(request.requestId, { reason = "PRIVATE_STAFF_ONLY" })
    coordinator.Disputes.NoCorrection(request.requestId, "Public outcome")
    coordinator.Disputes.Resolve(request.requestId, "close", { reason = "PRIVATE_CLOSE_REASON" })
    coordinator.Disputes.Resolve(request.requestId, "archive", { reason = "PRIVATE_ARCHIVE_REASON" })
    world:Advance(61); coordinator.RequestDelivery.Pump()
    local updates = world:TakePackets()
    local ownerWire = ""
    for _, packet in ipairs(updates) do
      if packet.target == PLAYER then ownerWire = ownerWire .. packet.payload end
    end
    assert_false(ownerWire:find("PRIVATE_", 1, true) ~= nil)
    local player = world:Deliver(PLAYER, updates)
    assert_equal("Archived", player.Disputes.GetRequest(request.requestId, PLAYER).status)
    local found = false
    for _, value in ipairs(_G.__dibsMessages) do if value:find(request.requestId, 1, true) then found = true end end
    assert_true(found)
  end)

  it("rejects unknown senders and demoted coordinator authority without payload-role trust", function()
    local world, _, packets = setup()
    local coordinator = world:Activate(COORDINATOR)
    local accepted = coordinator.Sync.OnAddonMessage("DIBS", packets[1].payload, "WHISPER", "Stranger-Realm")
    assert_false(accepted)
    world.ranks[1] = 3
    coordinator = world:Activate(COORDINATOR)
    local _, results = world:Deliver(COORDINATOR, packets)
    assert_false(results[#results][1])
    assert_equal("REQUEST_AUTHORITY_CHANGED", results[#results][2])
    assert_equal(0, #coordinator.GetDB().disputes.order)
  end)

  it("does not send the previous guild's pending work after a scope change", function()
    local world, request = setup()
    local player = world:Activate(PLAYER)
    world:TakePackets()
    _G.GetGuildInfo = function() return "DifferentGuild", "Member", 3, "Realm" end
    world:Advance(61)
    player.RequestDelivery.Pump()
    assert_equal(0, #world:TakePackets())
    assert_nil(player.RequestDelivery.GetStatus(request.requestId))
    assert_equal(0, #player.Disputes.ListForPlayer(PLAYER))
  end)

  it("fails malformed authority and snapshot shapes closed without runtime exceptions", function()
    local world, request = setup()
    local player = world:Activate(PLAYER)
    local pending = select(2, next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    local malformed = player.DeepCopy(pending.message)
    malformed.authority = 1
    local coordinator = world:Activate(COORDINATOR)
    local accepted, reason = coordinator.RequestDelivery.Receive(malformed, PLAYER)
    assert_false(accepted); assert_equal("REQUEST_AUTHORITY_CHANGED", reason)
    local snapshot = {
      operationId = "synthetic-snapshot", requestId = request.requestId, kind = "snapshot",
      guildScope = player.GetGuildKey(), revision = 2, authority = pending.message.authority,
      owner = PLAYER, projection = "owner",
      body = { requestId = request.requestId, revision = 2, status = "Open", category = "other",
        note = "", evidence = {}, replies = {}, timeline = 123 },
    }
    player = world:Activate(PLAYER)
    accepted, reason = player.RequestDelivery.Receive(snapshot, COORDINATOR)
    assert_false(accepted); assert_equal("INVALID_REQUEST_SNAPSHOT", reason)
    snapshot.body.timeline = {}
    snapshot.projection = "officer"
    accepted, reason = player.RequestDelivery.Receive(snapshot, COORDINATOR)
    assert_false(accepted); assert_equal("REQUEST_PRIVATE", reason)
  end)

  it("does not clear a pending operation for a matching receipt from the wrong actual sender", function()
    local world, request = setup()
    local player = world:Activate(PLAYER)
    local pending = select(2, next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    local acknowledgement = {
      operationId = "wrong-sender-ack", requestId = request.requestId, kind = "receipt",
      guildScope = player.GetGuildKey(), revision = pending.message.revision, authority = player.DeepCopy(pending.message.authority),
      acknowledgedId = pending.message.operationId, accepted = true,
    }
    player.RequestDelivery.Receive(acknowledgement, OFFICER)
    assert_not_nil(next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    assert_true(player.RequestDelivery.GetStatus(request.requestId).state ~= "received")
    assert_true(player.RequestDelivery.Receive(acknowledgement, COORDINATOR))
    assert_nil(next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    assert_equal("received", player.RequestDelivery.GetStatus(request.requestId).state)
  end)

  it("does not accept an old operation receipt under a replacement epoch", function()
    local world, request = setup()
    local player = world:Activate(PLAYER)
    local pending = select(2, next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    local acknowledgement = {
      operationId = "replacement-epoch-ack", requestId = request.requestId, kind = "receipt",
      guildScope = player.GetGuildKey(), revision = pending.message.revision, authority = player.DeepCopy(pending.message.authority),
      acknowledgedId = pending.message.operationId, accepted = true,
    }
    world.epoch = 2
    acknowledgement.authority.epoch = 2
    player.RequestDelivery.Receive(acknowledgement, COORDINATOR)
    assert_not_nil(next(player.GetLocalDB().requestDelivery[player.GetGuildKey()].pending))
    assert_true(player.RequestDelivery.GetStatus(request.requestId).state ~= "received")
  end)
end)
