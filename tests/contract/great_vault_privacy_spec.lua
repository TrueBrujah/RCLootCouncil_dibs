local loader = require("helpers.load_addon")
local fixture = require("helpers.great_vault_fixture")

describe("Great Vault privacy", function()
  it("keeps evidence private while exposing player-safe status and reset context", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 281020, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      family = "TOKEN", resetId = "week-1", evidenceId = "claim:281020",
      evidence = { privateCallbackPayload = "secret" },
    })
    local projection = dibs.PreDibs.ProjectVaultAcquisition(record, "player")

    assert_equal("AUTOMATIC_CONFIRMED", projection.verificationState)
    assert_equal(record.resetId, projection.resetId)
    assert_nil(projection.evidence)
    assert_nil(projection.originalEvidence)
    assert_equal("claim:281020", projection.evidenceId)
  end)
end)
