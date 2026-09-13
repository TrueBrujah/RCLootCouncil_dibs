local loader = require("helpers.load_addon")

local function supportedRC(options)
  options = options or {}
  options.enabled = options.enabled ~= false
  options.version = "DIBS_TEST_RCLC_AWARD_V1"
  options.dibsAdapterProfile = "DIBS_RCLC_AWARD_TEST_V1"
  return loader.makeRCLootCouncil(options)
end

local roster = { "Coordinator-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function activateV2()
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = "Coordinator-Realm", guildLeader = true,
    guildMembers = roster, guildRankIndices = ranks,
  } })
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "B09 governance" }))
  local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Coordinator-Realm"))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 9,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { "Coordinator-Realm" }))
  assert_not_nil(dibs.Seasons.Create("B09"))
  assert_not_nil(dibs.Ledger.Grant("Player-Realm", 1, "B09 setup", "test", dibs.GetCurrentSeasonId()))
  return dibs
end

describe("B09 RCLootCouncil versioned award adapter", function()
  it("keeps core operational when RC is absent or its version is unsupported", function()
    local _, absent = loader.load({ wow = { guildLeader = true } })
    assert_equal("absent", absent.RCLootCouncil.GetCapabilities().state)
    assert_true(absent.Permissions.Can("settings.modify"))

    local rc = loader.makeRCLootCouncil({ enabled = true, version = "unverified-retail" })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local status = dibs.RCLootCouncil.GetAwardAdapterStatus()
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, 1, "Tester-Realm", "awarded", "item:19019", "DIB")
    assert_equal("UNSUPPORTED", status.state)
    assert_false(status.awardEvidence)
    assert_true(result.ignored)
    assert_equal("RC_VERSION_UNSUPPORTED", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("accepts only the explicit fixture profile and routes final evidence through the protected command", function()
    local rc = supportedRC({ currentSessionId = "b09-session" })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local status = dibs.RCLootCouncil.GetAwardAdapterStatus()
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local result = dibs.RCLootCouncil.OnAwardSuccess(nil, 7, "Tester-Realm", "awarded", "item:19019", "DIB")

    assert_equal("AVAILABLE", status.state)
    assert_true(status.awardEvidence)
    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
    local receipts = dibs.GetDB().rclootcouncilAdapter.evidence
    local receipt = receipts["rclc:session:b09-session:7:tester-realm:19019"]
    assert_equal("DIBS_RCLC_AWARD_TEST_V1", receipt.adapterProfile)
    assert_equal(nil, receipt.raw)
    assert_equal(nil, receipt.winner)
  end)

  it("fails closed for unknown callbacks, statuses, ambiguous identity, and malformed items", function()
    local rc = supportedRC({ currentSessionId = "b09-fail-closed" })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local callback = dibs.RCLootCouncil.HandleAwardCallback("OtherCallback", 1, "Tester-Realm", "awarded", "item:19019", "DIB")
    local status = dibs.RCLootCouncil.OnAwardSuccess(nil, 2, "Tester-Realm", "normal", "item:19019", "DIB")
    local identity = dibs.RCLootCouncil.OnAwardSuccess(nil, 3, "Tester", "awarded", "item:19019", "DIB")
    local item = dibs.RCLootCouncil.OnAwardSuccess(nil, 4, "Tester-Realm", "awarded", "not-an-item", "DIB")
    assert_equal("RC_AWARD_CALLBACK_UNSUPPORTED", callback.reasonCode)
    assert_equal("AWARD_STATUS_UNSUPPORTED", status.reasonCode)
    assert_equal("AWARD_IDENTITY_UNAVAILABLE", identity.reasonCode)
    assert_equal("AWARD_INVALID_ITEM", item.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("makes same evidence idempotent and conflicting evidence manual-review only", function()
    local rc = supportedRC({ currentSessionId = "b09-dedupe" })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local first = dibs.RCLootCouncil.OnAwardSuccess(nil, 4, "Tester-Realm", "awarded", "item:19019", "DIB")
    local duplicate = dibs.RCLootCouncil.OnAwardSuccess(nil, 4, "Tester-Realm", "awarded", "item:19019", "DIB")
    local conflict = dibs.RCLootCouncil.OnAwardSuccess(nil, 4, "Tester-Realm", "awarded", "item:19019:0", "DIB")
    assert_true(first.ok)
    assert_true(duplicate.duplicate)
    assert_equal("AWARD_EVIDENCE_CONFLICT", conflict.reasonCode)
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("keeps a non-coordinator callback out of the canonical ledger", function()
    local coordinator = activateV2()
    local saved = coordinator.DeepCopy(_G.RCLootCouncil_dibsDB)
    local rc = supportedRC({ currentSessionId = "b09-non-coordinator" })
    local _, follower = loader.load({
      rclootcouncil = rc, savedVariables = saved,
      wow = { playerName = "Officer-Realm", guildLeader = false,
        guildMembers = roster, guildRankIndices = ranks },
    })
    local season = follower.GetCurrentSeasonId()
    local before = follower.Ledger.GetBalance("Player-Realm", season)
    local result = follower.RCLootCouncil.OnAwardSuccess(nil, 8, "Player-Realm", "awarded", "item:19019", "DIB")

    assert_false(result.ok)
    assert_equal("CURRENT_COORDINATOR_REQUIRED", result.reasonCode)
    assert_equal("PENDING_RECONCILIATION", result.proposal.status)
    assert_equal(before, follower.Ledger.GetBalance("Player-Realm", season))
    assert_equal(0, follower.Ledger.GetCanonicalState().commitCount)
  end)

  it("keeps legacy dibsOrigin history display-only and leaves RC history unchanged", function()
    local history = { ["Tester-Realm"] = {
      { id = "old-dib", dibsOrigin = "RCLootCouncil_dibs", lootWon = "item:19019", response = "DIB" },
    } }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local result, reason = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, session.candidates[1].candidateId, {
      confirmation = true, manualAcknowledgement = true, reason = "review",
    }, nil)
    assert_true(rows[1].legacySynthetic)
    assert_equal("Dibs legacy synthetic history", rows[1].historySource)
    assert_equal("legacy", session.candidates[1].classification)
    assert_equal(nil, result)
    assert_equal("HISTORY_LEGACY_DISPLAY_ONLY", reason)
    assert_equal("RCLootCouncil_dibs", history["Tester-Realm"][1].dibsOrigin)
  end)
end)
