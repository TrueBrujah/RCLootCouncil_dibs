local loader = require("helpers.load_addon")

describe("Ledger recent transaction projection", function()
  it("returns only the newest bounded matching rows and defensive copies", function()
    local _, dibs = loader.load({ withAce3 = true })
    local transactions = {
      old = { transactionId = "old", seasonId = "S1", playerName = "Member-Realm", createdAt = 1 },
      recentA = { transactionId = "recent-a", seasonId = "S1", playerName = "Member-Realm", createdAt = 8 },
      recentB = { transactionId = "recent-b", seasonId = "S1", playerName = "Member-Realm", createdAt = 10 },
      hidden = { transactionId = "hidden", seasonId = "S1", playerName = "Former-Realm", createdAt = 12 },
      otherSeason = { transactionId = "other", seasonId = "S2", playerName = "Member-Realm", createdAt = 15 },
    }
    dibs.GetDB().ledger.transactions = transactions

    local rows = dibs.Ledger.GetRecentTransactions("S1", 2, nil, function(tx)
      return tx.playerName == "Member-Realm"
    end)

    assert_equal(2, #rows)
    assert_equal("recent-b", rows[1].transactionId)
    assert_equal("recent-a", rows[2].transactionId)
    rows[1].reason = "changed copy"
    assert_nil(transactions.recentB.reason)
  end)
end)
