local loader = require("helpers.load_addon")

local function legacyGuild(version)
  return {
    version = version,
    currentSeasonId = "season-legacy",
    seasons = { ["season-legacy"] = { id = "season-legacy", name = "Legacy", isArchived = false } },
    rankRules = {},
    ledger = {
      transactions = {
        ["legacy-tx-1"] = { transactionId = "legacy-tx-1", playerName = "Tester-Realm", amount = -1, seasonId = "season-legacy" },
      },
      playerStates = {},
      awardTransactions = {},
      evidenceTransactions = {},
    },
    permissions = { adminEvents = {}, activeStandaloneAdmins = {} },
    preDibs = {
      requests = { { requestId = "legacy-request-1", playerName = "Tester-Realm", itemID = 21061, seasonId = "season-legacy" } },
      modePolicies = {},
      acquisitions = {},
    },
    settings = { allowPublicPreDibs = false },
    sync = { seenTransactions = {}, peerStates = {} },
  }
end

local function currentRoot(guild)
  return {
    schemaVersion = 6,
    guilds = { ["realm:testguild"] = guild or legacyGuild(7) },
    persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
  }
end

local function hasQuarantine(root, scope, original)
  for _, entry in ipairs(root.persistenceRecovery.quarantine or {}) do
    if entry.scope == scope and (original == nil or entry.original == original) then return true end
  end
  return false
end

describe("SavedVariables validation and recovery", function()
  it("accepts a valid current schema without rewriting valid ledger evidence", function()
    local source = currentRoot()
    local transaction = source.guilds["realm:testguild"].ledger.transactions["legacy-tx-1"]
    local _, dibs = loader.load({ savedVariables = source })
    local db = dibs.GetDB()

    assert_equal("VALID", dibs.GetPersistenceStatus().state)
    assert_equal("legacy-tx-1", db.ledger.transactions["legacy-tx-1"].transactionId)
    assert_equal(transaction.playerName, db.ledger.transactions["legacy-tx-1"].playerName)
    assert_equal(false, db.settings.allowPublicPreDibs)
    assert_equal(0, #_G.RCLootCouncil_dibsDB.persistenceRecovery.backups)
  end)

  it("migrates every supported historical guild schema deterministically", function()
    for version = 1, 6 do
      local _, dibs = loader.load({ savedVariables = legacyGuild(version) })
      local db = dibs.GetDB()
      assert_equal(7, db.version, "schema " .. tostring(version))
      assert_equal("legacy-tx-1", db.ledger.transactions["legacy-tx-1"].transactionId)
      assert_equal("legacy-request-1", db.preDibs.requests[1].requestId)
      assert_equal("MIGRATABLE", dibs.GetPersistenceStatus().state)
    end
  end)

  it("recovers a wrong-type root by preserving it in bounded recovery evidence", function()
    local _, dibs = loader.load({ savedVariables = "corrupt-root" })
    local root = _G.RCLootCouncil_dibsDB

    assert_equal("RECOVERABLE_INVALID", dibs.GetPersistenceStatus().state)
    assert_true(hasQuarantine(root, "root", "corrupt-root"))
    assert_equal("corrupt-root", root.persistenceRecovery.backups[1].snapshot)
    assert_not_nil(dibs.GetDB().ledger.transactions)
  end)

  it("quarantines an invalid settings subtree while preserving valid seasons", function()
    local source = legacyGuild(6)
    source.settings = "not-a-table"
    local _, dibs = loader.load({ savedVariables = source })
    local root, db = _G.RCLootCouncil_dibsDB, dibs.GetDB()

    assert_equal("RECOVERABLE_INVALID", dibs.GetPersistenceStatus().state)
    assert_true(hasQuarantine(root, "guilds[realm:testguild].settings", "not-a-table"))
    assert_equal("season-legacy", db.seasons["season-legacy"].id)
    assert_not_nil(dibs.GetLocalSettings().debugLevels)
  end)

  it("quarantines malformed ledger data rather than silently dropping the original", function()
    local source = legacyGuild(6)
    source.ledger = "broken-ledger"
    local _, dibs = loader.load({ savedVariables = source })
    local root, db = _G.RCLootCouncil_dibsDB, dibs.GetDB()

    assert_equal("RECOVERABLE_INVALID", dibs.GetPersistenceStatus().state)
    assert_true(hasQuarantine(root, "guilds[realm:testguild].ledger", "broken-ledger"))
    assert_equal("broken-ledger", root.persistenceRecovery.backups[1].snapshot.ledger)
    assert_not_nil(db.ledger.transactions)
    assert_equal("legacy-request-1", db.preDibs.requests[1].requestId)
  end)

  it("defaults only missing optional structures in a truncated database", function()
    local source = { version = 6, settings = {} }
    local _, dibs = loader.load({ savedVariables = source })
    local db = dibs.GetDB()

    assert_not_nil(db.seasons)
    assert_not_nil(db.ledger.transactions)
    assert_not_nil(db.preDibs.requests)
    assert_not_nil(db.sync.peerStates)
  end)

  it("keeps nil optional fields valid without manufacturing a profile", function()
    local source = legacyGuild(6)
    source.currentSeasonId = nil
    source.profiles = nil
    local _, dibs = loader.load({ savedVariables = source })
    local db = dibs.GetDB()

    assert_nil(db.profiles)
    assert_false(hasQuarantine(_G.RCLootCouncil_dibsDB, "guilds[realm:testguild].currentSeasonId"))
    assert_equal("MIGRATABLE", dibs.GetPersistenceStatus().state)
  end)

  it("leaves a future schema untouched and exposes a read-only diagnostic", function()
    local source = currentRoot()
    source.schemaVersion = 999
    local _, dibs = loader.load({ savedVariables = source })
    local status = dibs.GetPersistenceStatus()

    assert_equal("FUTURE_UNSUPPORTED", status.state)
    assert_true(status.readOnly)
    assert_true(status.diagnostic:find("update RCLootCouncil_dibs", 1, true) ~= nil)
    assert_equal(source, _G.RCLootCouncil_dibsDB)
    assert_equal(999, _G.RCLootCouncil_dibsDB.schemaVersion)
  end)

  it("is idempotent after a completed migration and keeps one startup backup", function()
    local _, dibs = loader.load({ savedVariables = legacyGuild(1) })
    local root = _G.RCLootCouncil_dibsDB
    local backupId = root.persistenceRecovery.backups[1].backupId

    dibs.GetDB()
    assert_equal(1, #root.persistenceRecovery.backups)
    assert_equal(backupId, root.persistenceRecovery.backups[1].backupId)
    assert_equal("legacy-tx-1", dibs.GetDB().ledger.transactions["legacy-tx-1"].transactionId)
  end)

  it("does not commit a partial migration when the staged migration fails", function()
    local _, dibs = loader.load({ savedVariables = currentRoot() })
    local root = _G.RCLootCouncil_dibsDB
    local db = dibs.GetDB()
    db.version = 1
    local originalTransaction = db.ledger.transactions["legacy-tx-1"]
    dibs.Persistence.MigrateGuild = function() error("intentional migration failure") end

    dibs.GetDB()

    assert_equal(root, _G.RCLootCouncil_dibsDB)
    assert_equal(1, root.guilds["realm:testguild"].version)
    assert_equal(originalTransaction, root.guilds["realm:testguild"].ledger.transactions["legacy-tx-1"])
    assert_equal("RECOVERABLE_INVALID", dibs.GetPersistenceStatus().state)
    assert_true(dibs.GetPersistenceStatus().readOnly)
  end)

  it("preserves historical transaction identifiers and Pre-Dib history through migration", function()
    local source = legacyGuild(1)
    local _, dibs = loader.load({ savedVariables = source })
    local db = dibs.GetDB()

    assert_equal("legacy-tx-1", db.ledger.transactions["legacy-tx-1"].transactionId)
    assert_equal("legacy-request-1", db.preDibs.requests[1].requestId)
    assert_equal("Tester-Realm", db.preDibs.requests[1].playerName)
    assert_equal("Normal", db.preDibs.requests[1].difficulty)
  end)
end)
