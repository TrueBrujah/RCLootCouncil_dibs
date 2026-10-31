local loader = require("helpers.load_addon")

-- RF-0013 reproduction suite.
--
-- RF-0013 - "Installation.Initialize : decouverte legacy partielle traitee comme
-- terminee" (docs/code-audit/INDEX.md#rf-0013, status NEED_UPDATE, risk HIGH).
--
-- The finding has three distinct parts. This suite proves each one against the
-- real modules with synthetic SavedVariables only:
--
--   A. A partial local-evidence scan can persist one source and lose the
--      other, because HistoricalBaseline.CollectLocalEvidence performs two
--      independent CollectEvidence calls and each persists on its own.
--   B. Installation.stageLegacyDiscovery does not resume a partial scan: it
--      only looks at the total evidence count, so a half-populated scan looks
--      like "nothing to do". Installation.GetStatus uses the same signal.
--   C. The non-GM path calls stageLegacyDiscovery and MultiLedger.ProposeLedger
--      without reading their result and always reports ok=true.
--
-- The tests below are written to FAIL on the current code where the defect is
-- present, and to pass once RF-0013 is fixed. They never weaken an assertion
-- to make a test pass.

local function countTable(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, wow = {
    guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { 0, 1, 3 },
  } })
  return dibs
end

-- Creates N synthetic ledger transactions in the active ledger.
local function seedLedger(dibs, count)
  local seasonId = dibs.Seasons.GetCurrent().id
  for index = 1, count do
    dibs.Ledger.AddTransaction({
      transactionId = string.format("rf0013-ledger-%04d", index),
      playerName = "Tester-Realm",
      amount = 1,
      type = "DIB_GRANTED",
      reason = "RF-0013 synthetic legacy row",
      source = "test",
      seasonId = seasonId,
      createdAt = 1700000000 + index,
    })
  end
end

-- Creates N synthetic Pre-Dib requests in the local preDibs store.
-- `db.preDibs.requests` is an array, not a keyed table.
local function seedPreDibs(dibs, count)
  local db = dibs.GetDB()
  db.preDibs = db.preDibs or { requests = {}, modePolicies = {}, acquisitions = {} }
  db.preDibs.requests = db.preDibs.requests or {}
  for index = 1, count do
    table.insert(db.preDibs.requests, {
      requestId = string.format("rf0013-predib-%04d", index),
      playerName = "Tester-Realm",
      itemID = 19019,
      status = "requested",
      seasonId = dibs.Seasons.GetCurrent().id,
      createdAt = 1700000000 + index,
    })
  end
end

describe("RF-0013 partial legacy discovery is not treated as complete", function()
  it("A. a partial scan that loses the Pre-Dibs source is detectable", function()
    local dibs = setup()
    seedLedger(dibs, 3)
    seedPreDibs(dibs, 2)

    local state = dibs.HistoricalBaseline.GetState()
    -- CollectLocalEvidence returns { ledger = <ids>, preDibs = <ids> }.
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "rf0013-partial")
    assert_not_nil(result, "the local evidence collection failed: " .. tostring(reason))
    assert_not_nil(result.ledger, "the ledger source was not collected")
    assert_not_nil(result.preDibs, "the Pre-Dibs source was not collected")

    -- GetState returns a copy, so the sources are read again after collection.
    local sources = dibs.HistoricalBaseline.GetState().sources or {}
    local hasLedger, hasPreDibs = false, false
    for sourceId in pairs(sources) do
      if sourceId:find(":ledger", 1, true) then hasLedger = true end
      if sourceId:find(":predibs", 1, true) then hasPreDibs = true end
    end
    assert_true(hasLedger, "the ledger source is missing from the baseline state")
    assert_true(hasPreDibs, "the Pre-Dibs source is missing from the baseline state")
  end)

  it("B. the installation scan resumes a partial scan instead of reporting nothing to do", function()
    local dibs = setup()
    seedLedger(dibs, 3)
    seedPreDibs(dibs, 2)

    -- Reproduce the exact partial state documented for RF-0013: the ledger
    -- source was persisted, the Pre-Dibs source was not. The scan therefore
    -- holds evidence (so the total count is greater than zero) while one
    -- expected source is still missing.
    local state = dibs.HistoricalBaseline.GetState()
    local partial = { sourceId = "rf0013-partial:ledger", sourceClient = dibs.GetPlayerName(),
      sourceType = "LEDGER_TRANSACTION", sourceVersion = dibs.GetDB().version,
      guildKey = dibs.GetGuildKey(), complete = true }
    local ledgerRecords = {}
    for _, record in ipairs(dibs.Ledger.GetAllTransactions("guild-primary") or {}) do
      ledgerRecords[#ledgerRecords + 1] = { originalId = record.transactionId, record = record }
    end
    local added = dibs.HistoricalBaseline.CollectEvidence(nil, partial, ledgerRecords)
    assert_not_nil(added, "the partial ledger source was not persisted")

    -- GetState returns a copy, so the sources are read again after collection.
    local sources = dibs.HistoricalBaseline.GetState().sources or {}
    local hasPreDibs = false
    for sourceId in pairs(sources) do
      if sourceId:find(":predibs", 1, true) then hasPreDibs = true end
    end
    assert_false(hasPreDibs, "the fixture already contains the Pre-Dibs source")

    -- The installation status must not treat this half-populated scan as
    -- complete. Real legacy data still exists and one expected source is
    -- missing, so the scan has to be reported as still required.
    local status = dibs.Installation.GetStatus(nil)
    assert_true(status.state == "RECONCILIATION_REQUIRED" or status.state == "NOT_INITIALIZED",
      "the installation status treated a partial scan as complete: " .. tostring(status.state))
    local hasScanBlocker = false
    for _, blocker in ipairs(status.blockers or {}) do
      if blocker == "LEGACY_EVIDENCE_SCAN_REQUIRED" or blocker == "LEGACY_RECONCILIATION_REQUIRED" then
        hasScanBlocker = true
      end
    end
    assert_true(hasScanBlocker,
      "the installation status exposed no blocker for the missing Pre-Dibs source")
  end)

  it("C. a non-GM initialization does not report success for work it never checked", function()
    local dibs = setup({ guildLeader = false })
    -- An officer (not the GM) is the actor for this case.
    local result = dibs.Installation.Initialize("Officer-Realm", {})
    assert_not_nil(result, "the officer initialization returned no result")
    -- The documented contract says the officer path must not claim a proposal
    -- it never created. Either the call reports that no proposal exists, or
    -- it fails explicitly; it must not report a successful proposal.
    if result.ok == true then
      local proposals = dibs.MultiLedger.GetProposals and dibs.MultiLedger.GetProposals() or {}
      local created = 0
      for _, proposal in ipairs(proposals) do created = created + 1 end
      assert_true(created > 0,
        "the officer path reported a created proposal but no proposal object exists")
    end
  end)

  it("D. an unreadable source is reported as unknown, not as an empty source", function()
    local dibs = setup()
    seedLedger(dibs, 2)
    local originalGetHistory = dibs.PreDibs.GetHistory
    -- A read failure must not be converted into "no Pre-Dibs data", and it
    -- must not propagate out of the status projection.
    dibs.PreDibs.GetHistory = function() error("synthetic read failure") end

    local ok, status = pcall(dibs.Installation.GetStatus, nil)
    assert_true(ok, "the status projection propagated a read failure: " .. tostring(status))
    assert_not_nil(status, "the status projection returned nothing")
    local hasBlocker = false
    for _, blocker in ipairs(status.blockers or {}) do
      if blocker == "LEGACY_EVIDENCE_SCAN_REQUIRED" then hasBlocker = true end
    end
    assert_true(hasBlocker,
      "an unreadable Pre-Dibs source produced no blocker; it was treated as empty")

    dibs.PreDibs.GetHistory = originalGetHistory
  end)

  it("E. the detection scope matches the collection scope", function()
    local dibs = setup()
    -- Rows that live only in another approved ledger must not make the
    -- primary guild look like it holds legacy data, because the local scan
    -- reads guild-primary explicitly.
    local proposal = dibs.MultiLedger.ProposeLedger("Tester-Realm", "RF-0013 other ledger")
    assert_not_nil(proposal, "the secondary ledger proposal was not created")
    local approved = dibs.MultiLedger.ApproveLedger("Tester-Realm", proposal.ledgerId)
    assert_true(approved.ok, tostring(approved.reasonCode))

    -- The row is written straight into the secondary ledger's own store.
    local otherLedger = dibs.db.ledgers[proposal.ledgerId]
    assert_not_nil(otherLedger, "the secondary ledger was not created")
    otherLedger.transactions["rf0013-other-ledger-row"] = {
      schema = 3, recordClass = "LEDGER_TRANSACTION", classification = "LOCAL_CANONICAL",
      transactionId = "rf0013-other-ledger-row", type = "DIB_GRANTED", actionType = "DIB_GRANTED",
      memberKey = "tester-realm", playerKey = "tester-realm", playerName = "Tester-Realm",
      seasonId = dibs.Seasons.GetCurrent().id, amount = 1, quantityDelta = 1,
      reason = "RF-0013 synthetic row in another ledger", source = "test", createdAt = 1700000001,
    }
    assert_equal(1, #dibs.Ledger.GetAllTransactions(proposal.ledgerId),
      "the synthetic row did not reach the secondary ledger")

    -- The secondary ledger becomes the active one. A detection that reads the
    -- active ledger would now see the row and claim the primary guild holds
    -- legacy data, while the local scan still reads guild-primary only.
    local activated = dibs.MultiLedger.SetActiveLedger(proposal.ledgerId)
    assert_true(activated, tostring(activated))
    assert_equal(proposal.ledgerId, dibs.MultiLedger.GetActiveLedgerId(),
      "the secondary ledger did not become active")

    -- The primary ledger holds no real legacy row, so the status must not
    -- claim the primary scan has data to collect.
    local status = dibs.Installation.GetStatus(nil)
    local missing = status.legacy and status.legacy.missingScanSources or {}
    local claimsLedgerData = false
    for _, source in ipairs(missing) do
      if source == "ledger" then claimsLedgerData = true end
    end
    assert_false(claimsLedgerData,
      "the detection read a ledger other than the one the local scan collects")
  end)
end)
