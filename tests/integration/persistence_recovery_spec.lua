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
    guilds = { ["realm:testguild"] = guild or legacyGuild(8) },
    persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
  }
end

local function hasQuarantine(root, scope, original)
  for _, entry in ipairs(root.persistenceRecovery.quarantine or {}) do
    if entry.scope == scope and (original == nil or entry.original == original) then return true end
  end
  return false
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

  it("adds the seasonal roster subtree without changing existing or historical guild data", function()
    local source = currentRoot()
    local existingGuild = source.guilds["realm:testguild"]
    existingGuild.seasonalRoster = {
      schema = 1,
      seasons = { ["season-legacy"] = { seasonId = "season-legacy", revision = 3,
        revisions = { ["1"] = { identitySeasonId = "dibs-old-id" } },
        enrollments = { enrollmentA = { enrollmentId = "enrollmentA" } } } },
      auditLog = { { eventId = "event-1", action = "ENROLLMENT_CREATED" } },
    }
    source.guilds["realm:oldguild"] = { version = 7, seasons = { preserved = { id = "preserved" } }, marker = "historical" }
    local rosterBefore = existingGuild.seasonalRoster
    local oldGuildBefore = source.guilds["realm:oldguild"]

    local _, dibs = loader.load({ savedVariables = source })
    local db = dibs.GetDB()

    assert_equal("MIGRATABLE", dibs.GetPersistenceStatus().state)
    assert_equal(2, db.seasonalRoster.schema)
    assert_equal(rosterBefore.seasons["season-legacy"].revision, db.seasonalRoster.seasons["season-legacy"].revision)
    assert_equal("season-legacy", db.seasonalRoster.seasonAliases.records["season-legacy"].canonicalSeasonId)
    assert_equal("dibs-old-id", db.seasonalRoster.seasonAliases.records["season-legacy"].legacyDibsSeasonIds[1])
    assert_equal("event-1", db.seasonalRoster.auditLog[1].eventId)
    assert_equal("historical", _G.RCLootCouncil_dibsDB.guilds["realm:oldguild"].marker)
    assert_equal(oldGuildBefore.seasons.preserved.id, _G.RCLootCouncil_dibsDB.guilds["realm:oldguild"].seasons.preserved.id)
  end)

  it("preserves a future seasonal-roster schema for fail-closed service handling", function()
    local source = currentRoot()
    source.guilds["realm:testguild"].seasonalRoster = {
      schema = 99,
      marker = "must-not-be-downgraded",
      opaque = { nested = true },
    }
    local _, dibs = loader.load({ savedVariables = source })

    assert_equal(99, dibs.GetDB().seasonalRoster.schema)
    assert_equal("must-not-be-downgraded", dibs.GetDB().seasonalRoster.marker)
    assert_true(dibs.GetDB().seasonalRoster.opaque.nested)
  end)

  it("migrates every supported historical guild schema deterministically", function()
    for version = 1, 7 do
      local _, dibs = loader.load({ savedVariables = legacyGuild(version) })
      local db = dibs.GetDB()
      assert_equal(8, db.version, "schema " .. tostring(version))
      assert_equal("legacy-tx-1", db.ledger.transactions["legacy-tx-1"].transactionId)
      assert_equal("legacy-request-1", db.preDibs.requests[1].requestId)
      assert_equal(3, db.disputes.version)
      assert_not_nil(db.disputes.operationStates)
      assert_equal("MIGRATABLE", dibs.GetPersistenceStatus().state)
    end
  end)

  it("adds the dispute operation projection without rewriting schema-7 history", function()
    local source = legacyGuild(7)
    source.disputes = {
      version = 2,
      requests = { { requestId = "old-request" } },
      order = { "old-request" },
      corrections = { oldCorrection = { correctionKey = "legacy-key", status = "APPLIED" } },
    }
    source.ledger.canonical = {
      schema = 1, epoch = 4, nextSeq = 3, rootHash = "root-2",
      commits = { ["4:1"] = { commitHash = "commit-1" }, ["4:2"] = { commitHash = "commit-2" } },
      positions = { ["4:1"] = "commit-1", ["4:2"] = "commit-2" },
      transactionIndex = { ["legacy-tx-1"] = "4:1" },
    }
    local _, dibs = loader.load({ savedVariables = source })
    local db = dibs.GetDB()

    assert_equal(8, db.version)
    assert_equal(3, db.disputes.version)
    assert_equal("legacy-key", db.disputes.corrections.oldCorrection.correctionKey)
    assert_equal("commit-1", db.ledger.canonical.commits["4:1"].commitHash)
    assert_equal("commit-2", db.ledger.canonical.commits["4:2"].commitHash)
    assert_equal("root-2", db.ledger.canonical.rootHash)
    assert_equal(3, db.ledger.canonical.nextSeq)
    assert_equal("4:1", db.ledger.canonical.transactionIndex["legacy-tx-1"])
    assert_not_nil(db.disputes.operationStates)
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

  it("avoids recopying the root for a future guild schema while remaining read-only", function()
    local source = currentRoot(legacyGuild(9))
    local _, dibs = loader.load({ savedVariables = source })
    assert_equal("FUTURE_UNSUPPORTED", dibs.GetPersistenceStatus().state)
    assert_true(dibs.GetPersistenceStatus().readOnly)

    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    dibs.GetDB()
    dibs.GetDB()
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Core data" then measured[entry.page] = entry.count end
    end
    assert_equal(2, measured["get-db-future-guild-schema"])
    assert_nil(measured["get-db-root-copy"], "future-schema checks should not clone the full root")
    assert_equal(source, _G.RCLootCouncil_dibsDB)
    assert_equal(9, source.guilds["realm:testguild"].version)
    assert_equal("FUTURE_UNSUPPORTED", dibs.GetPersistenceStatus().state)
    assert_true(dibs.GetPersistenceStatus().readOnly)
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

  it("leaves unrecoverable canonical history untouched during startup recovery", function()
    local source = currentRoot()
    local ledger = source.guilds["realm:testguild"].ledger
    ledger.canonical = {
      schema = 1,
      epoch = 7,
      nextSeq = 2,
      rootHash = "unverifiable-root",
      commits = {},
      transactionIndex = {},
      positions = {},
    }
    local _, dibs = loader.load({ savedVariables = source, skipInitialize = true })
    local db = dibs.GetDB()
    local canonicalBefore = dibs.DeepCopy(db.ledger.canonical)
    local transactionsBefore = dibs.DeepCopy(db.ledger.transactions)

    assert_true(dibs.Initialize())

    assert_equal("CANONICAL_SEQUENCE_GAP", dibs.canonicalOperationRecoveryStatus.reasonCode)
    assert_true(sameValue(canonicalBefore, db.ledger.canonical),
      "startup modified unrecoverable canonical history or its indexes")
    assert_true(sameValue(transactionsBefore, db.ledger.transactions),
      "startup modified transaction projections for unrecoverable history")
  end)

  it("records an explicit recovery-unavailable diagnostic when Disputes is missing", function()
    local _, dibs = loader.load({ savedVariables = currentRoot(), skipInitialize = true })
    dibs.Disputes = nil

    assert_true(dibs.Initialize())

    assert_equal("CANONICAL_RECOVERY_UNAVAILABLE", dibs.canonicalOperationRecoveryStatus.reasonCode)
  end)

  it("fails closed when startup recovery returns no verifiable result", function()
    local _, dibs = loader.load({ savedVariables = currentRoot(), skipInitialize = true })
    dibs.Disputes.ReconstructOperationStates = function() return nil end
    assert_true(dibs.Initialize())
    assert_false(dibs.canonicalOperationRecoveryStatus.rebuilt)
    assert_equal("CANONICAL_RECOVERY_FAILED", dibs.canonicalOperationRecoveryStatus.reasonCode)
    assert_equal("guild-primary", dibs.canonicalOperationRecoveryStatus.ledgerId)
    assert_equal(dibs.GetGuildKey(), dibs.canonicalOperationRecoveryStatus.guildKey)
  end)

  it("records successful validation of an empty canonical history at startup", function()
    local _, dibs = loader.load({ savedVariables = currentRoot(), skipInitialize = true })
    local canonical = assert(dibs.Ledger.GetCanonicalState("guild-primary"))
    local nextSeq, rootHash = canonical.nextSeq, canonical.rootHash

    assert_true(dibs.Initialize())

    assert_true(dibs.canonicalOperationRecoveryStatus.rebuilt)
    assert_equal("OPERATION_STATES_REBUILT", dibs.canonicalOperationRecoveryStatus.reasonCode)
    assert_equal(nextSeq, dibs.Ledger.GetCanonicalState("guild-primary").nextSeq)
    assert_equal(rootHash, dibs.Ledger.GetCanonicalState("guild-primary").rootHash)
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
