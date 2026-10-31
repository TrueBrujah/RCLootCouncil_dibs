local loader = require("helpers.load_addon")

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
    local dibs = setup()
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true

    -- The isolated client replaces only the persistence bridge.
    dibs.MultiLedger.RecordCanonicalOperation = function()
      return { transactionId = "tx-1", commitHash = "hash-1" }
    end

    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { operationId = "op-1" })
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("tx-1", result.value.transactionId)
  end)

  it("preserves Ledger errors through the protected boundary", function()
    local dibs = setup()
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true

    -- The bridge reports the real Ledger diagnostic.
    dibs.MultiLedger.RecordCanonicalOperation = function()
      return nil, "INSUFFICIENT_BALANCE", { diagnostic = "Ledger Error: Insufficient Balance" }
    end

    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { operationId = "op-1" })
    assert_equal(false, result.ok)
    assert_equal("INSUFFICIENT_BALANCE", result.reasonCode)
    assert_equal("Ledger Error: Insufficient Balance", result.diagnostic)
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
