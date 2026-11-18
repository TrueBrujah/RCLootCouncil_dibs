local clients = require("helpers.canonical_operation_clients")
local fixtures = require("helpers.dispute_fixtures")
local writer = require("helpers.canonical_writer")

local function setup()
  local world = clients.new()
  local client = world:Load("Coordinator-Realm")
  local dibs = client.dibs
  local seasonId = dibs.GetCurrentSeasonId()
  local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(client.name, seasonId, {
    transactionId = "t014-governance-original",
  }), "guild-primary"))
  local request = assert(dibs.Disputes.CreateReport({ category = "wrong_item_player",
    transactionRef = original.transactionId, note = "T014 proposal verification" }))
  world:ActivateV2()
  local intent = {
    schemaVersion = 1, guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
    operationType = "DISPUTE_TARGET_TRANSFER", requestId = request.requestId,
    requestRevision = request.revision, evidenceId = request.evidence[1].evidenceId,
    originalTransactionId = original.transactionId, reason = "T014 correction",
    actor = assert(dibs.Identity.CreateSnapshot(client.name)), timestamp = 1700000000,
    signedEntries = {},
  }
  for index, name in ipairs({ client.name, world.names[2] }) do
    intent.signedEntries[index] = {
      guildKey = intent.guildKey, ledgerId = intent.ledgerId,
      requestId = request.requestId, requestRevision = request.revision,
      evidenceId = intent.evidenceId, originalTransactionId = original.transactionId,
      memberKey = assert(dibs.Identity.CreateSnapshot(name)).memberKey, seasonId = seasonId,
      actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = index == 1 and 1 or -1,
    }
  end
  return world, client, intent
end

describe("T014 Governance Proposal Store", function()
  it("persists the actual proposal and both entry identities after reload", function()
    local _, client, intent = setup()
    local proposal = assert(client.dibs.Governance.CreateDisputeOperationProposal(intent))
    assert_equal("LEDGER_OPERATION_PROPOSAL", proposal.recordClass)
    assert_equal("PENDING", proposal.status)
    assert_true(proposal.operation.signedEntries[1].transactionId ~= proposal.operation.signedEntries[2].transactionId)
    local world = clients.new()
    local reloaded = world:Load(client.name, clients.DeepCopy(client.dibs.GetDB()))
    local resumed = assert(reloaded.dibs.Governance.GetDisputeOperationProposal(proposal.proposalId))
    assert_true(clients.DeepEqual(proposal, resumed), "reload changed the immutable proposal")
  end)

  it("reuses all generated identities for the same intent at a later time", function()
    local _, client, intent = setup()
    local first = assert(client.dibs.Governance.CreateDisputeOperationProposal(intent))
    intent.timestamp = intent.timestamp + 60
    local retry, reason = client.dibs.Governance.CreateDisputeOperationProposal(intent)
    assert_equal("IDEMPOTENT_PROPOSAL", reason)
    assert_true(clients.DeepEqual(first, retry), "retry allocated or changed stored identities")
  end)

  it("returns a detached persisted proposal without changing storage", function()
    local _, client, intent = setup()
    local proposal = assert(client.dibs.Governance.CreateDisputeOperationProposal(intent))
    local before = clients.DeepCopy(client.dibs.GetDB())
    local resumed = assert(client.dibs.Governance.GetDisputeOperationProposal(proposal.proposalId))
    resumed.operation.signedEntries[1].quantityDelta = 999
    assert_true(clients.DeepEqual(before, client.dibs.GetDB()))
  end)

  it("bounds relay retry bookkeeping at five and retains the pending intent", function()
    local _, client, intent = setup()
    local governance = client.dibs.Governance
    local proposal = assert(governance.CreateDisputeOperationProposal(intent))
    for attempt = 1, 5 do assert_equal(attempt, governance.NoteDisputeOperationRelayAttempt(proposal.proposalId)) end
    local result, reason = governance.NoteDisputeOperationRelayAttempt(proposal.proposalId)
    assert_nil(result)
    assert_equal("RELAY_ATTEMPT_LIMIT_EXCEEDED", reason)
    local retained = assert(governance.GetDisputeOperationProposal(proposal.proposalId))
    assert_equal("PENDING", retained.status)
    assert_equal(proposal.operation.operationId, retained.operation.operationId)
  end)

  it("refuses a full store without evicting a persisted proposal", function()
    local _, client, intent = setup()
    local first
    for index = 1, 100 do
      intent.reason = "T014 capacity " .. tostring(index)
      local proposal = assert(client.dibs.Governance.CreateDisputeOperationProposal(intent))
      first = first or proposal
    end
    local before = clients.DeepCopy(client.dibs.GetDB())
    intent.reason = "T014 capacity overflow"
    local result, reason = client.dibs.Governance.CreateDisputeOperationProposal(intent)
    assert_nil(result)
    assert_equal("PROPOSAL_LIMIT_EXCEEDED", reason)
    assert_true(clients.DeepEqual(before, client.dibs.GetDB()))
    assert_not_nil(client.dibs.Governance.GetDisputeOperationProposal(first.proposalId))
  end)

  it("rejects acceptance and retry after the authority epoch changes", function()
    local _, client, intent = setup()
    local dibs = client.dibs
    local proposal = assert(dibs.Governance.CreateDisputeOperationProposal(intent))
    writer.enable(dibs)
    dibs.GetDB().governance.authority.ledgerEpoch = proposal.ledgerEpoch + 1
    local before = clients.DeepCopy(dibs.GetDB())
    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { proposalId = proposal.proposalId })
    assert_false(result.ok)
    assert_equal("STALE_AUTHORITY", result.reasonCode)
    local retry, reason = dibs.Governance.CreateDisputeOperationProposal(intent)
    assert_nil(retry)
    assert_equal("STALE_AUTHORITY", reason)
    assert_true(clients.DeepEqual(before, dibs.GetDB()), "stale authority changed accounting or proposal storage")
  end)
end)
