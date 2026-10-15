local loader = require("helpers.load_addon")

describe("Anonymous audit export contract", function()
  it("projects audit facts without identities or executable transactions", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.auditLog = {
      { action = "export", scope = "full", outcome = "success", actor = "Player-Realm", reason = "private note", createdAt = 10 },
    }
    db.ledger.transactions = {
      one = { transactionId = "one", type = "DIB_USED", playerName = "Player-Realm", amount = -1, seasonId = "S1" },
    }
    local report = dibs.AuditExport.BuildReport({ seasonId = "S1" })
    assert_false(report.identityIncluded)
    assert_false(report.executableTransactionsIncluded)
    assert_equal(1, #report.events)
    assert_nil(report.events[1].actor)
    assert_nil(report.events[1].reason)
    assert_equal("DIB_USED", report.transactionCounts[1].key)
    assert_equal(1, report.transactionCounts[1].count)
  end)

  it("uses a non-importable audit prefix", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local encoded, report = dibs.AuditExport.EncodeReport()
    assert_not_nil(report)
    assert_true(encoded:sub(1, #dibs.AuditExport.PREFIX) == dibs.AuditExport.PREFIX)
    assert_false(encoded:sub(1, #dibs.ImportExport.PACKAGE_PREFIX) == dibs.ImportExport.PACKAGE_PREFIX)
  end)

  it("requires guild administration and does not echo a supplied season identifier", function()
    local _, playerDibs = loader.load({ wow = { guildLeader = false }, withAce3 = true })
    local denied, deniedReason = playerDibs.AuditExport.BuildReport()
    assert_nil(denied)
    assert_equal("GUILD_ADMIN_REQUIRED", deniedReason)
    local deniedExport, deniedExportReason = playerDibs.AuditExport.EncodeReport()
    assert_nil(deniedExport)
    assert_equal("GUILD_ADMIN_REQUIRED", deniedExportReason)

    local _, officerDibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local report = officerDibs.AuditExport.BuildReport({ seasonId = "Private Guild / Season Name" })
    assert_equal(true, report.seasonScoped)
    assert_nil(report.seasonId)
  end)

  it("replaces unrecognized event metadata with fixed anonymous values", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local db = dibs.GetDB()
    db.auditLog = {
      {
        action = "Player-Realm",
        scope = "Private Guild / Player-Realm",
        outcome = "private officer note",
        actor = "Player-Realm",
        reason = "Player-Realm private note",
        createdAt = 10,
      },
    }
    db.ledger.transactions = {
      one = { transactionId = "private-id", type = "Player-Realm", playerName = "Player-Realm", seasonId = "S1" },
    }

    local report = dibs.AuditExport.BuildReport()
    assert_equal("other", report.events[1].action)
    assert_equal("other", report.events[1].scope)
    assert_equal("unknown", report.events[1].outcome)
    assert_equal("OTHER", report.transactionCounts[1].key)
    local encoded = dibs.AuditExport.EncodeReport()
    assert_false(encoded:find("Player-Realm", 1, true) ~= nil)
    assert_false(encoded:find("Private Guild", 1, true) ~= nil)
    assert_false(encoded:find("private-id", 1, true) ~= nil)
  end)
end)