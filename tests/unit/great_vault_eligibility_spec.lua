local loader = require("helpers.load_addon")
local fixture = require("helpers.great_vault_fixture")

describe("Great Vault eligibility", function()
  it("counts confirmed Vault evidence without creating a ledger transaction", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local policy = dibs.ProtectedActions.Execute("eligibility.policy.set", nil, {
      seasonId = seasonId, family = "TOKEN", completionThreshold = 1,
    })
    assert_true(policy.ok)
    local before = #dibs.Ledger.GetAllTransactions()
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 281010, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      family = "TOKEN", slot = "head", resetId = "week-1", evidenceId = "claim:281010",
    })
    assert_not_nil(record)
    local decision = dibs.CharacterEligibility.Evaluate({
      seasonId = seasonId, family = "TOKEN", itemID = 281011, slot = "chest", difficulty = "Normal",
    }, "Tester-Realm", seasonId)
    assert_equal("block", decision.outcome)
    assert_equal("CURIO_COMPLETE", decision.reasonCode)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("routes uncertain Vault evidence to review under the default unknown-data policy", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local policy = dibs.ProtectedActions.Execute("eligibility.policy.set", nil, {
      seasonId = seasonId, family = "TOKEN", completionThreshold = 1,
    })
    assert_true(policy.ok)
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 281012, "Normal", {
      source = "VAULT_MANUAL", verificationState = "MANUAL_RECORDED", family = "TOKEN",
      slot = "head", resetId = "week-1", evidenceId = "manual:281012",
    })
    assert_not_nil(record)
    local decision = dibs.CharacterEligibility.Evaluate({
      seasonId = seasonId, family = "TOKEN", itemID = 281013, slot = "chest", difficulty = "Normal",
    }, "Tester-Realm", seasonId)
    assert_equal("review", decision.outcome)
    assert_equal("VAULT_EVIDENCE_UNCERTAIN", decision.reasonCode)
  end)
end)
