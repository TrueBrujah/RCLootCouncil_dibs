local loader = require("helpers.load_addon")

describe("ProtectedActions routing", function()
  it("routes season and rank operations", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local season = dibs.ProtectedActions.Execute("season.create", nil, { name = "A" })
    assert_true(season.ok)
    local rank = dibs.ProtectedActions.Execute("rank.set", nil, { seasonId = season.value.id, rankIndex = 1, allocation = 3 })
    assert_true(rank.ok)
    assert_equal(3, rank.value.allocation)
  end)

  it("rechecks the stored proposer authority at canonical operation acceptance", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local accepted = 0
    local proposerRole = "member"
    dibs.Ledger.IsDisputeOperationTransportEnabled = function() return true end
    dibs.Permissions.Evaluate = function(actionId)
      return { allowed = actionId == "ledger.operation", actionId = actionId }
    end
    dibs.Identity.ResolveRosterMember = function(name)
      return { status = "RESOLVED", displayName = name, memberKey = "proposer-key", role = proposerRole }
    end
    dibs.GetGuildKey = function() return "guild-key" end
    dibs.Governance.GetDisputeOperationProposal = function()
      return {
        proposalId = "proposal-1", status = "PENDING",
        operation = {
          guildKey = "guild-key", ledgerId = "guild-primary", requestId = "request-1",
          requestRevision = 1, operationId = "operation-1",
          actor = { displayName = "Officer", memberKey = "proposer-key" },
        },
      }
    end
    dibs.Governance.ResolveDisputeOperationProposal = function() return true end
    dibs.Ledger.CommitDisputeOperation = function() accepted = accepted + 1; return { accepted = true, value = {} } end

    local refused = dibs.ProtectedActions.Execute("ledger.operation", nil, { proposalId = "proposal-1" })
    assert_false(refused.ok)
    assert_equal("PROPOSER_NOT_AUTHORIZED", refused.reasonCode)
    assert_equal(0, accepted, "revoked proposer must not reach canonical commit")

    proposerRole = "officer"
    local allowed = dibs.ProtectedActions.Execute("ledger.operation", nil, { proposalId = "proposal-1" })
    assert_true(allowed.ok)
    assert_equal(1, accepted)
  end)
end)
