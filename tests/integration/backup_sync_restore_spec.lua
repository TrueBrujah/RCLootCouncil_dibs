local loader = require("helpers.load_addon")

local function load(saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = { guildLeader = true } }))
end

local function adopt(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "backup test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
end

local function publishSeason(dibs, name)
  assert_not_nil(dibs.Seasons.Create(name))
  assert_true(dibs.Seasons.PublishCatalog(nil, "SEASON_CREATE"))
end

local function restore(dibs, snapshotId)
  local preview = assert(dibs.Backup.PreviewRestore(snapshotId))
  return assert(dibs.Backup.Restore(preview.previewId, true, "test"))
end

local function contains(list, value)
  for _, entry in ipairs(list or {}) do if entry == value then return true end end
  return false
end

describe("Backups across factory reset and sync-safe restore", function()
  it("keeps Officer backups through a factory reset and restores the guild state from them", function()
    local dibs = load()
    adopt(dibs)
    publishSeason(dibs, "Backup Season 1")
    publishSeason(dibs, "Backup Season 2")
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true }, "backup"))
    dibs.Ledger.Grant(dibs.GetPlayerName(), 1, "test", "backup", dibs.GetCurrentSeasonId())
    local expected = {
      governance = dibs.Governance.GetState().hash,
      catalog = dibs.Seasons.GetCatalogState().hash,
      policy = dibs.OperationalPolicy.GetState().hash,
      transactions = #dibs.Ledger.GetAllTransactions(),
    }
    local snapshot = assert(dibs.Backup.Create("full", "before reset"))

    local previousReload, previousCombat = _G.ReloadUI, _G.InCombatLockdown
    _G.ReloadUI, _G.InCombatLockdown = function() end, function() return false end
    dibs.FactoryReset()
    assert_true(dibs.FactoryReset("CONFIRM"))
    _G.ReloadUI, _G.InCombatLockdown = previousReload, previousCombat
    local root = _G.RCLootCouncil_dibsDB
    assert_not_nil(root, "Preserved backups need a root to survive the reload")
    assert_equal(0, (function() local n = 0; for _ in pairs(root.guilds) do n = n + 1 end; return n end)())
    assert_not_nil(root.preservedBackups)
    assert_nil(_G.RCLootCouncil_dibsSandboxDB)

    dibs = load(dibs.DeepCopy(root))
    assert_nil(_G.RCLootCouncil_dibsDB.preservedBackups, "Preserved backups are moved into the guild once")
    assert_equal(0, dibs.Governance.GetState().revision)
    assert_equal(0, dibs.Seasons.GetCatalogState().catalogRevision)
    assert_not_nil(dibs.Backup.Get(snapshot.snapshotId))

    local result = restore(dibs, snapshot.snapshotId)
    assert_equal(0, #result.keptLocal)
    assert_equal(expected.governance, dibs.Governance.GetState().hash)
    assert_equal(expected.catalog, dibs.Seasons.GetCatalogState().hash)
    assert_equal(expected.policy, dibs.OperationalPolicy.GetState().hash)
    assert_equal(expected.transactions, #dibs.Ledger.GetAllTransactions())
    assert_equal("Backup Season 2", dibs.Seasons.GetCurrent().name)
  end)

  it("never rolls back shared revision chains or ledger history when restoring an older backup", function()
    local dibs = load()
    adopt(dibs)
    publishSeason(dibs, "Old Season")
    local db = dibs.GetDB()
    db.settings.theme = "from-backup"
    local snapshot = assert(dibs.Backup.Create("full", "older"))
    publishSeason(dibs, "New Season")
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true }, "after backup"))
    dibs.Ledger.Grant(dibs.GetPlayerName(), 1, "test", "after backup", dibs.GetCurrentSeasonId())
    db.settings.theme = "changed"
    local catalog = dibs.DeepCopy(dibs.Seasons.GetCatalogState())
    local policyHash = dibs.OperationalPolicy.GetState().hash
    local transactions = #dibs.Ledger.GetAllTransactions()

    local result = restore(dibs, snapshot.snapshotId)
    assert_true(contains(result.keptLocal, "seasonCatalog"))
    assert_true(contains(result.keptLocal, "operationalPolicy"))
    assert_true(contains(result.keptLocal, "ledger:guild-primary"))
    db = dibs.GetDB()
    assert_equal(catalog.catalogRevision, dibs.Seasons.GetCatalogState().catalogRevision)
    assert_equal(catalog.hash, dibs.Seasons.GetCatalogState().hash)
    assert_equal("New Season", dibs.Seasons.GetCurrent().name)
    assert_equal(policyHash, dibs.OperationalPolicy.GetState().hash)
    assert_equal(transactions, #dibs.Ledger.GetAllTransactions())
    assert_equal("from-backup", db.settings.theme, "Local, unshared data still comes from the backup")
  end)

  it("keeps a shared season catalog when restoring a guild-scope backup", function()
    local dibs = load()
    adopt(dibs)
    publishSeason(dibs, "Catalog Season 1")
    local snapshot = assert(dibs.Backup.Create("guild", "guild scope"))
    publishSeason(dibs, "Catalog Season 2")
    local catalog = dibs.DeepCopy(dibs.Seasons.GetCatalogState())
    local result = restore(dibs, snapshot.snapshotId)
    assert_true(contains(result.keptLocal, "seasonCatalog"))
    assert_equal("Catalog Season 2", dibs.Seasons.GetCurrent().name)
    assert_equal(catalog.hash, dibs.Seasons.GetCatalogState().hash)
  end)
end)
