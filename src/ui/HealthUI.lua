--[[
Module: Dibs.HealthUI
Layer: UI/domain projection
Purpose: Present a bounded Officer health report from existing runtime services.
Responsibilities: Normalize readiness, persistence, integration, sync, and backup status.
Non-responsibilities: It does not repair data, mutate settings, or expose raw records.
]]

local Dibs = _G.Dibs
Dibs.HealthUI = Dibs.HealthUI or {}

local HealthUI = Dibs.HealthUI
HealthUI.ANOMALY_EXPORT_PREFIX = "DIBS-HEALTH-1|"

local function isAdmin()
  local role = Dibs.Permissions and Dibs.Permissions.GetGuildRole
    and Dibs.Permissions.GetGuildRole(nil) or "player"
  return role == "gm" or role == "officer", role
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

local function addCheck(report, id, state, reason, detail)
  report.checks[#report.checks + 1] = {
    id = id,
    state = state,
    reason = reason,
    detail = detail,
  }
  if state == "blocked" then report.blockingCount = report.blockingCount + 1 end
  if state == "degraded" or state == "unavailable" then report.warningCount = report.warningCount + 1 end
end

local function normalizeReadiness(report, readiness)
  local state = readiness and readiness.status or "Unavailable"
  local normalized = string.lower(state) == "ready" and "ready"
    or (string.lower(state) == "blocked" and "blocked"
      or (string.lower(state) == "degraded" and "degraded" or "unavailable"))
  addCheck(report, "readiness", normalized, readiness and readiness.reasonCodes or "READINESS_UNAVAILABLE",
    "Current Dibs readiness and protected runtime context.")
  report.readiness = {
    status = state,
    checkedAt = readiness and readiness.checkedAt,
    mode = readiness and readiness.mode,
    context = readiness and readiness.context,
    probes = readiness and readiness.probes or {},
  }
end

function HealthUI.Evaluate(options)
  options = type(options) == "table" and options or {}
  local allowed, role = isAdmin()
  if not allowed and options.allowPlayer ~= true then
    return { status = "DENIED", role = role, checks = {}, warnings = {}, blockingCount = 0, warningCount = 0 }
  end

  local report = {
    status = "READY",
    role = role,
    version = tostring(Dibs.VERSION or "unknown"),
    checks = {},
    warnings = {},
    blockingCount = 0,
    warningCount = 0,
    privateData = false,
  }

  local persistence = safeCall(Dibs.GetPersistenceStatus) or { state = "UNAVAILABLE" }
  local persistenceState = persistence.readOnly and "blocked"
    or (persistence.state == "VALID" and "ready" or "degraded")
  addCheck(report, "persistence", persistenceState, persistence.state,
    persistence.diagnostic or "SavedVariables migration and recovery state.")
  report.persistence = {
    state = persistence.state,
    readOnly = persistence.readOnly == true,
    diagnostic = persistence.diagnostic,
  }

  local db = safeCall(Dibs.GetDB) or {}
  report.schemaVersion = tonumber(db.version)

  local readiness = safeCall(Dibs.Readiness and Dibs.Readiness.Evaluate, { allowPlayer = true })
  normalizeReadiness(report, readiness)

  local rc = safeCall(Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus) or { status = "absent" }
  local rcState = tostring(rc.status or rc.availability or "absent")
  local rcOutsideRaid = rc.reasonCode == "RC_MASTER_LOOTER_UNVERIFIABLE"
    and readiness and readiness.context and readiness.context.inRaid ~= true
  local rcCheckState = rcState == "operational" and "ready"
    or (rcOutsideRaid and "ready" or (rcState == "degraded" and "degraded" or "unavailable"))
  local rcReason = rcOutsideRaid and "RC_LOADED_NO_RAID_CONTEXT" or (rc.reasonCode or "RC_ABSENT")
  local rcDetail = rcOutsideRaid
    and "RCLootCouncil is installed and loaded; live award capability will be verified in a raid."
    or "Optional RCLootCouncil capability and current limitation."
  addCheck(report, "rclootcouncil", rcCheckState, rcReason, rcDetail)
  report.rclootcouncil = {
    status = rcState,
    reasonCode = rc.reasonCode,
    observedVersion = rc.observedVersion,
  }

  local sync = safeCall(Dibs.Sync and Dibs.Sync.GetStatus) or { state = "SYNC_UNAVAILABLE" }
  local syncState = sync.state == "SYNC_READY" and "ready"
    or (sync.state == "SYNC_BEHIND" and "degraded" or "unavailable")
  addCheck(report, "sync", syncState, sync.reason or sync.state,
    "Guild synchronization transport and recovery state.")
  report.sync = { state = sync.state, protocolState = sync.protocolState, syncBehind = sync.syncBehind == true }

  local backups = safeCall(Dibs.Backup and Dibs.Backup.List, nil, nil) or {}
  local latest = backups[1]
  addCheck(report, "backup", latest and "ready" or "degraded",
    latest and nil or "NO_BACKUP", latest and "Latest local backup is available." or "No local backup is available.")
  report.backup = {
    available = latest ~= nil,
    createdAt = latest and latest.createdAt,
    count = #backups,
  }

  for _, item in ipairs(report.checks) do
    if item.state ~= "ready" then
      report.warnings[#report.warnings + 1] = { id = item.id, reason = item.reason, detail = item.detail }
    end
  end
  if report.blockingCount > 0 then
    report.status = "BLOCKED"
  elseif report.warningCount > 0 then
    report.status = "DEGRADED"
  end
  return report
end

function HealthUI.ScanAnomalies(options)
  options = type(options) == "table" and options or {}
  local allowed = isAdmin()
  if not allowed and options.allowPlayer ~= true then return { status = "DENIED", anomalies = {} } end
  local db = safeCall(Dibs.GetDB) or {}
  local seasons = db.seasons or {}
  local anomalies = {}
  for id, transaction in pairs(db.ledger and db.ledger.transactions or {}) do
    if type(transaction) == "table" and transaction.seasonId and not seasons[transaction.seasonId] then
      anomalies[#anomalies + 1] = { id = "ledger-season-" .. tostring(id), category = "INVALID_SEASON_REFERENCE", recordId = tostring(id), seasonId = transaction.seasonId, action = "REVIEW_REQUIRED" }
    end
  end
  for index, acquisition in ipairs(db.preDibs and db.preDibs.acquisitions or {}) do
    if type(acquisition) ~= "table" or not acquisition.acquisitionId then
      anomalies[#anomalies + 1] = { id = "vault-identity-" .. tostring(index), category = "INCOMPLETE_ACQUISITION", recordId = tostring(index), action = "REVIEW_REQUIRED" }
    end
  end
  table.sort(anomalies, function(a, b) return a.id < b.id end)
  return { status = #anomalies == 0 and "HEALTHY" or "REVIEW_REQUIRED", anomalies = anomalies, count = #anomalies }
end

function HealthUI.BuildCorrectionPreview(anomalyId, options)
  local result = HealthUI.ScanAnomalies(options)
  if result.status == "DENIED" then return result end
  for _, anomaly in ipairs(result.anomalies) do
    if anomaly.id == anomalyId then
      return { status = "PREVIEW", anomaly = anomaly, backupRequired = true, mutation = "NONE", reason = "Append-only data requires an explicit Officer decision before correction." }
    end
  end
  return { status = "NOT_FOUND", anomalyId = anomalyId }
end

function HealthUI.ExportAnomalies(options)
  local report = HealthUI.ScanAnomalies(options)
  if report.status == "DENIED" then return nil, "GUILD_ADMIN_REQUIRED" end
  local encoder = Dibs.ImportExport and Dibs.ImportExport.Encode
  if type(encoder) ~= "function" then return nil, "ENCODER_UNAVAILABLE" end
  local encoded, reason = encoder({ format = "DIBS_DATA_HEALTH", version = 1, createdAt = time(), anomalies = report.anomalies })
  if not encoded then return nil, reason end
  return HealthUI.ANOMALY_EXPORT_PREFIX .. encoded:sub(#Dibs.ImportExport.PACKAGE_PREFIX + 1), report
end

HealthUI.GetReport = HealthUI.Evaluate

return HealthUI