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

local SAFE_ACTIONS = {
  export = true, import_preview = true, import_cancel = true, import_apply = true,
  backup_create = true, restore_preview = true, restore_cancel = true, restore_apply = true,
  profile_create = true, profile_rename = true, profile_activate = true, profile_reset = true, profile_delete = true,
  ["great_vault.review"] = true, ["great_vault.conflict_review"] = true,
  ["eligibility.policy.set"] = true, ["eligibility.main.approve"] = true,
  ["eligibility.exception.create"] = true, ["eligibility.acquisition.record"] = true,
  ["eligibility.exception.consume"] = true,
  ["eligibility.relationship.APPROVED"] = true, ["eligibility.relationship.REJECTED"] = true,
  ["eligibility.relationship.PENDING"] = true, ["eligibility.relationship.REVOKED"] = true,
}

local SAFE_SCOPES = { ["local"] = true, guild = true, full = true, season = true }
local SAFE_OUTCOMES = { success = true, rejected = true, failed = true, cancelled = true }
local SAFE_TRANSACTION_TYPES = {
  SEASON_ALLOCATION = true, DIB_GRANTED = true, DIB_USED = true,
  DIB_REFUNDED = true, DIB_REVOKED = true, DIB_ADMIN_ADJUSTMENT = true,
}

local function safeValue(value, allowed, fallback)
  if type(value) == "string" and allowed[value] then return value end
  return fallback
end

local function authorized()
  local getGuildRole = Dibs.Permissions and Dibs.Permissions.GetGuildRole
  if type(getGuildRole) ~= "function" then return false end
  local ok, role = pcall(getGuildRole, nil)
  return ok and (role == "gm" or role == "officer")
end

local function getAuthorizedDB()
  if not authorized() then return nil, "GUILD_ADMIN_REQUIRED" end
  if type(Dibs.GetDB) ~= "function" then return nil, "DATABASE_UNAVAILABLE" end
  local ok, db = pcall(Dibs.GetDB)
  if not ok or type(db) ~= "table" then return nil, "DATABASE_UNAVAILABLE" end
  return db
end

local function copyEvent(event)
  event = type(event) == "table" and event or {}
  return {
    action = safeValue(event.action, SAFE_ACTIONS, "other"),
    scope = safeValue(event.scope, SAFE_SCOPES, "other"),
    outcome = safeValue(event.outcome, SAFE_OUTCOMES, "unknown"),
    createdAt = tonumber(event.createdAt or event.timestamp) or 0,
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
  local db, reason = getAuthorizedDB()
  if not db then return nil, reason end
  if options.seasonId ~= nil and type(options.seasonId) ~= "string" then
    return nil, "INVALID_SEASON"
  end
  local report = {
    format = "DIBS_ANONYMOUS_AUDIT",
    version = 1,
    createdAt = time(),
    addonVersion = tostring(Dibs.VERSION or "unknown"),
    seasonScoped = options.seasonId ~= nil,
    identityIncluded = false,
    executableTransactionsIncluded = false,
    eventCounts = {},
    transactionCounts = {},
    events = {},
  }

  local auditLog = type(db.auditLog) == "table" and db.auditLog or {}
  for index, event in ipairs(auditLog) do
    if index > M.MAX_EVENTS then break end
    local projected = copyEvent(event)
    report.events[#report.events + 1] = projected
    increment(report.eventCounts, projected.action)
  end
  report.truncatedEvents = math.max(0, #auditLog - M.MAX_EVENTS)
  report.eventCounts = sortedCounts(report.eventCounts)

  local transactions = type(db.ledger) == "table" and type(db.ledger.transactions) == "table"
    and db.ledger.transactions or {}
  for _, transaction in pairs(transactions) do
    if type(transaction) == "table"
      and (not options.seasonId or transaction.seasonId == options.seasonId) then
      local transactionType = safeValue(transaction.type or transaction.actionType, SAFE_TRANSACTION_TYPES, "OTHER")
      increment(report.transactionCounts, transactionType)
    end
  end
  report.transactionCounts = sortedCounts(report.transactionCounts)
  return report
end

function M.EncodeReport(options)
  local report, reportReason = M.BuildReport(options)
  if not report then return nil, reportReason end
  local encode = Dibs.ImportExport and Dibs.ImportExport.Encode
  if type(encode) ~= "function" then return nil, "ENCODER_UNAVAILABLE" end
  local encoded, reason = encode(report)
  local packagePrefix = Dibs.ImportExport and Dibs.ImportExport.PACKAGE_PREFIX
  if type(encoded) ~= "string" or type(packagePrefix) ~= "string"
    or encoded:sub(1, #packagePrefix) ~= packagePrefix then
    return nil, reason or "ENCODING_FAILED"
  end
  return M.PREFIX .. encoded:sub(#packagePrefix + 1), report
end

return M