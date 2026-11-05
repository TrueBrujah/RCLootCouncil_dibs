local loader = require("helpers.load_addon")

-- RF-0013 verification suite.
--
-- The session 16 brief asks for the guarantees of A1 and B1 to be
-- demonstrated explicitly, and to add only the tests that are needed
-- for that. This suite covers the guarantees that the first A1/B1
-- suites did not yet prove:
--
--   A1  the pagination is complete (no record is lost across a batch
--       boundary), the collection resumes after an interruption, the
--       deduplication holds, a source that changes during the collection
--       does not cause an infinite recollection, an old SavedVariables
--       root still loads and collects, and a partial collection can
--       never be approved.
--   B1  a proposal written before the metadata contract existed is not
--       stranded, missing metadata is refused, a duplicate proposal is
--       refused, the metadata is verified at approval, the GM and
--       Officer permissions hold, the proposal survives a reload, and
--       every decision is traced.

local function loadActor(playerName, leader, rank, saved)
  local _, dibs = loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = playerName, guildLeader = leader,
    guildMembers = { "GM-Realm", "Officer-Realm", "Player-Realm", "Tester-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 4, [4] = 4 },
    guildName = "RF0013 Test Guild", guildRealm = "TestRealm",
  } })
  dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
  return dibs
end

local function seedLedger(dibs, count, prefix)
  local seasonId = dibs.Seasons.GetCurrent().id
  for index = 1, count do
    dibs.Ledger.AddTransaction({
      transactionId = string.format("%s-%04d", prefix or "rf0013-verify", index),
      playerName = "Tester-Realm", amount = 1, type = "DIB_GRANTED",
      reason = "RF-0013 verification row", source = "test",
      seasonId = seasonId, createdAt = 1700000000 + index,
    })
  end
end

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

local function metadata(overrides)
  local value = {
    purpose = "GUILD_PRIMARY_MISSING",
    discoveredSources = { "ledger" },
    discoveredCounts = { ledger = 0 },
    unreadableSources = {},
    scanComplete = true,
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

-- A proposal written before the metadata contract existed: a `PROPOSED`
-- ledger with empty options and no entry in the proposal index.
local function seedLegacyProposal(dibs, ledgerId)
  local db = dibs.GetDB()
  db.ledgers = db.ledgers or {}
  db.ledgers[ledgerId] = {
    id = ledgerId, name = "Guild Primary", status = "PROPOSED",
    createdAt = 1700000000, createdBy = "Officer-Realm", isDefault = false,
    options = {}, transactions = {}, playerStates = {}, awardTransactions = {},
    evidenceTransactions = {},
    canonical = { schema = 1, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
  }
  return ledgerId
end

describe("RF-0013 A1 guarantees", function()
  it("V01 the pagination loses no record across a batch boundary", function()
    local dibs = loadActor("Tester-Realm", true, 0)
    -- More than one batch, so the boundary is crossed.
    seedLedger(dibs, 1200, "rf0013-v01")
    local total = sourceSize(dibs)
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v01")
    assert_not_nil(result, "the collection failed: " .. tostring(reason))
    assert_equal(total, #result.ledger, "a record was lost across the batch boundary")
    assert_equal(total, evidenceCount(dibs), "the collected evidence does not match the source")
  end)

  it("V02 the collection resumes after an interruption", function()
    local dibs = loadActor("Tester-Realm", true, 0)
    seedLedger(dibs, 700, "rf0013-v02")
    local total = sourceSize(dibs)
    -- The first collection is interrupted after the first batch: the
    -- progress is left INCOMPLETE with the cursor at the batch boundary.
    dibs.GetDB().legacyBaseline = dibs.GetDB().legacyBaseline or {}
    dibs.GetDB().legacyBaseline.collectionProgress = {
      ["v02:ledger"] = { cursor = 500, sourceFingerprint = "stale", totalSeen = 500, state = "INCOMPLETE" },
    }
    -- The fingerprint is stale, so the source is recollected from the
    -- beginning: the already-collected records are a no-op.
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v02")
    assert_not_nil(result, "the resumption failed: " .. tostring(reason))
    assert_equal(total, #result.ledger, "the resumption lost a record")
    assert_equal(total, evidenceCount(dibs), "the resumption duplicated a record")
    local progress = dibs.HistoricalBaseline.GetCollectionProgress("v02:ledger")
    assert_equal("COMPLETE", progress["v02:ledger"].state, "the resumption did not complete")
  end)

  it("V03 the deduplication holds when the same batch is collected twice", function()
    local dibs = loadActor("Tester-Realm", true, 0)
    seedLedger(dibs, 300, "rf0013-v03")
    local first = assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v03"))
    local afterFirst = evidenceCount(dibs)
    local second = assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v03"))
    assert_equal(#first.ledger, #second.ledger, "the replay reported a different set")
    assert_equal(afterFirst, evidenceCount(dibs), "the replay duplicated evidence")
  end)

  it("V04 a source that changes during the collection does not loop forever", function()
    local dibs = loadActor("Tester-Realm", true, 0)
    -- The source grows on every round, so the fingerprint never matches
    -- and the cursor is reset every time. The collection must still
    -- terminate and converge.
    local seasonId = dibs.Seasons.GetCurrent().id
    for round = 1, 4 do
      dibs.Ledger.AddTransaction({
        transactionId = string.format("rf0013-v04-%02d", round),
        playerName = "Tester-Realm", amount = 1, type = "DIB_GRANTED",
        reason = "growing source", source = "test", seasonId = seasonId,
        createdAt = 1700000100 + round,
      })
      local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v04")
      assert_not_nil(result, "the collection did not terminate on round " .. tostring(round) .. ": " .. tostring(reason))
    end
    local progress = dibs.HistoricalBaseline.GetCollectionProgress("v04:ledger")
    assert_equal("COMPLETE", progress["v04:ledger"].state, "the collection never converged")
    assert_equal(sourceSize(dibs), evidenceCount(dibs), "the growing source was not fully collected")
  end)

  it("V05 an old SavedVariables root loads and collects", function()
    -- A root from before RF-0013: no collectionProgress, no ledgerProposals.
    local saved = { schemaVersion = 1, guilds = { ["testrealm:rf0013testguild"] = { ledger = { transactions = {} } } } }
    local dibs = loadActor("Tester-Realm", true, 0, saved)
    local state = dibs.HistoricalBaseline.GetState()
    assert_not_nil(state.collectionProgress, "the collection progress was not initialised")
    local result, reason = dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v05")
    assert_not_nil(result, "the collection of an old root failed: " .. tostring(reason))
    local progress = dibs.HistoricalBaseline.GetCollectionProgress("v05:ledger")
    assert_equal("COMPLETE", progress["v05:ledger"].state, "the collection of an old root did not complete")
  end)

  it("V06 a partial collection is never approved as complete", function()
    local dibs = loadActor("GM-Realm", true, 0)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "RF-0013 V06" }) ~= false, "the governance was not adopted")
    seedLedger(dibs, 20, "rf0013-v06")
    assert(dibs.HistoricalBaseline.CollectLocalEvidence(nil, "v06"))
    -- The collection is left INCOMPLETE: the baseline must be refused.
    dibs.GetDB().legacyBaseline.collectionProgress["v06:ledger"].state = "INCOMPLETE"
    dibs.GetDB().legacyBaseline.collectionProgress["v06:ledger"].cursor = 5
    local baseline, reason = dibs.HistoricalBaseline.FinalizeBaseline(nil, { acknowledgeIncompleteEvidence = true })
    assert_nil(baseline, "a partial collection was approved as complete")
    assert_true(reason:find("INCOMPLETE_EVIDENCE_SOURCE_IN_PROGRESS", 1, true) ~= nil,
    "the refusal did not name the in-progress source: " .. tostring(reason))
  end)
end)

describe("RF-0013 B1 guarantees", function()
  it("V07 a proposal written before the metadata contract is not stranded", function()
    -- The officer is the local client: the `ledger.propose` permission
    -- requires the actor to be the local character.
    local officer = loadActor("Officer-Realm", false, 1)
    local ledgerId = seedLegacyProposal(officer, "LDR-legacy-v07")
    -- The legacy proposal carries no metadata: it is adopted into the
    -- index when it is read, so it can be repaired.
    local repaired = officer.MultiLedger.UpdateProposal("Officer-Realm", ledgerId, metadata())
    assert_true(repaired.ok, "the legacy proposal could not be repaired: " .. tostring(repaired.reasonCode))
    local proposal = officer.MultiLedger.GetProposal(repaired.proposalId)
    assert_not_nil(proposal, "the adopted proposal is not readable")
    assert_true(proposal.adopted == true, "the proposal was not marked as adopted")
    -- And it can now be approved by the GM.
    local gm = loadActor("GM-Realm", true, 0, officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", ledgerId)
    assert_true(approved.ok, "the repaired legacy proposal was refused: " .. tostring(approved.reasonCode))
  end)

  it("V08 missing metadata is refused at creation", function()
    local dibs = loadActor("Officer-Realm", false, 1)
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", { discoveredSources = { "ledger" } })
    assert_false(result.ok, "a proposal without a purpose was accepted")
    assert_equal("INVALID_PROPOSAL_PURPOSE", result.reasonCode)
    assert_equal(0, #dibs.MultiLedger.ListProposals(), "the refused proposal was persisted")
  end)

  it("V09 a duplicate active proposal is refused", function()
    local dibs = loadActor("Officer-Realm", false, 1)
    local first = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(first.ok, "the first proposal was refused")
    local second = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_false(second.ok, "a duplicate proposal was accepted")
    assert_equal("DUPLICATE_LEDGER_PROPOSAL", second.reasonCode)
    assert_equal(1, #dibs.MultiLedger.ListProposals(), "two active proposals coexist")
  end)

  it("V10 the metadata is verified again at approval", function()
    local officer = loadActor("Officer-Realm", false, 1)
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the officer proposal was refused")
    -- The volume contradicts the evidence actually available.
    officer.GetDB().legacyBaseline = officer.GetDB().legacyBaseline or {}
    officer.GetDB().legacyBaseline.collectionProgress = {
      ["v10:ledger"] = { cursor = 5, sourceFingerprint = "x", totalSeen = 5, state = "COMPLETE" },
    }
    local gm = loadActor("GM-Realm", true, 0, officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_false(approved.ok, "a proposal with a contradictory volume was approved")
    assert_equal("PROPOSAL_VOLUME_MISMATCH", approved.reasonCode)
  end)

  it("V11 the GM and Officer permissions hold", function()
    local officer = loadActor("Officer-Realm", false, 1)
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the officer could not propose")
    -- The officer cannot approve.
    local byOfficer = officer.MultiLedger.ApproveLedger("Officer-Realm", proposed.ledgerId)
    assert_false(byOfficer.ok, "an officer approved a proposal")
    assert_equal("GUILD_MASTER_REQUIRED", byOfficer.reasonCode)
    -- The GM can.
    local gm = loadActor("GM-Realm", true, 0, officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local byGM = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_true(byGM.ok, "the GM could not approve: " .. tostring(byGM.reasonCode))
  end)

  it("V12 the proposal survives a reload", function()
    local officer = loadActor("Officer-Realm", false, 1)
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the officer proposal was refused")
    -- The client restarts with the same SavedVariables.
    local reloaded = loadActor("Officer-Realm", false, 1, officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local proposal = reloaded.MultiLedger.GetProposal(proposed.proposalId)
    assert_not_nil(proposal, "the proposal did not survive the reload")
    assert_equal("PROPOSED", proposal.status, "the proposal changed status across the reload")
    assert_equal("GUILD_PRIMARY_MISSING", proposal.metadata.purpose, "the metadata did not survive the reload")
    -- And it is still approvable after the reload.
    local gm = loadActor("GM-Realm", true, 0, reloaded.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_true(approved.ok, "the reloaded proposal could not be approved: " .. tostring(approved.reasonCode))
  end)

  it("V13 every decision is traced", function()
    local officer = loadActor("Officer-Realm", false, 1)
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the officer proposal was refused")
    -- A refused approval is traced: the source is still being collected.
    officer.GetDB().legacyBaseline = officer.GetDB().legacyBaseline or {}
    officer.GetDB().legacyBaseline.collectionProgress = {
      ["v13:ledger"] = { cursor = 2, sourceFingerprint = "x", totalSeen = 2, state = "INCOMPLETE" },
    }
    local refused = loadActor("GM-Realm", true, 0, officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local refusal = refused.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_false(refusal.ok, "the approval with an incomplete source was accepted")
    local refusedActions = {}
    for _, entry in ipairs(refused.GetDB().auditLog or {}) do
      if type(entry) == "table" and entry.action == "LEDGER_PROPOSAL_REJECTED" then refusedActions[#refusedActions + 1] = entry end
    end
    assert_true(#refusedActions > 0, "the refusal was not traced")
    assert_not_nil(refusedActions[1].reason, "the traced refusal carries no reason")
    assert_equal("PROPOSAL_SOURCE_INCOMPLETE", refusedActions[1].reason,
      "the traced refusal carries the wrong reason")
    -- An approved decision is traced too.
    local clean = loadActor("Officer-Realm", false, 1)
    local approvedProposal = clean.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(approvedProposal.ok, "the officer proposal was refused")
    local gm = loadActor("GM-Realm", true, 0, clean.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", approvedProposal.ledgerId)
    assert_true(approved.ok, "the approval was refused: " .. tostring(approved.reasonCode))
    local approvedActions = 0
    for _, entry in ipairs(gm.GetDB().auditLog or {}) do
      if type(entry) == "table" and entry.action == "LEDGER_PROPOSAL_APPROVED" then approvedActions = approvedActions + 1 end
    end
    assert_true(approvedActions > 0, "the approval was not traced")
  end)
end)
