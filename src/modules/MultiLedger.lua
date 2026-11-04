--[[
Module: Dibs.MultiLedger
Layer: Domain / Multi-ledger management facade
Purpose: Manage multiple concurrent guild ledgers, active ledger context,
proposal by officers, and approval by the Guild Master.
Responsibilities: Isolate ledger storage partitions, track active ledger, validate lifecycle.
Dependencies: Dibs.Identity, Dibs.Permissions, Dibs.Ledger, Dibs.Governance.
SavedVariables: db.ledgers, db.activeLedgerId.
]]

local Dibs = _G.Dibs
Dibs.MultiLedger = Dibs.MultiLedger or {}
local MultiLedger = Dibs.MultiLedger

local DEFAULT_LEDGER_ID = "guild-primary"

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function copy(value)
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

local function ensureLedgers()
  local db = Dibs.GetDB and Dibs.GetDB()
  if not db then return nil end

  if type(db.ledgers) ~= "table" then
    db.ledgers = {}
  end

  if not db.ledgers[DEFAULT_LEDGER_ID] then
    if type(db.ledger) == "table" and db.ledger.transactions then
      db.ledgers[DEFAULT_LEDGER_ID] = db.ledger
    else
      db.ledgers[DEFAULT_LEDGER_ID] = {
        transactions = {},
        playerStates = {},
        awardTransactions = {},
        evidenceTransactions = {},
        canonical = { schema = 1, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
      }
    end
  end

  local primary = db.ledgers[DEFAULT_LEDGER_ID]
  primary.id = DEFAULT_LEDGER_ID
  primary.name = primary.name or "Primary"
  primary.status = "APPROVED"
  primary.isDefault = true

  if type(db.activeLedgerId) ~= "string" or not db.ledgers[db.activeLedgerId] then
    db.activeLedgerId = DEFAULT_LEDGER_ID
  end

  -- Keep legacy pointer in sync with active ledger
  db.ledger = db.ledgers[db.activeLedgerId]

  return db
end

local function resolveLedger(db, ledgerId)
  local ledger = db.ledgers[ledgerId]
  if not ledger then
    for _, candidate in pairs(db.ledgers) do
      if candidate.name and string.lower(candidate.name) == string.lower(ledgerId) then
        return candidate.id, candidate
      end
    end
  end
  return ledgerId, ledger
end

local function isLocallyApproved(ledgerId, ledger)
  if not ledger or ledger.status ~= "APPROVED" then return false end
  if ledgerId == DEFAULT_LEDGER_ID then return true end
  return not (Dibs.Governance and Dibs.Governance.IsLedgerApproved)
    or Dibs.Governance.IsLedgerApproved(ledgerId) == true
end

local function activateLedger(db, ledgerId, ledger)
  if Dibs.PreDibs and Dibs.PreDibs.SetLedgerContext then
    local scoped, scopeReason = Dibs.PreDibs.SetLedgerContext(ledgerId)
    if not scoped then return false, scopeReason or "LEDGER_NOT_APPROVED" end
  end
  db.activeLedgerId = ledgerId
  db.ledger = ledger
  return true
end

local enforcingGuildLedger = false

local function imposedLedgerId()
  local policy = Dibs.OperationalPolicy
  return policy and type(policy.GetActiveLedgerId) == "function" and policy.GetActiveLedgerId() or nil
end

local function refreshOpenWindows()
  for _, frame in ipairs({ _G.DibsPlayerFrame, _G.DibsOfficerFrame }) do
    if type(frame) == "table" and type(frame.Refresh) == "function" then pcall(frame.Refresh, frame) end
  end
end

-- Aligns the local working ledger with the guild-imposed one carried by the
-- synchronized operational policy. Without an imposed ledger, the local
-- choice remains (legacy behavior).
function MultiLedger.EnforceGuildActiveLedger(silent)
  if enforcingGuildLedger then return true, "ENFORCEMENT_IN_PROGRESS" end
  local db = ensureLedgers()
  if not db then return false, "DB_UNAVAILABLE" end
  local imposed = imposedLedgerId()
  if not imposed then return true, "NOT_IMPOSED" end
  if db.activeLedgerId == imposed then return true, "IMPOSED" end
  local ledger = db.ledgers[imposed]
  if not isLocallyApproved(imposed, ledger) then return false, "GUILD_ACTIVE_LEDGER_UNAVAILABLE" end
  enforcingGuildLedger = true
  local ok, reason = activateLedger(db, imposed, ledger)
  enforcingGuildLedger = false
  if not ok then return false, reason end
  if MultiLedger.viewLedgerId == imposed then MultiLedger.viewLedgerId = nil end
  if silent ~= true then refreshOpenWindows() end
  return true, "IMPOSED"
end

function MultiLedger.GetActiveLedgerId()
  if not enforcingGuildLedger then MultiLedger.EnforceGuildActiveLedger(true) end
  local db = ensureLedgers()
  return db and db.activeLedgerId or DEFAULT_LEDGER_ID
end

function MultiLedger.GetGuildActiveLedgerId()
  return imposedLedgerId()
end

-- Fails closed when the guild imposes a ledger that is not yet usable locally
-- (catalog not synchronized, archived, or unapproved).
function MultiLedger.RequireGuildActiveLedger()
  local imposed = imposedLedgerId()
  if not imposed then return true end
  if MultiLedger.GetActiveLedgerId() ~= imposed then return false, "GUILD_ACTIVE_LEDGER_UNAVAILABLE" end
  return true
end

function MultiLedger.GetGuildLedgerStatus()
  local db = ensureLedgers()
  local active = MultiLedger.GetActiveLedgerId()
  local imposed = imposedLedgerId()
  local function ledgerName(id)
    local ledger = db and id and db.ledgers[id]
    return ledger and ledger.name or (id == DEFAULT_LEDGER_ID and "Primary") or id
  end
  local state = not imposed and "NOT_IMPOSED" or (active == imposed and "IMPOSED" or "UNAVAILABLE")
  return {
    state = state,
    activeLedgerId = active,
    activeLedgerName = ledgerName(active),
    imposedLedgerId = imposed,
    imposedLedgerName = imposed and ledgerName(imposed) or nil,
    viewLedgerId = MultiLedger.GetViewLedgerId(),
    viewLedgerName = ledgerName(MultiLedger.GetViewLedgerId()),
  }
end

function MultiLedger.CanSetGuildActiveLedger(actor)
  if not (Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite) then return false, "POLICY_UNAVAILABLE" end
  local name = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName())
  local policyState = Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or {}
  if policyState.status ~= "POLICY_ADOPTED" then
    local snapshot = Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.Identity.CreateSnapshot(name)
    local gm = snapshot and Dibs.Identity.IsCurrentGuildMaster and Dibs.Identity.IsCurrentGuildMaster(snapshot)
    if gm then return true end
    return false, "POLICY_UNINITIALIZED"
  end
  return Dibs.OperationalPolicy.CanWrite(name)
end

-- GM/Officer only: imposes the ledger on every guild member through the
-- synchronized operational policy (persistent, replayed to late joiners).
function MultiLedger.SetGuildActiveLedger(ledgerId, actor)
  local db = ensureLedgers()
  if not db then return false, "DB_UNAVAILABLE" end
  if type(ledgerId) ~= "string" or ledgerId == "" then return false, "INVALID_LEDGER_ID" end
  local resolvedId, ledger = resolveLedger(db, ledgerId)
  if not ledger then return false, "LEDGER_NOT_FOUND" end
  if not isLocallyApproved(resolvedId, ledger) then return false, "LEDGER_UNAPPROVED" end
  if imposedLedgerId() == resolvedId then
    local allowed, authReason = MultiLedger.CanSetGuildActiveLedger(actor)
    if not allowed then return false, authReason end
    local enforced, enforceReason = MultiLedger.EnforceGuildActiveLedger()
    if not enforced then return false, enforceReason end
    local sent, syncReason = false, "SYNC_UNAVAILABLE"
    if Dibs.Sync and Dibs.Sync.AnnounceOperationalPolicy then sent, syncReason = Dibs.Sync.AnnounceOperationalPolicy() end
    return true, "UNCHANGED", sent, syncReason
  end
  if not (Dibs.OperationalPolicy and Dibs.OperationalPolicy.SetActiveLedger) then return false, "POLICY_UNAVAILABLE" end
  local ok, reason, _, sent, syncReason = Dibs.OperationalPolicy.SetActiveLedger(resolvedId, actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()))
  if not ok then return false, reason or "POLICY_WRITER_REQUIRED" end
  local enforced, enforceReason = MultiLedger.EnforceGuildActiveLedger()
  if not enforced then return false, enforceReason end
  return true, resolvedId, sent, syncReason
end

-- Read-only consultation of another approved ledger; never changes the ledger
-- used for Pre-Dibs, awards, or debits. Session-local by design.
function MultiLedger.GetViewLedgerId()
  local db = ensureLedgers()
  local view = MultiLedger.viewLedgerId
  if view and db and isLocallyApproved(view, db.ledgers[view]) then return view end
  MultiLedger.viewLedgerId = nil
  return db and db.activeLedgerId or DEFAULT_LEDGER_ID
end

function MultiLedger.SetViewLedger(ledgerId)
  local db = ensureLedgers()
  if not db then return false, "DB_UNAVAILABLE" end
  if type(ledgerId) ~= "string" or ledgerId == "" then return false, "INVALID_LEDGER_ID" end
  local resolvedId, ledger = resolveLedger(db, ledgerId)
  if not isLocallyApproved(resolvedId, ledger) then return false, "LEDGER_UNAPPROVED" end
  MultiLedger.viewLedgerId = resolvedId ~= MultiLedger.GetActiveLedgerId() and resolvedId or nil
  return true, resolvedId
end

function MultiLedger.IsViewingOtherLedger()
  return MultiLedger.GetViewLedgerId() ~= MultiLedger.GetActiveLedgerId()
end

function MultiLedger.GetLedgers()
  local db = ensureLedgers()
  if not db then return {} end

  local list = {}
  for id, ledger in pairs(db.ledgers) do
    local txCount = 0
    if type(ledger.transactions) == "table" then
      for _ in pairs(ledger.transactions) do
        txCount = txCount + 1
      end
    end

    table.insert(list, {
      id = id,
      name = ledger.name or id,
      status = ledger.status or "APPROVED",
      createdAt = ledger.createdAt or 0,
      createdBy = ledger.createdBy or "SYSTEM",
      approvedAt = ledger.approvedAt or 0,
      approvedBy = ledger.approvedBy or (ledger.isDefault and "SYSTEM" or nil),
      isDefault = ledger.isDefault == true,
      transactionCount = txCount,
    })
  end

  table.sort(list, function(a, b)
    if a.isDefault then return true end
    if b.isDefault then return false end
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)

  return list
end

function MultiLedger.GetLedgerById(ledgerId)
  local db = ensureLedgers()
  if not db or not ledgerId or not db.ledgers[ledgerId] then return nil end
  return copy(db.ledgers[ledgerId])
end

function MultiLedger.SetActiveLedger(arg1, arg2)
  local ledgerId = (arg2 ~= nil and arg2) or arg1
  local db = ensureLedgers()
  if not db then return false, "DB_UNAVAILABLE" end
  if type(ledgerId) ~= "string" or ledgerId == "" then return false, "INVALID_LEDGER_ID" end

  local ledger
  ledgerId, ledger = resolveLedger(db, ledgerId)
  if not ledger then return false, "LEDGER_NOT_FOUND" end
  if ledger.status ~= "APPROVED" then return false, "LEDGER_UNAPPROVED" end
  local imposed = imposedLedgerId()
  if imposed and imposed ~= ledgerId and not enforcingGuildLedger then
    return false, "GUILD_ACTIVE_LEDGER_IMPOSED"
  end
  return activateLedger(db, ledgerId, ledger)
end

function MultiLedger.ProposeLedger(actor, name, options)
  local db = ensureLedgers()
  if not db then return { ok = false, reasonCode = "DB_UNAVAILABLE" } end

  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate("ledger.propose", actor)
  if not decision or not decision.allowed then
    return { ok = false, reasonCode = decision and decision.reasonCode or "GUILD_ADMIN_REQUIRED" }
  end

  local cleanName = trim(name)
  if not cleanName or #cleanName > 50 then
    return { ok = false, reasonCode = "INVALID_LEDGER_NAME" }
  end

  local now = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  local randSuffix = string.format("%04x", math.random(0, 0xffff))
  local ledgerId = "LDR-" .. tostring(now) .. "-" .. randSuffix

  local actorName = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()) or "Unknown"

  db.ledgers[ledgerId] = {
    id = ledgerId,
    name = cleanName,
    status = "PROPOSED",
    createdAt = now,
    createdBy = actorName,
    isDefault = false,
    options = options or {},
    transactions = {},
    playerStates = {},
    awardTransactions = {},
    evidenceTransactions = {},
    canonical = { schema = 1, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
  }

  return { ok = true, ledgerId = ledgerId }
end

function MultiLedger.ApproveLedger(actor, ledgerId)
  local db = ensureLedgers()
  if not db then return { ok = false, reasonCode = "DB_UNAVAILABLE" } end

  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate("ledger.approve", actor)
  if not decision or not decision.allowed then
    return { ok = false, reasonCode = decision and decision.reasonCode or "GUILD_MASTER_REQUIRED" }
  end

  if type(ledgerId) ~= "string" or ledgerId == "" or not db.ledgers[ledgerId] then
    return { ok = false, reasonCode = "LEDGER_NOT_FOUND" }
  end

  local ledger = db.ledgers[ledgerId]
  if ledger.status ~= "PROPOSED" and ledger.status ~= "APPROVED" then
    return { ok = false, reasonCode = "LEDGER_NOT_APPROVABLE" }
  end

  if not (Dibs.Governance and Dibs.Governance.RecordLedgerApproval) then
    return { ok = false, reasonCode = "AUDIT_UNAVAILABLE" }
  end
  local recorded, recordReason, approval = Dibs.Governance.RecordLedgerApproval(actor, ledgerId, ledger.name)
  if not recorded then return { ok = false, reasonCode = recordReason or "AUDIT_RECORD_FAILED" } end

  ledger.status = "APPROVED"
  ledger.approvedAt = approval and approval.approvedAt or ledger.approvedAt
  ledger.approvedBy = approval and approval.approvedBy or ledger.approvedBy

  if not (Dibs.SyncV2 and type(Dibs.SyncV2.BroadcastCatalogDigest) == "function") then
    return { ok = false, reasonCode = "SYNC_PENDING", localApproved = true, retryable = true }
  end
  local sent, sendReason = Dibs.SyncV2.BroadcastCatalogDigest()
  if not sent then
    return {
      ok = false,
      reasonCode = "SYNC_PENDING",
      syncReasonCode = sendReason,
      localApproved = true,
      retryable = true,
    }
  end

  return { ok = true, replayed = recordReason == "IDEMPOTENT_REPLAY" }
end

function MultiLedger.ArchiveLedger(actor, ledgerId)
  local db = ensureLedgers()
  if not db then return { ok = false, reasonCode = "DB_UNAVAILABLE" } end

  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate("ledger.archive", actor)
  if not decision or not decision.allowed then
    return { ok = false, reasonCode = decision and decision.reasonCode or "GUILD_MASTER_REQUIRED" }
  end

  if ledgerId == DEFAULT_LEDGER_ID then
    return { ok = false, reasonCode = "CANNOT_ARCHIVE_DEFAULT" }
  end

  if not ledgerId or not db.ledgers[ledgerId] then
    return { ok = false, reasonCode = "LEDGER_NOT_FOUND" }
  end
  if imposedLedgerId() == ledgerId then
    return { ok = false, reasonCode = "GUILD_ACTIVE_LEDGER_CANNOT_ARCHIVE" }
  end

  local ledger = db.ledgers[ledgerId]
  local now = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  local actorName = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()) or "Unknown"

  ledger.status = "ARCHIVED"
  ledger.archivedAt = now
  ledger.archivedBy = actorName

  if db.activeLedgerId == ledgerId then
    activateLedger(db, DEFAULT_LEDGER_ID, db.ledgers[DEFAULT_LEDGER_ID])
  end

  return { ok = true }
end

local function ensureDeletionTombstones(db)
  db.ledgerDeletionTombstones = db.ledgerDeletionTombstones or {}
  return db.ledgerDeletionTombstones
end

function MultiLedger.ApplyLedgerDeletion(actor, ledgerId, deletion)
  local db = ensureLedgers()
  if not db then return { ok = false, reasonCode = "DB_UNAVAILABLE" } end
  if type(ledgerId) ~= "string" or ledgerId == "" then
    return { ok = false, reasonCode = "INVALID_LEDGER_ID" }
  end
  if ledgerId == DEFAULT_LEDGER_ID then
    return { ok = false, reasonCode = "CANNOT_DELETE_DEFAULT" }
  end
  local ledger = db.ledgers[ledgerId]
  local tombstones = ensureDeletionTombstones(db)
  if tombstones[ledgerId] then return { ok = true, reasonCode = "IDEMPOTENT_REPLAY" } end
  local verifiedTombstone = deletion and deletion.verifiedTombstone == true
  if not ledger and not verifiedTombstone then return { ok = false, reasonCode = "LEDGER_NOT_FOUND" } end
  if ledger and ledger.status ~= "ARCHIVED" and not verifiedTombstone then
    return { ok = false, reasonCode = "LEDGER_MUST_BE_ARCHIVED" }
  end

  if db.activeLedgerId == ledgerId then
    local switched, switchReason = activateLedger(db, DEFAULT_LEDGER_ID, db.ledgers[DEFAULT_LEDGER_ID])
    if not switched then return { ok = false, reasonCode = switchReason or "ACTIVE_LEDGER_SWITCH_FAILED" } end
  end
  local timestamp = (deletion and deletion.timestamp) or (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  tombstones[ledgerId] = {
    ledgerId = ledgerId,
    name = ledger and ledger.name or (deletion and deletion.name) or ledgerId,
    deletedAt = timestamp,
    deletedBy = (deletion and deletion.deletedBy) or actor or "REMOTE",
  }
  db.ledgers[ledgerId] = nil
  db.ledger = db.ledgers[db.activeLedgerId]
  return { ok = true }
end

function MultiLedger.DeleteLedger(actor, ledgerId, options)
  local db = ensureLedgers()
  if not db then return { ok = false, reasonCode = "DB_UNAVAILABLE" } end
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate("ledger.delete", actor)
  if not decision or not decision.allowed then
    return { ok = false, reasonCode = decision and decision.reasonCode or "GUILD_MASTER_REQUIRED" }
  end
  if not options or options.confirmed ~= true then return { ok = false, reasonCode = "CONFIRMATION_REQUIRED" } end
  if ledgerId == DEFAULT_LEDGER_ID then return { ok = false, reasonCode = "CANNOT_DELETE_DEFAULT" } end
  if type(ledgerId) ~= "string" or ledgerId == "" then return { ok = false, reasonCode = "INVALID_LEDGER_ID" } end
  if not (Dibs.SyncV2 and type(Dibs.SyncV2.Send) == "function") then
    return { ok = false, reasonCode = "SYNC_UNAVAILABLE" }
  end

  local tombstones = ensureDeletionTombstones(db)
  local existingTombstone = tombstones[ledgerId]
  local ledger = db.ledgers[ledgerId]
  if not existingTombstone then
    if not ledger then return { ok = false, reasonCode = "LEDGER_NOT_FOUND" } end
    if ledger.status ~= "ARCHIVED" then return { ok = false, reasonCode = "LEDGER_MUST_BE_ARCHIVED" } end
    if db.activeLedgerId == ledgerId then return { ok = false, reasonCode = "ACTIVE_LEDGER_CANNOT_DELETE" } end
  end

  if not (Dibs.Governance and type(Dibs.Governance.RecordLedgerDeletion) == "function") then
    return { ok = false, reasonCode = "AUDIT_UNAVAILABLE" }
  end
  local ledgerName = (existingTombstone and existingTombstone.name) or (ledger and ledger.name) or ledgerId
  local timestamp, actorName
  local replayed = existingTombstone ~= nil
  if not existingTombstone then
    if type(Dibs.Governance.PrepareLedgerDeletion) ~= "function" then
      return { ok = false, reasonCode = "AUDIT_UNAVAILABLE" }
    end
    local prepared, prepareReason, request = Dibs.Governance.PrepareLedgerDeletion(actor, ledgerId, ledgerName)
    if not prepared then return { ok = false, reasonCode = prepareReason or "AUDIT_RECORD_FAILED" } end
    replayed = prepareReason == "IDEMPOTENT_REPLAY"
    timestamp = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
    actorName = (Dibs.GetPlayerName and Dibs.GetPlayerName()) or (request and request.actor) or "Unknown"
  else
    local recorded, recordReason = Dibs.Governance.RecordLedgerDeletion(actor, ledgerId, ledgerName)
    if not recorded then return { ok = false, reasonCode = recordReason or "AUDIT_RECORD_FAILED" } end
    timestamp = existingTombstone.deletedAt
    actorName = existingTombstone.deletedBy
  end

  local sent, sendReason = Dibs.SyncV2.Send({
    type = "LEDGER_DELETE",
    ledgerId = ledgerId,
    deletedBy = actorName,
    timestamp = timestamp,
    name = ledgerName,
  }, "GUILD")
  if not sent then
    return {
      ok = false,
      reasonCode = "SYNC_PENDING",
      syncReasonCode = sendReason,
      localDeleted = existingTombstone ~= nil,
      retryable = true,
    }
  end

  if not existingTombstone then
    local recorded, recordReason, auditRecord = Dibs.Governance.RecordLedgerDeletion(actor, ledgerId, ledgerName)
    if not recorded then return { ok = false, reasonCode = recordReason or "AUDIT_RECORD_FAILED" } end
    actorName = auditRecord and auditRecord.actor or actorName
    local applied = MultiLedger.ApplyLedgerDeletion(actor, ledgerId, {
      timestamp = timestamp,
      deletedBy = actorName,
    })
    if not applied or not applied.ok then
      return { ok = false, reasonCode = applied and applied.reasonCode or "LEDGER_DELETE_FAILED" }
    end
    existingTombstone = tombstones[ledgerId]
  end
  existingTombstone.lastBroadcastAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  return { ok = true, replayed = replayed }
end

local function getSenderRaidAuthority(sender)
  if not sender or sender == "" then return false end
  local cleanSender = tostring(sender):match("^([^-]+)") or sender
  if Dibs.Permissions and type(Dibs.Permissions.GetGuildRole) == "function" then
    local role = Dibs.Permissions.GetGuildRole(sender) or Dibs.Permissions.GetGuildRole(cleanSender)
    if role == "gm" or role == "officer" then
      return true
    end
  end
  return false
end

-- Kept for slash commands and older peers. Only GM/Officers may choose the
-- active ledger; raid lead, assist, and Master Looter no longer qualify.
function MultiLedger.CanBroadcastRaidLedger(actor)
  local inGroup = false
  if type(IsInRaid) == "function" and IsInRaid() then
    inGroup = true
  elseif type(IsInGroup) == "function" and IsInGroup() then
    inGroup = true
  end

  if not inGroup and (type(IsInGroup) == "function" or type(IsInRaid) == "function") then
    return false, "NOT_IN_GROUP"
  end

  local actorName = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()) or "player"
  if Dibs.Permissions and Dibs.Permissions.GetGuildRole then
    local role = Dibs.Permissions.GetGuildRole(actorName)
    if role == "gm" or role == "officer" then
      return true
    end
  end

  return false, "GUILD_OFFICER_REQUIRED"
end

function MultiLedger.BroadcastRaidLedger(actor, targetLedgerId)
  local canBroadcast, reason = MultiLedger.CanBroadcastRaidLedger(actor)
  if not canBroadcast then
    return false, reason or "GUILD_OFFICER_REQUIRED"
  end

  local db = ensureLedgers()
  if not db then return false, "DB_UNAVAILABLE" end

  local target = targetLedgerId or db.activeLedgerId
  local _, ledger = resolveLedger(db, tostring(target))

  if not ledger then return false, "LEDGER_NOT_FOUND" end
  if ledger.status ~= "APPROVED" then return false, "LEDGER_UNAPPROVED" end

  local imposed, imposeReason = MultiLedger.SetGuildActiveLedger(ledger.id, actor)
  if not imposed then return false, imposeReason end

  local inRaid = type(IsInRaid) == "function" and IsInRaid()
  local channel = inRaid and "RAID" or "PARTY"
  local sender = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()) or "Leader"
  local now = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or (time and time()) or 0

  local message = {
    action = "SET_ACTIVE_LEDGER",
    ledgerId = ledger.id,
    ledgerName = ledger.name,
    sender = sender,
    timestamp = now,
  }

  local sent = false
  if Dibs.Ace3 and Dibs.Ace3.SendComm then
    sent = Dibs.Ace3.SendComm("DIBS_RAID", message, channel)
  end
  if not sent and type(C_ChatInfo) == "table" and type(C_ChatInfo.SendAddonMessage) == "function" then
    local payload = "DIBS_RAID:SET_ACTIVE_LEDGER:" .. tostring(ledger.id) .. ":" .. tostring(ledger.name)
    sent = pcall(C_ChatInfo.SendAddonMessage, "DIBS_RAID", payload, channel) == true
  end

  if Dibs.Message then
    local text = string.format("Raid active ledger synchronized to %s: %s", channel, tostring(ledger.name))
    Dibs.Message(text)
  end

  return true, ledger.id
end

function MultiLedger.OnRaidCommReceived(prefix, payload, channel, sender)
  if prefix ~= "DIBS_RAID" then return false end
  local message = payload
  if type(payload) == "string" then
    if Dibs.Ace3 and Dibs.Ace3.Deserialize then
      local deserialized = Dibs.Ace3.Deserialize(payload)
      if type(deserialized) == "table" then
        message = deserialized
      end
    end
    if type(message) == "string" and message:match("^DIBS_RAID:") then
      local _, action, ledgerId, ledgerName = strsplit(":", message)
      message = { action = action, ledgerId = ledgerId, ledgerName = ledgerName, sender = sender }
    end
  end

  if type(message) ~= "table" or not message.action then return false, "INVALID_PAYLOAD" end

  local senderName = sender or message.sender
  local localName = Dibs.GetPlayerName and Dibs.GetPlayerName()
  if localName and senderName and string.lower(tostring(localName)) == string.lower(tostring(senderName)) then
    return true, "IGNORE_LOCAL_ECHO"
  end

  if not getSenderRaidAuthority(senderName) then
    return false, "UNAUTHORIZED_SENDER"
  end

  if message.action == "SET_ACTIVE_LEDGER" then
    if imposedLedgerId() then return false, "GUILD_ACTIVE_LEDGER_IMPOSED" end
    local ledgerId = message.ledgerId
    local db = ensureLedgers()
    if not db or not db.ledgers then return false, "DB_UNAVAILABLE" end

    local targetLedger = db.ledgers[ledgerId]
    if not targetLedger then
      for _, candidate in pairs(db.ledgers) do
        if candidate.name and string.lower(candidate.name) == string.lower(tostring(message.ledgerName or ledgerId)) then
          targetLedger = candidate
          ledgerId = candidate.id
          break
        end
      end
    end

    if not targetLedger or targetLedger.status ~= "APPROVED" then
      return false, "LEDGER_UNAPPROVED_OR_NOT_FOUND"
    end

    local currentActive = MultiLedger.GetActiveLedgerId()
    if currentActive ~= ledgerId then
      MultiLedger.SetActiveLedger(nil, ledgerId)
      refreshOpenWindows()
      if Dibs.Message then
        local senderDisplay = message.sender or sender or "Raid Leader"
        local ledgerDisplay = message.ledgerName or targetLedger.name or ledgerId
        local template = (Dibs.L and Dibs.L.RAID_LEDGER_SYNCED) or "Raid active ledger synchronized: %s (by %s)."
        Dibs.Message(string.format(template, tostring(ledgerDisplay), tostring(senderDisplay)))
      end
    end
    return true, "LEDGER_SYNCHRONIZED"
  end

  return false, "UNKNOWN_ACTION"
end

function MultiLedger.RegisterTransport()
  if MultiLedger.transportRegistered then return true end
  if Dibs.Ace3 and Dibs.Ace3.RegisterComm then
    local ok = Dibs.Ace3.RegisterComm("DIBS_RAID", function(prefix, payload, channel, sender)
      return MultiLedger.OnRaidCommReceived(prefix, payload, channel, sender)
    end)
    MultiLedger.transportRegistered = ok == true
    return MultiLedger.transportRegistered
  end
  return false
end

return MultiLedger
