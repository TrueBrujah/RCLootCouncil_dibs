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
    db.ledger = db.ledgers[db.activeLedgerId or "guild-primary"] or db.ledger
  end
  if type(live.sync) == "table" then db.sync = live.sync end
  return kept
end
local function sizeOf(payload)
  if Dibs.ImportExport and Dibs.ImportExport.Export then
    local text = Dibs.ImportExport.Export("local", { actor = Dibs.GetPlayerName() }); return text and #text or 0
  end
  return 0
end
---@param scope string|nil Snapshot scope.
---@param reason string|nil Why the snapshot was created.
---@param actor string Officer actor identity.
---@return DibsBackupSnapshot|nil snapshot
---@return table|string|nil prunedOrReason Pruned snapshot IDs or error code.
-- Side effects: Persists a bounded recovery snapshot before risky data operations.
function M.Create(scope, reason, actor)
  scope = scope or "full"; if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db = ensure(); local payload = Dibs.ImportExport and Dibs.ImportExport.GetPayload and Dibs.ImportExport.GetPayload(scope)
  if not payload then return nil, "INVALID_SCOPE" end
  local packageText, package = Dibs.ImportExport.Export(scope, { actor = actor, reason = reason, allowOversize = true }); if not packageText then return nil, package end
  local snapshot = { snapshotId = Dibs.NewId("snapshot"), scope = scope, guildScope = Dibs.currentGuildKey, characterScope = Dibs.GetPlayerName and Dibs.GetPlayerName() or "UnknownPlayer", schemaVersion = Dibs.ImportExport.SCHEMA_VERSION, addonVersion = Dibs.VERSION, createdAt = time(), createdBy = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), size = #packageText, checksum = package.checksum, retentionState = "active", payload = clone(payload), reason = reason }
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
function M.Get(snapshotId)
  local db = ensure(); for _, snapshot in ipairs(db.backups) do if snapshot.snapshotId == snapshotId then return snapshot end end; return nil
end
---@param snapshotId string Snapshot identifier.
---@param actor string Officer actor identity.
---@return table|nil preview Validated restore preview.
---@return string|nil reasonCode
function M.PreviewRestore(snapshotId, actor)
  local snapshot = M.Get(snapshotId); if not snapshot then return nil, "SNAPSHOT_NOT_FOUND" end
  if not authorized(snapshot.scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local preview = { previewId = Dibs.NewId("restore"), snapshotId = snapshotId, targetScope = snapshot.scope, strategy = "replace", additions = 0, changes = { "declared scope: " .. snapshot.scope }, omissions = {}, conflicts = {}, migrations = {}, sensitiveFields = snapshot.scope == "full" and { "ledger", "player identities" } or {}, expectedLedgerImpact = { replace = snapshot.scope == "full" and 1 or 0 }, createdAt = time(), actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), decision = "pending" }
  local db = ensure(); db.pendingRestores = db.pendingRestores or {}; db.pendingRestores[preview.previewId] = { preview = preview, snapshot = snapshot }; audit("restore_preview", snapshot, "success", nil, actor); return preview
end
---@param previewId string Preview identifier.
---@param confirm boolean Explicit confirmation.
---@param reason string|nil Restore reason.
---@param actor string Officer actor identity.
---@return table|nil result Restore result or cancelled preview.
---@return string|nil reasonCode
-- Side effects: Restores a snapshot only after explicit preview and confirmation.
function M.Restore(previewId, confirm, reason, actor)
  local db = ensure(); local pending = db.pendingRestores and db.pendingRestores[previewId]; if not pending then return nil, "PREVIEW_NOT_FOUND" end
  if confirm ~= true then pending.preview.decision = "cancelled"; audit("restore_cancel", pending.snapshot, "success", reason, actor); return pending.preview end
  local snapshot = pending.snapshot; if not authorized(snapshot.scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local safety, safetyReason = M.Create(snapshot.scope, "before-restore:" .. tostring(snapshot.snapshotId), actor); if not safety then return nil, safetyReason end
  local payload = snapshot.payload or {}
  local keptLocal = {}
  if snapshot.scope == "full" then
    local keep = { backups = db.backups, pendingRestores = db.pendingRestores, pendingImports = db.pendingImports, auditLog = db.auditLog, backupRetention = db.backupRetention }
    local live = {}
    for k, v in pairs(db) do live[k] = v end
    for k in pairs(db) do db[k] = nil end; for k, v in pairs(keep) do db[k] = v end; for k, v in pairs(payload) do db[k] = clone(v) end
    keptLocal = keepNewerSharedState(db, live)
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
