local clients = require("helpers.canonical_operation_clients")
local fixtures = require("helpers.dispute_fixtures")

local function replaceUpvalue(fn, name, value)
  assert_true(type(debug) == "table" and type(debug.getupvalue) == "function"
    and type(debug.setupvalue) == "function")
  for index = 1, 64 do
    local upvalueName = debug.getupvalue(fn, index)
    if upvalueName == nil then break end
    if upvalueName == name then
      debug.setupvalue(fn, index, value)
      return
    end
  end
  error("private Ledger test seam not found: " .. name, 2)
end

local function enableCanonicalWriter(client)
  local writer = client.dibs.Ledger.CommitDisputeOperation
  replaceUpvalue(writer, "DISPUTE_OPERATION_WRITES_ENABLED", true)
  replaceUpvalue(writer, "operationReadinessProbe", function() return true end)
  replaceUpvalue(writer, "operationFailureProbe", function() return nil end)
  client.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
end

describe("T014 Governance Proposal Store", function()
  local function setup()
    local world = clients.new()
    local client = world:Load("Coordinator-Realm")
    local dibs = client.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(client.name, seasonId, {
      transactionId = "t014-governance-original",
    }), "guild-primary"))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "T014 persisted proposal regression",
    }))
    world:ActivateV2()
    local target = assert(dibs.Identity.CreateSnapshot(world.names[2]))
    local details = {
      operationType = "DISPUTE_TARGET_TRANSFER",
      ledgerId = "guild-primary",
      requestId = request.requestId,
      requestRevision = request.revision,
      evidenceId = request.evidence[1].evidenceId,
      originalTransactionId = original.transactionId,
      reason = "T014 proposal test correction",
      signedEntries = {
        { memberKey = original.memberKey, seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1 },
        { memberKey = target.memberKey, seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1 },
      },
    }
    return world, client, details
  end

  it("Creates a stable correction proposal and persists it after reload", function()
    local _, client, details = setup()
    local governance = client.dibs.Governance
    local proposal = assert(governance.CreateDisputeProposal(client.name, details))
    assert_equal("LEDGER_OPERATION_PROPOSAL", proposal.recordClass)
    assert_equal("PENDING", proposal.status)
    assert_equal(proposal.operation.operationId .. "-1", proposal.operation.signedEntries[1].transactionId)
    assert_equal(proposal.operation.operationId .. "-2", proposal.operation.signedEntries[2].transactionId)

    local savedVariables = clients.DeepCopy(client.dibs.GetDB())
    local reloadedWorld = clients.new()
    local reloaded = reloadedWorld:Load(client.name, savedVariables)
    local resumed = assert(reloaded.dibs.Governance.ResumeDisputeProposal(client.name, proposal.proposalId))
    assert_equal(proposal.proposalId, resumed.proposalId)
    assert_equal(proposal.operation.operationId, resumed.operation.operationId)
    assert_equal(proposal.operation.payloadHash, resumed.operation.payloadHash)
    assert_equal(proposal.operation.signedEntries[1].transactionId, resumed.operation.signedEntries[1].transactionId)
  end)

  it("Deduplicates retries with same intent", function()
    local _, client, details = setup()
    local governance = client.dibs.Governance
    local first = assert(governance.CreateDisputeProposal(client.name, details))
    local retry, status = governance.CreateDisputeProposal(client.name, details)
    assert_equal("IDEMPOTENT_PROPOSAL", status)
    assert_equal(first.proposalId, retry.proposalId)
    assert_equal(first.operation.operationId, retry.operation.operationId)
    assert_equal(first.operation.payloadHash, retry.operation.payloadHash)
    assert_equal(first.operation.signedEntries[2].transactionId, retry.operation.signedEntries[2].transactionId)
  end)

  it("Resumes pending proposal without allocating new IDs", function()
    local _, client, details = setup()
    local governance = client.dibs.Governance
    local proposal = assert(governance.CreateDisputeProposal(client.name, details))
    local resumed, status = governance.ResumeDisputeProposal(client.name, proposal.proposalId)
    assert_equal("RESUMED", status)
    assert_equal(proposal.proposalId, resumed.proposalId)
    assert_equal(proposal.operation.operationId, resumed.operation.operationId)
    assert_equal(proposal.operation.signedEntries[1].transactionId, resumed.operation.signedEntries[1].transactionId)
  end)

  it("Bounds relay retries at five without losing the persisted proposal", function()
    local _, client, details = setup()
    local governance = client.dibs.Governance
    local proposal = assert(governance.CreateDisputeProposal(client.name, details))
    for expectedAttempt = 1, 5 do
      local attempt, status = governance.NoteDisputeProposalRelayAttempt(client.name, proposal.proposalId)
      assert_equal(expectedAttempt, attempt)
      assert_equal("RELAY_PENDING", status)
    end
    local attempt, reason = governance.NoteDisputeProposalRelayAttempt(client.name, proposal.proposalId)
    assert_nil(attempt)
    assert_equal("RELAY_ATTEMPTS_EXHAUSTED", reason)
    assert_equal(proposal.operation.operationId,
      assert(governance.GetDisputeProposal(proposal.proposalId)).operation.operationId)
  end)

  it("Refuses a full proposal store without evicting an existing proposal", function()
    local _, client, details = setup()
    local governance = client.dibs.Governance
    local first
    for index = 1, 100 do
      local intent = clients.DeepCopy(details)
      intent.reason = "T014 proposal cap " .. tostring(index)
      local proposal, reason = governance.CreateDisputeProposal(client.name, intent)
      assert_not_nil(proposal, reason)
      if index == 1 then first = proposal end
    end
    local overflow = clients.DeepCopy(details)
    overflow.reason = "T014 proposal cap overflow"
    local proposal, reason = governance.CreateDisputeProposal(client.name, overflow)
    assert_nil(proposal)
    assert_equal("DISPUTE_PROPOSAL_LIMIT_EXCEEDED", reason)
    assert_equal(first.proposalId, assert(governance.GetDisputeProposal(first.proposalId)).proposalId)
  end)

  it("Rejects proposal with stale authority", function()
    local _, client, details = setup()
    local governance = client.dibs.Governance
    local proposal = assert(governance.CreateDisputeProposal(client.name, details))
    client.dibs.GetDB().governance.authority.ledgerEpoch = proposal.ledgerEpoch + 1
    local result, reason = governance.AcceptDisputeProposal(client.name, proposal.proposalId)
    assert_nil(result)
    assert_equal("STALE_AUTHORITY", reason)
  end)

  it("Relays an Officer proposal to the coordinator and accepts it once", function()
    local world, coordinator, details = setup()
    local officer = world:Load("Officer-Realm", clients.DeepCopy(coordinator.dibs.GetDB()))
    coordinator.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    officer.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local proposal = assert(officer.dibs.Governance.CreateDisputeProposal(officer.name, details))
    assert_equal("Officer-Realm", proposal.proposer.displayName)
    local relayed, relayStatus = officer.dibs.Sync.RelayDisputeProposal(proposal)
    assert_true(relayed, relayStatus)
    assert_true(world:Pump() > 0, "serialized proposal and receipt packets were not delivered")
    local received = assert(coordinator.dibs.Governance.GetDisputeProposal(proposal.proposalId))
    assert_equal("Officer-Realm", received.proposer.displayName)
    assert_equal("RELAY_ACKED", assert(officer.dibs.Governance.GetDisputeProposal(proposal.proposalId)).relayStatus)
    for _, delivery in ipairs(world.deliveries) do
      assert_true(delivery.accepted, tostring(delivery.reason))
    end

    enableCanonicalWriter(coordinator)
    local result, acceptStatus = coordinator.dibs.Governance.AcceptDisputeProposal(coordinator.name, proposal.proposalId)
    assert_not_nil(result)
    assert_equal("ACCEPTED_IN_SESSION", acceptStatus)
    local stored = assert(coordinator.dibs.Governance.GetDisputeProposal(proposal.proposalId))
    assert_equal("ACCEPTED_IN_SESSION", stored.status)
    assert_equal("RECEIVED", select(2, officer.dibs.Governance.AcknowledgeDisputeProposal(
      officer.name, proposal.proposalId, proposal.coordinator.memberKey)))

    local replay, replayStatus = coordinator.dibs.Governance.AcceptDisputeProposal(coordinator.name, proposal.proposalId)
    assert_not_nil(replay)
    assert_equal("ACCEPTED_IN_SESSION", replayStatus)
    assert_equal(1, coordinator.dibs.Ledger.GetCanonicalState("guild-primary").nextSeq - 1)

    local changedIntent = clients.DeepCopy(details)
    changedIntent.reason = "A different operation for the already accepted revision"
    local secondProposal, secondReason = coordinator.dibs.Governance.CreateDisputeProposal(
      coordinator.name, changedIntent)
    assert_nil(secondProposal)
    assert_equal("DISPUTE_REVISION_ALREADY_CORRECTED", secondReason)
  end)
end)
