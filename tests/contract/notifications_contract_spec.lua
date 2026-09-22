local loader = require("helpers.load_addon")

describe("Notifications contract", function()
  it("emits one local notification per event identity", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local messages = 0
    dibs.Message = function() messages = messages + 1 end
    assert_true(dibs.Notifications.Notify("predib-1", "PREDIB_CONFIRMED", { targetPlayer = dibs.GetPlayerName(), itemName = "Blade" }))
    assert_false(dibs.Notifications.Notify("predib-1", "PREDIB_CONFIRMED", { targetPlayer = dibs.GetPlayerName(), itemName = "Blade" }))
    assert_equal(1, messages)
  end)

  it("does not disclose another player's event and supports per-character disablement", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local messages = 0
    dibs.Message = function() messages = messages + 1 end
    assert_false(dibs.Notifications.Notify("other-1", "VAULT_RECORDED", { targetPlayer = "Other-Realm", itemName = "Private item" }))
    assert_equal(0, messages)
    assert_false(dibs.Notifications.SetEnabled(false))
    assert_false(dibs.Notifications.Notify("local-1", "VAULT_RECORDED", { targetPlayer = dibs.GetPlayerName(), itemName = "Item" }))
    assert_equal(0, messages)
  end)

  it("deduplicates after a local SavedVariables reload", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local localVariables = _G.RCLootCouncil_dibsLocalDB
    dibs.Notifications.Notify("reload-1", "REQUEST_RESOLVED", { targetPlayer = dibs.GetPlayerName(), itemName = "Item" })
    local _, reloaded = loader.load({ wow = { guildLeader = true }, withAce3 = true, localVariables = localVariables })
    local messages = 0
    reloaded.Message = function() messages = messages + 1 end
    assert_false(reloaded.Notifications.Notify("reload-1", "REQUEST_RESOLVED", { targetPlayer = reloaded.GetPlayerName(), itemName = "Item" }))
    assert_equal(0, messages)
  end)
end)
