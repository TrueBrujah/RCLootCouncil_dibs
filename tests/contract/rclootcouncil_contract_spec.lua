local loader = require("helpers.load_addon")

describe("RC contract", function()
  it("reports absent when RC is missing", function()
    local _, dibs = loader.load({ withLibStub = false, wow = { guildLeader = true } })
    assert_equal("absent", dibs.RCLootCouncil.GetAvailability())
  end)

  it("reports operational with enabled RC and master looter", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-ML" } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    assert_equal("operational", dibs.RCLootCouncil.GetAvailability())
  end)
end)
