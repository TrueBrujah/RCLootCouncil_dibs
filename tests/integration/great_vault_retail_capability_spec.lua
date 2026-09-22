local loader = require("helpers.load_addon")

describe("Great Vault Retail capability", function()
  it("initializes safely when no Retail Great Vault API is present", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })

    assert_not_nil(dibs.GreatVault)
    assert_equal("UNAVAILABLE", dibs.GreatVault.GetCapability().status)
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic")
    assert_equal("MANUAL_RECORDED", record.verificationState)
  end)
end)
