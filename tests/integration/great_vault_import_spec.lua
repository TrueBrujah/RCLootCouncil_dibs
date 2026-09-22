local loader = require("helpers.load_addon")

describe("Great Vault import", function()
  it("deduplicates repeated full-data packages without replacing reviewed history", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true, guildName = "Import Guild" } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Owner-Realm", 283301, "Normal", {
      source = "VAULT_MANUAL", verificationState = "MANUAL_RECORDED", resetId = "week-import",
    })
    local packageText = assert(dibs.ImportExport.Export("full"))
    local reviewed = dibs.PreDibs.ReviewVaultAcquisition(record.acquisitionId, "REFERENCE_ONLY", "Tester-Realm", "Historical review")
    assert_not_nil(reviewed)

    local function applyPackage()
      local preview = assert(dibs.ImportExport.Preview(packageText, "full", "append"))
      return assert(dibs.ImportExport.Apply(preview.previewId, true, "Vault history import", "Tester-Realm"))
    end
    assert_equal("confirmed", applyPackage().decision)
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
    assert_equal("REFERENCE_ONLY", dibs.PreDibs.GetVaultAcquisition(record.acquisitionId).verificationState)
    assert_equal("Historical review", dibs.PreDibs.GetVaultAcquisition(record.acquisitionId).review.reason)
    assert_equal("confirmed", applyPackage().decision)
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
  end)

  it("rejects a full package from another guild before mutation", function()
    local _, source = loader.load({ withAce3 = true, wow = { guildLeader = true, guildName = "Source Guild" } })
    source.PreDibs.RecordVaultAcquisition("Owner-Realm", 283302, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", resetId = "week-cross-guild",
    })
    local packageText = assert(source.ImportExport.Export("full"))
    local savedRoot = _G.RCLootCouncil_dibsDB
    local _, target = loader.load({ withAce3 = true, savedVariables = savedRoot, wow = { guildLeader = true, guildName = "Target Guild" } })
    local before = #target.PreDibs.GetAcquisitions()
    local preview, reason = target.ImportExport.Preview(packageText, "full", "append", "Tester-Realm")
    assert_nil(preview)
    assert_equal("CROSS_GUILD_FULL_BLOCKED", reason)
    assert_equal(before, #target.PreDibs.GetAcquisitions())
  end)
end)
