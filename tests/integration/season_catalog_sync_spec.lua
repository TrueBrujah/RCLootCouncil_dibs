local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function adoptPolicy(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "season catalog test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }, "season catalog test"))
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  return envelope
end

local function transferCatalog(dibs, catalog, sender)
  local raw = assert(dibs.Ace3.Serialize(catalog))
  local transferId = "season-catalog-transfer-" .. tostring(catalog.catalogRevision)
  local begin = {
    type = "TRANSFER_BEGIN", transferId = transferId, entityType = "SEASON_CATALOG",
    entityId = tostring(catalog.catalogRevision), revision = catalog.catalogRevision,
    contentHash = catalog.contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1,
  }
  assert_true(dibs.Sync.Receive(remote(dibs, begin, sender), sender))
  assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = 1, chunk = raw }, sender), sender))
  return dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = transferId }, sender), sender)
end

describe("Guild season catalog", function()
  it("replicates a complete authorized season catalog to a reconnecting member", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local policySaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local first = assert(gm.Seasons.Create("Season One"))
    local second = assert(gm.Seasons.Create("Season Two"))
    assert_true(gm.Seasons.ArchiveSeason(first.id) ~= nil)
    assert_true(gm.Seasons.SetCurrent(second.id))

    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_SET")
    assert_true(published, tostring(publishReason))
    assert_equal(1, catalog.catalogRevision)

    local target = load("Player-Realm", policySaved)
    local applied, applyReason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_equal("Season Two", target.Seasons.GetCurrent().name)
    assert_true(target.Seasons.GetById(first.id).isArchived)
  end)

  it("applies a catalog delivered through the bounded SyncV2 transfer", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local policySaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local season = assert(gm.Seasons.Create("Transferred Season"))
    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(publishReason))

    local target = load("Player-Realm", policySaved)
    local applied, applyReason = transferCatalog(target, catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_equal("Transferred Season", target.Seasons.GetById(season.id).name)
    assert_equal(catalog.catalogRevision, target.Seasons.GetCatalogState().catalogRevision)
  end)
end)
