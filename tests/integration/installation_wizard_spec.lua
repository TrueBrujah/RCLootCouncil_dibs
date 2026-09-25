local loader = require("helpers.load_addon")

local roster = { "Tester-Realm", "Officer-Realm", "Member-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, guildLeader, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = guildLeader, guildMembers = roster, guildRankIndices = ranks,
  } }))
end

describe("Installation readiness projection", function()
  it("reports NOT_INITIALIZED before governance adoption and hides the actor from initializing", function()
    local dibs = load("Tester-Realm", true)
    local status = dibs.Installation.GetStatus()
    assert_equal("NOT_INITIALIZED", status.state)
    assert_equal("CLEAN", status.installType)
    assert_true(status.actor.isGM)

    local member = load("Member-Realm", false)
    local memberStatus = member.Installation.GetStatus()
    assert_equal("NOT_INITIALIZED", memberStatus.state)
    assert_false(memberStatus.actor.isGM)
  end)

  it("reports READY_TO_INITIALIZE on a clean guild after governance adoption", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local status = dibs.Installation.GetStatus()
    assert_equal("READY_TO_INITIALIZE", status.state)
    assert_equal("CLEAN", status.installType)
    assert_equal(0, status.legacy.evidenceCount)
    assert_false(status.legacy.reconciliationRequired)
  end)

  it("reports RECONCILIATION_REQUIRED when real legacy ledger data has not been scanned yet", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local season = dibs.Seasons.Create("Legacy Season")
    assert_not_nil(season)
    assert_not_nil(dibs.Ledger.Grant("Member-Realm", 1, "legacy grant", "test", season.id))
    local status = dibs.Installation.GetStatus()
    assert_equal("RECONCILIATION_REQUIRED", status.state)
    assert_equal("UPGRADE", status.installType)
    assert_true(status.legacy.hasUncollectedEvidence)
  end)
end)

describe("Installation.Initialize orchestrator", function()
  it("rejects a non-GM without mutating anything", function()
    local dibs = load("Member-Realm", false)
    local result = dibs.Installation.Initialize(nil)
    assert_false(result.ok)
    assert_equal("GUILD_MASTER_REQUIRED", result.reasonCode)
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
  end)

  it("initializes a clean guild in one call and is idempotent", function()
    local dibs = load("Tester-Realm", true)
    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("READY", result.status.state)
    assert_true(dibs.Governance.IsV2Enforced())
    assert_equal("GENESIS", result.status.baseline.type)

    local governanceRevisionAfterFirst = dibs.Governance.GetState().revision
    local second = dibs.Installation.Initialize(nil)
    assert_true(second.ok)
    assert_equal("ALREADY_INITIALIZED", second.reasonCode)
    assert_equal(governanceRevisionAfterFirst, dibs.Governance.GetState().revision)
  end)

  it("blocks one-click initialization when legacy evidence has open findings, and resumes after reconciliation", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local season = dibs.Seasons.Create("Legacy Season")
    assert_not_nil(dibs.Ledger.Grant("Member-Realm", 1, "legacy grant", "test", season.id))

    local blocked = dibs.Installation.Initialize(nil)
    assert_false(blocked.ok)
    assert_equal("baseline", blocked.stage)
    assert_equal("LEGACY_RECONCILIATION_REQUIRED", blocked.reasonCode)
    assert_true(blocked.status.legacy.evidenceCount > 0)
    assert_nil(dibs.LegacyBaseline.GetBaseline())

    for _, evidence in ipairs(dibs.LegacyBaseline.GetEvidence()) do
      assert_not_nil(dibs.LegacyBaseline.RecordDecision(nil, evidence.evidenceId, "INCLUDE", { reason = "reviewed" }))
    end

    local resumed = dibs.Installation.Initialize(nil)
    assert_true(resumed.ok, tostring(resumed.reasonCode))
    assert_equal("READY", resumed.status.state)
    assert_equal("RECONCILED", resumed.status.baseline.type)
  end)

  it("does not silently acknowledge incomplete evidence sources", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local added = dibs.LegacyBaseline.CollectEvidence(nil, {
      sourceId = "manual-import", sourceClient = "Tester-Realm", sourceType = "LEDGER_TRANSACTION", complete = false,
    }, { { originalId = "tx-1", record = { transactionId = "tx-1", playerName = "Member-Realm", amount = 1, seasonId = "S1", actionType = "DIB_GRANTED" } } })
    assert_not_nil(added)
    assert_not_nil(dibs.LegacyBaseline.RecordDecision(nil, added[1], "INCLUDE", { reason = "reviewed" }))

    local blocked = dibs.Installation.Initialize(nil)
    assert_false(blocked.ok)
    assert_equal("baseline", blocked.stage)
    assert_equal("INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED", blocked.reasonCode)
    assert_nil(dibs.LegacyBaseline.GetBaseline())

    local resumed = dibs.Installation.Initialize(nil, { acknowledgeIncompleteEvidence = true })
    assert_true(resumed.ok, tostring(resumed.reasonCode))
    assert_equal("READY", resumed.status.state)
  end)

  it("resumes from the authority stage after a partial reload-simulated failure", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    assert_not_nil(dibs.LegacyBaseline.FinalizeBaseline(nil))
    local status = dibs.Installation.GetStatus()
    assert_equal("READY_TO_INITIALIZE", status.state)
    assert_false(dibs.Governance.IsV2Enforced())

    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal("READY", result.status.state)
  end)
end)

describe("P0 regression: Governance.ActivateV2 never silently acknowledges incomplete evidence", function()
  it("stops on incomplete evidence sources unless the caller explicitly acknowledges them", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local added = dibs.LegacyBaseline.CollectEvidence(nil, {
      sourceId = "manual-import", sourceClient = "Tester-Realm", sourceType = "LEDGER_TRANSACTION", complete = false,
    }, { { originalId = "tx-1", record = { transactionId = "tx-1", playerName = "Member-Realm", amount = 1, seasonId = "S1", actionType = "DIB_GRANTED" } } })
    assert_not_nil(dibs.LegacyBaseline.RecordDecision(nil, added[1], "INCLUDE", { reason = "reviewed" }))

    local blocked, blockedReason = dibs.Governance.ActivateV2(nil)
    assert_false(blocked)
    assert_equal("INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED", blockedReason)
    assert_nil(dibs.LegacyBaseline.GetBaseline())
    assert_false(dibs.Governance.IsV2Enforced())

    local enabled, enableReason = dibs.Governance.ActivateV2(nil, { acknowledgeIncompleteEvidence = true })
    assert_true(enabled, tostring(enableReason))
  end)

  it("still allows the deterministic empty/genesis baseline for a truly clean guild", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local enabled, reason = dibs.Governance.ActivateV2(nil)
    assert_true(enabled, tostring(reason))
    assert_true(dibs.Governance.IsV2Enforced())
  end)
end)
