local clients = require("helpers.canonical_operation_clients")
local fixtures = require("helpers.dispute_fixtures")

local function freshClient()
  local world = clients.new()
  return world, world:Load("Coordinator-Realm")
end

local function capture(client, world, requestId, ledgerIds)
  local dibs = client.dibs
  local state = { ledgers = {} }
  for _, ledgerId in ipairs(ledgerIds or { "guild-primary" }) do
    local ledger = {
      transactions = dibs.Ledger.GetAllTransactions(ledgerId),
      balances = {},
      canonical = dibs.Ledger.GetCanonicalState and dibs.Ledger.GetCanonicalState(ledgerId) or nil,
    }
    for _, playerName in ipairs(world.names) do
      ledger.balances[playerName] = dibs.Ledger.GetBalance(
        playerName,
        dibs.GetCurrentSeasonId(),
        ledgerId
      )
    end
    state.ledgers[ledgerId] = ledger
  end
  state.request = requestId and dibs.Disputes.GetRequest(requestId, dibs.GetPlayerName()) or nil
  return clients.DeepCopy(state)
end

local function createTargetCase(client, world, ledgerId)
  local dibs = client.dibs
  local seasonId = dibs.GetCurrentSeasonId()
  local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(client.name, seasonId, {
    transactionId = "rf0012-target-original",
  }), ledgerId))
  local request = assert(dibs.Disputes.CreateReport({
    category = "wrong_item_player",
    transactionRef = original.transactionId,
    note = "RF-0012 target-transfer regression",
  }))
  return original, request, seasonId
end

local function targetCorrectionOptions(world, request)
  return {
    confirmed = true,
    reason = "RF-0012 transfer regression",
    playerName = world.names[2],
    expectedRevision = request.revision,
  }
end

local function replaceUpvalue(fn, name, value)
  assert_true(type(debug) == "table" and type(debug.getupvalue) == "function"
    and type(debug.setupvalue) == "function", "isolated Lua debug support is required")
  for index = 1, 64 do
    local upvalueName, previous = debug.getupvalue(fn, index)
    if upvalueName == nil then break end
    if upvalueName == name then
      debug.setupvalue(fn, index, value)
      return previous
    end
  end
  error("private Ledger test seam not found: " .. name, 2)
end

local function enableCanonicalWriter(client)
  local writer = client.dibs.Ledger.CommitDisputeOperation
  assert_true(type(writer) == "function", "Ledger.CommitDisputeOperation is not implemented")
  -- Only this isolated test client replaces the private, fail-closed writer gates.
  replaceUpvalue(writer, "DISPUTE_OPERATION_WRITES_ENABLED", true)
  replaceUpvalue(writer, "operationReadinessProbe", function() return true end)
  replaceUpvalue(writer, "operationFailureProbe", function(point)
    local hit, failure = client.failureInjector:Hit(point)
    if hit then return failure end
    return nil
  end)
  return writer
end

-- Enables the whole canonical correction path in one isolated test client:
-- the private Ledger writer gate, the private runtime readiness probe, and the
-- release flag consulted by the protected boundary. None of these switches
-- exist in the production addon as a user or SavedVariables option.
-- The verified coordinator authority is established separately through
-- world:ActivateV2().
local function enableCanonicalCorrectionPath(client)
  local writer = enableCanonicalWriter(client)
  client.dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
  return writer
end

local function makeCanonicalTargetTransfer(client, original, request, seasonId, recipientName)
  local dibs = client.dibs
  local guildKey = dibs.GetGuildKey()
  local actor = assert(dibs.Identity.CreateSnapshot(client.name))
  local recipient = assert(dibs.Identity.CreateSnapshot(recipientName))
  local evidenceId = request.evidence[1].evidenceId or false
  local operationId = "rf0012-canonical-transfer-" .. tostring(request.requestId)
  local operation = {
    schemaVersion = 1,
    operationId = operationId,
    operationType = "DISPUTE_TARGET_TRANSFER",
    guildKey = guildKey,
    ledgerId = "guild-primary",
    requestId = request.requestId,
    requestRevision = request.revision,
    evidenceId = evidenceId,
    originalTransactionId = original.transactionId,
    actor = actor,
    reason = "RF-0012 canonical transfer",
    timestamp = 1700000000,
    signedEntries = {
      {
        operationId = operationId,
        entryIndex = 1,
        transactionId = operationId .. "-entry-1",
        guildKey = guildKey,
        ledgerId = "guild-primary",
        memberKey = original.memberKey,
        seasonId = seasonId,
        actionType = "DIB_ADMIN_ADJUSTMENT",
        quantityDelta = 1,
        evidenceId = evidenceId,
        originalTransactionId = original.transactionId,
        requestId = request.requestId,
        requestRevision = request.revision,
      },
      {
        operationId = operationId,
        entryIndex = 2,
        transactionId = operationId .. "-entry-2",
        guildKey = guildKey,
        ledgerId = "guild-primary",
        memberKey = recipient.memberKey,
        seasonId = seasonId,
        actionType = "DIB_ADMIN_ADJUSTMENT",
        quantityDelta = -1,
        evidenceId = evidenceId,
        originalTransactionId = original.transactionId,
        requestId = request.requestId,
        requestRevision = request.revision,
      },
    },
  }
  return assert(dibs.Ledger.BuildDisputeOperation(operation))
end

local function canonicalTransferCase()
  local world, client = freshClient()
  local original, request, seasonId = createTargetCase(client, world)
  world:ActivateV2()
  local activeSeasonId = client.dibs.GetCurrentSeasonId()
  assert(client.dibs.Ledger.Grant(client.name, 1, "RF-0012 prior canonical award", "test", activeSeasonId))
  local award = client.dibs.Ledger.CommitDibUse({
    actor = client.name,
    action = "ledger.use",
    ledgerId = "guild-primary",
  }, {
    transactionId = "rf0012-prior-canonical-award",
    playerName = client.name,
    seasonId = activeSeasonId,
    amount = 1,
    reason = "RF-0012 prior canonical award",
  })
  assert_true(award and award.accepted, tostring(award and award.reasonCode))
  world:TakePackets()
  local operation = makeCanonicalTargetTransfer(client, original, request, seasonId, world.names[2])
  return world, client, original, request, seasonId, operation
end

local function primaryLedger(client)
  return client.dibs.db.ledgers["guild-primary"]
end

local function operationCommitCount(ledger)
  local count = 0
  for _, commit in pairs(ledger.canonical.commits) do
    if commit.recordClass == "LEDGER_OPERATION_COMMIT" then count = count + 1 end
  end
  return count
end

local function assertTransferProjected(client, operation, commit)
  local ledger = primaryLedger(client)
  local position = tostring(commit.ledgerEpoch) .. ":" .. tostring(commit.sequence)
  for index, entry in ipairs(operation.signedEntries) do
    local transaction = ledger.transactions[entry.transactionId]
    assert_not_nil(transaction, "operation entry transaction was not projected")
    assert_equal(operation.operationId, transaction.operationId)
    assert_equal(index, transaction.entryIndex)
    assert_equal(entry.memberKey, transaction.memberKey)
    assert_equal(entry.quantityDelta, transaction.quantityDelta)
    assert_equal(position, ledger.canonical.transactionIndex[entry.transactionId])
    local state = ledger.playerStates[entry.seasonId][entry.memberKey]
    local occurrences = 0
    for _, transactionId in ipairs(state.transactions) do
      if transactionId == entry.transactionId then occurrences = occurrences + 1 end
    end
    assert_equal(1, occurrences, "operation transaction was not projected exactly once")
  end
end

-- Injects named RF-0012 failure points at the Ledger writer boundary. The
-- protected boundary is intentionally left intact so the real production path
-- (ProtectedActions -> MultiLedger -> Ledger) still runs. The armed point is
-- consumed by the Ledger's own private failure probe, exactly like a real
-- interruption at that stage.
local function runWithActionFailures(world, client, failurePlan, action)
  local writer = client.dibs.Ledger.CommitDisputeOperation
  local originalWriter = writer
  local calls = 0
  local function wrapper(context, operation)
    calls = calls + 1
    local failurePoint = failurePlan[calls]
    if failurePoint then
      world:ArmFailure(client.name, failurePoint)
    end
    return originalWriter(context, operation)
  end
  client.dibs.Ledger.CommitDisputeOperation = wrapper
  -- The private writer gates are upvalues of the production writer function.
  -- Replacing them on that same function object opens the gate for the
  -- isolated test client only; the wrapper delegates to it.
  replaceUpvalue(originalWriter, "DISPUTE_OPERATION_WRITES_ENABLED", true)
  replaceUpvalue(originalWriter, "operationReadinessProbe", function() return true end)
  replaceUpvalue(originalWriter, "operationFailureProbe", function(point)
    local hit, failure = client.failureInjector:Hit(point)
    if hit then return failure end
    return nil
  end)
  local ok, result, reason = pcall(action)
  client.dibs.Ledger.CommitDisputeOperation = originalWriter
  if not ok then error(result, 0) end
  return result, reason, calls
end

local function assertBlocked(result, reason)
  assert_true(type(result) == "table", tostring(reason or "missing result"))
  assert_false(result.accepted == true or result.ok == true, "blocked operation was reported as accepted")
  local diagnostic = result.reasonCode or result.diagnostic
  assert_true(type(diagnostic) == "string" and diagnostic ~= "", "blocked operation omitted its diagnostic")
end

local function submitCanonical(client)
  local writer = client.dibs.Ledger.CommitDisputeOperation
  if type(writer) ~= "function" then
    return nil, "Ledger.CommitDisputeOperation is not implemented"
  end
  return writer({ ledgerId = "guild-primary" }, {})
end

local function assertWriterBlocked(world, client)
  local before = capture(client, world)
  local result, reason = submitCanonical(client)
  assert_true(clients.DeepEqual(before, capture(client, world)), "blocked writer changed accounting state")
  assertBlocked(result, reason)
end

describe("RF-0012 canonical dispute operation gate", function()
  it("injects each named failure once and resets only the selected test client", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local follower = world:Load("Player-Realm", coordinator.env.RCLootCouncil_dibsDB)
    local before = capture(coordinator, world)

    for _, point in ipairs(fixtures.getFailurePoints()) do
      world:ArmFailure(coordinator.name, point)
      local hit, failure = world:HitFailure(coordinator.name, point)
      assert_true(hit, "failure point did not trigger: " .. point)
      assert_equal("INJECTED_TEST_FAILURE", failure.code)
      assert_equal(point, failure.point)
      assert_false(world:HitFailure(coordinator.name, point), "failure point triggered more than once: " .. point)
      assert_equal(1, #coordinator.failureInjector:GetTriggered())
      assert_false(follower.failureInjector:IsArmed())
      world:ResetFailures(coordinator.name)
      assert_false(coordinator.failureInjector:IsArmed())
      assert_equal(0, #coordinator.failureInjector:GetTriggered())
    end

    assert_true(clients.DeepEqual(before, capture(coordinator, world)))
    assert_nil(coordinator.env.__rf0012FailureInjector)
    assert_nil(follower.env.__rf0012FailureInjector)
  end)

  it("blocks direct submission while the release-source default is disabled", function()
    local world, coordinator = freshClient()
    assertWriterBlocked(world, coordinator)
  end)

  it("blocks coordinator acceptance while the release-source default is disabled", function()
    local world = clients.new()
    local coordinator = world:ActivateV2()
    assertWriterBlocked(world, coordinator)
  end)

  it("commits both target-transfer legs in one sequence and exact replay is a no-op", function()
    local world, coordinator, original, request, seasonId, operation = canonicalTransferCase()
    local writer = enableCanonicalWriter(coordinator)
    local ledger = primaryLedger(coordinator)
    local originalRow = clients.DeepCopy(ledger.transactions[original.transactionId])
    local transactionsBefore = #coordinator.dibs.Ledger.GetAllTransactions("guild-primary")
    local sequenceBefore = ledger.canonical.nextSeq
    local oldSourceBalance = coordinator.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary")
    local oldRecipientBalance = coordinator.dibs.Ledger.GetBalance(world.names[2], seasonId, "guild-primary")
    local newId = coordinator.dibs.NewId
    local generatedIds = 0
    local operationIdPrefixes = { "op-", "entry-", "rf0012-canonical" }
    local operationIdGenerated = false
    coordinator.dibs.NewId = function(prefix, ...)
      generatedIds = generatedIds + 1
      for _, forbidden in ipairs(operationIdPrefixes) do
        if tostring(prefix or ""):find(forbidden, 1, true) then operationIdGenerated = true end
      end
      return newId(prefix, ...)
    end

    local result = writer({ actor = coordinator.name, ledgerId = operation.ledgerId }, operation)
    coordinator.dibs.NewId = newId
    assert_true(result.accepted)
    assert_false(result.idempotentReplay)
    assert_true(result.canonicalAccepted)
    assert_true(result.projectionComplete)
    -- The Ledger must never allocate the operation or entry identities. A
    -- transport message ID for the announcement is a separate concern.
    assert_false(operationIdGenerated, "Ledger allocated an operation or entry ID")

    local commit = result.value
    ledger = primaryLedger(coordinator)
    assert_equal("LEDGER_OPERATION_COMMIT", commit.recordClass)
    assert_equal(2, #operation.signedEntries)
    assert_equal(2, #commit.operation.signedEntries)
    assert_equal(sequenceBefore, commit.sequence)
    assert_equal(sequenceBefore + 1, ledger.canonical.nextSeq)
    assert_equal(commit.commitHash, ledger.canonical.rootHash)
    assert_equal(1, operationCommitCount(ledger))
    assertTransferProjected(coordinator, operation, commit)
    assert_equal(transactionsBefore + 2, #coordinator.dibs.Ledger.GetAllTransactions("guild-primary"))
    assert_equal(oldSourceBalance + 1, coordinator.dibs.Ledger.GetBalance(coordinator.name, seasonId, "guild-primary"))
    assert_equal(oldRecipientBalance - 1, coordinator.dibs.Ledger.GetBalance(world.names[2], seasonId, "guild-primary"))
    assert_true(clients.DeepEqual(originalRow, ledger.transactions[original.transactionId]),
      "canonical correction rewrote the historical source transaction")

    local afterFirst = clients.DeepCopy(world:Snapshot(coordinator))
    local replay = writer({ actor = coordinator.name, ledgerId = operation.ledgerId }, operation)
    assert_true(replay.accepted)
    assert_true(replay.idempotentReplay)
    assert_equal("IDEMPOTENT_REPLAY", replay.reasonCode)
    assert_equal(1, operationCommitCount(primaryLedger(coordinator)))
    assert_true(clients.DeepEqual(afterFirst, world:Snapshot(coordinator)),
      "exact replay changed SavedVariables")
  end)

  it("rejects an invalid second leg and pre-acceptance faults without mutation", function()
    local world, coordinator, _, _, _, operation = canonicalTransferCase()
    local writer = enableCanonicalWriter(coordinator)
    local invalid = clients.DeepCopy(operation)
    invalid.signedEntries[2].quantityDelta = 0
    invalid.payloadHash = coordinator.dibs.Ledger.CalculateDisputeOperationPayloadHash(invalid)
    local before = world:Snapshot(coordinator)
    local invalidResult = writer({ actor = coordinator.name }, invalid)
    assertBlocked(invalidResult)
    assert_false(invalidResult.canonicalAccepted == true)
    assert_true(clients.DeepEqual(before, world:Snapshot(coordinator)),
      "invalid second leg changed SavedVariables")

    for _, point in ipairs({ "pre-validation", "pre-acceptance" }) do
      world:ArmFailure(coordinator.name, point)
      before = world:Snapshot(coordinator)
      local result = writer({ actor = coordinator.name }, operation)
      assertBlocked(result, point)
      assert_false(result.canonicalAccepted == true)
      assert_equal("INJECTED_TEST_FAILURE", result.reasonCode)
      assert_true(clients.DeepEqual(before, world:Snapshot(coordinator)),
        point .. " failure changed SavedVariables")
      assert_equal(1, #coordinator.failureInjector:GetTriggered())
      world:ResetFailures(coordinator.name)
    end
  end)

  it("repairs the same accepted journal record after projection interruptions", function()
    for _, point in ipairs({
      "after-canonical-acceptance",
      "transaction-row:1",
      "transaction-row:2",
      "transaction-index",
      "balance",
    }) do
      local world, coordinator, _, _, _, operation = canonicalTransferCase()
      local writer = enableCanonicalWriter(coordinator)
      local transactionsBefore = #coordinator.dibs.Ledger.GetAllTransactions("guild-primary")
      world:ArmFailure(coordinator.name, point)
      local failed = writer({ actor = coordinator.name }, operation)
      assert_false(failed.accepted)
      assert_true(failed.canonicalAccepted)
      assert_false(failed.projectionComplete)
      assert_equal("PROJECTION_INCOMPLETE", failed.reasonCode, point)
      assert_equal(point, failed.diagnostic)
      local ledger = primaryLedger(coordinator)
      assert_equal(1, operationCommitCount(ledger), point .. " appended more than one journal record")
      local sequence = ledger.canonical.nextSeq
      assert_equal(1, #coordinator.failureInjector:GetTriggered())

      local replay = writer({ actor = coordinator.name }, operation)
      assert_true(replay.accepted, point .. " replay did not complete projections")
      assert_true(replay.idempotentReplay)
      assert_equal(sequence, primaryLedger(coordinator).canonical.nextSeq)
      assert_equal(1, operationCommitCount(primaryLedger(coordinator)))
      assertTransferProjected(coordinator, operation, replay.value)
      assert_equal(transactionsBefore + 2, #coordinator.dibs.Ledger.GetAllTransactions("guild-primary"))
    end
  end)

  it("rejects changed content for an accepted operation ID", function()
    local world, coordinator, _, _, _, operation = canonicalTransferCase()
    local writer = enableCanonicalWriter(coordinator)
    local accepted = writer({ actor = coordinator.name }, operation)
    assert_true(accepted.accepted)
    local before = world:Snapshot(coordinator)
    local changed = clients.DeepCopy(operation)
    changed.reason = "Changed content under the same operation ID"
    changed.payloadHash = coordinator.dibs.Ledger.CalculateDisputeOperationPayloadHash(changed)
    local conflict = writer({ actor = coordinator.name }, changed)
    assertBlocked(conflict)
    assert_equal("OPERATION_ID_CONFLICT", conflict.reasonCode)
    assert_true(clients.DeepEqual(before, world:Snapshot(coordinator)),
      "changed content under an accepted operation ID mutated SavedVariables")
  end)

  it("blocks direct coordinator acceptance when authority readiness is unknown", function()
    local world = clients.new()
    local coordinator = world:ActivateV2()
    coordinator.dibs.Governance.GetAuthorityState = function() return nil end
    assertWriterBlocked(world, coordinator)
  end)

  it("blocks when the private runtime readiness gate is unknown", function()
    local world, coordinator, _, _, _, operation = canonicalTransferCase()
    local writer = coordinator.dibs.Ledger.CommitDisputeOperation
    replaceUpvalue(writer, "DISPUTE_OPERATION_WRITES_ENABLED", true)
    local before = world:Snapshot(coordinator)
    local result = writer({ actor = coordinator.name }, operation)
    assertBlocked(result)
    -- T021: the readiness probe now delegates to the shared gate, so the
    -- refusal carries that gate's explicit diagnostic instead of a generic
    -- unknown-readiness code. Both are refusals; the state must change nothing.
    assert_true(result.reasonCode == "OPERATION_READINESS_UNKNOWN"
      or result.reasonCode == "CANONICAL_DISPUTE_OPERATIONS_DISABLED",
      "unexpected readiness refusal: " .. tostring(result.reasonCode))
    assert_true(clients.DeepEqual(before, world:Snapshot(coordinator)),
      "unknown runtime readiness changed SavedVariables")
  end)

  it("blocks direct submission while sequence recovery is pending", function()
    local world = clients.new()
    local coordinator = world:ActivateV2()
    coordinator.dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    assertWriterBlocked(world, coordinator)
  end)

  it("routes protected operation submissions through the same gate", function()
    local world, coordinator = freshClient()
    local before = capture(coordinator, world)
    local result = coordinator.dibs.ProtectedActions.Execute("ledger.operation", nil, { operation = {} })
    assertBlocked(result)
    assert_true(clients.DeepEqual(before, capture(coordinator, world)), "blocked protected action changed accounting state")
    assert_true(result.reasonCode ~= "INVALID_ACTION", "protected operation action is not registered")
  end)

  it("keeps both transfer legs atomic when the canonical operation is rejected", function()
    -- T015 replaced the legacy leg-by-leg compensation with one all-or-reject
    -- canonical operation. A rejection must leave every projection untouched.
    for _, point in ipairs({ "pre-validation", "pre-acceptance" }) do
      local world, coordinator = freshClient()
      local _, request = createTargetCase(coordinator, world)
      world:ActivateV2()
      enableCanonicalCorrectionPath(coordinator)
      local options = targetCorrectionOptions(world, request)
      local before = capture(coordinator, world, request.requestId)
      local result, reason = runWithActionFailures(world, coordinator, { [1] = point }, function()
        return coordinator.dibs.Disputes.Resolve(request.requestId, "correct_target", options, nil)
      end)

      assert_nil(result)
      assert_equal("INJECTED_TEST_FAILURE", reason)
      assert_true(clients.DeepEqual(before, capture(coordinator, world, request.requestId)),
        "a rejected canonical operation changed the ledger or dispute snapshot")    end
  end)

  it("rejects a failed canonical projection without leaving a partial transfer", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local options = targetCorrectionOptions(world, request)
    local before = capture(coordinator, world, request.requestId)
    local result, reason = runWithActionFailures(world, coordinator, {
      [1] = "after-canonical-acceptance",
    }, function()
      return coordinator.dibs.Disputes.Resolve(request.requestId, "correct_target", options, nil)
    end)
    local after = capture(coordinator, world, request.requestId)

    assert_nil(result)
    -- The post-acceptance interruption surfaces the documented T010 state: the
    -- journal record is accepted, the projections are incomplete, and the
    -- caller is told so instead of receiving a success-shaped result.
    assert_equal("PROJECTION_INCOMPLETE", reason)
    -- The journal record survives so recovery can rebuild the projections, but
    -- no transaction row and no balance change may be visible.
    local ledger = primaryLedger(coordinator)
    assert_equal(1, operationCommitCount(ledger), "the accepted journal record was lost")
    assert_equal(#before.ledgers["guild-primary"].transactions, #after.ledgers["guild-primary"].transactions,
      "a failed projection left a transaction row behind")
    for _, playerName in ipairs(world.names) do
      assert_equal(before.ledgers["guild-primary"].balances[playerName],
        after.ledgers["guild-primary"].balances[playerName], "a failed projection changed a balance")
    end
  end)

  it("does not double-apply a target transfer after a failed attempt and retry", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local options = targetCorrectionOptions(world, request)
    local before = capture(coordinator, world, request.requestId)
    local failedResult, failedReason = runWithActionFailures(world, coordinator, {
      [1] = "pre-acceptance",
    }, function()
      return coordinator.dibs.Disputes.Resolve(request.requestId, "correct_target", options, nil)
    end)
    local afterFailure = capture(coordinator, world, request.requestId)

    assert_nil(failedResult)
    assert_equal("INJECTED_TEST_FAILURE", failedReason)
    assert_true(clients.DeepEqual(before, afterFailure),
      "failed attempt changed accounting state before retry")
  end)

  it("does not append another transfer for a duplicate successful correction", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local first, firstReason = coordinator.dibs.Disputes.Resolve(
      request.requestId,
      "correct_target",
      targetCorrectionOptions(world, request),
      nil
    )
    assert_true(first and first.ok == true, tostring(firstReason))
    local afterFirst = capture(coordinator, world, request.requestId)
    local currentRequest = coordinator.dibs.Disputes.GetRequest(request.requestId, coordinator.name)
    local duplicate, reason = coordinator.dibs.Disputes.Resolve(
      request.requestId,
      "correct_target",
      targetCorrectionOptions(world, currentRequest),
      nil
    )

    -- T024: a duplicate of a complete correction is an idempotent replay. It
    -- never appends a second transfer and never changes the resolved request.
    if duplicate == nil then
      assert_equal("REQUEST_ALREADY_RESOLVED", reason)
    else
      assert_true(duplicate.ok == true, tostring(reason))
      assert_equal("REPLAYED", duplicate.outcome)
    end
    assert_true(clients.DeepEqual(afterFirst, capture(coordinator, world, request.requestId)),
      "duplicate correction appended transactions or changed the resolved request")
  end)
  it("leaves no accounting change when the operation fails before acceptance", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local before = capture(coordinator, world, request.requestId)
    local result, reason = runWithActionFailures(world, coordinator, { [1] = "pre-acceptance" }, function()
      return coordinator.dibs.Disputes.Resolve(
        request.requestId, "correct_target", targetCorrectionOptions(world, request), nil)
    end)

    assert_nil(result)
    assert_equal("INJECTED_TEST_FAILURE", reason)
    assert_true(clients.DeepEqual(before, capture(coordinator, world, request.requestId)),
      "a pre-acceptance failure changed the ledger or dispute snapshot")
    assert_equal(0, operationCommitCount(primaryLedger(coordinator)),
      "a pre-acceptance failure left a canonical commit behind")
  end)

  it("rebuilds the projections from the accepted record after a post-acceptance interruption", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local options = targetCorrectionOptions(world, request)
    local before = capture(coordinator, world, request.requestId)

    -- The interruption happens after the canonical record is accepted and before
    -- the transaction rows are projected.
    local result, reason = runWithActionFailures(world, coordinator, {
      [1] = "after-canonical-acceptance",
    }, function()
      return coordinator.dibs.Disputes.Resolve(request.requestId, "correct_target", options, nil)
    end)
    assert_nil(result)
    assert_equal("PROJECTION_INCOMPLETE", reason)

    -- Exactly one canonical record exists and the transaction rows are missing.
    local ledger = primaryLedger(coordinator)
    assert_equal(1, operationCommitCount(ledger), "the accepted record was lost")
    local interrupted = capture(coordinator, world, request.requestId)
    assert_equal(#before.ledgers["guild-primary"].transactions,
      #interrupted.ledgers["guild-primary"].transactions,
      "an interrupted projection left a transaction row behind")

    -- The replay rebuilds the missing projections from that same record
    -- without appending a second commit.
    local replay, replayReason = coordinator.dibs.Disputes.Resolve(
      request.requestId, "correct_target", options, nil)
    assert_true(replay and replay.ok == true, tostring(replay) .. " / " .. tostring(replayReason))
    local rebuilt = capture(coordinator, world, request.requestId)
    assert_equal(1, operationCommitCount(primaryLedger(coordinator)),
      "the replay appended a second canonical commit")
    assert_equal(#before.ledgers["guild-primary"].transactions + 2,
      #rebuilt.ledgers["guild-primary"].transactions,
      "the replay did not rebuild the two operation legs")
    for _, playerName in ipairs(world.names) do
      assert_equal(before.ledgers["guild-primary"].balances[playerName],
        rebuilt.ledgers["guild-primary"].balances[playerName],
        "the replay did not reproduce the expected balance for " .. playerName)
    end
  end)

  it("classifies a valid canonical chain and every broken state distinctly", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local result = coordinator.dibs.Disputes.Resolve(
      request.requestId, "correct_target", targetCorrectionOptions(world, request), nil)
    assert_true(result and result.ok == true, tostring(result))

    local ledger = primaryLedger(coordinator)
    local valid = coordinator.dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("VALID", valid.classification, tostring(valid.reasonCode))

    -- A missing sequence is classified as a gap.
    local savedSequence = ledger.canonical.nextSeq
    ledger.canonical.nextSeq = savedSequence + 1
    local gapped = coordinator.dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("MISSING_SEQUENCE", gapped.classification, tostring(gapped.reasonCode))
    assert_equal("CANONICAL_SEQUENCE_GAP", gapped.reasonCode)
    ledger.canonical.nextSeq = savedSequence

    -- A wrong root is classified apart from a gap.
    local savedRoot = ledger.canonical.rootHash
    ledger.canonical.rootHash = "WRONG-ROOT"
    local wrongRoot = coordinator.dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("WRONG_ROOT", wrongRoot.classification, tostring(wrongRoot.reasonCode))
    ledger.canonical.rootHash = savedRoot

    -- A missing transaction row is an incomplete projection.
    local commit = ledger.canonical.commits["7:1"]
    local entryId = commit.operation.signedEntries[1].transactionId
    local savedRow = ledger.transactions[entryId]
    ledger.transactions[entryId] = nil
    local incomplete = coordinator.dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("INCOMPLETE_PROJECTION", incomplete.classification, tostring(incomplete.reasonCode))
    ledger.transactions[entryId] = savedRow

    -- An index that does not point at the owning position is an index mismatch.
    local savedIndex = ledger.canonical.transactionIndex[entryId]
    ledger.canonical.transactionIndex[entryId] = "7:99"
    local indexMismatch = coordinator.dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("INDEX_MISMATCH", indexMismatch.classification, tostring(indexMismatch.reasonCode))
    ledger.canonical.transactionIndex[entryId] = savedIndex

    -- The chain is valid again once the state is restored.
    local restored = coordinator.dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("VALID", restored.classification, tostring(restored.reasonCode))
  end)

  it("rebuilds mixed history deterministically without double counting", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local result = coordinator.dibs.Disputes.Resolve(
      request.requestId, "correct_target", targetCorrectionOptions(world, request), nil)
    assert_true(result and result.ok == true, tostring(result))

    local dibs = coordinator.dibs
    local ledger = primaryLedger(coordinator)
    -- A pre-feature local row that no canonical record backs stays legacy
    -- history and must be counted exactly once.
    local legacyId = "rf0012-mixed-legacy-row"
    ledger.transactions[legacyId] = {
      transactionId = legacyId, playerName = world.names[3], memberKey = world.names[3],
      seasonId = dibs.GetCurrentSeasonId(), type = "DIB_GRANTED", amount = 2, quantityDelta = 2,
    }

    local first = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(first.rebuilt, tostring(first.reasonCode))
    local afterFirst = {
      transactions = clients.DeepCopy(ledger.transactions),
      balances = {},
    }
    for _, playerName in ipairs(world.names) do
      afterFirst.balances[playerName] = dibs.Ledger.GetBalance(playerName, dibs.GetCurrentSeasonId(), "guild-primary")
    end

    -- A second rebuild produces identical rows, identifiers, balances, and
    -- indexes without advancing the sequence or changing the root hash.
    local sequenceBefore = ledger.canonical.nextSeq
    local rootBefore = ledger.canonical.rootHash
    local second = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(second.rebuilt, tostring(second.reasonCode))
    assert_equal(sequenceBefore, ledger.canonical.nextSeq, "a rebuild advanced the sequence")
    assert_equal(rootBefore, ledger.canonical.rootHash, "a rebuild changed the root hash")
    assert_true(clients.DeepEqual(afterFirst.transactions, ledger.transactions),
      "a repeated rebuild produced different transaction rows")
    for _, playerName in ipairs(world.names) do
      assert_equal(afterFirst.balances[playerName],
        dibs.Ledger.GetBalance(playerName, dibs.GetCurrentSeasonId(), "guild-primary"),
        "a repeated rebuild produced a different balance for " .. playerName)
    end
    -- The legacy row is preserved and the commit-backed rows are counted once.
    assert_not_nil(ledger.transactions[legacyId], "the legacy local row was dropped")
    assert_not_nil(ledger.transactions["rf0012-target-original"],
      "the original legacy local row was dropped")
    local operationRows = 0
    for transactionId, transaction in pairs(ledger.transactions) do
      if type(transaction) == "table" and transaction.operationId then operationRows = operationRows + 1 end
    end
    assert_equal(2, operationRows, "the commit-backed operation rows were not counted exactly once")
  end)

  it("reconstructs the operation state projection from the accepted commits", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local result = coordinator.dibs.Disputes.Resolve(
      request.requestId, "correct_target", targetCorrectionOptions(world, request), nil)
    assert_true(result and result.ok == true, tostring(result))

    local dibs = coordinator.dibs
    local reconstructed = dibs.Disputes.ReconstructOperationStates("guild-primary")
    assert_true(reconstructed.rebuilt, tostring(reconstructed.reasonCode))
    local states = reconstructed.states
    local count = 0
    local found = nil
    for _, state in pairs(states) do
      count = count + 1
      found = state
    end
    assert_equal(1, count, "the operation state projection did not contain exactly one operation")
    assert_equal(request.requestId, found.requestId)
    assert_equal("ACCEPTED", found.status)
    assert_true(found.linked, "the operation state was not linked to its request")
    assert_equal(2, #found.entryTransactionIds, "the operation state lost an entry transaction ID")

    -- A second reconstruction is deterministic.
    local second = dibs.Disputes.ReconstructOperationStates("guild-primary")
    assert_true(second.rebuilt, tostring(second.reasonCode))
    local secondCount = 0
    for _ in pairs(second.states) do secondCount = secondCount + 1 end
    assert_equal(1, secondCount, "a repeated reconstruction produced a different projection")
  end)

  it("does not link an operation whose request revision no longer matches", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local result = coordinator.dibs.Disputes.Resolve(
      request.requestId, "correct_target", targetCorrectionOptions(world, request), nil)
    assert_true(result and result.ok == true, tostring(result))

    local dibs = coordinator.dibs
    -- A reopened dossier is a new revision with no accepted correction link.
    local stored = dibs.GetDB().disputes.requests[request.requestId]
    stored.revision = tonumber(stored.revision or 1) + 1
    stored.correctionRevision = nil
    stored.correctionTransactionId = nil
    stored.resolution = nil
    local reconstructed = dibs.Disputes.ReconstructOperationStates("guild-primary")
    assert_true(reconstructed.rebuilt, tostring(reconstructed.reasonCode))
    local found = nil
    for _, state in pairs(reconstructed.states) do found = state end
    assert_not_nil(found, "the operation state was dropped")
    assert_equal("UNLINKED", found.status)
    assert_equal("OPERATION_REVISION_MISMATCH", found.reasonCode)
    assert_false(found.linked, "a mismatched operation was linked to the dossier")
  end)

  it("counts a commit-backed row once and a legacy local row once", function()
    local world, coordinator = freshClient()
    local _, request = createTargetCase(coordinator, world)
    world:ActivateV2()
    enableCanonicalCorrectionPath(coordinator)
    local options = targetCorrectionOptions(world, request)

    -- A legacy local row with no canonical commit stays legacy history.
    local dibs = coordinator.dibs
    local legacyTransaction = assert(dibs.Ledger.AddTransaction(
      fixtures.transaction(world.names[3], dibs.GetCurrentSeasonId(), {
        transactionId = "rf0012-legacy-local-row",
        amount = 1,
        type = "DIB_GRANTED",
      }), "guild-primary"))

    local before = capture(coordinator, world, request.requestId)
    local result = dibs.Disputes.Resolve(request.requestId, "correct_target", options, nil)
    assert_true(result and result.ok == true, tostring(result))
    local after = capture(coordinator, world, request.requestId)

    -- The legacy row is preserved exactly, and the operation adds exactly its
    -- own two rows.
    assert_equal(before.ledgers["guild-primary"].transactions["rf0012-legacy-local-row"],
      after.ledgers["guild-primary"].transactions["rf0012-legacy-local-row"],
      "the legacy local row was rewritten")
    assert_equal(#before.ledgers["guild-primary"].transactions + 2,
      #after.ledgers["guild-primary"].transactions,
      "the operation did not add exactly its two rows")
    assert_equal(1, operationCommitCount(primaryLedger(coordinator)),
      "the operation did not produce exactly one canonical commit")
  end)

  it("rejects a correction when its original is outside the active ledger", function()
    local world, coordinator = freshClient()
    local dibs = coordinator.dibs
    local original, request = createTargetCase(coordinator, world, "guild-primary")
    local proposal = dibs.MultiLedger.ProposeLedger(coordinator.name, "RF-0012 active mismatch")
    assert_true(proposal.ok, tostring(proposal.reasonCode))
    local approved = dibs.MultiLedger.ApproveLedger(coordinator.name, proposal.ledgerId)
    assert_true(approved.ok, tostring(approved.reasonCode))
    local activated, activationReason = dibs.MultiLedger.SetActiveLedger(proposal.ledgerId)
    assert_true(activated, tostring(activationReason))
    local originalRetained = false
    for _, transaction in ipairs(dibs.Ledger.GetAllTransactions("guild-primary")) do
      if transaction.transactionId == original.transactionId then originalRetained = true end
    end
    assert_true(originalRetained, "source transaction was not present in its recorded ledger")

    local before = capture(coordinator, world, request.requestId, { "guild-primary", proposal.ledgerId })
    local result = dibs.Disputes.CorrectBalance(request.requestId, {
      amount = 1,
      confirmed = true,
      reason = "RF-0012 active-ledger mismatch",
      expectedRevision = request.revision,
    }, nil)
    local after = capture(coordinator, world, request.requestId, { "guild-primary", proposal.ledgerId })

    assert_nil(result)
    assert_true(clients.DeepEqual(before, after),
      "correction wrote to the active ledger instead of rejecting the original-ledger mismatch")
  end)
end)
