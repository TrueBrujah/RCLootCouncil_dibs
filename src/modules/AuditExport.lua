--[[
Module: Dibs.AuditExport
Layer: Read-only audit projection
Purpose: Build a bounded, anonymous report for support and guild review.
Non-responsibilities: It never imports, mutates SavedVariables, or exports identities.
]]

local Dibs = _G.Dibs
Dibs.AuditExport = Dibs.AuditExport or {}

local M = Dibs.AuditExport
M.PREFIX = "DIBS-AUDIT-1|"
M.MAX_EVENTS = 500

local function copyEvent(event)
  return {
    action = tostring(event.action or "unknown"),
    scope = tostring(event.scope or "unknown"),
    outcome = tostring(event.outcome or "unknown"),
    createdAt = tonumber(event.createdAt) or 0,
  }
end

local function increment(map, key)
  key = tostring(key or "unknown")
  map[key] = (map[key] or 0) + 1
end

local function sortedCounts(map)
  local rows = {}
  for key, value in pairs(map) do rows[#rows + 1] = { key = key, count = value } end
  table.sort(rows, function(a, b) return a.key < b.key end)
  return rows
end

function M.BuildReport(options)
  options = type(options) == "table" and options or {}
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  local report = {
    format = "DIBS_ANONYMOUS_AUDIT",
    version = 1,
    createdAt = time(),
    addonVersion = tostring(Dibs.VERSION or "unknown"),
    seasonId = options.seasonId,
    identityIncluded = false,
    executableTransactionsIncluded = false,
    eventCounts = {},
    transactionCounts = {},
    events = {},
  }

  for index, event in ipairs(db.auditLog or {}) do
    if index > M.MAX_EVENTS then break end
    local projected = copyEvent(event)
    report.events[#report.events + 1] = projected
    increment(report.eventCounts, projected.action)
  end
  report.eventCounts = sortedCounts(report.eventCounts)

  local transactions = db.ledger and db.ledger.transactions or {}
  for _, transaction in pairs(transactions) do
    if type(transaction) == "table"
      and (not options.seasonId or transaction.seasonId == options.seasonId) then
      increment(report.transactionCounts, transaction.type or transaction.actionType)
    end
  end
  report.transactionCounts = sortedCounts(report.transactionCounts)
  return report
end

function M.EncodeReport(options)
  local report = M.BuildReport(options)
  local encode = Dibs.ImportExport and Dibs.ImportExport.Encode
  if type(encode) ~= "function" then return nil, "ENCODER_UNAVAILABLE" end
  local encoded, reason = encode(report)
  if not encoded then return nil, reason end
  return M.PREFIX .. encoded:sub(#Dibs.ImportExport.PACKAGE_PREFIX + 1), report
end

return M