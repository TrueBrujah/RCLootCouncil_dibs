local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("Blizzard Encounter Journal encounter tuple", function()
  it("uses name, description and encounter ID in catalogue and debug scans", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({
      raidInstanceID = 900,
      raidInstances = { { id = 900, name = "Tuple Citadel" } },
      encounters = { [900] = { { id = 901, name = "Tuple Warden", description = "Not an identifier" } } },
      loot = { [901] = { { itemID = 280011, name = "Tuple Trophy", link = "|Hitem:280011::::::::::::|h[Tuple Trophy]|h|r" } } },
    })
    local encounterName, description, encounterID = EJ_GetEncounterInfoByIndex(1, 900)
    assert_equal("Tuple Warden", encounterName)
    assert_equal("Not an identifier", description)
    assert_equal(901, encounterID)
    local catalog, metadata = dibs.EncounterJournal.GetLootCatalog("", { refresh = true })
    assert_true(metadata.available)
    assert_equal(1, #catalog)
    assert_equal("Tuple Warden", catalog[1].bossName)
    assert_equal(901, catalog[1].encounterID)
    assert_equal(1, dibs.EncounterJournal.DumpVisibleLootDebug())
  end)

  it("keeps the encounter ID from the Blizzard tuple when the encounter has no loot", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({
      raidInstanceID = 900,
      raidInstances = { { id = 900, name = "Empty Citadel" } },
      encounters = { [900] = { { id = 902, name = "Empty Warden", description = "No drops" } } },
      loot = {},
    })

    local encounterName, description, encounterID = EJ_GetEncounterInfoByIndex(1, 900)
    assert_equal("Empty Warden", encounterName)
    assert_equal("No drops", description)
    assert_equal(902, encounterID)

    local catalog, metadata = dibs.EncounterJournal.GetLootCatalog("", { refresh = true })
    assert_false(metadata.available)
    assert_equal("NO_RAID_LOOT_FOUND", metadata.reason)
    assert_equal(1, metadata.scannedEncounters)
    assert_equal(0, #catalog)
    assert_equal(0, dibs.EncounterJournal.DumpVisibleLootDebug())
  end)
end)
