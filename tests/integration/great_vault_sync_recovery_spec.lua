local loader = require("helpers.load_addon")

describe("Great Vault sync recovery", function()
  local function load()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Owner-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    return dibs
  end

  local function remote(dibs, message, sender)
    local envelope = assert(dibs.Sync.BuildEnvelope(message))
    envelope.senderNameRealm = sender
    envelope.senderMemberKey = string.lower(sender)
    return envelope
  end

  it("requests missing detail and clears sync-behind only after verified application", function()
    local dibs = load()
    local record = {
      acquisitionId = "vault-recovery-1", guildKey = dibs.GetGuildKey(), playerName = "Owner-Realm",
      characterId = "Player-2-OWNER", itemID = 283001, difficulty = "Normal", seasonId = dibs.GetCurrentSeasonId(),
      resetId = "week-1", family = "TOKEN", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      source = "GREAT_VAULT", evidenceId = "claim:283001", revision = 2, syncState = "LOCAL",
    }
    local detail = dibs.Sync.BuildVaultDetail(record)
    local digest = remote(dibs, {
      type = "VAULT_DIGEST", entityType = "VAULT_ACQUISITION", entityId = "current", revision = 1,
      entries = { { acquisitionId = record.acquisitionId, revision = 2, contentHash = detail.contentHash } },
    }, "Owner-Realm")
    local accepted, reason = dibs.Sync.Receive(digest, "Owner-Realm")
    assert_true(accepted, reason)
    assert_equal("VAULT_DETAIL_REQUESTED", reason)
    assert_true(dibs.Sync.IsSyncBehind())
    accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Owner-Realm"), "Owner-Realm")
    assert_true(accepted, reason)
    assert_equal("APPLIED", reason)
    assert_false(dibs.Sync.IsSyncBehind())
  end)

  it("accepts detail before digest and treats the later digest as current", function()
    local dibs = load()
    local record = {
      acquisitionId = "vault-recovery-2", guildKey = dibs.GetGuildKey(), playerName = "Owner-Realm",
      characterId = "Player-2-OWNER", itemID = 283002, difficulty = "Normal", seasonId = dibs.GetCurrentSeasonId(),
      resetId = "week-1", family = "TOKEN", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      source = "GREAT_VAULT", evidenceId = "claim:283002", revision = 1, syncState = "LOCAL",
    }
    local detail = dibs.Sync.BuildVaultDetail(record)
    local accepted, reason = dibs.Sync.Receive(remote(dibs, detail, "Owner-Realm"), "Owner-Realm")
    assert_true(accepted, reason)
    local digest = remote(dibs, {
      type = "VAULT_DIGEST", entityType = "VAULT_ACQUISITION", entityId = "current", revision = 1,
      entries = { { acquisitionId = record.acquisitionId, revision = 1, contentHash = detail.contentHash } },
    }, "Owner-Realm")
    accepted, reason = dibs.Sync.Receive(digest, "Owner-Realm")
    assert_true(accepted, reason)
    assert_equal("VAULT_DIGEST_CURRENT", reason)
  end)

  it("retries missing Vault detail after a lifecycle reconnect", function()
    local dibs = load()
    local detail = dibs.Sync.BuildVaultDetail({
      acquisitionId = "vault-recovery-retry", guildKey = dibs.GetGuildKey(), playerName = "Owner-Realm",
      characterId = "Player-2-OWNER", itemID = 283003, difficulty = "Normal", seasonId = dibs.GetCurrentSeasonId(),
      resetId = "week-retry", family = "TOKEN", verificationState = "AUTOMATIC_CONFIRMED", evidenceState = "COMPLETE",
      source = "GREAT_VAULT", evidenceId = "claim:283003", revision = 2, syncState = "LOCAL",
    })
    local accepted = dibs.Sync.Receive(remote(dibs, {
      type = "VAULT_DIGEST", entityType = "VAULT_ACQUISITION", entityId = "current", revision = 1,
      entries = { { acquisitionId = detail.acquisitionId, revision = 2, contentHash = detail.contentHash } },
    }, "Owner-Realm"), "Owner-Realm")
    assert_true(accepted)
    local pending = dibs.GetDB().sync.v2.vaultPending[detail.acquisitionId]
    assert_not_nil(pending)
    local before = pending.attempts or 0
    dibs.Sync.OnLifecycle("RECONNECT")
    assert_true((dibs.GetDB().sync.v2.vaultPending[detail.acquisitionId].attempts or 0) > before)
  end)

  it("expires an incomplete Vault transfer without creating an acquisition", function()
    local dibs = load()
    local begin = remote(dibs, {
      type = "TRANSFER_BEGIN", transferId = "vault-expired", entityType = "VAULT_DETAIL",
      entityId = "vault-expired", revision = 1, contentHash = "content", payloadHash = "raw",
      chunkCount = 1,
    }, "Owner-Realm")
    assert_true(dibs.Sync.Receive(begin, "Owner-Realm"))
    dibs.runtime.v2Transfers["vault-expired"].expiresAt = 0
    local chunk = remote(dibs, { type = "TRANSFER_CHUNK", transferId = "vault-expired", chunkIndex = 1, chunk = "x" }, "Owner-Realm")
    local accepted, reason = dibs.Sync.Receive(chunk, "Owner-Realm")
    assert_false(accepted)
    assert_equal("INVALID_TRANSFER_CHUNK", reason)
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)
end)
