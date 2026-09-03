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
      "modules/Sync.lua",
      "modules/RaidRelay.lua",
      "integrations/EncounterJournal.lua",
      "integrations/RCLootCouncil.lua",
      "ui/PlayerUI.lua",
      "ui/OfficerUI.lua",
    }

    for _, relative in ipairs(required) do
      local chunk, err = loadfile("src/" .. relative)
      assert_not_nil(chunk, "unloadable source: src/" .. relative .. " :: " .. tostring(err))
    end
  end)
end)
