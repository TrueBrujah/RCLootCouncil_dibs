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
local function sizeOf(payload)
  if Dibs.ImportExport and Dibs.ImportExport.Export then
    local text = Dibs.ImportExport.Export("local", { actor = Dibs.GetPlayerName() }); return text and #text or 0
  end
  return 0
end
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
function M.PreviewRestore(snapshotId, actor)
  local snapshot = M.Get(snapshotId); if not snapshot then return nil, "SNAPSHOT_NOT_FOUND" end
  if not authorized(snapshot.scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local preview = { previewId = Dibs.NewId("restore"), snapshotId = snapshotId, targetScope = snapshot.scope, strategy = "replace", additions = 0, changes = { "declared scope: " .. snapshot.scope }, omissions = {}, conflicts = {}, migrations = {}, sensitiveFields = snapshot.scope == "full" and { "ledger", "player identities" } or {}, expectedLedgerImpact = { replace = snapshot.scope == "full" and 1 or 0 }, createdAt = time(), actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), decision = "pending" }
  local db = ensure(); db.pendingRestores = db.pendingRestores or {}; db.pendingRestores[preview.previewId] = { preview = preview, snapshot = snapshot }; audit("restore_preview", snapshot, "success", nil, actor); return preview
end
function M.Restore(previewId, confirm, reason, actor)
  local db = ensure(); local pending = db.pendingRestores and db.pendingRestores[previewId]; if not pending then return nil, "PREVIEW_NOT_FOUND" end
  if confirm ~= true then pending.preview.decision = "cancelled"; audit("restore_cancel", pending.snapshot, "success", reason, actor); return pending.preview end
  local snapshot = pending.snapshot; if not authorized(snapshot.scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local safety, safetyReason = M.Create(snapshot.scope, "before-restore:" .. tostring(snapshot.snapshotId), actor); if not safety then return nil, safetyReason end
  local payload = snapshot.payload or {}
  if snapshot.scope == "full" then
    local keep = { backups = db.backups, pendingRestores = db.pendingRestores, pendingImports = db.pendingImports, auditLog = db.auditLog, backupRetention = db.backupRetention }
    for k in pairs(db) do db[k] = nil end; for k, v in pairs(keep) do db[k] = v end; for k, v in pairs(payload) do db[k] = clone(v) end
  elseif snapshot.scope == "local" then
    db.settings = db.settings or {}; for k, v in pairs(payload.presentation or {}) do db.settings[k] = clone(v) end
  elseif snapshot.scope == "guild" then
    db.settings = db.settings or {}; for k, v in pairs(payload.settings or {}) do db.settings[k] = clone(v) end; db.rankRules = clone(payload.rankRules or db.rankRules); db.seasons = clone(payload.seasons or db.seasons); db.profiles = db.profiles or {}; db.profiles.guild = clone(payload.profiles or db.profiles.guild)
  else return nil, "INVALID_SCOPE" end
  pending.preview.decision = "confirmed"; pending.preview.safetySnapshotId = safety.snapshotId; pending.preview.reason = reason; db.pendingRestores[previewId] = nil; audit("restore_apply", snapshot, "success", reason, actor); return pending.preview
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
