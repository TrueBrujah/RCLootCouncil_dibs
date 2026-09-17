--[[
Module: Dibs.Core
Layer: Composition root and application services
Purpose: Create the guild-scoped runtime, expose stable APIs, and connect WoW events.
Responsibilities: SavedVariables migration, slash commands, permissions-aware orchestration, and startup.
Non-responsibilities: Ledger rules, loot ownership, and UI layout belong to their modules.
Dependencies: WoW API; optional Ace3 and RCLootCouncil integrations.
Blizzard events: ADDON_LOADED, PLAYER_LOGIN, GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, PLAYER_REGEN_ENABLED, CHAT_MSG_ADDON.
Internal events/messages: Routes CHAT_MSG_ADDON to Dibs.Sync; invalidates readiness on roster/zone/combat changes.
SavedVariables: RCLootCouncil_dibsDB, guild-scoped schema version 6.
RCLootCouncil: Initializes capability-aware integration when the optional addon is present.
Combat safety: Defers protected UI work until PLAYER_REGEN_ENABLED.
Invariants: DIBS-RULE-001, DIBS-RULE-002, DIBS-RULE-003, DIBS-RULE-004, DIBS-RULE-009.
Related docs: docs/developer/architecture.md, docs/developer/saved-variables.md.
]]

local addonName, RCLootCouncil_dibs = ...

RCLootCouncil_dibs = RCLootCouncil_dibs or {}
_G.RCLootCouncil_dibs = RCLootCouncil_dibs

Dibs = _G.Dibs or RCLootCouncil_dibs
_G.Dibs = Dibs

-- Keep the shared namespace explicit for editors and for Core's early guards.
-- Permissions.lua fills this table with the authoritative implementation once
-- the ordered module list reaches it; initializing it here is intentionally
-- side-effect free and preserves an existing table during reloads.
Dibs.Permissions = Dibs.Permissions or {}
Dibs.Identity = Dibs.Identity or {}
Dibs.Governance = Dibs.Governance or {}
Dibs.OperationalPolicy = Dibs.OperationalPolicy or {}
Dibs.LegacyBaseline = Dibs.LegacyBaseline or {}
Dibs.ProtectedActions = Dibs.ProtectedActions or {}
Dibs.PreDibs = Dibs.PreDibs or {}
Dibs.Seasons = Dibs.Seasons or {}
Dibs.RankRules = Dibs.RankRules or {}
Dibs.Ledger = Dibs.Ledger or {}
Dibs.LootPipeline = Dibs.LootPipeline or {}
Dibs.Sync = Dibs.Sync or {}
Dibs.RaidRelay = Dibs.RaidRelay or {}
Dibs.RaidPrompts = Dibs.RaidPrompts or {}
Dibs.Readiness = Dibs.Readiness or {}
Dibs.DryRun = Dibs.DryRun or {}
Dibs.CharacterEligibility = Dibs.CharacterEligibility or {}
Dibs.Eligibility = Dibs.CharacterEligibility
Dibs.Disputes = Dibs.Disputes or {}
Dibs.Ace3 = Dibs.Ace3 or {}
Dibs.AceGUI = Dibs.AceGUI or {}
Dibs.DeveloperUI = Dibs.DeveloperUI or {}
Dibs.DeveloperMode = Dibs.DeveloperMode or {}
Dibs.DeveloperSandboxStore = Dibs.DeveloperSandboxStore or {}
Dibs.DeveloperSandbox = Dibs.DeveloperSandbox or {}
Dibs.DeveloperSandboxScenarios = Dibs.DeveloperSandboxScenarios or {}
Dibs.EncounterJournal = Dibs.EncounterJournal or {}
Dibs.RCLootCouncil = Dibs.RCLootCouncil or {}
Dibs.RCOptions = Dibs.RCOptions or {}
Dibs.PlayerUI = Dibs.PlayerUI or {}
Dibs.OfficerUI = Dibs.OfficerUI or {}
Dibs.LogsUI = Dibs.LogsUI or {}
Dibs.DebugLogs = Dibs.DebugLogs or {}
Dibs.Reconciliation = Dibs.Reconciliation or {}
Dibs.Backup = Dibs.Backup or {}
Dibs.ImportExport = Dibs.ImportExport or {}
Dibs.Profiles = Dibs.Profiles or {}
Dibs.DebugLogs.entries = Dibs.DebugLogs.entries or {}
Dibs.DebugLogs.maxEntries = Dibs.DebugLogs.maxEntries or 300

Dibs.ADDON_NAME = addonName or "RCLootCouncil_dibs"
Dibs.MODULE_NAME = "RCLootCouncil_dibs"
Dibs.VERSION = "0.6.0"
Dibs.ICON_TEXTURE = "Interface\\AddOns\\RCLootCouncil_dibs\\media\\RCLootCouncil_Dibs_Logo"
Dibs.PROTOCOL_VERSION = 1
Dibs.DEFAULT_DIBS_PER_RANK = 1
Dibs.SAVED_VARIABLE_NAME = "RCLootCouncil_dibsDB"

if Dibs ~= RCLootCouncil_dibs then
  RCLootCouncil_dibs = Dibs
  _G.RCLootCouncil_dibs = Dibs
end

local function deepcopy(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return seen[value]
  end

  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[deepcopy(key, seen)] = deepcopy(item, seen)
  end
  return copy
end

-- Shared by backup, import/export and profile modules.  The copy is deliberately
-- data-only: functions, userdata and frames are never copied into SavedVariables.
Dibs.DeepCopy = Dibs.DeepCopy or deepcopy

local function mergeDefaults(target, defaults)
  if type(target) ~= "table" then
    target = {}
  end

  for key, value in pairs(defaults) do
    if type(value) == "table" and type(target[key]) == "table" then
      mergeDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = deepcopy(value)
    end
  end

  return target
end

local function normalizeGuildKey(realm, name)
  local value = string.lower(tostring(realm or "unknown-realm") .. ":" .. tostring(name or "unknown"))
  return (value:gsub("%s+", ""))
end

-- Isolates all Dibs data by guild so alts in different guilds never share seasons/ledger/requests.
---@return string guildKey Stable normalized guild identity used for persistence and sync.
function Dibs.GetGuildKey()
  local realm = type(GetRealmName) == "function" and GetRealmName() or "unknown-realm"
  if type(IsInGuild) == "function" and IsInGuild() and type(GetGuildInfo) == "function" then
    local guildName = GetGuildInfo("player")
    if guildName and guildName ~= "" then
      return normalizeGuildKey(realm, guildName)
    end
  end
  local playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or "unknown"
  return normalizeGuildKey(realm, "no-guild:" .. tostring(playerName))
end

local defaultDB = {
  version = 6,
  currentSeasonId = nil,
  seasons = {},
  rankRules = {},
  ledger = {
    transactions = {},
    playerStates = {},
    awardTransactions = {},
    evidenceTransactions = {},
    canonical = { schema = 1, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
  },
  permissions = {
    adminEvents = {},
    activeStandaloneAdmins = {},
  },
  preDibs = {
    requests = {},
    modePolicies = {},
    acquisitions = {},
  },
  disputes = {
    version = 1,
    requests = {},
    order = {},
    corrections = {},
  },
  reconciliation = {
    version = 1,
    sessions = {},
    aliases = {},
    aliasHistory = {},
    decisions = {},
    evidence = {},
    evidenceIndex = {},
  },
  characterEligibility = {
    version = 1,
    policies = {},
    acquisitions = {},
    acquisitionIndex = {},
    relationships = {},
    relationshipOrder = {},
    mainChanges = {},
    mainChangeOrder = {},
    exceptions = {},
    decisions = {},
  },
  governance = {
    schema = 1,
    status = "POLICY_UNINITIALIZED",
    revision = 0,
    hash = "GENESIS",
    records = {},
    auditLog = {},
    conflicts = {},
    aliases = { schema = 1, records = {} },
    future = { coordinator = nil, ledgerEpoch = nil, protocolState = "LEGACY_LOCAL", baseline = nil },
    authority = { schema = 1, state = "LEGACY_LOCAL", proposals = {}, orphanedEvidence = {}, auditLog = {} },
  },
  operationalPolicy = {
    schema = 1, status = "POLICY_UNINITIALIZED", policyRevision = 0, hash = "GENESIS",
    records = {}, auditLog = {}, conflicts = {}, values = { modules = {
      preDibs = true, requests = true, rclootcouncil = true, announcements = true,
      lootEligibility = true, historicalReconciliation = true,
    } },
  },
  legacyBaseline = {
    schema = 1,
    status = "LEGACY_PREPARED",
    evidence = {},
    sources = {},
    findings = {},
    decisions = {},
    activeDecisionByEvidence = {},
    baseline = nil,
    recoveries = {},
    auditLog = {},
  },
  backups = {},
  backupRetention = 5,
  auditLog = {},
  sync = {
    seenTransactions = {},
    peerStates = {},
    v2 = { schema = 1, protocolState = "LEGACY_LOCAL", requestIndex = {}, tombstones = {}, replay = {}, peers = {} },
  },
  settings = {
    language = "AUTO",
    debugLevels = { all = 1 },
    defaultAllocation = 1,
    officerMaxRankIndex = 1,
    officerRankIndices = {},
    installationMode = "AUTO",
    allowPublicPreDibs = true,
    preDibAnnouncementChannel = "GUILD",
    preDibOfficerAnnouncementChannel = "OFFICER",
    preDibAnnouncementTemplate = "[Dibs] %player requested %item (%difficulty) - %date %time",
    raidReminderTemplate = "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]",
    developerModeEnabled = false,
    defaultSyncInterval = 5,
    raidEntryDibPromptsEnabled = false,
    raidReminderMessage = "[Dibs] Review your eligible Pre-Dibs before the encounter.",
  },
}

local FLAT_ROOT_MARKERS = { "seasons", "preDibs", "ledger", "permissions", "settings" }
local ROOT_SCHEMA_VERSION = 6
local GUILD_SCHEMA_VERSION = 6
local RECOVERY_METADATA_VERSION = 1
local MAX_STARTUP_BACKUPS = 3
local MAX_QUARANTINE_RECORDS = 25

Dibs.Persistence = Dibs.Persistence or {}

local function isFlatLegacyRoot(persisted)
  if type(persisted.guilds) == "table" then return false end
  for _, key in ipairs(FLAT_ROOT_MARKERS) do
    if type(persisted[key]) == "table" then return true end
  end
  return false
end

local function isWholeNumber(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function sortedKeys(value)
  local keys = {}
  for key in pairs(value or {}) do table.insert(keys, key) end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function newRoot()
  return {
    schemaVersion = ROOT_SCHEMA_VERSION,
    guilds = {},
    persistenceRecovery = {
      version = RECOVERY_METADATA_VERSION,
      backups = {},
      quarantine = {},
      nextBackupId = 1,
    },
  }
end

local function ensureRecoveryMetadata(root, changes)
  local existing = root.persistenceRecovery
  if type(existing) ~= "table" then
    root.persistenceRecovery = {
      version = RECOVERY_METADATA_VERSION,
      backups = {},
      quarantine = {},
      nextBackupId = 1,
    }
    changes.changed = true
    if existing ~= nil then
      changes.recovery = true
      changes.needsBackup = true
      table.insert(root.persistenceRecovery.quarantine, {
        scope = "root.persistenceRecovery",
        reason = "EXPECTED_TABLE",
        original = deepcopy(existing),
      })
    end
  end

  local metadata = root.persistenceRecovery
  if type(metadata.quarantine) ~= "table" then
    local invalid = metadata.quarantine
    metadata.quarantine = {}
    changes.changed, changes.recovery, changes.needsBackup = true, true, true
    if invalid ~= nil then table.insert(metadata.quarantine, { scope = "root.persistenceRecovery.quarantine", reason = "EXPECTED_TABLE", original = deepcopy(invalid) }) end
  end
  if not isWholeNumber(metadata.version) or metadata.version ~= RECOVERY_METADATA_VERSION then
    local invalid = metadata.version
    metadata.version = RECOVERY_METADATA_VERSION
    changes.changed = true
    if invalid ~= nil then
      changes.recovery = true
      changes.needsBackup = true
      table.insert(metadata.quarantine, {
        scope = "root.persistenceRecovery.version",
        reason = "UNSUPPORTED_METADATA_VERSION",
        original = invalid,
      })
    end
  end
  if type(metadata.backups) ~= "table" then
    local invalid = metadata.backups
    metadata.backups = {}
    changes.changed, changes.recovery, changes.needsBackup = true, true, true
    if invalid ~= nil then table.insert(metadata.quarantine, { scope = "root.persistenceRecovery.backups", reason = "EXPECTED_TABLE", original = deepcopy(invalid) }) end
  end
  if not isWholeNumber(metadata.nextBackupId) or metadata.nextBackupId < 1 then
    metadata.nextBackupId = #metadata.backups + 1
    changes.changed = true
  end
  return metadata
end

local function quarantine(root, changes, scope, reason, original)
  local metadata = ensureRecoveryMetadata(root, changes)
  table.insert(metadata.quarantine, {
    scope = scope,
    reason = reason,
    original = deepcopy(original),
  })
  while #metadata.quarantine > MAX_QUARANTINE_RECORDS do table.remove(metadata.quarantine, 1) end
  changes.changed, changes.recovery, changes.needsBackup = true, true, true
end

local function recoverySnapshot(source)
  if type(source) ~= "table" then return deepcopy(source) end
  local snapshot = {}
  for key, value in pairs(source) do
    -- Recovery snapshots do not recursively retain earlier recovery snapshots.
    if key ~= "persistenceRecovery" then snapshot[deepcopy(key)] = deepcopy(value) end
  end
  return snapshot
end

local function addStartupBackup(root, source, reason)
  local metadata = root.persistenceRecovery
  local backup = {
    backupId = "startup-" .. tostring(metadata.nextBackupId),
    reason = reason,
    sourceSchemaVersion = type(source) == "table" and source.schemaVersion or nil,
    snapshot = recoverySnapshot(source),
  }
  metadata.nextBackupId = metadata.nextBackupId + 1
  table.insert(metadata.backups, backup)
  while #metadata.backups > MAX_STARTUP_BACKUPS do table.remove(metadata.backups, 1) end
  return backup
end

local function ensureTable(owner, key, template, root, changes, scope)
  if owner[key] == nil then
    owner[key] = deepcopy(template)
    changes.changed = true
  elseif type(owner[key]) ~= "table" then
    quarantine(root, changes, scope, "EXPECTED_TABLE", owner[key])
    owner[key] = deepcopy(template)
  end
  return owner[key]
end

local function sanitizeRecordMap(container, root, changes, scope)
  for _, key in ipairs(sortedKeys(container)) do
    if type(container[key]) ~= "table" then
      quarantine(root, changes, scope .. "[" .. tostring(key) .. "]", "EXPECTED_RECORD_TABLE", container[key])
      container[key] = nil
    end
  end
end

local function sanitizeNestedRecordMap(container, root, changes, scope)
  for _, key in ipairs(sortedKeys(container)) do
    if type(container[key]) ~= "table" then
      quarantine(root, changes, scope .. "[" .. tostring(key) .. "]", "EXPECTED_TABLE", container[key])
      container[key] = nil
    else
      sanitizeRecordMap(container[key], root, changes, scope .. "[" .. tostring(key) .. "]")
    end
  end
end

local function validateGuildSubtrees(db, root, changes, guildKey)
  local scope = "guilds[" .. tostring(guildKey) .. "]"
  ensureTable(db, "seasons", {}, root, changes, scope .. ".seasons")
  sanitizeRecordMap(db.seasons, root, changes, scope .. ".seasons")
  ensureTable(db, "rankRules", {}, root, changes, scope .. ".rankRules")
  sanitizeRecordMap(db.rankRules, root, changes, scope .. ".rankRules")

  local ledger = ensureTable(db, "ledger", defaultDB.ledger, root, changes, scope .. ".ledger")
  ensureTable(ledger, "transactions", {}, root, changes, scope .. ".ledger.transactions")
  ensureTable(ledger, "playerStates", {}, root, changes, scope .. ".ledger.playerStates")
  ensureTable(ledger, "awardTransactions", {}, root, changes, scope .. ".ledger.awardTransactions")
  ensureTable(ledger, "evidenceTransactions", {}, root, changes, scope .. ".ledger.evidenceTransactions")
  local canonicalLedger = ensureTable(ledger, "canonical", defaultDB.ledger.canonical, root, changes, scope .. ".ledger.canonical")
  ensureTable(canonicalLedger, "commits", {}, root, changes, scope .. ".ledger.canonical.commits")
  ensureTable(canonicalLedger, "transactionIndex", {}, root, changes, scope .. ".ledger.canonical.transactionIndex")
  ensureTable(canonicalLedger, "positions", {}, root, changes, scope .. ".ledger.canonical.positions")
  if canonicalLedger.schema ~= 1 or (canonicalLedger.epoch ~= nil and not isWholeNumber(canonicalLedger.epoch))
    or not isWholeNumber(canonicalLedger.nextSeq) or canonicalLedger.nextSeq < 1
    or (canonicalLedger.rootHash ~= nil and type(canonicalLedger.rootHash) ~= "string") then
    quarantine(root, changes, scope .. ".ledger.canonical", "UNSUPPORTED_CANONICAL_LEDGER", canonicalLedger)
    ledger.canonical = deepcopy(defaultDB.ledger.canonical)
  end
  sanitizeRecordMap(ledger.transactions, root, changes, scope .. ".ledger.transactions")
  sanitizeNestedRecordMap(ledger.playerStates, root, changes, scope .. ".ledger.playerStates")

  local permissions = ensureTable(db, "permissions", defaultDB.permissions, root, changes, scope .. ".permissions")
  ensureTable(permissions, "adminEvents", {}, root, changes, scope .. ".permissions.adminEvents")
  ensureTable(permissions, "activeStandaloneAdmins", {}, root, changes, scope .. ".permissions.activeStandaloneAdmins")

  local preDibs = ensureTable(db, "preDibs", defaultDB.preDibs, root, changes, scope .. ".preDibs")
  ensureTable(preDibs, "requests", {}, root, changes, scope .. ".preDibs.requests")
  ensureTable(preDibs, "modePolicies", {}, root, changes, scope .. ".preDibs.modePolicies")
  ensureTable(preDibs, "acquisitions", {}, root, changes, scope .. ".preDibs.acquisitions")
  sanitizeRecordMap(preDibs.requests, root, changes, scope .. ".preDibs.requests")
  sanitizeRecordMap(preDibs.modePolicies, root, changes, scope .. ".preDibs.modePolicies")
  sanitizeRecordMap(preDibs.acquisitions, root, changes, scope .. ".preDibs.acquisitions")

  local disputes = ensureTable(db, "disputes", defaultDB.disputes, root, changes, scope .. ".disputes")
  ensureTable(disputes, "requests", {}, root, changes, scope .. ".disputes.requests")
  ensureTable(disputes, "order", {}, root, changes, scope .. ".disputes.order")
  ensureTable(disputes, "corrections", {}, root, changes, scope .. ".disputes.corrections")

  local reconciliation = ensureTable(db, "reconciliation", defaultDB.reconciliation, root, changes, scope .. ".reconciliation")
  for _, key in ipairs({ "sessions", "aliases", "aliasHistory", "decisions", "evidence", "evidenceIndex" }) do
    ensureTable(reconciliation, key, {}, root, changes, scope .. ".reconciliation." .. key)
  end

  local eligibility = ensureTable(db, "characterEligibility", defaultDB.characterEligibility, root, changes, scope .. ".characterEligibility")
  for _, key in ipairs({ "policies", "acquisitions", "acquisitionIndex", "relationships", "relationshipOrder", "mainChanges", "mainChangeOrder", "exceptions", "decisions" }) do
    ensureTable(eligibility, key, {}, root, changes, scope .. ".characterEligibility." .. key)
  end

  local governance = ensureTable(db, "governance", defaultDB.governance, root, changes, scope .. ".governance")
  ensureTable(governance, "records", {}, root, changes, scope .. ".governance.records")
  ensureTable(governance, "auditLog", {}, root, changes, scope .. ".governance.auditLog")
  ensureTable(governance, "conflicts", {}, root, changes, scope .. ".governance.conflicts")
  local aliases = ensureTable(governance, "aliases", { schema = 1, records = {} }, root, changes, scope .. ".governance.aliases")
  ensureTable(aliases, "records", {}, root, changes, scope .. ".governance.aliases.records")
  local future = ensureTable(governance, "future", defaultDB.governance.future, root, changes, scope .. ".governance.future")
  if governance.schema ~= 1 then
    quarantine(root, changes, scope .. ".governance.schema", "UNSUPPORTED_GOVERNANCE_SCHEMA", governance.schema)
    governance.schema = 1
  end
  if governance.status ~= "POLICY_UNINITIALIZED" and governance.status ~= "GOVERNANCE_ADOPTED" then
    quarantine(root, changes, scope .. ".governance.status", "INVALID_GOVERNANCE_STATUS", governance.status)
    governance.status = "POLICY_UNINITIALIZED"
  end
  if not isWholeNumber(governance.revision) then
    quarantine(root, changes, scope .. ".governance.revision", "EXPECTED_NONNEGATIVE_INTEGER", governance.revision)
    governance.revision = 0
  end
  if type(governance.hash) ~= "string" or governance.hash == "" then
    quarantine(root, changes, scope .. ".governance.hash", "EXPECTED_NONEMPTY_HASH", governance.hash)
    governance.hash = "GENESIS"
  end
  local authority = ensureTable(governance, "authority", defaultDB.governance.authority, root, changes, scope .. ".governance.authority")
  ensureTable(authority, "proposals", {}, root, changes, scope .. ".governance.authority.proposals")
  ensureTable(authority, "orphanedEvidence", {}, root, changes, scope .. ".governance.authority.orphanedEvidence")
  ensureTable(authority, "auditLog", {}, root, changes, scope .. ".governance.authority.auditLog")
  local validAuthorityState = authority.state == "LEGACY_LOCAL" or authority.state == "ACTIVE" or authority.state == "HANDOFF_CLOSING"
    or authority.state == "COORDINATOR_UNAVAILABLE" or authority.state == "RECOVERY_PENDING"
  if authority.schema ~= 1 or not validAuthorityState then
    quarantine(root, changes, scope .. ".governance.authority", "UNSUPPORTED_AUTHORITY_STATE", authority)
    governance.authority = deepcopy(defaultDB.governance.authority)
  end
  local activeFuture = type(future.authority) == "table" and future.authority.state == "ACTIVE"
  if (future.coordinator ~= nil or future.ledgerEpoch ~= nil or future.baseline ~= nil or future.protocolState ~= "LEGACY_LOCAL") and not activeFuture then
    quarantine(root, changes, scope .. ".governance.future", "INVALID_FUTURE_GOVERNANCE", future)
    governance.future = deepcopy(defaultDB.governance.future)
  end

  local operationalPolicy = ensureTable(db, "operationalPolicy", defaultDB.operationalPolicy, root, changes, scope .. ".operationalPolicy")
  ensureTable(operationalPolicy, "records", {}, root, changes, scope .. ".operationalPolicy.records")
  ensureTable(operationalPolicy, "auditLog", {}, root, changes, scope .. ".operationalPolicy.auditLog")
  ensureTable(operationalPolicy, "conflicts", {}, root, changes, scope .. ".operationalPolicy.conflicts")
  if operationalPolicy.schema ~= 1 then
    quarantine(root, changes, scope .. ".operationalPolicy.schema", "UNSUPPORTED_OPERATIONAL_POLICY_SCHEMA", operationalPolicy.schema)
    db.operationalPolicy = deepcopy(defaultDB.operationalPolicy)
  elseif operationalPolicy.status ~= "POLICY_UNINITIALIZED" and operationalPolicy.status ~= "POLICY_ADOPTED" then
    quarantine(root, changes, scope .. ".operationalPolicy.status", "INVALID_OPERATIONAL_POLICY_STATUS", operationalPolicy.status)
    operationalPolicy.status = "POLICY_UNINITIALIZED"
  elseif not isWholeNumber(operationalPolicy.policyRevision) then
    quarantine(root, changes, scope .. ".operationalPolicy.policyRevision", "EXPECTED_NONNEGATIVE_INTEGER", operationalPolicy.policyRevision)
    operationalPolicy.policyRevision = 0
  elseif type(operationalPolicy.hash) ~= "string" or operationalPolicy.hash == "" then
    quarantine(root, changes, scope .. ".operationalPolicy.hash", "EXPECTED_NONEMPTY_HASH", operationalPolicy.hash)
    operationalPolicy.hash = "GENESIS"
  end

  local legacyBaseline = ensureTable(db, "legacyBaseline", defaultDB.legacyBaseline, root, changes, scope .. ".legacyBaseline")
  for _, key in ipairs({ "evidence", "sources", "findings", "decisions", "activeDecisionByEvidence", "recoveries", "auditLog" }) do
    ensureTable(legacyBaseline, key, {}, root, changes, scope .. ".legacyBaseline." .. key)
  end
  if legacyBaseline.schema ~= 1 then
    quarantine(root, changes, scope .. ".legacyBaseline.schema", "UNSUPPORTED_LEGACY_BASELINE_SCHEMA", legacyBaseline.schema)
    db.legacyBaseline = deepcopy(defaultDB.legacyBaseline)
  elseif legacyBaseline.status ~= "LEGACY_PREPARED" and legacyBaseline.status ~= "BASELINE_APPROVED" then
    quarantine(root, changes, scope .. ".legacyBaseline.status", "INVALID_LEGACY_BASELINE_STATUS", legacyBaseline.status)
    legacyBaseline.status = "LEGACY_PREPARED"
  elseif legacyBaseline.baseline ~= nil and type(legacyBaseline.baseline) ~= "table" then
    quarantine(root, changes, scope .. ".legacyBaseline.baseline", "EXPECTED_OPTIONAL_TABLE", legacyBaseline.baseline)
    legacyBaseline.baseline = nil
  end

  ensureTable(db, "backups", {}, root, changes, scope .. ".backups")
  ensureTable(db, "auditLog", {}, root, changes, scope .. ".auditLog")
  local sync = ensureTable(db, "sync", defaultDB.sync, root, changes, scope .. ".sync")
  ensureTable(sync, "seenTransactions", {}, root, changes, scope .. ".sync.seenTransactions")
  ensureTable(sync, "peerStates", {}, root, changes, scope .. ".sync.peerStates")
  local syncV2 = ensureTable(sync, "v2", defaultDB.sync.v2, root, changes, scope .. ".sync.v2")
  ensureTable(syncV2, "requestIndex", {}, root, changes, scope .. ".sync.v2.requestIndex")
  ensureTable(syncV2, "tombstones", {}, root, changes, scope .. ".sync.v2.tombstones")
  ensureTable(syncV2, "replay", {}, root, changes, scope .. ".sync.v2.replay")
  ensureTable(syncV2, "peers", {}, root, changes, scope .. ".sync.v2.peers")
  if syncV2.policyTarget ~= nil then ensureTable(syncV2, "policyTarget", {}, root, changes, scope .. ".sync.v2.policyTarget") end
  if syncV2.schema ~= 1 then
    quarantine(root, changes, scope .. ".sync.v2.schema", "UNSUPPORTED_SYNC_V2_SCHEMA", syncV2.schema)
    sync.v2 = deepcopy(defaultDB.sync.v2)
  elseif syncV2.protocolState ~= "LEGACY_LOCAL" and syncV2.protocolState ~= "CUTOVER_PREPARED" and syncV2.protocolState ~= "V2_ENFORCED" then
    quarantine(root, changes, scope .. ".sync.v2.protocolState", "INVALID_PROTOCOL_STATE", syncV2.protocolState)
    syncV2.protocolState = "LEGACY_LOCAL"
  end
  local settings = ensureTable(db, "settings", defaultDB.settings, root, changes, scope .. ".settings")
  for key, value in pairs(defaultDB.settings) do
    if type(value) == "table" then ensureTable(settings, key, value, root, changes, scope .. ".settings." .. key) end
  end

  if db.profiles ~= nil then
    local profiles = ensureTable(db, "profiles", {}, root, changes, scope .. ".profiles")
    for _, key in ipairs({ "local", "guild", "active" }) do
      if profiles[key] ~= nil then ensureTable(profiles, key, {}, root, changes, scope .. ".profiles." .. key) end
    end
  end
  for _, key in ipairs({ "pendingRestores", "pendingImports" }) do
    if db[key] ~= nil then ensureTable(db, key, {}, root, changes, scope .. "." .. key) end
  end
  if db.currentSeasonId ~= nil and type(db.currentSeasonId) ~= "string" then
    quarantine(root, changes, scope .. ".currentSeasonId", "EXPECTED_OPTIONAL_STRING", db.currentSeasonId)
    db.currentSeasonId = nil
  end
  if db.backupRetention ~= nil and (type(db.backupRetention) ~= "number" or db.backupRetention < 1 or db.backupRetention > 25 or db.backupRetention ~= math.floor(db.backupRetention)) then
    quarantine(root, changes, scope .. ".backupRetention", "OUT_OF_RANGE", db.backupRetention)
    db.backupRetention = defaultDB.backupRetention
  end
end

local function migrateGuild(db)
  if db.version < 2 then
    db.permissions = db.permissions or { adminEvents = {}, activeStandaloneAdmins = {} }
    db.permissions.adminEvents = db.permissions.adminEvents or {}
    db.permissions.activeStandaloneAdmins = db.permissions.activeStandaloneAdmins or {}
    db.ledger = db.ledger or { transactions = {}, playerStates = {}, awardTransactions = {}, evidenceTransactions = {} }
    db.ledger.awardTransactions = db.ledger.awardTransactions or {}
    db.ledger.evidenceTransactions = db.ledger.evidenceTransactions or {}
    db.version = 2
  end
  if db.version < 3 then
    db.preDibs = db.preDibs or { requests = {}, modePolicies = {} }
    db.preDibs.requests = db.preDibs.requests or {}
    db.preDibs.modePolicies = db.preDibs.modePolicies or {}
    for _, request in ipairs(db.preDibs.requests) do
      request.revision = math.max(1, tonumber(request.revision) or 1)
      request.modeAtCreation = request.modeAtCreation or "WILD_OPEN"
      request.delivery = request.delivery or { state = "PENDING" }
    end
    db.version = 3
  end
  if db.version < 4 then
    db.preDibs = db.preDibs or { requests = {}, modePolicies = {}, acquisitions = {} }
    db.preDibs.requests = db.preDibs.requests or {}
    db.preDibs.acquisitions = db.preDibs.acquisitions or {}
    for _, request in ipairs(db.preDibs.requests) do request.difficulty = request.difficulty or "UNKNOWN" end
    db.version = 4
  end
  if db.version < 5 then
    db.preDibs = db.preDibs or { requests = {}, modePolicies = {}, acquisitions = {} }
    db.preDibs.requests = db.preDibs.requests or {}
    for _, request in ipairs(db.preDibs.requests) do
      if request.difficulty == nil or request.difficulty == "" or request.difficulty == "UNKNOWN" then request.difficulty = "Normal" end
    end
    db.version = 5
  end
  if db.version < 6 then
    db.disputes = db.disputes or { version = 1, requests = {}, order = {}, corrections = {} }
    db.disputes.version = tonumber(db.disputes.version) or 1
    db.disputes.requests = db.disputes.requests or {}
    db.disputes.order = db.disputes.order or {}
    db.disputes.corrections = db.disputes.corrections or {}
    db.version = 6
  end
end

Dibs.Persistence.MigrateGuild = Dibs.Persistence.MigrateGuild or migrateGuild

local function persistenceStatus(state, diagnostic, readOnly)
  return { state = state, diagnostic = diagnostic, readOnly = readOnly == true }
end

function Dibs.GetPersistenceStatus()
  return deepcopy(Dibs.persistenceStatus or persistenceStatus("VALID", nil, false))
end

local function setReadOnlyRecovery(source, state, diagnostic)
  Dibs._persistenceRuntimeDB = Dibs._persistenceRuntimeDB or deepcopy(defaultDB)
  Dibs.db = Dibs._persistenceRuntimeDB
  Dibs.persistenceStatus = persistenceStatus(state, diagnostic, true)
  Dibs._persistenceSource = source
end

local function isReadyRoot(root, guildKey)
  if type(root) ~= "table" or root.schemaVersion ~= ROOT_SCHEMA_VERSION or type(root.guilds) ~= "table" or type(root.persistenceRecovery) ~= "table" then return false end
  local db = root.guilds[guildKey]
  if type(db) ~= "table" or db.version ~= GUILD_SCHEMA_VERSION then return false end
  for _, key in ipairs({ "seasons", "rankRules", "ledger", "permissions", "preDibs", "disputes", "reconciliation", "characterEligibility", "governance", "backups", "auditLog", "sync", "settings" }) do
    if type(db[key]) ~= "table" then return false end
  end
  return true
end

local function ensureDB()
  local dbName = Dibs.SAVED_VARIABLE_NAME or "RCLootCouncil_dibsDB"
  local guildKey = Dibs.GetGuildKey()
  Dibs.currentGuildKey = guildKey
  local source = _G[dbName]
  if source == nil and type(_G.DibsDB) == "table" then source = _G.DibsDB end

  if Dibs._persistenceSource == source and isReadyRoot(source, guildKey) then
    Dibs.db = source.guilds[guildKey]
    Dibs.persistenceStatus = Dibs.persistenceStatus or persistenceStatus("VALID", nil, false)
    _G.DibsDB = Dibs.db
    return
  end

  if type(source) == "table" and isWholeNumber(source.schemaVersion) and source.schemaVersion > ROOT_SCHEMA_VERSION then
    setReadOnlyRecovery(source, "FUTURE_UNSUPPORTED", "SavedVariables schema " .. tostring(source.schemaVersion) .. " is newer than supported schema " .. tostring(ROOT_SCHEMA_VERSION) .. "; update RCLootCouncil_dibs before modifying data.")
    return
  end

  local changes = { changed = false, migration = false, recovery = false, needsBackup = false }
  local staged
  if source == nil then
    staged = newRoot()
    changes.changed = true
  elseif type(source) ~= "table" then
    staged = newRoot()
    quarantine(staged, changes, "root", "EXPECTED_TABLE", source)
  else
    staged = deepcopy(source)
  end

  if isFlatLegacyRoot(staged) then
    local legacy = staged
    staged = newRoot()
    staged.guilds[guildKey] = legacy
    changes.changed, changes.migration, changes.needsBackup = true, true, true
  elseif not isWholeNumber(staged.schemaVersion) then
    if staged.schemaVersion ~= nil then quarantine(staged, changes, "root.schemaVersion", "EXPECTED_SUPPORTED_INTEGER", staged.schemaVersion) end
    staged.schemaVersion = ROOT_SCHEMA_VERSION
    changes.changed, changes.migration, changes.needsBackup = true, true, true
  elseif staged.schemaVersion < ROOT_SCHEMA_VERSION then
    staged.schemaVersion = ROOT_SCHEMA_VERSION
    changes.changed, changes.migration, changes.needsBackup = true, true, true
  end

  ensureRecoveryMetadata(staged, changes)
  if type(staged.guilds) ~= "table" then
    quarantine(staged, changes, "root.guilds", "EXPECTED_TABLE", staged.guilds)
    staged.guilds = {}
  end
  for _, key in ipairs(sortedKeys(staged.guilds)) do
    if type(staged.guilds[key]) ~= "table" then
      quarantine(staged, changes, "root.guilds[" .. tostring(key) .. "]", "EXPECTED_GUILD_TABLE", staged.guilds[key])
      staged.guilds[key] = nil
    end
  end

  local existingGuild = staged.guilds[guildKey]
  local isNewGuild = existingGuild == nil
  if existingGuild == nil then
    staged.guilds[guildKey] = {}
    changes.changed = true
  end
  local db = staged.guilds[guildKey]
  if type(db) ~= "table" then
    quarantine(staged, changes, "root.guilds[" .. tostring(guildKey) .. "]", "EXPECTED_GUILD_TABLE", db)
    db = {}
    staged.guilds[guildKey] = db
  end

  if not isNewGuild then
    if isWholeNumber(db.version) and db.version > GUILD_SCHEMA_VERSION then
      setReadOnlyRecovery(source, "FUTURE_UNSUPPORTED", "Guild database version " .. tostring(db.version) .. " is newer than supported version " .. tostring(GUILD_SCHEMA_VERSION) .. "; update RCLootCouncil_dibs before modifying data.")
      return
    elseif db.version == nil then
      db.version = 1
      changes.changed, changes.recovery, changes.migration, changes.needsBackup = true, true, true, true
    elseif not isWholeNumber(db.version) or db.version < 1 then
      quarantine(staged, changes, "guilds[" .. tostring(guildKey) .. "].version", "EXPECTED_SUPPORTED_INTEGER", db.version)
      db.version = 1
      changes.migration = true
    elseif db.version < GUILD_SCHEMA_VERSION then
      changes.migration, changes.needsBackup = true, true
    end
  end

  validateGuildSubtrees(db, staged, changes, guildKey)
  if changes.migration then
    local ok, migrationError = pcall(Dibs.Persistence.MigrateGuild, db)
    if not ok then
      setReadOnlyRecovery(source, "RECOVERABLE_INVALID", "SavedVariables migration failed without committing changes: " .. tostring(migrationError))
      return
    end
  end
  mergeDefaults(db, defaultDB)

  if changes.needsBackup and source ~= nil then addStartupBackup(staged, source, changes.recovery and "recovery" or "migration") end
  if changes.migration or changes.recovery then
    staged.persistenceRecovery.lastMigration = {
      sourceSchemaVersion = type(source) == "table" and source.schemaVersion or nil,
      targetSchemaVersion = ROOT_SCHEMA_VERSION,
      guildKey = guildKey,
      result = changes.recovery and "RECOVERABLE_INVALID" or "MIGRATABLE",
    }
  end

  _G[dbName] = staged
  Dibs.db = staged.guilds[guildKey]
  Dibs._persistenceRuntimeDB = nil
  Dibs._persistenceSource = staged
  Dibs.persistenceStatus = persistenceStatus(changes.recovery and "RECOVERABLE_INVALID" or (changes.migration and "MIGRATABLE" or "VALID"), nil, false)
  _G.DibsDB = Dibs.db
end

---@return DibsGuildDB db Active guild-scoped database after migration/defaulting.
function Dibs.GetDB()
  ensureDB()

  if Dibs.DeveloperSandboxStore and Dibs.DeveloperSandboxStore.Initialize then
    Dibs.DeveloperSandboxStore.Initialize()
  end
  return Dibs.db
end

Dibs.CoreAPI = Dibs.CoreAPI or {}

local function coreActorIsLocal(actor)
  if actor == nil then return true end
  if not Dibs.Permissions or type(Dibs.Permissions.CanonicalPlayerId) ~= "function" then return false end
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  local localId = Dibs.Permissions.CanonicalPlayerId(nil)
  local localName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
  local localNameId = Dibs.Permissions.CanonicalPlayerId(localName)
  return actorId ~= nil and (
    (localId ~= nil and string.lower(tostring(actorId)) == string.lower(tostring(localId)))
      or (localNameId ~= nil and string.lower(tostring(actorId)) == string.lower(tostring(localNameId)))
  )
end

local function coreActorCanViewAll(actor)
  if not Dibs.Permissions or type(Dibs.Permissions.GetGuildRole) ~= "function" then return false end
  if not coreActorIsLocal(actor) then return false end
  local role = Dibs.Permissions.GetGuildRole(actor)
  return role == "gm" or role == "officer"
end

local function coreActorMatchesPlayer(actor, player)
  if not Dibs.Permissions or type(Dibs.Permissions.CanonicalPlayerId) ~= "function" then return false end
  if actor == nil then actor = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil end
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  local playerId = Dibs.Permissions.CanonicalPlayerId(player)
  return actorId ~= nil and playerId ~= nil and string.lower(tostring(actorId)) == string.lower(tostring(playerId))
end

---@param request table|nil Request containing `name` and optional actor identity.
---@return DibsSeason|nil season Created season, or nil when authority/validation fails.
-- Side effects: Persists a season through ProtectedActions.
function Dibs.CoreAPI.createSeason(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("season.create", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and result.value or nil
end

---@param request table|nil Request containing `seasonId` and optional actor identity.
---@return table|nil result Active season ID, or nil when the action is denied.
-- Side effects: Updates `db.currentSeasonId`.
function Dibs.CoreAPI.setActiveSeason(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("season.set", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and { activeSeasonId = result.value } or nil
end

---@param request table|nil Optional officer actor context.
---@return table result `{seasons=...}` or an empty officer-scoped result.
function Dibs.CoreAPI.listSeasons(request)
  if not coreActorCanViewAll(request and (request.actor or request.actorIdentity) or nil) then
    return { seasons = {}, reasonCode = "OFFICER_SCOPE_REQUIRED" }
  end
  local seasons = Dibs.Seasons and Dibs.Seasons.ListSeasons and Dibs.Seasons.ListSeasons() or {}
  return { seasons = seasons }
end

function Dibs.CoreAPI.setRankAllocation(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("rank.set", payload.actor or payload.actorIdentity, payload)
  local rule = result and result.ok and result.value
  local reasonCode = result and result.reasonCode
  return rule and {
    seasonId = payload.seasonId,
    rankIndex = rule.rankIndex,
    allocation = rule.allocation,
    rankName = rule.rankName,
  } or { reasonCode = reasonCode }
end

function Dibs.CoreAPI.getRankAllocation(request)
  local payload = request or {}
  if not coreActorCanViewAll(payload.actor or payload.actorIdentity) then
    return nil, "OFFICER_SCOPE_REQUIRED"
  end
  local rule = Dibs.RankRules and Dibs.RankRules.GetRankAllocation and Dibs.RankRules.GetRankAllocation(payload.seasonId, payload.rankIndex) or nil
  return rule and {
    allocation = rule.allocation,
    rankName = rule.rankName,
  } or nil
end

function Dibs.CoreAPI.getEligibilityPolicy(request)
  local payload = request or {}
  return Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetPolicy
    and Dibs.CharacterEligibility.GetPolicy(payload.seasonId, payload.family) or nil
end

function Dibs.CoreAPI.setEligibilityPolicy(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("eligibility.policy.set", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and result.value or { reasonCode = result and result.reasonCode or "AUTHORITY_UNAVAILABLE" }
end

function Dibs.CoreAPI.evaluateEligibility(request)
  local payload = request or {}
  if not Dibs.CharacterEligibility or not Dibs.CharacterEligibility.Evaluate then
    return { outcome = "review", reasonCode = "ELIGIBILITY_UNAVAILABLE" }
  end
  return Dibs.CharacterEligibility.Evaluate(payload.itemContext or payload, payload.playerName, payload.seasonId)
end

function Dibs.CoreAPI.declareCharacterRelationship(request)
  local payload = request or {}
  return Dibs.CharacterEligibility and Dibs.CharacterEligibility.DeclareRelationship
    and Dibs.CharacterEligibility.DeclareRelationship(payload, payload.actor or payload.actorIdentity) or nil
end

function Dibs.CoreAPI.reviewCharacterRelationship(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("eligibility.relationship.review", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and result.value or { reasonCode = result and result.reasonCode or "AUTHORITY_UNAVAILABLE" }
end

function Dibs.CoreAPI.requestMainChange(request)
  local payload = request or {}
  return Dibs.CharacterEligibility and Dibs.CharacterEligibility.RequestMainChange
    and Dibs.CharacterEligibility.RequestMainChange(payload, payload.actor or payload.actorIdentity) or nil
end

function Dibs.CoreAPI.approveMainChange(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("eligibility.main.review", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and result.value or { reasonCode = result and result.reasonCode or "AUTHORITY_UNAVAILABLE" }
end

function Dibs.CoreAPI.createProbationException(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("eligibility.exception.create", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and result.value or { reasonCode = result and result.reasonCode or "AUTHORITY_UNAVAILABLE" }
end

---@param request table Transaction fields plus actor/actorIdentity.
---@return table result Append result with `accepted`, `value`, and optional `reasonCode`.
-- Side effects: Appends exactly one immutable ledger transaction or records an idempotent replay.
function Dibs.CoreAPI.appendTransaction(request)
  local payload = request or {}
  if not Dibs.Ledger or not Dibs.Ledger.AppendTransaction then
    return { accepted = false, reasonCode = "LEDGER_UNAVAILABLE" }
  end
  local actionByType = {
    DIB_GRANTED = "ledger.grant",
    DIB_USED = "ledger.use",
    DIB_REFUNDED = "ledger.refund",
    DIB_REVOKED = "ledger.adjust",
    DIB_ADMIN_ADJUSTMENT = "ledger.adjust",
    SEASON_ALLOCATION = "ledger.adjust",
  }
  local actionId = actionByType[payload.actionType or payload.type] or "ledger.adjust"
  local actor = payload.actor or payload.actorIdentity
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate(actionId, actor)
  if not decision or decision.allowed ~= true then
    return { accepted = false, idempotentReplay = false, reasonCode = decision and decision.reasonCode or "AUTHORITY_UNAVAILABLE" }
  end
  local transaction = {}
  for key, value in pairs(payload) do
    if key ~= "actor" and key ~= "actorIdentity" then transaction[key] = value end
  end
  transaction.actorId = transaction.actorId or decision.actorId
  return Dibs.Ledger.AppendTransaction(transaction, { action = actionId, actor = actor })
end

---@param request table|nil Player/season query and actor identity.
---@return table result Permission-filtered transaction list.
function Dibs.CoreAPI.getTransactions(request)
  local payload = request or {}
  local actor = payload.actor or payload.actorIdentity
  local requestedPlayer = payload.playerGuid or payload.playerName
  if not coreActorCanViewAll(actor) then
    requestedPlayer = requestedPlayer or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
    if not coreActorMatchesPlayer(actor, requestedPlayer) then
      return { transactions = {}, reasonCode = "PLAYER_SCOPE_REQUIRED" }
    end
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(payload.seasonId, requestedPlayer) or {}
  return { transactions = transactions }
end

function Dibs.CoreAPI.getPlayerSeasonState(request)
  local payload = request or {}
  local actor = payload.actor or payload.actorIdentity
  local requestedPlayer = payload.playerGuid or payload.playerName
  if not coreActorCanViewAll(actor) then
    requestedPlayer = requestedPlayer or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
    if not coreActorMatchesPlayer(actor, requestedPlayer) then
      return nil, "PLAYER_SCOPE_REQUIRED"
    end
  end
  return Dibs.Ledger and Dibs.Ledger.GetPlayerSeasonState and Dibs.Ledger.GetPlayerSeasonState(payload.seasonId, requestedPlayer)
end

---@param request table Action ID and actor identity to evaluate.
---@return table decision Authorization/readiness decision with stable reason code.
function Dibs.CoreAPI.canExecuteAuthoritativeAction(request)
  local payload = request or {}
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate(payload.actionId, payload.actor)
  if not decision then
    return { allowed = false, authoritySource = "none", reasonCode = "AUTHORITY_UNAVAILABLE" }
  end
  return {
    allowed = decision.allowed == true,
    authoritySource = decision.authority,
    reasonCode = decision.reasonCode,
  }
end

---@param prefix string|nil Identifier prefix.
---@return string id Opaque unique identifier containing a timestamp/counter.
function Dibs.NewId(prefix)
  local timestamp = tostring(time() or 0)
  local randomPart = tostring(math.random(100000, 999999))
  return (prefix or "dibs") .. "-" .. timestamp .. "-" .. randomPart
end

---@return string|nil seasonId Active season identifier, if configured.
function Dibs.GetCurrentSeasonId()
  ensureDB()
  if Dibs.db.currentSeasonId and Dibs.db.currentSeasonId ~= "" then
    return Dibs.db.currentSeasonId
  end

  if Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault then
    local season = Dibs.Seasons.GetOrCreateDefault()
    if season then
      Dibs.db.currentSeasonId = season.id
    end
  end

  return Dibs.db.currentSeasonId
end

---@return string playerName Canonical local player name/GUID representation.
function Dibs.GetPlayerName()
  local name, realm
  if type(UnitFullName) == "function" then
    name, realm = UnitFullName("player")
  end
  name = name or (type(UnitName) == "function" and UnitName("player"))
  if not name then return "UnknownPlayer" end
  realm = realm or (type(GetRealmName) == "function" and GetRealmName())
  if realm and realm ~= "" and not tostring(name):find("-", 1, true) then
    return tostring(name) .. "-" .. tostring(realm)
  end
  return tostring(name)
end

---@return integer timestamp Current Unix timestamp.
function Dibs.GetTimestamp()
  return time()
end

function Dibs.Message(text)
  local value = tostring(text or "")
  local module, level = value:match("^%[([^%]]+)%]%s*"), nil
  if module then
    local suffix = module:match("[Dd]ebug")
    level = suffix and 4 or 1
  else
    module, level = "core", 1
  end
  if Dibs.DebugLogs and Dibs.DebugLogs.Add then Dibs.DebugLogs.Add(module, level, value) end
  -- User-facing command/status messages must remain visible even when an
  -- officer sets a diagnostic module to level 0.  Only explicit diagnostic
  -- messages use the debug-level filter.
  local isDiagnostic = value:match("^%[([^%]]*[Dd]ebug[^%]]*)%]") ~= nil
    or value:match("^EJDBG") ~= nil
  if isDiagnostic and Dibs.DebugEnabled and not Dibs.DebugEnabled(module, level) then return end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff8b5cf6Dibs|r " .. value)
  end
end

function Dibs.DebugEnabled(module, level)
  local settings = Dibs.GetDB and Dibs.GetDB().settings or {}
  local levels = settings.debugLevels or { all = 1 }
  local threshold = tonumber(levels[module])
  if threshold == nil then threshold = tonumber(levels.all) or 1 end
  return (tonumber(threshold) or 0) >= (tonumber(level) or 1)
end

function Dibs.SetDebugLevel(module, level, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  module = string.lower(tostring(module or "all"))
  level = math.max(0, math.min(5, tonumber(level) or 0))
  local settings = Dibs.GetDB().settings
  settings.debugLevels = settings.debugLevels or {}
  settings.debugLevels[module] = level
  return level, nil
end

function Dibs.GetDebugLevels()
  return Dibs.GetDB().settings.debugLevels or { all = 1 }
end

function Dibs.BuildDebugReport()
  local levels = Dibs.GetDebugLevels()
  local size = Dibs.ImportExport and Dibs.ImportExport.GetSizeDiagnostics and Dibs.ImportExport.GetSizeDiagnostics() or {}
  local formatSize = Dibs.ImportExport and Dibs.ImportExport.FormatSize or tostring
  local largestSections = {}
  for index = 1, math.min(5, #(size.largestSections or {})) do
    local section = size.largestSections[index]
    largestSections[#largestSections + 1] = tostring(section.name) .. "=" .. formatSize(section.bytes)
  end
  local clubId, streamId = nil, nil
  if Dibs.PreDibs and Dibs.PreDibs.GetRaidDibsChannel then
    clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  end
  local rc = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or nil
  local vote = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetVotingIntegrationStatus and Dibs.RCLootCouncil.GetVotingIntegrationStatus() or {}
  local projection = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetConfigProjectionStatus and Dibs.RCLootCouncil.GetConfigProjectionStatus() or {}
  local projectionDefault = projection.default or {}
  local additionalCount = 0
  for _ in pairs(projection.additional or {}) do additionalCount = additionalCount + 1 end
  local lines = {
    "Dibs debug report",
    "Version: " .. tostring(Dibs.VERSION),
    "Database size: serializedDB=" .. formatSize(size.databaseBytes) .. " fullPayload=" .. formatSize(size.fullPayloadBytes) .. " fullPackage=" .. formatSize(size.fullPackageBytes) .. " backupLimit=" .. formatSize(size.backupLimitBytes) .. " portableLimit=" .. formatSize(size.portableLimitBytes),
    "Largest full sections: " .. (#largestSections > 0 and table.concat(largestSections, ", ") or "unavailable"),
    "Framework: " .. Dibs.GetFrameworkStatus(),
    "RCLootCouncil: " .. tostring(rc and (rc.diagnostic or rc.status or "available") or "absent") .. " reason=" .. tostring(rc and rc.reasonCode or "RC_ABSENT"),
    "Capabilities: " .. tostring(Dibs.Capabilities and Dibs.Capabilities.FormatDiagnostics and Dibs.Capabilities.FormatDiagnostics() or "unavailable"),
    "RCLootCouncil capabilities: " .. tostring(rc and rc.capabilities and (rc.capabilities.masterLooter and "masterLooter " or "") .. (rc.capabilities.awardCallback and "awardCallback " or "") .. (rc.capabilities.awardIdentity and "awardIdentity" or "none") or "none"),
    "Config projection: addon=" .. tostring(projection.addonFound == true) .. " profiles=" .. tostring(projection.profileCount or 0) .. " defaultButtons=" .. tostring(projectionDefault.activeButtons or "none") .. " dibButton=" .. tostring(projectionDefault.buttonDibIndex or "none") .. " dibResponse=" .. tostring(projectionDefault.responseDibIndex or "none") .. " additionalSets=" .. tostring(additionalCount),
    "Voting frame: module=" .. tostring(vote.moduleFound) .. " AddColumn=" .. tostring(vote.addColumn) .. " scrollCols=" .. tostring(vote.scrollColumns) .. " count=" .. tostring(vote.scrollColumnCount) .. " hasDibs=" .. tostring(vote.scrollHasDibs) .. " renderedDibs=" .. tostring(vote.renderedHasDibs) .. " DibsColumn=" .. tostring(vote.dibsColumnInstalled),
    "Season: " .. tostring(Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or "none"),
    "Raid Dibs: " .. (clubId and ("available clubId=" .. tostring(clubId) .. " streamId=" .. tostring(streamId)) or "unavailable"),
    "Debug levels: all=" .. tostring(levels.all or 1) .. " announce=" .. tostring(levels.announce or "inherit") .. " sync=" .. tostring(levels.sync or "inherit") .. " ui=" .. tostring(levels.ui or "inherit") .. " encounter_journal=" .. tostring(levels.encounter_journal or "inherit"),
  }
  local moduleDiagnostics = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleManagementDiagnostics
    and Dibs.OperationalPolicy.GetModuleManagementDiagnostics(nil)
  if moduleDiagnostics then
    lines[#lines + 1] = "Module management: governanceInitialized=" .. tostring(moduleDiagnostics.governanceInitialized)
      .. " governanceActive=" .. tostring(moduleDiagnostics.governanceActive)
      .. " governanceRevision=" .. tostring(moduleDiagnostics.governanceRevision)
      .. " canonicalPlayer=" .. tostring(moduleDiagnostics.canonicalPlayer or "unavailable")
      .. " governanceGM=" .. tostring(moduleDiagnostics.governanceGM or "unavailable")
      .. " gmIdentityMatch=" .. tostring(moduleDiagnostics.gmIdentityMatch)
      .. " operationalPolicyReady=" .. tostring(moduleDiagnostics.operationalPolicyReady)
      .. " canManageModules=" .. tostring(moduleDiagnostics.canManageModules)
      .. " blockingReason=" .. tostring(moduleDiagnostics.blockingReason or "none")
  end
  return table.concat(lines, "\n")
end

function Dibs.GetFrameworkStatus()
  local ace3 = Dibs.Ace3
  local libraries = ace3 and ace3.libs or {}
  local function enabled(name)
    return libraries and libraries[name] and "yes" or "no"
  end
  return "Ace3: GUI=" .. enabled("gui") ..
    " | Config=" .. enabled("config") ..
    " | Comm=" .. enabled("comm") ..
    " | Event=" .. enabled("event") ..
    " | Timer=" .. enabled("timer")
end

function Dibs.ApplyDefaultRules()
  ensureDB()
  local season = Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault()
  if not season then
    return
  end

  for rankIndex = 0, 5 do
    local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason(season.id) or {}
    local existing = rules[tostring(rankIndex)]
    if existing == nil then
      Dibs.RankRules.SetAllocation(season.id, rankIndex, "Rank " .. tostring(rankIndex), 1)
    end
  end

  local playerState = Dibs.Ledger and Dibs.Ledger.GetPlayerState(Dibs.GetPlayerName(), season.id)
  if playerState and (tonumber(playerState.allocation) or 0) == 0 then
    Dibs.Ledger.RegisterSeasonAllocation(Dibs.GetPlayerName(), season.id, 1, "Initial season allocation")
  end
end

function Dibs.HandleSlashCommand(msg)
  local command = (msg or ""):match("^%s*(.-)%s*$")
  local action = command:match("^(%S+)") or ""
  local rest = command:match("^%S+%s+(.+)$") or ""
  local args = {}
  for token in string.gmatch(command, "%S+") do
    table.insert(args, token)
  end

  if action == "debug" then
    local module = string.lower(args[2] or "all")
    if module == "logs" then
      if Dibs.DebugLogs and Dibs.DebugLogs.Open then Dibs.DebugLogs.Open() end
      return
    end
    if module == "report" then
      Dibs.Message(Dibs.BuildDebugReport())
      return
    end
    if module == "rc" or module == "projection" then
      if Dibs.RCLootCouncil and Dibs.RCLootCouncil.RefreshConfigProjection then
        local ok, changedOrReason = Dibs.RCLootCouncil.RefreshConfigProjection()
        if ok then
          Dibs.Message("RCLootCouncil DIB projection refreshed (changed=" .. tostring(changedOrReason == true) .. "). Run /dibs debug report for the detected profile.")
        else
          Dibs.Message("RCLootCouncil DIB projection unavailable: " .. tostring(changedOrReason))
        end
      end
      return
    end
    local level = tonumber(args[3])
    if level == nil or level < 0 or level > 5 then
      Dibs.Message("Usage: /dibs debug <module|all> 0-5")
      return
    end
    local applied, reason = Dibs.SetDebugLevel(module, level)
    if applied == nil then
      Dibs.Message("Only the guild master or an officer may change Dibs settings (" .. tostring(reason) .. ").")
    else
      Dibs.Message("Debug level " .. module .. " = " .. tostring(applied))
    end
    return
  end

  if action == "overview" then
    Dibs.Message(Dibs.OfficerUI and Dibs.OfficerUI.BuildStatusText and Dibs.OfficerUI.BuildStatusText() or "Dibs overview unavailable.")
    return
  end

  if action == "readiness" or action == "ready" or action == "preflight" then
    if Dibs.Readiness and type(Dibs.Readiness.OpenReport) == "function" then
      local shell, report, reason = Dibs.Readiness.OpenReport("detailed")
      if not shell and report then
        Dibs.Message(report)
      elseif not shell then
        Dibs.Message("Readiness unavailable: " .. tostring(reason))
      end
    elseif Dibs.Readiness and type(Dibs.Readiness.Run) == "function" then
      local result, reason = Dibs.Readiness.Run()
      Dibs.Message(result and Dibs.Readiness.FormatSummary(result, true) or ("Readiness unavailable: " .. tostring(reason)))
    else
      Dibs.Message("Raid readiness is unavailable.")
    end
    return
  end

  if action == "dryrun" or action == "dry-run" then
    if Dibs.DryRun and type(Dibs.DryRun.RunFromSlash) == "function" then
      local result, reason = Dibs.DryRun.RunFromSlash(rest)
      if result then
        Dibs.Message(Dibs.DryRun.Format(result))
      elseif reason == "USAGE" then
        Dibs.Message("Usage: /dibs dryrun <itemID/link> <winner> <response> <finalized|test|pending> [session]")
      else
        Dibs.Message("Dry-run unavailable: " .. tostring(reason))
      end
    else
      Dibs.Message("Dibs dry-run is unavailable.")
    end
    return
  end

  if action == "" or action == "help" then
    Dibs.Message("Dibs commands: /dibs help | /dibs status | /dibs readiness | /dibs dryrun <item> <winner> <response> <status> [session] | /dibs balance | /dibs ui | /dibs requests | /dibs options | /dibs data | /dibs officer | /dibs review | /dibs reconcile | /dibs grant <player> <amount> | /dibs use <player> <amount> | /dibs pre <itemID> [itemName] | /dibs season create [name] | /dibs season set <id> | /dibs rank set <index> <amount> [name]")
    Dibs.Message("Developer commands (Developer Mode required): /dibs dev on | /dibs dev off | /dibs dev status | /dibs testitem <itemID>")
    Dibs.Message("Debug commands: /dibs ejdebug | /dibs ejsub list|scan|matrix|apply recommended|block <SUB>|allow <SUB>|clear | /dibs announce debug on|off|scan")
    return
  end

  if action == "status" then
    Dibs.Message(Dibs.GetFrameworkStatus())
    return
  end

  if action == "announce" then
    local mode = args[2] or "scan"
    if mode == "debug" then
      local enabled = string.lower(args[3] or "off") == "on"
      local applied, reason = Dibs.PreDibs.SetAnnouncementDebug(enabled)
      if applied == nil then
        Dibs.Message("Only the guild master or an officer may change Dibs settings (" .. tostring(reason) .. ").")
      else
        Dibs.Message("Announcement debug " .. (applied and "ON" or "OFF") .. ".")
      end
    elseif mode == "scan" then
      if Dibs.PreDibs and Dibs.PreDibs.DebugRaidDibs then
        Dibs.PreDibs.DebugRaidDibs()
      else
        Dibs.Message("Announcement debug is unavailable.")
      end
    else
      Dibs.Message("Usage: /dibs announce debug on|off|scan")
    end
    return
  end

  if action == "ejdebug" then
    if Dibs.EncounterJournal and Dibs.EncounterJournal.DumpVisibleLootDebug then
      Dibs.EncounterJournal.DumpVisibleLootDebug()
    else
      Dibs.Message("Encounter Journal debug is unavailable.")
    end
    return
  end

  if action == "ejsub" then
    if Dibs.EncounterJournal and Dibs.EncounterJournal.HandleSubCategorySlash then
      Dibs.EncounterJournal.HandleSubCategorySlash(rest)
    else
      Dibs.Message("Encounter Journal sub-category controls are unavailable.")
    end
    return
  end

  if action == "dev" then
    if Dibs.DeveloperMode and Dibs.DeveloperMode.HandleDevSlash then
      Dibs.DeveloperMode.HandleDevSlash(args)
    else
      Dibs.Message("Developer mode module unavailable.")
    end
    return
  end

  if action == "testitem" then
    if Dibs.DeveloperMode and Dibs.DeveloperMode.HandleTestItemSlash then
      Dibs.DeveloperMode.HandleTestItemSlash(rest)
    else
      Dibs.Message("Developer mode module unavailable.")
    end
    return
  end

  if action == "balance" then
    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
    local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(Dibs.GetPlayerName(), season and season.id) or 0
    Dibs.Message("Current balance: " .. tostring(balance))
    return
  end

  if action == "options" then
    if Dibs.RCOptions and Dibs.RCOptions.Open then Dibs.RCOptions.Open() end
    return
  end

  if action == "ui" then
    if Dibs.PlayerUI and Dibs.PlayerUI.Show then
      Dibs.PlayerUI.Show()
    end
    return
  end

  if action == "officer" then
    if Dibs.OfficerUI and Dibs.OfficerUI.Show then
      Dibs.OfficerUI.Show()
    end
    return
  end

  if action == "data" or action == "backup" or action == "profiles" or action == "import" or action == "export" then
    local tab = action == "profiles" and "profiles" or ((action == "import" or action == "export") and "transfer" or "backups")
    if Dibs.DataUI and Dibs.DataUI.Open then Dibs.DataUI.Open(tab) else Dibs.Message("Data window is unavailable until AceGUI is loaded.") end
    return
  end

  if action == "requests" or action == "report" then
    local enabled, message = true, nil
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.RequireModuleEnabled then
      enabled, _, message = Dibs.OperationalPolicy.RequireModuleEnabled("requests")
    end
    if not enabled then Dibs.Message(message or "Requests is disabled by the Guild Master."); return end
    local frame = Dibs.PlayerUI and Dibs.PlayerUI.CreateWindow and Dibs.PlayerUI.CreateWindow()
    if frame and frame.SelectTab then frame.SelectTab("requests") end
    if frame then frame:Show(); frame:Raise() end
    return
  end

  if action == "review" or action == "disputes" then
    local enabled, message = true, nil
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.RequireModuleEnabled then
      enabled, _, message = Dibs.OperationalPolicy.RequireModuleEnabled("requests")
    end
    if not enabled then Dibs.Message(message or "Requests is disabled by the Guild Master."); return end
    if Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
      local opened = Dibs.OfficerUI.Toggle(true)
      local frame = opened and _G.DibsOfficerFrame or nil
      if frame and frame.SelectTab then frame.SelectTab("disputes") end
    end
    return
  end

  if action == "reconcile" or action == "history" then
    local enabled, message = true, nil
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.RequireModuleEnabled then
      enabled, _, message = Dibs.OperationalPolicy.RequireModuleEnabled("historicalReconciliation")
    end
    if action == "reconcile" and not enabled then Dibs.Message(message or "Historical Reconciliation is disabled by the Guild Master."); return end
    if Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
      local opened = Dibs.OfficerUI.Toggle(true)
      local frame = opened and _G.DibsOfficerFrame or nil
      if frame and frame.SelectTab then frame.SelectTab("reconciliation") end
    end
    return
  end

  if action == "grant" then
    if not Dibs.Permissions or not Dibs.Permissions.CanManageDibs() then
      Dibs.Message("You do not have permission to grant Dibs.")
      return
    end

    local playerName = args[2]
    local amount = tonumber(args[3]) or 1
    local result = Dibs.ProtectedActions.Execute("ledger.grant", nil, { playerName = playerName, amount = amount, reason = "Officer grant", source = "slash" })
    Dibs.Message(result.ok and ("Granted " .. tostring(amount) .. " Dibs to " .. tostring(playerName)) or result.diagnostic)
    return
  end

  if action == "use" then
    if not Dibs.Permissions or not Dibs.Permissions.CanManageDibs() then
      Dibs.Message("You do not have permission to consume Dibs.")
      return
    end

    local playerName = args[2]
    local amount = tonumber(args[3]) or 1
    local result = Dibs.ProtectedActions.Execute("ledger.use", nil, { playerName = playerName, amount = amount, reason = "Officer consumption", source = "slash" })
    Dibs.Message(result.ok and ("Consumed " .. tostring(amount) .. " Dibs from " .. tostring(playerName)) or result.diagnostic)
    return
  end

  if action == "pre" then
    local enabled, message = true, nil
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.RequireModuleEnabled then
      enabled, _, message = Dibs.OperationalPolicy.RequireModuleEnabled("preDibs")
    end
    if not enabled then Dibs.Message(message or "Pre-Dibs is disabled by the Guild Master."); return end
    local itemID = tonumber(args[2]) or 0
    local itemName = table.concat(args, " ", 3)
    local payloadName = itemName ~= "" and itemName or "Item " .. tostring(itemID)
    local request, reason
    if Dibs.PreDibs and Dibs.PreDibs.CreatePublic and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() then
      request, reason = Dibs.PreDibs.CreatePublic(Dibs.GetPlayerName(), itemID, payloadName, Dibs.GetCurrentSeasonId(), "slash")
    else
      request = Dibs.PreDibs.Create(Dibs.GetPlayerName(), itemID, payloadName, Dibs.GetCurrentSeasonId())
    end

    if request then
      Dibs.Message("Pre-Dib created for item " .. tostring(itemID) .. " (status: " .. tostring(request.status) .. ")")
    else
      Dibs.Message(reason == "PUBLIC_PRE_DIBS_DISABLED" and "Public pre-dibs are disabled." or "A valid item ID is required.")
    end
    return
  end

  if action == "vault" then
    local record, reason = Dibs.PreDibs and Dibs.PreDibs.RecordVaultAcquisition and Dibs.PreDibs.RecordVaultAcquisition(Dibs.GetPlayerName(), args[2], args[3]) or nil, "ACQUISITIONS_UNAVAILABLE"
    if record then
      Dibs.Message("Vault acquisition recorded for item " .. tostring(record.itemID) .. " (" .. tostring(record.difficulty) .. ").")
    else
      Dibs.Message(reason == "INVALID_ITEM" and "A valid item ID is required." or "Unable to record Vault acquisition.")
    end
    return
  end

  if action == "predibmode" then
    local result = Dibs.ProtectedActions.Execute("predib.mode.set", nil, { seasonId = Dibs.GetCurrentSeasonId(), mode = args[2], source = "slash" })
    Dibs.Message(result.ok and ("Pre-Dib mode: " .. tostring(result.value.mode)) or (result.diagnostic or "Unable to change Pre-Dib mode."))
    return
  end

  if action == "mode" then
    local mode = args[2] or "AUTO"
    local result = Dibs.ProtectedActions.Execute("installation.mode.set", nil, { mode = mode, source = "slash" })
    Dibs.Message(result.ok and ("Installation mode: " .. tostring(result.value)) or (result.diagnostic or "Unable to change installation mode."))
    return
  end

  if action == "remind" then
    local ok, reason = Dibs.RaidRelay and Dibs.RaidRelay.SendReminder and Dibs.RaidRelay.SendReminder(rest) or false, "REMINDER_UNAVAILABLE"
    Dibs.Message(ok and "Dib reminder sent." or (reason or "Unable to send Dib reminder."))
    return
  end

  if action == "admin" then
    local mode, target = args[2] or "list", args[3]
    if mode == "list" then
      local result = Dibs.ProtectedActions.Execute("admin.list", nil, {})
      if not result.ok then Dibs.Message(result.diagnostic) return end
      local names = {}
      for _, admin in ipairs(result.value) do table.insert(names, tostring(admin.playerName)) end
      table.sort(names)
      Dibs.Message("Standalone Dibs administrators: " .. (#names > 0 and table.concat(names, ", ") or "none"))
      return
    end
    local actionId = mode == "add" and "admin.appoint" or (mode == "remove" and "admin.revoke" or nil)
    if not actionId or not target then Dibs.Message("Usage: /dibs admin list|add|remove <Name-Realm>") return end
    local result = Dibs.ProtectedActions.Execute(actionId, nil, { target = target, reason = "Slash command" })
    Dibs.Message(result.ok and ("Standalone administrator updated: " .. target) or result.diagnostic)
    return
  end

  if action == "season" then
    local mode = args[2] or "show"
    if mode == "create" then
      local name = table.concat(args, " ", 3)
       local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name ~= "" and name or nil })
       local season = result.value
      if season then
        Dibs.Message("Created season: " .. tostring(season.name) .. " (" .. tostring(season.id) .. ")")
      else
        Dibs.Message("Failed to create season.")
      end
      return
    end

    if mode == "set" then
      local seasonId = args[3]
       local result = Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = seasonId })
       if result.ok then
        Dibs.Message("Current season set to: " .. tostring(seasonId))
      else
        Dibs.Message("Season not found: " .. tostring(seasonId))
      end
      return
    end

    if mode == "list" then
      local list = Dibs.Seasons and Dibs.Seasons.List() or {}
      local currentSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
      local text = "Seasons: "
      for _, season in ipairs(list) do
        local marker = season.id == currentSeasonId and " [ACTIVE]" or ""
        text = text .. tostring(season.name) .. " (" .. tostring(season.id) .. ")" .. marker .. ", "
      end
      Dibs.Message(text)
      return
    end

    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent()
    Dibs.Message("Current season: " .. tostring(season and season.name or "None") .. " (" .. tostring(season and season.id or "none") .. ")")
    return
  end

  if action == "rcopts" then
    if Dibs.RCOptions and Dibs.RCOptions.EnsureRegistered then
      local ok = Dibs.RCOptions.EnsureRegistered(10)
      Dibs.Message(ok and "RC options registration confirmed." or "RC options registration retry started.")
    else
      Dibs.Message("RC options integration module is unavailable.")
    end
    return
  end

  if action == "rank" then
    local mode = args[2] or "list"
    if mode == "set" then
      local rankIndex = tonumber(args[3]) or 0
      local allocation = tonumber(args[4]) or 1
      local rankName = table.concat(args, " ", 5)
       if Dibs.ProtectedActions then
         local result = Dibs.ProtectedActions.Execute("rank.set", nil, { seasonId = Dibs.GetCurrentSeasonId(), rankIndex = rankIndex, rankName = rankName ~= "" and rankName or "Rank " .. tostring(rankIndex), allocation = allocation })
         local rule = result.value
         if not result.ok then Dibs.Message(result.diagnostic) return end
        Dibs.Message("Rank " .. tostring(rankIndex) .. " set to " .. tostring(rule.allocation) .. " Dibs")
      end
      return
    end

    if mode == "list" then
      local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
      local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason(season and season.id or Dibs.GetCurrentSeasonId()) or {}
      local text = "Rank rules: "
      local items = {}
      for _, rule in pairs(rules) do
        table.insert(items, "R" .. tostring(rule.rankIndex) .. "=" .. tostring(rule.allocation))
      end
      table.sort(items)
      text = text .. table.concat(items, ", ")
      Dibs.Message(text)
      return
    end
  end

  Dibs.Message("Unknown Dibs command. Use /dibs help.")
end

function Dibs.SetupSlashCommands()
  -- SlashCmdList is normally present while the TOC is loading, but a
  -- load-on-demand/early-login path can expose it a little later.  Creating
  -- the table and repeating this idempotently at Initialize makes the command
  -- available in both paths.
  _G.SlashCmdList = _G.SlashCmdList or {}
  _G.SlashCmdList["DIBS"] = function(msg)
    return Dibs.HandleSlashCommand(msg)
  end
  _G.SLASH_DIBS1 = "/dibs"
  _G.SLASH_DIBS2 = "/dib"
  _G.SLASH_DIBS3 = "/dids"

  -- Retail resolves chat input through a cached uppercase hash.  Importing
  -- the registries is the supported path, but keep the direct entries in sync
  -- as a fallback for clients that expose the hash before ChatFrameUtil does.
  local slashHash = _G.hash_SlashCmdList
  if type(slashHash) == "table" then
    pcall(function()
      slashHash["/DIBS"] = "DIBS"
      slashHash["/DIB"] = "DIBS"
      slashHash["/DIDS"] = "DIBS"
    end)
  end

  -- Retail's chat frame keeps a second hash registry for slash commands.  It
  -- is normally populated during Blizzard startup, but this addon can load
  -- after that point (or after a load-on-demand reload).  Re-importing is
  -- idempotent and makes all three aliases immediately executable.
  local chatUtil = _G.ChatFrameUtil
  if type(chatUtil) == "table" and type(chatUtil.ImportAllListsToHash) == "function" then
    pcall(chatUtil.ImportAllListsToHash)
  elseif type(_G.ChatFrame_ImportAllListsToHash) == "function" then
    pcall(_G.ChatFrame_ImportAllListsToHash)
  end
end

-- Keep /dibs available even when an optional integration initializes later.
Dibs.SetupSlashCommands()

function Dibs.RegisterOptionsPanel()
  local rcLoaded = false
  if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
    local first, second = C_AddOns.IsAddOnLoaded("RCLootCouncil")
    rcLoaded = (second == true or first == true)
  end
  if not rcLoaded then
    rcLoaded = type(_G.RCLootCouncil) == "table"
  end

  -- When RCLootCouncil is present, Dibs registers under its options tree via integrations/RCLootCouncilOptions.lua.
  if rcLoaded then
    return nil
  end

  if _G.DibsOptionsPanel then
    return _G.DibsOptionsPanel
  end

  local panel = CreateFrame("Frame", "DibsOptionsPanel", UIParent)
  panel.name = "Dibs"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Dibs")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetWidth(520)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Use this panel to open Dibs windows quickly. Commands: /dibs ui, /dibs officer.")

  local openPlayerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openPlayerButton:SetSize(140, 24)
  openPlayerButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
  openPlayerButton:SetText("Open Player UI")
  openPlayerButton:SetScript("OnClick", function()
    if Dibs.PlayerUI and Dibs.PlayerUI.Toggle then
      Dibs.PlayerUI.Toggle(true)
    end
  end)

  local openOfficerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openOfficerButton:SetSize(140, 24)
  openOfficerButton:SetPoint("LEFT", openPlayerButton, "RIGHT", 12, 0)
  openOfficerButton:SetText("Open Officer UI")
  openOfficerButton:SetScript("OnClick", function()
    if Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
      Dibs.OfficerUI.Toggle(true)
    end
  end)

  if _G.Settings and type(_G.Settings.RegisterCanvasLayoutCategory) == "function"
    and type(_G.Settings.RegisterAddOnCategory) == "function" then
    local category = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    _G.Settings.RegisterAddOnCategory(category)
  end

  _G.DibsOptionsPanel = panel
  return panel
end

local function registerOptionalCapabilities()
  local capabilities = rawget(Dibs, "Capabilities")
  if not capabilities or not capabilities.Register then return end
  capabilities.Register("player_ui", { dependency = "Dibs UI", initialize = function()
    return Dibs.PlayerUI and Dibs.PlayerUI.CreateWindow and Dibs.PlayerUI.CreateWindow() or false
  end })
  capabilities.Register("officer_ui", { dependency = "Dibs UI", initialize = function()
    return Dibs.OfficerUI and Dibs.OfficerUI.CreateWindow and Dibs.OfficerUI.CreateWindow() or false
  end })
  capabilities.Register("rclootcouncil", { dependency = "RCLootCouncil", retryEvents = { "RCLootCouncil_LOADED", "PLAYER_ENTERING_WORLD" }, initialize = function()
    local ok = Dibs.RCLootCouncil and Dibs.RCLootCouncil.Initialize and Dibs.RCLootCouncil.Initialize()
    if ok then return true end
    local status = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or {}
    return false, status.reasonCode or "RCLC_UNAVAILABLE"
  end })
  capabilities.Register("encounter_journal", { dependency = "Blizzard_EncounterJournal", retryEvents = { "Blizzard_EncounterJournal_LOADED" }, initialize = function()
    local ok = false
    local reason = "ENCOUNTER_JOURNAL_UNAVAILABLE"
    if Dibs.EncounterJournal and Dibs.EncounterJournal.AddActionIfAvailable then
      ok, reason = Dibs.EncounterJournal.AddActionIfAvailable(0)
    end
    return ok == true, reason or "ENCOUNTER_JOURNAL_UNAVAILABLE"
  end })
  capabilities.Register("options_panel", { dependency = "Retail Settings", initialize = function()
    Dibs.RegisterOptionsPanel(); return true
  end })
  capabilities.Register("rclootcouncil_options", { dependency = "RCLootCouncil options", retryEvents = { "RCLootCouncil_LOADED", "PLAYER_REGEN_ENABLED" }, initialize = function()
    local ok = Dibs.RCOptions and Dibs.RCOptions.EnsureRegistered and Dibs.RCOptions.EnsureRegistered(1)
    return ok == true, "RC_OPTIONS_UNAVAILABLE"
  end })
end

local function initializeOptionalCapabilities()
  local capabilities = rawget(Dibs, "Capabilities")
  if not capabilities or not capabilities.Initialize then return end
  for _, id in ipairs({ "player_ui", "officer_ui", "rclootcouncil", "encounter_journal", "options_panel", "rclootcouncil_options" }) do
    capabilities.Initialize(id, "STARTUP")
  end
end

function Dibs.Initialize()
  if Dibs.initialized then
    return true
  end

  ensureDB()

  if Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault then
    Dibs.Seasons.GetOrCreateDefault()
  end

  if Dibs.RankRules then
    Dibs.ApplyDefaultRules()
  end

  if Dibs.Sync and Dibs.Sync.RegisterTransport then
    Dibs.Sync.RegisterTransport()
  end
  if Dibs.Sync and Dibs.Sync.OnLifecycle then Dibs.Sync.OnLifecycle("STARTUP") end

  Dibs.SetupSlashCommands()
  registerOptionalCapabilities()
  initializeOptionalCapabilities()
  Dibs.initialized = true
  Dibs.Message("Dibs initialized")
  return true
end

local eventFrame = CreateFrame("Frame")
local function onRuntimeEvent(event, ...)
  if event == "PLAYER_LOGIN" then
    Dibs.Initialize()
    if Dibs.RCLootCouncil and Dibs.RCLootCouncil.Initialize then Dibs.RCLootCouncil.Initialize() end
    -- Core initialization must never depend on the optional adapter.  A late
    -- RCLootCouncil load is rechecked after Dibs is ready, while Standalone
    -- mode still receives the normal database, UI, and slash-command setup.
    if Dibs.Capabilities and Dibs.Capabilities.Retry then Dibs.Capabilities.Retry("rclootcouncil", "PLAYER_LOGIN") end
    if Dibs.Readiness and Dibs.Readiness.Invalidate then Dibs.Readiness.Invalidate("PLAYER_LOGIN") end
    return
  end
  if event == "ADDON_LOADED" then
    local loadedAddon = ...
    -- RCLootCouncil can be enabled load-on-demand after Dibs. Re-run only the
    -- optional adapter when its addon becomes available; Standalone mode is
    -- unaffected.
    if loadedAddon == "RCLootCouncil" then
      if Dibs.RCLootCouncil and Dibs.RCLootCouncil.Initialize then Dibs.RCLootCouncil.Initialize() end
      if Dibs.Capabilities and Dibs.Capabilities.Retry then
        Dibs.Capabilities.Retry("rclootcouncil", "RCLootCouncil_LOADED")
        Dibs.Capabilities.Retry("rclootcouncil_options", "RCLootCouncil_LOADED")
      end
      if Dibs.Readiness and Dibs.Readiness.Invalidate then Dibs.Readiness.Invalidate("RCLootCouncil lifecycle") end
    end
    if loadedAddon == "Blizzard_EncounterJournal" and Dibs.Capabilities and Dibs.Capabilities.Retry then
      Dibs.Capabilities.Retry("encounter_journal", "Blizzard_EncounterJournal_LOADED")
    end
    return
  end
  if event == "PLAYER_ENTERING_WORLD"
    and Dibs.Capabilities
    and Dibs.Capabilities.Retry
  then
    if Dibs.RCLootCouncil and Dibs.RCLootCouncil.Initialize then Dibs.RCLootCouncil.Initialize() end
    -- A reload can restore RCLootCouncil's AceDB after ADDON_LOADED. Retry at
    -- the first world entry so its profile and ML module are ready before the
    -- Master Looter options are opened.
    Dibs.Capabilities.Retry("rclootcouncil", "PLAYER_ENTERING_WORLD")
    if Dibs.Readiness and Dibs.Readiness.Invalidate then Dibs.Readiness.Invalidate("PLAYER_ENTERING_WORLD") end
  end
  if event == "CHAT_MSG_ADDON" and Dibs.Sync and Dibs.Sync.OnAddonMessage then return Dibs.Sync.OnAddonMessage(...) end
  if event == "GROUP_ROSTER_UPDATE" and Dibs.Sync and Dibs.Sync.OnRosterChanged then Dibs.Sync.OnRosterChanged() end
  if event == "GUILD_ROSTER_UPDATE" then
    if Dibs.Identity and Dibs.Identity.OnRosterChanged then Dibs.Identity.OnRosterChanged() end
    if Dibs.Sync and Dibs.Sync.OnRosterChanged then Dibs.Sync.OnRosterChanged() end
  end
  if Dibs.Readiness and Dibs.Readiness.Invalidate
    and (event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_REGEN_ENABLED")
  then
    Dibs.Readiness.Invalidate(event)
  end
  if event == "PLAYER_REGEN_ENABLED" and Dibs.RCLootCouncil and Dibs.RCLootCouncil.OnCombatEnded then
    Dibs.RCLootCouncil.OnCombatEnded()
  end
  if Dibs.RaidPrompts and Dibs.RaidPrompts.OnEvent then Dibs.RaidPrompts.OnEvent(event) end
end

function Dibs.SetupRuntimeEvents()
  if Dibs.runtimeEventsRegistered then return true end
  local events = { "PLAYER_LOGIN", "ADDON_LOADED", "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }
  local usingAceEvent = Dibs.Ace3 and Dibs.Ace3.RegisterEvent
  if usingAceEvent then
    for _, event in ipairs(events) do Dibs.Ace3.RegisterEvent(event, onRuntimeEvent) end
    if not (Dibs.Sync and Dibs.Sync.RegisterTransport and Dibs.Sync.RegisterTransport()) then
      Dibs.Ace3.RegisterEvent("CHAT_MSG_ADDON", onRuntimeEvent)
    end
  else
    for _, event in ipairs(events) do eventFrame:RegisterEvent(event) end
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:SetScript("OnEvent", function(_, event, ...) return onRuntimeEvent(event, ...) end)
  end
  Dibs.runtimeEventsRegistered = true
  return true
end

ensureDB()
