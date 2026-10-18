local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Alpha-Realm", "Bravo-Realm", "Charlie-Realm", "Delta-Realm", "Echo-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3, [4] = 3, [5] = 3, [6] = 3, [7] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm",
    guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  return envelope
end

local function receive(dibs, message, sender)
  return dibs.Sync.Receive(remote(dibs, dibs.DeepCopy(message), sender), sender)
end

local function fetches(dibs)
  local result = {}
  for _, sent in ipairs(dibs.Ace3.libs.comm.sent) do
    local message = dibs.Ace3.Deserialize(sent.payload)
    if message.type == "DETAIL_FETCH" then result[#result + 1] = { message = message, target = sent.target } end
  end
  return result
end

local function transfer(dibs, entityType, record, revision, sender)
  local raw = assert(dibs.Ace3.Serialize(record))
  local id = entityType .. "-" .. tostring(revision) .. "-" .. sender
  local ok, reason
  for _, message in ipairs({
    { type = "TRANSFER_BEGIN", transferId = id, entityType = entityType, entityId = tostring(revision),
      revision = revision, contentHash = record.contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1 },
    { type = "TRANSFER_CHUNK", transferId = id, chunkIndex = 1, chunk = raw },
    { type = "TRANSFER_END", transferId = id, entityType = entityType },
  }) do
    ok, reason = dibs.Sync.Receive(remote(dibs, message, sender), sender)
    if not ok then return ok, reason end
  end
  return ok, reason
end

local function adopt(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "relay test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
end

local function gmWithCatalog(count)
  local gm = load("GameMaster-Realm")
  adopt(gm)
  local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
  local records = {}
  for index = 1, count do
    assert_not_nil(gm.Seasons.Create("Relay Season " .. index))
    assert_true(gm.Seasons.PublishCatalog(nil, "SEASON_CREATE"))
    records[index] = gm.DeepCopy(gm.Seasons.GetCatalogRecord(index))
  end
  return gm, saved, records, gm.DeepCopy(gm.Sync.BuildSeasonCatalogDigest())
end

describe("Corroborated relay when no writer is online", function()
  it("adopts a multi-revision catalog chain once three members announce the same state", function()
    local _, saved, records, digest = gmWithCatalog(3)
    local dibs = load("Delta-Realm", saved)
    dibs.Ace3.libs.comm.sent = {}
    local ok, reason = receive(dibs, digest, "Alpha-Realm")
    assert_false(ok)
    assert_equal("POLICY_WRITER_REQUIRED", reason)
    ok, reason = receive(dibs, digest, "Alpha-Realm")
    assert_equal("POLICY_WRITER_REQUIRED", reason, "A repeated vote must not count twice")
    ok, reason = receive(dibs, digest, "Bravo-Realm")
    assert_equal("POLICY_WRITER_REQUIRED", reason)
    assert_equal(0, #fetches(dibs), "Below quorum must not fetch anything")
    ok, reason = receive(dibs, digest, "Charlie-Realm")
    assert_true(ok, tostring(reason))
    assert_equal("RELAY_DETAIL_REQUESTED", reason)
    assert_true(dibs.Sync.IsSyncBehind())

    ok, reason = transfer(dibs, "SEASON_CATALOG", records[1], 1, "Echo-Realm")
    assert_false(ok, "A member who did not vote for the target cannot serve it")
    assert_equal("POLICY_WRITER_REQUIRED", reason)

    for revision = 1, 3 do
      local sent = fetches(dibs)
      assert_equal(revision, sent[#sent].message.requests[1].revision)
      ok, reason = transfer(dibs, "SEASON_CATALOG", records[revision], revision, "Charlie-Realm")
      assert_true(ok, tostring(reason))
      assert_equal(revision < 3 and "RELAY_CHAIN_STAGED" or "RELAY_CHAIN_ADOPTED", reason)
      assert_equal(revision < 3 and 0 or 3, dibs.Seasons.GetCatalogState().catalogRevision,
        "Relayed records stay staged until the whole chain links")
    end
    assert_equal(digest.contentHash, dibs.Seasons.GetCatalogState().hash)
    assert_equal("GameMaster-Realm", dibs.Seasons.GetCatalogRecord(3).authorNameRealm)
    dibs.Sync.RecheckSyncBehind()
    assert_false(dibs.Sync.IsSyncBehind())
  end)

  it("adopts a relayed policy revision with the original writer's authority", function()
    local gm = load("GameMaster-Realm")
    adopt(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true }, "relay"))
    assert_true(gm.OperationalPolicy.Change(nil, { allowPublicPreDibs = false }, "relay"))
    local records = { gm.DeepCopy(gm.OperationalPolicy.GetRecord(1)), gm.DeepCopy(gm.OperationalPolicy.GetRecord(2)) }
    local digest = gm.DeepCopy(gm.Sync.BuildOperationalPolicyDigest())
    local dibs = load("Delta-Realm", saved)
    for _, sender in ipairs({ "Alpha-Realm", "Bravo-Realm", "Charlie-Realm" }) do receive(dibs, digest, sender) end
    assert_true(transfer(dibs, "OPERATIONAL_POLICY", records[1], 1, "Bravo-Realm"))
    local ok, reason = transfer(dibs, "OPERATIONAL_POLICY", records[2], 2, "Alpha-Realm")
    assert_true(ok, tostring(reason))
    assert_equal("RELAY_CHAIN_ADOPTED", reason)
    assert_equal(digest.contentHash, dibs.OperationalPolicy.GetState().hash)
    assert_false(dibs.OperationalPolicy.GetState().allowPublicPreDibs == true)
  end)

  it("rejects a corroborated chain whose author is not an authorized writer", function()
    local gm, saved, records = gmWithCatalog(1)
    local forged = gm.DeepCopy(records[1])
    forged.authorNameRealm = "Charlie-Realm"
    forged.contentHash = gm.Seasons.CalculateCatalogHash(forged)
    local digest = { type = "DIGEST", entityType = "SEASON_CATALOG", entityId = "1", revision = 1,
      contentHash = forged.contentHash, parentHash = forged.parentHash, parentRevision = 0 }
    local dibs = load("Delta-Realm", saved)
    local before = dibs.DeepCopy(dibs.Seasons.GetCatalogState())
    for _, sender in ipairs({ "Alpha-Realm", "Bravo-Realm", "Charlie-Realm" }) do receive(dibs, digest, sender) end
    local ok = transfer(dibs, "SEASON_CATALOG", forged, 1, "Charlie-Realm")
    assert_false(ok, "Collusion cannot create authority the author never had")
    assert_equal(before.catalogRevision, dibs.Seasons.GetCatalogState().catalogRevision)
    assert_equal(before.hash, dibs.Seasons.GetCatalogState().hash)
  end)

  it("drops a staged chain that does not link to the local state", function()
    local gm, saved, records, digest = gmWithCatalog(2)
    local broken = gm.DeepCopy(records[2])
    broken.parentHash = "not-the-parent"
    broken.contentHash = gm.Seasons.CalculateCatalogHash(broken)
    digest.contentHash = broken.contentHash
    local dibs = load("Delta-Realm", saved)
    for _, sender in ipairs({ "Alpha-Realm", "Bravo-Realm", "Charlie-Realm" }) do receive(dibs, digest, sender) end
    assert_true(transfer(dibs, "SEASON_CATALOG", records[1], 1, "Alpha-Realm"))
    local ok, reason = transfer(dibs, "SEASON_CATALOG", broken, 2, "Alpha-Realm")
    assert_false(ok)
    assert_equal("RELAY_CHAIN_MISMATCH", reason)
    assert_equal(0, dibs.Seasons.GetCatalogState().catalogRevision)
    assert_true(dibs.Sync.IsSyncBehind())
  end)

  it("keeps a corroborated divergence visible instead of overwriting local state", function()
    local gm, saved, records = gmWithCatalog(1)
    local dibs = load("Delta-Realm", saved)
    dibs.Ace3.libs.comm.sent = {}
    assert_true(receive(dibs, gm.Sync.BuildSeasonCatalogDigest(), "GameMaster-Realm"))
    assert_true(transfer(dibs, "SEASON_CATALOG", records[1], 1, "GameMaster-Realm"))
    local localHash = dibs.Seasons.GetCatalogState().hash
    local divergent = { type = "DIGEST", entityType = "SEASON_CATALOG", entityId = "1", revision = 1, contentHash = "other-history" }
    receive(dibs, divergent, "Alpha-Realm")
    receive(dibs, divergent, "Bravo-Realm")
    local ok, reason = receive(dibs, divergent, "Charlie-Realm")
    assert_false(ok)
    assert_equal("SEASON_CATALOG_CONFLICT", reason)
    assert_equal(localHash, dibs.Seasons.GetCatalogState().hash)
    dibs.Sync.RecheckSyncBehind()
    assert_true(dibs.Sync.IsSyncBehind())
  end)

  it("adopts relayed governance authored by the current Guild Master", function()
    local gm = load("GameMaster-Realm")
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    adopt(gm)
    local record = gm.DeepCopy(gm.Governance.GetState().records["1"])
    local digest = gm.DeepCopy(gm.Sync.BuildGovernanceDigest())
    local dibs = load("Delta-Realm", saved)
    dibs.Ace3.libs.comm.sent = {}
    local ok, reason
    for _, sender in ipairs({ "Alpha-Realm", "Bravo-Realm", "Charlie-Realm" }) do ok, reason = receive(dibs, digest, sender) end
    assert_true(ok, tostring(reason))
    local sent = fetches(dibs)
    assert_equal("GOVERNANCE", sent[#sent].message.requests[1].entityType)
    assert_equal(0, sent[#sent].message.requests[1].parentRevision)
    ok, reason = transfer(dibs, "GOVERNANCE", record, 1, "Charlie-Realm")
    assert_true(ok, tostring(reason))
    assert_equal("RELAY_CHAIN_ADOPTED", reason)
    assert_equal(digest.contentHash, dibs.Governance.GetState().hash)
  end)

  it("ignores a quorum of stale members when the local state is newer", function()
    local gm, saved, records = gmWithCatalog(2)
    local dibs = load("Delta-Realm", saved)
    assert_true(receive(dibs, gm.Sync.BuildSeasonCatalogDigest(), "GameMaster-Realm"))
    assert_true(transfer(dibs, "SEASON_CATALOG", records[1], 1, "GameMaster-Realm"))
    assert_true(transfer(dibs, "SEASON_CATALOG", records[2], 2, "GameMaster-Realm"))
    local stale = { type = "DIGEST", entityType = "SEASON_CATALOG", entityId = "1", revision = 1, contentHash = records[1].contentHash }
    receive(dibs, stale, "Alpha-Realm")
    receive(dibs, stale, "Bravo-Realm")
    local ok, reason = receive(dibs, stale, "Charlie-Realm")
    assert_true(ok)
    assert_equal("RELAY_STALE_IGNORED", reason)
    assert_equal(2, dibs.Seasons.GetCatalogState().catalogRevision)
  end)
end)
