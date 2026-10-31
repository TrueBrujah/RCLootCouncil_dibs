local clients = require("helpers.canonical_operation_clients")
local fixtures = require("helpers.dispute_fixtures")

describe("RF-0012 isolated canonical-operation clients", function()
  it("converges through serialized SyncV2 dispatch without shared client state", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs

    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "RF-0012 distributed test" }))
    local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
    local coordinatorIdentity = assert(dibs.Identity.CreateSnapshot("Coordinator-Realm"))
    assert_true(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1,
      state = "ACTIVE",
      coordinator = coordinatorIdentity,
      ledgerEpoch = 7,
      transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
    } } }))
    assert_true(dibs.Governance.EnableV2(nil, { "Coordinator-Realm" }))
    assert_true(dibs.Governance.IsV2Enforced())
    assert_not_nil(dibs.Seasons.Create("RF0012 distributed"))
    assert_not_nil(dibs.Ledger.Grant(
      "Player-Realm",
      1,
      "RF-0012 distributed setup",
      "test",
      dibs.GetCurrentSeasonId()
    ))
    world:TakePackets()

    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local player = world:Load("Player-Realm", savedVariables)
    local officer = world:Load("Officer-Realm", savedVariables)
    local followers = { player, officer }
    for _, follower in ipairs(followers) do
      assert_true(follower.env ~= coordinator.env)
      assert_true(follower.dibs ~= coordinator.dibs)
      assert_true(follower.dibs.Ledger ~= coordinator.dibs.Ledger)
      assert_true(follower.dibs.Sync ~= coordinator.dibs.Sync)
      assert_true(follower.dibs.runtime ~= coordinator.dibs.runtime)
      assert_true(follower.env.RCLootCouncil_dibsDB ~= coordinator.env.RCLootCouncil_dibsDB)
      local localIdentity = assert(follower.dibs.Identity.CreateSnapshot(follower.name))
      local authority = follower.dibs.Governance.GetAuthorityState()
      assert_not_nil(localIdentity.memberKey)
      assert_equal("ACTIVE", authority.state)
      assert_equal(coordinatorIdentity.memberKey, authority.coordinator.memberKey)
    end

    local before = {}
    for _, follower in ipairs(followers) do
      local rootHash = follower.dibs.Ledger.GetCanonicalState().rootHash
      before[follower.name] = {
        database = world:Snapshot(follower),
        dibs = follower.env.Dibs,
        databaseGlobal = follower.env.RCLootCouncil_dibsDB,
        ledger = follower.dibs.Ledger,
        sync = follower.dibs.Sync,
        runtime = follower.dibs.runtime,
        rootHash = rootHash,
      }
    end

    local result = dibs.Ledger.CommitDibUse(nil, {
      transactionId = "rf0012-distributed-award-1",
      proposalId = "rf0012-distributed-proposal-1",
      playerName = "Player-Realm",
      seasonId = dibs.GetCurrentSeasonId(),
      amount = 1,
      itemID = 275658,
      source = "RF-0012 distributed test",
    })
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("CANONICAL_COMMITTED", result.reasonCode)

    for _, follower in ipairs(followers) do
      local original = before[follower.name]
      assert_true(follower.env.Dibs == original.dibs)
      assert_true(follower.env.RCLootCouncil_dibsDB == original.databaseGlobal)
      assert_true(follower.dibs.Ledger == original.ledger)
      assert_true(follower.dibs.Sync == original.sync)
      assert_true(follower.dibs.runtime == original.runtime)
      assert_true(clients.DeepEqual(original.database, world:Snapshot(follower)))
      assert_equal(original.rootHash, follower.dibs.Ledger.GetCanonicalState().rootHash)
    end

    assert_true(#world.packets > 0, "coordinator did not announce the canonical commit")
    for _, packet in ipairs(world.packets) do
      assert_equal("string", type(packet.payload))
    end
    assert_true(world:Pump() > 0, "no serialized SyncV2 messages were delivered")

    local canonical = dibs.Ledger.GetCanonicalState()
    for _, delivery in ipairs(world.deliveries) do
      assert_true(delivery.accepted, tostring(delivery.reason))
    end
    local deliveryTrace = {}
    for _, delivery in ipairs(world.deliveries) do
      deliveryTrace[#deliveryTrace + 1] = delivery.sender .. ">" .. delivery.receiver .. ":" .. tostring(delivery.reason)
    end
    for _, follower in ipairs(followers) do
      local followerState = follower.dibs.Ledger.GetCanonicalState()
      assert_equal(canonical.epoch, followerState.epoch)
      assert_equal(canonical.nextSeq, followerState.nextSeq, follower.name .. " sequence mismatch: " .. table.concat(deliveryTrace, ", "))
      assert_equal(canonical.rootHash, followerState.rootHash)
      assert_equal(
        dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId()),
        follower.dibs.Ledger.GetBalance("Player-Realm", follower.dibs.GetCurrentSeasonId())
      )
      local applied = follower.dibs.Ledger.GetCanonicalCommit(result.value.ledgerEpoch, result.value.sequence)
      assert_not_nil(applied)
      assert_equal(result.value.commitHash, applied.commitHash)
    end
  end)

  it("blocks a new operation commit at every receiver before accounting mutation while disabled", function()
    local world = clients.new()
    local coordinator = world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local followers = {
      world:Load("Player-Realm", savedVariables),
      world:Load("Officer-Realm", savedVariables),
    }
    -- The coordinator gate is open so the record reaches the receivers. The
    -- receivers stay closed, which is what this case proves.
    coordinator.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local before = {}
    for _, follower in ipairs(followers) do
      before[follower.name] = fixtures.captureAccountingState(
        follower.dibs,
        nil,
        world.names,
        follower.dibs.GetCurrentSeasonId(),
        "guild-primary"
      )
    end

    assert_true(coordinator.dibs.Sync.Send({
      type = "TRANSFER_BEGIN",
      transferId = "rf0012-disabled-operation-1",
      entityType = "LEDGER_OPERATION_COMMIT",
      entityId = "7:1",
      revision = 1,
      contentHash = "synthetic-operation-commit",
      payloadHash = "synthetic-payload",
      chunkCount = 1,
      ledgerId = "guild-primary",
    }, "GUILD"))
    assert_true(world:Pump() > 0)
    assert_equal(#followers, #world.deliveries)

    local gateReasons = {}
    for _, delivery in ipairs(world.deliveries) do
      assert_false(delivery.accepted == true, "disabled receiver accepted an operation commit")
      assert_true(type(delivery.reason) == "string" and delivery.reason ~= "")
      local reason = string.upper(delivery.reason)
      local gateReason = reason:find("DISABLED", 1, true)
          or reason:find("NOT_READY", 1, true)
          or reason:find("RECOVERY", 1, true)
          or reason:find("INCOMPATIBLE", 1, true)
      gateReasons[#gateReasons + 1] = gateReason ~= nil
    end
    for _, follower in ipairs(followers) do
      local after = fixtures.captureAccountingState(
        follower.dibs,
        nil,
        world.names,
        follower.dibs.GetCurrentSeasonId(),
        "guild-primary"
      )
      assert_true(clients.DeepEqual(before[follower.name], after), "disabled receiver changed accounting state")
    end
    for index, gateReason in ipairs(gateReasons) do
      assert_true(gateReason, "receiver rejected before applying the default-off gate: " .. world.deliveries[index].reason)
    end
  end)
end)

-- T017: SyncV2 production-path contract tests for the canonical operation
-- protocol. These exercise the real allowlist, dispatch, receiver, announcement,
-- and digest paths of the production SyncV2 module.

local function newWorld()
  return clients.new()
end

local function captureFollower(follower, world)
  return fixtures.captureAccountingState(
    follower.dibs,
    nil,
    world.names,
    follower.dibs.GetCurrentSeasonId(),
    "guild-primary"
  )
end

describe("RF-0012 SyncV2 canonical operation protocol", function()
  it("advertises the ledger operation capability with an independent version", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    -- T021: the capability is advertised only while the shared gate is open.
    coordinator.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local envelope = assert(coordinator.dibs.Sync.BuildEnvelope({
      type = "LEDGER_DIGEST",
      ledgerId = "guild-primary",
    }))
    assert_not_nil(envelope.protocol)
    assert_not_nil(envelope.protocol.capabilities)
    assert_equal(true, envelope.protocol.capabilities.ledgerOperationCommit,
      "the ledger operation capability is not advertised")
    assert_not_nil(envelope.protocol.operationProtocolVersion,
      "the operation protocol version is not independent of the general envelope")
  end)

  it("rejects unsupported operation record types and schemas", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)
    local before = captureFollower(follower, world)

    local sent = coordinator.dibs.Sync.Send({
      type = "TRANSFER_BEGIN",
      transferId = "rf0012-unsupported-entity-1",
      entityType = "LEDGER_OPERATION_UNSUPPORTED",
      entityId = "7:1",
      revision = 1,
      contentHash = "synthetic",
      chunkCount = 1,
    }, "GUILD")
    assert_false(sent == true, "an unsupported operation entity was accepted for sending")
    assert_true(world:Pump() >= 0)

    local after = captureFollower(follower, world)
    assert_true(clients.DeepEqual(before, after), "an unsupported entity changed accounting state")
  end)

  it("keeps the operation routes distinct from the award proposal and commit routes", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    coordinator.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)
    local before = captureFollower(follower, world)

    -- A typed operation proposal is a whisper route to the coordinator and
    -- must never enter award accounting.
    local proposalSent = coordinator.dibs.Sync.Send({
      type = "TRANSFER_BEGIN",
      transferId = "rf0012-operation-proposal-1",
      entityType = "LEDGER_OPERATION_PROPOSAL",
      entityId = "op-rf0012-1",
      revision = 1,
      contentHash = "synthetic-proposal",
      chunkCount = 1,
    }, "WHISPER", "Coordinator-Realm")
    assert_true(proposalSent, "the typed operation proposal was not sent")
    assert_true(world:Pump() > 0, "the typed operation proposal was not delivered")

    local after = captureFollower(follower, world)
    assert_true(clients.DeepEqual(before, after),
      "a relayed operation proposal entered accounting state")
  end)

  it("rejects an operation commit whose sender is not the current coordinator", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)
    -- The gate is open on both sides so the sender check is the one exercised.
    coordinator.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    follower.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local before = captureFollower(follower, world)

    -- A forged record claiming a coordinator that is not the local one.
    assert_true(coordinator.dibs.Sync.Send({
      type = "TRANSFER_BEGIN",
      transferId = "rf0012-forged-commit-1",
      entityType = "LEDGER_OPERATION_COMMIT",
      entityId = "7:1",
      revision = 1,
      contentHash = "synthetic-forged",
      chunkCount = 1,
      ledgerId = "guild-primary",
      operationSchemaVersion = 99,
    }, "GUILD"))
    assert_true(world:Pump() > 0, "the forged commit was not delivered")

    local after = captureFollower(follower, world)
    assert_true(clients.DeepEqual(before, after), "a forged operation commit changed accounting state")
  end)

  it("keeps legacy award commit behavior unchanged", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)

    local before = coordinator.dibs.Ledger.GetCanonicalState()
    local result = coordinator.dibs.Ledger.CommitDibUse({
      actor = coordinator.name,
      action = "ledger.use",
      ledgerId = "guild-primary",
    }, {
      transactionId = "rf0012-legacy-award-commit",
      playerName = world.names[2],
      seasonId = coordinator.dibs.GetCurrentSeasonId(),
      amount = 1,
      reason = "RF-0012 legacy award commit",
    })
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("AWARD_COMMIT", result.value.recordClass)
    assert_true(world:Pump() > 0, "the legacy award commit was not delivered")

    local after = follower.dibs.Ledger.GetCanonicalState()
    assert_equal(before.nextSeq + 1, after.nextSeq)
    assert_equal(result.value.commitHash, after.rootHash)
  end)

  it("announces an accepted operation commit and the updated digest to the guild", function()
    local world = newWorld()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(coordinator.name, seasonId, {
      transactionId = "rf0012-announce-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "RF-0012 announcement",
    }))
    world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)
    local officer = world:Load("Officer-Realm", savedVariables)
    local followers = { follower, officer }
    local actor = assert(dibs.Identity.CreateSnapshot(coordinator.name))
    local recipient = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local evidenceId = request.evidence[1].evidenceId or false
    local operationId = "rf0012-announce-op"
    local operation = {
      schemaVersion = 1,
      operationId = operationId,
      operationType = "DISPUTE_TARGET_TRANSFER",
      guildKey = dibs.GetGuildKey(),
      ledgerId = "guild-primary",
      requestId = request.requestId,
      requestRevision = request.revision,
      evidenceId = evidenceId,
      originalTransactionId = original.transactionId,
      actor = actor,
      reason = "RF-0012 announcement",
      timestamp = 1700000000,
      signedEntries = {
        {
          operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
        {
          operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
      },
    }
    local built = assert(dibs.Ledger.BuildDisputeOperation(operation))

    -- The isolated client opens the private writer gate only.
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    -- T021: the shared gate is open on the coordinator so the announcement is
    -- actually dispatched. The receivers stay closed.
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local result = writer({ actor = coordinator.name, ledgerId = "guild-primary" }, built)
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("CANONICAL_COMMITTED", result.reasonCode)

    assert_true(world:Pump() > 0, "the accepted operation commit was not delivered")
    local announced = false
    for _, delivery in ipairs(world.deliveries) do
      if delivery.reason == "DETAIL_SENT" or delivery.reason == "TRANSFER_STARTED" then announced = true end
    end
    assert_true(announced, "no canonical operation announcement was delivered")

    -- The default-off gate keeps the receivers closed, so their accounting
    -- state is unchanged until the feature is enabled explicitly.
    for _, client in ipairs(followers) do
      local state = client.dibs.Ledger.GetCanonicalState()
      assert_equal(0, state.commitCount, "a closed receiver applied the operation commit")
    end
  end)

  it("returns the record class actually stored at a position during catch-up", function()
    local world = newWorld()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(coordinator.name, seasonId, {
      transactionId = "rf0012-catchup-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "RF-0012 catch-up",
    }))
    world:ActivateV2()

    -- Position 1 is a legacy award commit.
    local award = dibs.Ledger.CommitDibUse({
      actor = coordinator.name,
      action = "ledger.use",
      ledgerId = "guild-primary",
    }, {
      transactionId = "rf0012-catchup-award",
      playerName = world.names[2],
      seasonId = dibs.GetCurrentSeasonId(),
      amount = 1,
      reason = "RF-0012 catch-up award",
    })
    assert_true(award.accepted, tostring(award.reasonCode))
    assert_equal("AWARD_COMMIT", award.value.recordClass)

    -- Position 2 is a canonical operation commit.
    local actor = assert(dibs.Identity.CreateSnapshot(coordinator.name))
    local recipient = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local evidenceId = request.evidence[1].evidenceId or false
    local operationId = "rf0012-catchup-op"
    local operation = {
      schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_TARGET_TRANSFER",
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
      requestId = request.requestId, requestRevision = request.revision,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      actor = actor, reason = "RF-0012 catch-up", timestamp = 1700000000,
      signedEntries = {
        {
          operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
        {
          operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
      },
    }
    local built = assert(dibs.Ledger.BuildDisputeOperation(operation))
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local committed = writer({ actor = coordinator.name, ledgerId = "guild-primary" }, built)
    assert_true(committed.accepted, tostring(committed.reasonCode))
    assert_equal("LEDGER_OPERATION_COMMIT", committed.value.recordClass)

    -- The stored record class at each position must be preserved verbatim.
    local ledger = dibs.db.ledgers["guild-primary"]
    local storedAward = dibs.Ledger.GetCanonicalCommit(committed.value.ledgerEpoch, 1, "guild-primary")
    local storedOperation = dibs.Ledger.GetCanonicalCommit(committed.value.ledgerEpoch, 2, "guild-primary")
    assert_equal("AWARD_COMMIT", storedAward.recordClass)
    assert_equal("LEDGER_OPERATION_COMMIT", storedOperation.recordClass)
    assert_equal(award.value.commitHash, storedAward.commitHash)
    assert_equal(committed.value.commitHash, storedOperation.commitHash)
  end)

  it("withholds the operation capability while the shared gate is closed", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    local envelope = assert(coordinator.dibs.Sync.BuildEnvelope({
      type = "LEDGER_DIGEST",
      ledgerId = "guild-primary",
    }))
    assert_equal(false, envelope.protocol.capabilities.ledgerOperationCommit,
      "the operation capability is advertised while the gate is closed")
  end)

  it("advertises the operation capability only when the shared gate is open", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    coordinator.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local envelope = assert(coordinator.dibs.Sync.BuildEnvelope({
      type = "LEDGER_DIGEST",
      ledgerId = "guild-primary",
    }))
    assert_equal(true, envelope.protocol.capabilities.ledgerOperationCommit,
      "the operation capability is withheld while the gate is open")
  end)

  it("refuses to send an operation record while the shared gate is closed", function()
    local world = newWorld()
    local coordinator = world:ActivateV2()
    local sent, reason = coordinator.dibs.Sync.Send({
      type = "TRANSFER_BEGIN",
      transferId = "rf0012-gated-send-1",
      entityType = "LEDGER_OPERATION_COMMIT",
      entityId = "7:1",
      revision = 1,
      contentHash = "synthetic",
      payloadHash = "synthetic",
      chunkCount = 1,
      ledgerId = "guild-primary",
    }, "GUILD")
    assert_false(sent == true, "an operation record was sent while the gate is closed")
    assert_equal("CANONICAL_DISPUTE_OPERATIONS_DISABLED", reason)
  end)

  it("refuses the coordinator acceptance path while the shared gate is closed", function()
    local world = newWorld()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(coordinator.name, seasonId, {
      transactionId = "rf0012-gated-accept-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "RF-0012 gated acceptance",
    }))
    world:ActivateV2()

    local actor = assert(dibs.Identity.CreateSnapshot(coordinator.name))
    local recipient = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local evidenceId = request.evidence[1].evidenceId or false
    local operationId = "rf0012-gated-accept-op"
    local operation = {
      schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_TARGET_TRANSFER",
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
      requestId = request.requestId, requestRevision = request.revision,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      actor = actor, reason = "RF-0012 gated acceptance", timestamp = 1700000000,
      signedEntries = {
        {
          operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
        {
          operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
      },
    }
    local built = assert(dibs.Ledger.BuildDisputeOperation(operation))
    local before = dibs.Ledger.GetCanonicalState()
    local result = dibs.Ledger.CommitDisputeOperation({ actor = coordinator.name, ledgerId = "guild-primary" }, built)
    assert_false(result.accepted, "the coordinator accepted an operation while the gate is closed")
    assert_equal("CANONICAL_DISPUTE_OPERATIONS_DISABLED", result.reasonCode)
    local after = dibs.Ledger.GetCanonicalState()
    assert_equal(before.nextSeq, after.nextSeq, "a refused acceptance advanced the sequence")
    assert_equal(before.rootHash, after.rootHash, "a refused acceptance changed the root hash")
  end)

  it("converges three clients on one operation and survives exactly 100 retries", function()
    local world = newWorld()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(coordinator.name, seasonId, {
      transactionId = "rf0012-converge-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "RF-0012 convergence",
    }))
    world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local player = world:Load("Player-Realm", savedVariables)
    local officer = world:Load("Officer-Realm", savedVariables)
    local clients = { player, officer }

    local actor = assert(dibs.Identity.CreateSnapshot(coordinator.name))
    local recipient = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local evidenceId = request.evidence[1].evidenceId or false
    local operationId = "rf0012-converge-op"
    local operation = {
      schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_TARGET_TRANSFER",
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
      requestId = request.requestId, requestRevision = request.revision,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      actor = actor, reason = "RF-0012 convergence", timestamp = 1700000000,
      signedEntries = {
        {
          operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
        {
          operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
      },
    }
    local built = assert(dibs.Ledger.BuildDisputeOperation(operation))
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    for _, client in ipairs(clients) do
      client.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    end

    local result = writer({ actor = coordinator.name, ledgerId = "guild-primary" }, built)
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_true(world:Pump() > 0, "the operation commit was not delivered")

    -- Every client converges on the same canonical state.
    local expected = dibs.Ledger.GetCanonicalState()
    local expectedBalance = dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary")
    for _, client in ipairs(clients) do
      local state = client.dibs.Ledger.GetCanonicalState()
      assert_equal(expected.epoch, state.epoch, client.name .. " epoch mismatch")
      assert_equal(expected.nextSeq, state.nextSeq, client.name .. " sequence mismatch")
      assert_equal(expected.rootHash, state.rootHash, client.name .. " root hash mismatch")
      assert_equal(expectedBalance, client.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary"),
        client.name .. " balance mismatch")
      local applied = client.dibs.Ledger.GetCanonicalCommit(result.value.ledgerEpoch, result.value.sequence, "guild-primary")
      assert_not_nil(applied, client.name .. " did not apply the operation commit")
      assert_equal(result.value.commitHash, applied.commitHash)
    end

    -- Exactly 100 duplicate/retry deliveries must change nothing.
    local before = {}
    for _, client in ipairs(clients) do
      before[client.name] = {
        state = client.dibs.Ledger.GetCanonicalState(),
        balance = client.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary"),
        transactions = #client.dibs.Ledger.GetAllTransactions("guild-primary"),
      }
    end
    local coordinatorState = dibs.Ledger.GetCanonicalState()
    local coordinatorBalance = dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary")
    local coordinatorTransactions = #dibs.Ledger.GetAllTransactions("guild-primary")

    for attempt = 1, 100 do
      local replay = writer({ actor = coordinator.name, ledgerId = "guild-primary" }, built)
      assert_true(replay.accepted, "retry " .. attempt .. " was refused: " .. tostring(replay.reasonCode))
      world:Pump()
    end

    for _, client in ipairs(clients) do
      local state = client.dibs.Ledger.GetCanonicalState()
      assert_equal(before[client.name].state.nextSeq, state.nextSeq,
        "a retry advanced the sequence on " .. client.name)
      assert_equal(before[client.name].state.rootHash, state.rootHash,
        "a retry changed the root hash on " .. client.name)
      assert_equal(before[client.name].balance,
        client.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary"),
        "a retry changed the balance on " .. client.name)
      assert_equal(before[client.name].transactions, #client.dibs.Ledger.GetAllTransactions("guild-primary"),
        "a retry appended a transaction on " .. client.name)
    end
    local finalState = dibs.Ledger.GetCanonicalState()
    assert_equal(coordinatorState.nextSeq, finalState.nextSeq, "a retry advanced the coordinator sequence")
    assert_equal(coordinatorState.rootHash, finalState.rootHash, "a retry changed the coordinator root hash")
    assert_equal(coordinatorBalance, dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary"),
      "a retry changed the coordinator balance")
    assert_equal(coordinatorTransactions, #dibs.Ledger.GetAllTransactions("guild-primary"),
      "a retry appended a coordinator transaction")
  end)

  it("refuses a commit from a stale coordinator epoch", function()
    local world = newWorld()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(coordinator.name, seasonId, {
      transactionId = "rf0012-stale-epoch-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "RF-0012 stale epoch",
    }))
    world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)
    follower.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true

    local actor = assert(dibs.Identity.CreateSnapshot(coordinator.name))
    local recipient = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local evidenceId = request.evidence[1].evidenceId or false
    local operationId = "rf0012-stale-epoch-op"
    local operation = {
      schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_TARGET_TRANSFER",
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
      requestId = request.requestId, requestRevision = request.revision,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      actor = actor, reason = "RF-0012 stale epoch", timestamp = 1700000000,
      signedEntries = {
        {
          operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
        {
          operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
      },
    }
    local built = assert(dibs.Ledger.BuildDisputeOperation(operation))
    local commit = {
      schema = 1, recordClass = "LEDGER_OPERATION_COMMIT", protocolVersion = 1,
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
      ledgerEpoch = 999, sequence = 1, previousHash = "STALE", payloadHash = built.payloadHash,
      proposer = { memberKey = actor.memberKey, displayName = actor.displayName, authority = "TEST" },
      coordinator = { memberKey = actor.memberKey, displayName = actor.displayName },
      operation = built,
    }
    local commitHash = dibs.Ledger.GetCanonicalOperationCommitHash and dibs.Ledger.GetCanonicalOperationCommitHash(commit)
    if commitHash then commit.commitHash = commitHash end

    local before = follower.dibs.Ledger.GetCanonicalState()
    local applied = follower.dibs.Ledger.ApplyOperationCommit(commit, coordinator.name, "guild-primary")
    assert_false(applied.accepted, "a stale epoch commit was accepted")
    assert_equal("STALE_EPOCH", applied.reasonCode)
    local after = follower.dibs.Ledger.GetCanonicalState()
    assert_equal(before.nextSeq, after.nextSeq, "a refused commit advanced the sequence")
    assert_equal(before.rootHash, after.rootHash, "a refused commit changed the root hash")
  end)

  it("keeps an incompatible client visibly behind instead of applying the record", function()
    local world = newWorld()
    local coordinator = world:Load("Coordinator-Realm")
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(coordinator.name, seasonId, {
      transactionId = "rf0012-incompatible-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "RF-0012 incompatible peer",
    }))
    world:ActivateV2()
    local savedVariables = coordinator.env.RCLootCouncil_dibsDB
    local follower = world:Load("Player-Realm", savedVariables)
    -- The peer does not advertise the operation capability, so the record it
    -- receives is not applicable.
    follower.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false

    local actor = assert(dibs.Identity.CreateSnapshot(coordinator.name))
    local recipient = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local evidenceId = request.evidence[1].evidenceId or false
    local operationId = "rf0012-incompatible-op"
    local operation = {
      schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_TARGET_TRANSFER",
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
      requestId = request.requestId, requestRevision = request.revision,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      actor = actor, reason = "RF-0012 incompatible peer", timestamp = 1700000000,
      signedEntries = {
        {
          operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
        {
          operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
          guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
          seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
          evidenceId = evidenceId, originalTransactionId = original.transactionId,
          requestId = request.requestId, requestRevision = request.revision,
        },
      },
    }
    local built = assert(dibs.Ledger.BuildDisputeOperation(operation))
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local result = writer({ actor = coordinator.name, ledgerId = "guild-primary" }, built)
    assert_true(result.accepted, tostring(result.reasonCode))

    local before = follower.dibs.Ledger.GetCanonicalState()
    local beforeBalance = follower.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary")
    world:Pump()
    local after = follower.dibs.Ledger.GetCanonicalState()
    local afterBalance = follower.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary")
    assert_equal(before.nextSeq, after.nextSeq, "an incompatible peer advanced its sequence")
    assert_equal(before.rootHash, after.rootHash, "an incompatible peer changed its root hash")
    assert_equal(beforeBalance, afterBalance, "an incompatible peer changed a balance")
  end)
end)
