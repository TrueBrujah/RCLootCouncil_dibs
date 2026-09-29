local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved, overrides)
  local wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm", guildMembers = roster, guildRankIndices = ranks,
  }
  for key, value in pairs(overrides or {}) do wow[key] = value end
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = wow }))
end

local function sameValue(first, second, seen)
  if type(first) ~= type(second) then return false end
  if type(first) ~= "table" then return first == second end
  seen = seen or {}
  if seen[first] == second then return true end
  seen[first] = second
  for key, value in pairs(first) do
    if not sameValue(value, second[key], seen) then return false end
  end
  for key in pairs(second) do
    if first[key] == nil then return false end
  end
  return true
end

local function adoptPolicy(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "guild Loot Rules test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }, "guild Loot Rules test"))
end

describe("Guild-authoritative Loot Rules", function()
  it("LRA01 adopts a complete snapshot once as the current GM", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_equal(0, gm.Seasons.GetCatalogState().catalogRevision)
    local adopted, reason = gm.LootRules.Adopt()
    assert_true(adopted, tostring(reason))
    assert_equal(1, gm.Seasons.GetCatalogState().catalogRevision)
    local authority, status = gm.LootRules.GetAuthoritySnapshot()
    assert_true(type(authority) == "table", tostring(status))
    assert_equal("GUILD_LOOT_RULES_READY", status)
  end)

  it("LRA02 denies Officer adoption without changing the catalog", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local officer = load("Officer-Realm", saved)
    local adopted, reason = officer.LootRules.Adopt()
    assert_equal(false, adopted)
    assert_equal("CURRENT_GUILD_MASTER_REQUIRED", reason)
    assert_equal(0, officer.Seasons.GetCatalogState().catalogRevision)
  end)

  it("LRA03 keeps draft edits ineffective until explicit publication", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local before, source = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal("GUILD", source)
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", not before))
    local stillEffective, stillSource = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal(before, stillEffective)
    assert_equal("GUILD", stillSource)
  end)

  it("LRA04 publishes a draft change as one audited catalog revision", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local revision = gm.Seasons.GetCatalogState().catalogRevision
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    local published, reason = gm.LootRules.PublishDraft()
    assert_true(published, tostring(reason))
    assert_equal(revision + 1, gm.Seasons.GetCatalogState().catalogRevision)
    local record = gm.Seasons.GetCatalogRecord(revision + 1)
    assert_equal("GUILD_LOOT_RULES_PUBLISH", record.audit.action)
    assert_true(type(record.audit.changedLootTypes) == "table")
    assert_true(table.concat(record.audit.changedLootTypes, ","):find("TOKEN", 1, true) ~= nil)
    local effective = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal(false, effective)
  end)

  it("LRA05 preserves the prior authority and local draft when transport preflight fails", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local revision = gm.Seasons.GetCatalogState().catalogRevision
    local effectiveBefore = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", not effectiveBefore))
    local draftBefore = gm.LootRules.GetDraftSnapshot()
    gm.Sync.RegisterTransport = function() return false end
    local published, reason = gm.LootRules.PublishDraft()
    assert_equal(false, published)
    assert_equal("SYNC_UNAVAILABLE", reason)
    assert_equal(revision, gm.Seasons.GetCatalogState().catalogRevision)
    assert_equal(effectiveBefore, gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide"))
    assert_equal(draftBefore.types.TOKEN.adventureGuide, gm.LootRules.GetDraftSnapshot().types.TOKEN.adventureGuide)
  end)

  it("LRA06 denies Officer publication after adoption without changing the authority", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local revision = gm.Seasons.GetCatalogState().catalogRevision
    local prior = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", not prior))
    gm.Permissions.IsGM = function() return false end
    local published, reason = gm.LootRules.PublishDraft()
    assert_equal(false, published)
    assert_equal("CURRENT_GUILD_MASTER_REQUIRED", reason)
    assert_equal(revision, gm.Seasons.GetCatalogState().catalogRevision)
    assert_equal(prior, gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide"))
  end)

  it("LRA07 rolls back the local revision and projection if catalog announcement fails", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local revision = gm.Seasons.GetCatalogState().catalogRevision
    local prior = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", not prior))
    local projectedValues = {}
    gm.RCLootCouncil.RefreshConfigProjection = function()
      projectedValues[#projectedValues + 1] = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
      return true, true
    end
    gm.Sync.AnnounceSeasonCatalog = function() return false, "SYNC_UNAVAILABLE" end
    local published, reason = gm.LootRules.PublishDraft()
    assert_equal(false, published)
    assert_equal("SYNC_UNAVAILABLE", reason)
    assert_equal(revision, gm.Seasons.GetCatalogState().catalogRevision)
    assert_equal(prior, gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide"))
    assert_equal(2, #projectedValues)
    assert_equal(not prior, projectedValues[1])
    assert_equal(prior, projectedValues[2])
  end)

  it("LRA08 applies stable semantic authority keys and preserves local and unrelated RC data", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local savedBeforeAdoption = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "rclootcouncil", false))
    assert_true(gm.LootRules.Adopt())
    local catalog = gm.Seasons.GetCatalogRecord(gm.Seasons.GetCatalogState().catalogRevision)

    local target = load("Player-Realm", savedBeforeAdoption, { inRaid = true, instanceType = "raid", instanceId = 123 })
    target.db.settings.dibAllowedTypes = target.db.settings.dibAllowedTypes or {}
    target.db.settings.dibRCEnabledTypes = target.db.settings.dibRCEnabledTypes or {}
    local keys = target.LootRules.GetSupportedTypes()
    for _, typeKey in ipairs(keys) do
      local rule = catalog.guildConfiguration.guildLootRules.types[typeKey]
      target.db.settings.dibAllowedTypes[typeKey] = not rule.adventureGuide
      target.db.settings.dibRCEnabledTypes[typeKey] = not rule.rclootcouncil
    end
    local localAllowed = target.DeepCopy(target.db.settings.dibAllowedTypes)
    local localButtons = target.DeepCopy(target.db.settings.dibRCEnabledTypes)
    _G.RCLootCouncilDB = { profile = { unrelatedSetting = "preserve", buttons = { ["other-addon"] = true } } }
    local unrelatedRCBefore = target.DeepCopy(_G.RCLootCouncilDB)
    local refreshCount = 0
    target.RCLootCouncil.RefreshConfigProjection = function()
      refreshCount = refreshCount + 1
      return true, true
    end

    local applied, applyReason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    for _, typeKey in ipairs(keys) do
      local rule = catalog.guildConfiguration.guildLootRules.types[typeKey]
      assert_equal(rule.adventureGuide, target.RCLootCouncil.IsDibEnabledForType(typeKey))
      assert_equal(rule.rclootcouncil, target.RCLootCouncil.IsRCButtonEnabledForType(typeKey))
    end
    assert_true(sameValue(localAllowed, target.db.settings.dibAllowedTypes))
    assert_true(sameValue(localButtons, target.db.settings.dibRCEnabledTypes))
    assert_true(sameValue(unrelatedRCBefore, _G.RCLootCouncilDB))
    assert_equal(1, refreshCount)

  end)

  it("LRA19 does not apply a later catalog revision before its missing parent", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local beforeAdoption = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.LootRules.Adopt())
    local prior = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", not prior))
    assert_true(gm.LootRules.PublishDraft())
    local revisionTwo = gm.Seasons.GetCatalogRecord(2)

    local target = load("Player-Realm", beforeAdoption)
    target.db.settings.dibAllowedTypes = { TOKEN = true }
    local localBefore = target.DeepCopy(target.db.settings.dibAllowedTypes)
    local applied, reason = target.Seasons.ApplyCatalog(revisionTwo, "GameMaster-Realm")
    assert_false(applied)
    assert_equal("SEASON_CATALOG_PARENT_MISSING", reason)
    assert_equal(0, target.Seasons.GetCatalogState().catalogRevision)
    assert_true(sameValue(localBefore, target.db.settings.dibAllowedTypes))
    assert_equal("LOCAL_LEGACY_ONLY", target.LootRules.GetStatus().status)
  end)

  it("LRA20 distinguishes all six authority and synchronization readiness states", function()
    local gm = load("GameMaster-Realm")
    local function assertReadinessStatus(expected)
      local report = gm.Readiness.Evaluate({ allowPlayer = true })
      assert_equal(expected, report.guildLootRulesStatus)
      local probe
      for _, item in ipairs(report.probes) do
        if item.name == "guild_loot_rules" then probe = item end
      end
      assert_true(probe ~= nil)
      assert_true(gm.Readiness.FormatSummary(report, true):find(expected, 1, true) ~= nil)
      assert_true(gm.Readiness.BuildReport(report, "detailed"):find(expected, 1, true) ~= nil)
    end

    local status = gm.LootRules.GetStatus()
    assert_equal("GUILD_LOOT_RULES_NOT_CONFIGURED", status.status)
    assertReadinessStatus(status.status)
    gm.db.settings.dibAllowedTypes = { TOKEN = false }
    status = gm.LootRules.GetStatus()
    assert_equal("LOCAL_LEGACY_ONLY", status.status)
    assertReadinessStatus(status.status)

    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    status = gm.LootRules.GetStatus()
    assert_equal("GUILD_LOOT_RULES_READY", status.status)
    assertReadinessStatus(status.status)

    gm.Sync.GetStatus = function()
      return { state = "SYNC_BEHIND", reason = "SEASON_CATALOG_PARENT_MISSING" }
    end
    status = gm.LootRules.GetStatus()
    assert_equal("GUILD_LOOT_RULES_SYNC_BEHIND", status.status)
    assertReadinessStatus(status.status)

    gm.Sync.GetStatus = function() return { state = "SYNC_READY" } end
    gm.Sync.GetSynchronizationStatus = function()
      return { lastAddonVersionMismatch = { reasonCode = "ADDON_UPDATE_REQUIRED" } }
    end
    status = gm.LootRules.GetStatus()
    assert_equal("GUILD_LOOT_RULES_INCOMPATIBLE", status.status)
    assertReadinessStatus(status.status)
    local effective, effectiveSource = gm.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal(gm.LootRules.GetAuthoritySnapshot().types.TOKEN.adventureGuide, effective)
    assert_equal("GUILD", effectiveSource)

    local legacyClient = load("Player-Realm")
    legacyClient.db.settings.dibAllowedTypes = { TOKEN = false }
    legacyClient.Sync.GetSynchronizationStatus = function()
      return { lastAddonVersionMismatch = { reasonCode = "ADDON_UPDATE_REQUIRED" } }
    end
    local localEffective, localReason = legacyClient.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal(nil, localEffective)
    assert_equal("GUILD_LOOT_RULES_INCOMPATIBLE", localReason)

    gm.Sync.GetSynchronizationStatus = function() return {} end
    gm.RCOptions.GetSupportedLootRuleTypeValues = nil
    gm.RCOptions.GetLootTypeOptions = function() return nil end
    status = gm.LootRules.GetStatus()
    assert_equal("UNAVAILABLE", status.status)
    assertReadinessStatus(status.status)
  end)

  it("LRA22 applies a validated guild update during a raid and keeps catalog lag visible", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local beforeAdoption = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    assert_true(gm.LootRules.Adopt())
    local catalog = gm.Seasons.GetCatalogRecord(1)

    local target = load("Player-Realm", beforeAdoption, { inRaid = true, instanceType = "raid", instanceId = 456 })
    target.db.settings.dibAllowedTypes = { TOKEN = true }
    local applied, reason = target.Seasons.ApplyCatalog(catalog, "GameMaster-Realm")
    assert_true(applied, tostring(reason))
    assert_equal(false, target.LootRules.GetEffectiveValue("TOKEN", "adventureGuide"))
    target.Sync.MarkSyncBehind("SEASON_CATALOG_PARENT_MISSING")
    local report = target.Readiness.Evaluate({ allowPlayer = true })
    assert_equal("GUILD_LOOT_RULES_SYNC_BEHIND", report.guildLootRulesStatus)
    local probe
    for _, item in ipairs(report.probes) do
      if item.name == "guild_loot_rules" then probe = item end
    end
    assert_equal("SEASON_CATALOG_PARENT_MISSING", probe.reasonCode)
    local value, source = target.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal(false, value)
    assert_equal("GUILD", source)
  end)
end)
