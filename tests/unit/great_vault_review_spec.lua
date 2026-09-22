local loader = require("helpers.load_addon")
local fixture = require("helpers.great_vault_fixture")

describe("Great Vault review", function()
  it("confirms a manual record with immutable evidence and an audit decision", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 281001, "Normal", {
      source = "VAULT_MANUAL", family = "TOKEN", evidenceId = "manual:281001",
      evidence = { note = "player report" }, resetId = "week-1",
    })
    local reviewed, reason = dibs.PreDibs.ReviewVaultAcquisition(record.acquisitionId, "OFFICER_CONFIRMED", "Tester-Realm", "Verified against screenshot")

    assert_not_nil(reviewed, reason)
    assert_equal("OFFICER_CONFIRMED", reviewed.verificationState)
    assert_equal("Verified against screenshot", reviewed.review.reason)
    assert_equal("manual:281001", reviewed.originalEvidence.evidenceId)
    assert_equal(2, reviewed.revision)
    assert_equal("OFFICER_CONFIRMED", dibs.PreDibs.GetAcquisitionsForItem(281001)[1].verificationState)
    local replay, replayReason = dibs.PreDibs.ReviewVaultAcquisition(record.acquisitionId, "OFFICER_CONFIRMED", "Tester-Realm", "Verified against screenshot")
    assert_not_nil(replay, replayReason)
    assert_equal("IDEMPOTENT_REPLAY", replayReason)
    assert_true(replay.idempotentReplay)
  end)

  it("requires a reason for rejection and keeps rejected evidence out of eligibility", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 281002, "Normal", {
      source = "GREAT_VAULT", verificationState = "UNVERIFIED", family = "TOKEN",
      resetId = "week-1", evidenceId = "claim:281002",
    })
    local rejected, reason = dibs.PreDibs.ReviewVaultAcquisition(record.acquisitionId, "REJECTED", "Tester-Realm")
    assert_nil(rejected)
    assert_equal("REASON_REQUIRED", reason)

    rejected, reason = dibs.PreDibs.ReviewVaultAcquisition(record.acquisitionId, "REJECTED", "Tester-Realm", "No matching claim")
    assert_not_nil(rejected, reason)
    assert_equal("REJECTED", rejected.verificationState)
    local restored, transitionReason = dibs.PreDibs.ReviewVaultAcquisition(record.acquisitionId, "OFFICER_CONFIRMED", "Tester-Realm", "Later claim")
    assert_nil(restored)
    assert_equal("INVALID_REVIEW_TRANSITION", transitionReason)
  end)
end)
