local loader = require("helpers.load_addon")

describe("Great Vault sync isolation", function()
  it("rejects a cross-scope direct apply without mutation", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      guildLeader = true, guildName = "Guild-A", guildMembers = { "Tester-Realm", "Owner-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    local applied, reason = dibs.PreDibs.ApplyVaultSyncRecord({
      acquisitionId = "vault-cross-scope", guildKey = "other-realm:Guild-B", playerName = "Owner-Realm", itemID = 283101,
      revision = 1, verificationState = "AUTOMATIC_CONFIRMED", source = "GREAT_VAULT",
    })
    assert_nil(applied)
    assert_equal("GUILD_SCOPE_MISMATCH", reason)
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("routes immutable identity changes to Officer review instead of last-write-wins", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      guildLeader = true, guildMembers = { "Tester-Realm", "Owner-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Owner-Realm", 283102, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE", resetId = "week-identity",
    })
    local applied, reason = dibs.PreDibs.ApplyVaultSyncRecord({
      acquisitionId = record.acquisitionId, guildKey = dibs.GetGuildKey(), playerName = "Owner-Realm", itemID = 283103,
      revision = 2, verificationState = "AUTOMATIC_CONFIRMED", source = "GREAT_VAULT", resetId = "week-identity",
    })
    assert_nil(applied)
    assert_equal("CONFLICT_REVIEW_REQUIRED", reason)
    assert_equal(283102, dibs.PreDibs.GetVaultAcquisition(record.acquisitionId).itemID)
    assert_equal(1, #dibs.PreDibs.GetVaultConflicts())
  end)

  it("keeps guild-scoped history hidden after a guild change", function()
    local _, dibsA = loader.load({ withAce3 = true, wow = {
      guildLeader = true, guildName = "Guild-A", guildMembers = { "Tester-Realm", "Owner-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    dibsA.PreDibs.RecordVaultAcquisition("Owner-Realm", 283104, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", resetId = "week-guild-a",
    })
    local savedRoot = _G.RCLootCouncil_dibsDB
    local _, dibsB = loader.load({ withAce3 = true, wow = {
      guildLeader = true, guildName = "Guild-B", guildMembers = { "Tester-Realm", "Owner-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    _G.RCLootCouncil_dibsDB = savedRoot
    assert_equal(0, #dibsB.PreDibs.GetAcquisitions())
  end)

  it("keeps the old guild record when the same character changes guilds", function()
    local _, dibsA = loader.load({ withAce3 = true, wow = {
      guildLeader = true, guildName = "Guild-A", guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 0 },
    } })
    local record = dibsA.PreDibs.RecordVaultAcquisition("Tester-Realm", 283108, "Normal", { resetId = "week-change" })
    local savedRoot = _G.RCLootCouncil_dibsDB
    local guildKeyA = dibsA.currentGuildKey
    local _, dibsB = loader.load({ withAce3 = true, savedVariables = savedRoot, wow = {
      guildLeader = true, guildName = "Guild-B", guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 0 },
    } })
    assert_equal(0, #dibsB.PreDibs.GetAcquisitions())
    assert_equal(record.acquisitionId, savedRoot.guilds[guildKeyA].preDibs.acquisitions[1].acquisitionId)
  end)

  it("keeps unguilded character history isolated", function()
    local _, dibsA = loader.load({ withAce3 = true, wow = { inGuild = false, playerName = "AltOne-Realm" } })
    dibsA.PreDibs.RecordVaultAcquisition("AltOne-Realm", 283105, "Normal", {
      source = "VAULT_MANUAL", verificationState = "MANUAL_RECORDED", resetId = "week-alt-one",
    })
    local savedRoot = _G.RCLootCouncil_dibsDB
    local _, dibsB = loader.load({ withAce3 = true, wow = { inGuild = false, playerName = "AltTwo-Realm" } })
    _G.RCLootCouncil_dibsDB = savedRoot
    assert_equal(0, #dibsB.PreDibs.GetAcquisitions())
  end)

  it("keeps an unguilded migrated record owned by its recorded character", function()
    local legacy = {
      version = 6,
      preDibs = { requests = {}, modePolicies = {}, acquisitions = {
        { acquisitionId = "unguilded-legacy", playerName = "AltOne-Realm", itemID = 283109, source = "VAULT" },
      } },
    }
    local _, dibs = loader.load({ savedVariables = legacy, wow = { inGuild = false, playerName = "AltTwo-Realm" } })
    local record = dibs.PreDibs.GetVaultAcquisition("unguilded-legacy")
    assert_nil(record)
    local savedRoot = _G.RCLootCouncil_dibsDB
    local _, altOne = loader.load({ savedVariables = savedRoot, wow = { inGuild = false, playerName = "AltOne-Realm" } })
    record = altOne.PreDibs.GetVaultAcquisition("unguilded-legacy")
    assert_equal(altOne.GetCharacterScopeKey("AltOne-Realm"), record.guildKey)
    assert_equal(1, #altOne.PreDibs.GetAcquisitions())
  end)

  it("requires an Officer decision before accepting a conflicting identity", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      guildLeader = true, guildMembers = { "Tester-Realm", "Owner-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    local record = dibs.PreDibs.RecordVaultAcquisition("Owner-Realm", 283106, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE", resetId = "week-review",
    })
    local _, reason = dibs.PreDibs.ApplyVaultSyncRecord({
      acquisitionId = record.acquisitionId, guildKey = dibs.GetGuildKey(), playerName = "Owner-Realm", itemID = 283107,
      revision = 9, verificationState = "AUTOMATIC_CONFIRMED", source = "GREAT_VAULT", resetId = "week-review",
    })
    assert_equal("CONFLICT_REVIEW_REQUIRED", reason)
    local conflict = dibs.PreDibs.GetVaultConflicts()[1]
    local resolved, resolveReason = dibs.PreDibs.ResolveVaultConflict(conflict.conflictId, "ACCEPT_INCOMING", "Tester-Realm", "Verified corrected item")
    assert_nil(resolveReason)
    assert_equal("RESOLVED", resolved.status)
    assert_equal(283107, dibs.PreDibs.GetVaultAcquisition(record.acquisitionId).itemID)
    local replay, replayReason = dibs.PreDibs.ResolveVaultConflict(conflict.conflictId, "KEEP_CURRENT", "Tester-Realm", "Repeat review")
    assert_equal("IDEMPOTENT_REPLAY", replayReason)
    assert_equal("RESOLVED", replay.status)
  end)
end)