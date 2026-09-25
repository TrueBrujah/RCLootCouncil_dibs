--[[
Module: Dibs.Installation
Layer: Guild installation/readiness orchestration
Purpose: Derive one normalized guild installation/readiness projection and
orchestrate the GM-facing "Initialize DIBS" workflow over existing
authoritative modules (Governance, LegacyBaseline, Sync).
Non-responsibilities: It owns no authority, ledger, baseline, or protocol
state of its own; every mutation is delegated to the module that already
validates it. It never mutates db.governance/db.ledger/db.sync.v2 directly.
SavedVariables: None (fully derived; no persisted installation state).
]]

local Dibs = _G.Dibs
Dibs.Installation = Dibs.Installation or {}
local Installation = Dibs.Installation

local function localPlayer()
  return Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
end

local function actorSnapshot(actor)
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then return nil end
  local snapshot = Dibs.Identity.CreateSnapshot(actor or localPlayer())
  return snapshot
end

local function isGM(actor)
  if not Dibs.Identity or type(Dibs.Identity.IsCurrentGuildMaster) ~= "function" then return false end
  return Dibs.Identity.IsCurrentGuildMaster(actor or localPlayer()) == true
end

local function countTable(value)
  local total = 0
  for _ in pairs(value or {}) do total = total + 1 end
  return total
end

local function countFindingsOpen(findings)
  local total = 0
  for _, finding in ipairs(findings or {}) do if finding.status == "OPEN" then total = total + 1 end end
  return total
end

local function hasIncompleteSources(baselineState)
  for _, source in pairs((baselineState or {}).sources or {}) do
    if source.complete == false then return true end
  end
  return false
end

-- Real existing Dibs data, independent of whether LegacyBaseline evidence has
-- ever been collected. A guild is never "clean" merely because the evidence
-- cache is empty (see Installation_Initialization_V2_Architecture_Review.md).
-- SEASON_ALLOCATION transactions are excluded: Dibs.Initialize() creates a
-- default season and automatic rank allocations for every guild, so their
-- presence alone is not evidence of prior manual Dibs usage.
local function detectRealLegacyData()
  local ledgerCount = 0
  if Dibs.Ledger and type(Dibs.Ledger.GetAllTransactions) == "function" then
    local ok, transactions = pcall(Dibs.Ledger.GetAllTransactions)
    if ok and type(transactions) == "table" then
      for _, tx in ipairs(transactions) do
        if tx.type ~= "SEASON_ALLOCATION" then ledgerCount = ledgerCount + 1 end
      end
    end
  end
  local preDibCount = 0
  local db = Dibs.GetDB and Dibs.GetDB()
  if type(db) == "table" and type(db.preDibs) == "table" and type(db.preDibs.requests) == "table" then
    preDibCount = #db.preDibs.requests
  end
  return ledgerCount > 0 or preDibCount > 0, ledgerCount, preDibCount
end

---@param actor string|nil Optional actor override; defaults to the local player.
---@return table status Normalized installation/readiness projection.
function Installation.GetStatus(actor)
  local governance = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or { status = "POLICY_UNINITIALIZED" }
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState() or { state = "LEGACY_LOCAL" }
  local protocolActive = Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced() == true
  local baselineState = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetState and Dibs.LegacyBaseline.GetState() or { evidence = {}, sources = {} }
  local approvedBaseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline()
  local findings = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetFindings and Dibs.LegacyBaseline.GetFindings() or {}
  local evidenceCount = countTable(baselineState.evidence)
  local openFindings = countFindingsOpen(findings)
  local incompleteSources = hasIncompleteSources(baselineState)
  local hasRealLegacyData = detectRealLegacyData()
  local hasUncollectedEvidence = hasRealLegacyData and evidenceCount == 0
  local reconciliationRequired = hasUncollectedEvidence or (evidenceCount > 0 and openFindings > 0)

  local actorIsGM = isGM(actor)
  local snapshot = actorSnapshot(actor)
  local candidateDisplayName = (authority.coordinator and authority.coordinator.displayName) or (snapshot and snapshot.displayName)
  local syncBehind = Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() == true
  local compatibilityReady, compatibilityReason = true, nil
  if candidateDisplayName and Dibs.Sync and type(Dibs.Sync.CanEnforceV2) == "function" then
    compatibilityReady, compatibilityReason = Dibs.Sync.CanEnforceV2({ candidateDisplayName })
  end

  local blockers, warnings = {}, {}
  local state
  if governance.status ~= "GOVERNANCE_ADOPTED" then
    state = "NOT_INITIALIZED"
    blockers[#blockers + 1] = "GOVERNANCE_REQUIRED"
  elseif protocolActive then
    if authority.state == "COORDINATOR_UNAVAILABLE" then state = "COORDINATOR_UNAVAILABLE"
    elseif authority.state == "RECOVERY_PENDING" then state = "RECOVERY_REQUIRED"
    elseif authority.state == "HANDOFF_CLOSING" then state, blockers[#blockers + 1] = "BLOCKED", "HANDOFF_IN_PROGRESS"
    else state = "READY" end
  elseif reconciliationRequired then
    state = "RECONCILIATION_REQUIRED"
    blockers[#blockers + 1] = hasUncollectedEvidence and "LEGACY_EVIDENCE_SCAN_REQUIRED" or "LEGACY_RECONCILIATION_REQUIRED"
  elseif authority.state ~= "LEGACY_LOCAL" and authority.state ~= "ACTIVE" then
    state = "BLOCKED"
    blockers[#blockers + 1] = authority.state
  else
    state = "READY_TO_INITIALIZE"
    if incompleteSources then warnings[#warnings + 1] = "INCOMPLETE_EVIDENCE_SOURCES" end
    if not compatibilityReady then warnings[#warnings + 1] = compatibilityReason or "WRITER_COMPATIBILITY_REQUIRED" end
    if syncBehind then warnings[#warnings + 1] = "SYNC_BEHIND" end
  end
  if not actorIsGM then blockers[#blockers + 1] = "GUILD_MASTER_REQUIRED" end

  return {
    state = state,
    installType = hasRealLegacyData and "UPGRADE" or "CLEAN",
    actor = { isGM = actorIsGM, displayName = snapshot and snapshot.displayName or nil },
    governance = { ready = governance.status == "GOVERNANCE_ADOPTED" },
    legacy = {
      evidenceCount = evidenceCount,
      openFindings = openFindings,
      incompleteSources = incompleteSources,
      hasUncollectedEvidence = hasUncollectedEvidence,
      reconciliationRequired = reconciliationRequired,
    },
    baseline = {
      ready = approvedBaseline ~= nil,
      type = approvedBaseline and (evidenceCount == 0 and "GENESIS" or "RECONCILED") or nil,
    },
    coordinator = { ready = authority.state == "ACTIVE", candidate = candidateDisplayName },
    compatibility = { ready = compatibilityReady, reasonCode = (not compatibilityReady) and compatibilityReason or nil },
    sync = { ready = not syncBehind, behind = syncBehind },
    protocol = { active = protocolActive },
    blockers = blockers,
    warnings = warnings,
    technical = {
      protocolState = Dibs.Sync and Dibs.Sync.GetProtocolState and Dibs.Sync.GetProtocolState() or governance.future and governance.future.protocolState,
      authorityState = authority.state,
      ledgerEpoch = authority.ledgerEpoch,
      baselineHash = approvedBaseline and approvedBaseline.legacyBaselineHash or nil,
      coordinatorMemberKey = authority.coordinator and authority.coordinator.memberKey or nil,
    },
  }
end

function Installation.GetReconciliationView()
  local evidence = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetEvidence and Dibs.LegacyBaseline.GetEvidence() or {}
  local state = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetState and Dibs.LegacyBaseline.GetState() or { decisions = {}, activeDecisionByEvidence = {} }
  local findings = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetFindings and Dibs.LegacyBaseline.GetFindings() or {}
  local findingByEvidence = {}
  for _, finding in ipairs(findings) do
    for _, evidenceId in ipairs(finding.evidenceIds or {}) do
      findingByEvidence[evidenceId] = findingByEvidence[evidenceId] or {}
      table.insert(findingByEvidence[evidenceId], finding)
    end
  end
  local rows = {}
  for _, item in ipairs(evidence) do
    local decisionId = state.activeDecisionByEvidence and state.activeDecisionByEvidence[item.evidenceId]
    local decision = decisionId and state.decisions and state.decisions[decisionId]
    rows[#rows + 1] = {
      evidenceId = item.evidenceId,
      sourceId = item.sourceId,
      sourceType = item.sourceType,
      identity = item.identity and item.identity.original or "Unknown",
      action = item.action,
      amount = item.amount,
      seasonId = item.seasonId,
      decision = decision and decision.decision or nil,
      decisionId = decisionId,
      findings = findingByEvidence[item.evidenceId] or {},
    }
  end
  table.sort(rows, function(a, b) return tostring(a.evidenceId) < tostring(b.evidenceId) end)
  return rows
end

local function stageGovernance(actor)
  local governance = Dibs.Governance.GetState()
  if governance.status == "GOVERNANCE_ADOPTED" then return true, "ALREADY_ADOPTED" end
  local ok, reason = Dibs.Governance.AdoptInitial(actor, { reason = "INSTALLATION_WIZARD" })
  if not ok then return false, reason end
  return true, "ADOPTED"
end

-- Safe/idempotent: only imports existing local ledger/Pre-Dibs data as
-- reviewable evidence. It never approves or decides anything.
local function stageLegacyDiscovery(actor)
  local hasRealLegacyData, _, _ = detectRealLegacyData()
  local baselineState = Dibs.LegacyBaseline.GetState()
  local evidenceCount = countTable(baselineState.evidence)
  if not hasRealLegacyData or evidenceCount > 0 then return true, "NO_ACTION_REQUIRED" end
  local result, reason = Dibs.LegacyBaseline.CollectLocalEvidence(actor, "installation-wizard")
  if not result then return false, reason or "LEGACY_EVIDENCE_COLLECTION_FAILED" end
  return true, "COLLECTED"
end

local function stageBaseline(actor, options)
  local existing = Dibs.LegacyBaseline.GetBaseline()
  if existing then return true, "ALREADY_APPROVED" end
  local baselineState = Dibs.LegacyBaseline.GetState()
  local evidenceCount = countTable(baselineState.evidence)
  if evidenceCount > 0 then
    local findings = Dibs.LegacyBaseline.GetFindings()
    if countFindingsOpen(findings) > 0 then return false, "LEGACY_RECONCILIATION_REQUIRED" end
  end
  local acknowledgeIncompleteEvidence = options and options.acknowledgeIncompleteEvidence == true
  local baseline, reason = Dibs.LegacyBaseline.FinalizeBaseline(actor, { acknowledgeIncompleteEvidence = acknowledgeIncompleteEvidence })
  if not baseline then return false, reason end
  return true, "APPROVED"
end

local function stageCoordinator(actor)
  local authority = Dibs.Governance.GetAuthorityState()
  if authority.state == "ACTIVE" then return true, "ALREADY_ACTIVE" end
  if authority.state ~= "LEGACY_LOCAL" then return false, authority.state end
  local baseline = Dibs.LegacyBaseline.GetBaseline()
  if not baseline then return false, "BASELINE_REQUIRED" end
  local ok, reason = Dibs.Governance.EstablishInitialAuthority(actor, baseline.legacyBaselineHash)
  if not ok then return false, reason end
  return true, "ACTIVE"
end

local function stageCutover(actor, writers)
  if Dibs.Governance.IsV2Enforced() then return true, "ALREADY_ENFORCED" end
  local authority = Dibs.Governance.GetAuthorityState()
  if authority.state ~= "ACTIVE" then return false, "AUTHORITY_ACTIVE_REQUIRED" end
  local selectedWriters = writers or { authority.coordinator and authority.coordinator.displayName }
  local ok, reason = Dibs.Governance.EnableV2(actor, selectedWriters)
  if not ok then return false, reason end
  return true, "ENFORCED"
end

---@param actor string|nil Optional actor override; defaults to the local player.
---@param options table|nil `{ writers, acknowledgeIncompleteEvidence }`.
---@return table result `{ ok, stage?, reasonCode, status }`.
function Installation.Initialize(actor, options)
  options = type(options) == "table" and options or {}
  if not isGM(actor) then
    return { ok = false, stage = "actor", reasonCode = "GUILD_MASTER_REQUIRED", status = Installation.GetStatus(actor) }
  end
  if Installation.GetStatus(actor).protocol.active then
    return { ok = true, reasonCode = "ALREADY_INITIALIZED", status = Installation.GetStatus(actor) }
  end
  local govOk, govReason = stageGovernance(actor)
  if not govOk then return { ok = false, stage = "governance", reasonCode = govReason, status = Installation.GetStatus(actor) } end
  local discoveryOk, discoveryReason = stageLegacyDiscovery(actor)
  if not discoveryOk then return { ok = false, stage = "legacy", reasonCode = discoveryReason, status = Installation.GetStatus(actor) } end
  local baseOk, baseReason = stageBaseline(actor, options)
  if not baseOk then return { ok = false, stage = "baseline", reasonCode = baseReason, status = Installation.GetStatus(actor) } end
  local coordOk, coordReason = stageCoordinator(actor)
  if not coordOk then return { ok = false, stage = "coordinator", reasonCode = coordReason, status = Installation.GetStatus(actor) } end
  local cutoverOk, cutoverReason = stageCutover(actor, options.writers)
  if not cutoverOk then return { ok = false, stage = "cutover", reasonCode = cutoverReason, status = Installation.GetStatus(actor) } end
  return { ok = true, reasonCode = "INITIALIZED", status = Installation.GetStatus(actor) }
end

return Installation
