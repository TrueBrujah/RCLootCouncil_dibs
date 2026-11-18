--[[
Module: Dibs.Backup
Layer: Persistence safety
Purpose: Create bounded recovery snapshots before restore/import operations.
Responsibilities: Retention, checksums, preview, and explicit restore.
Non-responsibilities: It does not synchronize backups or infer business decisions.
Dependencies: ImportExport, Dibs.GetDB, Permissions.
Blizzard events: None directly.  Internal events/messages: None emitted.
SavedVariables: db.backups and db.backupRetention.
RCLootCouncil: Snapshot data can include RC reconciliation metadata, never live loot state.
Combat safety: Data-only, with UI invocation subject to officer/combat policy.
Invariants: Restore is explicit and bounded; DIBS-RULE-008. Restore never rolls back a
  shared revision chain (governance, policy, season catalog) or a more advanced ledger;
  the newer side is kept and sync fills the gap. Backups survive a factory reset.
Related docs: docs/developer/saved-variables.md, docs/officer/auditing.md.
]]

---@diagnostic disable: return-type-mismatch, redundant-return-value, undefined-field

local Dibs = _G.Dibs
Dibs.Backup = Dibs.Backup or {}
local M = Dibs.Backup
M.DEFAULT_RETENTION = 5
M.MAX_RETENTION = 25

local function clone(v) return Dibs.DeepCopy and Dibs.DeepCopy(v) or v end
local function ensure()
  local db = Dibs.GetDB(); db.backups = db.backups or {}; db.backupRetention = math.max(1, math.min(M.MAX_RETENTION, tonumber(db.backupRetention) or M.DEFAULT_RETENTION)); return db
end
local function authorized(scope, actor)
  if scope == "local" then return true end
  return Dibs.Permissions and Dibs.Permissions.Can and Dibs.Permissions.Can("settings.modify", actor) == true
end
local function audit(action, snapshot, outcome, reason, actor)
  local db = ensure(); db.auditLog = db.auditLog or {}; table.insert(db.auditLog, { auditId = Dibs.NewId("audit"), action = action, scope = snapshot and snapshot.scope, snapshotId = snapshot and snapshot.snapshotId, actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), createdAt = time(), outcome = outcome or "success", reason = reason })
end
local function revisionOf(state, field) return type(state) == "table" and tonumber(state[field]) or 0 end
-- Shared revision chains synchronize with the guild; restoring an older copy would
-- roll them back or fork them, so the newer side wins and sync fills any gap.
local SHARED_CHAINS = {
  { key = "governance", field = "revision" },
  { key = "operationalPolicy", field = "policyRevision" },
  { key = "seasonCatalog", field = "catalogRevision", companions = { "seasons", "currentSeasonId" } },
}
local function ledgerProgress(ledger)
  local canonical = type(ledger) == "table" and type(ledger.canonical) == "table" and ledger.canonical or {}
  local count = 0
  for _ in pairs(type(ledger) == "table" and type(ledger.transactions) == "table" and ledger.transactions or {}) do count = count + 1 end
  return tonumber(canonical.nextSeq) or 1, count, canonical.rootHash
end
local function keepNewerSharedState(db, live)
  local kept = {}
  for _, chain in ipairs(SHARED_CHAINS) do
    local liveRevision, restoredRevision = revisionOf(live[chain.key], chain.field), revisionOf(db[chain.key], chain.field)
    local diverged = liveRevision == restoredRevision and liveRevision > 0 and live[chain.key].hash ~= db[chain.key].hash
    if liveRevision > restoredRevision or diverged then
      db[chain.key] = live[chain.key]
      for _, companion in ipairs(chain.companions or {}) do db[companion] = live[companion] end
      kept[#kept + 1] = chain.key
    end
  end
  if type(live.ledgers) == "table" then
    if type(db.ledgers) ~= "table" then db.ledgers = {} end
    for ledgerId, ledger in pairs(live.ledgers) do
      local liveSeq, liveCount, liveRoot = ledgerProgress(ledger)
      local restoredSeq, restoredCount, restoredRoot = ledgerProgress(db.ledgers[ledgerId])
      if db.ledgers[ledgerId] == nil or liveSeq > restoredSeq
        or (liveSeq == restoredSeq and (liveRoot ~= restoredRoot or liveCount > restoredCount)) then
        if db.ledgers[ledgerId] ~= nil then kept[#kept + 1] = "ledger:" .. tostring(ledgerId) end
        db.ledgers[ledgerId] = ledger
      end
    end
  end
  if type(live.ledgerDeletionTombstones) == "table" then
    db.ledgerDeletionTombstones = db.ledgerDeletionTombstones or {}
    for ledgerId, tombstone in pairs(live.ledgerDeletionTombstones) do
      db.ledgerDeletionTombstones[ledgerId] = clone(tombstone)
      kept[#kept + 1] = "ledgerDeletion:" .. tostring(ledgerId)
    end
  end
  if type(live.governance) == "table" then
    db.governance = db.governance or {}
    for _, field in ipairs({ "ledgerDeletionRequests", "ledgerDeletionRecords" }) do
      if type(live.governance[field]) == "table" then
        db.governance[field] = db.governance[field] or {}
        for ledgerId, record in pairs(live.governance[field]) do
          db.governance[field][ledgerId] = clone(record)
        end
      end
    end
    db.governance.auditLog = db.governance.auditLog or {}
    for _, event in ipairs(live.governance.auditLog or {}) do
      if event.action == "LEDGER_DELETED" or event.action == "LEDGER_DELETION_AUTHORIZED" then
        local found = false
        for _, existing in ipairs(db.governance.auditLog) do
          if existing.action == event.action and existing.ledgerId == event.ledgerId then found = true; break end
        end
        if not found then table.insert(db.governance.auditLog, clone(event)) end
      end
    end
  end
  for ledgerId in pairs(db.ledgerDeletionTombstones or {}) do
    if ledgerId ~= "guild-primary" then
      if db.ledgers then db.ledgers[ledgerId] = nil end
      if db.activeLedgerId == ledgerId then db.activeLedgerId = "guild-primary" end
    end
  end
  if db.ledgers then db.ledger = db.ledgers[db.activeLedgerId or "guild-primary"] end
  if type(live.sync) == "table" then db.sync = live.sync end
  return kept
end
local function sizeOf(payload)
  if Dibs.ImportExport and Dibs.ImportExport.Export then
    local text = Dibs.ImportExport.Export("local", { actor = Dibs.GetPlayerName() }); return text and #text or 0
  end
  return 0
end
local function payloadChecksum(payload)
  local ie = Dibs.ImportExport
  if type(ie) ~= "table" or type(ie.Encode) ~= "function" or type(ie.Checksum) ~= "function" then return nil end
  local encoded = ie.Encode(payload)
  if type(encoded) ~= "string" then return nil end
  return ie.Checksum(encoded)
end
local function validateSnapshot(snapshot)
  if type(snapshot) ~= "table" or type(snapshot.payload) ~= "table" then return nil, "SNAPSHOT_PAYLOAD_MISSING" end
  if snapshot.scope ~= "local" and snapshot.scope ~= "guild" and snapshot.scope ~= "full" then return nil, "INVALID_SCOPE" end
  if snapshot.scope ~= "local" and snapshot.guildScope ~= Dibs.currentGuildKey then return nil, "CROSS_GUILD_RESTORE_BLOCKED" end

  if snapshot.packageChecksum == nil and snapshot.payloadChecksum == nil then return true end
  local ie = Dibs.ImportExport
  local originalText = snapshot.packageText
  if originalText ~= nil then
    if type(originalText) ~= "string" or type(ie) ~= "table" or type(ie.Decode) ~= "function" then
      return nil, "SNAPSHOT_PACKAGE_INVALID"
    end
    local package, reason = ie.Decode(originalText, { allowOversize = true, allowUnsafe = true })
    if not package then return nil, reason == "CHECKSUM_MISMATCH" and "SNAPSHOT_CHECKSUM_MISMATCH" or (reason or "SNAPSHOT_PACKAGE_INVALID") end
    if snapshot.packageChecksum and package.checksum ~= snapshot.packageChecksum then return nil, "SNAPSHOT_CHECKSUM_MISMATCH" end
    if package.scope ~= snapshot.scope or package.sourceGuild ~= snapshot.guildScope then return nil, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH" end
    local attestedPayload = payloadChecksum(package.payload)
    local currentPayload = payloadChecksum(snapshot.payload)
    if attestedPayload and currentPayload and attestedPayload ~= currentPayload then return nil, "SNAPSHOT_CHECKSUM_MISMATCH" end
  elseif snapshot.payloadChecksum == nil then
    return true
  end
  if snapshot.payloadChecksum then
    local actual = payloadChecksum(snapshot.payload)
    if not actual or actual ~= snapshot.payloadChecksum then return nil, "SNAPSHOT_CHECKSUM_MISMATCH" end
  end
  return true
end
---@param scope string|nil Snapshot scope.
---@param reason string|nil Why the snapshot was created.
---@param actor string Officer actor identity.
---@return DibsBackupSnapshot|nil snapshot
---@return table|string|nil prunedOrReason Pruned snapshot IDs or error code.
-- Side effects: Persists a bounded recovery snapshot before risky data operations.
function M.Create(scope, reason, actor)
  scope = scope or "full"; if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db = ensure(); if not Dibs.ImportExport or not Dibs.ImportExport.Export then return nil, "INVALID_SCOPE" end
  local packageText, package = Dibs.ImportExport.Export(scope, { actor = actor, reason = reason, allowOversize = true }); if not packageText then return nil, package end
  local payload = package.payload
  local retainedPackageText = #packageText <= Dibs.ImportExport.MAX_PACKAGE_SIZE and packageText or nil
  local compressedPackageText
  if not retainedPackageText and Dibs.BackupTransport and Dibs.BackupTransport.GetStatus().available then
    compressedPackageText = Dibs.BackupTransport.Wrap(packageText)
  end
  local snapshot = { snapshotId = Dibs.NewId("snapshot"), scope = scope, guildScope = Dibs.currentGuildKey, characterScope = Dibs.GetPlayerName and Dibs.GetPlayerName() or "UnknownPlayer", schemaVersion = Dibs.ImportExport.SCHEMA_VERSION, addonVersion = Dibs.VERSION, createdAt = time(), createdBy = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), size = #packageText, checksum = package.checksum, packageChecksum = package.checksum, packageText = retainedPackageText, payloadChecksum = payloadChecksum(payload), retentionState = "active", payload = clone(payload), reason = reason }
  snapshot.compressedPackageText = compressedPackageText
  table.insert(db.backups, snapshot); table.sort(db.backups, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
  local pruned = {}; while #db.backups > db.backupRetention do local old = table.remove(db.backups); old.retentionState = "pruned"; table.insert(pruned, old.snapshotId) end
  audit("backup_create", snapshot, "success", reason, actor); return clone(snapshot), pruned
end
function M.List(scope, actor)
  local db = ensure(); local result = {}
  for _, snapshot in ipairs(db.backups) do
    if (not scope or snapshot.scope == scope) and authorized(snapshot.scope, actor) then
      table.insert(result, clone(snapshot))
    end
  end
  return result
end
function M.GetSummary(scope, actor, dbOverride)
  local db = type(dbOverride) == "table" and dbOverride
    or (type(Dibs.GetDB) == "function" and Dibs.GetDB()) or nil
  local backups = type(db) == "table" and type(db.backups) == "table" and db.backups or {}
  local count, latest, canViewRestricted = 0, nil, nil
  for _, snapshot in ipairs(backups) do
    if type(snapshot) == "table" and (not scope or snapshot.scope == scope) then
      local allowed = snapshot.scope == "local"
      if not allowed then
        if canViewRestricted == nil then
          canViewRestricted = authorized(snapshot.scope, actor)
        end
        allowed = canViewRestricted
      end
      if allowed then
        count = count + 1
        if not latest then latest = snapshot end
      end
    end
  end
  return {
    count = count,
    available = latest ~= nil,
    createdAt = latest and latest.createdAt,
  }
end
function M.Get(snapshotId)
  local db = ensure(); for _, snapshot in ipairs(db.backups) do if snapshot.snapshotId == snapshotId then return snapshot end end; return nil
end
---@param snapshotId string Selected historical snapshot identifier.
---@param options table|nil Actor, sensitive-data confirmation and audit reason.
---@return string|nil originalText Original retained portable package.
---@return table|string|nil packageOrReason Validated package or rejection code.
---@return table|nil snapshot Selected stored snapshot on successful validation.
-- Export only existing attested text; never recapture live data or reconstruct provenance.
local function validateSnapshotExport(snapshotId, options)
  options = options or {}
  local db = Dibs.GetDB()
  local snapshot
  if type(snapshotId) == "string" and snapshotId ~= "" then
    for _, candidate in ipairs(type(db.backups) == "table" and db.backups or {}) do
      if type(candidate) == "table" and candidate.snapshotId == snapshotId then snapshot = candidate; break end
    end
  end
  if not snapshot then return nil, "SNAPSHOT_NOT_FOUND" end
  if snapshot.scope ~= "local" and snapshot.scope ~= "guild" and snapshot.scope ~= "full" then return nil, "INVALID_SCOPE" end
  local permissions, ie = Dibs.Permissions, Dibs.ImportExport
  if not permissions or type(permissions.CanonicalPlayerId) ~= "function" then return nil, "GUILD_ADMIN_REQUIRED" end
  local currentName = Dibs.GetPlayerName and Dibs.GetPlayerName()
  local currentId = permissions.CanonicalPlayerId(currentName)
  local currentGuid = permissions.CanonicalPlayerId(nil)
  if options.actor ~= nil then
    local actorId = permissions.CanonicalPlayerId(options.actor)
    local matchesGuid = type(actorId) == "string" and type(currentGuid) == "string"
      and string.lower(actorId) == string.lower(currentGuid)
    if not actorId or (actorId ~= currentId and not matchesGuid) then return nil, "ACTOR_MISMATCH" end
  end
  if not authorized(snapshot.scope, nil) then return nil, "GUILD_ADMIN_REQUIRED" end
  if snapshot.guildScope ~= Dibs.currentGuildKey then return nil, "CROSS_GUILD_EXPORT_BLOCKED" end
  if snapshot.scope == "local" and (type(currentName) ~= "string" or currentName == ""
    or type(snapshot.characterScope) ~= "string" or snapshot.characterScope == ""
    or not currentId or permissions.CanonicalPlayerId(snapshot.characterScope) ~= currentId) then
    return nil, "CHARACTER_SCOPE_MISMATCH"
  end
  if snapshot.scope == "full" and options.confirmedSensitive ~= true then return nil, "SENSITIVE_CONFIRMATION_REQUIRED" end
  if options.compressed == true and (not Dibs.BackupTransport or not Dibs.BackupTransport.GetStatus().available) then
    return nil, "COMPRESSION_UNAVAILABLE"
  end
  local originalText = snapshot.packageText
  if originalText == nil and snapshot.compressedPackageText ~= nil then
    if not Dibs.BackupTransport then return nil, "COMPRESSION_UNAVAILABLE" end
    local reason
    originalText, reason = Dibs.BackupTransport.Unwrap(snapshot.compressedPackageText)
    if not originalText then return nil, reason end
  end
  if type(originalText) ~= "string" or originalText == "" then return nil, "SNAPSHOT_PACKAGE_MISSING" end
  local expectedText = options.expectedPackageText
  if type(expectedText) == "string" and expectedText:sub(1, 10) == "DIBS-COMP-" then
    if not Dibs.BackupTransport then return nil, "COMPRESSION_UNAVAILABLE" end
    local reason
    expectedText, reason = Dibs.BackupTransport.Unwrap(expectedText)
    if not expectedText then return nil, reason end
  end
  if options.expectedPackageText ~= nil and expectedText ~= originalText then
    return nil, "SNAPSHOT_EXPORT_CHANGED"
  end
  if not ie or type(ie.Decode) ~= "function" or type(ie.Encode) ~= "function" or type(ie.Checksum) ~= "function" then
    return nil, "SNAPSHOT_PACKAGE_INVALID"
  end
  local limit = options.compressed == true and ie.MAX_BACKUP_SIZE or ie.MAX_PACKAGE_SIZE
  if #originalText > limit then return nil, "PACKAGE_TOO_LARGE" end
  if type(snapshot.packageChecksum) ~= "string" or type(snapshot.payloadChecksum) ~= "string" then
    return nil, "SNAPSHOT_ATTESTATION_MISSING"
  end
  local package, reason = ie.Decode(originalText, { allowOversize = options.compressed == true })
  if not package then return nil, reason end
  if package.scope ~= snapshot.scope or package.sourceGuild ~= snapshot.guildScope
    or package.schemaVersion ~= snapshot.schemaVersion or package.addonVersion ~= snapshot.addonVersion then
    return nil, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH"
  end
  if snapshot.scope == "local" and permissions.CanonicalPlayerId(package.sourceCharacter) ~= currentId then
    return nil, "CHARACTER_SCOPE_MISMATCH"
  end
  if type(snapshot.characterScope) ~= "string" or snapshot.characterScope == ""
    or type(package.sourceCharacter) ~= "string" or package.sourceCharacter == ""
    or permissions.CanonicalPlayerId(package.sourceCharacter) ~= permissions.CanonicalPlayerId(snapshot.characterScope) then
    return nil, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH"
  end
  if package.checksum ~= snapshot.packageChecksum
    or (snapshot.checksum ~= nil and package.checksum ~= snapshot.checksum) then return nil, "SNAPSHOT_CHECKSUM_MISMATCH" end
  if type(snapshot.payload) ~= "table" then return nil, "SNAPSHOT_PAYLOAD_MISSING" end
  local encodedPayload, encodedPackagePayload = ie.Encode(snapshot.payload), ie.Encode(package.payload)
  if not encodedPayload or not encodedPackagePayload or encodedPayload ~= encodedPackagePayload
    or ie.Checksum(encodedPayload) ~= snapshot.payloadChecksum then return nil, "SNAPSHOT_CHECKSUM_MISMATCH" end
  return originalText, package, snapshot
end
function M.ExportSnapshot(snapshotId, options)
  local text, package, snapshot = validateSnapshotExport(snapshotId, options)
  if not text then return nil, package end
  local transportInfo
  if options and options.compressed == true then
    if not Dibs.BackupTransport then return nil, "COMPRESSION_UNAVAILABLE" end
    text, transportInfo = Dibs.BackupTransport.Wrap(text)
    if not text then return nil, transportInfo end
  end
  audit("backup_export", snapshot, "success", options and options.reason, nil)
  return text, package, transportInfo
end
-- Read-only permission/integrity recheck for UI-held text; returns no package data.
function M.ValidateSnapshotExport(snapshotId, options)
  local text, package = validateSnapshotExport(snapshotId, options)
  if not text then return nil, package end
  return true
end
---@param snapshotId string Snapshot identifier.
---@param actor string Officer actor identity.
---@return table|nil preview Validated restore preview.
---@return string|nil reasonCode
function M.PreviewRestore(snapshotId, actor)
  local snapshot = M.Get(snapshotId); if not snapshot then return nil, "SNAPSHOT_NOT_FOUND" end
  if not authorized(snapshot.scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local valid, validationReason = validateSnapshot(snapshot); if not valid then return nil, validationReason end
  local preview = { previewId = Dibs.NewId("restore"), snapshotId = snapshotId, targetScope = snapshot.scope, strategy = "replace", additions = 0, changes = { "declared scope: " .. snapshot.scope }, omissions = {}, conflicts = {}, migrations = {}, sensitiveFields = snapshot.scope == "full" and { "ledger", "player identities" } or {}, expectedLedgerImpact = { replace = snapshot.scope == "full" and 1 or 0 }, createdAt = time(), actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), decision = "pending" }
  local db = ensure(); if type(db.pendingRestores) ~= "table" then db.pendingRestores = {} end
  db.pendingRestores[preview.previewId] = { preview = preview, snapshotId = snapshotId }
  Dibs.ImportExport.PrunePendingPreviews(db, "pendingRestores", preview.createdAt)
  audit("restore_preview", snapshot, "success", nil, actor); return preview
end
---@param previewId string Preview identifier.
---@param confirm boolean Explicit confirmation.
---@param reason string|nil Restore reason.
---@param actor string Officer actor identity.
---@return table|nil result Restore result or cancelled preview.
---@return string|nil reasonCode
-- Side effects: Restores a snapshot only after explicit preview and confirmation.
function M.Restore(previewId, confirm, reason, actor)
  local db = ensure(); local pending = Dibs.ImportExport.PrunePendingPreviews(db, "pendingRestores")[previewId]; if not pending then return nil, "PREVIEW_NOT_FOUND" end
  if confirm ~= true then
    pending.preview.decision = "cancelled"
    db.pendingRestores[previewId] = nil
    audit("restore_cancel", M.Get(pending.snapshotId), "success", reason, actor)
    return pending.preview
  end
  local snapshot = M.Get(pending.snapshotId)
  if not snapshot then return nil, "SNAPSHOT_NOT_FOUND" end
  if not authorized(snapshot.scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local valid, validationReason = validateSnapshot(snapshot); if not valid then return nil, validationReason end
  local safety, safetyReason = M.Create(snapshot.scope, "before-restore:" .. tostring(snapshot.snapshotId), actor); if not safety then return nil, safetyReason end
  local payload = snapshot.payload or {}
  local keptLocal = {}
  if snapshot.scope == "full" then
    local keep = { backups = db.backups, pendingRestores = db.pendingRestores, pendingImports = db.pendingImports, auditLog = db.auditLog, backupRetention = db.backupRetention }
    local live = {}
    for k, v in pairs(db) do live[k] = v end
    local staged = {}
    for key, value in pairs(payload) do staged[key] = clone(value) end
    keptLocal = keepNewerSharedState(staged, live)
    for key in pairs(db) do db[key] = nil end
    for key, value in pairs(staged) do db[key] = value end
    for key, value in pairs(keep) do db[key] = value end
  elseif snapshot.scope == "local" then
    db.settings = db.settings or {}; for k, v in pairs(payload.presentation or {}) do db.settings[k] = clone(v) end
  elseif snapshot.scope == "guild" then
    db.settings = db.settings or {}; for k, v in pairs(payload.settings or {}) do db.settings[k] = clone(v) end; db.rankRules = clone(payload.rankRules or db.rankRules); db.profiles = db.profiles or {}; db.profiles.guild = clone(payload.profiles or db.profiles.guild)
    -- A shared catalog only changes through published revisions; rewriting its
    -- projection here would later be republished as a rollback.
    if revisionOf(db.seasonCatalog, "catalogRevision") > 0 then keptLocal[#keptLocal + 1] = "seasonCatalog"
    else db.seasons = clone(payload.seasons or db.seasons) end
  else return nil, "INVALID_SCOPE" end
  if Dibs.Sync and Dibs.Sync.RecheckSyncBehind then Dibs.Sync.RecheckSyncBehind() end
  pending.preview.decision = "confirmed"; pending.preview.safetySnapshotId = safety.snapshotId; pending.preview.reason = reason; pending.preview.keptLocal = keptLocal; db.pendingRestores[previewId] = nil; audit("restore_apply", snapshot, "success", reason, actor); return pending.preview
end
function M.SetRetention(value, actor)
  if not authorized("guild", actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db = ensure(); db.backupRetention = math.max(1, math.min(M.MAX_RETENTION, math.floor(tonumber(value) or M.DEFAULT_RETENTION))); return db.backupRetention
end
M.CreateSnapshot = M.Create
M.ListSnapshots = M.List
M.Preview = M.PreviewRestore
M.RestoreSnapshot = M.Restore
return M
