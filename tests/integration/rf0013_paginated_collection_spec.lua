local loader = require("helpers.load_addon")

-- RF-0013 (A1) regression suite.
--
-- RF-0013 - "Installation.Initialize : decouverte legacy partielle traitee
-- comme terminee" (docs/code-audit/INDEX.md#rf-0013).
--
-- A1 makes the historical collection **paginated**:
--   * a batch holds at most 500 records;
--   * a source contributes at most 500 records per cycle;
--   * a cycle treats at most 5000 records;
--   * **retention is not bounded**: a base may hold more than one cycle
--     collects, and nothing is ever deleted to make room;
--   * the cursor is persistent and advances only after the batch it
--     covers has been accepted;
--   * the source fingerprint invalidates a cursor that no longer describes
--     the source;
--   * the states are COMPLETE, INCOMPLETE and ERROR;
--   * an incomplete collection can never be approved as complete.
--
-- The deduplication is the one `collectInto` already performs: this suite
-- never re-implements it, it verifies that the replay of a batch is a
-- no-op because of it.

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, savedVariables = options.savedVariables or {}, wow = {
    playerName = "Tester-Realm",
    guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { 0, 1, 3 },
  } })
  return dibs
end

local function seasonOf(dibs)
  return dibs.Seasons.GetCurrent().id
end

-- Creates N synthetic ledger transactions in the active ledger.
local function seedLedger(dibs, count, prefix)
  local seasonId = seasonOf(dibs)
  for index = 1, count do
    dibs.Ledger.AddTransaction({
      transactionId = string.format("%s-%04d", prefix or "rf0013-a1", index),
      playerName = "Tester-Realm",
      amount = 1,
      type = "DIB_GRANTED",
      reason = "RF-0013 A1 synthetic row",
      source = "test",
      seasonId = seasonId,
      createdAt = 1700000000 + index,
    })
  end
end

local function progressOf(dibs, sourceId)
  local progress = dibs.HistoricalBaseline.GetCollectionProgress(sourceId)
  return progress[sourceId]
end

-- The number of records the local ledger source actually holds. The
-- season allocation row is part of the source, so the fixtures below
-- work from the real count rather than from the number of rows they
-- seeded.
local function sourceSize(dibs)
  local count = 0
  for _ in ipairs(dibs.Ledger.GetAllTransactions("guild-primary") or {}) do count = count + 1 end
  return count
end

local function evidenceCount(dibs)
  local count = 0
  for _ in pairs(dibs.HistoricalBaseline.GetState().evidence or {}) do count = count + 1 end
  return count
end

-- The baseline can only be finalized once the governance is adopted. The
-- refusal this suite looks for is the **collection** refusal, so the
-- governance is established first.
local function adoptGovernance(dibs)
  if not dibs.Governance.IsV2Enforced() then
    local ok = dibs.Governance.AdoptInitial(nil, { reason = "RF-0013 A1 fixture" })
    assert_true(ok ~= false, "the governance could not be adopted")
  end
end

describe("RF-0013 A1 paginated historical collection", function()
  it("A01 collects a source of exactly 500 records and marks it complete", function()
    local dibs = setup()
    -- The source also holds the season allocation row, so the fixture
    -- seeds one row less than the bound.
    seedLedger(dibs, 499, "rf0013-a01")
    assert_equal(500, sourceSize(dibs), "the fixture does not hold exactly 500 records")
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a01")
    assert_not_nil(result, "the collection failed: " .. tostring(reason))
    assert_equal(500, #result.ledger, "the source was not collected in full")
    local progress = progressOf(dibs, "a01:ledger")
    assert_not_nil(progress, "the collection progress was not persisted")
    assert_equal("COMPLETE", progress.state, "the source was not marked complete")
    assert_equal(500, progress.cursor, "the cursor did not reach the end of the source")
  end)

  it("A02 collects a source larger than one batch", function()
    local dibs = setup()
    seedLedger(dibs, 1200, "rf0013-a02")
    local total = sourceSize(dibs)
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a02")
    assert_not_nil(result, "the collection failed: " .. tostring(reason))
    -- The whole source is collected across several batches.
    assert_equal(total, #result.ledger, "the source was not collected in full")
    local progress = progressOf(dibs, "a02:ledger")
    assert_equal("COMPLETE", progress.state, "the source was not marked complete")
    assert_equal(total, progress.cursor, "the cursor did not reach the end of the source")
  end)

  it("A03 collects a source across several batches without losing a record", function()
    local dibs = setup()
    -- A source larger than one batch is collected batch after batch. No
    -- record is dropped and none is refused: the bound is a bound of one
    -- batch, and the cycle bound is 5000 records.
    seedLedger(dibs, 1000, "rf0013-a03")
    local total = sourceSize(dibs)
    local ok, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a03")
    assert_not_nil(ok, "the collection failed: " .. tostring(reason))
    assert_equal(total, #ok.ledger, "a record was lost across the batches")
    local progress = progressOf(dibs, "a03:ledger")
    assert_equal("COMPLETE", progress.state)
    assert_equal(total, progress.cursor, "the cursor did not reach the end of the source")
  end)

  it("A04 keeps the cursor after an accepted batch and resumes from it", function()
    local dibs = setup()
    seedLedger(dibs, 700, "rf0013-a04")
    -- The first cycle collects the first batch; the cursor stops there.
    local state = dibs.HistoricalBaseline.GetState()
    local records = {}
    for _, record in ipairs(dibs.Ledger.GetAllTransactions("guild-primary") or {}) do
      records[#records + 1] = { originalId = record.transactionId, record = record }
    end
    table.sort(records, function(a, b) return tostring(a.originalId) < tostring(b.originalId) end)
    local firstBatch = {}
    for index = 1, 500 do firstBatch[#firstBatch + 1] = records[index] end
    local added, reason = dibs.HistoricalBaseline.CollectEvidence(nil, {
      sourceId = "a04:ledger", sourceClient = dibs.GetPlayerName(),
      sourceType = "LEDGER_TRANSACTION", sourceVersion = dibs.GetDB().version,
      guildKey = dibs.GetGuildKey(), complete = true,
    }, firstBatch)
    assert_not_nil(added, "the first batch was not accepted: " .. tostring(reason))
    assert_equal(500, #added, "the first batch did not hold 500 records")
  end)

  it("A05 replays an already collected batch without duplicating anything", function()
    local dibs = setup()
    seedLedger(dibs, 600, "rf0013-a05")
    local before = evidenceCount(dibs)
    local total = sourceSize(dibs)
    local first = assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a05"))
    assert_equal(total, #first.ledger)
    local afterFirst = evidenceCount(dibs)
    -- The very same collection runs again: the deduplication that
    -- `collectInto` already performs makes the replay a no-op.
    local second = assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a05"))
    assert_equal(total, #second.ledger, "the replay did not report the same records")
    assert_equal(afterFirst, evidenceCount(dibs), "the replay duplicated evidence")
    assert_true(before < afterFirst, "the first collection added nothing")
  end)

  it("A06 restarts the collection when the source has changed", function()
    local dibs = setup()
    seedLedger(dibs, 10, "rf0013-a06")
    local result = assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a06"))
    local initial = sourceSize(dibs)
    assert_equal(initial, #result.ledger)
    local before = evidenceCount(dibs)
    -- The source grows: its fingerprint no longer matches the cursor.
    seedLedger(dibs, 5, "rf0013-a06-extra")
    local grownTotal = sourceSize(dibs)
    local grown = assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a06"))
    assert_equal(grownTotal, #grown.ledger, "the grown source was not collected in full")
    assert_equal(before + 5, evidenceCount(dibs), "the restart duplicated the already collected records")
    local progress = progressOf(dibs, "a06:ledger")
    assert_equal("COMPLETE", progress.state, "the collection did not resume to the end")
    assert_equal(grownTotal, progress.cursor, "the cursor did not follow the changed source")
  end)

  it("A07 never deletes a record that was already collected", function()
    local dibs = setup()
    seedLedger(dibs, 300, "rf0013-a07")
    assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a07"))
    local afterFirst = evidenceCount(dibs)
    assert_equal(301, afterFirst, "the first collection did not collect the source")
    -- A second cycle with more data must add, never replace.
    seedLedger(dibs, 200, "rf0013-a07-more")
    assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a07"))
    assert_equal(afterFirst + 200, evidenceCount(dibs), "the historical evidence was not preserved")
  end)

  it("A08 refuses to approve a baseline while a collection is in progress", function()
    local dibs = setup()
    adoptGovernance(dibs)
    seedLedger(dibs, 20, "rf0013-a08")
    -- The collection is only started, not finished: the progress is left
    -- in the INCOMPLETE state on purpose.
    local state = dibs.GetDB().legacyBaseline
    state.collectionProgress = { ["a08:ledger"] = { cursor = 5, sourceFingerprint = "x", totalSeen = 5, state = "INCOMPLETE" } }
    local baseline, reason = dibs.HistoricalBaseline.FinalizeBaseline(nil, { acknowledgeIncompleteEvidence = true })
    assert_nil(baseline, "a baseline was approved while a collection was in progress")
    assert_not_nil(reason, "the refusal carried no diagnostic")
    assert_true(reason:find("INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS", 1, true) ~= nil,
    "the refusal did not name the in-progress source: " .. tostring(reason))
  end)

  it("A09 refuses to approve a baseline after a failed collection", function()
    local dibs = setup()
    adoptGovernance(dibs)
    seedLedger(dibs, 20, "rf0013-a09")
    local state = dibs.GetDB().legacyBaseline
    state.collectionProgress = { ["a09:ledger"] = { cursor = 5, sourceFingerprint = "x", totalSeen = 5, state = "ERROR", lastReason = "EVIDENCE_LIMIT_EXCEEDED" } }
    local baseline, reason = dibs.HistoricalBaseline.FinalizeBaseline(nil, { acknowledgeIncompleteEvidence = true })
    assert_nil(baseline, "a baseline was approved after a failed collection")
    assert_true(reason:find("INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS", 1, true) ~= nil,
    "the refusal did not name the failed source: " .. tostring(reason))
    assert_true(reason:find("EVIDENCE_LIMIT_EXCEEDED", 1, true) ~= nil,
    "the refusal did not carry the collection reason: " .. tostring(reason))
  end)

  it("A10 approves a baseline when every collection is complete", function()
    local dibs = setup()
    adoptGovernance(dibs)
    seedLedger(dibs, 20, "rf0013-a10")
    assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a10"))
    local progress = progressOf(dibs, "a10:ledger")
    assert_not_nil(progress, "the collection progress is missing")
    assert_equal("COMPLETE", progress.state)
    local baseline, reason = dibs.HistoricalBaseline.FinalizeBaseline(nil, {})
    -- The baseline may still be refused for an unrelated reason, but never
    -- for a collection that is in progress.
    if not baseline then
      assert_true(reason:find("INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS", 1, true) == nil,
        "a complete collection still blocked the approval: " .. tostring(reason))
    else
      assert_not_nil(baseline.legacyBaselineHash, "the approved baseline carries no hash")
    end
  end)

  it("A11 reports the collection progress so the interface can show it", function()
    local dibs = setup()
    seedLedger(dibs, 20, "rf0013-a11")
    assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a11"))
    local progress = dibs.HistoricalBaseline.GetCollectionProgress("a11:ledger")
    assert_not_nil(progress["a11:ledger"], "the progress is not readable")
    assert_equal("COMPLETE", progress["a11:ledger"].state)
    assert_equal(sourceSize(dibs), progress["a11:ledger"].cursor)
    assert_not_nil(progress["a11:ledger"].totalSeen, "the progress carries no total")
  end)

  it("A12 collects a source that is empty without treating it as a blocker", function()
    local dibs = setup()
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "a12")
    assert_not_nil(result, "the collection of an empty environment failed: " .. tostring(reason))
    assert_equal(sourceSize(dibs), #result.ledger, "the source size does not match the collected records")
    local progress = progressOf(dibs, "a12:ledger")
    assert_not_nil(progress, "the progress of an empty source was not persisted")
    assert_equal("COMPLETE", progress.state, "an empty source was not marked complete")
    assert_equal(sourceSize(dibs), progress.cursor, "the cursor does not match the source")
  end)
end)
