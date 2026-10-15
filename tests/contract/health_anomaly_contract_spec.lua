local loader = require("helpers.load_addon")

describe("Health anomaly center contract", function()
  it("detects anomalies and creates a non-mutating correction preview", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.seasons = {}
    db.ledger.transactions = { broken = { transactionId = "broken", seasonId = "missing" } }
    local scan = dibs.HealthUI.ScanAnomalies()
    assert_equal("REVIEW_REQUIRED", scan.status)
    assert_equal(1, scan.count)
    local preview = dibs.HealthUI.BuildCorrectionPreview(scan.anomalies[1].id)
    assert_equal("PREVIEW", preview.status)
    assert_equal("NONE", preview.mutation)
    assert_not_nil(db.ledger.transactions.broken)
    local missingPreview = dibs.HealthUI.BuildCorrectionPreview("unknown-finding")
    assert_equal("NOT_FOUND", missingPreview.status)
  end)

  it("groups malformed, duplicate, and conflicting Vault findings without exposing source rows", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.seasons = {}
    db.ledger.transactions = {
      secretTransactionId = { transactionId = "secretTransactionId", seasonId = "missing" },
    }
    db.preDibs.acquisitions = {
      { playerName = "PrivatePlayer", itemID = 12345 },
      { acquisitionId = "duplicate-id", playerName = "PrivatePlayer", itemID = 12345, resetId = "reset-1" },
      { acquisitionId = "duplicate-id", playerName = "OtherPrivatePlayer", itemID = 12346, resetId = "reset-1" },
    }
    local conflicts = dibs.PreDibs.GetVaultConflicts()
    conflicts[1] = {
      conflictId = "private-conflict-id", acquisitionId = "duplicate-id", status = "REVIEW_REQUIRED",
      current = { playerName = "PrivatePlayer", evidence = "private-evidence" },
      incoming = { playerName = "OtherPrivatePlayer", evidence = "private-evidence" },
    }
    local conflictStore = db.preDibs.ledgers["guild-primary"].vaultConflicts
    local ledgerStorageVersion = db.preDibs.ledgerStorageVersion

    local scan = dibs.HealthUI.ScanAnomalies()
    local categories = {}
    for _, finding in ipairs(scan.anomalies) do
      categories[finding.category] = (categories[finding.category] or 0) + 1
      assert_not_nil(finding.id)
      assert_not_nil(finding.detail)
      assert_nil(finding.record)
      assert_nil(finding.evidence)
    end
    assert_equal("REVIEW_REQUIRED", scan.status)
    assert_equal(1, categories.INVALID_SEASON_REFERENCE)
    assert_equal(1, categories.INCOMPLETE_ACQUISITION)
    assert_equal(1, categories.DUPLICATE_ACQUISITION)
    assert_equal(1, categories.VAULT_CONFLICT)
    assert_equal("AVAILABLE", scan.sources.vaultConflicts.status)
    assert_equal(conflictStore, db.preDibs.ledgers["guild-primary"].vaultConflicts)
    assert_equal(ledgerStorageVersion, db.preDibs.ledgerStorageVersion)
  end)

  it("marks an unavailable findings source instead of reporting a clean scan", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.activeLedgerId = "guild-primary"
    db.preDibs.ledgerStorageVersion = 1
    db.preDibs.ledgers = { ["guild-primary"] = {} }
    db.preDibs.vaultConflicts = nil

    local scan = dibs.HealthUI.ScanAnomalies()

    assert_equal("UNAVAILABLE", scan.status)
    assert_equal("UNAVAILABLE", scan.sources.vaultConflicts.status)
  end)

  it("denies the scan to a non-administrator without returning findings", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.Permissions.GetGuildRole = function() return "player" end

    local scan = dibs.HealthUI.ScanAnomalies()

    assert_equal("DENIED", scan.status)
    assert_equal(0, scan.count)
    assert_equal(0, #scan.anomalies)
  end)

  it("rechecks authority when previewing a finding", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.seasons = {}
    db.ledger.transactions = { broken = { transactionId = "broken", seasonId = "missing" } }
    local findingId = dibs.HealthUI.ScanAnomalies().anomalies[1].id
    dibs.Permissions.GetGuildRole = function() return "player" end

    local preview = dibs.HealthUI.BuildCorrectionPreview(findingId)

    assert_equal("DENIED", preview.status)
    assert_equal("NONE", preview.mutation)
  end)

  it("exports anomaly reports without making them import packages", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local encoded, report = dibs.HealthUI.ExportAnomalies()
    assert_not_nil(report)
    assert_true(encoded:sub(1, #dibs.HealthUI.ANOMALY_EXPORT_PREFIX) == dibs.HealthUI.ANOMALY_EXPORT_PREFIX)
    assert_false(encoded:sub(1, #dibs.ImportExport.PACKAGE_PREFIX) == dibs.ImportExport.PACKAGE_PREFIX)
  end)

  it("exports only aggregate counts and excludes guild identities and record IDs", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.seasons = {}
    db.ledger.transactions = {
      privateTxn42 = { transactionId = "privateTxn42", seasonId = "missing", playerName = "PrivatePlayer" },
    }
    db.preDibs.acquisitions = {
      {
        acquisitionId = "privateAcquisition42", playerName = "PrivatePlayer", itemID = 45678,
        verificationState = "MANUAL_RECORDED", evidence = "private-evidence",
      },
    }
    local beforeTransactions = db.ledger.transactions.privateTxn42
    local beforeAcquisition = db.preDibs.acquisitions[1]

    local encoded, report = dibs.HealthUI.ExportAnomalies()

    assert_not_nil(encoded)
    assert_equal("DIBS_DATA_HEALTH", report.format)
    assert_equal(2, report.totalCount)
    assert_equal(nil, report.anomalies)
    assert_equal(false, report.identityIncluded)
    assert_equal(false, report.executableTransactionsIncluded)
    assert_false(encoded:find("PrivatePlayer", 1, true) ~= nil)
    assert_false(encoded:find("privateTxn42", 1, true) ~= nil)
    assert_false(encoded:find("privateAcquisition42", 1, true) ~= nil)
    assert_false(encoded:find("private-evidence", 1, true) ~= nil)
    assert_equal(beforeTransactions, db.ledger.transactions.privateTxn42)
    assert_equal(beforeAcquisition, db.preDibs.acquisitions[1])
  end)

  it("returns explicit export failures for denied authority and missing encoders", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.Permissions.GetGuildRole = function() return "player" end
    local denied, deniedReason = dibs.HealthUI.ExportAnomalies()
    assert_nil(denied)
    assert_equal("GUILD_ADMIN_REQUIRED", deniedReason)

    dibs.Permissions.GetGuildRole = function() return "gm" end
    dibs.ImportExport.Encode = nil
    local unavailable, unavailableReason = dibs.HealthUI.ExportAnomalies()
    assert_nil(unavailable)
    assert_equal("ENCODER_UNAVAILABLE", unavailableReason)
  end)

  it("scans a representative large guild fixture within the review budget", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.seasons = {}
    db.ledger.transactions = {}
    db.preDibs.acquisitions = {}
    for index = 1, 5000 do
      db.ledger.transactions["txn-" .. tostring(index)] = { seasonId = "missing" }
    end
    for index = 1, 1000 do
      db.preDibs.acquisitions[index] = { playerName = "SyntheticPlayer", itemID = 12345 }
    end
    local startedAt = os.clock()

    local scan = dibs.HealthUI.ScanAnomalies()
    local elapsed = os.clock() - startedAt

    assert_equal(6000, scan.count)
    assert_true(elapsed < 2, "Large health scan took " .. tostring(elapsed) .. " seconds.")
  end)
end)