local loader = require("helpers.load_addon")

-- RF-0013 (B1) regression suite.
--
-- RF-0013 - "Installation.Initialize : decouverte legacy partielle traitee
-- comme terminee" (docs/code-audit/INDEX.md#rf-0013).
--
-- B1 extends `MultiLedger.ProposeLedger` so that a proposal the Guild
-- Master can actually decide on. The five gaps that were confirmed in
-- session 14 are locked here:
--
--   B1-E1 the covered scope is validated;
--   B1-E2 the discovered volume is validated, and re-verified against
--          the evidence actually available at approval;
--   B1-E3 the purpose is validated against a closed list;
--   B1-E4 the unreadable sources are represented explicitly, and a
--          proposal that claims a complete scan cannot hide one;
--   B1-E5 the active proposals are unique: a second proposal on the same
--          purpose and the same scope is refused.
--
-- A proposal is never compliant because its name is "Guild Primary": the
-- approval re-verifies the metadata, not the name.

-- The Guild Master and the Officer share one guild database: the
-- proposal the officer writes is the proposal the GM approves. The
-- `savedVariables` argument is what makes them share it.
local function loadGM(saved)
  local _, dibs = loader.load({ withAce3 = true, savedVariables = saved, wow = {
    guildLeader = true, playerName = "GM-Realm",
    guildMembers = { "GM-Realm", "Officer-Realm", "Member-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 4 },
    guildName = "RF0013 Test Guild", guildRealm = "TestRealm",
  } })
  dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
  return dibs
end

local function loadOfficer(saved)
  local _, dibs = loader.load({ withAce3 = true, savedVariables = saved, wow = {
    guildLeader = false, playerName = "Officer-Realm",
    guildMembers = { "GM-Realm", "Officer-Realm", "Member-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 4 },
    guildName = "RF0013 Test Guild", guildRealm = "TestRealm",
  } })
  dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
  return dibs
end

local function loadMember()
  local _, dibs = loader.load({ withAce3 = true, wow = {
    guildLeader = false, playerName = "Member-Realm",
    guildMembers = { "GM-Realm", "Officer-Realm", "Member-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 4 },
  } })
  return dibs
end

-- The shared guild database of the officer and the Guild Master. The
-- guild key is the one the addon actually computes for this roster, so
-- both clients read and write the same partition.
local function sharedDatabase()
  return { schemaVersion = 1, guilds = {} }
end

-- A valid proposal metadata set.
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

local function auditActions(dibs)
  local actions = {}
  for _, entry in ipairs(dibs.GetDB().auditLog or {}) do
    if type(entry) == "table" and entry.action and entry.action:find("LEDGER_PROPOSAL", 1, true) then
      actions[#actions + 1] = entry.action
    end
  end
  return actions
end

local function hasAction(dibs, action)
  for _, found in ipairs(auditActions(dibs)) do if found == action then return true end end
  return false
end

describe("RF-0013 B1 officer proposal", function()
  it("B01 refuses a proposal from a plain member", function()
    local dibs = loadMember()
    local result = dibs.MultiLedger.ProposeLedger("Member-Realm", "Guild Primary", metadata())
    assert_false(result.ok, "a plain member created a proposal")
    assert_equal("GUILD_ADMIN_REQUIRED", result.reasonCode)
    assert_equal(0, #dibs.MultiLedger.ListProposals(), "the refused proposal was persisted")
  end)

  it("B02 persists a proposal with its metadata and makes it readable", function()
    local dibs = loadOfficer()
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(result.ok, "the officer proposal was refused: " .. tostring(result.reasonCode))
    assert_not_nil(result.ledgerId, "the proposal carries no ledger id")
    assert_not_nil(result.proposalId, "the proposal carries no proposal id")
    local proposal = dibs.MultiLedger.GetProposal(result.proposalId)
    assert_not_nil(proposal, "the proposal cannot be read back")
    assert_equal("PROPOSED", proposal.status)
    assert_equal("GUILD_PRIMARY_MISSING", proposal.metadata.purpose)
    assert_equal(1, #proposal.metadata.discoveredSources)
    -- The metadata travels with the ledger so the GM sees it.
    for _, ledger in ipairs(dibs.MultiLedger.GetLedgers()) do
      if ledger.id == result.ledgerId then
        assert_not_nil(ledger.proposal, "the ledger carries no proposal metadata")
        assert_equal("GUILD_PRIMARY_MISSING", ledger.proposal.purpose)
      end
    end
  end)

  it("B03 refuses a second active proposal on the same purpose and scope", function()
    local dibs = loadOfficer()
    local first = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(first.ok, "the first proposal was refused")
    local second = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_false(second.ok, "a contradictory active proposal was accepted")
    assert_equal("DUPLICATE_LEDGER_PROPOSAL", second.reasonCode)
    assert_equal(1, #dibs.MultiLedger.ListProposals(), "two active proposals coexist")
  end)

  it("B04 refuses a purpose outside the closed list", function()
    local dibs = loadOfficer()
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ purpose = "BECAUSE_I_SAID_SO" }))
    assert_false(result.ok, "an unknown purpose was accepted")
    assert_equal("INVALID_PROPOSAL_PURPOSE", result.reasonCode)
    assert_equal(0, #dibs.MultiLedger.ListProposals(), "the refused proposal was persisted")
  end)

  it("B05 refuses a scope that names an unknown source", function()
    local dibs = loadOfficer()
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ discoveredSources = { "ledger", "wallet" } }))
    assert_false(result.ok, "an unknown source was accepted")
    assert_equal("INVALID_PROPOSAL_SCOPE", result.reasonCode)
  end)

  it("B06 refuses a volume that is not a non-negative integer", function()
    local dibs = loadOfficer()
    local negative = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ discoveredCounts = { ledger = -1 } }))
    assert_false(negative.ok, "a negative volume was accepted")
    assert_equal("INVALID_PROPOSAL_VOLUME", negative.reasonCode)
    local fractional = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ discoveredCounts = { ledger = 1.5 } }))
    assert_false(fractional.ok, "a fractional volume was accepted")
    assert_equal("INVALID_PROPOSAL_VOLUME", fractional.reasonCode)
    local unknown = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ discoveredCounts = { wallet = 3 } }))
    assert_false(unknown.ok, "a volume for an unknown source was accepted")
    assert_equal("INVALID_PROPOSAL_VOLUME", unknown.reasonCode)
  end)

  it("B07 refuses a complete scan that hides an unreadable source", function()
    local dibs = loadOfficer()
    local result = dibs.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ unreadableSources = { "predibs" }, scanComplete = true }))
    assert_false(result.ok, "a proposal claiming a complete scan with an unreadable source was accepted")
    assert_equal("INVALID_PROPOSAL_COMPLETENESS", result.reasonCode)
  end)

  it("B08 refuses the approval of a proposal whose source is still incomplete", function()
    local officer = loadOfficer()
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the officer proposal was refused")
    -- The source collection is still running: the proposal cannot be
    -- approved on a scan that has not finished.
    officer.GetDB().legacyBaseline = officer.GetDB().legacyBaseline or {}
    officer.GetDB().legacyBaseline.collectionProgress = {
      ["proposal-scan:ledger"] = { cursor = 3, sourceFingerprint = "x", totalSeen = 3, state = "INCOMPLETE" },
    }
    local gm = loadGM(officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    -- The GM shares the same guild database: the approval sees the same
    -- in-progress collection.
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_false(approved.ok, "a proposal with an incomplete source was approved")
    assert_equal("PROPOSAL_SOURCE_INCOMPLETE", approved.reasonCode)
  end)

  it("B09 refuses the approval of a proposal with an unreadable source", function()
    local officer = loadOfficer()
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ unreadableSources = { "predibs" }, scanComplete = false }))
    assert_true(proposed.ok, "the officer proposal was refused: " .. tostring(proposed.reasonCode))
    local gm = loadGM(officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_false(approved.ok, "a proposal with an unreadable source was approved")
    assert_equal("PROPOSAL_UNREADABLE_SOURCES", approved.reasonCode)
  end)

  it("B10 refuses the approval when the declared volume contradicts the evidence", function()
    local officer = loadOfficer()
    -- The collection completed with 7 records.
    officer.GetDB().legacyBaseline = officer.GetDB().legacyBaseline or {}
    officer.GetDB().legacyBaseline.collectionProgress = {
      ["proposal-volume:ledger"] = { cursor = 7, sourceFingerprint = "x", totalSeen = 7, state = "COMPLETE" },
    }
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ discoveredCounts = { ledger = 999 } }))
    assert_true(proposed.ok, "the officer proposal was refused: " .. tostring(proposed.reasonCode))
    local gm = loadGM(officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_false(approved.ok, "a proposal whose volume contradicts the evidence was approved")
    assert_equal("PROPOSAL_VOLUME_MISMATCH", approved.reasonCode)
  end)

  it("B11 lets the GM approve a valid proposal and records the trace", function()
    local officer = loadOfficer()
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the officer proposal was refused")
    local gm = loadGM(officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_true(approved.ok, "the GM approval was refused: " .. tostring(approved.reasonCode))
    -- The ledger is approved.
    for _, ledger in ipairs(gm.MultiLedger.GetLedgers()) do
      if ledger.id == proposed.ledgerId then
        assert_equal("APPROVED", ledger.status, "the ledger was not approved")
      end
    end
    -- The creation and the approval are both traced.
    assert_true(hasAction(officer, "LEDGER_PROPOSAL_CREATED"), "the creation was not traced")
    assert_true(hasAction(gm, "LEDGER_PROPOSAL_APPROVED"), "the approval was not traced")
  end)

  it("B12 refuses the approval of a proposal by an officer", function()
    local officer = loadOfficer()
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok)
    local approved = officer.MultiLedger.ApproveLedger("Officer-Realm", proposed.ledgerId)
    assert_false(approved.ok, "an officer approved a proposal")
    assert_equal("GUILD_MASTER_REQUIRED", approved.reasonCode)
    for _, ledger in ipairs(officer.MultiLedger.GetLedgers()) do
      if ledger.id == proposed.ledgerId then
        assert_equal("PROPOSED", ledger.status, "the proposal was approved anyway")
      end
    end
  end)

  it("B13 lets the officer correct a proposal and keeps the trace", function()
    local officer = loadOfficer()
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      metadata({ unreadableSources = { "predibs" }, scanComplete = false }))
    assert_true(proposed.ok, "the officer proposal was refused")
    local updated = officer.MultiLedger.UpdateProposal("Officer-Realm", proposed.proposalId,
      metadata({ unreadableSources = {}, scanComplete = true }))
    assert_true(updated.ok, "the correction was refused: " .. tostring(updated.reasonCode))
    local proposal = officer.MultiLedger.GetProposal(proposed.proposalId)
    assert_equal(0, #proposal.metadata.unreadableSources, "the unreadable sources were not cleared")
    assert_true(hasAction(officer, "LEDGER_PROPOSAL_UPDATED"), "the correction was not traced")
  end)

  it("B14 refuses a proposal whose metadata is absent when a source is declared", function()
    local officer = loadOfficer()
    -- A proposal that declares a source but carries no purpose is invalid.
    local result = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary",
      { discoveredSources = { "ledger" } })
    assert_false(result.ok, "a proposal without a purpose was accepted")
    assert_equal("INVALID_PROPOSAL_PURPOSE", result.reasonCode)
  end)

  it("B15 never reports a proposal created when none was persisted", function()
    local member = loadMember()
    local result = member.MultiLedger.ProposeLedger("Member-Realm", "Guild Primary", metadata())
    assert_false(result.ok)
    -- The refusal never claims a proposal, and the store stays empty.
    assert_nil(result.proposalId, "a refused proposal reported an identifier")
    assert_equal(0, #member.MultiLedger.ListProposals())
    local ledgers = member.MultiLedger.GetLedgers()
    local proposed = 0
    for _, ledger in ipairs(ledgers) do if ledger.status == "PROPOSED" then proposed = proposed + 1 end end
    assert_equal(0, proposed, "a refused proposal left a ledger behind")
  end)

  it("B16 refuses approval when discovered history was omitted from the declared scope", function()
    local officer = loadOfficer()
    table.insert(officer.GetDB().preDibs.requests, {
      requestId = "rf0013-omitted-predib", playerName = "Member-Realm", itemID = 19019,
      status = "requested", seasonId = officer.Seasons.GetCurrent().id, createdAt = 1700000001,
    })
    local proposed = officer.MultiLedger.ProposeLedger("Officer-Realm", "Guild Primary", metadata())
    assert_true(proposed.ok, "the proposal should be persisted for GM review")
    local gm = loadGM(officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local approved = gm.MultiLedger.ApproveLedger("GM-Realm", proposed.ledgerId)
    assert_false(approved.ok, "the proposal silently omitted existing Pre-Dibs history")
    assert_equal("PROPOSAL_SOURCE_OMITTED", approved.reasonCode)
  end)
end)
