describe("TOC load integrity", function()
  it("loads every required source listed in addon load order", function()
    local required = {
      "Core.lua",
      "locales/enUS.lua",
      "locales/frFR.lua",
      "modules/Seasons.lua",
      "modules/RankRules.lua",
      "modules/Ledger.lua",
      "modules/Permissions.lua",
      "modules/ProtectedActions.lua",
      "modules/PreDibs.lua",
      "modules/LootPipeline.lua",
      "modules/Sync.lua",
      "modules/RaidRelay.lua",
      "integrations/Ace3.lua",
      "integrations/DeveloperMode.lua",
      "integrations/EncounterJournal.lua",
      "integrations/RCLootCouncil.lua",
      "ui/AceGUI.lua",
      "ui/PlayerUI.lua",
      "ui/OfficerUI.lua",
    }

    for _, relative in ipairs(required) do
      local chunk, err = loadfile("src/" .. relative)
      assert_not_nil(chunk, "unloadable source: src/" .. relative .. " :: " .. tostring(err))
    end
  end)

  it("registers the Dibs slash handler after initialization", function()
    local loader = require("helpers.load_addon")
    loader.load({ wow = { guildLeader = true } })

    assert_not_nil(_G.SlashCmdList.DIBS)
    assert_equal("/dibs", _G.SLASH_DIBS1)
  end)

  it("reports embedded Ace3 service availability", function()
    local loader = require("helpers.load_addon")
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })

    local status = dibs.GetFrameworkStatus()

    assert_true(string.find(status, "GUI=yes", 1, true) ~= nil)
    assert_true(string.find(status, "Comm=yes", 1, true) ~= nil)
    assert_true(string.find(status, "Config=yes", 1, true) ~= nil)
  end)

end)
