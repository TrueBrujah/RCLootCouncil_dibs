local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

local function sameValue(first, second, seen)
  if type(first) ~= type(second) then return false end
  if type(first) ~= "table" then return first == second end
  seen = seen or {}
  if seen[first] == second then return true end
  seen[first] = second
  for key, value in pairs(first) do
    if not sameValue(value, second[key], seen) then return false end
  end
  for key in pairs(second) do
    if first[key] == nil then return false end
  end
  return true
end

local function setup()
  local _, dibs = loader.load({
    withAce3 = true,
    wow = {
      playerName = "Tester-Realm",
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Other-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1 },
      guildOnline = { [1] = true, [2] = true },
    },
  })
  local seasonId = dibs.GetCurrentSeasonId()
  local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
    transactionId = "rf0012-unit-original",
  })))
  local request = assert(dibs.Disputes.CreateReport({
    category = "wrong_debit",
    transactionRef = original.transactionId,
  }))
  local actor = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
  return dibs, seasonId, original, request, actor
end

local function balanceCorrection(dibs, seasonId, original, request, actor)
  local guildKey = dibs.GetGuildKey()
  return {
    schemaVersion = 1,
    operationId = "rf0012-unit-operation-1",
    operationType = "DISPUTE_BALANCE_CORRECTION",
    guildKey = guildKey,
    ledgerId = "guild-primary",
    requestId = request.requestId,
    requestRevision = request.revision,
    evidenceId = request.evidence[1].evidenceId or false,
    originalTransactionId = original.transactionId,
    actor = actor,
    reason = "Unit test correction",
    timestamp = 1700000000,
    signedEntries = {
      {
        operationId = "rf0012-unit-operation-1",
        entryIndex = 1,
        transactionId = "rf0012-unit-entry-1",
        guildKey = guildKey,
        ledgerId = "guild-primary",
        memberKey = actor.memberKey,
        seasonId = seasonId,
        actionType = "DIB_ADMIN_ADJUSTMENT",
        quantityDelta = 1,
        evidenceId = request.evidence[1].evidenceId or false,
        originalTransactionId = original.transactionId,
        requestId = request.requestId,
        requestRevision = request.revision,
      },
    },
  }
end

local function attributionResolution(dibs, request, actor)
  local guildKey = dibs.GetGuildKey()
  return {
    schemaVersion = 1,
    operationId = "rf0012-unit-attribution-1",
    operationType = "DISPUTE_ATTRIBUTION_RESOLUTION",
    guildKey = guildKey,
    ledgerId = "guild-primary",
    requestId = request.requestId,
    requestRevision = request.revision,
    evidenceId = false,
    originalTransactionId = false,
    actor = actor,
    reason = "Attribution-only unit test",
    timestamp = 1700000000,
    signedEntries = {},
  }
end

local function payloadHash(dibs, operation)
  local calculate = dibs.Ledger.CalculateDisputeOperationPayloadHash
  assert_true(type(calculate) == "function", "Ledger.CalculateDisputeOperationPayloadHash is not implemented")
  return calculate(operation)
end

local function validate(dibs, operation)
  local validator = dibs.Ledger.ValidateDisputeOperation
  assert_true(type(validator) == "function", "Ledger.ValidateDisputeOperation is not implemented")
  return validator(operation)
end

local function rehash(dibs, operation)
  operation.payloadHash = payloadHash(dibs, operation)
  return operation
end

local function operationCommit(operation, ledgerId, sequence)
  return {
    schema = 1,
    recordClass = "LEDGER_OPERATION_COMMIT",
    protocolVersion = 1,
    guildKey = operation.guildKey,
    ledgerId = ledgerId,
    ledgerEpoch = 4,
    sequence = sequence,
    previousHash = "GENESIS",
    payloadHash = operation.payloadHash,
    proposer = {
      memberKey = operation.actor.memberKey,
      displayName = operation.actor.displayName,
      authority = "GUILD_MASTER",
    },
    coordinator = { memberKey = operation.actor.memberKey, displayName = operation.actor.displayName },
    operation = operation,
    commitHash = "test-commit-" .. tostring(sequence),
  }
end

local function reverseInsert(value)
  if type(value) ~= "table" then return value end
  local keys, result = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(first, second) return tostring(first) < tostring(second) end)
  for index = #keys, 1, -1 do
    local key = keys[index]
    result[key] = reverseInsert(value[key])
  end
  return result
end

describe("Canonical Ledger Operation v1", function()
  it("validates required fields and the contract's explicit absent values", function()
    local dibs, seasonId, original, request, actor = setup()
    local validOperation = rehash(dibs, balanceCorrection(dibs, seasonId, original, request, actor))
    local valid, reason = validate(dibs, validOperation)
    assert_true(valid, tostring(reason))

    local absentFields = {
      "schemaVersion",
      "operationId",
      "operationType",
      "guildKey",
      "ledgerId",
      "requestId",
      "requestRevision",
      "evidenceId",
      "originalTransactionId",
      "actor",
      "reason",
      "timestamp",
      "signedEntries",
    }
    for _, field in ipairs(absentFields) do
      local candidate = dibs.DeepCopy(validOperation)
      candidate[field] = nil
      rehash(dibs, candidate)
      local accepted = validate(dibs, candidate)
      assert_false(accepted, "missing required field accepted: " .. field)
    end

    local absentEntryFields = {
      "operationId",
      "entryIndex",
      "transactionId",
      "guildKey",
      "ledgerId",
      "memberKey",
      "seasonId",
      "actionType",
      "quantityDelta",
      "evidenceId",
      "originalTransactionId",
      "requestId",
      "requestRevision",
    }
    for _, field in ipairs(absentEntryFields) do
      local candidate = dibs.DeepCopy(validOperation)
      candidate.signedEntries[1][field] = nil
      rehash(dibs, candidate)
      local accepted = validate(dibs, candidate)
      assert_false(accepted, "missing required entry field accepted: " .. field)
    end

    local absentPayloadHash = dibs.DeepCopy(validOperation)
    absentPayloadHash.payloadHash = nil
    local accepted = validate(dibs, absentPayloadHash)
    assert_false(accepted, "missing payloadHash accepted")

    local attribution = rehash(dibs, attributionResolution(dibs, request, actor))
    local attributionAccepted, attributionReason = validate(dibs, attribution)
    assert_true(attributionAccepted, tostring(attributionReason))

    local missingOriginal = dibs.DeepCopy(validOperation)
    missingOriginal.originalTransactionId = false
    missingOriginal.signedEntries[1].originalTransactionId = false
    rehash(dibs, missingOriginal)
    assert_false(validate(dibs, missingOriginal), "balance correction accepted an absent original transaction")

    local implicitEvidence = dibs.DeepCopy(validOperation)
    implicitEvidence.evidenceId = nil
    implicitEvidence.signedEntries[1].evidenceId = nil
    rehash(dibs, implicitEvidence)
    assert_false(validate(dibs, implicitEvidence), "implicit absent evidence accepted")
  end)

  it("accepts only supported schema versions and operation types", function()
    local dibs, seasonId, original, request, actor = setup()
    local balance = rehash(dibs, balanceCorrection(dibs, seasonId, original, request, actor))
    assert_true(validate(dibs, balance))

    local target = dibs.DeepCopy(balance)
    target.operationId = "rf0012-unit-transfer-1"
    target.operationType = "DISPUTE_TARGET_TRANSFER"
    target.signedEntries[1].operationId = target.operationId
    target.signedEntries[1].quantityDelta = 1
    local otherIdentity = assert(dibs.Identity.CreateSnapshot("Other-Realm"))
    target.signedEntries[1].memberKey = actor.memberKey
    target.signedEntries[2] = dibs.DeepCopy(target.signedEntries[1])
    target.signedEntries[2].entryIndex = 2
    target.signedEntries[2].transactionId = "rf0012-unit-entry-2"
    target.signedEntries[2].memberKey = otherIdentity.memberKey
    target.signedEntries[2].quantityDelta = -1
    rehash(dibs, target)
    assert_true(validate(dibs, target))

    local attribution = rehash(dibs, attributionResolution(dibs, request, actor))
    assert_true(validate(dibs, attribution))

    local unsupportedVersion = dibs.DeepCopy(balance)
    unsupportedVersion.schemaVersion = 2
    rehash(dibs, unsupportedVersion)
    assert_false(validate(dibs, unsupportedVersion), "unsupported schema version accepted")

    local unsupportedType = dibs.DeepCopy(balance)
    unsupportedType.operationType = "NO_CORRECTION"
    rehash(dibs, unsupportedType)
    assert_false(validate(dibs, unsupportedType), "unsupported operation type accepted")
  end)

  it("validates the complete correction matrix without changing SavedVariables", function()
    local dibs, seasonId, original, request, actor = setup()
    local base = balanceCorrection(dibs, seasonId, original, request, actor)
    local candidates = {}
    local function addInvalid(name, candidate)
      rehash(dibs, candidate)
      candidates[#candidates + 1] = { name = name, operation = candidate }
    end
    local function invalidBalance(name, mutate)
      local candidate = dibs.DeepCopy(base)
      mutate(candidate)
      addInvalid(name, candidate)
    end
    local function makeTransfer()
      local candidate = dibs.DeepCopy(base)
      local otherIdentity = assert(dibs.Identity.CreateSnapshot("Other-Realm"))
      candidate.operationId = "rf0012-unit-transfer-matrix"
      candidate.operationType = "DISPUTE_TARGET_TRANSFER"
      candidate.signedEntries[1].operationId = candidate.operationId
      candidate.signedEntries[1].actionType = "DIB_ADMIN_ADJUSTMENT"
      candidate.signedEntries[1].quantityDelta = 1
      candidate.signedEntries[2] = dibs.DeepCopy(candidate.signedEntries[1])
      candidate.signedEntries[2].entryIndex = 2
      candidate.signedEntries[2].transactionId = "rf0012-unit-transfer-entry-2"
      candidate.signedEntries[2].memberKey = otherIdentity.memberKey
      candidate.signedEntries[2].quantityDelta = -1
      return candidate
    end

    invalidBalance("wrong guild", function(candidate)
      candidate.guildKey = candidate.guildKey .. "-foreign"
      candidate.signedEntries[1].guildKey = candidate.guildKey
    end)
    invalidBalance("unapproved/missing ledger", function(candidate)
      candidate.ledgerId = "unapproved-ledger"
      candidate.signedEntries[1].ledgerId = candidate.ledgerId
    end)
    invalidBalance("unknown request", function(candidate)
      candidate.requestId = "unknown-request"
      candidate.signedEntries[1].requestId = candidate.requestId
    end)
    invalidBalance("stale request revision", function(candidate)
      candidate.requestRevision = candidate.requestRevision + 1
      candidate.signedEntries[1].requestRevision = candidate.requestRevision
    end)
    invalidBalance("unknown evidence", function(candidate)
      candidate.evidenceId = "unknown-evidence"
      candidate.signedEntries[1].evidenceId = candidate.evidenceId
    end)
    invalidBalance("unknown original transaction", function(candidate)
      candidate.originalTransactionId = "unknown-original"
      candidate.signedEntries[1].originalTransactionId = candidate.originalTransactionId
    end)
    invalidBalance("duplicate transaction identity in entries", function(candidate)
      candidate.signedEntries[2] = dibs.DeepCopy(candidate.signedEntries[1])
      candidate.signedEntries[2].entryIndex = 2
      candidate.signedEntries[2].transactionId = candidate.signedEntries[1].transactionId
    end)
    invalidBalance("invalid signed action", function(candidate)
      candidate.signedEntries[1].actionType = "DIB_REFUNDED"
      candidate.signedEntries[1].quantityDelta = -1
    end)
    invalidBalance("unsupported dispute action", function(candidate)
      candidate.signedEntries[1].actionType = "DIB_REVOKED"
      candidate.signedEntries[1].quantityDelta = -1
    end)
    invalidBalance("quantity exceeds Ledger limit", function(candidate)
      candidate.signedEntries[1].quantityDelta = 100001
    end)
    invalidBalance("unknown member", function(candidate)
      candidate.signedEntries[1].memberKey = "unknown-realm"
    end)
    invalidBalance("unknown season", function(candidate)
      candidate.signedEntries[1].seasonId = "unknown-season"
    end)

    local invalidSecondLeg = makeTransfer()
    invalidSecondLeg.signedEntries[2].quantityDelta = -2
    addInvalid("invalid second transfer leg and nonzero net", invalidSecondLeg)
    local duplicateTransferId = makeTransfer()
    duplicateTransferId.signedEntries[2].transactionId = duplicateTransferId.signedEntries[1].transactionId
    addInvalid("duplicate transfer transaction ID", duplicateTransferId)
    local mismatchedParent = makeTransfer()
    mismatchedParent.signedEntries[2].operationId = "another-operation"
    addInvalid("mismatched entry parent", mismatchedParent)
    local malformedArray = makeTransfer()
    malformedArray.signedEntries[1] = nil
    addInvalid("sparse entry array", malformedArray)
    local wrongTransferSource = makeTransfer()
    wrongTransferSource.signedEntries[1].memberKey = wrongTransferSource.signedEntries[2].memberKey
    addInvalid("transfer does not reverse original member", wrongTransferSource)

    for _, item in ipairs(candidates) do
      local before = dibs.DeepCopy(dibs.GetDB())
      local accepted, reason = validate(dibs, item.operation)
      assert_false(accepted, item.name .. " accepted (" .. tostring(reason) .. ")")
      assert_true(sameValue(before, dibs.GetDB()), item.name .. " changed SavedVariables")
    end

    local previousStatus = request.status
    request.status = dibs.Disputes.STATUSES.RESOLVED
    local closedRequestOperation = rehash(dibs, dibs.DeepCopy(base))
    local resolvedBefore = dibs.DeepCopy(dibs.GetDB())
    local resolvedAccepted = validate(dibs, closedRequestOperation)
    assert_false(resolvedAccepted, "resolved dispute accepted a correction")
    assert_true(sameValue(resolvedBefore, dibs.GetDB()), "resolved request validation changed SavedVariables")
    request.status = previousStatus

    local validOperations = {
      rehash(dibs, dibs.DeepCopy(base)),
      rehash(dibs, makeTransfer()),
      rehash(dibs, attributionResolution(dibs, request, actor)),
    }
    for _, candidate in ipairs(validOperations) do
      local before = dibs.DeepCopy(dibs.GetDB())
      local accepted, reason = validate(dibs, candidate)
      assert_true(accepted, tostring(reason))
      assert_true(sameValue(before, dibs.GetDB()), "valid operation validation changed SavedVariables")
    end

    local supportedActions = {
      { actionType = "DIB_USED", quantityDelta = -1 },
      { actionType = "DIB_REFUNDED", quantityDelta = 1 },
      { actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1 },
      { actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1 },
    }
    for _, action in ipairs(supportedActions) do
      local candidate = dibs.DeepCopy(base)
      candidate.signedEntries[1].actionType = action.actionType
      candidate.signedEntries[1].quantityDelta = action.quantityDelta
      rehash(dibs, candidate)
      local accepted, reason = validate(dibs, candidate)
      assert_true(accepted, tostring(reason))
    end

    local attributionWithEntry = attributionResolution(dibs, request, actor)
    attributionWithEntry.signedEntries = { dibs.DeepCopy(base.signedEntries[1]) }
    rehash(dibs, attributionWithEntry)
    assert_false(validate(dibs, attributionWithEntry), "attribution-only operation accepted a balance entry")
  end)

  it("hashes equivalent key orders deterministically and excludes payloadHash itself", function()
    local dibs, seasonId, original, request, actor = setup()
    local operation = balanceCorrection(dibs, seasonId, original, request, actor)
    local firstHash = payloadHash(dibs, operation)
    local reorderedHash = payloadHash(dibs, reverseInsert(operation))
    assert_true(type(firstHash) == "string" and firstHash ~= "")
    assert_equal(firstHash, payloadHash(dibs, operation))
    assert_equal(firstHash, reorderedHash)

    operation.payloadHash = "not-part-of-the-payload-hash"
    assert_equal(firstHash, payloadHash(dibs, operation))
  end)

  it("rebuilds an operation from stable supplied IDs without allocating or persisting intent", function()
    local dibs, seasonId, original, request, actor = setup()
    local intent = balanceCorrection(dibs, seasonId, original, request, actor)
    local before = dibs.DeepCopy(dibs.GetDB())
    local originalNewId = dibs.NewId
    local allocations = 0
    dibs.NewId = function(...)
      allocations = allocations + 1
      return originalNewId(...)
    end
    local build = dibs.Ledger.BuildDisputeOperation
    assert_true(type(build) == "function", "Ledger.BuildDisputeOperation is not implemented")
    local first, firstReason = build(intent)
    local second, secondReason = build(intent)
    dibs.NewId = originalNewId

    assert_true(type(first) == "table", tostring(firstReason))
    assert_true(type(second) == "table", tostring(secondReason))
    assert_equal(0, allocations, "Ledger allocated an intent ID instead of using supplied Governance IDs")
    assert_equal(intent.operationId, first.operationId)
    assert_equal(intent.signedEntries[1].transactionId, first.signedEntries[1].transactionId)
    assert_equal(intent.timestamp, first.timestamp)
    assert_equal(first.payloadHash, second.payloadHash)
    assert_true(sameValue(first, second), "the same stable intent produced different operation content")
    assert_nil(intent.payloadHash, "builder mutated the supplied intent")
    assert_true(sameValue(before, dibs.GetDB()), "building an operation changed SavedVariables")
  end)

  it("detects changes to every immutable operation and entry field", function()
    local dibs, seasonId, original, request, actor = setup()
    local operation = balanceCorrection(dibs, seasonId, original, request, actor)
    local originalHash = payloadHash(dibs, operation)
    local mutations = {
      { name = "schemaVersion", apply = function(value) value.schemaVersion = 2 end },
      { name = "operationId", apply = function(value) value.operationId = value.operationId .. "-changed" end },
      { name = "operationType", apply = function(value) value.operationType = "DISPUTE_ATTRIBUTION_RESOLUTION" end },
      { name = "guildKey", apply = function(value) value.guildKey = value.guildKey .. "-changed" end },
      { name = "ledgerId", apply = function(value) value.ledgerId = "other-ledger" end },
      { name = "requestId", apply = function(value) value.requestId = value.requestId .. "-changed" end },
      { name = "requestRevision", apply = function(value) value.requestRevision = value.requestRevision + 1 end },
      { name = "evidenceId", apply = function(value) value.evidenceId = "other-evidence" end },
      { name = "originalTransactionId", apply = function(value) value.originalTransactionId = "other-original" end },
      { name = "actor", apply = function(value) value.actor.displayName = "Other-Realm" end },
      { name = "reason", apply = function(value) value.reason = value.reason .. " changed" end },
      { name = "timestamp", apply = function(value) value.timestamp = value.timestamp + 1 end },
      { name = "actor.memberKey", apply = function(value) value.actor.memberKey = value.actor.memberKey .. "-changed" end },
      { name = "entry.transactionId", apply = function(value) value.signedEntries[1].transactionId = "other-entry" end },
      { name = "entry.operationId", apply = function(value) value.signedEntries[1].operationId = "other-operation" end },
      { name = "entry.guildKey", apply = function(value) value.signedEntries[1].guildKey = value.signedEntries[1].guildKey .. "-changed" end },
      { name = "entry.ledgerId", apply = function(value) value.signedEntries[1].ledgerId = "other-ledger" end },
      { name = "entry.memberKey", apply = function(value) value.signedEntries[1].memberKey = value.signedEntries[1].memberKey .. "-changed" end },
      { name = "entry.seasonId", apply = function(value) value.signedEntries[1].seasonId = "other-season" end },
      { name = "entry.actionType", apply = function(value) value.signedEntries[1].actionType = "DIB_REVOKED" end },
      { name = "entry.quantityDelta", apply = function(value) value.signedEntries[1].quantityDelta = -1 end },
      { name = "entry.entryIndex", apply = function(value) value.signedEntries[1].entryIndex = 2 end },
      { name = "entry.evidenceId", apply = function(value) value.signedEntries[1].evidenceId = "other-evidence" end },
      { name = "entry.originalTransactionId", apply = function(value) value.signedEntries[1].originalTransactionId = "other-original" end },
      { name = "entry.requestId", apply = function(value) value.signedEntries[1].requestId = value.signedEntries[1].requestId .. "-changed" end },
      { name = "entry.requestRevision", apply = function(value) value.signedEntries[1].requestRevision = value.signedEntries[1].requestRevision + 1 end },
    }
    for _, mutation in ipairs(mutations) do
      local candidate = dibs.DeepCopy(operation)
      mutation.apply(candidate)
      assert_true(payloadHash(dibs, candidate) ~= originalHash, "immutable field omitted from payload hash: " .. mutation.name)
    end
  end)

  it("rejects tampered payload hashes and unsupported ledger actions", function()
    local dibs, seasonId, original, request, actor = setup()
    local operation = rehash(dibs, balanceCorrection(dibs, seasonId, original, request, actor))

    local tampered = dibs.DeepCopy(operation)
    tampered.reason = "changed after hashing"
    local tamperedAccepted, tamperedReason = validate(dibs, tampered)
    assert_false(tamperedAccepted, tostring(tamperedReason))

    local unsupportedAction = dibs.DeepCopy(operation)
    unsupportedAction.signedEntries[1].actionType = "UNSUPPORTED_ACCOUNTING_ACTION"
    rehash(dibs, unsupportedAction)
    local actionAccepted, actionReason = validate(dibs, unsupportedAction)
    assert_false(actionAccepted, tostring(actionReason))
  end)

  it("rebuilds guild-wide identity indexes and distinguishes replay from conflicts", function()
    local dibs, seasonId, original, request, actor = setup()
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local operation = rehash(dibs, balanceCorrection(dibs, seasonId, original, request, actor))
    local check = dibs.Ledger.CheckDisputeOperationReplay
    assert_true(type(check) == "function", "Ledger.CheckDisputeOperationReplay is not implemented")
    local function checkWithoutMutation(candidate)
      local before = dibs.DeepCopy(dibs.GetDB())
      local result, reason = check(candidate)
      assert_true(type(result) == "table", tostring(reason))
      assert_true(sameValue(before, dibs.GetDB()), "operation replay check changed SavedVariables")
      return result
    end

    local unseen = checkWithoutMutation(operation)
    assert_equal("NEW", unseen.status)
    ledger.canonical.commits["4:1"] = operationCommit(operation, "guild-primary", 1)

    local replay = checkWithoutMutation(operation)
    assert_equal("REPLAY", replay.status)
    assert_equal("IDEMPOTENT_REPLAY", replay.reasonCode)

    local changed = dibs.DeepCopy(operation)
    changed.reason = changed.reason .. " changed"
    rehash(dibs, changed)
    local changedResult = checkWithoutMutation(changed)
    assert_equal("CONFLICT", changedResult.status)
    assert_equal("OPERATION_ID_CONFLICT", changedResult.reasonCode)

    local collisionStored = dibs.DeepCopy(operation)
    collisionStored.reason = collisionStored.reason .. " collision-shaped content"
    collisionStored.payloadHash = operation.payloadHash
    ledger.canonical.commits["4:1"] = operationCommit(collisionStored, "guild-primary", 1)
    local collisionResult = checkWithoutMutation(operation)
    assert_equal("CONFLICT", collisionResult.status)
    assert_equal("OPERATION_ID_CONFLICT", collisionResult.reasonCode)

    local otherLedger = dibs.DeepCopy(operation)
    otherLedger.ledgerId = "raid-secondary"
    otherLedger.signedEntries[1].ledgerId = otherLedger.ledgerId
    rehash(dibs, otherLedger)
    local otherLedgerResult = checkWithoutMutation(otherLedger)
    assert_equal("CONFLICT", otherLedgerResult.status)
    assert_equal("OPERATION_ID_CONFLICT", otherLedgerResult.reasonCode)

    local awardTransactionId = "rf0012-existing-award-transaction"
    ledger.canonical.commits["4:2"] = {
      schema = 1,
      recordClass = "AWARD_COMMIT",
      guildKey = operation.guildKey,
      ledgerEpoch = 4,
      sequence = 2,
      canonicalTransactionId = awardTransactionId,
      transaction = { transactionId = awardTransactionId },
      commitHash = "test-award-commit",
    }
    local transactionCollision = dibs.DeepCopy(operation)
    transactionCollision.operationId = "rf0012-unit-operation-award-collision"
    transactionCollision.signedEntries[1].operationId = transactionCollision.operationId
    transactionCollision.signedEntries[1].transactionId = awardTransactionId
    rehash(dibs, transactionCollision)
    local transactionResult = checkWithoutMutation(transactionCollision)
    assert_equal("CONFLICT", transactionResult.status)
    assert_equal("TRANSACTION_ID_CONFLICT", transactionResult.reasonCode)

    local otherDibs, otherSeason, otherOriginal, otherRequest, otherActor = setup()
    local primaryOperation = rehash(
      otherDibs,
      balanceCorrection(otherDibs, otherSeason, otherOriginal, otherRequest, otherActor)
    )
    local secondaryOperation = otherDibs.DeepCopy(primaryOperation)
    secondaryOperation.ledgerId = "raid-secondary"
    secondaryOperation.signedEntries[1].ledgerId = secondaryOperation.ledgerId
    rehash(otherDibs, secondaryOperation)
    otherDibs.GetDB().ledgers["raid-secondary"] = {
      id = "raid-secondary",
      status = "APPROVED",
      transactions = {},
      canonical = {
        commits = { ["4:1"] = operationCommit(secondaryOperation, "raid-secondary", 1) },
      },
    }
    local otherBefore = otherDibs.DeepCopy(otherDibs.GetDB())
    local crossLedgerReplay = otherDibs.Ledger.CheckDisputeOperationReplay(primaryOperation)
    assert_true(type(crossLedgerReplay) == "table", "cross-ledger check failed")
    assert_equal("CONFLICT", crossLedgerReplay.status)
    assert_equal("OPERATION_ID_CONFLICT", crossLedgerReplay.reasonCode)
    assert_true(sameValue(otherBefore, otherDibs.GetDB()), "cross-ledger index check changed SavedVariables")
  end)
end)
