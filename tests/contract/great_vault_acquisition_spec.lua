local loader = require("helpers.load_addon")
local fixture = require("helpers.great_vault_fixture")

describe("Great Vault acquisition contract", function()
  it("does not confirm a reward choice without claim evidence", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local result = dibs.GreatVault.EvaluateObservation(fixture.observation({ claimComplete = false, event = "REWARD_CHOICE" }))

    assert_equal("AMBIGUOUS", result.status)
    assert_equal("PARTIAL", result.confidence)
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("confirms a complete claim through the shared acquisition boundary", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local result = dibs.GreatVault.RecordClaim(fixture.observation())

    assert_equal("CONFIRMED", result.status)
    assert_not_nil(result.acquisition)
    assert_equal("AUTOMATIC_CONFIRMED", result.acquisition.verificationState)
  end)

  it("reports unavailable capability without creating a record", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, skipInitialize = true })
    local result = dibs.GreatVault.EvaluateObservation({ itemID = 21016 })

    assert_equal("UNAVAILABLE", result.status)
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)
end)
