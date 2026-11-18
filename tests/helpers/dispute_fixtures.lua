local M = {}

local function clone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[clone(key, seen)] = clone(item, seen) end
  return result
end

function M.captureAccountingState(dibs, _options, playerNames, seasonId, ledgerId)
  local db = dibs.GetDB and dibs.GetDB() or dibs.db or {}
  local ledgers = type(db.ledgers) == "table" and db.ledgers or {}
  local ledger = ledgers[ledgerId] or (ledgerId == "guild-primary" and db.ledger) or {}
  local balances = {}
  for _, name in ipairs(playerNames or {}) do
    balances[name] = dibs.Ledger.GetBalance(name, seasonId, ledgerId)
  end
  return {
    transactions = clone(ledger.transactions or {}),
    playerStates = clone(ledger.playerStates or {}),
    awardTransactions = clone(ledger.awardTransactions or {}),
    evidenceTransactions = clone(ledger.evidenceTransactions or {}),
    canonical = clone(ledger.canonical or {}),
    balances = balances,
  }
end

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

function M.newFailureInjector()
  local armedPoint, triggered = nil, {}
  return {
    Arm = function(_, point) armedPoint = point end,
    Hit = function(_, point)
      if armedPoint ~= point then return false end
      armedPoint = nil
      triggered[#triggered + 1] = point
      return true, { code = "INJECTED_TEST_FAILURE", point = point }
    end,
    Reset = function() armedPoint = nil; triggered = {} end,
    IsArmed = function() return armedPoint ~= nil end,
    GetTriggered = function() return triggered end,
  }
end

function M.getFailurePoints()
  return { "pre-validation", "pre-acceptance", "after-canonical-acceptance", "transaction-row:1",
    "transaction-row:2", "transaction-index", "balance" }
end

return M
