local loader = require("helpers.load_addon")

describe("Great Vault sync privacy", function()
  local function load()
    return loader.load({ withAce3 = true, wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Owner-Realm", "Other-Realm" },
      guildRankIndices = { [1] = 0, [2] = 3, [3] = 3 },
    } })
  end

  local function remote(dibs, message, sender)
    local envelope = assert(dibs.Sync.BuildEnvelope(message))
    envelope.senderNameRealm = sender
    envelope.senderMemberKey = string.lower(sender)
    return envelope
  end

  it("rejects an unauthorized sender without mutating the acquisition store", function()
    local _, dibs = load()
    local record = dibs.PreDibs.RecordVaultAcquisition("Owner-Realm", 283001, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      resetId = "week-privacy", evidenceId = "claim:283001",
    })
    local detail = dibs.Sync.BuildVaultDetail(record)
    local before = #dibs.PreDibs.GetAcquisitions()
    local accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Other-Realm"), "Other-Realm")
    assert_false(accepted)
    assert_equal("VAULT_AUTHORITY_REQUIRED", reason)
    assert_equal(before, #dibs.PreDibs.GetAcquisitions())
  end)

  it("rejects live-loot fields before Vault validation or mutation", function()
    local _, dibs = load()
    local detail = {
      type = "VAULT_DETAIL", acquisitionId = "vault-live-loot", revision = 1,
      contentHash = "not-used", payload = {
        acquisitionId = "vault-live-loot", playerName = "Owner-Realm", itemID = 283002,
        verificationState = "AUTOMATIC_CONFIRMED", revision = 1, candidates = { "Player-Realm" },
      },
    }
    local accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Owner-Realm"), "Owner-Realm")
    assert_false(accepted)
    assert_equal("FORBIDDEN_LIVE_LOOT_DATA", reason)
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("keeps manual recording available when the sync transport is unavailable", function()
    local _, dibs = loader.load({ withAce3 = false, wow = { guildLeader = true } })
    local record, reason = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 283003, "Normal")
    assert_not_nil(record)
    assert_nil(reason)
    local sent, sendReason = dibs.Sync.Send({ type = "VAULT_ACK", acquisitionId = record.acquisitionId, revision = 1, result = "APPLIED" }, "GUILD")
    assert_false(sent)
    assert_equal("SYNC_UNAVAILABLE", sendReason)
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
  end)
end)
