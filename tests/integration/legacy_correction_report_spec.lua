local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

-- T028: read-only historical reconciliation fixtures.
-- Each synthetic case has an explicit expected classification and known
-- identifiers. The report generation must never change any data.

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
  local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
  return dibs
end

local function addLegacyRow(dibs, ledgerId, transactionId, overrides)
  local seasonId = dibs.GetCurrentSeasonId()
  local transaction = fixtures.transaction("Tester-Realm", seasonId, {
    transactionId = transactionId,
    amount = 1,
    type = "DIB_GRANTED",
  })
  for key, value in pairs(overrides or {}) do transaction[key] = value end
  local ledger = dibs.GetDB().ledgers[ledgerId]
  ledger.transactions[transactionId] = transaction
  return transaction
end

describe("RF-0012 legacy correction reconciliation fixtures", function()
  it("classifies a complete legacy correction with a known original and request", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    local original = addLegacyRow(dibs, "guild-primary", "legacy-complete-original")
    local correction = addLegacyRow(dibs, "guild-primary", "legacy-complete-correction", {
      amount = -1,
      type = "DIB_USED",
      originalTransactionId = original.transactionId,
      correctionKey = "legacy-complete-key",
      reviewRequestId = "legacy-complete-request",
    })
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local entry = report.entries and report.entries[correction.transactionId]
    assert_not_nil(entry, "the complete legacy correction was not reported")
    assert_equal("COMPLETE", entry.classification, tostring(entry.reasonCode))
    assert_equal(original.transactionId, entry.originalTransactionId)
    assert_equal("legacy-complete-request", entry.requestId)
    assert_equal("guild-primary", entry.ledgerId)
  end)

  it("classifies a partial legacy correction whose original is missing", function()
    local dibs = setup()
    local correction = addLegacyRow(dibs, "guild-primary", "legacy-partial-correction", {
      amount = -1,
      type = "DIB_USED",
      originalTransactionId = "legacy-partial-missing-original",
      correctionKey = "legacy-partial-key",
    })
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local entry = report.entries and report.entries[correction.transactionId]
    assert_not_nil(entry, "the partial legacy correction was not reported")
    assert_equal("PARTIAL", entry.classification, tostring(entry.reasonCode))
    assert_equal("legacy-partial-missing-original", entry.originalTransactionId)
  end)

  it("classifies an ambiguous legacy correction present in two ledgers", function()
    local dibs = setup()
    local secondLedgerId = "legacy-ambiguous-ledger"
    local db = dibs.GetDB()
    db.ledgers[secondLedgerId] = db.ledgers[secondLedgerId] or {
      id = secondLedgerId, name = secondLedgerId, status = "APPROVED", createdAt = 0,
      transactions = {}, playerStates = {}, awardTransactions = {}, evidenceTransactions = {},
      canonical = { schema = 1, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
    }
    local correction = addLegacyRow(dibs, "guild-primary", "legacy-ambiguous-correction", {
      amount = -1,
      type = "DIB_USED",
      originalTransactionId = "legacy-ambiguous-original",
      correctionKey = "legacy-ambiguous-key",
    })
    db.ledgers[secondLedgerId].transactions[correction.transactionId] = dibs.DeepCopy(correction)
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local entry = report.entries and report.entries[correction.transactionId]
    assert_not_nil(entry, "the ambiguous legacy correction was not reported")
    assert_equal("AMBIGUOUS", entry.classification, tostring(entry.reasonCode))
  end)

  it("classifies a local-only legacy correction with no canonical backing", function()
    local dibs = setup()
    local correction = addLegacyRow(dibs, "guild-primary", "legacy-local-only-correction", {
      amount = -1,
      type = "DIB_USED",
      source = "legacy-correction",
    })
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local entry = report.entries and report.entries[correction.transactionId]
    assert_not_nil(entry, "the local-only legacy correction was not reported")
    assert_equal("LOCAL_ONLY", entry.classification, tostring(entry.reasonCode))
  end)

  it("classifies an unverifiable legacy correction candidate and never treats a correctionKey as proof", function()
    local dibs = setup()
    local correction = addLegacyRow(dibs, "guild-primary", "legacy-unverifiable-correction", {
      amount = -1,
      type = "DIB_USED",
      correctionKey = "legacy-unverifiable-key",
    })
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local entry = report.entries and report.entries[correction.transactionId]
    assert_not_nil(entry, "the unverifiable legacy correction was not reported")
    assert_equal("UNVERIFIABLE", entry.classification, tostring(entry.reasonCode))
    assert_nil(entry.originalTransactionId, "a correctionKey was treated as proof of an original")
  end)

  it("reports a rollback candidate without treating it as an accepted correction", function()
    local dibs = setup()
    local rollback = addLegacyRow(dibs, "guild-primary", "legacy-rollback-candidate", {
      amount = 1,
      type = "DIB_GRANTED",
      correctionKey = "legacy-correction-key:rollback",
    })
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local entry = report.entries and report.entries[rollback.transactionId]
    assert_not_nil(entry, "the rollback candidate was not reported")
    assert_true(entry.rollbackCandidate, "the rollback candidate was not identified")
  end)

  it("leaves every ledger, row, request, sequence, and root unchanged", function()
    local dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    local original = addLegacyRow(dibs, "guild-primary", "legacy-readonly-original")
    addLegacyRow(dibs, "guild-primary", "legacy-readonly-correction", {
      amount = -1,
      type = "DIB_USED",
      originalTransactionId = original.transactionId,
      correctionKey = "legacy-readonly-key",
    })
    local db = dibs.GetDB()
    local before = dibs.DeepCopy({
      ledgers = db.ledgers,
      disputes = db.disputes,
    })
    local beforeRoot = db.ledgers["guild-primary"].canonical.rootHash
    local beforeSequence = db.ledgers["guild-primary"].canonical.nextSeq

    dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")

    local after = dibs.DeepCopy({
      ledgers = db.ledgers,
      disputes = db.disputes,
    })
    assert_true(sameValue(before, after), "the legacy report changed stored data")
    assert_equal(beforeRoot, db.ledgers["guild-primary"].canonical.rootHash,
      "the legacy report changed the root hash")
    assert_equal(beforeSequence, db.ledgers["guild-primary"].canonical.nextSeq,
      "the legacy report advanced the sequence")
  end)
end)
