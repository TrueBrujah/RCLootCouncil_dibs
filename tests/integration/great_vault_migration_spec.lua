local loader = require("helpers.load_addon")

describe("Great Vault migration", function()
  it("preserves legacy acquisitions and classifies missing evidence", function()
    local legacy = {
      version = 6,
      preDibs = {
        requests = {}, modePolicies = {}, acquisitions = {
          { acquisitionId = "legacy-kept", playerName = "Owner-Realm", itemID = 283201, source = "VAULT", acquiredAt = 1001 },
        },
      },
      ledger = { transactions = {}, playerStates = {}, awardTransactions = {}, evidenceTransactions = {} },
    }
    local _, dibs = loader.load({ savedVariables = legacy, wow = {
      guildName = "Legacy Guild", guildLeader = true, guildMembers = { "Tester-Realm", "Owner-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    local record = dibs.PreDibs.GetVaultAcquisition("legacy-kept")
    assert_not_nil(record)
    assert_equal("VAULT_LEGACY", record.source)
    assert_equal("LEGACY_RECORDED", record.verificationState)
    assert_equal("MISSING", record.evidenceState)
    assert_equal("legacy-kept", record.acquisitionId)
    local preview = dibs.OfficerUI.BuildVaultMigrationPreview()
    assert_equal(1, #preview.rows)
    assert_equal("LEGACY_RECORDED", preview.rows[1].projection.verificationState)
    assert_equal(1, #dibs.LogsUI.BuildVaultMigrationPreview().rows)
    for _, transaction in pairs(dibs.GetDB().ledger.transactions or {}) do
      assert_true(transaction.actionType ~= "DIB_USED")
    end
    assert_equal(7, dibs.GetDB().version)
    assert_not_nil(record.migration)
  end)

  it("does not remigrate an already upgraded record", function()
    local legacy = {
      version = 6,
      preDibs = { requests = {}, modePolicies = {}, acquisitions = {
        { acquisitionId = "legacy-repeat", playerName = "Owner-Realm", itemID = 283202, source = "MANUAL", claimedAt = 1002 },
      } },
    }
    local _, dibs = loader.load({ savedVariables = legacy, wow = { guildName = "Legacy Guild" } })
    local savedRoot = _G.RCLootCouncil_dibsDB
    local first = dibs.PreDibs.GetVaultAcquisition("legacy-repeat")
    local migratedAt = first.migration.migratedAt
    loader.load({ savedVariables = savedRoot, wow = { guildName = "Legacy Guild" } })
    local second = _G.Dibs.PreDibs.GetVaultAcquisition("legacy-repeat")
    assert_equal(migratedAt, second.migration.migratedAt)
    assert_equal("MANUAL", second.source)
  end)

  it("recovers future root schemas without modifying the saved data", function()
    local future = { schemaVersion = 99, guilds = {}, persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 } }
    local _, dibs = loader.load({ savedVariables = future, wow = { guildName = "Future Guild" } })
    assert_equal("FUTURE_UNSUPPORTED", dibs.GetPersistenceStatus().state)
    assert_equal(99, _G.RCLootCouncil_dibsDB.schemaVersion)
    assert_nil(_G.RCLootCouncil_dibsDB.guilds[dibs.GetGuildKey()])
  end)

  it("keeps migrated flat history in its original guild bucket", function()
    local legacy = {
      version = 6,
      preDibs = { requests = {}, modePolicies = {}, acquisitions = {
        { acquisitionId = "legacy-guild-scope", playerName = "Owner-Realm", itemID = 283203, source = "VAULT" },
      } },
    }
    local _, dibsA = loader.load({ savedVariables = legacy, wow = { guildName = "Legacy Guild" } })
    local savedRoot = _G.RCLootCouncil_dibsDB
    local guildKeyA = dibsA.currentGuildKey
    local _, dibsB = loader.load({ savedVariables = savedRoot, wow = { guildName = "Other Guild" } })
    assert_equal(0, #dibsB.PreDibs.GetAcquisitions())
    assert_equal(1, #savedRoot.guilds[guildKeyA].preDibs.acquisitions)
  end)
end)
