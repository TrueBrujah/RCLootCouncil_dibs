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
    "isolated Lua runtime must expose the existing private writer seams")
  for index = 1, 64 do
    local name = debug.getupvalue(fn, index)
    if name == nil then break end
    if name == expectedName then debug.setupvalue(fn, index, value); return end
  end
  error("missing existing writer test seam: " .. expectedName, 2)
end

local function setup(operationId, secondary)
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Other-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
  } })
  local ledgerId = "guild-primary"
  if secondary then
    local proposed = dibs.MultiLedger.ProposeLedger(nil, "Canonical recovery split")
    assert_true(proposed.ok)
    ledgerId = proposed.ledgerId
    assert_true(dibs.MultiLedger.ApproveLedger(nil, ledgerId).ok)
    assert_true(dibs.MultiLedger.SetActiveLedger(ledgerId))
  end
  local seasonId = dibs.GetCurrentSeasonId()
  if secondary then
    assert_not_nil(dibs.Ledger.RegisterSeasonAllocation("Tester-Realm", seasonId, 1, "Secondary fixture allocation"))
  end
  local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
    transactionId = operationId .. "-original",
  }), ledgerId))
  local legacy = assert(dibs.Ledger.AddTransaction(fixtures.transaction("Other-Realm", seasonId, {
    transactionId = operationId .. "-legacy", type = "DIB_GRANTED", amount = 2,
  }), ledgerId))
  local request = assert(dibs.Disputes.CreateReport({ category = "wrong_debit", transactionRef = original.transactionId }))
  local actor = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
  local evidenceId = request.evidence[1].evidenceId or false
  local operation = assert(dibs.Ledger.BuildDisputeOperation({
    schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_BALANCE_CORRECTION",
    guildKey = dibs.GetGuildKey(), ledgerId = ledgerId, requestId = request.requestId,
    requestRevision = request.revision, evidenceId = evidenceId,
    originalTransactionId = original.transactionId, actor = actor, reason = "operation recovery fixture",
    timestamp = 1700000000, signedEntries = {{
      operationId = operationId, entryIndex = 1, transactionId = operationId .. "-entry",
      guildKey = dibs.GetGuildKey(), ledgerId = ledgerId, memberKey = actor.memberKey,
      seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
      evidenceId = evidenceId, originalTransactionId = original.transactionId,
      requestId = request.requestId, requestRevision = request.revision,
    }},
  }))

  assert(dibs.Governance.AdoptInitial(nil, { reason = "operation recovery fixture" }))
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  assert(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = actor, ledgerEpoch = 7,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
  assert(dibs.Governance.IsV2Enforced())
  assert(dibs.Ledger.GetCanonicalState(ledgerId))
  assert(dibs.Ledger.Grant("Other-Realm", 1, "recovery fixture grant", "test", seasonId, nil, ledgerId))
  local award = dibs.Ledger.CommitDibUse({ actor = "Tester-Realm", action = "ledger.use", ledgerId = ledgerId }, {
    transactionId = operationId .. "-award", playerName = "Other-Realm", seasonId = seasonId,
    amount = 1, reason = "recovery fixture canonical award",
  })
  assert_true(award and award.accepted, tostring(award and award.reasonCode))

  local writer = dibs.Ledger.CommitDisputeOperation
  replaceUpvalue(writer, "DISPUTE_OPERATION_WRITES_ENABLED", true)
  replaceUpvalue(writer, "operationReadinessProbe", function() return true end)
  dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
  local result = writer({ actor = "Tester-Realm", ledgerId = ledgerId }, operation)
  assert_true(result.accepted, tostring(result.reasonCode))
  assert_false(result.idempotentReplay)
  return dibs, operation, original, legacy, result.value, ledgerId
end

local function removeOperationProjection(ledger, operation)
  for _, entry in ipairs(operation.signedEntries) do
    ledger.transactions[entry.transactionId] = nil
    ledger.canonical.transactionIndex[entry.transactionId] = nil
  end
  ledger.canonical.positions = {}
  ledger.playerStates = {}
  ledger.awardTransactions = {}
  ledger.evidenceTransactions = {}
end

describe("Canonical dispute operation projection recovery", function()
  it("refuses a cross-ledger operation identity conflict before repairing any projection", function()
    local dibs, operation = setup("rf0012-recovery-cross-scope")
    local db = dibs.GetDB()
    assert_true(dibs.Disputes.ReconstructOperationStates("guild-primary").rebuilt)
    db.disputes.operationStates[operation.operationId].ledgerId = "foreign-ledger"
    removeOperationProjection(db.ledgers["guild-primary"], operation)
    local before = dibs.DeepCopy(db)
    local result = dibs.Disputes.ReconstructOperationStates("guild-primary")
    assert_false(result.rebuilt)
    assert_equal("OPERATION_ID_CONFLICT", result.reasonCode)
    assert_true(sameValue(before, db), "conflict refusal applied a partial projection repair")
  end)

  it("reconstructs a nonempty secondary journal at startup against the accepted balance oracle", function()
    local dibs, operation, original, legacy, commit, ledgerId = setup("rf0012-secondary-operation", true)
    local ledger = dibs.GetDB().ledgers[ledgerId]
    local beforeBalance = dibs.Ledger.GetBalance("Tester-Realm", operation.signedEntries[1].seasonId, ledgerId)
    local sequence, root = ledger.canonical.nextSeq, ledger.canonical.rootHash
    removeOperationProjection(ledger, operation)
    dibs.GetDB().disputes.operationStates = {}
    dibs.initialized = false
    assert_true(dibs.Initialize())
    assert_true(dibs.canonicalOperationRecoveryStatuses[ledgerId].rebuilt)
    assert_equal(beforeBalance, dibs.Ledger.GetBalance("Tester-Realm", operation.signedEntries[1].seasonId, ledgerId))
    assert_equal(sequence, ledger.canonical.nextSeq)
    assert_equal(root, ledger.canonical.rootHash)
    assert_not_nil(ledger.transactions[original.transactionId])
    assert_not_nil(ledger.transactions[legacy.transactionId])
    assert_equal(commit.commitHash, dibs.GetDB().disputes.operationStates[operation.operationId].commitHash)
    assert_equal(ledgerId, dibs.GetDB().disputes.operationStates[operation.operationId].ledgerId)
  end)

  it("preserves accepted operation states in other ledgers while rebuilding one ledger", function()
    local dibs, operation = setup("rf0012-multiledger-state")
    assert_true(dibs.Disputes.ReconstructOperationStates("guild-primary").rebuilt)
    local accepted = dibs.DeepCopy(dibs.GetDB().disputes.operationStates[operation.operationId])
    assert_not_nil(accepted)
    local proposed = dibs.MultiLedger.ProposeLedger(nil, "Recovery split")
    assert_true(proposed.ok)
    assert_true(dibs.MultiLedger.ApproveLedger(nil, proposed.ledgerId).ok)
    assert_not_nil(dibs.Ledger.GetCanonicalState(proposed.ledgerId))
    assert_true(dibs.Disputes.ReconstructOperationStates(proposed.ledgerId).rebuilt)
    assert_true(sameValue(accepted, dibs.GetDB().disputes.operationStates[operation.operationId]),
      "recovering the empty split discarded primary operation evidence")
  end)

  it("validates secondary ledger startup independently and preserves its legacy rows and root", function()
    local dibs = setup("rf0012-secondary-startup")
    local proposed = dibs.MultiLedger.ProposeLedger(nil, "Startup split")
    assert_true(proposed.ok)
    local ledgerId = proposed.ledgerId
    assert_true(dibs.MultiLedger.ApproveLedger(nil, ledgerId).ok)
    assert_not_nil(dibs.Ledger.GetCanonicalState(ledgerId))
    assert_not_nil(dibs.Ledger.Grant("Other-Realm", 2, "Secondary legacy allocation", "test", dibs.GetCurrentSeasonId(), nil, ledgerId))
    local ledger = dibs.GetDB().ledgers[ledgerId]
    local before = dibs.DeepCopy(ledger.transactions)
    local sequence, root = ledger.canonical.nextSeq, ledger.canonical.rootHash
    dibs.initialized = false
    assert_true(dibs.Initialize())
    local recovery = dibs.canonicalOperationRecoveryStatuses and dibs.canonicalOperationRecoveryStatuses[ledgerId]
    assert_not_nil(recovery, "startup never checked the secondary ledger")
    assert_true(recovery.rebuilt, tostring(recovery.reasonCode))
    assert_equal(ledgerId, recovery.ledgerId)
    assert_equal(dibs.GetGuildKey(), recovery.guildKey)
    assert_equal(sequence, ledger.canonical.nextSeq)
    assert_equal(root, ledger.canonical.rootHash)
    assert_true(sameValue(before, ledger.transactions))
  end)

  it("rebuilds missing rows and indexes deterministically without advancing sequence or root", function()
    local dibs, operation, original, legacy, commit = setup("rf0012-recovery-success")
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local sequence, root = ledger.canonical.nextSeq, ledger.canonical.rootHash
    local expectedBalance = dibs.Ledger.GetBalance("Tester-Realm", operation.signedEntries[1].seasonId, "guild-primary")
    local awardCommit, awardRow
    for _, row in pairs(ledger.canonical.commits) do
      if row.recordClass == "AWARD_COMMIT" then awardCommit = row end
    end
    awardRow = ledger.transactions[operation.operationId .. "-award"]
    assert_equal("LEDGER_OPERATION_COMMIT", commit.recordClass)
    assert_not_nil(awardCommit, "fixture did not include the existing AWARD_COMMIT record")
    assert_not_nil(awardRow, "fixture did not include its award transaction projection")
    removeOperationProjection(ledger, operation)
    assert_nil(ledger.transactions[operation.signedEntries[1].transactionId])

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))
    assert_equal(sequence, ledger.canonical.nextSeq)
    assert_equal(root, ledger.canonical.rootHash)
    assert_equal("Tester-Realm", ledger.transactions[operation.signedEntries[1].transactionId].playerName)
    assert_equal(original.transactionId, ledger.transactions[original.transactionId].transactionId)
    assert_equal(legacy.transactionId, ledger.transactions[legacy.transactionId].transactionId)
    assert_equal(awardCommit.commitHash, ledger.canonical.commits[
      tostring(awardCommit.ledgerEpoch) .. ":" .. tostring(awardCommit.sequence)].commitHash,
      "rebuild changed the existing AWARD_COMMIT")
    assert_not_nil(ledger.transactions[operation.operationId .. "-award"], "rebuild dropped the AWARD_COMMIT transaction")
    assert_equal(expectedBalance, dibs.Ledger.GetBalance("Tester-Realm", operation.signedEntries[1].seasonId, "guild-primary"))
    assert_equal(tostring(commit.ledgerEpoch) .. ":" .. tostring(commit.sequence),
      ledger.canonical.transactionIndex[operation.signedEntries[1].transactionId])

    local afterFirst = dibs.DeepCopy(ledger.transactions)
    local second = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(second.rebuilt, tostring(second.reasonCode))
    assert_equal(sequence, ledger.canonical.nextSeq)
    assert_equal(root, ledger.canonical.rootHash)
    assert_true(sameValue(afterFirst, ledger.transactions), "second rebuild changed row identifiers or content")
    assert_equal(expectedBalance, dibs.Ledger.GetBalance("Tester-Realm", operation.signedEntries[1].seasonId, "guild-primary"))
  end)

  it("rejects altered commit hash, operation hash, and scope without changing projections", function()
    local dibs, operation, _, _, operationCommit = setup("rf0012-recovery-reject")
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local commitKey = tostring(operationCommit.ledgerEpoch) .. ":" .. tostring(operationCommit.sequence)
    local commit = ledger.canonical.commits[commitKey]
    assert_not_nil(commit)
    local originalCommit = dibs.DeepCopy(commit)
    local cases = {
      { reason = "CANONICAL_COMMIT_HASH_MISMATCH", mutate = function(value) value.commitHash = "tampered-commit-hash" end },
      { reason = "CANONICAL_OPERATION_HASH_MISMATCH", mutate = function(value) value.operation.reason = "tampered operation" end },
      { reason = "CANONICAL_SCOPE_MISMATCH", mutate = function(value) value.ledgerId = "foreign-ledger" end },
    }
    for _, case in ipairs(cases) do
      ledger.canonical.commits[commitKey] = dibs.DeepCopy(originalCommit)
      case.mutate(ledger.canonical.commits[commitKey])
      local before = dibs.DeepCopy(dibs.GetDB())
      local rejected = dibs.Ledger.RebuildLedgerProjections("guild-primary")
      assert_false(rejected.rebuilt, case.reason .. " accepted")
      assert_equal(case.reason, rejected.reasonCode, tostring(rejected.reasonCode))
      assert_true(sameValue(before, dibs.GetDB()), case.reason .. " changed projections")
    end
    ledger.canonical.commits[commitKey] = originalCommit
    assert_true(operation.operationId == originalCommit.operation.operationId)
  end)
end)
