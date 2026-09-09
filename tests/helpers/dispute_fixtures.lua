local M = {}

function M.transaction(playerName, seasonId, overrides)
  local value = {
    transactionId = "tx-fixture-" .. tostring(playerName or "player"),
    playerName = playerName or "Tester-Realm",
    seasonId = seasonId or "season-fixture",
    type = "DIB_USED",
    amount = -1,
    itemID = 19019,
    itemLink = "|Hitem:19019::::::::::::|h[Fixture Item]|h|r",
    awardRef = "history:fixture-award",
    response = "DIB",
    sourceStatus = "awarded",
    createdAt = 1700000000,
    reason = "Fixture award",
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

function M.report(category, overrides)
  local value = {
    category = category or "other",
    note = "Fixture report",
    itemID = 19019,
    itemName = "Fixture Item",
    source = "dibs",
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

return M
