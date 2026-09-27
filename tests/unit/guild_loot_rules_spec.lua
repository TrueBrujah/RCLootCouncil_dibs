local loader = require("helpers.load_addon")

local function load()
  return select(2, loader.load({ withAce3 = true }))
end

local function setSupportedKeys(dibs, keys)
  dibs.RCOptions.GetLootTypeOptions = function()
    return { types = { values = function() return keys end } }
  end
end

describe("Guild Loot Rules normalization", function()
  it("normalizes a complete snapshot from the dynamic option keys", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio", OTHER = "Other" })
    local normalized, reason = dibs.LootRules.NormalizeSnapshot({
      schemaVersion = 1,
      types = {
        TOKEN = { adventureGuide = false, rclootcouncil = true },
        OTHER = { adventureGuide = true, rclootcouncil = false },
      },
    })
    assert_true(type(normalized) == "table", tostring(reason))
    assert_equal(false, normalized.types.TOKEN.adventureGuide)
    assert_equal(true, normalized.types.TOKEN.rclootcouncil)
    assert_equal(true, normalized.types.OTHER.adventureGuide)
    assert_equal(false, normalized.types.OTHER.rclootcouncil)
  end)

  it("rejects missing or unsupported dynamic keys", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio", OTHER = "Other" })
    local normalized, reason = dibs.LootRules.NormalizeSnapshot({
      schemaVersion = 1,
      types = { TOKEN = { adventureGuide = true, rclootcouncil = true } },
    })
    assert_equal(nil, normalized)
    assert_equal("INCOMPLETE_GUILD_LOOT_RULES", reason)

    normalized, reason = dibs.LootRules.NormalizeSnapshot({
      schemaVersion = 1,
      types = {
        TOKEN = { adventureGuide = true, rclootcouncil = true },
        OTHER = { adventureGuide = true, rclootcouncil = true },
        UNKNOWN = { adventureGuide = true, rclootcouncil = true },
      },
    })
    assert_equal(nil, normalized)
    assert_equal("UNSUPPORTED_GUILD_LOOT_TYPE", reason)
  end)

  it("rejects unsupported schema versions and non-boolean decisions", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio" })
    local normalized, reason = dibs.LootRules.NormalizeSnapshot({
      schemaVersion = 2,
      types = { TOKEN = { adventureGuide = true, rclootcouncil = true } },
    })
    assert_equal(nil, normalized)
    assert_equal("UNSUPPORTED_GUILD_LOOT_RULES_SCHEMA", reason)

    normalized, reason = dibs.LootRules.NormalizeSnapshot({
      schemaVersion = 1,
      types = { TOKEN = { adventureGuide = 1, rclootcouncil = true } },
    })
    assert_equal(nil, normalized)
    assert_equal("INVALID_GUILD_LOOT_RULE", reason)
  end)

  it("reports the option source unavailable instead of accepting a partial snapshot", function()
    local dibs = load()
    dibs.RCOptions.GetLootTypeOptions = function() return nil end
    local normalized, reason = dibs.LootRules.NormalizeSnapshot({ schemaVersion = 1, types = {} })
    assert_equal(nil, normalized)
    assert_equal("GUILD_LOOT_RULES_UNAVAILABLE", reason)
  end)

  it("builds a complete draft from preserved local maps and existing defaults", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio", OTHER = "Other" })
    dibs.db.settings.dibAllowedTypes = { TOKEN = false }
    dibs.db.settings.dibRCEnabledTypes = { OTHER = false }
    local draft, reason = dibs.LootRules.GetDraftSnapshot()
    assert_true(type(draft) == "table", tostring(reason))
    assert_equal(false, draft.types.TOKEN.adventureGuide)
    assert_equal(true, draft.types.TOKEN.rclootcouncil)
    assert_equal(true, draft.types.OTHER.adventureGuide)
    assert_equal(false, draft.types.OTHER.rclootcouncil)
  end)

  it("uses the complete local draft as effective values before adoption", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio" })
    dibs.db.settings.dibAllowedTypes = { TOKEN = false }
    dibs.db.settings.dibRCEnabledTypes = { TOKEN = true }
    local adventureGuide, source = dibs.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    local rcButton, rcSource = dibs.LootRules.GetEffectiveValue("TOKEN", "rclootcouncil")
    assert_equal(false, adventureGuide)
    assert_equal("LOCAL_LEGACY_ONLY", source)
    assert_equal(true, rcButton)
    assert_equal("LOCAL_LEGACY_ONLY", rcSource)
  end)

  it("allows only the GM to edit the local draft", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio" })
    dibs.Permissions.IsGM = function() return false end
    local priorSettings = dibs.db.settings.dibAllowedTypes
    local changed, reason = dibs.LootRules.SetDraftValue("TOKEN", "adventureGuide", false)
    assert_equal(false, changed)
    assert_equal("CURRENT_GUILD_MASTER_REQUIRED", reason)
    assert_equal(priorSettings, dibs.db.settings.dibAllowedTypes)

    dibs.Permissions.IsGM = function() return true end
    changed, reason = dibs.LootRules.SetDraftValue("TOKEN", "adventureGuide", false)
    assert_true(changed, tostring(reason))
    assert_equal(false, dibs.db.settings.dibAllowedTypes.TOKEN)
  end)

  it("distinguishes unconfigured, local-only, and unavailable states", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio" })
    assert_equal("GUILD_LOOT_RULES_NOT_CONFIGURED", dibs.LootRules.GetStatus().status)
    dibs.db.settings.dibAllowedTypes = { TOKEN = false }
    assert_equal("LOCAL_LEGACY_ONLY", dibs.LootRules.GetStatus().status)
    dibs.RCOptions.GetLootTypeOptions = function() return nil end
    assert_equal("UNAVAILABLE", dibs.LootRules.GetStatus().status)
  end)

  it("reports draft changes only after an adopted snapshot exists", function()
    local dibs = load()
    setSupportedKeys(dibs, { TOKEN = "Curio" })
    assert_equal(false, dibs.LootRules.HasDraftChanges())
    dibs.Permissions.IsGM = function() return true end
    assert_true(dibs.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    assert_equal(false, dibs.LootRules.HasDraftChanges())
    dibs.Seasons.GetCatalogState = function() return { catalogRevision = 1 } end
    dibs.Seasons.GetCatalogRecord = function()
      return { guildConfiguration = { guildLootRules = {
        schemaVersion = 1,
        types = { TOKEN = { adventureGuide = true, rclootcouncil = true } },
      } } }
    end
    assert_true(dibs.LootRules.HasDraftChanges())
  end)
end)
