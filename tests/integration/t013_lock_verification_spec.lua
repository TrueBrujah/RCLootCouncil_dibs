local loader = require("helpers.load_addon")

describe("T013 Readiness Lock Verification", function()
  local function setup()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    return dibs
  end

  it("Strictly refuses ledger.operation when feature is disabled (Default State)", function()
    local dibs = setup()
    -- The release flag is compiled into the source. A test that wants the
    -- closed state sets it explicitly so the assertion does not depend on
    -- the shipped default.
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false

    -- Mock the RecordCanonicalOperation to ensure it's not called
    local recordCalled = false
    dibs.MultiLedger.RecordCanonicalOperation = function() recordCalled = true return { transactionId = "tx-test" } end

    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { operationId = "test-op-1" })

    assert_equal(false, result.ok)
    assert_equal("FEATURE_DISABLED", result.decision.reasonCode)
    assert_equal(false, recordCalled, "The underlying RecordCanonicalOperation should never have been called")
  end)

  it("Refuses ledger.operation even if enabled, when readiness guards are not met", function()
    local dibs = setup()
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true

    -- T013 requires a shared default-off/readiness guard, not only the
    -- feature flag. With the release flag open, the real protected boundary
    -- and the real canonical writer must still refuse, because this
    -- environment has no V2 authority, no enforced protocol, and no verified
    -- coordinator. The real modules are used on purpose: a mock would replace
    -- the very gate under test.
    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, {
      operationId = "test-op-2",
      originalTransactionId = "no-such-transaction",
      actionType = "DIB_ADMIN_ADJUSTMENT",
      amount = 1,
      reviewRequestId = "no-such-request",
    })

    assert_equal(false, result.ok, "the protected boundary accepted a correction without readiness")
    local reason = result.decision.reasonCode
    assert_true(reason ~= nil, "the refusal carried no reason code")
    assert_true(reason ~= "CANONICAL_COMMITTED",
      "the correction was committed without readiness: " .. tostring(reason))
  end)

  it("Refuses direct internal calls to Ledger.CommitDisputeOperation when lock is active", function()
    local dibs = setup()
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false

    -- Verify the Ledger API is gated by the feature flag
    -- DISPUTE_OPERATION_WRITES_ENABLED should be false by default
    local result = dibs.Ledger.CommitDisputeOperation({}, {})
    assert_equal(false, result.canonicalAccepted, "Internal API must be blocked when feature is disabled")
    assert_equal("CANONICAL_DISPUTE_OPERATIONS_DISABLED", result.reasonCode)
  end)

  it("Keeps the release flag out of the local SavedVariables settings", function()
    local dibs = setup()
    -- The flag is release-controlled: it is a compiled source constant, not a
    -- user preference and not a SavedVariables value. A player who edits the
    -- local settings table cannot open the canonical correction path.
    local settings = dibs.GetLocalSettings()
    assert_nil(settings.canonical_operations,
      "a SavedVariables switch for the canonical path still exists")

    -- Setting the release constant on the running client is what a
    -- pre-release build does at load time; it is not a persisted value.
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    assert_nil(dibs.GetLocalSettings().canonical_operations,
      "the release flag was written into the local settings")
  end)

  it("Refuses the canonical path when the release flag is false even if a SavedVariables value claims otherwise", function()
    local dibs = setup()
    -- Simulate a player hand-editing their SavedVariables to try to enable
    -- the feature.
    dibs.GetLocalSettings().canonical_operations = true
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false

    local recordCalled = false
    dibs.MultiLedger.RecordCanonicalOperation = function() recordCalled = true return { transactionId = "tx-test" } end

    local result = dibs.ProtectedActions.Execute("ledger.operation", nil, { operationId = "test-op-3" })
    assert_equal(false, result.ok, "a SavedVariables value opened the canonical path")
    assert_equal(false, recordCalled, "the canonical writer was reached through a SavedVariables value")
  end)
end)
