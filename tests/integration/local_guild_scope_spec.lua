local loader = require("helpers.load_addon")

describe("Local and guild persistence scopes", function()
  it("migrates personal settings out of the guild database", function()
    local saved = {
      schemaVersion = 6,
      guilds = {
        ["realm:testguild"] = {
          version = 7,
          settings = {
            language = "frFR",
            developerModeEnabled = true,
            debugLevels = { all = 4 },
            ejKnownSubCategories = { TIER = true },
          },
        },
      },
      persistenceRecovery = {},
    }
    local _, dibs = loader.load({ withAce3 = true, savedVariables = saved, wow = {
      playerName = "Tester-Realm", guildName = "TestGuild", guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 0 },
    } })

    local localSettings = dibs.GetLocalSettings()
    assert_equal("frFR", localSettings.language)
    assert_true(localSettings.developerModeEnabled)
    assert_equal(4, localSettings.debugLevels.all)
    assert_true(localSettings.ejKnownSubCategories.TIER)
    assert_nil(dibs.GetDB().settings.language)
    assert_nil(dibs.GetDB().settings.developerModeEnabled)
    assert_nil(dibs.GetDB().settings.debugLevels)
    assert_nil(dibs.GetDB().settings.ejKnownSubCategories)
  end)

  it("keeps local preferences outside guild-scoped state", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildName = "TestGuild", guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 0 },
    } })
    dibs.GetLocalSettings().language = "enUS"
    dibs.GetLocalSettings().debugLevels.all = 5
    dibs.GetDB().settings.allowPublicPreDibs = false

    assert_equal("enUS", dibs.GetLocalSettings().language)
    assert_equal(5, dibs.GetLocalSettings().debugLevels.all)
    assert_equal(false, dibs.GetDB().settings.allowPublicPreDibs)
    assert_nil(dibs.GetDB().settings.language)
    assert_nil(dibs.GetDB().settings.debugLevels)
  end)
end)
