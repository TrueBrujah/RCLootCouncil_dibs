local loader = require("helpers.load_addon")

describe("Raid relay", function()
  it("broadcasts hello and a manifest only when relay is active", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, inRaid = true }, withAce3 = true })
    local sent = {}
    dibs.Sync.Send = function(message, channel)
      sent[#sent + 1] = { message = message, channel = channel }
      return true
    end

    local _, inactiveSent = dibs.RaidRelay.Broadcast()
    assert_false(inactiveSent)
    assert_equal(0, #sent)

    dibs.RaidRelay.SetActiveRelay(true)
    local _, activeSent = dibs.RaidRelay.Broadcast("RAID")
    assert_true(activeSent)
    assert_equal(2, #sent)
    assert_equal("HELLO", sent[1].message.type)
    assert_equal("MANIFEST", sent[2].message.type)
    assert_equal("RAID", sent[2].channel)
  end)

  it("keeps relay state and full-state export restricted to guild administrators", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = false,
      guildMembers = { "Tester-Realm" },
      guildRankIndices = { [1] = 3 },
    } })
    local enabled, enableReason = dibs.RaidRelay.SetActiveRelay(true)
    assert_nil(enabled)
    assert_equal("GUILD_ADMIN_REQUIRED", enableReason)
    local state, sent, reason = dibs.RaidRelay.Broadcast()
    assert_equal(0, #state.transactions)
    assert_false(sent)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)
end)
