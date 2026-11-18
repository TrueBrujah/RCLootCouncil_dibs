--[[
Module: Dibs.Ledger
Layer: Domain / append-only store
Purpose: Provide the single local command boundary for durable ledger mutation.
Responsibilities: Validate, canonicalize, append, and project local ledger transactions.
Non-responsibilities: Network replication, coordinator activation, epochs, and RCLootCouncil authority.
Dependencies: Identity, Permissions, Seasons.
SavedVariables: db.ledger.transactions, playerStates, awardTransactions, evidenceTransactions.

B03 boundary: every newly created transaction is LOCAL_CANONICAL and is
constructed detached, validated, hashed, replay-checked, then appended. Old
records stay LEGACY by absence of a classification; they are never rewritten.
]]

local Dibs = _G.Dibs
Dibs.Ledger = Dibs.Ledger or {}
local Ledger = Dibs.Ledger

local SCHEMA = 3
local CLASSIFICATION = "LOCAL_CANONICAL"
local CANONICAL_SCHEMA = 1
local VALID_ACTION_TYPES = {
  SEASON_ALLOCATION = true, DIB_GRANTED = true, DIB_USED = true,
  DIB_REFUNDED = true, DIB_REVOKED = true, DIB_ADMIN_ADJUSTMENT = true,
}

local ACTION_BY_PROTECTED_ACTION = {
  ["ledger.grant"] = "DIB_GRANTED", ["ledger.use"] = "DIB_USED",
  ["ledger.refund"] = "DIB_REFUNDED", ["ledger.adjust"] = "DIB_ADMIN_ADJUSTMENT",
}
local PROTECTED_ACTION_BY_TYPE = {
  DIB_GRANTED = "ledger.grant", DIB_USED = "ledger.use", DIB_REFUNDED = "ledger.refund",
  DIB_REVOKED = "ledger.adjust", DIB_ADMIN_ADJUSTMENT = "ledger.adjust", SEASON_ALLOCATION = "ledger.adjust",
}

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local MAX_PLAYER_DIBS_PROJECTIONS = 256
local playerDibsProjections, playerDibsProjectionOrder = {}, {}
local playerStateProjectionRevisions = setmetatable({}, { __mode = "k" })
local MAX_PLAYER_HISTORY_INDEXES = 128
local playerHistoryIndexes, playerHistoryIndexOrder = {}, {}
local MAX_PLAYER_HISTORY_SUMMARIES = 128
local playerHistorySummaries, playerHistorySummaryOrder = {}, {}
local ledgerDataRevisions, ledgerTransactionDiagnostics = {}, {}
local ledgerNonAllocationCounts = {}
local ledgerHasNonAllocationTransactions = {}
local recentHistoryChoicesCache

local function beginLedgerUITiming()
  return Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
end

local function beginLedgerCPUUITiming()
  return Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin(false)
end

local function recordLedgerUITiming(name, startedAt)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Ledger data", name, startedAt)
  end
end

local function copyPlayerDibsProjection(projection)
  local result = {}
  for key, value in pairs(projection) do result[key] = value end
  return result
end

local function rememberPlayerDibsProjection(key, entry)
  if playerDibsProjections[key] == nil then
    if #playerDibsProjectionOrder >= MAX_PLAYER_DIBS_PROJECTIONS then
      local oldest = table.remove(playerDibsProjectionOrder, 1)
      playerDibsProjections[oldest] = nil
    end
    playerDibsProjectionOrder[#playerDibsProjectionOrder + 1] = key
  end
  playerDibsProjections[key] = entry
end

function Ledger.GetActiveLedgerId(dbOverride)
  if Dibs.MultiLedger and type(Dibs.MultiLedger.GetActiveLedgerId) == "function" then
    return Dibs.MultiLedger.GetActiveLedgerId(dbOverride)
  end
  local db = type(dbOverride) == "table" and dbOverride or Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  return db.activeLedgerId or "guild-primary"
end

local function ensureState(targetLedgerId, timingPrefix, dbOverride)
  local dbReadStartedAt = timingPrefix and beginLedgerUITiming()
  Dibs.db = type(dbOverride) == "table" and dbOverride or Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  local db = Dibs.db
  if timingPrefix then recordLedgerUITiming(timingPrefix .. "-db-read", dbReadStartedAt) end
  db.ledgers = db.ledgers or {}
  if db.ledger and not db.ledgers["guild-primary"] then
    db.ledgers["guild-primary"] = {
      id = "guild-primary",
      name = "Primary",
      status = "APPROVED",
      createdAt = (db.ledger.createdAt or (time and time()) or 0),
      transactions = db.ledger.transactions or {},
      playerStates = db.ledger.playerStates or {},
      awardTransactions = db.ledger.awardTransactions or {},
      evidenceTransactions = db.ledger.evidenceTransactions or {},
      canonical = db.ledger.canonical or { schema = CANONICAL_SCHEMA, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
    }
    db.activeLedgerId = db.activeLedgerId or "guild-primary"
  end

  local idStartedAt = timingPrefix and beginLedgerUITiming()
  local id = targetLedgerId or Ledger.GetActiveLedgerId(dbOverride) or "guild-primary"
  if timingPrefix then recordLedgerUITiming(timingPrefix .. "-ledger-id", idStartedAt) end
  local ledgerStartedAt = timingPrefix and beginLedgerUITiming()
  db.ledgers[id] = db.ledgers[id] or {
    id = id,
    name = (id == "guild-primary" and "Primary" or id),
    status = "APPROVED",
    createdAt = (time and time()) or 0,
    transactions = {},
    playerStates = {},
    awardTransactions = {},
    evidenceTransactions = {},
    canonical = { schema = CANONICAL_SCHEMA, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} },
  }

  local ledger = db.ledgers[id]
  ledger.transactions = ledger.transactions or {}; ledger.playerStates = ledger.playerStates or {}
  ledger.awardTransactions = ledger.awardTransactions or {}; ledger.evidenceTransactions = ledger.evidenceTransactions or {}
  ledger.canonical = ledger.canonical or { schema = CANONICAL_SCHEMA, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} }
  ledger.canonical.commits = ledger.canonical.commits or {}; ledger.canonical.transactionIndex = ledger.canonical.transactionIndex or {}; ledger.canonical.positions = ledger.canonical.positions or {}
  if ledger.canonical.schema ~= CANONICAL_SCHEMA then ledger.canonical = { schema = CANONICAL_SCHEMA, epoch = nil, nextSeq = 1, rootHash = nil, commits = {}, transactionIndex = {}, positions = {} } end

  if id == (db.activeLedgerId or "guild-primary") then
    db.ledger = ledger
  end

  if timingPrefix then recordLedgerUITiming(timingPrefix .. "-ledger-normalize", ledgerStartedAt) end

  return ledger
end

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function finiteNumber(value)
  local number = tonumber(value)
  return number ~= nil and number == number and math.abs(number) < math.huge
end

local function finiteInteger(value) return finiteNumber(value) and tonumber(value) == math.floor(tonumber(value)) end
local function normalizeLegacyPlayerKey(playerName) return string.lower(trim(tostring(playerName or "")) or "") end

-- The activation snapshot fixes one accounting owner for each seasonal
-- person. Main changes select a character; they never move old transactions.
local function seasonalAccountingKey(memberKey, seasonId)
  local db = Dibs.GetDB()
  local season = db.seasonalRoster and db.seasonalRoster.seasons[seasonId]
  if season and season.activationAdopted then
    for _, snapshot in pairs(season.activationIdentities or {}) do
      for _, key in ipairs(snapshot.memberKeys or {}) do
        if key == memberKey then return snapshot.mainCharacterKey end
      end
    end
  end
  return memberKey
end

local function ensurePlayerState(playerKey, seasonId, targetLedgerId)
  playerKey = seasonalAccountingKey(playerKey, seasonId)
  local ledger = ensureState(targetLedgerId)
  ledger.playerStates[seasonId] = ledger.playerStates[seasonId] or {}
  ledger.playerStates[seasonId][playerKey] = ledger.playerStates[seasonId][playerKey] or { allocation = 0, balance = 0, transactions = {} }
  return ledger.playerStates[seasonId][playerKey]
end

local function actionAmountIsValid(actionType, amount, reconciliation)
  if actionType == "SEASON_ALLOCATION" and type(reconciliation) == "table"
    and reconciliation.kind == "SEASONAL_ALLOCATION_DRIFT" and reconciliation.schema == 1
    and finiteInteger(reconciliation.assignedBefore) and finiteInteger(reconciliation.expectedAllocation)
    and reconciliation.expectedAllocation >= 0 and reconciliation.expectedAllocation <= 100000
    and amount == reconciliation.expectedAllocation - reconciliation.assignedBefore then return amount ~= 0 end
  if actionType == "DIB_GRANTED" or actionType == "DIB_REFUNDED" or actionType == "SEASON_ALLOCATION" then return amount > 0 end
  if actionType == "DIB_USED" or actionType == "DIB_REVOKED" then return amount < 0 end
  return actionType == "DIB_ADMIN_ADJUSTMENT" and amount ~= 0
end

-- Type-tagged and key-sorted serialization is independent from B00's test-only
-- contract hash. It is deterministic content identity, not client authentication.
local function canonicalSerialize(value, seen)
  local kind = type(value)
  if kind == "nil" then return "z" end
  if kind == "boolean" then return value and "b1" or "b0" end
  if kind == "number" then
    if not finiteNumber(value) then return nil, "NON_FINITE_CANONICAL_VALUE" end
    if value == 0 then value = 0 end
    return "n" .. string.format("%.17g", value)
  end
  if kind == "string" then return "s" .. tostring(#value) .. ":" .. value end
  if kind ~= "table" then return nil, "UNSUPPORTED_CANONICAL_VALUE" end
  seen = seen or {}
  if seen[value] then return nil, "CYCLIC_CANONICAL_VALUE" end
  seen[value] = true
  local entries = {}
  for key, item in pairs(value) do
    local encodedKey, keyReason = canonicalSerialize(key, seen)
    local encodedValue, valueReason = canonicalSerialize(item, seen)
    if not encodedKey or not encodedValue then seen[value] = nil; return nil, keyReason or valueReason end
    table.insert(entries, encodedKey .. "=" .. encodedValue)
  end
  seen[value] = nil; table.sort(entries)
  return "t{" .. table.concat(entries, ",") .. "}"
end

-- Stable 31-bit polynomial hash. Each intermediate is representable exactly by
-- Lua's number type. This non-cryptographic hash detects differing content only.
---@param serialized string Canonical serialized content.
local function contentHash(serialized)
  local hash = 0
  for index = 1, #serialized do hash = (hash * 131 + serialized:byte(index)) % 2147483647 end
  return string.format("D3-%08x", hash)
end

local function canonicalSnapshot(snapshot)
  return { memberKey = snapshot.memberKey, displayName = snapshot.displayName, guidWitness = snapshot.guidWitness }
end

local function canonicalContent(tx)
  return {
    schema = SCHEMA, recordClass = "LEDGER_TRANSACTION", classification = CLASSIFICATION,
    transactionId = tx.transactionId, actionType = tx.actionType, memberKey = tx.memberKey,
    identitySnapshot = canonicalSnapshot(tx.identitySnapshot), seasonId = tx.seasonId,
    accountingMemberKey = tx.accountingMemberKey,
    amount = tx.amount, reason = tx.reason, source = tx.source,
    reconciliation = tx.reconciliation,
    evidence = { evidenceId = tx.evidenceId, awardRef = tx.awardRef, itemID = tx.itemID, itemLink = tx.itemLink, sourceStatus = tx.sourceStatus, response = tx.response, reviewRequestId = tx.reviewRequestId, originalTransactionId = tx.originalTransactionId, correctionKey = tx.correctionKey, confirmation = tx.confirmation },
    actor = { actorId = tx.actorId, identitySnapshot = canonicalSnapshot(tx.actorSnapshot), authority = tx.context and tx.context.authority, action = tx.context and tx.context.action },
    debtPolicy = tx.debtPolicy,
  }
end

local function transactionCanonicalHash(tx)
  local serialized, reason = canonicalSerialize(canonicalContent(tx))
  if not serialized then return nil, reason end
  return contentHash(serialized), serialized
end

local function canonicalCommitHash(commit)
  local projection = { schema = commit.schema, recordClass = commit.recordClass, guildKey = commit.guildKey,
    protocolMajor = commit.protocolMajor, ledgerEpoch = commit.ledgerEpoch, sequence = commit.sequence,
    previousHash = commit.previousHash, canonicalTransactionId = commit.canonicalTransactionId,
    transactionHash = commit.transactionHash, coordinator = commit.coordinator, proposalId = commit.proposalId,
    transaction = canonicalContent(commit.transaction) }
  if commit.ledgerId ~= nil then projection.ledgerId = commit.ledgerId end
  local serialized, reason = canonicalSerialize(projection)
  if not serialized then return nil, reason end
  return contentHash(serialized)
end

local function authority()
  return Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState() or nil
end
local function v2Enforced()
  return Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced() == true
end
local function isApprovedLedger(ledgerId)
  if type(ledgerId) ~= "string" or ledgerId == "" then return false end
  if ledgerId == "guild-primary" then return true end
  local db = Dibs.GetDB and Dibs.GetDB()
  local ledger = db and db.ledgers and db.ledgers[ledgerId]
  return ledger ~= nil and ledger.status == "APPROVED"
    and Dibs.Governance and Dibs.Governance.IsLedgerApproved
    and Dibs.Governance.IsLedgerApproved(ledgerId) == true
end
local function localCoordinator(authorityState, actor)
  if not authorityState or authorityState.state ~= "ACTIVE" or type(authorityState.coordinator) ~= "table" then return nil, "COORDINATOR_UNAVAILABLE" end
  if Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() then return nil, "SYNC_BEHIND" end
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then return nil, "IDENTITY_UNAVAILABLE" end
  local localSnapshot, localReason = Dibs.Identity.CreateSnapshot(Dibs.GetPlayerName())
  if not localSnapshot then return nil, localReason end
  if actor ~= nil then
    local requested, requestedReason = Dibs.Identity.CreateSnapshot(actor)
    if not requested then return nil, requestedReason end
    if requested.memberKey ~= localSnapshot.memberKey then return nil, "LOCAL_COORDINATOR_REQUIRED" end
  end
  if localSnapshot.memberKey ~= authorityState.coordinator.memberKey then return nil, "CURRENT_COORDINATOR_REQUIRED" end
  return localSnapshot
end
local function authorityRoot(authorityState)
  local transition = authorityState and authorityState.transition or {}
  if transition.kind == "NORMAL_HANDOFF" and transition.parentClosure then return transition.parentClosure.rootHash end
  return transition.baselineHash
end
local function canonicalStateForAuthority(ledger, authorityState)
  local canonical = ledger.canonical
  if canonical.epoch == nil then
    local root = authorityRoot(authorityState)
    if type(root) ~= "string" or root == "" then return nil, "CANONICAL_BASELINE_REQUIRED" end
    canonical.epoch, canonical.nextSeq, canonical.rootHash = authorityState.ledgerEpoch, 1, root
    return canonical
  end
  if canonical.epoch == authorityState.ledgerEpoch then return canonical end
  if canonical.epoch > authorityState.ledgerEpoch then return nil, "STALE_EPOCH" end
  local root = authorityRoot(authorityState)
  if type(root) ~= "string" or root == "" then return nil, "CANONICAL_BASELINE_REQUIRED" end
  if authorityState.transition and authorityState.transition.kind == "NORMAL_HANDOFF" and canonical.rootHash ~= root then return nil, "HANDOFF_ROOT_MISMATCH" end
  canonical.epoch, canonical.nextSeq, canonical.rootHash = authorityState.ledgerEpoch, 1, root
  return canonical
end
local function positionKey(epoch, sequence) return tostring(epoch) .. ":" .. tostring(sequence) end

local function sameCanonicalContent(existing, candidate)
  return existing.classification == CLASSIFICATION and type(existing.canonicalContentHash) == "string"
    and existing.canonicalContentHash == candidate.canonicalContentHash
end

local function getCurrentBalance(memberKey, seasonId, targetLedgerId)
  memberKey = seasonalAccountingKey(memberKey, seasonId)
  local ledger = ensureState(targetLedgerId); local state = ledger.playerStates[seasonId] and ledger.playerStates[seasonId][memberKey]
  if not state then return 0 end
  local balance = tonumber(state.allocation) or 0
  for _, transactionId in ipairs(state.transactions or {}) do
    local tx = ledger.transactions[transactionId]
    if tx and tx.type ~= "SEASON_ALLOCATION" then balance = balance + (tonumber(tx.amount) or 0) end
  end
  return balance
end

local function validateSeason(seasonId)
  if type(seasonId) ~= "string" or seasonId == "" then return false, "MISSING_SEASON_ID" end
  if not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(seasonId) then return false, "SEASON_NOT_FOUND" end
  return true
end

local function createMemberSnapshot(value)
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then return nil, "IDENTITY_UNAVAILABLE" end
  local snapshot, reason = Dibs.Identity.CreateSnapshot(value)
  if not snapshot then return nil, reason or "INVALID_IDENTITY" end
  if type(snapshot.memberKey) ~= "string" or type(snapshot.displayName) ~= "string" then return nil, "INVALID_IDENTITY_SNAPSHOT" end
  return snapshot
end

function Ledger.GetRankReconciliationSnapshot(playerName, seasonId)
  local v2StartedAt = beginLedgerCPUUITiming()
  if not v2Enforced() then
    recordLedgerUITiming("reconciliation-snapshot-v2-check", v2StartedAt)
    return nil, "V2_ENFORCED_REQUIRED"
  end
  recordLedgerUITiming("reconciliation-snapshot-v2-check", v2StartedAt)
  local syncStartedAt = beginLedgerCPUUITiming()
  if Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() then
    recordLedgerUITiming("reconciliation-snapshot-sync-behind-check", syncStartedAt)
    return nil, "SYNC_BEHIND"
  end
  recordLedgerUITiming("reconciliation-snapshot-sync-behind-check", syncStartedAt)
  local seasonStartedAt = beginLedgerCPUUITiming()
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId())
  local currentSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or targetSeason
  if targetSeason ~= currentSeasonId then
    recordLedgerUITiming("reconciliation-snapshot-season", seasonStartedAt)
    return nil, "STALE_SEASON"
  end
  recordLedgerUITiming("reconciliation-snapshot-season", seasonStartedAt)
  local authorityStartedAt = beginLedgerCPUUITiming()
  local authorityState = authority()
  if not authorityState or authorityState.state ~= "ACTIVE" or not authorityState.coordinator
    or not finiteInteger(authorityState.ledgerEpoch) then
    recordLedgerUITiming("reconciliation-snapshot-authority", authorityStartedAt)
    return nil, "COORDINATOR_UNAVAILABLE"
  end
  recordLedgerUITiming("reconciliation-snapshot-authority", authorityStartedAt)
  local identityStartedAt = beginLedgerCPUUITiming()
  local resolved = Dibs.Identity and Dibs.Identity.ResolveRosterMember and Dibs.Identity.ResolveRosterMember(playerName)
  if not resolved or resolved.status ~= "RESOLVED" then
    recordLedgerUITiming("reconciliation-snapshot-identity", identityStartedAt)
    return nil, resolved and resolved.status or "ROSTER_UNAVAILABLE"
  end
  local targetSnapshot, identityReason = createMemberSnapshot(resolved.displayName)
  if not targetSnapshot then
    recordLedgerUITiming("reconciliation-snapshot-identity", identityStartedAt)
    return nil, identityReason
  end
  if targetSnapshot.memberKey ~= resolved.memberKey then
    recordLedgerUITiming("reconciliation-snapshot-identity", identityStartedAt)
    return nil, "STALE_TARGET"
  end
  recordLedgerUITiming("reconciliation-snapshot-identity", identityStartedAt)
  local rankStartedAt = beginLedgerCPUUITiming()
  local rankInfo = Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo and Dibs.RankRules.GetPlayerRankInfo(resolved.displayName)
  if type(rankInfo) ~= "table" or tonumber(rankInfo.rankIndex) == nil then
    recordLedgerUITiming("reconciliation-snapshot-rank-catalog", rankStartedAt)
    return nil, "RANK_UNAVAILABLE"
  end
  local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  local catalogRevision = tonumber(catalog.catalogRevision)
  if not finiteInteger(catalogRevision) or catalogRevision < 1 or type(catalog.hash) ~= "string" or catalog.hash == "GENESIS" then
    recordLedgerUITiming("reconciliation-snapshot-rank-catalog", rankStartedAt)
    return nil, "SEASON_CATALOG_UNPUBLISHED"
  end
  local expected
  if Dibs.RankRules and Dibs.RankRules.GetAllocationForRank then
    expected = tonumber(Dibs.RankRules.GetAllocationForRank(targetSeason, rankInfo.rankIndex))
  elseif Dibs.RankRules and Dibs.RankRules.GetAllocationForPlayer then
    expected = tonumber(Dibs.RankRules.GetAllocationForPlayer(resolved.displayName, targetSeason))
  end
  if not finiteInteger(expected) or expected < 0 then
    recordLedgerUITiming("reconciliation-snapshot-rank-catalog", rankStartedAt)
    return nil, "RANK_RULE_INVALID"
  end
  recordLedgerUITiming("reconciliation-snapshot-rank-catalog", rankStartedAt)
  local ledgerStartedAt = beginLedgerCPUUITiming()
  local playerState = Ledger.GetPlayerHistorySummary and Ledger.GetPlayerHistorySummary(resolved.displayName, targetSeason)
    or Ledger.GetPlayerState(resolved.displayName, targetSeason) or {}
  local assigned = tonumber(playerState.allocation) or 0
  if not finiteInteger(assigned) or assigned < 0 then
    recordLedgerUITiming("reconciliation-snapshot-player-state", ledgerStartedAt)
    return nil, "ASSIGNED_ALLOCATION_INVALID"
  end
  recordLedgerUITiming("reconciliation-snapshot-player-state", ledgerStartedAt)
  local policyStartedAt = beginLedgerCPUUITiming()
  local governanceState = Dibs.Governance and Dibs.Governance.GetRevisionSummary
    and Dibs.Governance.GetRevisionSummary()
    or (Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState()) or {}
  local policyState = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetDigestSummary
    and Dibs.OperationalPolicy.GetDigestSummary()
    or (Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState()) or {}
  recordLedgerUITiming("reconciliation-snapshot-policy-revisions", policyStartedAt)
  local snapshot = {
    playerName = resolved.displayName, targetSnapshot = targetSnapshot, targetMemberKey = resolved.memberKey,
    seasonId = targetSeason, currentSeasonId = currentSeasonId,
    currentRankIndex = tonumber(rankInfo.rankIndex), currentRankName = rankInfo.rankName or "Guild Member",
    expectedAllocation = expected, assignedBefore = assigned, seasonCatalogRevision = catalogRevision,
    seasonCatalogHash = catalog.hash, governanceRevision = tonumber(governanceState.revision) or 0,
    operationalPolicyRevision = tonumber(policyState.policyRevision) or 0, reconciliationMode = "MANUAL",
    authorityEpoch = tonumber(authorityState.ledgerEpoch), coordinatorMemberKey = authorityState.coordinator.memberKey,
  }
  local operationBasis = {
    targetMemberKey = snapshot.targetMemberKey, seasonId = snapshot.seasonId,
    currentRankIndex = snapshot.currentRankIndex, currentRankName = snapshot.currentRankName,
    expectedAllocation = snapshot.expectedAllocation, assignedBefore = snapshot.assignedBefore,
    seasonCatalogRevision = snapshot.seasonCatalogRevision, seasonCatalogHash = snapshot.seasonCatalogHash,
    governanceRevision = snapshot.governanceRevision, operationalPolicyRevision = snapshot.operationalPolicyRevision,
    authorityEpoch = snapshot.authorityEpoch, coordinatorMemberKey = snapshot.coordinatorMemberKey,
  }
  local hashStartedAt = beginLedgerCPUUITiming()
  local serialized, serializeReason = canonicalSerialize(operationBasis)
  if not serialized then
    recordLedgerUITiming("reconciliation-snapshot-operation-hash", hashStartedAt)
    return nil, serializeReason
  end
  snapshot.operationKey = contentHash(serialized)
  recordLedgerUITiming("reconciliation-snapshot-operation-hash", hashStartedAt)
  return snapshot
end

local function validateRankReconciliation(reconciliation, playerName, amount)
  if type(reconciliation) ~= "table" or reconciliation.schema ~= 1 then return false, "INVALID_RECONCILIATION_CONTEXT" end
  local current, currentReason = Ledger.GetRankReconciliationSnapshot(playerName, reconciliation.seasonId)
  if not current then return false, currentReason end
  if current.targetMemberKey ~= reconciliation.targetMemberKey then return false, "STALE_TARGET" end
  if current.seasonId ~= reconciliation.seasonId or current.currentSeasonId ~= reconciliation.currentSeasonId then return false, "STALE_SEASON" end
  if current.currentRankIndex ~= reconciliation.currentRankIndex or current.currentRankName ~= reconciliation.currentRankName then return false, "STALE_RANK" end
  if current.seasonCatalogRevision ~= reconciliation.seasonCatalogRevision or current.seasonCatalogHash ~= reconciliation.seasonCatalogHash then return false, "STALE_CATALOG" end
  if current.assignedBefore ~= reconciliation.assignedBefore then return false, "STALE_ASSIGNMENT" end
  if current.expectedAllocation ~= reconciliation.expectedAllocation then return false, "STALE_EXPECTATION" end
  if current.governanceRevision ~= reconciliation.governanceRevision
    or current.operationalPolicyRevision ~= reconciliation.operationalPolicyRevision
    or current.reconciliationMode ~= reconciliation.reconciliationMode
    or current.authorityEpoch ~= reconciliation.authorityEpoch
    or current.coordinatorMemberKey ~= reconciliation.coordinatorMemberKey then return false, "AUTHORITY_CHANGED" end
  if current.operationKey ~= reconciliation.operationKey then return false, "STALE_OPERATION" end
  if amount ~= current.expectedAllocation - current.assignedBefore or amount <= 0 then return false, "STALE_DELTA" end
  local requester = reconciliation.requestedBySnapshot
  local resolvedRequester = requester and Dibs.Identity and Dibs.Identity.ResolveRosterMember and Dibs.Identity.ResolveRosterMember(requester.displayName)
  if not requester or not resolvedRequester or resolvedRequester.status ~= "RESOLVED"
    or resolvedRequester.memberKey ~= requester.memberKey then return false, "REQUESTER_UNAVAILABLE" end
  local requesterRole = Dibs.Permissions and Dibs.Permissions.GetGuildRole
    and Dibs.Permissions.GetGuildRole(requester.displayName)
  if requesterRole ~= "gm" and requesterRole ~= "officer" then return false, "REQUESTER_AUTHORITY_CHANGED" end
  return true, current
end

local function authorize(context, actionType)
  context = context or {}
  if context.systemBootstrap == true then
    if actionType ~= "SEASON_ALLOCATION" then return nil, "BOOTSTRAP_ACTION_FORBIDDEN" end
    local actorSnapshot, snapshotReason = createMemberSnapshot(Dibs.GetPlayerName())
    if not actorSnapshot then return nil, snapshotReason end
    return { actorId = actorSnapshot.memberKey, actorSnapshot = actorSnapshot, authority = "local-bootstrap", action = "season.bootstrap", reasonCode = "SYSTEM_BOOTSTRAP" }
  end
  local protectedAction = context.action or ACTION_BY_PROTECTED_ACTION[context.protectedAction]
  if not protectedAction then
    if actionType == "DIB_GRANTED" then protectedAction = "ledger.grant"
    elseif actionType == "DIB_USED" then protectedAction = "ledger.use"
    elseif actionType == "DIB_REFUNDED" then protectedAction = "ledger.refund" else protectedAction = "ledger.adjust" end
  end
  if not Dibs.Permissions or type(Dibs.Permissions.Evaluate) ~= "function" then return nil, "AUTHORITY_UNAVAILABLE" end
  local actor = context.actor or Dibs.GetPlayerName()
  local decision = Dibs.Permissions.Evaluate(protectedAction, actor)
  if not decision or decision.allowed ~= true then return nil, decision and decision.reasonCode or "AUTHORITY_UNAVAILABLE" end
  local actorSnapshot, snapshotReason = createMemberSnapshot(actor)
  if not actorSnapshot then return nil, snapshotReason end
  return { actorId = decision.actorId or actorSnapshot.memberKey, actorSnapshot = actorSnapshot, authority = decision.authority, action = protectedAction, reasonCode = decision.reasonCode }
end

local function explicitDebtPolicy(context)
  local requested = context and context.debtPolicy
  if requested == nil and context and context.allowDebt == true then requested = { allowDebt = true, source = "LOCAL_EXPLICIT" } end
  if requested == nil then return { allowDebt = false, source = "DEFAULT_LOCAL" } end
  if type(requested) ~= "table" or requested.allowDebt ~= true then return nil, "INVALID_DEBT_POLICY" end
  local source = trim(requested.source)
  if not source then return nil, "INVALID_DEBT_POLICY" end
  return { allowDebt = true, source = source }
end

local function buildDetachedTransaction(context, input)
  input = input or {}; local actionType = input.actionType or input.type
  if type(actionType) ~= "string" or not VALID_ACTION_TYPES[actionType] then return nil, "INVALID_ACTION_TYPE" end
  local transactionId = trim(input.transactionId) or Dibs.NewId("tx")
  if #transactionId > 160 then return nil, "INVALID_TRANSACTION_ID" end
  local seasonId = input.seasonId or Dibs.GetCurrentSeasonId(); local seasonOK, seasonReason = validateSeason(seasonId)
  if not seasonOK then return nil, seasonReason end
  local amount = tonumber(input.quantityDelta or input.amount)
  if not finiteInteger(amount) or amount == 0 or math.abs(amount) > 100000 then return nil, "INVALID_AMOUNT" end
  if not actionAmountIsValid(actionType, amount, input.reconciliation) then return nil, "INVALID_QUANTITY_SIGN" end
  local snapshot, identityReason = createMemberSnapshot({ nameRealm = input.playerName or input.memberKey or input.playerKey, guidWitness = input.guidWitness or input.playerGuid })
  if not snapshot then return nil, identityReason end
  local authorization, authorizationReason = authorize(context, actionType)
  if not authorization then return nil, authorizationReason end
  if context and context.systemBootstrap == true and snapshot.memberKey ~= authorization.actorSnapshot.memberKey then
    return nil, "BOOTSTRAP_TARGET_MISMATCH"
  end
  local debtPolicy, debtReason = explicitDebtPolicy(context); if not debtPolicy then return nil, debtReason end
  local reason = trim(input.reason) or "No reason provided"
  local timestamp = tonumber(input.timestamp or input.createdAt) or (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  if not finiteNumber(timestamp) then return nil, "MISSING_TIMESTAMP" end
  local tx = {
    schema = SCHEMA, recordClass = "LEDGER_TRANSACTION", classification = CLASSIFICATION,
    transactionId = transactionId, type = actionType, actionType = actionType, action = actionType,
    memberKey = snapshot.memberKey, playerKey = snapshot.memberKey, playerName = snapshot.displayName,
    identitySnapshot = copy(snapshot), playerGuid = snapshot.guidWitness, guidWitness = snapshot.guidWitness,
    seasonId = seasonId, amount = amount, quantityDelta = amount, reason = reason, source = trim(input.source) or "local",
    evidenceId = trim(input.evidenceId), awardRef = trim(input.awardRef), itemID = input.itemID, itemLink = input.itemLink,
    sourceStatus = input.sourceStatus, response = input.response, reviewRequestId = input.reviewRequestId,
    originalTransactionId = input.originalTransactionId, correctionKey = input.correctionKey,
    confirmation = input.confirmation == true or nil, createdAt = timestamp, timestamp = timestamp,
    actorId = authorization.actorId, actorSnapshot = copy(authorization.actorSnapshot),
    context = { authority = authorization.authority, action = authorization.action, authorization = authorization.reasonCode }, debtPolicy = debtPolicy,
    reconciliation = type(input.reconciliation) == "table" and copy(input.reconciliation) or nil,
  }
  local accountingKey = seasonalAccountingKey(snapshot.memberKey, seasonId)
  if accountingKey ~= snapshot.memberKey then tx.accountingMemberKey = accountingKey end
  local hash, hashReason = transactionCanonicalHash(tx); if not hash then return nil, hashReason end
  tx.canonicalContentHash = hash
  return tx
end

local function appendValidated(tx, targetLedgerId)
  local ledger = ensureState(targetLedgerId); ledger.transactions[tx.transactionId] = tx
  if tx.awardRef then ledger.awardTransactions[tx.awardRef] = tx.transactionId end
  if tx.evidenceId then ledger.evidenceTransactions[tx.evidenceId] = tx.transactionId end
  local state = ensurePlayerState(tx.accountingMemberKey or tx.memberKey, tx.seasonId, targetLedgerId); table.insert(state.transactions, tx.transactionId)
  if tx.type == "SEASON_ALLOCATION" then state.allocation = (tonumber(state.allocation) or 0) + tx.amount end
  state.balance = getCurrentBalance(tx.memberKey, tx.seasonId, targetLedgerId)
  playerStateProjectionRevisions[state] = (playerStateProjectionRevisions[state] or 0) + 1
  ledgerDataRevisions[ledger.id] = (ledgerDataRevisions[ledger.id] or 0) + 1
  ledgerTransactionDiagnostics[ledger.id] = nil
  ledgerNonAllocationCounts[ledger.id] = nil
  return tx
end

---@param context table Local caller context; it never represents a coordinator or epoch.
---@param record table Candidate transaction fields.
---@param targetLedgerId string|nil Optional target ledger identifier.
---@return table result `{accepted, idempotentReplay, value?, reasonCode?}`.
function Ledger.CommitLocalTransaction(context, record, targetLedgerId)
  local ledgerId = targetLedgerId or (context and context.ledgerId) or Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return { accepted = false, idempotentReplay = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  local ledger = ensureState(ledgerId); local input = record or {}; local inputId = trim(input.transactionId)
  local existing = inputId and ledger.transactions[inputId] or nil
  local tx, reason = buildDetachedTransaction(context or {}, input)
  if not tx then return { accepted = false, idempotentReplay = false, reasonCode = reason } end
  if tx.type == "DIB_USED" and v2Enforced() and not (context and context.b06Canonical == true) then
    local proposal = Dibs.Governance and Dibs.Governance.RecordAwardProposal and Dibs.Governance.RecordAwardProposal(
      context and context.actor or Dibs.GetPlayerName(), input)
    return { accepted = false, idempotentReplay = false, reasonCode = "DISTRIBUTED_COMMIT_REQUIRED", proposal = proposal }
  end
  -- B05b fences local consumption while coordinator authority is unavailable,
  -- closing, or recovering. This is deliberately not a B06 distributed commit.
  if tx.type == "DIB_USED" and Dibs.Governance and Dibs.Governance.GetDibUseGate then
    local allowed, gateReason = Dibs.Governance.GetDibUseGate()
    if not allowed then
      local proposal = Dibs.Governance.RecordAwardProposal and Dibs.Governance.RecordAwardProposal(
        context and context.actor or Dibs.GetPlayerName(), input)
      return { accepted = false, idempotentReplay = false, reasonCode = gateReason, proposal = proposal }
    end
  end
  if existing then
    if sameCanonicalContent(existing, tx) then return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(existing) } end
    return { accepted = false, idempotentReplay = false, reasonCode = "TRANSACTION_CONFLICT" }
  end
  if tx.type == "SEASON_ALLOCATION" and context and context.systemBootstrap == true then
    local state = ledger.playerStates[tx.seasonId] and ledger.playerStates[tx.seasonId][tx.memberKey]
    if state and (tonumber(state.allocation) or 0) ~= 0 then
      return { accepted = false, idempotentReplay = false, reasonCode = "SEASON_ALLOCATION_EXISTS" }
    end
  end
  if tx.type == "DIB_USED" and tx.debtPolicy.allowDebt ~= true and getCurrentBalance(tx.memberKey, tx.seasonId, ledgerId) + tx.amount < 0 then
    return { accepted = false, idempotentReplay = false, reasonCode = "INSUFFICIENT_BALANCE" }
  end
  return { accepted = true, idempotentReplay = false, reasonCode = "COMMITTED_LOCAL", value = copy(appendValidated(tx, ledgerId)) }
end

local function proposalFor(context, evidence)
  return Dibs.Governance and Dibs.Governance.RecordAwardProposal and Dibs.Governance.RecordAwardProposal(
    context and context.actor or Dibs.GetPlayerName(), evidence)
end

function Ledger.GetCanonicalState(targetLedgerId)
  local ledgerId = targetLedgerId or Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return nil end
  local ledger = ensureState(ledgerId)
  if v2Enforced() then
    local authorityState = authority()
    if authorityState and authorityState.state == "ACTIVE" then canonicalStateForAuthority(ledger, authorityState) end
  end
  local canonical = ledger.canonical
  return copy({ schema = canonical.schema, epoch = canonical.epoch, nextSeq = canonical.nextSeq, rootHash = canonical.rootHash,
    commitCount = (function() local n = 0; for _ in pairs(canonical.commits) do n = n + 1 end; return n end)() })
end

-- Sync digest callers need only stable scalar fields. Preserve the same
-- approval and authority-epoch reconciliation as GetCanonicalState without
-- counting or copying the full commit map on this hot path.
function Ledger.GetCanonicalDigestState(targetLedgerId, authorityDigest)
  local db = Dibs.db
  local guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or nil
  local resolved = guildKey and Dibs.currentGuildKey == guildKey and type(db) == "table"
  local ledgerId = targetLedgerId
  if resolved then ledgerId = ledgerId or db.activeLedgerId or "guild-primary" end
  if not ledgerId then ledgerId = Ledger.GetActiveLedgerId() end
  local ledger = resolved and type(db.ledgers) == "table" and db.ledgers[ledgerId] or nil
  if ledgerId == "guild-primary" and not ledger and resolved then ledger = db.ledger end
  local canonical = ledger and ledger.canonical
  local fastApproved = ledgerId == "guild-primary" or (ledger and ledger.status == "APPROVED"
    and Dibs.Governance and Dibs.Governance.IsLedgerApproved
    and Dibs.Governance.IsLedgerApproved(ledgerId) == true)
  if not resolved or not ledger or type(canonical) ~= "table"
    or canonical.schema ~= CANONICAL_SCHEMA or not fastApproved then
    if not isApprovedLedger(ledgerId) then return nil end
    ledger = ensureState(ledgerId)
    canonical = ledger.canonical
  end
  local governance = Dibs.Governance
  if authorityDigest == nil then
    authorityDigest = governance and governance.GetAuthorityDigestState
      and governance.GetAuthorityDigestState() or nil
  end
  local isEnforced = authorityDigest and authorityDigest.protocolState == "V2_ENFORCED"
  if isEnforced == nil then isEnforced = v2Enforced() end
  if isEnforced then
    local authorityState
    if authorityDigest then
      authorityState = {
        state = authorityDigest.state,
        ledgerEpoch = authorityDigest.ledgerEpoch,
        transition = authorityDigest.transitionKind and {
          kind = authorityDigest.transitionKind,
          baselineHash = authorityDigest.transitionRootHash,
          parentClosure = authorityDigest.parentClosureRootHash and { rootHash = authorityDigest.parentClosureRootHash } or nil,
        } or nil,
      }
    else
      authorityState = authority()
    end
    if authorityState and authorityState.state == "ACTIVE" then
      local canonical, reason = canonicalStateForAuthority(ledger, authorityState)
      if not canonical then return nil, reason end
    end
  end
  canonical = ledger.canonical
  return {
    epoch = canonical.epoch,
    nextSeq = canonical.nextSeq,
    rootHash = canonical.rootHash,
  }
end

function Ledger.GetCanonicalCommit(epoch, sequence, targetLedgerId)
  local ledgerId = targetLedgerId or Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return nil end
  return copy(ensureState(ledgerId).canonical.commits[positionKey(epoch, sequence)])
end

function Ledger.CommitAwardProposal(context, proposalId, awardEvidence)
  if not v2Enforced() then return { accepted = false, reasonCode = "V2_ENFORCED_REQUIRED" } end
  local authorityState = authority(); local coordinator, coordinatorReason = localCoordinator(authorityState, context and context.actor)
  if not coordinator then return { accepted = false, reasonCode = coordinatorReason, proposal = proposalFor(context, awardEvidence) } end
  local evidence = copy(awardEvidence or {})
  local proposal = nil
  for _, candidate in ipairs(Dibs.Governance and Dibs.Governance.GetAwardProposals and Dibs.Governance.GetAwardProposals() or {}) do
    if candidate.proposalId == proposalId then proposal = candidate break end
  end
  if not proposal or proposal.status ~= "PENDING_RECONCILIATION" then return { accepted = false, reasonCode = "PROPOSAL_NOT_PENDING" } end
  local ledgerId = proposal.ledgerId or (awardEvidence and awardEvidence.ledgerId)
    or (context and context.ledgerId) or Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return { accepted = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  evidence.ledgerId = ledgerId
  evidence.playerName = evidence.playerName or proposal.playerSnapshot.displayName
  evidence.proposalId = proposal.proposalId
  if proposal.reconciliation then
    evidence.reconciliation = copy(proposal.reconciliation)
    evidence.reconciliation.proposalId = proposal.proposalId
    evidence.amount = evidence.amount or proposal.amount
    local valid, validationReason = validateRankReconciliation(evidence.reconciliation, evidence.playerName, tonumber(evidence.amount))
    if not valid then
      if string.match(tostring(validationReason), "^STALE_") or validationReason == "AUTHORITY_CHANGED" then
        if Dibs.Governance and Dibs.Governance.ResolveAwardProposal then
          Dibs.Governance.ResolveAwardProposal(proposal.proposalId, "STALE", validationReason)
        end
      elseif validationReason ~= "SYNC_BEHIND" and validationReason ~= "COORDINATOR_UNAVAILABLE" then
        if Dibs.Governance and Dibs.Governance.ResolveAwardProposal then
          Dibs.Governance.ResolveAwardProposal(proposal.proposalId, "REJECTED", validationReason)
        end
      end
      return { accepted = false, reasonCode = validationReason, proposalId = proposal.proposalId }
    end
  end
  local result
  if proposal.type == "SEASON_ALLOCATION" then
    evidence.amount = evidence.amount or proposal.amount
    evidence.seasonId = evidence.seasonId or proposal.seasonId
    evidence.rankIndex = evidence.rankIndex or proposal.rankIndex
    evidence.rankName = evidence.rankName or proposal.rankName
    evidence.reason = evidence.reason or proposal.context
    evidence.source = evidence.source or proposal.source
    context = copy(context or {}); context.ledgerId = ledgerId
    result = Ledger.CommitSeasonAllocation(context, evidence)
  else
    evidence.itemID = evidence.itemID or proposal.itemID; evidence.itemLink = evidence.itemLink or proposal.itemLink
    evidence.awardRef = evidence.awardRef or proposal.awardRef; evidence.evidenceId = evidence.evidenceId or proposal.evidenceId
    context = copy(context or {}); context.ledgerId = ledgerId
    result = Ledger.CommitDibUse(context, evidence)
  end
  if result.accepted and Dibs.Governance and Dibs.Governance.MarkAwardProposalCommitted then
    Dibs.Governance.MarkAwardProposalCommitted(proposal.proposalId, result.value)
  end
  return result
end

function Ledger.ApplyAwardCommit(commit, sender, targetLedgerId)
  if not v2Enforced() then return { accepted = false, reasonCode = "V2_ENFORCED_REQUIRED" } end
  if type(commit) ~= "table" or commit.schema ~= CANONICAL_SCHEMA or commit.recordClass ~= "AWARD_COMMIT"
    or commit.guildKey ~= Dibs.GetGuildKey() or commit.protocolMajor ~= 2 then return { accepted = false, reasonCode = "INVALID_AWARD_COMMIT" } end
  local authorityState = authority()
  if not authorityState or authorityState.state ~= "ACTIVE" or commit.ledgerEpoch ~= authorityState.ledgerEpoch
    or type(commit.coordinator) ~= "table" or commit.coordinator.memberKey ~= authorityState.coordinator.memberKey then return { accepted = false, reasonCode = "STALE_EPOCH" } end
  if Dibs.Identity and Dibs.Identity.CreateSnapshot then
    local senderSnapshot, senderReason = Dibs.Identity.CreateSnapshot(sender)
    if not senderSnapshot then return { accepted = false, reasonCode = senderReason } end
    if senderSnapshot.memberKey ~= commit.coordinator.memberKey then return { accepted = false, reasonCode = "CURRENT_COORDINATOR_REQUIRED" } end
  end
  local declaredLedgerId = commit.ledgerId or "guild-primary"
  local ledgerId = targetLedgerId or declaredLedgerId
  if declaredLedgerId ~= ledgerId then return { accepted = false, reasonCode = "LEDGER_SCOPE_MISMATCH" } end
  if not isApprovedLedger(ledgerId) then return { accepted = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  local ledger = ensureState(ledgerId); local canonical, canonicalReason = canonicalStateForAuthority(ledger, authorityState)
  if not canonical then return { accepted = false, reasonCode = canonicalReason } end
  local key = positionKey(commit.ledgerEpoch, commit.sequence); local known = canonical.commits[key]
  local expectedHash, hashReason = canonicalCommitHash(commit)
  if not expectedHash or expectedHash ~= commit.commitHash then return { accepted = false, reasonCode = hashReason or "COMMIT_HASH_MISMATCH" } end
  if known then
    if known.commitHash == commit.commitHash then
      if commit.proposalId and Dibs.Governance and Dibs.Governance.MarkAwardProposalCommitted then
        Dibs.Governance.MarkAwardProposalCommitted(commit.proposalId, known)
      end
      if commit.proposalId and Dibs.Sync and Dibs.Sync.ClearAwardReservation then
        Dibs.Sync.ClearAwardReservation(commit.proposalId, known)
      end
      return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(known) }
    end
    return { accepted = false, reasonCode = "CANONICAL_POSITION_CONFLICT" }
  end
  if commit.sequence ~= canonical.nextSeq then
    if commit.sequence > canonical.nextSeq and Dibs.Sync and Dibs.Sync.MarkSyncBehind then Dibs.Sync.MarkSyncBehind("LEDGER_GAP") end
    return { accepted = false, reasonCode = commit.sequence > canonical.nextSeq and "SYNC_BEHIND" or "STALE_SEQUENCE" }
  end
  if commit.previousHash ~= canonical.rootHash then return { accepted = false, reasonCode = "PREVIOUS_HASH_MISMATCH" } end
  if type(commit.transaction) ~= "table" or commit.transaction.transactionId ~= commit.canonicalTransactionId
    or commit.transaction.canonicalContentHash ~= commit.transactionHash then return { accepted = false, reasonCode = "TRANSACTION_HASH_MISMATCH" } end
  local transactionHash = transactionCanonicalHash(commit.transaction)
  if transactionHash ~= commit.transactionHash then return { accepted = false, reasonCode = "TRANSACTION_HASH_MISMATCH" } end
  local valid, validationReason = Ledger.ValidateTransaction(commit.transaction)
  if not valid then return { accepted = false, reasonCode = validationReason } end
  local existing = ledger.transactions[commit.canonicalTransactionId]
  if existing then return { accepted = false, reasonCode = existing.canonicalContentHash == commit.transactionHash and "TRANSACTION_ALREADY_LOCAL" or "TRANSACTION_CONFLICT" } end
  -- All validation is complete before either transaction projection or chain state mutates.
  appendValidated(copy(commit.transaction), ledgerId)
  canonical.commits[key], canonical.positions[key], canonical.transactionIndex[commit.canonicalTransactionId] = copy(commit), commit.commitHash, key
  canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
  if commit.proposalId and Dibs.Governance and Dibs.Governance.MarkAwardProposalCommitted then
    Dibs.Governance.MarkAwardProposalCommitted(commit.proposalId, commit)
  end
  if commit.proposalId and Dibs.Sync and Dibs.Sync.ClearAwardReservation then
    Dibs.Sync.ClearAwardReservation(commit.proposalId, commit)
  end
  return { accepted = true, idempotentReplay = false, reasonCode = "CANONICAL_APPLIED", value = copy(commit) }
end

-- B06 canonical command. Legacy local operation remains unchanged until the
-- GM explicitly enforces V2; after cutover this is the only DIB_USED writer.
function Ledger.CommitDibUse(context, awardEvidence)
  local evidence = copy(awardEvidence or {}); evidence.type, evidence.actionType = "DIB_USED", "DIB_USED"
  local ledgerId = (context and context.ledgerId) or evidence.ledgerId or Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return { accepted = false, idempotentReplay = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  evidence.ledgerId = ledgerId
  evidence.amount = -math.abs(tonumber(evidence.amount) or 1)
  evidence.seasonId = evidence.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId())
  if not v2Enforced() then return Ledger.CommitLocalTransaction(context, evidence, ledgerId) end
  local authorityState = authority(); local coordinator, coordinatorReason = localCoordinator(authorityState, context and context.actor)
  if not coordinator then return { accepted = false, idempotentReplay = false, reasonCode = coordinatorReason, proposal = proposalFor(context, evidence) } end
  local ledger = ensureState(ledgerId); local canonical, canonicalReason = canonicalStateForAuthority(ledger, authorityState)
  if not canonical then return { accepted = false, idempotentReplay = false, reasonCode = canonicalReason } end
  local stableAwardId = evidence.transactionId or evidence.proposalId or evidence.awardRef or evidence.evidenceId
  if type(stableAwardId) ~= "string" or stableAwardId == "" then
    return { accepted = false, idempotentReplay = false, reasonCode = "STABLE_AWARD_ID_REQUIRED" }
  end
  evidence.transactionId = evidence.transactionId or ("c" .. tostring(authorityState.ledgerEpoch) .. "-" .. stableAwardId)
  local tx, txReason = buildDetachedTransaction({ action = (context and context.action) or "ledger.use", actor = coordinator.displayName,
    debtPolicy = context and context.debtPolicy, b06Canonical = true, ledgerId = ledgerId }, evidence)
  if not tx then return { accepted = false, idempotentReplay = false, reasonCode = txReason } end
  local existing = ledger.transactions[tx.transactionId]
  if existing then
    local key = canonical.transactionIndex[tx.transactionId]; local known = key and canonical.commits[key]
    if known and existing.canonicalContentHash == tx.canonicalContentHash then return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(known) } end
    return { accepted = false, idempotentReplay = false, reasonCode = "TRANSACTION_CONFLICT" }
  end
  if tx.debtPolicy.allowDebt ~= true and getCurrentBalance(tx.memberKey, tx.seasonId, ledgerId) + tx.amount < 0 then return { accepted = false, idempotentReplay = false, reasonCode = "INSUFFICIENT_BALANCE" } end
  local commit = { schema = CANONICAL_SCHEMA, recordClass = "AWARD_COMMIT", guildKey = Dibs.GetGuildKey(), protocolMajor = 2,
    ledgerEpoch = authorityState.ledgerEpoch, sequence = canonical.nextSeq, previousHash = canonical.rootHash,
    canonicalTransactionId = tx.transactionId, transactionHash = tx.canonicalContentHash, transaction = tx,
    coordinator = { memberKey = coordinator.memberKey, displayName = coordinator.displayName, guidWitness = coordinator.guidWitness }, proposalId = evidence.proposalId }
  if ledgerId ~= "guild-primary" then commit.ledgerId = ledgerId end
  local commitHash, hashReason = canonicalCommitHash(commit); if not commitHash then return { accepted = false, idempotentReplay = false, reasonCode = hashReason } end
  commit.commitHash = commitHash
  -- Stage construction completed. The durable transaction and canonical cursor
  -- now advance together before any caller can broadcast this commit.
  appendValidated(tx, ledgerId)
  local key = positionKey(commit.ledgerEpoch, commit.sequence)
  canonical.commits[key], canonical.positions[key], canonical.transactionIndex[tx.transactionId] = copy(commit), commit.commitHash, key
  canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
  if Dibs.Sync and Dibs.Sync.AnnounceAwardCommit then Dibs.Sync.AnnounceAwardCommit(copy(commit)) end
  return { accepted = true, idempotentReplay = false, reasonCode = "CANONICAL_COMMITTED", value = copy(commit) }
end

-- Compatibility validation for imported/legacy records; it never upgrades them.
function Ledger.ValidateTransaction(record)
  local tx = record or {}
  if type(tx.transactionId) ~= "string" or tx.transactionId == "" then return false, "MISSING_TRANSACTION_ID" end
  if not finiteNumber(tx.timestamp or tx.createdAt) then return false, "MISSING_TIMESTAMP" end
  local seasonOK, seasonReason = validateSeason(tx.seasonId); if not seasonOK then return false, seasonReason end
  if type(tx.playerName) ~= "string" or tx.playerName == "" then return false, "MISSING_PLAYER_IDENTITY" end
  local actionType = tx.actionType or tx.type; if type(actionType) ~= "string" or not VALID_ACTION_TYPES[actionType] then return false, "INVALID_ACTION_TYPE" end
  local amount = tonumber(tx.quantityDelta or tx.amount)
  if not finiteNumber(amount) or amount == 0 then return false, "MISSING_QUANTITY_DELTA" end
  if not actionAmountIsValid(actionType, amount, tx.reconciliation) then return false, "INVALID_QUANTITY_SIGN" end
  if math.abs(amount) > 100000 then return false, "QUANTITY_OUT_OF_RANGE" end
  return true
end

-- RF-0012 canonical dispute operations. These helpers deliberately keep the
-- immutable intent separate from the persisted canonical commit.
local DISPUTE_OPERATION_WRITES_ENABLED = false
local function operationReadinessProbe(operation)
  if type(operation) ~= "table" then return false, "INVALID_OPERATION" end
  if not isApprovedLedger(operation.ledgerId) then return false, "LEDGER_NOT_APPROVED" end
  if not v2Enforced() then return false, "V2_ENFORCED_REQUIRED" end
  local recovery = Dibs.canonicalOperationRecoveryStatus
  if operation.ledgerId ~= "guild-primary" then
    recovery = Dibs.canonicalOperationRecoveryStatuses and Dibs.canonicalOperationRecoveryStatuses[operation.ledgerId]
  end
  if type(recovery) ~= "table" or recovery.rebuilt ~= true
    or recovery.ledgerId ~= operation.ledgerId or recovery.guildKey ~= Dibs.GetGuildKey() then
    return false, "CANONICAL_RECOVERY_UNAVAILABLE"
  end
  local authorityState = authority()
  if not authorityState or authorityState.state ~= "ACTIVE" or type(authorityState.coordinator) ~= "table" then
    return false, "COORDINATOR_UNAVAILABLE"
  end
  local identity = Dibs.Identity
  if not identity or type(identity.CreateSnapshot) ~= "function" then return false, "IDENTITY_UNAVAILABLE" end
  local coordinator, coordinatorReason = identity.CreateSnapshot(authorityState.coordinator.displayName)
  if not coordinator or coordinator.memberKey ~= authorityState.coordinator.memberKey then
    return false, coordinatorReason or "CURRENT_COORDINATOR_REQUIRED"
  end
  local sync = Dibs.Sync
  if not sync or type(sync.GetStatusSummary) ~= "function" or type(identity.GetRosterSnapshot) ~= "function" then
    return false, "SYNC_UNAVAILABLE"
  end
  local status = sync.GetStatusSummary()
  if not status or status.state == "SYNC_UNAVAILABLE" then return false, "SYNC_UNAVAILABLE" end
  if status.syncBehind then return false, "SYNC_BEHIND" end
  if status.protocolState ~= "V2_ENFORCED" then return false, "V2_ENFORCED_REQUIRED" end
  local current = Ledger.ClassifyCanonicalRecovery(operation.ledgerId)
  if not current or current.classification ~= "VALID" then
    return false, current and current.reasonCode or "CANONICAL_STATE_NOT_READY"
  end
  local db = Dibs.GetDB()
  local ledger = db.ledgers and db.ledgers[operation.ledgerId]
  local canonical = ledger and ledger.canonical
  if not canonical or (canonical.epoch ~= nil and canonical.epoch ~= authorityState.ledgerEpoch) then
    return false, "STALE_EPOCH"
  end
  -- Read persisted protocol advertisements and the verified roster directly.
  -- UI peer projections also initialize digest subtrees and are not a read-only
  -- acceptance guard. Offline peers are checked when they reconnect.
  local localMember = identity.CreateSnapshot(Dibs.GetPlayerName())
  local roster = identity.GetRosterSnapshot()
  if not localMember or type(roster) ~= "table" then return false, "IDENTITY_UNAVAILABLE" end
  local peers = db.sync and db.sync.v2 and db.sync.v2.peers or {}
  for _, row in ipairs(roster) do
    local peer = peers[row.memberKey]
    if row.memberKey ~= localMember.memberKey and row.online == true and peer then
      local protocol = peer.protocol
      if not protocol or protocol.major ~= 2 or not protocol.capabilities
        or protocol.capabilities.ledgerOperationCommit ~= true
        or protocol.operationProtocolVersion ~= 1 or protocol.operationSchemaVersion ~= 1 then
        return false, "OPERATION_PEER_INCOMPATIBLE"
      end
    end
  end
  return true
end
local operationFailureProbe
local DISPUTE_OPERATION_TYPES = {
  DISPUTE_BALANCE_CORRECTION = 1,
  DISPUTE_TARGET_TRANSFER = 2,
  DISPUTE_ATTRIBUTION_RESOLUTION = 0,
}
local DISPUTE_OPERATION_ACTIONS = {
  DIB_USED = true, DIB_REFUNDED = true, DIB_ADMIN_ADJUSTMENT = true,
}

local function disputeOperationContent(operation)
  local result = {}
  for key, value in pairs(operation or {}) do
    if key ~= "payloadHash" then result[key] = value end
  end
  return result
end

function Ledger.CalculateDisputeOperationPayloadHash(operation)
  if type(operation) ~= "table" then return nil, "INVALID_OPERATION" end
  local serialized, reason = canonicalSerialize(disputeOperationContent(operation))
  if not serialized then return nil, reason end
  return contentHash(serialized)
end

local function validOperationId(value)
  return type(value) == "string" and value ~= "" and #value <= 160 and trim(value) == value
end

local function operationRequest(operation)
  -- This is an internal protocol validation read, not a user-facing dossier
  -- read. GetRequest applies the receiver's local officer/player visibility
  -- policy and returns a redacted view, which can reject a valid coordinator
  -- commit on an otherwise authorized replica.
  local db = Dibs.GetDB and Dibs.GetDB() or _G.DibsDB or {}
  local requests = db.disputes and db.disputes.requests
  local request = type(requests) == "table" and requests[operation.requestId] or nil
  if type(request) ~= "table" then return nil, "REQUEST_NOT_FOUND" end
  return request
end

local function operationLedgerData(ledgerId)
  local db = Dibs.GetDB and Dibs.GetDB() or _G.DibsDB or {}
  local ledger = db.ledgers and db.ledgers[ledgerId]
  if not ledger and ledgerId == "guild-primary" then ledger = db.ledger end
  if type(ledger) ~= "table" then return nil, "LEDGER_NOT_FOUND" end
  return ledger
end

function Ledger.ValidateDisputeOperation(operation)
  if type(operation) ~= "table" then return false, "INVALID_OPERATION" end
  if operation.schemaVersion ~= 1 then return false, "UNSUPPORTED_OPERATION_VERSION" end
  if not validOperationId(operation.operationId) or not DISPUTE_OPERATION_TYPES[operation.operationType]
    or type(operation.guildKey) ~= "string" or operation.guildKey == ""
    or operation.guildKey ~= (Dibs.GetGuildKey and Dibs.GetGuildKey())
    or not validOperationId(operation.ledgerId) or not isApprovedLedger(operation.ledgerId)
    or not validOperationId(operation.requestId) or not finiteInteger(operation.requestRevision) or operation.requestRevision < 1
    or (operation.evidenceId ~= false and not validOperationId(operation.evidenceId))
    or (operation.originalTransactionId ~= false and not validOperationId(operation.originalTransactionId))
    or not finiteNumber(operation.timestamp) or type(operation.reason) ~= "string" or trim(operation.reason) == nil
    or #operation.reason > 500 or type(operation.actor) ~= "table"
    or not validOperationId(operation.actor.memberKey) or type(operation.actor.displayName) ~= "string"
    or not validOperationId(operation.actor.displayName) or type(operation.signedEntries) ~= "table"
    or type(operation.payloadHash) ~= "string" then return false, "INVALID_OPERATION" end
  local hash, hashReason = Ledger.CalculateDisputeOperationPayloadHash(operation)
  if not hash or hash ~= operation.payloadHash then return false, hashReason or "HASH_MISMATCH" end
  local actor = Dibs.Identity and Dibs.Identity.ResolveRosterMember and Dibs.Identity.ResolveRosterMember(operation.actor.displayName)
  if not actor or actor.status ~= "RESOLVED" or actor.memberKey ~= operation.actor.memberKey then return false, "PROPOSER_NOT_AUTHORIZED" end
  local request, requestReason = operationRequest(operation)
  if not request then return false, requestReason end
  if request.guildScope ~= nil and request.guildScope ~= operation.guildKey then return false, "GUILD_SCOPE_MISMATCH" end
  if request.revision ~= operation.requestRevision then return false, "STALE_DISPUTE_REVISION" end
  if request.status == (Dibs.Disputes.STATUSES and Dibs.Disputes.STATUSES.RESOLVED) then return false, "DISPUTE_NOT_CORRECTABLE" end
  local entryCount, maxIndex = 0, 0
  for key in pairs(operation.signedEntries) do
    if not finiteInteger(key) or key < 1 then return false, "INVALID_ENTRY" end
    entryCount = entryCount + 1; if key > maxIndex then maxIndex = key end
  end
  if entryCount ~= maxIndex or entryCount ~= DISPUTE_OPERATION_TYPES[operation.operationType] then return false, "INVALID_ENTRY" end
  if operation.operationType == "DISPUTE_ATTRIBUTION_RESOLUTION" then
    if operation.originalTransactionId ~= false then return false, "INVALID_OPERATION" end
    return true
  end
  if operation.originalTransactionId == false then return false, "ORIGINAL_TRANSACTION_MISSING" end
  local ledger, ledgerReason = operationLedgerData(operation.ledgerId)
  if not ledger then return false, ledgerReason end
  local original = ledger.transactions and ledger.transactions[operation.originalTransactionId]
  if type(original) ~= "table" then return false, "ORIGINAL_TRANSACTION_MISSING" end
  local originalMember = original.memberKey or original.playerKey
  local net, seenIds, firstMember = 0, {}, nil
  for index = 1, entryCount do
    local entry = operation.signedEntries[index]
    if type(entry) ~= "table" or entry.operationId ~= operation.operationId or entry.entryIndex ~= index
      or not validOperationId(entry.transactionId) or seenIds[entry.transactionId]
      or entry.guildKey ~= operation.guildKey or entry.ledgerId ~= operation.ledgerId
      or not validOperationId(entry.memberKey) or not validOperationId(entry.seasonId)
      or entry.actionType == nil or not DISPUTE_OPERATION_ACTIONS[entry.actionType]
      or not finiteInteger(entry.quantityDelta) or entry.quantityDelta == 0 or math.abs(entry.quantityDelta) > 100000
      or entry.evidenceId ~= operation.evidenceId or entry.originalTransactionId ~= operation.originalTransactionId
      or entry.requestId ~= operation.requestId or entry.requestRevision ~= operation.requestRevision then
      return false, "INVALID_ENTRY"
    end
    seenIds[entry.transactionId] = true
    local seasonOK = validateSeason(entry.seasonId)
    if not seasonOK then return false, "INVALID_ENTRY" end
    if entry.actionType == "DIB_USED" and entry.quantityDelta >= 0 then return false, "INVALID_ENTRY" end
    if entry.actionType == "DIB_REFUNDED" and entry.quantityDelta <= 0 then return false, "INVALID_ENTRY" end
    if entry.actionType == "DIB_ADMIN_ADJUSTMENT" and entry.quantityDelta == 0 then return false, "INVALID_ENTRY" end
    if not Dibs.Identity or not Dibs.Identity.ResolveRosterMember then return false, "INVALID_ENTRY" end
    local member = Dibs.Identity.ResolveRosterMember(entry.memberKey)
    if not member or member.status ~= "RESOLVED" or member.memberKey ~= entry.memberKey then return false, "INVALID_ENTRY" end
    if index == 1 then firstMember = entry.memberKey end
    if operation.operationType == "DISPUTE_BALANCE_CORRECTION" and entry.memberKey ~= originalMember then return false, "ORIGINAL_TRANSACTION_MISMATCH" end
    net = net + entry.quantityDelta
  end
  if operation.operationType == "DISPUTE_TARGET_TRANSFER" and (net ~= 0 or firstMember ~= originalMember
    or operation.signedEntries[1].memberKey == operation.signedEntries[2].memberKey) then return false, "INVALID_ENTRY" end
  if operation.evidenceId ~= false then
    local found = false
    for _, evidence in ipairs(request.evidence or {}) do if evidence.evidenceId == operation.evidenceId then found = true; break end end
    if not found then return false, "INVALID_ENTRY" end
  end
  return true
end

function Ledger.BuildDisputeOperation(intent)
  if type(intent) ~= "table" then return nil, "INVALID_OPERATION" end
  local operation = copy(intent)
  operation.payloadHash = nil
  local hash, reason = Ledger.CalculateDisputeOperationPayloadHash(operation)
  if not hash then return nil, reason end
  operation.payloadHash = hash
  local valid, validationReason = Ledger.ValidateDisputeOperation(operation)
  if not valid then return nil, validationReason end
  return operation
end

function Ledger.CheckDisputeOperationReplay(operation)
  if type(operation) ~= "table" then return nil, "INVALID_OPERATION" end
  local db = Dibs.GetDB and Dibs.GetDB() or _G.DibsDB or {}
  local candidate, candidateReason = canonicalSerialize(disputeOperationContent(operation))
  if not candidate then return nil, candidateReason end
  local foundOperation, foundCommit, foundLedger, transactionCollision
  for ledgerId, ledger in pairs(db.ledgers or {}) do
    for _, commit in pairs((ledger.canonical and ledger.canonical.commits) or {}) do
      if type(commit) == "table" and commit.recordClass == "LEDGER_OPERATION_COMMIT" and type(commit.operation) == "table" then
        local existing = commit.operation
        if existing.operationId == operation.operationId then
          local serialized = canonicalSerialize(disputeOperationContent(existing))
          if foundOperation or foundLedger and foundLedger ~= ledgerId or existing.guildKey ~= operation.guildKey
            or existing.ledgerId ~= operation.ledgerId or serialized ~= candidate or existing.payloadHash ~= operation.payloadHash then
            return { status = "CONFLICT", reasonCode = "OPERATION_ID_CONFLICT" }
          end
          foundOperation, foundCommit, foundLedger = existing, commit, ledgerId
        end
        for _, entry in ipairs(operation.signedEntries or {}) do
          if commit.canonicalTransactionId == entry.transactionId
            or (type(commit.operation.signedEntries) == "table" and (function()
              for _, known in ipairs(commit.operation.signedEntries) do if known.transactionId == entry.transactionId then return true end end
              return false
            end)()) then transactionCollision = true end
        end
      elseif type(commit) == "table" then
        for _, entry in ipairs(operation.signedEntries or {}) do if commit.canonicalTransactionId == entry.transactionId then transactionCollision = true end end
      end
    end
  end
  for _, entry in ipairs(operation.signedEntries or {}) do
    for _, ledger in pairs(db.ledgers or {}) do
      if ledger.transactions and ledger.transactions[entry.transactionId] then transactionCollision = true end
    end
  end
  if transactionCollision and not foundOperation then return { status = "CONFLICT", reasonCode = "TRANSACTION_ID_CONFLICT" } end
  if foundOperation then return { status = "REPLAY", reasonCode = "IDEMPOTENT_REPLAY", commit = copy(foundCommit) } end
  return { status = "NEW" }
end

-- Keep the canonical-operation release gate shared by local writers and Sync.
-- A peer must not advertise or apply this protocol while the local writer is
-- disabled, even if the wire receiver is otherwise available.
function Ledger.IsDisputeOperationTransportEnabled()
  return Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED == true and DISPUTE_OPERATION_WRITES_ENABLED == true
end

local function requireRecoverableCanonicalLedger(ledgerId)
  if type(Ledger.ClassifyCanonicalRecovery) ~= "function" then return false, "CANONICAL_RECOVERY_UNAVAILABLE" end
  local status = Ledger.ClassifyCanonicalRecovery(ledgerId)
  if status.classification == "INCOMPLETE_PROJECTION" or status.classification == "INDEX_MISMATCH" then
    if type(Ledger.RebuildLedgerProjections) ~= "function" then return false, "CANONICAL_STATE_NOT_READY" end
    local rebuilt = Ledger.RebuildLedgerProjections(ledgerId)
    if not rebuilt or rebuilt.rebuilt ~= true then return false, rebuilt and rebuilt.reasonCode or "CANONICAL_STATE_NOT_READY" end
    status = Ledger.ClassifyCanonicalRecovery(ledgerId)
  end
  if not status or status.classification ~= "VALID" then
    return false, status and status.reasonCode or "CANONICAL_STATE_NOT_READY"
  end
  return true
end

function Ledger.CommitDisputeOperation(context, operation)
  context = type(context) == "table" and context or {}
  if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true or not DISPUTE_OPERATION_WRITES_ENABLED then
    return { accepted = false, reasonCode = "CANONICAL_OPERATION_WRITES_DISABLED" }
  end
  if type(operationReadinessProbe) ~= "function" then return { accepted = false, reasonCode = "OPERATION_READINESS_UNKNOWN" } end
  local ready, readinessReason = operationReadinessProbe(operation)
  if ready ~= true then return { accepted = false, reasonCode = readinessReason or "OPERATION_NOT_READY" } end
  if not v2Enforced() then return { accepted = false, reasonCode = "V2_ENFORCED_REQUIRED" } end
  if operationFailureProbe then
    local failure = operationFailureProbe("pre-validation")
    if failure then return { accepted = false, reasonCode = type(failure) == "table" and failure.code or failure } end
  end
  local valid, validationReason = Ledger.ValidateDisputeOperation(operation)
  if not valid then return { accepted = false, reasonCode = validationReason or "INVALID_OPERATION" } end
  local replay = Ledger.CheckDisputeOperationReplay(operation)
  if not replay then return { accepted = false, reasonCode = "HISTORY_CONFLICT" } end
  if replay.status == "CONFLICT" then return { accepted = false, reasonCode = replay.reasonCode } end
  if replay.status == "REPLAY" then
    local replayLedgerId = replay.commit and replay.commit.ledgerId or operation.ledgerId
    local replayReady, replayRecoveryReason = requireRecoverableCanonicalLedger(replayLedgerId)
    if not replayReady then return { accepted = false, reasonCode = replayRecoveryReason or "CANONICAL_STATE_NOT_READY" } end
    return { accepted = true, idempotentReplay = true, reasonCode = replay.reasonCode, value = replay.commit }
  end
  local authorityState = authority()
  local coordinator, coordinatorReason = localCoordinator(authorityState, context.actor)
  if not coordinator then return { accepted = false, reasonCode = coordinatorReason or "COORDINATOR_UNAVAILABLE" } end
  local ledger = operationLedgerData(operation.ledgerId)
  if not ledger then return { accepted = false, reasonCode = "LEDGER_NOT_FOUND" } end
  local canonical, canonicalReason = canonicalStateForAuthority(ledger, authorityState)
  if not canonical or canonical.epoch ~= authorityState.ledgerEpoch or not finiteInteger(canonical.nextSeq)
    or type(canonical.rootHash) ~= "string" then return { accepted = false, reasonCode = canonicalReason or "CANONICAL_STATE_NOT_READY" } end
  local recoverable, recoveryReason = requireRecoverableCanonicalLedger(operation.ledgerId)
  if not recoverable then return { accepted = false, reasonCode = recoveryReason or "CANONICAL_STATE_NOT_READY" } end
  if operationFailureProbe then
    local failure = operationFailureProbe("pre-acceptance")
    if failure then return { accepted = false, reasonCode = type(failure) == "table" and failure.code or failure } end
  end
  for index = 1, #operation.signedEntries do
    local failure = operationFailureProbe and operationFailureProbe("before-entry-validation:" .. tostring(index))
    if failure then return { accepted = false, reasonCode = failure } end
  end
  local commit = { schema = CANONICAL_SCHEMA, recordClass = "LEDGER_OPERATION_COMMIT", guildKey = operation.guildKey,
    ledgerId = operation.ledgerId, protocolVersion = 1, ledgerEpoch = canonical.epoch, sequence = canonical.nextSeq,
    previousHash = canonical.rootHash, payloadHash = operation.payloadHash, operation = copy(operation),
    proposer = { memberKey = operation.actor.memberKey, displayName = operation.actor.displayName },
    coordinator = { memberKey = coordinator.memberKey, displayName = coordinator.displayName } }
  local serialized, serializeReason = canonicalSerialize(commit)
  if not serialized then return { accepted = false, reasonCode = serializeReason } end
  commit.commitHash = contentHash(serialized)
  local key = positionKey(commit.ledgerEpoch, commit.sequence)
  -- Acceptance is one immutable commit. All semantic checks finish before the
  -- canonical boundary; projection work is deliberately replayable afterward.
  canonical.commits[key], canonical.positions[key] = copy(commit), commit.commitHash
  canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
  if Dibs.Sync and Dibs.Sync.AnnounceDisputeOperationCommit then
    pcall(Dibs.Sync.AnnounceDisputeOperationCommit, copy(commit))
  end
  if operationFailureProbe then local failure = operationFailureProbe("after-canonical-acceptance"); if failure then return { accepted = false, reasonCode = type(failure) == "table" and failure.code or failure } end end
  local projectedRows = {}
  for index, entry in ipairs(operation.signedEntries) do
    local tx = { schema = SCHEMA, recordClass = "LEDGER_TRANSACTION", classification = CLASSIFICATION,
      transactionId = entry.transactionId, type = entry.actionType, actionType = entry.actionType, action = entry.actionType,
      memberKey = entry.memberKey, playerKey = entry.memberKey, playerName = (Dibs.Identity.ResolveRosterMember(entry.memberKey) or {}).displayName,
      seasonId = entry.seasonId, amount = entry.quantityDelta, quantityDelta = entry.quantityDelta,
      reason = operation.reason, source = "dispute-operation", createdAt = operation.timestamp, timestamp = operation.timestamp,
      operationId = operation.operationId, entryIndex = index, originalTransactionId = operation.originalTransactionId,
      evidenceId = operation.evidenceId ~= false and operation.evidenceId or nil,
      reviewRequestId = operation.requestId, actorId = operation.actor.memberKey, actorSnapshot = copy(operation.actor),
      context = { authority = "coordinator", action = "dispute.operation" }, debtPolicy = { allowDebt = true, source = "CANONICAL_DISPUTE_OPERATION" } }
    tx.identitySnapshot = copy(Dibs.Identity.CreateSnapshot(entry.memberKey))
    tx.canonicalContentHash = transactionCanonicalHash(tx)
    appendValidated(tx, operation.ledgerId)
    projectedRows[#projectedRows + 1] = tx
    if operationFailureProbe then local failure = operationFailureProbe("balance"); if failure then return { accepted = false, reasonCode = type(failure) == "table" and failure.code or failure } end end
    if operationFailureProbe then local failure = operationFailureProbe("transaction-row:" .. tostring(index)); if failure then return { accepted = false, reasonCode = type(failure) == "table" and failure.code or failure } end end
  end
  if operationFailureProbe then local failure = operationFailureProbe("transaction-index"); if failure then return { accepted = false, reasonCode = type(failure) == "table" and failure.code or failure } end end
  for _, tx in ipairs(projectedRows) do canonical.transactionIndex[tx.transactionId] = key end
  return { accepted = true, idempotentReplay = false, reasonCode = "CANONICAL_COMMITTED", value = copy(commit) }
end

-- Reconstruct the mutable accounting views from the immutable award journal
-- and retained pre-journal transaction rows. Prepare every projection before
-- publishing it so malformed history cannot leave a half-rebuilt ledger.
local function operationRecoveryRows(commit, ledgerId, sequence)
  local allowedActions = { DIB_USED = true, DIB_REFUNDED = true, DIB_ADMIN_ADJUSTMENT = true }
  if type(commit) ~= "table" or commit.recordClass ~= "LEDGER_OPERATION_COMMIT"
    or commit.protocolVersion ~= 1 or type(commit.operation) ~= "table" then
    return nil, "INVALID_OPERATION_COMMIT"
  end
  local operation = commit.operation
  if operation.schemaVersion ~= 1 or type(operation.operationId) ~= "string" or operation.operationId == ""
    or operation.guildKey ~= Dibs.GetGuildKey() or operation.ledgerId ~= ledgerId
    or type(operation.payloadHash) ~= "string" or commit.payloadHash ~= operation.payloadHash
    or type(operation.signedEntries) ~= "table" or type(operation.actor) ~= "table"
    or type(commit.proposer) ~= "table" or commit.proposer.memberKey ~= operation.actor.memberKey
    or commit.proposer.displayName ~= operation.actor.displayName
    or type(commit.coordinator) ~= "table" or type(commit.coordinator.memberKey) ~= "string"
    or type(commit.coordinator.displayName) ~= "string" then
    return nil, "INVALID_OPERATION_COMMIT"
  end
  if type(Ledger.CalculateDisputeOperationPayloadHash) ~= "function" then return nil, "OPERATION_VALIDATOR_UNAVAILABLE" end
  local operationHash = Ledger.CalculateDisputeOperationPayloadHash(operation)
  if operationHash ~= operation.payloadHash then return nil, "CANONICAL_OPERATION_HASH_MISMATCH" end
  local commitContent = copy(commit)
  commitContent.commitHash = nil
  local serialized = canonicalSerialize(commitContent)
  if not serialized or contentHash(serialized) ~= commit.commitHash then return nil, "CANONICAL_COMMIT_HASH_MISMATCH" end

  local expectedEntries = operation.operationType == "DISPUTE_BALANCE_CORRECTION" and 1
    or operation.operationType == "DISPUTE_TARGET_TRANSFER" and 2
    or operation.operationType == "DISPUTE_ATTRIBUTION_RESOLUTION" and 0
  if expectedEntries == nil then return nil, "UNSUPPORTED_OPERATION_TYPE" end
  local count, maxIndex = 0, 0
  for key in pairs(operation.signedEntries) do
    if not finiteInteger(key) or key < 1 then return nil, "INVALID_OPERATION_ENTRY" end
    count = count + 1
    if key > maxIndex then maxIndex = key end
  end
  if count ~= maxIndex or count ~= expectedEntries then return nil, "INVALID_OPERATION_ENTRY" end

  local rows, seen, net, firstMember = {}, {}, 0, nil
  for index, entry in ipairs(operation.signedEntries) do
    if type(entry) ~= "table" or entry.operationId ~= operation.operationId or entry.entryIndex ~= index
      or type(entry.transactionId) ~= "string" or entry.transactionId == "" or seen[entry.transactionId]
      or entry.guildKey ~= operation.guildKey or entry.ledgerId ~= ledgerId
      or type(entry.memberKey) ~= "string" or entry.memberKey == ""
      or type(entry.seasonId) ~= "string" or entry.seasonId == ""
      or type(entry.actionType) ~= "string" or not allowedActions[entry.actionType]
      or not finiteInteger(entry.quantityDelta) or entry.quantityDelta == 0
      or entry.evidenceId ~= operation.evidenceId
      or entry.originalTransactionId ~= operation.originalTransactionId
      or entry.requestId ~= operation.requestId or entry.requestRevision ~= operation.requestRevision then
      return nil, "INVALID_OPERATION_ENTRY"
    end
    if not validateSeason(entry.seasonId) then return nil, "INVALID_OPERATION_ENTRY" end
    seen[entry.transactionId] = true
    if index == 1 then firstMember = entry.memberKey end
    if entry.actionType == "DIB_USED" and entry.quantityDelta >= 0 then return nil, "INVALID_OPERATION_ENTRY" end
    if entry.actionType == "DIB_REFUNDED" and entry.quantityDelta <= 0 then return nil, "INVALID_OPERATION_ENTRY" end
    local resolved = Dibs.Identity and Dibs.Identity.ResolveRosterMember
      and Dibs.Identity.ResolveRosterMember(entry.memberKey)
    local identity = resolved and resolved.status == "RESOLVED" and Dibs.Identity.CreateSnapshot(entry.memberKey)
    if not identity or identity.memberKey ~= entry.memberKey then return nil, "OPERATION_IDENTITY_UNAVAILABLE" end
    local actorSnapshot = copy(operation.actor)
    local tx = { schema = SCHEMA, recordClass = "LEDGER_TRANSACTION", classification = CLASSIFICATION,
      transactionId = entry.transactionId, type = entry.actionType, actionType = entry.actionType, action = entry.actionType,
      memberKey = entry.memberKey, playerKey = entry.memberKey, playerName = resolved.displayName,
      seasonId = entry.seasonId, amount = entry.quantityDelta, quantityDelta = entry.quantityDelta,
      reason = operation.reason, source = "dispute-operation", createdAt = operation.timestamp, timestamp = operation.timestamp,
      operationId = operation.operationId, entryIndex = index, originalTransactionId = operation.originalTransactionId,
      evidenceId = operation.evidenceId ~= false and operation.evidenceId or nil,
      reviewRequestId = operation.requestId, actorId = operation.actor.memberKey, actorSnapshot = actorSnapshot,
      context = { authority = "coordinator", action = "dispute.operation" },
      debtPolicy = { allowDebt = true, source = "CANONICAL_DISPUTE_OPERATION" }, identitySnapshot = identity }
    tx.canonicalContentHash = transactionCanonicalHash(tx)
    if not tx.canonicalContentHash then return nil, "CANONICAL_TRANSACTION_HASH_UNAVAILABLE" end
    rows[#rows + 1] = tx
    net = net + entry.quantityDelta
  end
  if operation.operationType == "DISPUTE_TARGET_TRANSFER"
    and (net ~= 0 or firstMember == operation.signedEntries[2].memberKey) then
    return nil, "INVALID_OPERATION_ENTRY"
  end
  if operation.operationType ~= "DISPUTE_ATTRIBUTION_RESOLUTION" then
    local db = Dibs.GetDB and Dibs.GetDB() or _G.DibsDB or {}
    local sourceLedger = db.ledgers and db.ledgers[ledgerId]
    if not sourceLedger and ledgerId == "guild-primary" then sourceLedger = db.ledger end
    local original = sourceLedger and sourceLedger.transactions and sourceLedger.transactions[operation.originalTransactionId]
    if not original then return nil, "ORIGINAL_TRANSACTION_MISSING" end
    if operation.operationType == "DISPUTE_BALANCE_CORRECTION"
      and operation.signedEntries[1].memberKey ~= (original.memberKey or original.playerKey) then
      return nil, "ORIGINAL_TRANSACTION_MISMATCH"
    end
    if operation.operationType == "DISPUTE_TARGET_TRANSFER"
      and operation.signedEntries[1].memberKey ~= (original.memberKey or original.playerKey) then
      return nil, "ORIGINAL_TRANSACTION_MISMATCH"
    end
  end
  return rows
end

-- Apply a coordinator-authored dispute operation commit received over Sync.
-- All validation and collision checks complete before the first SavedVariables
-- mutation, so a bad transfer cannot leave a partial ledger projection.
function Ledger.ApplyDisputeOperationCommit(commit, sender, targetLedgerId)
  if not Ledger.IsDisputeOperationTransportEnabled() then
    return { accepted = false, reasonCode = "CANONICAL_OPERATION_WRITES_DISABLED" }
  end
  if not v2Enforced() then return { accepted = false, reasonCode = "V2_ENFORCED_REQUIRED" } end
  if type(commit) ~= "table" or commit.schema ~= CANONICAL_SCHEMA
    or commit.recordClass ~= "LEDGER_OPERATION_COMMIT" or commit.protocolVersion ~= 1
    or commit.guildKey ~= Dibs.GetGuildKey() then
    return { accepted = false, reasonCode = "INVALID_OPERATION_COMMIT" }
  end
  local authorityState = authority()
  if not authorityState or authorityState.state ~= "ACTIVE" or commit.ledgerEpoch ~= authorityState.ledgerEpoch
    or type(commit.coordinator) ~= "table"
    or type(authorityState.coordinator) ~= "table"
    or commit.coordinator.memberKey ~= authorityState.coordinator.memberKey then
    return { accepted = false, reasonCode = "STALE_EPOCH" }
  end
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then
    return { accepted = false, reasonCode = "IDENTITY_UNAVAILABLE" }
  end
  local senderSnapshot = Dibs.Identity.CreateSnapshot(sender)
  if not senderSnapshot or senderSnapshot.memberKey ~= commit.coordinator.memberKey then
    return { accepted = false, reasonCode = "CURRENT_COORDINATOR_REQUIRED" }
  end
  local operation = commit.operation
  local ledgerId = targetLedgerId or (type(operation) == "table" and operation.ledgerId)
  if type(operation) ~= "table" or type(ledgerId) ~= "string" or ledgerId == ""
    or commit.ledgerId ~= ledgerId or operation.ledgerId ~= ledgerId then
    return { accepted = false, reasonCode = "LEDGER_SCOPE_MISMATCH" }
  end
  if not isApprovedLedger(ledgerId) then return { accepted = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  -- Do not initialize or reconcile a ledger while it is not in a state that
  -- can safely accept a remote commit. ensureState/canonicalStateForAuthority
  -- may create or repair mutable state, so classify the persisted ledger first.
  local persistedRecovery = Ledger.ClassifyCanonicalRecovery(ledgerId)
  if not persistedRecovery or persistedRecovery.classification ~= "VALID" then
    return { accepted = false, reasonCode = persistedRecovery and persistedRecovery.reasonCode
      or "CANONICAL_STATE_NOT_READY" }
  end
  local ledger = ensureState(ledgerId)
  local canonical, canonicalReason = canonicalStateForAuthority(ledger, authorityState)
  if not canonical then return { accepted = false, reasonCode = canonicalReason or "CANONICAL_STATE_NOT_READY" } end
  if type(commit.sequence) ~= "number" or commit.sequence ~= math.floor(commit.sequence) or commit.sequence < 1 then
    return { accepted = false, reasonCode = "INVALID_SEQUENCE" }
  end
  local key = positionKey(commit.ledgerEpoch, commit.sequence)
  -- Validate the received operation record before even acknowledging a replay.
  -- A matching claimed commitHash alone is insufficient because the payload
  -- may carry altered operation content under an already-known position.
  local rows, rowsReason = operationRecoveryRows(commit, ledgerId, commit.sequence)
  if not rows then return { accepted = false, reasonCode = rowsReason or "INVALID_OPERATION_COMMIT" } end
  local known = canonical.commits[key]
  if known then
    if known.commitHash == commit.commitHash then
      return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(known) }
    end
    return { accepted = false, reasonCode = "CANONICAL_POSITION_CONFLICT" }
  end
  if commit.sequence ~= canonical.nextSeq then
    if commit.sequence > canonical.nextSeq and Dibs.Sync and Dibs.Sync.MarkSyncBehind then Dibs.Sync.MarkSyncBehind("LEDGER_GAP") end
    return { accepted = false, reasonCode = commit.sequence > canonical.nextSeq and "SYNC_BEHIND" or "STALE_SEQUENCE" }
  end
  if commit.previousHash ~= canonical.rootHash then return { accepted = false, reasonCode = "PREVIOUS_HASH_MISMATCH" } end
  if type(operationReadinessProbe) ~= "function" then return { accepted = false, reasonCode = "OPERATION_READINESS_UNKNOWN" } end
  local ready, readinessReason = operationReadinessProbe(operation)
  if ready ~= true then return { accepted = false, reasonCode = readinessReason or "OPERATION_NOT_READY" } end
  local operationValid, operationReason = Ledger.ValidateDisputeOperation(operation)
  if not operationValid then return { accepted = false, reasonCode = operationReason or "INVALID_OPERATION" } end
  for _, row in ipairs(rows) do
    for _, candidateLedger in pairs((Dibs.GetDB() or {}).ledgers or {}) do
      if candidateLedger.transactions and candidateLedger.transactions[row.transactionId] then
        return { accepted = false, reasonCode = "TRANSACTION_ID_CONFLICT" }
      end
    end
  end
  local recoverable, recoveryReason = requireRecoverableCanonicalLedger(ledgerId)
  if not recoverable then
    return { accepted = false, reasonCode = recoveryReason or "CANONICAL_STATE_NOT_READY" }
  end

  canonical.commits[key], canonical.positions[key] = copy(commit), commit.commitHash
  canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
  for _, row in ipairs(rows) do
    appendValidated(row, ledgerId)
    canonical.transactionIndex[row.transactionId] = key
  end
  return { accepted = true, idempotentReplay = false, reasonCode = "CANONICAL_COMMITTED", value = copy(commit) }
end

function Ledger.ClassifyCanonicalRecovery(targetLedgerId)
  local ledgerId = targetLedgerId or Ledger.GetActiveLedgerId()
  local db = Dibs.GetDB and Dibs.GetDB()
  local ledger = db and db.ledgers and db.ledgers[ledgerId]
  if not ledger and ledgerId == "guild-primary" then ledger = db and db.ledger end
  if type(ledger) ~= "table" then return { classification = "UNRECOVERABLE", reasonCode = "LEDGER_NOT_FOUND" } end
  local canonical = ledger.canonical
  if type(canonical) ~= "table" or canonical.schema ~= CANONICAL_SCHEMA or type(canonical.commits) ~= "table" then
    return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_STATE_MISSING" }
  end
  if type(canonical.positions) ~= "table" or type(canonical.transactionIndex) ~= "table" then
    return { classification = "INDEX_MISMATCH", reasonCode = "CANONICAL_INDEX_MISSING" }
  end
  local epoch, nextSeq = tonumber(canonical.epoch), tonumber(canonical.nextSeq)
  if not finiteInteger(nextSeq) or nextSeq < 1 then
    return { classification = "UNRECOVERABLE", reasonCode = "INVALID_CANONICAL_STATE" }
  end
  local expectedRoot
  local authorityState = authority()
  if epoch and authorityState and authorityState.state == "ACTIVE" and authorityState.ledgerEpoch == epoch then
    expectedRoot = authorityRoot(authorityState)
  end
  local transactionIndex, positions = {}, {}
  for sequence = 1, nextSeq - 1 do
    if not epoch then return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_EPOCH_MISSING", sequence = sequence } end
    local key = positionKey(epoch, sequence)
    local commit = canonical.commits[key]
    if type(commit) ~= "table" then return { classification = "MISSING_SEQUENCE", reasonCode = "CANONICAL_SEQUENCE_GAP", sequence = sequence } end
    if commit.ledgerEpoch ~= epoch or commit.sequence ~= sequence or commit.guildKey ~= Dibs.GetGuildKey()
      or ((commit.ledgerId or "guild-primary") ~= ledgerId) then
      return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_SCOPE_MISMATCH", sequence = sequence }
    end
    if expectedRoot ~= nil and commit.previousHash ~= expectedRoot then
      return { classification = "WRONG_ROOT", reasonCode = "CANONICAL_PREVIOUS_HASH_MISMATCH", sequence = sequence }
    end
    local rows, rowReason
    if commit.recordClass == "AWARD_COMMIT" then
      if commit.schema ~= CANONICAL_SCHEMA or commit.protocolMajor ~= 2 or type(commit.transaction) ~= "table"
        or commit.transaction.transactionId ~= commit.canonicalTransactionId
        or transactionCanonicalHash(commit.transaction) ~= commit.transactionHash
        or commit.transaction.canonicalContentHash ~= commit.transactionHash
        or canonicalCommitHash(commit) ~= commit.commitHash then
        return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_COMMIT_HASH_MISMATCH", sequence = sequence }
      end
      rows = { commit.transaction }
    elseif commit.recordClass == "LEDGER_OPERATION_COMMIT" then
      rows, rowReason = operationRecoveryRows(commit, ledgerId, sequence)
      if not rows then return { classification = "UNRECOVERABLE", reasonCode = rowReason, sequence = sequence } end
    else
      return { classification = "UNRECOVERABLE", reasonCode = "UNSUPPORTED_CANONICAL_RECORD", sequence = sequence }
    end
    for _, row in ipairs(rows) do
      local id = row.transactionId
      if transactionIndex[id] then return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_TRANSACTION_ID_CONFLICT", transactionId = id } end
      transactionIndex[id] = key
      local existing = ledger.transactions and ledger.transactions[id]
      if not existing then return { classification = "INCOMPLETE_PROJECTION", reasonCode = "CANONICAL_TRANSACTION_PROJECTION_MISSING", transactionId = id } end
      if transactionCanonicalHash(existing) ~= transactionCanonicalHash(row) then
        return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_TRANSACTION_PROJECTION_CONFLICT", transactionId = id }
      end
      if canonical.transactionIndex[id] ~= key then
        return { classification = "INDEX_MISMATCH", reasonCode = "CANONICAL_TRANSACTION_INDEX_MISMATCH", transactionId = id }
      end
    end
    if canonical.positions[key] ~= commit.commitHash then
      return { classification = "INDEX_MISMATCH", reasonCode = "CANONICAL_POSITION_INDEX_MISMATCH", sequence = sequence }
    end
    expectedRoot = commit.commitHash
  end
  for key, commit in pairs(canonical.commits) do
    local sequence = type(commit) == "table" and tonumber(commit.sequence) or nil
    if type(key) ~= "string" or not epoch or key ~= positionKey(epoch, sequence or -1)
      or not sequence or sequence < 1 or sequence >= nextSeq then
      return { classification = "UNRECOVERABLE", reasonCode = "CANONICAL_POSITION_CONFLICT" }
    end
  end
  if expectedRoot ~= nil and canonical.rootHash ~= expectedRoot then
    return { classification = "WRONG_ROOT", reasonCode = "CANONICAL_ROOT_MISMATCH" }
  end
  return { classification = "VALID", reasonCode = "VALID_CANONICAL_HISTORY", ledgerId = ledgerId,
    epoch = epoch, nextSeq = nextSeq, rootHash = canonical.rootHash }
end

function Ledger.RebuildLedgerProjections(targetLedgerId)
  local ledgerId = targetLedgerId or Ledger.GetActiveLedgerId()
  local db = Dibs.GetDB and Dibs.GetDB()
  local ledger = db and db.ledgers and db.ledgers[ledgerId]
  if not ledger and ledgerId == "guild-primary" then ledger = db and db.ledger end
  if type(ledger) ~= "table" then return { rebuilt = false, reasonCode = "LEDGER_NOT_FOUND" } end

  local canonical = ledger.canonical
  if type(canonical) ~= "table" or canonical.schema ~= CANONICAL_SCHEMA or type(canonical.commits) ~= "table" then
    return { rebuilt = false, reasonCode = "CANONICAL_STATE_MISSING" }
  end
  local epoch, nextSeq = tonumber(canonical.epoch), tonumber(canonical.nextSeq)
  local hasCommits = next(canonical.commits) ~= nil
  if not finiteInteger(nextSeq) or nextSeq < 1
    or (hasCommits and (not finiteInteger(epoch) or epoch < 1))
    or (not hasCommits and epoch ~= nil and (not finiteInteger(epoch) or epoch < 1)) then
    return { rebuilt = false, reasonCode = "INVALID_CANONICAL_STATE" }
  end

  local startingRoot = nil
  local authorityState = authority()
  if epoch and authorityState and authorityState.state == "ACTIVE" and authorityState.ledgerEpoch == epoch then
    startingRoot = authorityRoot(authorityState)
  end
  local transactionRows, orderedTransactions, positions, transactionIndex = {}, {}, {}, {}
  local expectedRoot = startingRoot
  local commitCount = 0
  for sequence = 1, nextSeq - 1 do
    if not epoch then return { rebuilt = false, reasonCode = "CANONICAL_EPOCH_MISSING", sequence = sequence } end
    local key = positionKey(epoch, sequence)
    local commit = canonical.commits[key]
    if type(commit) ~= "table" then
      return { rebuilt = false, reasonCode = "CANONICAL_SEQUENCE_GAP", sequence = sequence }
    end
    local operationRows
    if commit.recordClass == "LEDGER_OPERATION_COMMIT" then
      if commit.schema ~= CANONICAL_SCHEMA or commit.guildKey ~= Dibs.GetGuildKey()
        or commit.ledgerId ~= ledgerId or commit.ledgerEpoch ~= epoch or commit.sequence ~= sequence then
        return { rebuilt = false, reasonCode = "CANONICAL_SCOPE_MISMATCH", sequence = sequence }
      end
      local operationReason
      operationRows, operationReason = operationRecoveryRows(commit, ledgerId, sequence)
      if not operationRows then return { rebuilt = false, reasonCode = operationReason or "INVALID_OPERATION_COMMIT", sequence = sequence } end
    elseif commit.recordClass == "AWARD_COMMIT" then
      if commit.schema ~= CANONICAL_SCHEMA or commit.protocolMajor ~= 2
      or commit.guildKey ~= Dibs.GetGuildKey() or (commit.ledgerId or "guild-primary") ~= ledgerId
      or commit.ledgerEpoch ~= epoch or commit.sequence ~= sequence then
        return { rebuilt = false, reasonCode = "CANONICAL_SCOPE_MISMATCH", sequence = sequence }
      end
      if expectedRoot ~= nil and commit.previousHash ~= expectedRoot then
        return { rebuilt = false, reasonCode = "CANONICAL_PREVIOUS_HASH_MISMATCH", sequence = sequence }
      end
      if expectedRoot == nil then expectedRoot = commit.previousHash end
      local transaction = commit.transaction
      if type(transaction) ~= "table" or transaction.transactionId ~= commit.canonicalTransactionId
        or transaction.canonicalContentHash ~= commit.transactionHash
        or transactionCanonicalHash(transaction) ~= commit.transactionHash then
        return { rebuilt = false, reasonCode = "CANONICAL_TRANSACTION_HASH_MISMATCH", sequence = sequence }
      end
      local valid, validationReason = Ledger.ValidateTransaction(transaction)
      if not valid then return { rebuilt = false, reasonCode = validationReason or "INVALID_CANONICAL_TRANSACTION", sequence = sequence } end
      local expectedCommitHash = canonicalCommitHash(commit)
      if not expectedCommitHash or expectedCommitHash ~= commit.commitHash then
        return { rebuilt = false, reasonCode = "CANONICAL_COMMIT_HASH_MISMATCH", sequence = sequence }
      end
      operationRows = { transaction }
    else
      return { rebuilt = false, reasonCode = "UNSUPPORTED_CANONICAL_RECORD", sequence = sequence }
    end
    if expectedRoot ~= nil and commit.previousHash ~= expectedRoot then
      return { rebuilt = false, reasonCode = "CANONICAL_PREVIOUS_HASH_MISMATCH", sequence = sequence }
    end
    if expectedRoot == nil then expectedRoot = commit.previousHash end
    for _, transaction in ipairs(operationRows) do
      local transactionId = transaction.transactionId
      if transactionRows[transactionId] then
        return { rebuilt = false, reasonCode = "CANONICAL_TRANSACTION_ID_CONFLICT", transactionId = transactionId }
      end
      local existing = ledger.transactions and ledger.transactions[transactionId]
      if existing and transactionCanonicalHash(existing) ~= transactionCanonicalHash(transaction) then
        return { rebuilt = false, reasonCode = "CANONICAL_TRANSACTION_PROJECTION_CONFLICT", transactionId = transactionId }
      end
      transactionRows[transactionId] = copy(transaction)
      orderedTransactions[#orderedTransactions + 1] = transactionRows[transactionId]
      transactionIndex[transactionId] = key
    end
    positions[key] = commit.commitHash
    expectedRoot, commitCount = commit.commitHash, commitCount + 1
  end

  -- Extra or misplaced records are not safe to reinterpret as a valid chain.
  for key, commit in pairs(canonical.commits) do
    local sequence = type(commit) == "table" and tonumber(commit.sequence) or nil
    if type(key) ~= "string" or type(commit) ~= "table"
      or not epoch or key ~= positionKey(epoch, sequence or -1) or commit.ledgerEpoch ~= epoch
      or not sequence or sequence < 1 or sequence >= nextSeq then
      return { rebuilt = false, reasonCode = "CANONICAL_POSITION_CONFLICT" }
    end
  end
  if expectedRoot ~= nil and canonical.rootHash ~= expectedRoot then
    return { rebuilt = false, reasonCode = "CANONICAL_ROOT_MISMATCH" }
  end
  if commitCount == 0 and startingRoot ~= nil and canonical.rootHash ~= startingRoot then
    return { rebuilt = false, reasonCode = "CANONICAL_ROOT_MISMATCH" }
  end

  local legacyRowCount, legacyRows = 0, {}
  for transactionId, transaction in pairs(ledger.transactions or {}) do
    if transactionRows[transactionId] == nil then
      if type(transaction) ~= "table" or transaction.transactionId ~= transactionId then
        return { rebuilt = false, reasonCode = "LEGACY_TRANSACTION_ID_MISMATCH", transactionId = transactionId }
      end
      local valid, validationReason = Ledger.ValidateTransaction(transaction)
      if not valid then
        return { rebuilt = false, reasonCode = validationReason or "INVALID_LEGACY_TRANSACTION", transactionId = transactionId }
      end
      legacyRows[#legacyRows + 1] = { id = transactionId, value = transaction }
    end
  end
  table.sort(legacyRows, function(first, second)
    local firstTime = tonumber(first.value.createdAt or first.value.timestamp) or 0
    local secondTime = tonumber(second.value.createdAt or second.value.timestamp) or 0
    if firstTime == secondTime then return tostring(first.id) < tostring(second.id) end
    return firstTime < secondTime
  end)
  for _, row in ipairs(legacyRows) do
    transactionRows[row.id] = copy(row.value)
    orderedTransactions[#orderedTransactions + 1] = transactionRows[row.id]
    legacyRowCount = legacyRowCount + 1
  end

  local playerStates, awardTransactions, evidenceTransactions = {}, {}, {}
  local stateOrder = {}
  for _, transaction in ipairs(orderedTransactions) do
    local seasonId = transaction.seasonId
    local memberKey = transaction.accountingMemberKey or transaction.memberKey
    if type(memberKey) ~= "string" or memberKey == "" then
      return { rebuilt = false, reasonCode = "TRANSACTION_MEMBER_MISSING", transactionId = transaction.transactionId }
    end
    memberKey = seasonalAccountingKey(memberKey, seasonId)
    playerStates[seasonId] = playerStates[seasonId] or {}
    local state = playerStates[seasonId][memberKey]
    if not state then
      state = { allocation = 0, balance = 0, transactions = {} }
      playerStates[seasonId][memberKey] = state
      stateOrder[#stateOrder + 1] = state
    end
    state.transactions[#state.transactions + 1] = transaction.transactionId
    local amount = tonumber(transaction.quantityDelta or transaction.amount) or 0
    if (transaction.actionType or transaction.type) == "SEASON_ALLOCATION" then
      state.allocation = state.allocation + amount
    else
      state.balance = state.balance + amount
    end
    if transaction.awardRef then
      awardTransactions[transaction.awardRef] = transaction.transactionId
    end
    if transaction.evidenceId then
      evidenceTransactions[transaction.evidenceId] = transaction.transactionId
    end
  end
  for _, state in ipairs(stateOrder) do state.balance = state.balance + state.allocation end

  -- Commit the rebuilt projections only after journal and retained rows pass
  -- validation. The canonical records themselves remain byte-for-byte intact.
  ledger.transactions = transactionRows
  ledger.playerStates = playerStates
  ledger.canonical.positions = positions
  ledger.canonical.transactionIndex = transactionIndex
  ledger.awardTransactions = awardTransactions
  ledger.evidenceTransactions = evidenceTransactions
  if db.activeLedgerId == ledgerId or (ledgerId == "guild-primary" and not db.activeLedgerId) then db.ledger = ledger end
  Ledger.MarkTransactionsChanged(ledgerId)
  return { rebuilt = true, reasonCode = "PROJECTIONS_REBUILT", legacyRowCount = legacyRowCount,
    canonicalCommitCount = commitCount }
end

local function compatibilityContext(action, audit)
  return { action = audit and audit.action or PROTECTED_ACTION_BY_TYPE[action], actor = audit and (audit.actorName or audit.actor) or nil, debtPolicy = audit and audit.debtPolicy }
end

-- Deprecated compatibility facades. Each reaches the sole durable mutation command.
function Ledger.AppendTransaction(record, context, ledgerId) return Ledger.CommitLocalTransaction(context or compatibilityContext(nil, record), record, ledgerId) end
function Ledger.AddTransaction(record, ledgerId)
  local result = Ledger.CommitLocalTransaction(compatibilityContext(nil, record), record, ledgerId)
  return result.value, result.reasonCode
end

local function compatibilityMutation(action, playerName, amount, reason, source, seasonId, audit, ledgerId)
  local result = Ledger.CommitLocalTransaction(compatibilityContext(action, audit), {
    transactionId = audit and audit.transactionId, playerName = playerName or Dibs.GetPlayerName(), amount = amount, type = action,
    reason = reason, source = source, seasonId = seasonId, awardRef = audit and audit.awardRef, evidenceId = audit and audit.evidenceId,
    itemID = audit and audit.itemID, itemLink = audit and audit.itemLink, sourceStatus = audit and audit.sourceStatus,
    response = audit and audit.response, playerGuid = audit and audit.playerGuid, reviewRequestId = audit and audit.reviewRequestId,
    originalTransactionId = audit and audit.originalTransactionId, correctionKey = audit and audit.correctionKey,
    confirmation = audit and audit.confirmation,
  }, ledgerId)
  return result.value, result.reasonCode
end

function Ledger.Grant(playerName, amount, reason, source, seasonId, audit, ledgerId)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_GRANTED", playerName, numeric, reason or "Dib granted", source or "system", seasonId or Dibs.GetCurrentSeasonId(), audit, ledgerId)
end
function Ledger.Use(playerName, amount, reason, source, seasonId, audit, ledgerId)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_USED", playerName, -numeric, reason or "Dib consumed", source or "system", seasonId or Dibs.GetCurrentSeasonId(), audit, ledgerId)
end
function Ledger.Refund(playerName, amount, reason, source, seasonId, audit, ledgerId)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_REFUNDED", playerName, numeric, reason or "Dib refunded", source or "system", seasonId or Dibs.GetCurrentSeasonId(), audit, ledgerId)
end
local function commitCanonicalAdminAdjustment(playerName, amount, reason, source, seasonId, audit)
  local context = compatibilityContext("DIB_ADMIN_ADJUSTMENT", audit)
  local authorityState = authority()
  local coordinator, coordinatorReason = localCoordinator(authorityState, context.actor)
  if not coordinator then return { accepted = false, reasonCode = coordinatorReason } end
  local ledgerId = Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return { accepted = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  local ledger = ensureState(ledgerId)
  local canonical, canonicalReason = canonicalStateForAuthority(ledger, authorityState)
  if not canonical then return { accepted = false, reasonCode = canonicalReason } end
  local input = {
    transactionId = audit and audit.transactionId,
    type = "DIB_ADMIN_ADJUSTMENT",
    playerName = playerName or Dibs.GetPlayerName(),
    playerGuid = audit and audit.playerGuid,
    amount = amount,
    reason = reason,
    source = source,
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
    confirmation = audit and audit.confirmation,
  }
  local tx, txReason = buildDetachedTransaction(context, input)
  if not tx then return { accepted = false, reasonCode = txReason } end
  local existing = ledger.transactions[tx.transactionId]
  if existing then
    local key = canonical.transactionIndex[tx.transactionId]
    local known = key and canonical.commits[key]
    if known and existing.canonicalContentHash == tx.canonicalContentHash then
      return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(known) }
    end
    return { accepted = false, reasonCode = "TRANSACTION_CONFLICT" }
  end
  local commit = {
    schema = CANONICAL_SCHEMA, recordClass = "AWARD_COMMIT", guildKey = Dibs.GetGuildKey(), protocolMajor = 2,
    ledgerEpoch = authorityState.ledgerEpoch, sequence = canonical.nextSeq, previousHash = canonical.rootHash,
    canonicalTransactionId = tx.transactionId, transactionHash = tx.canonicalContentHash, transaction = tx,
    coordinator = { memberKey = coordinator.memberKey, displayName = coordinator.displayName, guidWitness = coordinator.guidWitness },
  }
  if ledgerId ~= "guild-primary" then commit.ledgerId = ledgerId end
  local commitHash, hashReason = canonicalCommitHash(commit)
  if not commitHash then return { accepted = false, reasonCode = hashReason } end
  commit.commitHash = commitHash
  appendValidated(tx, ledgerId)
  local key = positionKey(commit.ledgerEpoch, commit.sequence)
  canonical.commits[key], canonical.positions[key], canonical.transactionIndex[tx.transactionId] = copy(commit), commit.commitHash, key
  canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
  if Dibs.Sync and Dibs.Sync.AnnounceAwardCommit then Dibs.Sync.AnnounceAwardCommit(copy(commit)) end
  return { accepted = true, reasonCode = "CANONICAL_COMMITTED", value = copy(tx) }
end
---@doc.id ledger.adjust.reason
---@doc.category ledger
---@doc.since 0.6.5
---@doc.audience officer,gm
---@doc.permission ledger.adjust
---@doc.scope guild-season
---@doc.audit true
---@doc.reason-required true
---@doc.help-key UI_HELP_REASON
---@doc.label-key DOC_ADJUSTMENT_REASON_LABEL
function Ledger.AdminAdjust(playerName, amount, reason, source, seasonId, audit)
  local numeric = tonumber(amount); if not finiteInteger(numeric) or numeric == 0 then return nil, "INVALID_AMOUNT" end
  if source == "MANUAL_ADMIN" and v2Enforced() then
    local result = commitCanonicalAdminAdjustment(playerName, numeric, reason, source, seasonId, audit)
    return result.value, result.reasonCode
  end
  return compatibilityMutation("DIB_ADMIN_ADJUSTMENT", playerName, numeric, reason or "Manual adjustment", source or "officer", seasonId or Dibs.GetCurrentSeasonId(), audit)
end
function Ledger.RecordHistoricalAward(playerName, seasonId, awardRef, evidenceId, reason, audit)
  audit = copy(audit or {}); audit.awardRef, audit.evidenceId = awardRef, evidenceId
  if v2Enforced() then
    audit.playerName, audit.seasonId = playerName, seasonId
    audit.amount, audit.reason = 1, reason or "Historical RCLootCouncil award"
    audit.source = "rclootcouncil_history"
    local context = { actor = Dibs.GetPlayerName(), action = "ledger.use" }
    local matchingProposal
    for _, proposal in ipairs(Dibs.Governance and Dibs.Governance.GetAwardProposals and Dibs.Governance.GetAwardProposals() or {}) do
      if proposal.status == "PENDING_RECONCILIATION" and proposal.type == "DIB_USED"
        and proposal.awardRef == awardRef and proposal.evidenceId == evidenceId then
        if matchingProposal then return nil, "MULTIPLE_MATCHING_PROPOSALS" end
        matchingProposal = proposal
      end
    end
    local result
    if matchingProposal then
      result = Ledger.CommitAwardProposal(context, matchingProposal.proposalId, audit)
    else
      result = Ledger.CommitDibUse(context, audit)
    end
    if result.accepted then return result.value, result.reasonCode end
    return nil, result.reasonCode, result.proposal
  end
  return Ledger.Use(playerName, 1, reason or "Historical RCLootCouncil award", "rclootcouncil_history", seasonId, audit)
end
function Ledger.RegisterSeasonAllocation(playerName, seasonId, amount, reason, audit)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  local context = audit and compatibilityContext("rank.reconcile", audit) or { systemBootstrap = true }
  local result = Ledger.CommitSeasonAllocation(context, {
    playerName = playerName or Dibs.GetPlayerName(), amount = numeric,
    reason = reason or "Season allocation", source = audit and (audit.source or "rank_reconciliation") or "system", seasonId = seasonId or Dibs.GetCurrentSeasonId(),
    transactionId = audit and audit.transactionId, rankIndex = audit and audit.rankIndex, rankName = audit and audit.rankName,
    expectedAllocation = audit and audit.expectedAllocation, reconciliation = audit and audit.reconciliation,
  })
  return result.value, result.reasonCode, result
end

-- B06 canonical command mirroring CommitDibUse for automatic/manual season-allocation grants.
function Ledger.CommitSeasonAllocation(context, evidence)
  local input = copy(evidence or {}); input.type, input.actionType = "SEASON_ALLOCATION", "SEASON_ALLOCATION"
  local ledgerId = (context and context.ledgerId) or input.ledgerId or Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return { accepted = false, idempotentReplay = false, reasonCode = "LEDGER_NOT_APPROVED" } end
  input.ledgerId = ledgerId
  input.amount = math.abs(tonumber(input.amount) or 1)
  if input.reconciliation then
    if not v2Enforced() then return { accepted = false, idempotentReplay = false, reasonCode = "V2_ENFORCED_REQUIRED" } end
    local valid, validationReason = validateRankReconciliation(input.reconciliation, input.playerName, input.amount)
    if not valid then return { accepted = false, idempotentReplay = false, reasonCode = validationReason } end
  end
  if not v2Enforced() then return Ledger.CommitLocalTransaction(context, input, ledgerId) end
  local authorityState = authority(); local coordinator, coordinatorReason = localCoordinator(authorityState, context and context.actor)
  if not coordinator then return { accepted = false, idempotentReplay = false, reasonCode = coordinatorReason, proposal = proposalFor(context, input) } end
  local ledger = ensureState(ledgerId); local canonical, canonicalReason = canonicalStateForAuthority(ledger, authorityState)
  if not canonical then return { accepted = false, idempotentReplay = false, reasonCode = canonicalReason } end
  if input.reconciliation then
    input.transactionId = "rank-reconcile-" .. tostring(authorityState.ledgerEpoch) .. "-" .. tostring(input.reconciliation.operationKey)
    input.reconciliation = copy(input.reconciliation)
    input.reconciliation.proposalId = input.proposalId
  end
  input.seasonId = input.seasonId or Dibs.GetCurrentSeasonId()
  if context and context.systemBootstrap == true then
    local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(input.playerName) or normalizeLegacyPlayerKey(input.playerName)
    local state = ledger.playerStates[input.seasonId] and ledger.playerStates[input.seasonId][memberKey]
    if state and (tonumber(state.allocation) or 0) ~= 0 then
      return { accepted = false, idempotentReplay = false, reasonCode = "SEASON_ALLOCATION_EXISTS" }
    end
  end
  local tx, txReason = buildDetachedTransaction({ action = (context and context.action) or (input.reconciliation and "rank.reconcile") or "ledger.adjust", actor = coordinator.displayName, b06Canonical = true, ledgerId = ledgerId }, input)
  if not tx then return { accepted = false, idempotentReplay = false, reasonCode = txReason } end
  local existing = ledger.transactions[tx.transactionId]
  if existing then
    local key = canonical.transactionIndex[tx.transactionId]; local known = key and canonical.commits[key]
    if known and existing.canonicalContentHash == tx.canonicalContentHash then return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(known) } end
    return { accepted = false, idempotentReplay = false, reasonCode = "TRANSACTION_CONFLICT" }
  end
  local commit = { schema = CANONICAL_SCHEMA, recordClass = "AWARD_COMMIT", guildKey = Dibs.GetGuildKey(), protocolMajor = 2,
    ledgerEpoch = authorityState.ledgerEpoch, sequence = canonical.nextSeq, previousHash = canonical.rootHash,
    canonicalTransactionId = tx.transactionId, transactionHash = tx.canonicalContentHash, transaction = tx,
    coordinator = { memberKey = coordinator.memberKey, displayName = coordinator.displayName, guidWitness = coordinator.guidWitness }, proposalId = input.proposalId }
  if ledgerId ~= "guild-primary" then commit.ledgerId = ledgerId end
  local commitHash, hashReason = canonicalCommitHash(commit); if not commitHash then return { accepted = false, idempotentReplay = false, reasonCode = hashReason } end
  commit.commitHash = commitHash
  appendValidated(tx, ledgerId)
  local key = positionKey(commit.ledgerEpoch, commit.sequence)
  canonical.commits[key], canonical.positions[key], canonical.transactionIndex[tx.transactionId] = copy(commit), commit.commitHash, key
  canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
  if Dibs.Sync and Dibs.Sync.AnnounceAwardCommit then Dibs.Sync.AnnounceAwardCommit(copy(commit)) end
  return { accepted = true, idempotentReplay = false, reasonCode = "CANONICAL_COMMITTED", value = copy(commit) }
end

---@doc.id ledger.balance
---@doc.category ledger
---@doc.since 0.6.0
---@doc.audience player,officer,gm
---@doc.scope guild-season
---@doc.audit false
---@doc.help-key UI_HELP_DIB_BALANCE
---@doc.label-key DOC_LEDGER_BALANCE_LABEL
function Ledger.PrepareSeasonAllocationBatch(seasonId, rows, operationId, actor, reason, expectedRevision, mode)
  if not v2Enforced() then return nil, "V2_ENFORCED_REQUIRED" end
  local authorityState = authority()
  local coordinator, coordinatorReason = localCoordinator(authorityState, actor)
  if not coordinator then return nil, coordinatorReason end
  local ledgerId = Ledger.GetActiveLedgerId()
  if not isApprovedLedger(ledgerId) then return nil, "LEDGER_NOT_APPROVED" end
  local authorization, authorizationReason = authorize({ action = mode == "DRIFT" and "season.reconcile"
    or "season.activate", actor = actor }, "SEASON_ALLOCATION")
  if not authorization then return nil, authorizationReason end
  if type(rows) ~= "table" or #rows > 1000 or type(operationId) ~= "string" or #operationId < 1 or #operationId > 96
    or not trim(reason) or #reason > 500 or not validateSeason(seasonId)
    or (mode ~= "INITIALIZE" and mode ~= "DRIFT") then return nil, "INVALID_ALLOCATION_BATCH" end
  local db = Dibs.GetDB()
  local live = db.ledgers and db.ledgers[ledgerId] or db.ledger
  if type(live) ~= "table" or type(live.transactions) ~= "table" or type(live.playerStates) ~= "table"
    or type(live.canonical) ~= "table" then return nil, "LEDGER_UNAVAILABLE" end
  if Ledger.GetDataRevision(ledgerId) ~= expectedRevision then return nil, "STALE_LEDGER_REVISION" end
  if mode == "INITIALIZE" and next(live.playerStates[seasonId] or {}) then return nil, "SEASON_ALLOCATION_EXISTS" end
  local staged = copy(live)
  local canonical, canonicalReason = canonicalStateForAuthority(staged, authorityState)
  if not canonical then return nil, canonicalReason end
  local commits, seen = {}, {}
  staged.playerStates[seasonId] = staged.playerStates[seasonId] or {}
  for index, row in ipairs(rows) do
    if type(row) ~= "table" or type(row.characterKey) ~= "string" or seen[row.characterKey]
      or not finiteInteger(row.allocation) or row.allocation < 0 or row.allocation > 100000 then
      return nil, "INVALID_ALLOCATION_ROW"
    end
    seen[row.characterKey] = true
    local stateKey = seasonalAccountingKey(row.characterKey, seasonId)
    local state = staged.playerStates[seasonId][stateKey]
      or { allocation = 0, balance = 0, transactions = {} }
    local before = tonumber(state.allocation) or 0
    local amount = row.allocation - before
    if amount ~= 0 then
      local reconciliation = { schema = 1, kind = mode == "DRIFT" and "SEASONAL_ALLOCATION_DRIFT" or "SEASONAL_INITIAL_ALLOCATION",
        assignedBefore = before, expectedAllocation = row.allocation, operationId = operationId,
        rankIndex = row.rankIndex, rankName = row.rankName, personGroupId = row.personGroupId }
      local transaction, transactionReason = buildDetachedTransaction({ action = mode == "DRIFT"
        and "season.reconcile" or "season.activate", actor = coordinator.displayName, b06Canonical = true }, {
        type = "SEASON_ALLOCATION", seasonId = seasonId, playerName = row.character,
        amount = amount, transactionId = "season-batch-" .. operationId .. "-" .. tostring(index),
        source = mode == "DRIFT" and "seasonal_rank_drift" or "seasonal_activation",
        reason = reason, reconciliation = reconciliation,
      })
      if not transaction then return nil, transactionReason end
      if transaction.memberKey ~= row.characterKey then return nil, "ALLOCATION_IDENTITY_MISMATCH" end
      if staged.transactions[transaction.transactionId] then return nil, "TRANSACTION_CONFLICT" end
      local commit = { schema = CANONICAL_SCHEMA, recordClass = "AWARD_COMMIT", guildKey = Dibs.GetGuildKey(),
        protocolMajor = 2, ledgerEpoch = authorityState.ledgerEpoch, sequence = canonical.nextSeq,
        previousHash = canonical.rootHash, canonicalTransactionId = transaction.transactionId,
        transactionHash = transaction.canonicalContentHash, transaction = transaction,
        coordinator = { memberKey = coordinator.memberKey, displayName = coordinator.displayName,
          guidWitness = coordinator.guidWitness } }
      if ledgerId ~= "guild-primary" then commit.ledgerId = ledgerId end
      commit.commitHash = canonicalCommitHash(commit)
      if not commit.commitHash then return nil, "CANONICAL_HASH_UNAVAILABLE" end
      -- Keep the rank actually reviewed by the seasonal preview, including the
      -- explicit no-guild-rank case, in the immutable transaction snapshot.
      transaction.identitySnapshot.rankIndex, transaction.identitySnapshot.rankName = row.rankIndex, row.rankName
      transaction.canonicalContentHash = transactionCanonicalHash(transaction)
      commit.transactionHash = transaction.canonicalContentHash
      commit.commitHash = canonicalCommitHash(commit)
      if not transaction.canonicalContentHash or not commit.commitHash then return nil, "CANONICAL_HASH_UNAVAILABLE" end
      staged.transactions[transaction.transactionId] = transaction
      state.transactions[#state.transactions + 1] = transaction.transactionId
      state.allocation, state.balance = row.allocation, (tonumber(state.balance) or before) + amount
      local key = positionKey(commit.ledgerEpoch, commit.sequence)
      canonical.commits[key], canonical.positions[key], canonical.transactionIndex[transaction.transactionId]
        = copy(commit), commit.commitHash, key
      canonical.nextSeq, canonical.rootHash = canonical.nextSeq + 1, commit.commitHash
      commits[#commits + 1] = commit
    end
    staged.playerStates[seasonId][stateKey] = state
  end
  return { ledger = staged, ledgerId = ledgerId, expectedRevision = expectedRevision,
    originalLedger = live, authorityEpoch = authorityState.ledgerEpoch,
    coordinatorKey = coordinator.memberKey, commits = commits }
end

function Ledger.ValidateSeasonAllocationBatch(batch, actor)
  if type(batch) ~= "table" or not v2Enforced() then return false, "INVALID_ALLOCATION_BATCH" end
  local currentAuthority = authority()
  local coordinator, reason = localCoordinator(currentAuthority, actor)
  if not coordinator then return false, reason end
  local db = Dibs.GetDB()
  if currentAuthority.ledgerEpoch ~= batch.authorityEpoch or coordinator.memberKey ~= batch.coordinatorKey
    or Ledger.GetActiveLedgerId() ~= batch.ledgerId then return false, "AUTHORITY_CHANGED" end
  if not db.ledgers or db.ledgers[batch.ledgerId] ~= batch.originalLedger
    or Ledger.GetDataRevision(batch.ledgerId) ~= batch.expectedRevision then return false, "STALE_LEDGER_REVISION" end
  return true
end

-- Publish only after the owning service has atomically installed the detached
-- guild bucket. Delivery failure cannot undo a committed canonical operation.
function Ledger.NotifySeasonAllocationBatch(batch)
  Ledger.MarkTransactionsChanged(batch.ledgerId)
  for _, commit in ipairs(batch.commits or {}) do
    if Dibs.SyncV2 and Dibs.SyncV2.BroadcastAwardCommit then
      pcall(Dibs.SyncV2.BroadcastAwardCommit, commit)
    end
  end
end

function Ledger.GetBalance(playerName, seasonId, ledgerId)
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  return getCurrentBalance(memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName()), seasonId or Dibs.GetCurrentSeasonId(), ledgerId)
end
function Ledger.GetPendingDibReservations(playerName, seasonId, ledgerId)
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local activeLedger = Ledger.GetActiveLedgerId()
  local targetLedger = ledgerId or activeLedger
  -- Pre-0.8.10 reservations carry no ledger; they belong to the guild active ledger.
  local function inLedger(entry) return (entry.ledgerId or activeLedger) == targetLedger end
  local reserved, seen = 0, {}
  local proposals = Dibs.Governance and Dibs.Governance.GetAwardProposals and Dibs.Governance.GetAwardProposals() or {}
  for _, proposal in ipairs(proposals) do
    local player = proposal.playerSnapshot
    local proposalType = proposal.type or "AWARD"
    if player and seasonalAccountingKey(player.memberKey, targetSeason) == seasonalAccountingKey(memberKey, targetSeason)
      and (proposalType == "AWARD" or proposalType == "DIB_USED")
      and proposal.status == "PENDING_RECONCILIATION" and (not proposal.seasonId or proposal.seasonId == targetSeason) then
      local proposalId = proposal.proposalId
      if not proposalId or not seen[proposalId] then
        if inLedger(proposal) then reserved = reserved + math.abs(tonumber(proposal.amount) or 1) end
        if proposalId then seen[proposalId] = true end
      end
    end
  end
  local remoteReservations = Dibs.Sync and Dibs.Sync.GetPendingAwardReservations
    and Dibs.Sync.GetPendingAwardReservations() or {}
  for _, reservation in ipairs(remoteReservations) do
    if seasonalAccountingKey(reservation.playerMemberKey, targetSeason) == seasonalAccountingKey(memberKey, targetSeason)
      and (not reservation.seasonId or reservation.seasonId == targetSeason)
      and not seen[reservation.proposalId] then
      if inLedger(reservation) then reserved = reserved + math.abs(tonumber(reservation.amount) or 1) end
      seen[reservation.proposalId] = true
    end
  end
  return reserved
end
function Ledger.GetAvailableBalance(playerName, seasonId, ledgerId)
  return math.max(0, Ledger.GetBalance(playerName, seasonId, ledgerId) - Ledger.GetPendingDibReservations(playerName, seasonId, ledgerId))
end
function Ledger.GetPlayerState(playerName, seasonId, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  memberKey = seasonalAccountingKey(memberKey, targetSeason)
  local ledger = ensureState(ledgerId); local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  if not state then return { allocation = 0, balance = 0, transactions = {} } end
  local result = copy(state); result.balance = getCurrentBalance(memberKey, targetSeason, ledgerId); return result
end
function Ledger.GetPlayerAllocation(playerName, seasonId, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  memberKey = seasonalAccountingKey(memberKey, targetSeason)
  local ledger = ensureState(ledgerId)
  local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  return tonumber(state and state.allocation) or 0
end

-- Read a roster's assigned allocations with one ledger resolution. The result
-- contains only compact numeric values and is keyed by canonical member ID.
function Ledger.GetPlayerAllocations(members, seasonId, ledgerId, dbOverride)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local ledger = ensureState(ledgerId, nil, dbOverride)
  local states = ledger.playerStates[targetSeason] or {}
  local allocations = {}
  for _, member in ipairs(type(members) == "table" and members or {}) do
    local playerName = type(member) == "table"
      and (member.playerName or member.name or member.displayName) or member
    local memberKey = type(member) == "table" and member.memberKey or nil
    memberKey = memberKey or (Dibs.Identity and Dibs.Identity.CanonicalMemberKey
      and Dibs.Identity.CanonicalMemberKey(playerName))
    memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
    allocations[memberKey] = tonumber(states[memberKey] and states[memberKey].allocation) or 0
  end
  return allocations
end
function Ledger.GetTransactionForAward(awardRef, ledgerId)
  local ledger = ensureState(ledgerId); local id = awardRef and ledger.awardTransactions[tostring(awardRef)]
  return id and copy(ledger.transactions[id]) or nil
end
function Ledger.GetTransactionForEvidence(evidenceId, ledgerId)
  local ledger = ensureState(ledgerId); local id = evidenceId and ledger.evidenceTransactions[tostring(evidenceId)]
  return id and copy(ledger.transactions[id]) or nil
end
local function sortTransactions(list)
  table.sort(list, function(a, b)
    local first, second = a.createdAt or a.timestamp or 0, b.createdAt or b.timestamp or 0
    return first == second and tostring(a.transactionId) < tostring(b.transactionId) or first < second
  end)
end
local function getPlayerHistoryIndex(playerName, seasonId, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  local ledger = ensureState(ledgerId)
  local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  local key = table.concat({ tostring(ledger.id or ""), tostring(targetSeason or ""), memberKey }, "|")
  local revision = state and playerStateProjectionRevisions[state] or 0
  local ledgerRevision = ledgerDataRevisions[ledger.id] or 0
  local cached = playerHistoryIndexes[key]
  if cached and cached.state == state and cached.revision == revision
    and cached.ledgerRevision == ledgerRevision then return cached, ledger end

  local ids, used = {}, 0
  local allocation = tonumber(state and state.allocation) or 0
  local balance = allocation
  for _, id in ipairs(state and state.transactions or {}) do
    local transaction = ledger.transactions[id]
    if transaction then
      ids[#ids + 1] = id
      local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
      if transaction.type ~= "SEASON_ALLOCATION" then balance = balance + amount end
      if transaction.type == "DIB_USED" then
        used = used + math.max(0, -amount)
      elseif transaction.type == "DIB_REFUNDED" then
        used = math.max(0, used - math.max(0, amount))
      end
    end
  end
  table.sort(ids, function(firstId, secondId)
    local first, second = ledger.transactions[firstId], ledger.transactions[secondId]
    local firstTime = first and (first.createdAt or first.timestamp) or 0
    local secondTime = second and (second.createdAt or second.timestamp) or 0
    return firstTime == secondTime and tostring(firstId) < tostring(secondId) or firstTime < secondTime
  end)
  cached = { state = state, revision = revision, ledgerRevision = ledgerRevision, ids = ids, used = used,
    balance = balance, allocation = allocation }
  if not playerHistoryIndexes[key] then
    playerHistoryIndexOrder[#playerHistoryIndexOrder + 1] = key
    if #playerHistoryIndexOrder > MAX_PLAYER_HISTORY_INDEXES then
      local expired = table.remove(playerHistoryIndexOrder, 1)
      playerHistoryIndexes[expired] = nil
    end
  end
  playerHistoryIndexes[key] = cached
  return cached, ledger
end

local function playerHistorySummaryForLedger(ledger, playerName, memberKey, targetSeason)
  memberKey = memberKey or (Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(playerName))
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  local key = table.concat({ tostring(ledger.id or ""), tostring(targetSeason or ""), memberKey }, "|")
  local revision = state and playerStateProjectionRevisions[state] or 0
  local ledgerRevision = ledgerDataRevisions[ledger.id] or 0
  local cached = playerHistorySummaries[key]
  if cached and cached.state == state and cached.revision == revision
    and cached.ledgerRevision == ledgerRevision then
    return { count = cached.count, seasonUsed = cached.seasonUsed,
      balance = cached.balance, allocation = cached.allocation }
  end

  local count, used = 0, 0
  local allocation = tonumber(state and state.allocation) or 0
  local balance = allocation
  for _, id in ipairs(state and state.transactions or {}) do
    local transaction = ledger.transactions[id]
    if transaction then
      count = count + 1
      local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
      if transaction.type ~= "SEASON_ALLOCATION" then balance = balance + amount end
      if transaction.type == "DIB_USED" then
        used = used + math.max(0, -amount)
      elseif transaction.type == "DIB_REFUNDED" then
        used = math.max(0, used - math.max(0, amount))
      end
    end
  end
  cached = { state = state, revision = revision, ledgerRevision = ledgerRevision,
    count = count, seasonUsed = used, balance = balance, allocation = allocation }
  if not playerHistorySummaries[key] then
    playerHistorySummaryOrder[#playerHistorySummaryOrder + 1] = key
    if #playerHistorySummaryOrder > MAX_PLAYER_HISTORY_SUMMARIES then
      local expired = table.remove(playerHistorySummaryOrder, 1)
      playerHistorySummaries[expired] = nil
    end
  end
  playerHistorySummaries[key] = cached
  return { count = count, seasonUsed = used, balance = balance, allocation = allocation }
end

function Ledger.GetPlayerHistorySummary(playerName, seasonId, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local ledger = ensureState(ledgerId)
  return playerHistorySummaryForLedger(ledger, playerName, nil, targetSeason)
end

-- Resolve/normalize the ledger once when a page needs balances for several
-- visible roster rows. Preserve the same per-player summary cache and values.
function Ledger.GetPlayerHistorySummaries(players, seasonId, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local ledger = ensureState(ledgerId)
  local summaries = {}
  for index, player in ipairs(type(players) == "table" and players or {}) do
    local playerName = type(player) == "table"
      and (player.playerName or player.name or player.displayName) or player
    local memberKey = type(player) == "table" and player.memberKey or nil
    if type(playerName) == "string" and playerName ~= "" then
      summaries[index] = playerHistorySummaryForLedger(ledger, playerName, memberKey, targetSeason)
    else
      summaries[index] = { count = 0, seasonUsed = 0, balance = 0, allocation = 0 }
    end
  end
  return summaries
end

function Ledger.GetHistoryPage(playerName, seasonId, ledgerId, page, pageSize)
  local index, ledger = getPlayerHistoryIndex(playerName, seasonId, ledgerId)
  local requestedSize = tonumber(pageSize)
  if not finiteInteger(requestedSize) or requestedSize < 1 then requestedSize = 20 end
  local size = math.min(50, requestedSize)
  local total = #index.ids
  local pages = math.max(1, math.ceil(total / size))
  local requestedPage = tonumber(page)
  if not finiteInteger(requestedPage) or requestedPage < 1 then requestedPage = 1 end
  local currentPage = math.min(pages, requestedPage)
  local first = (currentPage - 1) * size + 1
  local rows = {}
  for position = first, math.min(total, first + size - 1) do
    local transaction = ledger.transactions[index.ids[position]]
    if transaction then rows[#rows + 1] = copy(transaction) end
  end
  return rows, total, currentPage
end

-- Return only fields used by the Player report transaction dropdown. This
-- avoids deep-copying transaction context, actor snapshots, and reconciliation
-- details for entries that are displayed as short choices.
local function copyRecentHistoryChoices(rows)
  local result = {}
  for index, row in ipairs(rows or {}) do
    local rowCopy = {}
    for key, value in pairs(row) do rowCopy[key] = value end
    result[index] = rowCopy
  end
  return result
end

function Ledger.GetRecentHistoryChoices(playerName, seasonId, ledgerId, pageSize)
  local totalStartedAt = beginLedgerUITiming()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local identityStartedAt = beginLedgerUITiming()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  recordLedgerUITiming("recent-history-choices-identity", identityStartedAt)
  local stateStartedAt = beginLedgerUITiming()
  local ledger = ensureState(ledgerId, "recent-history-choices")
  recordLedgerUITiming("recent-history-choices-ledger-resolution", stateStartedAt)
  stateStartedAt = beginLedgerUITiming()
  local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  recordLedgerUITiming("recent-history-choices-state-lookup", stateStartedAt)
  local requestedSize = tonumber(pageSize)
  if not finiteInteger(requestedSize) or requestedSize < 1 then requestedSize = 20 end
  local size = math.min(50, requestedSize)
  local stateRevision = state and playerStateProjectionRevisions[state] or 0
  local ledgerRevision = ledgerDataRevisions[ledger.id] or 0
  local transactionList = state and state.transactions or nil
  local cached = recentHistoryChoicesCache
  if cached and cached.ledger == ledger and cached.seasonId == targetSeason
    and cached.memberKey == memberKey and cached.state == state and cached.transactions == transactionList
    and cached.stateRevision == stateRevision and cached.ledgerRevision == ledgerRevision and cached.size == size then
    local rows = copyRecentHistoryChoices(cached.rows)
    recordLedgerUITiming("recent-history-choices-cache-hit", totalStartedAt)
    return rows, cached.total
  end
  local selected, total = {}, 0
  local scanStartedAt = beginLedgerUITiming()
  local function older(first, second)
    local firstTime = tonumber(first.transaction.createdAt or first.transaction.timestamp) or 0
    local secondTime = tonumber(second.transaction.createdAt or second.transaction.timestamp) or 0
    return firstTime == secondTime and tostring(first.id) < tostring(second.id) or firstTime < secondTime
  end
  local function newerThanEntry(timestamp, id, entry)
    local existingTime = tonumber(entry.transaction.createdAt or entry.transaction.timestamp) or 0
    return timestamp == existingTime and tostring(id) > tostring(entry.id) or timestamp > existingTime
  end
  for _, id in ipairs(state and state.transactions or {}) do
    local transaction = ledger.transactions[id]
    if transaction then
      total = total + 1
      local timestamp = tonumber(transaction.createdAt or transaction.timestamp) or 0
      if #selected < size then
        local entry = { id = id, transaction = transaction }
        selected[#selected + 1] = entry
        local index = #selected
        while index > 1 do
          local parent = math.floor(index / 2)
          if not older(selected[index], selected[parent]) then break end
          selected[index], selected[parent] = selected[parent], selected[index]
          index = parent
        end
      elseif newerThanEntry(timestamp, id, selected[1]) then
        local entry = { id = id, transaction = transaction }
        selected[1] = entry
        local index = 1
        while true do
          local left, right = index * 2, index * 2 + 1
          local oldest = index
          if left <= #selected and older(selected[left], selected[oldest]) then oldest = left end
          if right <= #selected and older(selected[right], selected[oldest]) then oldest = right end
          if oldest == index then break end
          selected[index], selected[oldest] = selected[oldest], selected[index]
          index = oldest
        end
      end
    end
  end
  table.sort(selected, older)
  local rows = {}
  for _, entry in ipairs(selected) do
    local transaction = entry.transaction
    rows[#rows + 1] = {
      transactionId = transaction.transactionId,
      createdAt = transaction.createdAt,
      timestamp = transaction.timestamp,
      type = transaction.type,
      actionType = transaction.actionType,
      amount = transaction.amount,
      quantityDelta = transaction.quantityDelta,
      reason = transaction.reason,
      source = transaction.source,
      itemID = transaction.itemID,
      itemName = transaction.itemName,
      itemLink = transaction.itemLink,
    }
  end
  recentHistoryChoicesCache = {
    ledger = ledger, seasonId = targetSeason, memberKey = memberKey, state = state,
    transactions = transactionList, stateRevision = stateRevision,
    ledgerRevision = ledgerRevision, size = size, rows = copyRecentHistoryChoices(rows),
    total = total,
  }
  recordLedgerUITiming("recent-history-choices-cache-miss", totalStartedAt)
  recordLedgerUITiming("recent-history-choices-scan", scanStartedAt)
  return rows, total
end

function Ledger.MarkTransactionsChanged(ledgerId)
  local ledger = ensureState(ledgerId)
  ledgerDataRevisions[ledger.id] = (ledgerDataRevisions[ledger.id] or 0) + 1
  ledgerTransactionDiagnostics[ledger.id] = nil
  ledgerNonAllocationCounts[ledger.id] = nil
  ledgerHasNonAllocationTransactions[ledger.id] = nil
  return ledgerDataRevisions[ledger.id]
end

function Ledger.GetDataRevision(ledgerId, dbOverride)
  local ledger = ensureState(ledgerId, nil, dbOverride)
  return ledgerDataRevisions[ledger.id] or 0
end

function Ledger.GetNonAllocationTransactionCount(ledgerId)
  local ledger = ensureState(ledgerId)
  local revision = ledgerDataRevisions[ledger.id] or 0
  local cached = ledgerNonAllocationCounts[ledger.id]
  if cached and cached.revision == revision then return cached.count end
  local count = 0
  for _, transaction in pairs(ledger.transactions or {}) do
    if transaction.type ~= "SEASON_ALLOCATION" then count = count + 1 end
  end
  ledgerNonAllocationCounts[ledger.id] = { revision = revision, count = count }
  return count
end

-- Installation readiness only needs to know whether the ledger contains any
-- real (non-allocation) history. Stop at the first match instead of counting
-- every transaction on a UI render path.
function Ledger.HasNonAllocationTransactions(ledgerId, dbOverride)
  local totalStartedAt = beginLedgerUITiming()
  local stateStartedAt = beginLedgerUITiming()
  local ledger = ensureState(ledgerId, nil, dbOverride)
  recordLedgerUITiming("non-allocation-ledger-resolution", stateStartedAt)
  local revision = ledgerDataRevisions[ledger.id] or 0
  local cached = ledgerHasNonAllocationTransactions[ledger.id]
  if cached and cached.revision == revision then
    recordLedgerUITiming("non-allocation-cache-hit", totalStartedAt)
    return cached.value
  end
  local scanStartedAt = beginLedgerUITiming()
  for _, transaction in pairs(ledger.transactions or {}) do
    if transaction.type ~= "SEASON_ALLOCATION" then
      ledgerHasNonAllocationTransactions[ledger.id] = { revision = revision, value = true }
      recordLedgerUITiming("non-allocation-scan", scanStartedAt)
      recordLedgerUITiming("non-allocation-check", totalStartedAt)
      return true
    end
  end
  ledgerHasNonAllocationTransactions[ledger.id] = { revision = revision, value = false }
  recordLedgerUITiming("non-allocation-scan", scanStartedAt)
  recordLedgerUITiming("non-allocation-check", totalStartedAt)
  return false
end

function Ledger.GetTransactionDiagnostics(ledgerId)
  local ledger = ensureState(ledgerId)
  local revision = ledgerDataRevisions[ledger.id] or 0
  local cached = ledgerTransactionDiagnostics[ledger.id]
  if cached and cached.revision == revision then
    return { transactionCount = cached.transactionCount,
      nonAllocationTransactionCount = cached.nonAllocationTransactionCount,
      playersWithRankTransitions = cached.playersWithRankTransitions,
      totalPlayersInLedger = cached.totalPlayersInLedger }
  end

  local playerRanks, transactionCount, nonAllocationTransactionCount = {}, 0, 0
  for _, transaction in pairs(ledger.transactions or {}) do
    transactionCount = transactionCount + 1
    if transaction.type ~= "SEASON_ALLOCATION" then
      nonAllocationTransactionCount = nonAllocationTransactionCount + 1
    end
    local rank = tonumber(transaction.playerRankIndex or transaction.playerRank)
    if rank ~= nil then
      local player = string.lower(tostring(transaction.playerName or transaction.playerId or transaction.playerGuid or "unknown"))
      playerRanks[player] = playerRanks[player] or {}
      playerRanks[player][rank] = true
    end
  end
  local changingPlayers, totalPlayers = 0, 0
  for _, ranks in pairs(playerRanks) do
    totalPlayers = totalPlayers + 1
    local count = 0
    for _ in pairs(ranks) do count = count + 1 end
    if count > 1 then changingPlayers = changingPlayers + 1 end
  end
  cached = { revision = revision, transactionCount = transactionCount,
    nonAllocationTransactionCount = nonAllocationTransactionCount,
    playersWithRankTransitions = changingPlayers, totalPlayersInLedger = totalPlayers }
  ledgerTransactionDiagnostics[ledger.id] = cached
  return { transactionCount = transactionCount,
    nonAllocationTransactionCount = nonAllocationTransactionCount,
    playersWithRankTransitions = changingPlayers, totalPlayersInLedger = totalPlayers }
end

---@doc.id ledger.audit.history
---@doc.category ledger
---@doc.since 0.6.5
---@doc.audience player,officer,gm
---@doc.scope guild-season
---@doc.audit false
---@doc.help-key UI_HELP_AUDIT_HISTORY
---@doc.label-key DOC_AUDIT_HISTORY_LABEL
function Ledger.GetHistory(playerName, seasonId, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName); local ledger = ensureState(ledgerId); local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  local history = {}; for _, id in ipairs(state and state.transactions or {}) do if ledger.transactions[id] then table.insert(history, copy(ledger.transactions[id])) end end
  sortTransactions(history); return history
end
function Ledger.GetAllTransactions(ledgerId)
  local list = {}; for _, tx in pairs(ensureState(ledgerId).transactions) do table.insert(list, copy(tx)) end; sortTransactions(list); return list
end
function Ledger.GetTransactions(seasonId, playerGuidOrName, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = playerGuidOrName and (Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerGuidOrName) or normalizeLegacyPlayerKey(playerGuidOrName)) or nil
  local list = {}
  for _, tx in pairs(ensureState(ledgerId).transactions) do
    local matchesPlayer = not memberKey or tx.memberKey == memberKey or tx.playerKey == memberKey or normalizeLegacyPlayerKey(tx.playerName) == memberKey or tostring(tx.playerGuid or tx.playerId or "") == tostring(playerGuidOrName or "")
    if tx.seasonId == targetSeason and matchesPlayer then table.insert(list, copy(tx)) end
  end
  sortTransactions(list); return list
end

-- Build the Officer period-statistics projection directly from the ledger.
-- Unlike GetTransactions + HistoryFilters.FilterRecords, this query does not
-- deep-copy matching transactions or allocate/sort temporary record arrays.
-- The resolver may map legacy transaction names to the current guild roster;
-- only aggregate rows and scalar counts are returned.
function Ledger.GetSeasonPlayerActivity(seasonId, ledgerId, resolvePlayerName, fromTimestamp, toTimestamp, dbOverride)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local hasDateFilter = fromTimestamp ~= nil or toTimestamp ~= nil
  local rowsByPlayer, count, undatedExcluded, unmatchedPlayers = {}, 0, 0, 0
  local ledger = ensureState(ledgerId, nil, dbOverride)
  local seasonSummary = {
    transactions = 0, players = 0, granted = 0, used = 0, awards = 0,
    corrections = 0, awardCount = {}, recentTransactions = {},
  }
  local activePlayers = {}
  local function resolvePeriodPlayerName(transaction, summaryIdentity, summaryName)
    local periodIdentity = transaction.playerName or transaction.playerKey or transaction.memberKey or transaction.playerId
    if periodIdentity == summaryIdentity then return summaryName end
    return type(resolvePlayerName) == "function" and resolvePlayerName(periodIdentity) or nil
  end
  for _, transaction in pairs(ledger.transactions) do
    if type(transaction) == "table" and transaction.seasonId == targetSeason then
      seasonSummary.transactions = seasonSummary.transactions + 1
      -- Keep the header summary's original identity rules while collecting it
      -- during this same scan as the filtered per-player rows.
      local summaryIdentity = transaction.playerName or transaction.playerKey or transaction.playerId
      local summaryName = type(resolvePlayerName) == "function" and resolvePlayerName(summaryIdentity)
      if summaryName and summaryName ~= "" then
        local summaryKey = string.lower(tostring(summaryName))
        if not activePlayers[summaryKey] then
          activePlayers[summaryKey] = true
          seasonSummary.players = seasonSummary.players + 1
        end
        local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
        if transaction.type == "DIB_GRANTED" then
          seasonSummary.granted = seasonSummary.granted + amount
        elseif transaction.type == "DIB_USED" then
          seasonSummary.used = seasonSummary.used + math.abs(amount)
          seasonSummary.awards = seasonSummary.awards + 1
          seasonSummary.awardCount[summaryKey] = (seasonSummary.awardCount[summaryKey] or 0) + 1
        elseif transaction.type == "DIB_REFUNDED" or transaction.type == "DIB_REVOKED"
          or transaction.type == "DIB_ADMIN_ADJUSTMENT" then
          seasonSummary.corrections = seasonSummary.corrections + 1
        end
      end
      local timestamp = tonumber(transaction.createdAt) or tonumber(transaction.timestamp)
      if hasDateFilter and not timestamp then
        undatedExcluded = undatedExcluded + 1
        local playerName = resolvePeriodPlayerName(transaction, summaryIdentity, summaryName)
        if playerName and playerName ~= "" then
          local key = string.lower(tostring(playerName))
          local row = rowsByPlayer[key]
          if not row then
            row = { playerName = tostring(playerName), transactions = 0, awards = 0, grantedDibs = 0,
              usedDibs = 0, corrections = 0, undatedExcluded = 0, partial = false }
            rowsByPlayer[key] = row
          end
          row.undatedExcluded = row.undatedExcluded + 1
          row.partial = true
        end
      elseif (fromTimestamp == nil or timestamp >= fromTimestamp)
        and (toTimestamp == nil or timestamp < toTimestamp) then
        count = count + 1
        local playerName = resolvePeriodPlayerName(transaction, summaryIdentity, summaryName)
        if playerName and playerName ~= "" then
          local key = string.lower(tostring(playerName))
          local row = rowsByPlayer[key]
          if not row then
            row = { playerName = tostring(playerName), transactions = 0, awards = 0, grantedDibs = 0,
              usedDibs = 0, corrections = 0, undatedExcluded = 0, partial = false }
            rowsByPlayer[key] = row
          end
          row.transactions = row.transactions + 1
          local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
          if transaction.type == "DIB_USED" then
            row.awards = row.awards + 1
            row.usedDibs = row.usedDibs + math.abs(amount)
          elseif transaction.type == "DIB_GRANTED" then
            row.grantedDibs = row.grantedDibs + amount
          elseif transaction.type == "DIB_REFUNDED" or transaction.type == "DIB_REVOKED"
            or transaction.type == "DIB_ADMIN_ADJUSTMENT" then
            row.corrections = row.corrections + 1
          end
        else
          unmatchedPlayers = unmatchedPlayers + 1
        end
      end
    end
  end
  return rowsByPlayer, count, undatedExcluded, unmatchedPlayers, seasonSummary, ledger.id
end

-- Aggregate the Officer dashboard's season metrics without deep-copying every
-- matching transaction into a temporary array. The optional resolver maps a
-- transaction identity to a current guild member name; only scalar metrics
-- and per-member award counts are retained in the result.
function Ledger.GetSeasonActivitySummary(seasonId, ledgerId, resolvePlayerName, recentLimit, dbOverride)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local ledger = ensureState(ledgerId, nil, dbOverride)
  local transactionCount, players, awardCount = 0, {}, {}
  local granted, used, awards, corrections = 0, 0, 0, 0
  local recentCount = math.max(0, math.min(20, math.floor(tonumber(recentLimit) or 0)))
  local recent = {}
  for _, transaction in pairs(ledger.transactions) do
    if transaction.seasonId == targetSeason then
      transactionCount = transactionCount + 1
      local playerName = type(resolvePlayerName) == "function"
        and resolvePlayerName(transaction.playerName or transaction.playerKey or transaction.playerId) or nil
      if playerName then
        local playerKey = string.lower(playerName)
        players[playerKey] = true
        local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
        if transaction.type == "DIB_GRANTED" then
          granted = granted + amount
        elseif transaction.type == "DIB_USED" then
          used = used + math.abs(amount)
          awards = awards + 1
          awardCount[playerKey] = (awardCount[playerKey] or 0) + 1
        elseif transaction.type == "DIB_REFUNDED" or transaction.type == "DIB_REVOKED"
          or transaction.type == "DIB_ADMIN_ADJUSTMENT" then
          corrections = corrections + 1
        end
        if recentCount > 0 then
          local timestamp = tonumber(transaction.createdAt or transaction.timestamp) or 0
          local position = #recent + 1
          for index, entry in ipairs(recent) do
            if timestamp > entry.timestamp then position = index; break end
          end
          if position <= recentCount then
            table.insert(recent, position, {
              transaction = transaction, playerName = playerName, timestamp = timestamp,
            })
            if #recent > recentCount then recent[#recent] = nil end
          end
        end
      end
    end
  end
  local playerCount = 0
  for _ in pairs(players) do playerCount = playerCount + 1 end
  local recentTransactions = {}
  for index, entry in ipairs(recent) do
    local transaction = entry.transaction
    recentTransactions[index] = {
      playerName = entry.playerName,
      playerKey = transaction.playerKey,
      playerId = transaction.playerId,
      createdAt = transaction.createdAt,
      timestamp = transaction.timestamp,
      type = transaction.type,
      actionType = transaction.actionType,
      amount = transaction.amount,
      quantityDelta = transaction.quantityDelta,
      reason = transaction.reason,
    }
  end
  return {
    transactions = transactionCount,
    players = playerCount,
    granted = granted,
    used = used,
    awards = awards,
    corrections = corrections,
    awardCount = awardCount,
    recentTransactions = recentTransactions,
  }
end

-- Dashboard activity needs only the newest few visible rows. Scan the ledger
-- without copying/sorting every transaction, then copy only the selected rows.
-- `include` is an optional presentation filter (for example, current guild
-- membership); normal history APIs keep their existing complete semantics.
function Ledger.GetRecentTransactions(seasonId, limit, ledgerId, include)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local count = math.max(1, math.min(20, math.floor(tonumber(limit) or 5)))
  local selected = {}
  for _, tx in pairs(ensureState(ledgerId).transactions) do
    if tx.seasonId == targetSeason and (type(include) ~= "function" or include(tx)) then
      local timestamp = tonumber(tx.createdAt or tx.timestamp) or 0
      local position = #selected + 1
      for index, entry in ipairs(selected) do
        local existing = tonumber(entry.createdAt or entry.timestamp) or 0
        if timestamp > existing then position = index break end
      end
      if position <= count then
        table.insert(selected, position, tx)
        if #selected > count then selected[#selected] = nil end
      end
    end
  end
  local result = {}
  for index, tx in ipairs(selected) do result[index] = copy(tx) end
  return result
end

function Ledger.GetPlayerSeasonState(seasonId, playerGuidOrName)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId(); local playerName = playerGuidOrName or Dibs.GetPlayerName(); local transactions = Ledger.GetTransactions(targetSeason, playerName)
  if type(playerName) == "string" and playerName:match("^Player%-%d+%-") and transactions[1] and transactions[1].playerName then
    playerName = transactions[1].playerName
  end
  local delta = 0; for _, tx in ipairs(transactions) do if tx.type ~= "SEASON_ALLOCATION" then delta = delta + (tonumber(tx.amount) or 0) end end
  local state = Ledger.GetPlayerState(playerName, targetSeason)
  return { seasonId = targetSeason, playerGuid = tostring(playerGuidOrName or state.playerId or playerName), playerName = playerName, currentRankIndex = 0, baseAllocation = tonumber(state.allocation) or 0, transactionDelta = delta, remainingBalance = Ledger.GetBalance(playerName, targetSeason), historySummary = { count = #transactions }, lastComputedAt = time() }
end
local function resolvePlayerDibsProjectionIdentity(playerName, targetSeason)
  local input = playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName())
  if Dibs.Identity and type(Dibs.Identity.ResolveRosterMember) == "function" then
    local resolved = Dibs.Identity.ResolveRosterMember(input)
    if not resolved or resolved.status ~= "RESOLVED" then
      return nil, { available = false, balance = nil, canonicalBalance = nil, availableBalance = nil,
        canonicalName = nil, reason = resolved and resolved.status or "IDENTITY_UNAVAILABLE", seasonId = targetSeason }
    end
    return {
      canonicalName = resolved.displayName,
      memberKey = resolved.memberKey,
      rankIndex = resolved.rankIndex,
    }
  end

  local canonicalName = Dibs.Identity and Dibs.Identity.NormalizeDisplayName
    and Dibs.Identity.NormalizeDisplayName(input) or input
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(input) or normalizeLegacyPlayerKey(canonicalName)
  if not canonicalName or tostring(canonicalName) == "" then
    return nil, { available = false, balance = nil, canonicalBalance = nil, availableBalance = nil,
      canonicalName = nil, reason = "IDENTITY_UNAVAILABLE", seasonId = targetSeason }
  end
  local rankInfo = Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo
    and Dibs.RankRules.GetPlayerRankInfo(canonicalName)
  return { canonicalName = canonicalName, memberKey = memberKey, rankIndex = rankInfo and rankInfo.rankIndex }
end

local function computePlayerDibsProjection(identity, targetSeason, ledgerId)
  local canonicalName, memberKey = identity.canonicalName, identity.memberKey
  local canonicalBalance = getCurrentBalance(memberKey, targetSeason, ledgerId)
  local pendingDibReservations = Ledger.GetPendingDibReservations(canonicalName, targetSeason, ledgerId)
  local rankMaximum
  if Dibs.RankRules and type(Dibs.RankRules.GetAllocationForRank) == "function" and identity.rankIndex ~= nil then
    local rankOk, allocation = pcall(Dibs.RankRules.GetAllocationForRank, targetSeason, identity.rankIndex)
    if rankOk then rankMaximum = tonumber(allocation) end
  elseif Dibs.RankRules and type(Dibs.RankRules.GetAllocationForPlayer) == "function" then
    local rankOk, allocation = pcall(Dibs.RankRules.GetAllocationForPlayer, canonicalName, targetSeason)
    if rankOk then rankMaximum = tonumber(allocation) end
  end
  return { available = true, balance = canonicalBalance, canonicalBalance = canonicalBalance,
    availableBalance = canonicalBalance - pendingDibReservations, pendingDibReservations = pendingDibReservations,
    rankMaximum = rankMaximum, canonicalName = canonicalName, seasonId = targetSeason }
end

local function getPlayerDibsProjection(playerName, seasonId, useCache, ledgerId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local identity, unavailable = resolvePlayerDibsProjectionIdentity(playerName, targetSeason)
  if not identity then return unavailable end
  if not identity.memberKey then
    identity.memberKey = normalizeLegacyPlayerKey(identity.canonicalName)
  end
  identity.memberKey = seasonalAccountingKey(identity.memberKey, targetSeason)

  local ledger = ensureState(ledgerId)
  local playerState = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][identity.memberKey]
  if not useCache then return computePlayerDibsProjection(identity, targetSeason, ledgerId) end

  local guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or ""
  local cacheKey = tostring(guildKey) .. "|" .. tostring(ledger.id or "") .. "|" .. tostring(targetSeason) .. "|" .. tostring(identity.memberKey)
  local identityGeneration = Dibs.Identity and Dibs.Identity.GetInvalidationGeneration
    and Dibs.Identity.GetInvalidationGeneration() or 0
  local proposalGeneration = Dibs.Governance and Dibs.Governance.GetAwardProposalGeneration
    and Dibs.Governance.GetAwardProposalGeneration(identity.memberKey) or 0
  local reservationGeneration = Dibs.Sync and Dibs.Sync.GetAwardReservationGeneration
    and Dibs.Sync.GetAwardReservationGeneration(identity.memberKey) or 0
  local rankGeneration = Dibs.RankRules and Dibs.RankRules.GetProjectionGeneration
    and Dibs.RankRules.GetProjectionGeneration(targetSeason) or 0
  local catalogRevision = Dibs.Seasons and Dibs.Seasons.GetCatalogRevision
    and Dibs.Seasons.GetCatalogRevision() or 0
  local seasonGeneration = Dibs.Seasons and Dibs.Seasons.GetCurrentSeasonGeneration
    and Dibs.Seasons.GetCurrentSeasonGeneration() or 0
  local viewerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or ""
  local viewerKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(viewerName) or tostring(viewerName)
  local defaultAllocation = Dibs.db and Dibs.db.settings and Dibs.db.settings.defaultAllocation
  local cached = playerDibsProjections[cacheKey]
  if cached and cached.playerState == playerState
    and cached.playerStateRevision == (playerState and playerStateProjectionRevisions[playerState] or 0)
    and cached.identityGeneration == identityGeneration
    and cached.proposalGeneration == proposalGeneration
    and cached.reservationGeneration == reservationGeneration
    and cached.rankGeneration == rankGeneration
    and cached.catalogRevision == catalogRevision
    and cached.seasonGeneration == seasonGeneration
    and cached.viewerKey == viewerKey
    and cached.defaultAllocation == defaultAllocation
    and cached.canonicalName == identity.canonicalName
    and cached.rankIndex == identity.rankIndex
  then
    return copyPlayerDibsProjection(cached.projection)
  end

  local projection = computePlayerDibsProjection(identity, targetSeason, ledgerId)
  rememberPlayerDibsProjection(cacheKey, {
    playerState = playerState,
    playerStateRevision = playerState and playerStateProjectionRevisions[playerState] or 0,
    identityGeneration = identityGeneration,
    proposalGeneration = proposalGeneration,
    reservationGeneration = reservationGeneration,
    rankGeneration = rankGeneration,
    catalogRevision = catalogRevision,
    seasonGeneration = seasonGeneration,
    viewerKey = viewerKey,
    defaultAllocation = defaultAllocation,
    canonicalName = identity.canonicalName,
    rankIndex = identity.rankIndex,
    projection = projection,
  })
  return copyPlayerDibsProjection(projection)
end

function Ledger.GetPlayerDibsProjection(playerName, seasonId, ledgerId)
  return getPlayerDibsProjection(playerName, seasonId, true, ledgerId)
end

function Ledger.GetCanonicalPlayerDibsState(seasonId, playerIdentity, ledgerId)
  return getPlayerDibsProjection(playerIdentity, seasonId, false, ledgerId)
end
function Ledger.CalculateCanonicalContentHash(record) return transactionCanonicalHash(record or {}) end
function Ledger.CalculateCanonicalCommitHash(record) return canonicalCommitHash(record or {}) end

return Ledger
