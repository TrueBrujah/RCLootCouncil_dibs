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
  if not allowed then
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

function HealthUI.ScanAnomalies()
  local allowed, role = isAdmin()
  if not allowed then
    return { status = "DENIED", role = role, anomalies = {}, count = 0, sources = {} }
  end
  local db
  local dbStatus = "UNAVAILABLE"
  if type(Dibs.GetDB) == "function" then
    local ok, value = pcall(Dibs.GetDB)
    if ok and type(value) == "table" then
      db, dbStatus = value, "AVAILABLE"
    elseif ok then
      dbStatus = "INVALID_SOURCE"
    else
      dbStatus = "SOURCE_ERROR"
    end
  end
  db = db or {}
  local seasons = type(db.seasons) == "table" and db.seasons or nil
  local transactions = type(db.ledger) == "table" and type(db.ledger.transactions) == "table"
    and db.ledger.transactions or nil
  local preDibsDB = type(db.preDibs) == "table" and db.preDibs or nil
  local acquisitions = preDibsDB and type(preDibsDB.acquisitions) == "table"
    and preDibsDB.acquisitions or nil
  local vaultConflicts
  if dbStatus == "AVAILABLE" and preDibsDB then
    if preDibsDB.ledgerStorageVersion == 1 then
      local ledgerId = tostring(db.activeLedgerId or "guild-primary")
      local ledgerStore = type(preDibsDB.ledgers) == "table" and preDibsDB.ledgers[ledgerId] or nil
      vaultConflicts = type(ledgerStore) == "table" and ledgerStore.vaultConflicts or nil
    else
      vaultConflicts = preDibsDB.vaultConflicts
    end
  end
  local sources = {
    ledger = { status = dbStatus == "AVAILABLE" and transactions and seasons and "AVAILABLE" or (dbStatus ~= "AVAILABLE" and dbStatus or "UNAVAILABLE") },
    acquisitions = { status = dbStatus == "AVAILABLE" and acquisitions and "AVAILABLE" or (dbStatus ~= "AVAILABLE" and dbStatus or "UNAVAILABLE") },
    vaultConflicts = { status = dbStatus == "AVAILABLE" and type(vaultConflicts) == "table" and "AVAILABLE" or (dbStatus ~= "AVAILABLE" and dbStatus or "UNAVAILABLE") },
  }
  local anomalies = {}
  local function addAnomaly(category, sourceId, action, detail)
    local detailKey = "HEALTH_REVIEW_DETAIL_" .. tostring(category)
    anomalies[#anomalies + 1] = {
      id = category .. ":" .. tostring(sourceId),
      category = category,
      status = "REVIEW_REQUIRED",
      action = action,
      detail = (Dibs.L and Dibs.L[detailKey]) or detail,
    }
  end
  local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
  end
  if transactions and seasons then
    for _, id in ipairs(sortedKeys(transactions)) do
      local transaction = transactions[id]
      if type(transaction) == "table" and transaction.seasonId and not seasons[transaction.seasonId] then
        addAnomaly("INVALID_SEASON_REFERENCE", id, "INVESTIGATE",
          "A ledger entry references a season that is not present.")
      end
    end
  end
  local acquisitionIds = {}
  if acquisitions then
    for _, index in ipairs(sortedKeys(acquisitions)) do
      local acquisition = acquisitions[index]
      local acquisitionId = type(acquisition) == "table" and tostring(acquisition.acquisitionId or "") or ""
      local itemID = type(acquisition) == "table" and tonumber(acquisition.itemID) or nil
      local incomplete = type(acquisition) ~= "table" or acquisitionId == ""
        or tostring(acquisition.playerName or "") == "" or not itemID or itemID <= 0
      if acquisitionId ~= "" then
        acquisitionIds[acquisitionId] = (acquisitionIds[acquisitionId] or 0) + 1
      end
      if incomplete then
        addAnomaly("INCOMPLETE_ACQUISITION", index, "OPEN_VAULT_REVIEW",
          "A Great Vault acquisition is missing required identity or item information.")
      else
        local verificationState = tostring(acquisition.verificationState or "")
        if verificationState == "UNVERIFIED" or verificationState == "MANUAL_RECORDED"
          or verificationState == "LEGACY_RECORDED" then
          addAnomaly("ACQUISITION_REVIEW_REQUIRED", acquisitionId, "OPEN_VAULT_REVIEW",
            "A Great Vault acquisition requires verification review.")
        end
      end
    end
    for _, acquisitionId in ipairs(sortedKeys(acquisitionIds)) do
      if acquisitionIds[acquisitionId] > 1 then
        addAnomaly("DUPLICATE_ACQUISITION", acquisitionId, "OPEN_VAULT_REVIEW",
          "Multiple Great Vault acquisitions share the same acquisition identity.")
      end
    end
  end
  if vaultConflicts then
    for _, index in ipairs(sortedKeys(vaultConflicts)) do
      local conflict = vaultConflicts[index]
      if type(conflict) == "table" and conflict.status == "REVIEW_REQUIRED" then
        addAnomaly("VAULT_CONFLICT", conflict.conflictId or index, "OPEN_VAULT_REVIEW",
          "A Great Vault synchronization conflict requires Officer review.")
      end
    end
  end
  table.sort(anomalies, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.id < b.id
  end)
  local unavailable = false
  for _, source in pairs(sources) do
    if source.status ~= "AVAILABLE" then unavailable = true; break end
  end
  local status = unavailable and "UNAVAILABLE" or (#anomalies == 0 and "HEALTHY" or "REVIEW_REQUIRED")
  return { status = status, anomalies = anomalies, count = #anomalies, sources = sources }
end

function HealthUI.BuildCorrectionPreview(anomalyId)
  local allowed, role = isAdmin()
  if not allowed then
    return { status = "DENIED", role = role, mutation = "NONE" }
  end
  local result = HealthUI.ScanAnomalies()
  if result.status == "DENIED" then return { status = "DENIED", role = result.role, mutation = "NONE" } end
  for _, anomaly in ipairs(result.anomalies) do
    if anomaly.id == anomalyId then
      return {
        status = "PREVIEW",
        finding = {
          id = anomaly.id,
          category = anomaly.category,
          status = anomaly.status,
          action = anomaly.action,
          detail = anomaly.detail,
        },
        nextAction = anomaly.action,
        mutation = "NONE",
      }
    end
  end
  if result.status == "UNAVAILABLE" then
    return { status = "UNAVAILABLE", mutation = "NONE", reason = "FINDINGS_SOURCE_UNAVAILABLE" }
  end
  return { status = "NOT_FOUND", anomalyId = anomalyId }
end

function HealthUI.ExportAnomalies(options)
  local report = HealthUI.ScanAnomalies(options)
  if report.status == "DENIED" then return nil, "GUILD_ADMIN_REQUIRED" end
  local encoder = Dibs.ImportExport and Dibs.ImportExport.Encode
  if type(encoder) ~= "function" then return nil, "ENCODER_UNAVAILABLE" end
  local categoryCounts, categoryKeys, sourceStatuses = {}, {}, {}
  for _, anomaly in ipairs(report.anomalies or {}) do
    categoryCounts[anomaly.category] = (categoryCounts[anomaly.category] or 0) + 1
  end
  for category in pairs(categoryCounts) do categoryKeys[#categoryKeys + 1] = category end
  table.sort(categoryKeys)
  local counts = {}
  for _, category in ipairs(categoryKeys) do
    counts[#counts + 1] = { category = category, count = categoryCounts[category] }
  end
  for source, value in pairs(report.sources or {}) do
    sourceStatuses[#sourceStatuses + 1] = { source = source, status = value.status }
  end
  table.sort(sourceStatuses, function(a, b) return a.source < b.source end)
  local db = safeCall(Dibs.GetDB) or {}
  local anonymousReport = {
    format = "DIBS_DATA_HEALTH",
    version = 1,
    createdAt = time(),
    addonVersion = tostring(Dibs.VERSION or "unknown"),
    schemaVersion = tonumber(db.version),
    scanStatus = report.status,
    sourceStatuses = sourceStatuses,
    totalCount = tonumber(report.count) or 0,
    categoryCounts = counts,
    identityIncluded = false,
    executableTransactionsIncluded = false,
  }
  local encoded, reason = encoder(anonymousReport)
  if not encoded then return nil, reason end
  return HealthUI.ANOMALY_EXPORT_PREFIX .. encoded:sub(#Dibs.ImportExport.PACKAGE_PREFIX + 1), anonymousReport
end

HealthUI.GetReport = HealthUI.Evaluate

return HealthUI