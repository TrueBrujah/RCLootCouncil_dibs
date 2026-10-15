local loader = require("helpers.load_addon")
local fixture = require("helpers.great_vault_fixture")

describe("Great Vault acquisition", function()
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
    dibs.HandleSlashCommand("vault " .. link)
    dibs.HandleSlashCommand("vault 21016 Heroic")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(2, #records)
    assert_equal(link, records[1].itemLink)
    assert_equal("UNKNOWN", records[1].difficulty)
    assert_equal(21016, records[2].itemID)
    assert_equal("Heroic", records[2].difficulty)
    assert_nil(records[2].itemLink)
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
