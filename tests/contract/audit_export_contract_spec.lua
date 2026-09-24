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
end)