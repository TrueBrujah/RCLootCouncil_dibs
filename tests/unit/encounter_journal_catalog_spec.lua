local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("Encounter Journal loot catalogue", function()
  it("indexes raid loot and supports name, ID, boss, and type searches", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({
      raidInstances = {
        { id = 900, name = "Citadel of Testing" },
      },
      encounters = {
        [900] = {
          { id = 901, name = "Test Warden" },
          { id = 902, name = "Archive Keeper" },
        },
      },
      loot = {
        [901] = {
          { itemID = 280001, name = "Warden's Curio", link = "|Hitem:280001::::::::::::|h[Warden's Curio]|h|r" },
        },
        [902] = {
          { itemID = 280002, name = "Archive Token", link = "|Hitem:280002::::::::::::|h[Archive Token]|h|r" },
        },
      },
    })

    local all, meta = dibs.EncounterJournal.GetLootCatalog("", { refresh = true, limit = 20 })
    assert_true(meta.available)
    assert_equal(2, #all)
    assert_equal("Citadel of Testing", all[1].instanceName)

    local byBoss = dibs.EncounterJournal.GetLootCatalog("warden")
    assert_equal(1, #byBoss)
    assert_equal(280001, byBoss[1].itemID)

    local byID = dibs.EncounterJournal.GetLootCatalog("280002")
    assert_equal(1, #byID)
    assert_equal("Archive Token", byID[1].itemName)

    local byType = dibs.EncounterJournal.GetLootCatalog(all[1].type)
    assert_true(#byType >= 1)
  end)
end)
