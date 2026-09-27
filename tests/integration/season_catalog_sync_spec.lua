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

  it("propagates an installation mode change to a reconnecting member", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local policySaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local result = gm.ProtectedActions.Execute("installation.mode.set", nil, { mode = "STANDALONE" })
    assert_true(result.ok, tostring(result.reasonCode))
    local catalog = gm.Seasons.GetCatalogRecord(gm.Seasons.GetCatalogState().catalogRevision)

    local target = load("Player-Realm", policySaved)
    assert_equal("AUTO", target.Permissions.GetInstallationMode())
    local applied, applyReason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_equal("STANDALONE", target.Permissions.GetInstallationMode())
  end)

  it("LRA12 preserves local legacy Loot Rules when applying a guild catalog", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    gm.db.settings.dibAllowedTypes = { TOKEN = true, OTHER = true }
    gm.db.settings.dibRCEnabledTypes = { default = true }
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert(gm.Seasons.Create("Loot Rules Season"))
    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(publishReason))

    local target = load("Player-Realm", gm.DeepCopy(saved))
    target.db.settings.dibAllowedTypes = { TOKEN = false, OTHER = false }
    target.db.settings.dibRCEnabledTypes = { default = false }
    local applied, applyReason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_false(target.db.settings.dibAllowedTypes.TOKEN)
    assert_false(target.db.settings.dibAllowedTypes.OTHER)
    assert_false(target.db.settings.dibRCEnabledTypes.default)
  end)

  it("LRA13 publishes and carries a complete versioned Loot Rules snapshot", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local draft = assert(gm.LootRules.GetDraftSnapshot())
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert(gm.Seasons.Create("Authoritative Loot Rules"))
    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "GUILD_LOOT_RULES_ADOPT", {
      guildLootRules = draft,
      changedLootTypes = { "default", "OTHER" },
    })
    assert_true(published, tostring(publishReason))
    assert_equal(1, catalog.guildConfiguration.guildLootRules.schemaVersion)
    assert_equal(gm.Seasons.CalculateCatalogHash(catalog), catalog.contentHash)
    assert_equal("GUILD_LOOT_RULES_ADOPT", catalog.audit.action)
    assert_equal("OTHER", catalog.audit.changedLootTypes[2])

    assert(gm.Seasons.Create("Later Season"))
    local nextPublished, nextReason, nextCatalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(nextPublished, tostring(nextReason))
    assert_equal(catalog.guildConfiguration.guildLootRules.schemaVersion,
      nextCatalog.guildConfiguration.guildLootRules.schemaVersion)

    local target = load("Player-Realm", gm.DeepCopy(saved))
    local applied, applyReason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    local authority = assert(target.LootRules.GetAuthoritySnapshot())
    assert_equal(catalog.guildConfiguration.guildLootRules.types.default.adventureGuide,
      authority.types.default.adventureGuide)
  end)

  it("LRA14 rejects an unsupported nested Loot Rules schema before catalog mutation", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local draft = assert(gm.LootRules.GetDraftSnapshot())
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert(gm.Seasons.Create("Invalid Loot Rules"))
    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "GUILD_LOOT_RULES_ADOPT", {
      guildLootRules = draft,
      changedLootTypes = { "TOKEN" },
    })
    assert_true(published, tostring(publishReason))
    local target = load("Player-Realm", saved)
    local invalid = target.DeepCopy(catalog)
    invalid.guildConfiguration.guildLootRules.schemaVersion = 99
    invalid.contentHash = target.Seasons.CalculateCatalogHash(invalid)
    local applied, applyReason = target.Seasons.ApplyCatalog(invalid, "GameMaster-Realm")
    assert_false(applied)
    assert_equal("UNSUPPORTED_GUILD_LOOT_RULES_SCHEMA", applyReason)
    assert_equal(0, target.Seasons.GetCatalogState().catalogRevision)
  end)

  it("LRA15 protects nested Loot Rules content with the catalog hash", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local draft = assert(gm.LootRules.GetDraftSnapshot())
    assert(gm.Seasons.Create("Hashed Loot Rules"))
    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "GUILD_LOOT_RULES_ADOPT", {
      guildLootRules = draft,
      changedLootTypes = { "TOKEN" },
    })
    assert_true(published, tostring(publishReason))
    local target = load("Player-Realm", gm.DeepCopy(_G.RCLootCouncil_dibsDB))
    local tampered = target.DeepCopy(catalog)
    tampered.guildConfiguration.guildLootRules.types.default.adventureGuide = false
    local applied, applyReason = target.Seasons.ApplyCatalog(tampered, "GameMaster-Realm")
    assert_false(applied)
    assert_equal("SEASON_CATALOG_HASH_MISMATCH", applyReason)
  end)

  it("LRA16 allows an authorized Officer catalog change that carries unchanged Loot Rules", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local adoptedSaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local officer = load("Officer-Realm", adoptedSaved)
    assert(officer.Seasons.Create("Officer Season"))
    local published, publishReason, catalog = officer.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(publishReason))
    local authority, status = officer.LootRules.GetAuthoritySnapshot()
    assert_true(type(authority) == "table")
    assert_equal("GUILD_LOOT_RULES_READY", status)
    assert_true(catalog.guildConfiguration.guildLootRules ~= nil)
  end)

  it("LRA17 replays an adopted Loot Rules catalog idempotently", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local catalog = gm.Seasons.GetCatalogRecord(gm.Seasons.GetCatalogState().catalogRevision)
    local target = load("Player-Realm", gm.DeepCopy(_G.RCLootCouncil_dibsDB))
    local applied, reason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(reason))
    assert_equal("IDEMPOTENT_REPLAY", reason)
  end)

  it("LRA18 rejects a later catalog revision that removes adopted Loot Rules", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert(gm.Seasons.Create("Downgrade Attempt"))
    local published, publishReason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(publishReason))
    catalog.guildConfiguration.guildLootRules = nil
    catalog.contentHash = gm.Seasons.CalculateCatalogHash(catalog)
    local target = load("Player-Realm", saved)
    local applied, applyReason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_false(applied)
    assert_equal("GUILD_LOOT_RULES_DOWNGRADE", applyReason)
    assert_equal(saved.guilds[target.GetGuildKey()].seasonCatalog.catalogRevision,
      target.Seasons.GetCatalogState().catalogRevision)
  end)
end)
