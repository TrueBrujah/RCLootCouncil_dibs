local loader = require("helpers.load_addon")

describe("Great Vault sync contract", function()
  local function load()
    return loader.load({ withAce3 = true, wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Owner-Realm", "Officer-Realm" },
      guildRankIndices = { [1] = 0, [2] = 3, [3] = 1 },
    } })
  end

  local function remote(dibs, message, sender)
    local envelope = assert(dibs.Sync.BuildEnvelope(message))
    envelope.senderNameRealm = sender
    envelope.senderMemberKey = string.lower(sender)
    return envelope
  end

  it("builds bounded digest, fetch, detail, and acknowledgement messages", function()
    local _, dibs = load()
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 282001, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      family = "TOKEN", resetId = "week-1", evidenceId = "claim:282001",
    })
    local digest = dibs.Sync.BuildVaultDigest()
    local fetch = dibs.Sync.BuildVaultFetch({ { acquisitionId = record.acquisitionId, revision = 1, contentHash = digest.entries[1].contentHash } })
    local detail = dibs.Sync.BuildVaultDetail(record)
    local ack = dibs.Sync.BuildVaultAck(record.acquisitionId, 1, "APPLIED")

    assert_equal("VAULT_DIGEST", digest.type)
    assert_equal("VAULT_FETCH", fetch.type)
    assert_equal("VAULT_DETAIL", detail.type)
    assert_equal("VAULT_ACK", ack.type)
    assert_nil(detail.payload.evidence)
    assert_nil(detail.payload.originalEvidence)
  end)

  it("applies same-guild detail idempotently and rejects stale or conflicting revisions", function()
    local _, dibs = load()
    local incoming = {
      acquisitionId = "vault-sync-1", guildKey = dibs.GetGuildKey(), playerName = "Owner-Realm",
      characterId = "Player-2-OWNER", itemID = 282002, difficulty = "Normal", seasonId = dibs.GetCurrentSeasonId(),
      resetId = "week-1", family = "TOKEN", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      source = "GREAT_VAULT", evidenceId = "claim:282002", revision = 2, syncState = "LOCAL",
    }
    local detail = dibs.Sync.BuildVaultDetail(incoming)
    local accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Owner-Realm"), "Owner-Realm")
    assert_true(accepted, reason)
    assert_equal("APPLIED", reason)
    accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Owner-Realm"), "Owner-Realm")
    assert_true(accepted, reason)
    assert_equal("IDEMPOTENT_REPLAY", reason)

    local stale = dibs.Sync.BuildVaultDetail(incoming)
    stale.revision = 1
    stale.payload.revision = 1
    stale.contentHash = dibs.Sync.BuildVaultDetail(stale.payload).contentHash
    accepted, reason = dibs.Sync.Receive(remote(dibs, stale, "Owner-Realm"), "Owner-Realm")
    assert_false(accepted)
    assert_equal("STALE_REVISION", reason)
  end)

  it("rejects cross-guild and private evidence payloads without mutation", function()
    local _, dibs = load()
    local detail = {
      type = "VAULT_DETAIL", acquisitionId = "vault-private", revision = 1,
      contentHash = "not-used", payload = {
        acquisitionId = "vault-private", playerName = "Owner-Realm", itemID = 282003,
        seasonId = dibs.GetCurrentSeasonId(), verificationState = "AUTOMATIC_CONFIRMED",
        evidence = { private = true }, revision = 1,
      },
    }
    local wrongGuild = remote(dibs, detail, "Owner-Realm")
    wrongGuild.guildKey = "other-guild"
    assert_false(dibs.Sync.Receive(wrongGuild, "Owner-Realm"))
    local before = #dibs.PreDibs.GetAcquisitions()
    local accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Owner-Realm"), "Owner-Realm")
    assert_false(accepted)
    assert_equal("FORBIDDEN_PRIVATE_EVIDENCE", reason)
    assert_equal(before, #dibs.PreDibs.GetAcquisitions())
  end)

  it("transfers Vault detail through the bounded chunk machinery", function()
    local _, dibs = load()
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 282004, "Normal", {
      source = "GREAT_VAULT", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      family = "TOKEN", resetId = "week-chunk", evidenceId = "claim:282004",
    })
    local sent, originalSend = {}, dibs.Sync.Send
    dibs.Sync.Send = function(message)
      sent[#sent + 1] = message
      return true, "captured"
    end
    local ok, reason = dibs.Sync.SendDetail("VAULT_DETAIL", record.acquisitionId, record.revision,
      dibs.Sync.BuildVaultDetail(record).contentHash, record, "Officer-Realm")
    dibs.Sync.Send = originalSend
    assert_true(ok, reason)
    assert_true(#sent >= 3)

    dibs.GetDB().preDibs.acquisitions = {}
    for _, message in ipairs(sent) do
      local accepted, receiveReason = dibs.Sync.Receive(remote(dibs, message, "Tester-Realm"), "Tester-Realm")
      assert_true(accepted, receiveReason)
    end
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
    assert_equal(record.acquisitionId, dibs.PreDibs.GetAcquisitions()[1].acquisitionId)
  end)
end)
