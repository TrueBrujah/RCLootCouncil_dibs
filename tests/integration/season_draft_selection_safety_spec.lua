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
    reason = "season draft safety test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }, "season draft safety test"))
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  return envelope
end

local function transferCatalog(dibs, catalog, sender)
  local raw = assert(dibs.Ace3.Serialize(catalog))
  local transferId = "season-draft-safety-transfer-" .. tostring(catalog.catalogRevision)
  local begin = {
    type = "TRANSFER_BEGIN", transferId = transferId, entityType = "SEASON_CATALOG",
    entityId = tostring(catalog.catalogRevision), revision = catalog.catalogRevision,
    contentHash = catalog.contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1,
  }
  assert_true(dibs.Sync.Receive(remote(dibs, begin, sender), sender))
  assert_true(dibs.Sync.Receive(remote(dibs, {
    type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = 1, chunk = raw,
  }, sender), sender))
  return dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = transferId }, sender), sender)
end

describe("Season draft selection safety", function()
  it("does not select a prepared draft locally after publishing the catalog and archiving the prior season", function()
    local dibs = load("GameMaster-Realm")
    adoptPolicy(dibs)
    dibs.db.seasons, dibs.db.currentSeasonId = {}, nil
    local current = assert(dibs.Seasons.Create("Current season"))
    local draft = assert(dibs.Seasons.CreateDraft("Prepared draft", "draft-local"))

    local published, reason, catalog = dibs.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(reason))
    assert_equal(current.id, catalog.currentSeasonId)
    assert_false(dibs.Seasons.GetById(draft.id).isActive)
    assert_equal(current.id, dibs.Seasons.GetCurrent().id)

    assert_not_nil(dibs.Seasons.ArchiveSeason(current.id))
    assert_nil(dibs.Seasons.GetCurrent())
    assert_nil(dibs.db.currentSeasonId)
  end)

  it("preserves the inactive draft as non-current when a received catalog is applied", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    gm.db.seasons, gm.db.currentSeasonId = {}, nil
    local prior = assert(gm.Seasons.Create("Current season"))
    local draft = assert(gm.Seasons.CreateDraft("Prepared draft", "draft-remote"))
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local published, reason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(reason))

    local receiver = load("Player-Realm", saved)
    local applied, applyReason = receiver.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_equal(prior.id, receiver.Seasons.GetCurrent().id)
    assert_false(receiver.Seasons.GetById(draft.id).isActive)
    assert_equal(prior.id, receiver.db.currentSeasonId)
  end)

  it("clears a receiver's archived current season when the catalog explicitly has no current season", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    gm.db.seasons, gm.db.currentSeasonId = {}, nil
    local prior = assert(gm.Seasons.Create("Current season"))
    local receiverSaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_not_nil(gm.Seasons.ArchiveSeason(prior.id))
    local published, reason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_ARCHIVE")
    assert_true(published, tostring(reason))
    assert_nil(catalog.currentSeasonId)

    local receiver = load("Player-Realm", receiverSaved)
    local applied, applyReason = receiver.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_nil(receiver.db.currentSeasonId)
    assert_nil(receiver.GetCurrentSeasonId())
    assert_nil(receiver.Seasons.GetCurrent())
    assert_equal(1, #receiver.Seasons.List(true))
  end)

  it("clears an archived current season through the bounded SyncV2 catalog transfer without selecting a draft", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    gm.db.seasons, gm.db.currentSeasonId = {}, nil
    local prior = assert(gm.Seasons.Create("Current season"))
    local draft = assert(gm.Seasons.CreateDraft("Prepared draft", "draft-transfer-archive"))
    local receiverSaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_not_nil(gm.Seasons.ArchiveSeason(prior.id))
    local published, reason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_ARCHIVE")
    assert_true(published, tostring(reason))
    assert_nil(catalog.currentSeasonId)

    local receiver = load("Player-Realm", receiverSaved)
    local applied, applyReason = transferCatalog(receiver, catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_nil(receiver.db.currentSeasonId)
    assert_nil(receiver.GetCurrentSeasonId())
    assert_nil(receiver.Seasons.GetCurrent())
    assert_false(receiver.Seasons.GetById(draft.id).isActive)
    assert_equal(2, #receiver.Seasons.List(true))
  end)

  it("rejects direct and protected legacy selection of an inactive draft", function()
    local dibs = load("GameMaster-Realm")
    adoptPolicy(dibs)
    dibs.db.seasons, dibs.db.currentSeasonId = {}, nil
    local current = assert(dibs.Seasons.Create("Current season"))
    local draft = assert(dibs.Seasons.CreateDraft("Prepared draft", "draft-legacy-set"))

    local selected, reason = dibs.Seasons.SetCurrent(draft.id)
    assert_false(selected)
    assert_equal("SEASON_NOT_FOUND", reason)
    local result = dibs.ProtectedActions.Execute("season.set", nil, { seasonId = draft.id })
    assert_false(result.ok)
    assert_equal(current.id, dibs.Seasons.GetCurrent().id)
  end)

  it("refuses to publish a local catalog that points at a stale inactive draft", function()
    local dibs = load("GameMaster-Realm")
    adoptPolicy(dibs)
    dibs.db.seasons, dibs.db.currentSeasonId = {}, nil
    local current = assert(dibs.Seasons.Create("Current season"))
    local draft = assert(dibs.Seasons.CreateDraft("Prepared draft", "draft-stale-pointer"))
    dibs.db.currentSeasonId = draft.id

    local published, reason = dibs.Seasons.PublishCatalog(nil, "SEASON_SET")
    assert_false(published)
    assert_equal("INVALID_SEASON_CATALOG_CURRENT_SEASON", reason)
    assert_equal(0, dibs.Seasons.GetCatalogState().catalogRevision)
    assert_equal(current.id, dibs.Seasons.GetById(current.id).id)
  end)

  it("rejects an incoming catalog whose current-season pointer names an inactive draft", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert(gm.Seasons.Create("Current season"))
    local draft = assert(gm.Seasons.CreateDraft("Prepared draft", "draft-invalid-catalog"))
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local published, reason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(reason))
    catalog.currentSeasonId = draft.id
    catalog.contentHash = gm.Seasons.CalculateCatalogHash(catalog)

    local receiver = load("Player-Realm", saved)
    local applied, applyReason = receiver.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_false(applied)
    assert_equal("INVALID_SEASON_CATALOG_CURRENT_SEASON", applyReason)
    assert_equal(0, receiver.Seasons.GetCatalogState().catalogRevision)
  end)
end)
