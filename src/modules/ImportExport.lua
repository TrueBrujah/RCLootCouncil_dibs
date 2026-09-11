--[[
Module: Dibs.ImportExport
Layer: Persistence boundary
Purpose: Encode, validate, preview, and apply portable Dibs packages.
Responsibilities: Versioned envelopes, checksums, bounded decoding, and audit records.
Non-responsibilities: It never silently applies imported data.
Dependencies: Dibs.GetDB, serializer/JSON test adapter, Permissions.
Blizzard events: None directly.  Internal events/messages: None emitted.
SavedVariables: Reads/writes guild DB and auditLog through explicit Apply calls.
RCLootCouncil: Imports may contain RC evidence but remain preview-first.
Combat safety: Data-only; officer UI must not apply while protected UI is locked.
Invariants: DIBS-RULE-008 and bounded package limits.
Related docs: docs/developer/saved-variables.md, docs/officer/auditing.md.
]]

local Dibs = _G.Dibs
Dibs.ImportExport = Dibs.ImportExport or {}

-- Portable, deterministic data format.  It intentionally resembles Lua tables
-- but is parsed by the small reader below; imported text is never passed to
-- loadstring/load or executed in any way.
local M = Dibs.ImportExport
M.PACKAGE_PREFIX = "DIBS-PKG-1|"
M.PACKAGE_VERSION = 1
M.SCHEMA_VERSION = 1
M.MAX_PACKAGE_SIZE = 250000
M.MAX_BACKUP_SIZE = 2000000
M.MAX_DEPTH = 24
M.MAX_NODES = 50000

local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") end

local function clone(v)
  if Dibs.DeepCopy then return Dibs.DeepCopy(v) end
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = clone(x) end; return out
end

local function keySort(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return tostring(a) < tostring(b)
end

local function encodeValue(value, depth, seen)
  depth = depth or 0
  if depth > M.MAX_DEPTH then return nil, "MAX_DEPTH" end
  local kind = type(value)
  if kind == "nil" then return "nil" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then return nil, "INVALID_NUMBER" end
    return tostring(value)
  end
  if kind == "string" then return string.format("%q", value) end
  if kind ~= "table" then return nil, "UNSAFE_VALUE_" .. string.upper(kind) end
  seen = seen or {}
  if seen[value] then return nil, "CYCLIC_DATA" end
  seen[value] = true
  local keys = {}
  for k in pairs(value) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" then seen[value] = nil; return nil, "INVALID_KEY" end
    table.insert(keys, k)
  end
  table.sort(keys, keySort)
  local parts = {}
  for _, k in ipairs(keys) do
    local ek, er = encodeValue(k, depth + 1, seen)
    if not ek then seen[value] = nil; return nil, er end
    local ev, er2 = encodeValue(value[k], depth + 1, seen)
    if not ev then seen[value] = nil; return nil, er2 end
    table.insert(parts, "[" .. ek .. "]=" .. ev)
  end
  seen[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

local function checksum(text)
  local hash = 2166136261
  for i = 1, #text do
    hash = (hash + string.byte(text, i) * 16777619) % 4294967296
    hash = (hash * 16777619) % 4294967296
  end
  local digits = "0123456789abcdef"; local out = {}
  for shift = 7, 0, -1 do
    local divisor = 16 ^ shift
    local digit = math.floor(hash / divisor) % 16
    out[#out + 1] = digits:sub(digit + 1, digit + 1)
  end
  return table.concat(out)
end
M.Checksum = checksum

local function parser(text)
  local position, nodes = 1, 0
  local function skip()
    while position <= #text and text:sub(position, position):match("%s") do position = position + 1 end
  end
  local parse
  local function parseString()
    position = position + 1
    local out = {}
    while position <= #text do
      local c = text:sub(position, position); position = position + 1
      if c == '"' then return table.concat(out) end
      if c == "\\" then
        if position > #text then return nil, "UNTERMINATED_STRING" end
        local e = text:sub(position, position); position = position + 1
        local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ["\\"] = "\\", ['"'] = '"' }
        if map[e] then table.insert(out, map[e])
        elseif e:match("%d") then
          local digits = e .. text:sub(position, position + 2)
          if not digits:match("^%d%d%d$") then return nil, "INVALID_ESCAPE" end
          position = position + 2; table.insert(out, string.char(tonumber(digits)))
        else return nil, "INVALID_ESCAPE" end
      else table.insert(out, c) end
    end
    return nil, "UNTERMINATED_STRING"
  end
  local function parseNumber()
    local start = position
    while position <= #text and text:sub(position, position):match("[%d%+%-%e%E%.]") do position = position + 1 end
    local raw = text:sub(start, position - 1); local n = tonumber(raw)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil, "INVALID_NUMBER" end
    return n
  end
  parse = function(depth)
    if depth > M.MAX_DEPTH then return nil, "MAX_DEPTH" end
    nodes = nodes + 1; if nodes > M.MAX_NODES then return nil, "MAX_NODES" end
    skip(); local c = text:sub(position, position)
    if c == '"' then return parseString() end
    if c == "{" then
      position = position + 1; local out = {}; skip()
      while position <= #text and text:sub(position, position) ~= "}" do
        skip(); if text:sub(position, position) ~= "[" then return nil, "EXPECTED_KEY" end
        position = position + 1; local k, ke = parse(depth + 1); if k == nil and ke then return nil, ke end
        skip(); if text:sub(position, position) ~= "]" then return nil, "EXPECTED_KEY_END" end
        position = position + 1; skip(); if text:sub(position, position) ~= "=" then return nil, "EXPECTED_ASSIGN" end
        position = position + 1; local v, ve = parse(depth + 1); if v == nil and ve then return nil, ve end
        if type(k) ~= "string" and type(k) ~= "number" then return nil, "INVALID_KEY" end
        out[k] = v; skip(); local sep = text:sub(position, position)
        if sep == "," then position = position + 1; skip() elseif sep ~= "}" then return nil, "EXPECTED_SEPARATOR" end
      end
      if text:sub(position, position) ~= "}" then return nil, "UNTERMINATED_TABLE" end
      position = position + 1; return out
    end
    if text:sub(position, position + 3) == "true" then position = position + 4; return true end
    if text:sub(position, position + 4) == "false" then position = position + 5; return false end
    if text:sub(position, position + 2) == "nil" then position = position + 3; return nil end
    if c:match("[%d%+%-%.]") then return parseNumber() end
    return nil, "UNEXPECTED_TOKEN"
  end
  local value, err = parse(0); skip()
  if err then return nil, err end
  if position <= #text then return nil, "TRAILING_DATA" end
  return value
end

local function containsUnsafe(value, depth)
  depth = (depth or 0) + 1
  if depth > M.MAX_DEPTH then return true, "MAX_DEPTH" end
  local kind = type(value)
  if kind == "function" or kind == "userdata" or kind == "thread" then return true, "UNSAFE_VALUE" end
  if kind == "string" then
    if value:find("/run", 1, true) or value:find("loadstring", 1, true) or value:find("RunScript", 1, true) then
      return true, "UNSAFE_CONTENT"
    end
  elseif kind == "table" then
    for k, v in pairs(value) do
      local bad, reason = containsUnsafe(k, depth); if bad then return true, reason end
      bad, reason = containsUnsafe(v, depth); if bad then return true, reason end
    end
  end
  return false
end

local PRESENTATION_KEYS = { "uiScale", "windowWidth", "windowHeight", "defaultTab", "pageSize", "showTooltips", "theme" }
local POLICY_KEYS = { "defaultAllocation", "officerMaxRankIndex", "officerRankIndices", "installationMode", "allowPublicPreDibs", "dibAllowedTypes", "preDibAnnouncementChannel", "preDibOfficerAnnouncementChannel", "raidReminderMessage" }
local function pick(source, keys)
  local out = {}; for _, key in ipairs(keys) do if source[key] ~= nil then out[key] = clone(source[key]) end end; return out
end
local function context()
  local realm = type(GetRealmName) == "function" and GetRealmName() or "unknown-realm"
  local character = Dibs.GetPlayerName and Dibs.GetPlayerName() or "UnknownPlayer"
  return tostring(realm), tostring(character)
end
local function characterKey()
  local realm, character = context(); return (character .. "-" .. realm):gsub("%s+", "")
end
local function roleAllowed(scope, actor)
  if scope == "local" then return true end
  return Dibs.Permissions and Dibs.Permissions.Can and Dibs.Permissions.Can("settings.modify", actor) == true
end

function M.GetPayload(scope)
  scope = scope or "local"; local db = Dibs.GetDB(); local realm, character = context()
  if scope == "local" then return { presentation = pick(db.settings or {}, PRESENTATION_KEYS), profile = clone(db.profiles and db.profiles["local"] and db.profiles["local"][characterKey()] or {}) }, realm, character end
  if scope == "guild" then return { settings = pick(db.settings or {}, POLICY_KEYS), rankRules = clone(db.rankRules or {}), seasons = clone(db.seasons or {}), profiles = clone(db.profiles and db.profiles.guild or {}) }, realm, character end
  if scope == "full" then local payload = clone(db); payload.backups, payload.pendingImports, payload.auditLog = nil, nil, nil; return payload, realm, character end
  return nil, nil, nil, "INVALID_SCOPE"
end

---@param scope "local"|"guild"|"full"|nil Export scope; defaults to local.
---@param options table|nil Actor, profile, redaction, and reason options.
---@return string|nil encoded Versioned package text.
---@return table|string|nil package Package metadata or reason code.
-- Side effects: Records an export audit event; does not mutate ledger data.
function M.Export(scope, options)
  options = options or {}; scope = scope or "local"; local actor = options.actor
  if not roleAllowed(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local payload, realm, character, reason = M.GetPayload(scope); if not payload then return nil, reason end
  local sensitivity = scope == "full" and "sensitive" or (scope == "guild" and "policy" or "local")
  if options.redacted then sensitivity = "redacted"; if scope ~= "local" then payload = { settings = pick((payload.settings or {}), { "defaultAllocation", "officerMaxRankIndex", "allowPublicPreDibs" }) } end end
  local package = { packageVersion = M.PACKAGE_VERSION, scope = scope, sourceGuild = Dibs.currentGuildKey, sourceCharacter = character, sourceProfile = options.profileName, addonVersion = Dibs.VERSION, schemaVersion = M.SCHEMA_VERSION, createdAt = time(), sensitivity = sensitivity, payload = payload }
  local body, err = encodeValue(package); if not body then return nil, err end
  local sizeLimit = options.allowOversize == true and M.MAX_BACKUP_SIZE or M.MAX_PACKAGE_SIZE
  if #body > sizeLimit then return nil, "PACKAGE_TOO_LARGE" end
  package.checksum = checksum(body); body, err = encodeValue(package); if not body then return nil, err end
  if #body > sizeLimit then return nil, "PACKAGE_TOO_LARGE" end
  M.RecordAudit("export", scope, true, options.reason, actor)
  return M.PACKAGE_PREFIX .. body, package
end

---@param text string Encoded package text.
---@return table|nil package Validated package envelope.
---@return string|nil reasonCode
function M.Decode(text)
  text = trim(text); if #text == 0 or #text > M.MAX_PACKAGE_SIZE + #M.PACKAGE_PREFIX + 200 then return nil, "INVALID_PACKAGE_SIZE" end
  if text:sub(1, #M.PACKAGE_PREFIX) ~= M.PACKAGE_PREFIX then return nil, "INVALID_PACKAGE_PREFIX" end
  local package, err = parser(text:sub(#M.PACKAGE_PREFIX + 1)); if not package then return nil, err end
  if type(package) ~= "table" or tonumber(package.packageVersion) ~= M.PACKAGE_VERSION then return nil, "UNSUPPORTED_PACKAGE_VERSION" end
  if tonumber(package.schemaVersion) ~= M.SCHEMA_VERSION then return nil, "UNSUPPORTED_SCHEMA" end
  if type(package.payload) ~= "table" or type(package.scope) ~= "string" or type(package.checksum) ~= "string" then return nil, "MISSING_REQUIRED_FIELD" end
  if package.scope == "local" and (type(package.sourceCharacter) ~= "string" or package.sourceCharacter == "") then return nil, "MISSING_CHARACTER_CONTEXT" end
  if (package.scope == "guild" or package.scope == "full") and (type(package.sourceGuild) ~= "string" or package.sourceGuild == "") then return nil, "MISSING_GUILD_CONTEXT" end
  local copy = clone(package); copy.checksum = nil; local body = encodeValue(copy); if not body or checksum(body) ~= string.lower(package.checksum) then return nil, "CHECKSUM_MISMATCH" end
  local bad, why = containsUnsafe(package.payload); if bad then return nil, why end
  if package.scope ~= "local" and package.scope ~= "guild" and package.scope ~= "full" then return nil, "INVALID_SCOPE" end
  return package
end

local function count(value)
  if type(value) ~= "table" then return 0 end; local n = 0; for _ in pairs(value) do n = n + 1 end; return n
end

local function describeMapDiff(changes, additions, source, target, prefix)
  if type(source) ~= "table" then return end
  target = type(target) == "table" and target or {}
  for key, value in pairs(source) do
    local label = (prefix and prefix ~= "" and (prefix .. ".") or "") .. tostring(key)
    if target[key] == nil then
      additions[#additions + 1] = label
    elseif tostring(target[key]) ~= tostring(value) then
      changes[#changes + 1] = label
    end
  end
end

---@param text string|table Encoded package or decoded envelope.
---@param targetScope "local"|"guild"|"full"|nil Target scope.
---@param strategy "merge"|"replace"|"append"|nil Apply strategy.
---@param actor string Officer actor for guild/full scopes.
---@return table|nil preview Preview with changes/conflicts and pending ID.
---@return string|nil reasonCode
function M.Preview(text, targetScope, strategy, actor)
  local package, reason = type(text) == "table" and text or M.Decode(text); if not package then return nil, reason end
  targetScope = targetScope or package.scope; strategy = strategy or (package.scope == "full" and "append" or "merge")
  if targetScope ~= package.scope then return nil, "SCOPE_MISMATCH" end
  if strategy ~= "merge" and strategy ~= "replace" and strategy ~= "append" then return nil, "INVALID_STRATEGY" end
  if package.scope ~= "full" and strategy == "append" then return nil, "INVALID_STRATEGY" end
  if not roleAllowed(targetScope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  if package.scope == "full" and package.sourceGuild ~= Dibs.currentGuildKey then return nil, "CROSS_GUILD_FULL_BLOCKED" end
  local db = Dibs.GetDB(); local current = targetScope == "local" and (db.settings or {}) or db
  local preview = { previewId = Dibs.NewId("preview"), packageId = package.checksum, targetScope = targetScope, strategy = strategy, additions = 0, changes = {}, omissions = {}, conflicts = {}, migrations = {}, sensitiveFields = package.sensitivity == "sensitive" and { "player identities", "ledger history" } or {}, expectedLedgerImpact = { additions = package.scope == "full" and count(package.payload.ledger and package.payload.ledger.transactions or {}) or 0, duplicates = 0 }, createdAt = time(), actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), decision = "pending" }
  local newFields = {}
  if targetScope == "local" then
    describeMapDiff(preview.changes, newFields, package.payload.presentation, current, "presentation")
    describeMapDiff(preview.changes, newFields, package.payload.profile, db.profiles and db.profiles["local"] and db.profiles["local"][characterKey()], "profile")
  elseif targetScope == "guild" then
    describeMapDiff(preview.changes, newFields, package.payload.settings, db.settings, "settings")
    describeMapDiff(preview.changes, newFields, package.payload.rankRules, db.rankRules, "rankRules")
    describeMapDiff(preview.changes, newFields, package.payload.seasons, db.seasons, "seasons")
    describeMapDiff(preview.changes, newFields, package.payload.profiles, db.profiles and db.profiles.guild, "profiles")
  else
    local incoming = package.payload.ledger and package.payload.ledger.transactions or {}
    local existing = db.ledger and db.ledger.transactions or {}
    for id in pairs(incoming) do
      if existing[id] then preview.expectedLedgerImpact.duplicates = preview.expectedLedgerImpact.duplicates + 1 end
    end
    for key in pairs(package.payload) do
      if key ~= "ledger" then preview.changes[#preview.changes + 1] = tostring(key) end
    end
  end
  preview.additions = #newFields + (preview.expectedLedgerImpact.additions or 0)
  if package.sensitivity == "redacted" then preview.omissions[#preview.omissions + 1] = "sensitive fields (redacted by exporter)" end
  db.pendingImports = db.pendingImports or {}; db.pendingImports[preview.previewId] = { preview = preview, package = package }
  M.RecordAudit("import_preview", package.scope, true, nil, actor); return preview
end

local function mergeInto(target, source, replace)
  if replace then for k in pairs(target) do target[k] = nil end end
  for k, v in pairs(source or {}) do target[k] = clone(v) end
end
---@param previewId string Preview identifier.
---@param confirm boolean Explicit confirmation.
---@param reason string|nil Apply reason.
---@param actor string Officer actor for guild/full scopes.
---@return table|nil result Applied/cancelled preview.
---@return string|nil reasonCode
-- Side effects: Applies only a previously validated preview and records audit/safety snapshot data.
function M.Apply(previewId, confirm, reason, actor)
  local db = Dibs.GetDB(); local pending = db.pendingImports and db.pendingImports[previewId]; if not pending then return nil, "PREVIEW_NOT_FOUND" end
  if confirm ~= true then pending.preview.decision = "cancelled"; M.RecordAudit("import_cancel", pending.preview.targetScope, true, reason, actor); return pending.preview end
  local package, preview = pending.package, pending.preview
  if not roleAllowed(preview.targetScope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  if package.scope == "full" then
    if package.sourceGuild ~= Dibs.currentGuildKey then return nil, "CROSS_GUILD_FULL_BLOCKED" end
    local safety = Dibs.Backup and Dibs.Backup.Create and Dibs.Backup.Create("full", "before-import:" .. tostring(package.checksum), actor)
    if not safety then return nil, "SAFETY_SNAPSHOT_FAILED" end
    preview.safetySnapshotId = safety.snapshotId
    local ledger = package.payload.ledger or {}; local targetLedger = db.ledger or {}; targetLedger.transactions = targetLedger.transactions or {}; targetLedger.awardTransactions = targetLedger.awardTransactions or {}; targetLedger.evidenceTransactions = targetLedger.evidenceTransactions or {}
    local staged = {}
    for id, tx in pairs(ledger.transactions or {}) do
      if type(tx) ~= "table" or tostring(tx.transactionId or id) ~= tostring(id) then return nil, "INVALID_TRANSACTION_ID" end
      if Dibs.Ledger and Dibs.Ledger.ValidateTransaction then
        local seasonKnown = (db.seasons and db.seasons[tx.seasonId]) or (package.payload.seasons and package.payload.seasons[tx.seasonId])
        if not seasonKnown then return nil, "SEASON_NOT_FOUND" end
        local ok, why = Dibs.Ledger.ValidateTransaction(tx)
        if not ok and why ~= "SEASON_NOT_FOUND" then return nil, why end
      end
      local existing = targetLedger.transactions[id]
      if existing and (existing.playerName ~= tx.playerName or tonumber(existing.amount) ~= tonumber(tx.amount)) then return nil, "TRANSACTION_CONFLICT" end
      if not existing then staged[id] = tx end
    end
    for ref, id in pairs(ledger.awardTransactions or {}) do
      if targetLedger.awardTransactions[ref] and targetLedger.awardTransactions[ref] ~= id then return nil, "AWARD_REFERENCE_CONFLICT" end
    end
    for id, tx in pairs(staged) do targetLedger.transactions[id] = clone(tx) end
    targetLedger.playerStates = targetLedger.playerStates or {}
    for id, tx in pairs(staged) do
      targetLedger.playerStates[tx.seasonId] = targetLedger.playerStates[tx.seasonId] or {}
      local playerKey = string.lower(tostring(tx.playerName or tx.playerGuid or ""))
      local state = targetLedger.playerStates[tx.seasonId][playerKey]
      if not state then state = { allocation = 0, balance = 0, transactions = {} }; targetLedger.playerStates[tx.seasonId][playerKey] = state end
      local found = false
      for _, existingId in ipairs(state.transactions or {}) do if existingId == id then found = true; break end end
      if not found then table.insert(state.transactions, id) end
    end
    for k, v in pairs(ledger.awardTransactions or {}) do targetLedger.awardTransactions[k] = targetLedger.awardTransactions[k] or v end
    for k, v in pairs(ledger.evidenceTransactions or {}) do targetLedger.evidenceTransactions[k] = targetLedger.evidenceTransactions[k] or v end
    for key, value in pairs(package.payload) do if key ~= "ledger" then db[key] = clone(value) end end
  elseif preview.targetScope == "local" then db.settings = db.settings or {}; mergeInto(db.settings, package.payload.presentation or {}, preview.strategy == "replace")
  else
    local safety = Dibs.Backup and Dibs.Backup.Create and Dibs.Backup.Create("guild", "before-config-import:" .. tostring(package.checksum), actor)
    if not safety then return nil, "SAFETY_SNAPSHOT_FAILED" end
    preview.safetySnapshotId = safety.snapshotId
    db.settings = db.settings or {}; mergeInto(db.settings, package.payload.settings or {}, preview.strategy == "replace")
    if package.payload.rankRules then db.rankRules = clone(package.payload.rankRules) end
    if package.payload.seasons then db.seasons = clone(package.payload.seasons) end
    if package.payload.profiles then db.profiles = db.profiles or {}; db.profiles.guild = clone(package.payload.profiles) end
  end
  preview.decision = "confirmed"; preview.reason = reason; db.pendingImports[previewId] = nil; M.RecordAudit("import_apply", package.scope, true, reason, actor); return preview
end

function M.RecordAudit(action, scope, ok, reason, actor)
  local db = Dibs.GetDB(); db.auditLog = db.auditLog or {}; table.insert(db.auditLog, { auditId = Dibs.NewId("audit"), action = action, scope = scope, actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), createdAt = time(), outcome = ok and "success" or "rejected", reason = reason })
end

-- Stable aliases used by UI integrations and future migration tooling.
M.Encode = function(package)
  local body, reason = encodeValue(package); if not body then return nil, reason end
  return M.PACKAGE_PREFIX .. body
end
M.Validate = M.Decode
M.PreviewImport = M.Preview
M.ApplyImport = M.Apply

return M
