local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

local function sameValue(first, second, seen)
  if type(first) ~= type(second) then return false end
  if type(first) ~= "table" then return first == second end
  seen = seen or {}
  if seen[first] == second then return true end
  seen[first] = second
  for key, value in pairs(first) do if not sameValue(value, second[key], seen) then return false end end
  for key in pairs(second) do if first[key] == nil then return false end end
  return true
end

local function replaceUpvalue(fn, expectedName, value)
  assert_true(type(debug) == "table" and type(debug.getupvalue) == "function" and type(debug.setupvalue) == "function",
    "the isolated Lua test runtime must expose private test seams")
  for index = 1, 64 do
    local name = debug.getupvalue(fn, index)
    if name == nil then break end
    if name == expectedName then debug.setupvalue(fn, index, value); return end
  end
  error("missing existing writer test seam: " .. expectedName, 2)
end

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Other-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
  } })
  return dibs
end

local function activateAuthority(dibs)
  assert(dibs.Governance.AdoptInitial(nil, { reason = "operation writer unit fixture" }))
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
  assert(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 7,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
  assert(dibs.Governance.IsV2Enforced())
end

local function prepareOperation(dibs, operationId)
  local seasonId = dibs.GetCurrentSeasonId()
  local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
    transactionId = operationId .. "-original",
  }), "guild-primary"))
  local request = assert(dibs.Disputes.CreateReport({ category = "wrong_debit", transactionRef = original.transactionId }))
  local actor = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
  local evidenceId = request.evidence[1].evidenceId or false
  local operation = {
    schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_BALANCE_CORRECTION",
    guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", requestId = request.requestId,
    requestRevision = request.revision, evidenceId = evidenceId,
    originalTransactionId = original.transactionId, actor = actor, reason = "unit commit boundary",
    timestamp = 1700000000, signedEntries = {{
      operationId = operationId, entryIndex = 1, transactionId = operationId .. "-entry",
      guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = actor.memberKey,
      seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      requestId = request.requestId, requestRevision = request.revision,
    }},
  }
  return assert(dibs.Ledger.BuildDisputeOperation(operation))
end

local function prepareAttributionOperation(dibs, operationId)
  local operation = dibs.DeepCopy(prepareOperation(dibs, operationId))
  operation.operationType = "DISPUTE_ATTRIBUTION_RESOLUTION"
  operation.originalTransactionId = false
  operation.evidenceId = false
  operation.signedEntries = {}
  operation.payloadHash = dibs.Ledger.CalculateDisputeOperationPayloadHash(operation)
  return assert(dibs.Ledger.BuildDisputeOperation(operation))
end

local function enableWriterForThisTest(dibs)
  local writer = dibs.Ledger.CommitDisputeOperation
  replaceUpvalue(writer, "DISPUTE_OPERATION_WRITES_ENABLED", true)
  replaceUpvalue(writer, "operationReadinessProbe", function() return true end)
  dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
  return writer
end

describe("Canonical dispute operation commit boundary", function()
  it("stays fail-closed with zero mutation while the production gate is closed", function()
    local dibs = setup()
    local writer = dibs.Ledger.CommitDisputeOperation
    local before = dibs.DeepCopy(dibs.GetDB())
    local result = writer({}, {})
    assert_false(result.accepted)
    assert_equal("CANONICAL_OPERATION_WRITES_DISABLED", result.reasonCode)
    assert_true(sameValue(before, dibs.GetDB()), "closed writer changed SavedVariables")
  end)

  it("commits a zero-entry attribution resolution once, replays idempotently, and rejects changed content", function()
    local dibs = setup()
    local operation = prepareAttributionOperation(dibs, "rf0012-attribution-commit")
    assert_equal(0, #operation.signedEntries)
    assert_equal(false, operation.originalTransactionId)
    activateAuthority(dibs)
    assert(dibs.Ledger.GetCanonicalState("guild-primary"))
    local writer = enableWriterForThisTest(dibs)
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local startSequence = ledger.canonical.nextSeq
    local beforeTransactions = dibs.DeepCopy(ledger.transactions)
    local beforeBalances = dibs.DeepCopy(ledger.balances)

    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, operation)
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_false(result.idempotentReplay)
    assert_equal(startSequence, result.value.sequence)
    assert_equal(startSequence + 1, ledger.canonical.nextSeq)
    assert_equal("LEDGER_OPERATION_COMMIT", result.value.recordClass)
    assert_true(sameValue(operation, result.value.operation))
    assert_true(sameValue(beforeTransactions, ledger.transactions), "attribution-only commit created a transaction")
    assert_true(sameValue(beforeBalances, ledger.balances), "attribution-only commit changed balances")

    local committedSequence, committedRoot = ledger.canonical.nextSeq, ledger.canonical.rootHash
    local replay = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, operation)
    assert_true(replay.accepted, tostring(replay.reasonCode))
    assert_true(replay.idempotentReplay)
    assert_equal(committedSequence, ledger.canonical.nextSeq)
    assert_equal(committedRoot, ledger.canonical.rootHash)
    assert_true(sameValue(beforeTransactions, ledger.transactions), "exact attribution replay created a transaction")
    assert_true(sameValue(beforeBalances, ledger.balances), "exact attribution replay changed balances")

    local conflict = dibs.DeepCopy(operation)
    conflict.reason = conflict.reason .. " changed"
    conflict.payloadHash = dibs.Ledger.CalculateDisputeOperationPayloadHash(conflict)
    local rejected = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, conflict)
    assert_false(rejected.accepted)
    assert_equal("OPERATION_ID_CONFLICT", rejected.reasonCode)
    assert_equal(committedSequence, ledger.canonical.nextSeq)
    assert_equal(committedRoot, ledger.canonical.rootHash)
    assert_true(sameValue(beforeTransactions, ledger.transactions))
    assert_true(sameValue(beforeBalances, ledger.balances))
  end)

  it("does not bypass runtime readiness for zero-entry attribution resolutions", function()
    local dibs = setup()
    local operation = prepareAttributionOperation(dibs, "rf0012-attribution-not-ready")
    activateAuthority(dibs)
    assert(dibs.Ledger.GetCanonicalState("guild-primary"))
    local writer = enableWriterForThisTest(dibs)
    replaceUpvalue(writer, "operationReadinessProbe", function() return false, "SYNC_BEHIND" end)
    local before = dibs.DeepCopy(dibs.GetDB())

    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, operation)
    assert_false(result.accepted)
    assert_equal("SYNC_BEHIND", result.reasonCode)
    assert_true(sameValue(before, dibs.GetDB()), "not-ready attribution resolution mutated SavedVariables")
  end)

  it("uses only the private test seams and appends one immutable commit with replay/conflict guards", function()
    local dibs = setup()
    local operation = prepareOperation(dibs, "rf0012-commit-boundary")
    activateAuthority(dibs)
    -- Seed the canonical cursor from current coordinator authority before taking
    -- the write-boundary snapshot; this is normal runtime initialization.
    assert(dibs.Ledger.GetCanonicalState("guild-primary"))
    local writer = enableWriterForThisTest(dibs)
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local startSequence = ledger.canonical.nextSeq
    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, operation)
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_false(result.idempotentReplay)
    assert_equal(startSequence + 1, ledger.canonical.nextSeq, "commit did not advance the canonical cursor once")
    assert_equal(startSequence, result.value.sequence)
    assert_equal("LEDGER_OPERATION_COMMIT", result.value.recordClass)
    assert_true(sameValue(operation, result.value.operation), "accepted commit changed immutable operation content")

    local beforeSequence, beforeRoot = ledger.canonical.nextSeq, ledger.canonical.rootHash
    local beforeRows = dibs.DeepCopy(ledger.transactions)
    local replay = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, operation)
    assert_true(replay.accepted, tostring(replay.reasonCode))
    assert_true(replay.idempotentReplay)
    assert_equal(beforeSequence, ledger.canonical.nextSeq)
    assert_equal(beforeRoot, ledger.canonical.rootHash)
    assert_true(sameValue(beforeRows, ledger.transactions), "exact replay changed transaction projections")

    local conflict = dibs.DeepCopy(operation)
    conflict.reason = conflict.reason .. " changed"
    conflict.payloadHash = dibs.Ledger.CalculateDisputeOperationPayloadHash(conflict)
    local rejected = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, conflict)
    assert_false(rejected.accepted)
    assert_equal("OPERATION_ID_CONFLICT", rejected.reasonCode)
    assert_equal(beforeSequence, ledger.canonical.nextSeq, "conflicting replay advanced the cursor")
    assert_equal(beforeRoot, ledger.canonical.rootHash, "conflicting replay changed the root")
  end)

  it("commits both legs of a target transfer under one canonical sequence", function()
    local dibs = setup()
    local operation = prepareOperation(dibs, "rf0012-multi-entry-commit")
    operation.operationType = "DISPUTE_TARGET_TRANSFER"
    operation.signedEntries[1].quantityDelta = 2
    local other = assert(dibs.Identity.CreateSnapshot("Other-Realm"))
    local second = dibs.DeepCopy(operation.signedEntries[1])
    second.entryIndex = 2
    second.transactionId = "rf0012-multi-entry-commit-entry-2"
    second.memberKey = other.memberKey
    second.quantityDelta = -2
    operation.signedEntries[2] = second
    operation.payloadHash = dibs.Ledger.CalculateDisputeOperationPayloadHash(operation)
    operation = assert(dibs.Ledger.BuildDisputeOperation(operation))

    activateAuthority(dibs)
    assert(dibs.Ledger.GetCanonicalState("guild-primary"))
    local writer = enableWriterForThisTest(dibs)
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local startSequence = ledger.canonical.nextSeq
    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, operation)
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal(startSequence, result.value.sequence)
    assert_equal(startSequence + 1, ledger.canonical.nextSeq)
    assert_equal(result.value.commitHash, ledger.canonical.rootHash)
    assert_equal(2, #operation.signedEntries)
    for _, entry in ipairs(operation.signedEntries) do
      local row = ledger.transactions[entry.transactionId]
      assert_not_nil(row, "transfer leg missing its ledger projection")
      assert_equal(entry.quantityDelta, row.quantityDelta)
      assert_equal(tostring(result.value.ledgerEpoch) .. ":" .. tostring(startSequence),
        ledger.canonical.transactionIndex[entry.transactionId])
    end
  end)
end)
