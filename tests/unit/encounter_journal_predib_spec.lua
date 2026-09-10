local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("Encounter Journal Pre-Dibs", function()
  it("rejects direct requests from dungeon context", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({ dungeonInstanceID = 200 })

    local allowed, reason = dibs.EncounterJournal.CanPreDib(20001)
    local request, submitReason = dibs.EncounterJournal.SubmitPreDib(20001, "Item 20001")

    assert_false(allowed)
    assert_equal("EJ_NON_RAID_CONTEXT", reason)
    assert_nil(request)
    assert_equal("EJ_NON_RAID_CONTEXT", submitReason)
    assert_equal(0, #dibs.PreDibs.GetHistory())
  end)

  it("allows requests from raid context", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({ raidInstanceID = 100 })

    local allowed, reason = dibs.EncounterJournal.CanPreDib(20002)
    local request, submitReason = dibs.EncounterJournal.SubmitPreDib(20002, "Item 20002")

    assert_true(allowed)
    assert_nil(reason)
    assert_not_nil(request)
    assert_nil(submitReason)
    assert_equal("confirmed", request.status)
  end)

  it("finds a confirmed request again after Adventure Guide rows are rebuilt", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({ raidInstanceID = 100 })
    local request = dibs.EncounterJournal.SubmitPreDib(20003, "Item 20003")

    assert_not_nil(request)
    assert_not_nil(dibs.PreDibs.GetConfirmedRequestForPlayer("Tester-Realm", 20003))
  end)

  it("opens a catalog item at its Adventure Guide encounter", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    wow.installEncounterJournalContext({
      raidInstanceID = 100,
      raidInstances = { { id = 100, name = "Test Raid" } },
      encounters = { [100] = { { id = 500, name = "Test Boss" } } },
      loot = { [500] = { { itemID = 20008, name = "Test Curio", link = "item:20008" } } },
    })

    local catalog = dibs.EncounterJournal.GetLootCatalog("Test Curio", { refresh = true })
    assert_equal(1, #catalog)
    assert_equal(100, catalog[1].instanceID)
    assert_equal(500, catalog[1].encounterID)
    assert_true(dibs.EncounterJournal.OpenLootItem(catalog[1]))
    assert_equal(500, _G.__ejNavigation.encounterId)
    assert_true(dibs.EncounterJournal.OpenLootItem("item:20008"))
    assert_equal(500, _G.__ejNavigation.encounterId)
  end)

  it("resolves Requested state by normalized player and current season", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local firstSeason = dibs.GetCurrentSeasonId()
    dibs.PreDibs.CreatePublic("Tester", 20004, "Item 20004", firstSeason, "test")
    local secondSeason = dibs.Seasons.Create("Second season")

    assert_nil(dibs.PreDibs.GetConfirmedRequestForPlayer("Tester-Realm", 20004, secondSeason.id))
    assert_not_nil(dibs.PreDibs.GetConfirmedRequestForPlayer("Tester-Realm", 20004, firstSeason))
  end)

  it("does not treat a Normal request as Requested in the Mythic journal", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.PreDibs.CreatePublic("Tester-Realm", 20007, "Item 20007", seasonId, "test", { difficulty = "Normal" })

    assert_not_nil(dibs.PreDibs.GetConfirmedRequestForPlayer("Tester-Realm", 20007, seasonId, "Normal"))
    assert_nil(dibs.PreDibs.GetConfirmedRequestForPlayer("Tester-Realm", 20007, seasonId, "Mythic"))
  end)

  it("uses the Journal difficulty for Wild Open but live raid difficulty for Encounter", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, inRaid = true, instanceType = "raid", instanceId = 100 } })
    wow.installEncounterJournalContext({ raidInstanceID = 100 })
    _G.EJ_GetDifficulty = function() return 16 end
    _G.GetInstanceInfo = function() return "Raid", "raid", 14, "Normal", nil, nil, nil, 100 end

    local wild = dibs.EncounterJournal.SubmitPreDib(20005, "Item")
    dibs.PreDibs.SetModePolicy(dibs.GetCurrentSeasonId(), "ENCOUNTER")
    local encounter = dibs.EncounterJournal.SubmitPreDib(20006, "Item")

    assert_equal("Mythic", wild.difficulty)
    assert_equal("Normal", encounter.difficulty)
  end)
end)
