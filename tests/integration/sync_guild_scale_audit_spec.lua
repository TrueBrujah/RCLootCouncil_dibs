local loader = require("helpers.load_addon")

local function setup(memberCount)
  local members, ranks = { "Tester-Realm" }, { 0 }
  for index = 2, memberCount do
    members[index], ranks[index] = "Audit" .. index .. "-Realm", 3
  end
  local _, dibs = loader.load({ withAce3 = true, savedVariables = {}, wow = {
    playerName = members[1], guildLeader = true, guildMembers = members,
    guildRankIndices = ranks,
  } })
  -- A burst has a fixed timestamp; the default double advances on every call.
  local now = time() + 10000
  _G.time = function() return now end
  local history = assert(dibs.PreDibs.GetHistory("guild-primary"))
  for index = 1, 20 do
    history[index] = { requestId = "scale-request-" .. index,
      ledgerId = "guild-primary", revision = 1, playerName = members[1],
      status = "confirmed", itemID = 21101, seasonId = dibs.GetCurrentSeasonId(),
      createdAt = index, updatedAt = index }
  end
  return dibs, members, function() now = now + 60 end
end

describe("Guild sync scale audit", function()
  for _, memberCount in ipairs({ 50, 60 }) do
    it("reuses the local request index for current digests from " .. memberCount .. " participants", function()
      local dibs, members = setup(memberCount)
      local manifest = assert(dibs.Sync.BuildManifest("guild-primary"))
      local digestSummary = assert(dibs.Sync.GetManifestDigestSummary("guild-primary"))
      assert_equal(manifest.revision, digestSummary.revision)
      assert_equal(manifest.contentHash, digestSummary.contentHash)
      local packets = {}
      for index = 2, #members do
        local message = assert(dibs.Sync.BuildEnvelope(dibs.DeepCopy(manifest)))
        message.senderNameRealm = members[index]
        message.senderMemberKey = assert(dibs.Identity.CanonicalMemberKey(members[index]))
        packets[#packets + 1] = { sender = members[index],
          payload = assert(dibs.Ace3.Serialize(message)) }
      end
      local original, reads = dibs.PreDibs.GetHistory, 0
      local originalLookup, lastLookup, lookupBuilds = dibs.PreDibs.GetHistoryLookup, nil, 0
      dibs.PreDibs.GetHistory = function(...)
        reads = reads + 1
        return original(...)
      end
      dibs.PreDibs.GetHistoryLookup = function(...)
        local lookup = originalLookup(...)
        if lookup ~= lastLookup then lookupBuilds = lookupBuilds + 1; lastLookup = lookup end
        return lookup
      end
      local outgoingBefore = #dibs.Ace3.libs.comm.sent
      local ok, err = pcall(function()
        for _, packet in ipairs(packets) do
          local accepted, reason = dibs.Sync.OnAddonMessage("DIBS", packet.payload,
            "GUILD", packet.sender)
          assert_true(accepted, tostring(reason))
          assert_equal("DIGEST_CURRENT", reason)
        end
      end)
      assert_true(ok, tostring(err))
      assert_equal(outgoingBefore, #dibs.Ace3.libs.comm.sent,
        "current indexes unexpectedly requested details")
      print("AUDIT_SYNC participants=" .. memberCount .. " incoming-indexes=" .. #packets
        .. " entries-per-index=20 history-reads=" .. reads .. " lookup-builds=" .. lookupBuilds .. " detail-fetches=0")
      assert_equal(0, reads, "unchanged digests should reuse the cached request index")
      assert_equal(1, lookupBuilds, "unchanged digests should reuse one local request lookup")
      local records = original("guild-primary")
      records[1].status, records[1].revision = "cancelled", 2
      dibs.PreDibs.MarkHistoryChanged("guild-primary")
      local refreshed = assert(dibs.Sync.BuildManifest("guild-primary"))
      local refreshedSummary = assert(dibs.Sync.GetManifestDigestSummary("guild-primary"))
      assert_equal(refreshed.contentHash, refreshedSummary.contentHash)
      assert_equal(1, reads, "a request mutation should rebuild the index once")
      assert_true(refreshed.contentHash ~= manifest.contentHash,
        "a changed request history should publish a new digest")
      dibs.PreDibs.GetHistoryLookup("guild-primary")
      assert_equal(2, lookupBuilds, "a request mutation should rebuild the local lookup")
      dibs.PreDibs.GetHistory = original
      dibs.PreDibs.GetHistoryLookup = originalLookup
    end)
  end

  it("builds local sync digests once for a 60-member peer roster", function()
    local dibs = setup(60)
    local rosterSnapshot = dibs.Identity.GetRosterSnapshot()
    assert_equal(60, #rosterSnapshot)
    assert_equal(rosterSnapshot, dibs.Identity.GetRosterSnapshot())
    local originalRosterInfo, rosterReads = _G.GetGuildRosterInfo, 0
    _G.GetGuildRosterInfo = function(...)
      rosterReads = rosterReads + 1
      return originalRosterInfo(...)
    end
    local counts, originals = {}, {}
    for _, name in ipairs({ "GetManifestDigestSummary", "BuildVaultDigest", "BuildLedgerDigest" }) do
      originals[name], counts[name] = dibs.Sync[name], 0
      local original = originals[name]
      dibs.Sync[name] = function(...)
        counts[name] = counts[name] + 1
        return original(...)
      end
    end
    local peers = dibs.Sync.GetPeerStatuses("GUILD")
    for name, original in pairs(originals) do dibs.Sync[name] = original end
    _G.GetGuildRosterInfo = originalRosterInfo
    assert_equal(60, #peers)
    assert_equal(0, rosterReads, "Synchronization should reuse the cached Identity roster")
    for name, count in pairs(counts) do
      print("AUDIT_SYNC peer-roster=60 " .. name .. "-builds=" .. count)
      assert_equal(1, count, name .. " should be computed once per rendered roster")
    end
  end)

  it("caches the Vault digest summary and invalidates it after an acquisition mutation", function()
    local dibs = setup(1)
    local acquisitions = dibs.PreDibs.GetAcquisitions()
    acquisitions[1] = {
      acquisitionId = "vault-scale-1", revision = 1, playerName = "Tester-Realm",
      itemID = 21101, seasonId = dibs.GetCurrentSeasonId(), source = "GREAT_VAULT",
      verificationState = "UNVERIFIED", syncState = "LOCAL",
    }
    dibs.PreDibs.MarkAcquisitionsChanged()
    local sourceItemName = acquisitions[1].itemName
    local detail = assert(dibs.Sync.BuildVaultDetail(acquisitions[1]))
    detail.acquisition.itemName = "network-side mutation"
    assert_equal(sourceItemName, acquisitions[1].itemName,
      "a Vault detail payload must not expose mutable SavedVariables references")
    local original, builds = dibs.Sync.BuildVaultDigest, 0
    dibs.Sync.BuildVaultDigest = function(...)
      builds = builds + 1
      return original(...)
    end
    local first = assert(dibs.Sync.GetVaultDigestSummary())
    local getAcquisitions = dibs.PreDibs.GetAcquisitions
    dibs.PreDibs.GetAcquisitions = function()
      error("a warm digest-cache hit should not resolve/normalize the full Pre-Dibs store")
    end
    local second = assert(dibs.Sync.GetVaultDigestSummary())
    dibs.PreDibs.GetAcquisitions = getAcquisitions
    assert_equal(first.contentHash, second.contentHash)
    local legacyProjection = dibs.DeepCopy(acquisitions[1])
    legacyProjection.evidence, legacyProjection.originalEvidence = nil, nil
    legacyProjection.review, legacyProjection.syncState = nil, nil
    local expectedHash = dibs.Sync.CalculateContentHash({ {
      acquisitionId = acquisitions[1].acquisitionId, revision = acquisitions[1].revision,
      contentHash = dibs.Sync.CalculateContentHash(legacyProjection),
      playerName = acquisitions[1].playerName, itemID = acquisitions[1].itemID,
      seasonId = acquisitions[1].seasonId, resetId = acquisitions[1].resetId,
      claimedAt = acquisitions[1].claimedAt,
      verificationState = acquisitions[1].verificationState,
      source = acquisitions[1].source, syncState = acquisitions[1].syncState,
    } })
    assert_equal(expectedHash, first.contentHash,
      "the shallow safe projection must preserve the established digest hash")
    assert_equal(1, builds, "unchanged acquisition data should reuse the scalar digest cache")
    acquisitions[1].evidence = { payload = string.rep("evidence", 1000) }
    dibs.PreDibs.MarkAcquisitionsChanged()
    local evidenceOnlyChange = assert(dibs.Sync.GetVaultDigestSummary())
    assert_equal(first.contentHash, evidenceOnlyChange.contentHash,
      "private evidence must remain excluded from the player-safe digest")
    assert_equal(2, builds, "a marked mutation should refresh the summary")
    acquisitions[1].revision = 2
    acquisitions[1].itemName = "Updated test item"
    dibs.PreDibs.MarkAcquisitionsChanged()
    local refreshed = assert(dibs.Sync.GetVaultDigestSummary())
    assert_equal(3, builds, "an acquisition mutation should rebuild the digest once")
    assert_true(refreshed.contentHash ~= first.contentHash,
      "the refreshed digest must reflect changed acquisition data")
    dibs.Sync.BuildVaultDigest = original
  end)

  it("builds the ledger digest from scalar canonical state without copying commit history", function()
    local dibs = setup(1)
    local ledger = dibs.GetDB().ledgers["guild-primary"]
    ledger.canonical.epoch, ledger.canonical.nextSeq, ledger.canonical.rootHash = "audit-epoch", 8, "audit-root"
    local isV2Enforced, getAuthority = dibs.Governance.IsV2Enforced, dibs.Governance.GetAuthorityState
    local getAuthorityDigestState = dibs.Governance.GetAuthorityDigestState
    dibs.Governance.IsV2Enforced = function()
      error("ledger digest should read protocol state from its scalar summary")
    end
    dibs.Governance.GetAuthorityState = function()
      error("ledger digest should not clone the full authority state")
    end
    dibs.Governance.GetAuthorityDigestState = function()
      return { protocolState = "V2_ENFORCED", state = "LEGACY_LOCAL" }
    end
    local getCanonicalState = dibs.Ledger.GetCanonicalState
    dibs.Ledger.GetCanonicalState = function()
      error("a sync digest must not clone/count the full canonical commit state")
    end
    local getDB = dibs.GetDB
    dibs.GetDB = function()
      error("a resolved primary-ledger digest must not normalize SavedVariables again")
    end
    local digest = assert(dibs.Sync.BuildLedgerDigest("guild-primary"))
    dibs.GetDB = getDB
    dibs.Ledger.GetCanonicalState = getCanonicalState
    dibs.Governance.IsV2Enforced, dibs.Governance.GetAuthorityState = isV2Enforced, getAuthority
    dibs.Governance.GetAuthorityDigestState = getAuthorityDigestState
    assert_equal("audit-epoch", digest.ledgerEpoch)
    assert_equal(7, digest.revision)
    assert_equal("audit-root", digest.contentHash)
  end)

  it("projects only the requested page of guild peers after name filtering", function()
    local dibs = setup(60)
    local originalResolve, resolveCalls = dibs.Identity.ResolveRosterMember, 0
    dibs.Identity.ResolveRosterMember = function(...)
      resolveCalls = resolveCalls + 1
      return originalResolve(...)
    end
    local peers, page = dibs.Sync.GetPeerStatuses("GUILD", {
      page = 2, pageSize = 20, query = "audit",
    })
    dibs.Identity.ResolveRosterMember = originalResolve

    assert_equal(20, #peers)
    assert_equal(59, page.totalMatches)
    assert_equal(3, page.totalPages)
    assert_equal(2, page.page)
    assert_equal(1, resolveCalls, "the shared roster snapshot should only resolve the local identity")
    for _, peer in ipairs(peers) do
      assert_true(string.lower(peer.playerName):find("audit", 1, true) ~= nil)
    end
  end)

  it("retains periodic announcements of unchanged indexes", function()
    local dibs, _, advance = setup(60)
    local sent = dibs.Ace3.libs.comm.sent
    local before = #sent
    for _ = 1, 2 do
      advance()
      assert_true(dibs.Sync.OnLifecycle("HEARTBEAT"))
    end
    local indexes, hashes = 0, {}
    for index = before + 1, #sent do
      local message = dibs.Ace3.Deserialize(sent[index].payload)
      if message and message.entityType == "PREDIB_INDEX" then
        indexes = indexes + 1
        hashes[#hashes + 1] = message.contentHash
        assert_equal("GUILD", sent[index].channel)
      end
    end
    assert_equal(2, indexes)
    assert_equal(hashes[1], hashes[2])
    local heartbeat = dibs.Ace3.libs.timer.scheduled[dibs.Sync.heartbeat]
    assert_not_nil(heartbeat)
    assert_equal(60, heartbeat.delay)
    print("AUDIT_SYNC heartbeats=2 unchanged-index-broadcasts=" .. indexes
      .. " heartbeat-delay=" .. heartbeat.delay)
  end)
end)
