local loader = require("helpers.load_addon")
local clients = require("helpers.canonical_operation_clients")
local writer = require("helpers.canonical_writer")

local function proposedResolution()
  local world = clients.new()
  local client = world:Load("Coordinator-Realm")
  world:ActivateV2()
  local dibs = client.dibs
  writer.enable(dibs)
  local request = assert(dibs.Disputes.CreateReport({ category = "other", note = "Protected operation fixture" }))
  local operation = assert(dibs.Ledger.BuildDisputeOperation({
    operationId = "protected-resolution", operationType = "DISPUTE_ATTRIBUTION_RESOLUTION",
    schemaVersion = 1, guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
    requestId = request.requestId, requestRevision = request.revision, signedEntries = {},
    originalTransactionId = false, evidenceId = request.evidence[1].evidenceId or false,
    actor = assert(dibs.Identity.CreateSnapshot("Coordinator-Realm")), reason = "Reviewed evidence", timestamp = 1700000000,
  }))
  local proposal = assert(dibs.Governance.CreateDisputeOperationProposal(operation))
  return dibs, proposal, operation
end

-- T013: the protected boundary for the canonical operation. The feature is
-- closed by default in the release source, and a closed client refuses the
-- action before the underlying writer is reached.

describe("ProtectedActions ledger.operation", function()
  local function setup()
    local _, dibs = loader.load({ wow = {
      playerName = "Tester-Realm",
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Other-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1 },
    }, withAce3 = true })
    return dibs
  end

  it("denies ledger.operation when feature is disabled", function()
    local dibs = setup()
    local settings = dibs.GetLocalSettings()
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false
    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { operationId = "op-1" })
    assert_equal(false, result.ok)
    assert_equal("FEATURE_DISABLED", result.reasonCode)
  end)

  it("allows ledger.operation when feature is enabled and actor is authorized", function()
    local dibs, proposal, operation = proposedResolution()
    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { proposalId = proposal.proposalId })
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("LEDGER_OPERATION_COMMIT", result.value.recordClass)
    assert_equal(proposal.operation.operationId, result.value.operation.operationId)
  end)

  it("preserves Ledger errors through the protected boundary", function()
    local dibs, proposal = proposedResolution()
    local before = dibs.Sync.CalculateContentHash(dibs.GetDB())
    writer.setUpvalue(dibs.Ledger.CommitDisputeOperation, "operationFailureProbe", function(point)
      if point == "pre-validation" then return "INSUFFICIENT_BALANCE" end
    end)
    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { proposalId = proposal.proposalId })
    assert_equal(false, result.ok)
    assert_equal("INSUFFICIENT_BALANCE", result.reasonCode)
    assert_equal("INSUFFICIENT_BALANCE", result.diagnostic)
    assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetDB()))
  end)

  it("denies ledger.operation for unauthorized actor", function()
    local _, dibs = loader.load({ wow = {
      playerName = "Member-Realm",
      guildLeader = false,
      guildMembers = { "Tester-Realm", "Member-Realm" },
      guildRankIndices = { [1] = 0, [2] = 3 },
    }, withAce3 = true })
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true

    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { operationId = "op-1" })
    assert_equal(false, result.ok)
    assert_equal(false, result.decision.allowed)
  end)
end)
