local M = {}

function M.assertRequest(request, playerName, itemID, seasonID, status)
  assert_not_nil(request)
  assert_equal(playerName, request.playerName)
  assert_equal(itemID, request.itemID)
  assert_equal(seasonID, request.seasonId)
  assert_equal(status, request.status)
end

function M.assertLedgerCount(dibs, expected)
  assert_equal(expected, #dibs.Ledger.GetAllTransactions())
end

return M