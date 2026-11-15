local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

-- T031: backup, restore, and import behaviour for canonical operation
-- commits. The fixtures compare operation and transaction identifiers and
-- content, balances, sequence and root, and the preview result.

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
  local _, dibs = loader.load({ wow = {
    playerName = "Tester-Realm",
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Other-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1 },
  }, withAce3 = true })
  return dibs
end

local function buildAcceptedOperation(dibs, clientName, recipientName)
  local seasonId = dibs.GetCurrentSeasonId()
  local original = assert(dibs.Ledger.AddTransaction(fixtures.transaction(clientName, seasonId, {
    transactionId = "backup-original",
  }), "guild-primary"))
  local request = assert(dibs.Disputes.CreateReport({
    category = "wrong_item_player",
    transactionRef = original.transactionId,
    note = "backup fixture",
  }))
  -- The canonical writer requires the verified coordinator authority.
  if not dibs.Governance.IsV2Enforced() then
    assert(dibs.Governance.AdoptInitial(nil, { reason = "RF-0012 backup fixture" }))
    local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
    local identity = assert(dibs.Identity.CreateSnapshot(clientName))
    assert(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = identity, ledgerEpoch = 7,
      transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
    } } }))
    assert(dibs.Governance.EnableV2(nil, { clientName }))
  end
  local actor = assert(dibs.Identity.CreateSnapshot(clientName))
  local recipient = assert(dibs.Identity.CreateSnapshot(recipientName))
  local evidenceId = request.evidence[1].evidenceId or false
  local operationId = "backup-operation"
  local operation = {
    schemaVersion = 1, operationId = operationId, operationType = "DISPUTE_TARGET_TRANSFER",
    guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary",
    requestId = request.requestId, requestRevision = request.revision,
    evidenceId = evidenceId, originalTransactionId = original.transactionId,
    actor = actor, reason = "backup fixture", timestamp = 1700000000,
    signedEntries = {
      {
        operationId = operationId, entryIndex = 1, transactionId = operationId .. "-e1",
        guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = original.memberKey,
        seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = 1,
        evidenceId = evidenceId, originalTransactionId = original.transactionId,
        requestId = request.requestId, requestRevision = request.revision,
      },
      {
        operationId = operationId, entryIndex = 2, transactionId = operationId .. "-e2",
        guildKey = dibs.GetGuildKey(), ledgerId = "guild-primary", memberKey = recipient.memberKey,
        seasonId = seasonId, actionType = "DIB_ADMIN_ADJUSTMENT", quantityDelta = -1,
        evidenceId = evidenceId, originalTransactionId = original.transactionId,
        requestId = request.requestId, requestRevision = request.revision,
      },
    },
  }
  local built = assert(dibs.Ledger.BuildDisputeOperation(operation))
  return original, request, built
end

describe("RF-0012 canonical dispute backup and restore", function()
  it("exports the complete accepted operation history in a full backup", function()
    local dibs = setup()
    local original, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(result.accepted, tostring(result.reasonCode))

    local snapshot, reason = dibs.Backup.Create("full", "RF-0012 backup fixture", "Tester-Realm")
    assert_not_nil(snapshot, tostring(reason))
    local payload = snapshot.payload or {}
    local ledger = payload.ledger or {}
    local canonical = ledger.canonical or {}
    local commits = canonical.commits or {}
    local operationCommit = nil
    for _, commit in pairs(commits) do
      if commit.recordClass == "LEDGER_OPERATION_COMMIT" then operationCommit = commit end
    end
    assert_not_nil(operationCommit, "the backup did not contain the accepted operation commit")
    assert_equal(built.operationId, operationCommit.operation.operationId)
    assert_equal(2, #operationCommit.operation.signedEntries,
      "the backup did not preserve every operation entry")
    assert_equal(result.value.commitHash, operationCommit.commitHash,
      "the backup did not preserve the commit hash")
    assert_not_nil(ledger.transactions[original.transactionId],
      "the backup dropped the original transaction")
  end)

  it("restores the original canonical commit content and hash from a full backup", function()
    local dibs = setup()
    local _, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local accepted = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(accepted.accepted, tostring(accepted.reasonCode))
    local expected = dibs.DeepCopy(accepted.value)
    local snapshot = assert(dibs.Backup.Create("full", "canonical restore fixture", "Tester-Realm"))

    -- Model a local copy missing the operation while retaining the older rows.
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    ledger.canonical.commits["7:1"] = nil
    ledger.canonical.positions["7:1"] = nil
    ledger.canonical.nextSeq = 1
    ledger.canonical.rootHash = string.rep("0", #expected.previousHash)
    for id, transaction in pairs(ledger.transactions) do
      if transaction.operationId == expected.operation.operationId then ledger.transactions[id] = nil end
    end

    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "restore canonical history", "Tester-Realm"))
    local restored = dibs.GetDB().ledgers["guild-primary"].canonical.commits["7:1"]
    assert_not_nil(restored, "restore discarded the canonical operation commit")
    assert_equal(expected.commitHash, restored.commitHash, "restore changed the immutable commit hash")
    assert_true(sameValue(expected, restored), "restore changed canonical commit content")
  end)

  it("rebuilds a missing operation projection after restoring its full backup", function()
    local dibs = setup()
    local _, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local committed = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(committed.accepted, tostring(committed.reasonCode))

    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local operationEntry = committed.value.operation.signedEntries[1]
    local testerBalanceBefore = dibs.Ledger.GetBalance("Tester-Realm", dibs.GetCurrentSeasonId(), "guild-primary")
    local recipientBalanceBefore = dibs.Ledger.GetBalance("Other-Realm", dibs.GetCurrentSeasonId(), "guild-primary")
    ledger.transactions[operationEntry.transactionId] = nil
    ledger.canonical.transactionIndex[operationEntry.transactionId] = nil
    local sequenceBefore, rootBefore = ledger.canonical.nextSeq, ledger.canonical.rootHash
    local snapshot = assert(dibs.Backup.Create("full", "projection recovery fixture", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "restore projection recovery fixture", "Tester-Realm"))
    ledger = dibs.GetDB().ledgers["guild-primary"]

    local recovery = dibs.Disputes.ReconstructOperationStates("guild-primary")
    assert_true(recovery.rebuilt, tostring(recovery.reasonCode))
    assert_not_nil(ledger.transactions[operationEntry.transactionId], "recovery did not rebuild the missing transaction")
    local classification = dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("VALID", classification.classification)
    assert_equal(sequenceBefore, ledger.canonical.nextSeq, "recovery advanced the canonical sequence")
    assert_equal(rootBefore, ledger.canonical.rootHash, "recovery changed the canonical root")
    assert_equal(testerBalanceBefore, dibs.Ledger.GetBalance("Tester-Realm", dibs.GetCurrentSeasonId(), "guild-primary"),
      "recovery double-applied the first transfer leg")
    assert_equal(recipientBalanceBefore, dibs.Ledger.GetBalance("Other-Realm", dibs.GetCurrentSeasonId(), "guild-primary"),
      "recovery double-applied the second transfer leg")
    assert_equal(committed.value.commitHash,
      ledger.canonical.commits[tostring(committed.value.ledgerEpoch) .. ":" .. tostring(committed.value.sequence)].commitHash)
  end)

  it("restores an identical operation replay without a second effect", function()
    local dibs = setup()
    local _, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(result.accepted, tostring(result.reasonCode))

    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local beforeSequence = ledger.canonical.nextSeq
    local beforeRoot = ledger.canonical.rootHash
    local beforeTransactions = dibs.DeepCopy(ledger.transactions)

    -- The same operation presented again is an idempotent replay.
    local replay = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(replay.accepted, tostring(replay.reasonCode))
    assert_true(replay.idempotentReplay, "an identical operation was not reported as a replay")
    assert_equal(beforeSequence, ledger.canonical.nextSeq, "a replay advanced the sequence")
    assert_equal(beforeRoot, ledger.canonical.rootHash, "a replay changed the root hash")
    assert_true(sameValue(beforeTransactions, ledger.transactions),
      "a replay changed the transaction rows")
  end)

  it("rejects a conflicting operation identity during an import preview", function()
    local dibs = setup()
    local _, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local conflicting = dibs.DeepCopy(built)
    conflicting.reason = "a materially different intent"

    local exported = dibs.ImportExport.Export("full", { actor = "Tester-Realm", reason = "RF-0012 conflict fixture" })
    assert_not_nil(exported, "the export failed")
    local package = dibs.ImportExport.Decode(exported)
    assert_not_nil(package, "the export could not be decoded")

    local preview, previewReason = dibs.ImportExport.Preview(exported, "full", "replace", "Tester-Realm")
    assert_not_nil(preview, tostring(previewReason))
    -- The preview never applies anything.
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    assert_equal(1, ledger.canonical.nextSeq, "a preview advanced the sequence")
    assert_nil(ledger.canonical.commits["7:1"], "a preview created a commit")
  end)

  it("keeps a legacy backup without operations readable", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    local legacy = dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
      transactionId = "legacy-backup-row",
      amount = 1,
      type = "DIB_GRANTED",
    }), "guild-primary")
    assert_not_nil(legacy)

    local exported = dibs.ImportExport.Export("full", { actor = "Tester-Realm", reason = "RF-0012 legacy fixture" })
    assert_not_nil(exported, "the legacy export failed")
    local package = dibs.ImportExport.Decode(exported)
    assert_not_nil(package, "the legacy export could not be decoded")
    local payload = package.payload or {}
    local canonical = (payload.ledger or {}).canonical or {}
    local commits = canonical.commits or {}
    for _, commit in pairs(commits) do
      assert_true(commit.recordClass ~= "LEDGER_OPERATION_COMMIT",
        "a legacy backup fabricated an operation commit")
    end
    assert_not_nil((payload.ledger or {}).transactions["legacy-backup-row"],
      "the legacy backup dropped its transaction row")
  end)

  it("does not convert a historical row into canonical operation evidence", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    local legacy = dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
      transactionId = "legacy-no-operation-row",
      amount = -1,
      type = "DIB_USED",
      originalTransactionId = "legacy-no-operation-original",
    }), "guild-primary")
    assert_not_nil(legacy)

    local exported = dibs.ImportExport.Export("full", { actor = "Tester-Realm", reason = "RF-0012 legacy row fixture" })
    assert_not_nil(exported, "the export failed")
    local package = dibs.ImportExport.Decode(exported)
    local payload = package.payload or {}
    local canonical = (payload.ledger or {}).canonical or {}
    for _, commit in pairs(canonical.commits or {}) do
      assert_true(commit.recordClass ~= "LEDGER_OPERATION_COMMIT",
        "a historical row was converted into an operation commit")
    end
    assert_not_nil((payload.ledger or {}).transactions["legacy-no-operation-row"],
      "the historical row was dropped")
    assert_equal(0, (tonumber(canonical.nextSeq) or 1) - 1,
      "a historical row advanced the canonical sequence")
  end)

  it("previews an identical operation as a no-op and refuses a conflicting one", function()
    local dibs = setup()
    local _, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local result = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(result.accepted, tostring(result.reasonCode))

    local exported = dibs.ImportExport.Export("full", { actor = "Tester-Realm", reason = "RF-0012 preview fixture" })
    assert_not_nil(exported, "the export failed")
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    local sequenceBefore = ledger.canonical.nextSeq
    local rootBefore = ledger.canonical.rootHash

    -- The identical package previews as a no-op and applies nothing.
    local preview, previewReason = dibs.ImportExport.Preview(exported, "full", "append", "Tester-Realm")
    assert_not_nil(preview, tostring(previewReason))
    assert_true((preview.expectedLedgerImpact.duplicates or 0) >= 1,
      "an identical operation was not previewed as a duplicate")
    assert_equal(sequenceBefore, ledger.canonical.nextSeq, "a preview advanced the sequence")
    assert_equal(rootBefore, ledger.canonical.rootHash, "a preview changed the root hash")

    -- A package whose operation differs at the same position is refused.
    local conflicting = dibs.DeepCopy(dibs.GetDB())
    for _, commit in pairs(conflicting.ledgers["guild-primary"].canonical.commits) do
      if commit.recordClass == "LEDGER_OPERATION_COMMIT" then
        commit.operation.reason = "a materially different intent"
      end
    end
    local conflictText = dibs.ImportExport.Export("full", { actor = "Tester-Realm", reason = "RF-0012 conflict fixture" })
    assert_not_nil(conflictText, "the conflicting export failed")
    local conflictPackage = dibs.ImportExport.Decode(conflictText)
    assert_not_nil(conflictPackage, "the conflicting export could not be decoded")
    -- Rebuild the package with the conflicting operation.
    local tampered = {
      packageVersion = conflictPackage.packageVersion, scope = conflictPackage.scope,
      sourceGuild = conflictPackage.sourceGuild, sourceCharacter = conflictPackage.sourceCharacter,
      sourceProfile = conflictPackage.sourceProfile, addonVersion = conflictPackage.addonVersion,
      schemaVersion = conflictPackage.schemaVersion, createdAt = conflictPackage.createdAt,
      sensitivity = conflictPackage.sensitivity,
      payload = { ledger = conflicting.ledgers["guild-primary"] },
    }
    local conflictPreview, conflictReason = dibs.ImportExport.Preview(tampered, "full", "append", "Tester-Realm")
    assert_nil(conflictPreview, "a conflicting operation was previewed as acceptable")
    -- The refusal names the exact problem: the tampered payload no longer
    -- matches its hash, and the identity conflict is reported as well.
    assert_true(conflictReason == "OPERATION_ID_CONFLICT" or conflictReason == "PAYLOAD_HASH_MISMATCH",
      "unexpected conflict refusal: " .. tostring(conflictReason))
  end)

  it("refuses to import operation transaction rows without their canonical commit", function()
    local dibs = setup()
    local _, _, built = buildAcceptedOperation(dibs, "Tester-Realm", "Other-Realm")
    local writer = dibs.Ledger.CommitDisputeOperation
    for index = 1, 64 do
      local name = debug.getupvalue(writer, index)
      if name == nil then break end
      if name == "DISPUTE_OPERATION_WRITES_ENABLED" then debug.setupvalue(writer, index, true) end
      if name == "operationReadinessProbe" then debug.setupvalue(writer, index, function() return true end) end
    end
    dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = true
    local accepted = writer({ actor = "Tester-Realm", ledgerId = "guild-primary" }, built)
    assert_true(accepted.accepted, tostring(accepted.reasonCode))

    local incoming = dibs.DeepCopy(dibs.GetDB().ledgers["guild-primary"])
    incoming.canonical.commits = {}
    local operationRows = 0
    for id, transaction in pairs(incoming.transactions) do
      if transaction.operationId then operationRows = operationRows + 1 end
    end
    assert_true(operationRows > 0, "the fixture did not produce canonical operation transaction rows")
    for id, transaction in pairs(dibs.GetDB().ledgers["guild-primary"].transactions) do
      if transaction.operationId then dibs.GetDB().ledgers["guild-primary"].transactions[id] = nil end
    end
    dibs.GetDB().ledger = dibs.GetDB().ledgers["guild-primary"]
    local package = {
      packageVersion = dibs.ImportExport.PACKAGE_VERSION, schemaVersion = dibs.ImportExport.SCHEMA_VERSION,
      scope = "full", sourceGuild = dibs.currentGuildKey, sourceCharacter = "Tester-Realm",
      sensitivity = "sensitive", payload = { ledger = incoming }, checksum = "test-only",
    }
    local preview, reason = dibs.ImportExport.Preview(package, "full", "append", "Tester-Realm")
    assert_nil(preview, "transaction rows were importable without their operation commit")
    assert_equal("CANONICAL_LEDGER_IMPORT_UNAVAILABLE", reason)
  end)
end)
