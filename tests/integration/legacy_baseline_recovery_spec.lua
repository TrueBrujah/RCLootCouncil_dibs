local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function load()
  return select(2, loader.load({ withAce3 = true, wow = {
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm", "Other-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 },
  } }))
end

local function ledger(id, player, amount, season, extra)
  local record = {
    transactionId = id, playerName = player or "Player-Realm", amount = amount or -1,
    actionType = amount and amount > 0 and "DIB_GRANTED" or "DIB_USED", seasonId = season or "season-1", timestamp = 100,
  }
  for key, value in pairs(extra or {}) do record[key] = value end
  return record
end

local function predib(id, player, status, extra)
  local record = { requestId = id, playerName = player or "Player-Realm", itemID = 1001, seasonId = "season-1", status = status or "pending", revision = 1, createdAt = 100 }
  for key, value in pairs(extra or {}) do record[key] = value end
  return record
end

local function source(id, kind, complete)
  return { sourceId = id, sourceClient = id .. "-Realm", sourceType = kind, sourceVersion = 6, complete = complete ~= false }
end

local function collect(dibs, id, kind, records, complete)
  return dibs.LegacyBaseline.CollectEvidence(nil, source(id, kind, complete), records)
end

local function adoptGovernance(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "B05a baseline approval" }))
end

local function decisionAll(dibs, decision, options)
  for _, evidence in ipairs(dibs.LegacyBaseline.GetEvidence()) do
    local result, reason = dibs.LegacyBaseline.RecordDecision(nil, evidence.evidenceId, decision, options)
    assert_not_nil(result, tostring(reason))
  end
end

local function recoveryPackage(dibs, evidenceSources)
  local package = {
    schema = 1, recordClass = "LEGACY_RECOVERY_PACKAGE", guildKey = dibs.GetGuildKey(),
    source = { sourceId = "recovery-1", authorNameRealm = "Tester-Realm", sourceKind = "MANUAL_IMPORT" },
    expectedContext = "LEGACY_LOCAL", baselineRelationship = { state = "PRE_BASELINE" },
    evidenceSources = evidenceSources, audit = { reason = "B05a test package" }, createdAt = 100,
  }
  package.contentHash = dibs.LegacyBaseline.CalculateRecoveryContentHash(package)
  return package
end

local function findingKinds(dibs)
  local kinds = {}
  for _, finding in ipairs(dibs.LegacyBaseline.GetFindings()) do kinds[finding.kind] = true end
  return kinds
end

describe("B05a legacy baseline reconciliation and staged recovery", function()
  it("preserves two identical peer histories as evidence without selecting either database as canonical", function()
    local dibs = load()
    local original = ledger("tx-1")
    assert_not_nil(collect(dibs, "peer-a", "LEDGER_TRANSACTION", { original }))
    assert_not_nil(collect(dibs, "peer-b", "LEDGER_TRANSACTION", { original }))
    assert_nil(dibs.LegacyBaseline.GetBaseline())
    assert_equal("tx-1", original.transactionId)
    assert_true(findingKinds(dibs).EXACT_DUPLICATE_EVIDENCE)
    assert_equal(2, #dibs.LegacyBaseline.GetEvidence())
  end)

  it("detects divergent peer histories, legacy-ID conflicts, likely duplicate awards, and identity ambiguity", function()
    local dibs = load()
    assert_not_nil(collect(dibs, "peer-a", "LEDGER_TRANSACTION", { ledger("shared", "Player-Realm", -1), ledger("award-a", "Player-Realm", -1), ledger("identity", "Player-Realm", -1) }))
    assert_not_nil(collect(dibs, "peer-b", "LEDGER_TRANSACTION", { ledger("shared", "Other-Realm", -1), ledger("award-b", "Player-Realm", -1), ledger("identity", "Other-Realm", -1), ledger("short", "Player", -1) }))
    local kinds = findingKinds(dibs)
    assert_true(kinds.PEER_EVIDENCE_DIVERGENCE)
    assert_true(kinds.LEGACY_ID_CONTENT_CONFLICT)
    assert_true(kinds.LIKELY_DUPLICATE_AWARD)
    assert_true(kinds.LEGACY_IDENTITY_CONFLICT)
    assert_true(kinds.UNRESOLVED_IDENTITY)
  end)

  it("requires explicit include, exclude, or compensation decisions and changes the deterministic baseline hash when a decision changes", function()
    local dibs = load(); adoptGovernance(dibs)
    assert_not_nil(collect(dibs, "peer-a", "LEDGER_TRANSACTION", { ledger("include", "Player-Realm", -1), ledger("exclude", "Other-Realm", -1), ledger("adjust", "Player-Realm", -1) }))
    assert_nil(dibs.LegacyBaseline.PreviewBaseline())
    local evidence = dibs.LegacyBaseline.GetEvidence()
    assert_not_nil(dibs.LegacyBaseline.RecordDecision(nil, evidence[1].evidenceId, "INCLUDE", { reason = "accepted" }))
    assert_not_nil(dibs.LegacyBaseline.RecordDecision(nil, evidence[2].evidenceId, "EXCLUDE", { reason = "duplicate" }))
    local adjustment, reason = dibs.LegacyBaseline.RecordDecision(nil, evidence[3].evidenceId, "COMPENSATING_ADJUSTMENT", {
      reason = "corrected", playerName = "Player-Realm", seasonId = "season-1", amount = 2, includeOriginal = false,
    })
    assert_not_nil(adjustment, tostring(reason))
    local first = assert(dibs.LegacyBaseline.PreviewBaseline())
    local replacement = assert(dibs.LegacyBaseline.RecordDecision(nil, evidence[2].evidenceId, "INCLUDE", { reason = "reviewed", supersedes = assert(dibs.LegacyBaseline.GetState().activeDecisionByEvidence[evidence[2].evidenceId]) }))
    local second = assert(dibs.LegacyBaseline.PreviewBaseline())
    assert_true(first.legacyBaselineHash ~= second.legacyBaselineHash)
    assert_equal("EXCLUDE", dibs.LegacyBaseline.GetState().decisions[replacement.supersedes].decision)
  end)

  it("reproduces the same baseline hash regardless of source collection order and never rewrites legacy IDs", function()
    local first = load()
    local records = { ledger("a", "Player-Realm", -1), ledger("b", "Other-Realm", 2) }
    assert_not_nil(collect(first, "one", "LEDGER_TRANSACTION", records)); assert_not_nil(collect(first, "two", "PREDIB_REQUEST", { predib("request-1") }))
    decisionAll(first, "INCLUDE")
    local baselineA = assert(first.LegacyBaseline.PreviewBaseline())
    for _, evidence in ipairs(first.LegacyBaseline.GetEvidence()) do assert_not_nil(evidence.originalId) end
    assert_equal("a", records[1].transactionId)
    local second = load()
    assert_not_nil(collect(second, "two", "PREDIB_REQUEST", { predib("request-1") })); assert_not_nil(collect(second, "one", "LEDGER_TRANSACTION", records))
    decisionAll(second, "INCLUDE")
    local baselineB = assert(second.LegacyBaseline.PreviewBaseline())
    assert_equal(baselineA.legacyBaselineHash, baselineB.legacyBaselineHash)
  end)

  it("allows only the fresh local GM to finalize and requires explicit acknowledgement for incomplete evidence", function()
    local dibs = load(); adoptGovernance(dibs)
    assert_not_nil(collect(dibs, "partial", "LEDGER_TRANSACTION", { ledger("tx-1") }, false))
    decisionAll(dibs, "INCLUDE")
    assert_nil(dibs.LegacyBaseline.FinalizeBaseline(nil))
    local baseline, reason = dibs.LegacyBaseline.FinalizeBaseline(nil, { acknowledgeIncompleteEvidence = true })
    assert_not_nil(baseline, tostring(reason)); assert_equal("BASELINE_APPROVED", reason)

    local denied = load(); adoptGovernance(denied); assert_not_nil(collect(denied, "peer", "LEDGER_TRANSACTION", { ledger("tx-1") })); decisionAll(denied, "INCLUDE")
    wow.setGuildRoster({ "Tester-Realm", "Officer-Realm" }, { [1] = 1, [2] = 0 })
    assert_nil(denied.LegacyBaseline.FinalizeBaseline(nil))
    denied.GetDB().settings.officerMaxRankIndex = 0
    assert_nil(denied.LegacyBaseline.FinalizeBaseline(nil))
    assert_nil(denied.LegacyBaseline.GetBaseline())
  end)

  it("keeps active-looking historical Pre-Dibs historical and never revives them", function()
    local dibs = load(); adoptGovernance(dibs)
    local request = predib("active-request", "Player-Realm", "confirmed")
    dibs.GetDB().preDibs.requests = { request }
    assert_not_nil(dibs.LegacyBaseline.CollectLocalEvidence(nil, "local-history"))
    decisionAll(dibs, "INCLUDE")
    local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
    assert_equal("confirmed", request.status)
    assert_equal("confirmed", dibs.GetDB().preDibs.requests[1].status)
    assert_equal("HISTORICAL_RECONFIRMATION_REQUIRED", baseline.historicalPreDibs[1].state)
  end)

  it("stages a complete recovery package and commits evidence atomically with provenance and a safety backup", function()
    local dibs = load()
    local package = recoveryPackage(dibs, {
      { source = source("remote-ledger", "LEDGER_TRANSACTION"), records = { ledger("tx-1") } },
      { source = source("remote-predib", "PREDIB_REQUEST"), records = { predib("request-1", "Player-Realm", "cancelled") } },
    })
    local staged, reason = dibs.LegacyBaseline.StageRecoveryPackage(package)
    assert_not_nil(staged, tostring(reason)); assert_equal(0, #dibs.LegacyBaseline.GetEvidence())
    local committed, commitReason = dibs.LegacyBaseline.CommitRecoveryPackage(nil, staged)
    assert_not_nil(committed, tostring(commitReason)); assert_equal("RECOVERY_COMMITTED", commitReason)
    assert_equal(2, #dibs.LegacyBaseline.GetEvidence()); assert_not_nil(committed.backupSnapshotId)
    assert_not_nil(dibs.LegacyBaseline.GetState().recoveries[package.contentHash])
    local replay, replayReason = dibs.LegacyBaseline.CommitRecoveryPackage(nil, staged)
    assert_true(replay.idempotentReplay); assert_equal("IDEMPOTENT_RECOVERY", replayReason)
  end)

  it("uses B04 WHISPER transport only to stage remote recovery evidence until an explicit local commit", function()
    local dibs = load()
    local package = recoveryPackage(dibs, { { source = source("transport-ledger", "LEDGER_TRANSACTION"), records = { ledger("transport-tx") } } })
    assert_true(dibs.Sync.SendLegacyRecoveryPackage(package, "Officer-Realm"))
    for _, sent in ipairs(dibs.Ace3.libs.comm.sent) do
      assert_true(dibs.Sync.OnAddonMessage(sent.prefix, sent.payload, sent.channel, "Tester-Realm"))
    end
    assert_equal(0, #dibs.LegacyBaseline.GetEvidence())
    assert_not_nil(dibs.LegacyBaseline.GetReceivedRecovery(package.contentHash))
    local committed, reason = dibs.LegacyBaseline.CommitReceivedRecovery(nil, package.contentHash)
    assert_not_nil(committed, tostring(reason)); assert_equal("RECOVERY_COMMITTED", reason)
    assert_equal(1, #dibs.LegacyBaseline.GetEvidence())
  end)

  it("rejects every invalid recovery stage before mutation: transaction, Pre-Dib, hash, guild, schema, and malformed identity", function()
    local dibs = load(); local originalLedger = dibs.GetDB().ledger; local originalRequests = dibs.GetDB().preDibs.requests
    local function rejected(package, expected)
      local staged, reason = dibs.LegacyBaseline.StageRecoveryPackage(package)
      assert_nil(staged); assert_equal(expected, reason)
      assert_equal(originalLedger, dibs.GetDB().ledger); assert_equal(originalRequests, dibs.GetDB().preDibs.requests); assert_equal(0, #dibs.LegacyBaseline.GetEvidence())
    end
    local badTx = recoveryPackage(dibs, { { source = source("bad-tx", "LEDGER_TRANSACTION"), records = { ledger("good"), { transactionId = "bad", playerName = "Player-Realm", actionType = "DIB_USED", seasonId = "season-1" } } } })
    rejected(badTx, "INVALID_RECOVERY_TRANSACTION")
    local badRequest = recoveryPackage(dibs, { { source = source("bad-request", "PREDIB_REQUEST"), records = { predib("good", "Player-Realm", "cancelled"), predib("bad", "Player-Realm", "pending", { itemID = 0 }) } } })
    rejected(badRequest, "INVALID_RECOVERY_PREDIB")
    local badHash = recoveryPackage(dibs, { { source = source("hash", "LEDGER_TRANSACTION"), records = { ledger("tx") } } }); badHash.contentHash = "bad"
    rejected(badHash, "RECOVERY_HASH_MISMATCH")
    local wrongGuild = recoveryPackage(dibs, { { source = source("guild", "LEDGER_TRANSACTION"), records = { ledger("tx") } } }); wrongGuild.guildKey = "wrong"; wrongGuild.contentHash = dibs.LegacyBaseline.CalculateRecoveryContentHash(wrongGuild)
    rejected(wrongGuild, "GUILD_SCOPE_MISMATCH")
    local future = recoveryPackage(dibs, { { source = source("schema", "LEDGER_TRANSACTION"), records = { ledger("tx") } } }); future.schema = 2; future.contentHash = dibs.LegacyBaseline.CalculateRecoveryContentHash(future)
    rejected(future, "UNSUPPORTED_RECOVERY_SCHEMA")
    local noIdentity = recoveryPackage(dibs, { { source = source("identity", "LEDGER_TRANSACTION"), records = { ledger("tx", "") } } })
    rejected(noIdentity, "MALFORMED_LEGACY_IDENTITY")
  end)

  it("keeps ImportExport full packages explicitly diagnostic and leaves B03 ledger and B04 synchronization boundaries untouched", function()
    local dibs = load()
    local text, package = dibs.ImportExport.Export("full")
    assert_not_nil(text); assert_equal("LEGACY_DIAGNOSTIC_ONLY", package.recoveryClass)
    local preview = assert(dibs.ImportExport.Preview(text, "full", "append"))
    assert_equal("LEGACY_DIAGNOSTIC_ONLY", preview.recoveryClass)
    assert_false(dibs.LegacyBaseline.ClassifyImportPackage(package).authoritativeRecovery)
    assert_equal("LOCAL_ONLY", dibs.Sync.BuildLedgerDigest().contentHash)
    assert_nil(dibs.Governance.GetState().future.ledgerEpoch)
  end)
end)
