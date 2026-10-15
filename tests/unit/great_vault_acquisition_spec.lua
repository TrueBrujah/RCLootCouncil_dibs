local loader = require("helpers.load_addon")
local fixture = require("helpers.great_vault_fixture")

describe("Great Vault acquisition", function()
  local previousTooltip, previousSecret, previousRaidFinder
  before_each(function()
    previousTooltip, previousSecret = _G.C_TooltipInfo, _G.issecretvalue
    previousRaidFinder = _G.ITEM_RAID_FINDER
    _G.C_TooltipInfo = nil
  end)
  after_each(function()
    _G.C_TooltipInfo, _G.issecretvalue = previousTooltip, previousSecret
    _G.ITEM_RAID_FINDER = previousRaidFinder
  end)

  it("preserves the exact manually supplied reward hyperlink through the slash command", function()
    local _, dibs = loader.load()
    local link = "|cnIQ4:|Hitem:159459::::::::90:577::35:3:123:456:789::::::|h[Ritual Binder's Ring]|h|r"
    dibs.HandleSlashCommand("vault " .. link .. " Mythic")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal(159459, records[1].itemID)
    assert_equal(link, records[1].itemLink)
    assert_equal("Mythic", records[1].difficulty)
    assert_equal("MANUAL_RECORDED", records[1].verificationState)
  end)
  it("records manual evidence with an explicit verification state and guild scope", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local ledgerCount = #dibs.Ledger.GetAllTransactions()

    local record, reason = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic")

    assert_nil(reason)
    assert_not_nil(record)
    assert_equal("VAULT_MANUAL", record.source)
    assert_equal("MANUAL_RECORDED", record.verificationState)
    assert_equal("MISSING", record.evidenceState)
    assert_equal(dibs.GetGuildKey(), record.guildKey)
    assert_equal("Player-1-TESTER", record.characterId)
    assert_equal(ledgerCount, #dibs.Ledger.GetAllTransactions())
  end)

  it("accepts an uncolored full item link and preserves numeric command compatibility", function()
    local _, dibs = loader.load()
    local link = "|Hitem:159459::::::::90:577::35:1:123::::::|h[Ritual Binder's Ring]|h"
    dibs.HandleSlashCommand("vault " .. link .. " hero")
    dibs.HandleSlashCommand("vault 21016 Heroic")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(2, #records)
    assert_equal(link, records[1].itemLink)
    assert_equal("Heroic", records[1].difficulty)
    assert_equal(21016, records[2].itemID)
    assert_equal("Heroic", records[2].difficulty)
    assert_nil(records[2].itemLink)
  end)

  it("refuses a missing or unknown difficulty and shows the usage instead of recording", function()
    local _, dibs = loader.load()
    local link = "|Hitem:159459::::::::90:577::35:1:123::::::|h[Ritual Binder's Ring]|h"
    _G.__dibsMessages = {}
    dibs.HandleSlashCommand("vault " .. link)
    dibs.HandleSlashCommand("vault 21016")
    dibs.HandleSlashCommand("vault 21016 Adventurer")
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    local usage = 0
    for _, message in ipairs(_G.__dibsMessages) do
      if message:find("/dibs vault <item link | [Item Name] | itemID> <LFR | Normal | Heroic | Mythic>", 1, true) then usage = usage + 1 end
    end
    assert_equal(3, usage)
  end)

  it("records LFR aliases manually and preserves them across reload without spending Dibs", function()
    local _, dibs = loader.load()
    local before = #dibs.Ledger.GetAllTransactions()
    for _, value in ipairs({ "LFR", "lfr", "Raid Finder", "Looking For Raid", "LOOKING_FOR_RAID", "Outil Raids", 17, "17" }) do
      assert_equal("LFR", dibs.PreDibs.NormalizeDifficulty(value))
    end
    dibs.HandleSlashCommand("vault 21016 LFR")
    dibs.HandleSlashCommand("vault 21017 Raid Finder")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(2, #records)
    for _, record in ipairs(records) do
      assert_equal("LFR", record.difficulty)
      assert_equal("MANUAL_RECORDED", record.verificationState)
    end
    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    local _, reloaded = loader.load({ savedVariables = saved })
    assert_equal(2, #reloaded.PreDibs.GetAcquisitions())
    assert_equal("LFR", reloaded.PreDibs.GetAcquisitions()[1].difficulty)
    reloaded.HandleSlashCommand("vault 21016 LFR")
    assert_equal(2, #reloaded.PreDibs.GetAcquisitions())
    assert_equal(before, #reloaded.Ledger.GetAllTransactions())
  end)

  it("keeps Heroic origin despite a Myth upgrade track and a different link context", function()
    local _, dibs = loader.load()
    _G.C_TooltipInfo = { GetHyperlink = function(link)
      return { lines = {
        { leftText = "Vault Ring" }, { leftText = "|cffa335eeHeroic|r" },
        { leftText = "Upgrade Level: Myth 2/6" },
      } }
    end }
    C_Item.GetItemUpgradeInfo = function() return { trackString = "Myth", currentLevel = 2, maxLevel = 6 } end
    _G.__dibsMessages = {}
    dibs.HandleSlashCommand("vault |cffa335ee|Hitem:21019::::::::90:577::5:1:123|h[Context Ring]|h|r")
    dibs.HandleSlashCommand("vault |cffa335ee|Hitem:21020::::::::90:577::6:1:123|h[Tooltip Ring]|h|r")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(2, #records)
    assert_equal("Heroic", records[1].difficulty)
    assert_nil(records[1].upgradeTrack)
    assert_equal("Heroic", records[2].difficulty)
    assert_nil(records[2].upgradeTrack)
    local detected = 0
    for _, message in ipairs(_G.__dibsMessages) do
      if message:find("Difficulty detected from the item", 1, true) then detected = detected + 1 end
    end
    assert_equal(2, detected)
  end)

  it("records link-only LFR evidence from a localized client label without copying the track", function()
    local _, dibs = loader.load()
    _G.ITEM_RAID_FINDER = "Synthetic Raid Finder"
    C_Item.GetItemUpgradeInfo = function() return { trackString = "Veteran" } end
    _G.C_TooltipInfo = { GetHyperlink = function()
      return { lines = { { leftText = "Vault Ring" }, { leftText = ITEM_RAID_FINDER } } }
    end }
    dibs.HandleSlashCommand("vault |Hitem:21016::::::::::::|h[Vault Ring]|h")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal("LFR", records[1].difficulty)
    assert_equal("MANUAL_RECORDED", records[1].verificationState)
    assert_nil(records[1].upgradeTrack)
  end)

  it("reads exact English and French difficulty labels from the exact item variant", function()
    local _, dibs = loader.load()
    local link = "|Hitem:268263::::::::90:577::5:1:123|h[Frond]|h"
    for _, case in ipairs({
      { "Raid Finder", "Upgrade Level: Veteran 1/6", "LFR" },
      { "Looking For Raid", "Upgrade Level: Veteran 6/6", "LFR" },
      { "Outil Raids", "Niveau d'amélioration : Vétéran 3/6", "LFR" },
      { "Normal", "Upgrade Level: Champion 4/6", "Normal" },
      { "Heroic", "Upgrade Level: Hero 2/6", "Heroic" },
      { "Mythic", "Upgrade Level: Myth 1/6", "Mythic" },
      { "Héroïque", "Niveau d'amélioration : Mythe 5/6", "Heroic" },
      { "Mythique", "Niveau d'amélioration : Mythe 6/6", "Mythic" },
    }) do
      _G.C_TooltipInfo = { GetHyperlink = function(input)
        assert_equal(link, input)
        return { lines = { { leftText = "Frond" }, { leftText = case[1] }, { leftText = case[2] } } }
      end }
      local difficulty, source = dibs.GreatVault.ResolveItemDifficulty(link)
      assert_equal(case[3], difficulty)
      assert_equal("RAID_ORIGIN", source)
    end
  end)

  it("classifies dungeon rewards by upgrade track, including Heroic Veteran and Mythic 0 Champion", function()
    local _, dibs = loader.load()
    local link = "|Hitem:268263::::::::90:577::5:1:123|h[Emblem]|h"
    for _, case in ipairs({
      { "Mythic+", "Myth 6/6", "Mythic" },
      { "Mythic+", "Hero 6/6", "Heroic" },
      { "Mythic+", "Champion 2/6", "Normal" },
      { "Mythic", "Champion 6/6", "Normal" },
      { "Mythique+", "Héros 3/6", "Heroic" },
      { "Heroic", "Veteran 1/6", "Heroic" },
      { "Heroic", "Veteran 6/6", "Heroic" },
      { "Héroïque", "Vétéran 3/6", "Heroic" },
      { "Mythic+", "Veteran 4/6", "LFR" },
    }) do
      _G.C_TooltipInfo = { GetHyperlink = function()
        return { lines = { { leftText = "Emblem" }, { leftText = case[1] }, { leftText = "Upgrade Level: " .. case[2] } } }
      end }
      local difficulty, source = dibs.GreatVault.ResolveItemDifficulty(link)
      assert_equal(case[3], difficulty)
      assert_equal("DUNGEON_TRACK", source)
    end
    for _, case in ipairs({
      { "Mythic+", "Adventurer 6/6" }, { "Heroic", "Adventurer 4/8" }, { "Mythic", "Hero 2/6" },
      { "Heroic", "Champion 3/6" }, { "Normal", "Myth 1/6" }, { "Mythic+", nil },
      { "Raid Finder", nil }, { "Raid Finder", "Adventurer 1/6" }, { "Normal", "Veteran 1/6" },
    }) do
      _G.C_TooltipInfo = { GetHyperlink = function()
        local lines = { { leftText = "Emblem" }, { leftText = case[1] } }
        if case[2] then lines[3] = { leftText = "Upgrade Level: " .. case[2] } end
        return { lines = lines }
      end }
      assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    end
  end)

  it("fails closed for missing, unknown, conflicting, or secret tooltip data", function()
    local _, dibs = loader.load()
    local link = "|Hitem:268263::::::::90:577::6:1:123|h[Frond]|h"
    C_Item.GetItemUpgradeInfo = function() return { trackString = "Myth" } end
    assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    _G.C_TooltipInfo = { GetHyperlink = function() return nil end }
    assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    for _, lines in ipairs({
      { { leftText = "Heroic" }, { leftText = "Upgrade Level: Myth 2/6" } },
      { { leftText = "Frond" }, { leftText = "Hero" }, { leftText = "Myth" } },
      { { leftText = "Frond" }, { leftText = "Looking for Raid" } },
      { { leftText = "Frond" }, { leftText = "Heroic" }, { leftText = "Mythic" } },
    }) do
      _G.C_TooltipInfo.GetHyperlink = function() return { lines = lines } end
      assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    end
    local secretText = setmetatable({}, { __tostring = function() error("secret must not be read") end })
    _G.issecretvalue = function(value) return value == secretText end
    _G.C_TooltipInfo.GetHyperlink = function()
      return { lines = { { leftText = "Frond" }, { leftText = secretText } } }
    end
    assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    _G.C_TooltipInfo.GetHyperlink = function() return secretText end
    assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    _G.C_TooltipInfo.GetHyperlink = function() error("synthetic tooltip API failure") end
    _G.__dibsMessages = {}
    assert_nil(dibs.GreatVault.ResolveItemDifficulty(link))
    assert_true(_G.__dibsMessages[1]:find(dibs.L.VAULT_REASON_TOOLTIP_UNAVAILABLE, 1, true) ~= nil)
    dibs.HandleSlashCommand("vault " .. link)
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("keeps explicit manual classifications and does not replace old evidence", function()
    local _, dibs = loader.load()
    local link = "|Hitem:268263::::::::90:577::5:1:123|h[Frond]|h"
    _G.C_TooltipInfo = { GetHyperlink = function()
      return { lines = { { leftText = "Frond" }, { leftText = "Mythic" }, { leftText = "Upgrade Level: Myth 1/6" } } }
    end }
    dibs.HandleSlashCommand("vault " .. link .. " Heroic")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal("Heroic", records[1].difficulty)
    assert_nil(records[1].upgradeTrack)
    dibs.HandleSlashCommand("vault " .. link)
    assert_equal(2, #records)
    assert_equal("Heroic", records[1].difficulty)
    assert_equal("Mythic", records[2].difficulty)
    assert_nil(records[2].upgradeTrack)
    dibs.HandleSlashCommand("vault " .. link)
    assert_equal(2, #records)
  end)

  it("keeps original difficulty separate from supplied upgrade-track evidence", function()
    local _, dibs = loader.load()
    _G.C_TooltipInfo = { GetHyperlink = function()
      return { lines = { { leftText = "Vault Ring" }, { leftText = "Heroic" }, { leftText = "Upgrade Level: Myth 3/6" } } }
    end }
    local result = dibs.GreatVault.RecordClaim(fixture.observation({
      itemLink = "|Hitem:21016::::::::::::|h[Vault Ring]|h",
      difficulty = "Mythic",
      upgradeTrack = "Mythic",
    }))
    assert_equal("CONFIRMED", result.status)
    assert_equal("Heroic", result.acquisition.difficulty)
    assert_equal("Mythic", result.acquisition.upgradeTrack)
  end)

  it("detects the French original difficulty without interpreting the upgrade line", function()
    local _, dibs = loader.load({ wow = { locale = "frFR" } })
    _G.C_TooltipInfo = { GetHyperlink = function()
      return { lines = {
        { leftText = "Objet" }, { leftText = "Héroïque" }, { leftText = "Niveau d'amélioration : Mythe 2/6" },
      } }
    end }
    _G.__dibsMessages = {}
    dibs.HandleSlashCommand("vault |Hitem:268263::::::::90:577::35:1:123|h[Objet]|h")
    local record = dibs.PreDibs.GetAcquisitions()[1]
    assert_equal("Heroic", record.difficulty)
    assert_nil(record.upgradeTrack)
    local explained = false
    local expected = string.format(dibs.L.VAULT_COMMAND_DIFFICULTY_DETECTED, "Heroic")
    for _, message in ipairs(_G.__dibsMessages) do
      if message:find(expected, 1, true) then explained = true end
    end
    assert_true(explained)
  end)

  it("accepts difficulty aliases and resolves a typed [Item Name]", function()
    local _, dibs = loader.load()
    local frondLink = "|cnIQ4:|Hitem:242400::::::::90:577::6:1:123::::::|h[Frostscale's Mystic Frond]|h|r"
    local getInfo = _G.C_Item.GetItemInfo
    _G.C_Item.GetItemInfo = function(input)
      if input == "Frostscale's Mystic Frond" then return "Frostscale's Mystic Frond", frondLink end
      return getInfo(input)
    end
    dibs.HandleSlashCommand("vault [Frostscale's Mystic Frond] Myth")
    dibs.HandleSlashCommand("vault 21017 normal")
    dibs.HandleSlashCommand("vault 21018 Mythique")
    _G.__dibsMessages = {}
    dibs.HandleSlashCommand("vault [Not A Real Item] Heroic")
    _G.C_Item.GetItemInfo = getInfo
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(3, #records)
    assert_equal(242400, records[1].itemID)
    assert_equal("Frostscale's Mystic Frond", records[1].itemName)
    assert_equal("Mythic", records[1].difficulty)
    assert_equal("Normal", records[2].difficulty)
    assert_equal("Mythic", records[3].difficulty)
    assert_true(_G.__dibsMessages[1]:find("Not A Real Item", 1, true) ~= nil)
  end)

  it("preserves legacy-colored links with spaces in their item names", function()
    local _, dibs = loader.load()
    local link = "|cffa335ee|Hitem:159459::::::::90:577::35:1:123::::::|h[Ritual Binder's Ring]|h|r"
    dibs.HandleSlashCommand("vault " .. link .. " Heroic")
    local record = dibs.PreDibs.GetAcquisitions()[1]
    assert_equal(link, record.itemLink)
    assert_equal("Ritual Binder's Ring", record.itemName)
    assert_equal("Heroic", record.difficulty)
  end)

  it("ignores a forged local guild scope", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildName = "Home Guild" } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21017, "Normal", {
      guildKey = "other-realm:other-guild",
    })
    assert_equal(dibs.GetGuildKey(), record.guildKey)
  end)

  it("deduplicates the same manual identity but separates weekly resets", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })

    local first = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic", { resetId = "reset-one" })
    local replay = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic", { resetId = "reset-one" })
    local nextReset = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic", { resetId = "reset-two" })

    assert_equal(first.acquisitionId, replay.acquisitionId)
    assert_true(nextReset.acquisitionId ~= first.acquisitionId)
    assert_equal(2, #dibs.PreDibs.GetAcquisitions())
  end)

  it("keeps a complete automatic claim outside the ledger", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local ledgerCount = #dibs.Ledger.GetAllTransactions()
    local record, reason = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic", {
      resetId = "reset-test",
      claimId = "claim-test-1",
      claimedAt = 1700000000,
      source = "GREAT_VAULT",
      verificationState = "AUTOMATIC_CONFIRMED",
      evidenceState = "COMPLETE",
      evidenceId = "claim-test-1",
      evidence = fixture.observation(),
    })

    assert_nil(reason)
    assert_equal("AUTOMATIC_CONFIRMED", record.verificationState)
    assert_equal("COMPLETE", record.evidenceState)
    assert_equal(ledgerCount, #dibs.Ledger.GetAllTransactions())
  end)
end)
