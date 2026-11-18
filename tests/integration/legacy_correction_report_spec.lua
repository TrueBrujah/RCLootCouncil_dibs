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
      source = "legacy_correction",
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

  it("does not mistake an ordinary award debit for a historical correction", function()
    local dibs = setup()
    addLegacyRow(dibs, "guild-primary", "ordinary-award", { amount = -1, type = "DIB_USED" })
    assert_nil(dibs.Disputes.BuildLegacyCorrectionReport("guild-primary").entries["ordinary-award"])
  end)

  it("keeps missing request references distinct from complete references", function()
    local dibs = setup()
    addLegacyRow(dibs, "guild-primary", "partial-original")
    addLegacyRow(dibs, "guild-primary", "missing-request", {
      originalTransactionId = "partial-original", correctionKey = "known-link",
    })
    local entry = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary").entries["missing-request"]
    assert_equal("PARTIAL", entry.classification)
    assert_equal("REQUEST_REFERENCE_MISSING", entry.reasonCode)
  end)

  it("denies the officer inventory to a member and preserves the guild state", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildRankIndices = { 3 } } })
    local before = dibs.DeepCopy(dibs.GetDB())
    local report, reason = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    assert_nil(report)
    assert_equal("OFFICER_REQUIRED", reason)
    assert_true(sameValue(before, dibs.GetDB()))
    assert_nil(dibs.OfficerUI.OpenHistoricalCorrectionReport("guild-primary"))
  end)

  it("renders an inspectable report with bounded pages and no mutation controls", function()
    local dibs = setup()
    for index = 1, 21 do
      addLegacyRow(dibs, "guild-primary", string.format("legacy-%02d", index), { correctionKey = "key-" .. index })
    end
    local before = dibs.DeepCopy(dibs.GetDB())
    local tables = {}
    local addTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, ...)
      tables[#tables + 1] = rows
      return addTable(shell, parent, columns, rows, ...)
    end
    local shell = assert(dibs.OfficerUI.OpenHistoricalCorrectionReport("guild-primary"))
    assert_equal(20, #tables[1])
    local nextPage
    local function inspect(widget)
      if widget.kind == "Button" then
        assert_true(widget.text == dibs.L.DISPUTE_REPORT_NEXT or widget.text == dibs.L.DISPUTE_REPORT_PREVIOUS)
        if widget.text == dibs.L.DISPUTE_REPORT_NEXT then nextPage = widget end
      end
      for _, child in ipairs(widget.children or {}) do inspect(child) end
    end
    inspect(shell.window)
    assert_not_nil(nextPage)
    nextPage.callbacks.OnClick(nextPage)
    assert_equal(1, #tables[2])
    assert_equal("legacy-21", tables[2][1][1])
    assert_true(sameValue(before, dibs.GetDB()))
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
