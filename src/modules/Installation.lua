--[[
Module: Dibs.Installation
Layer: Guild installation/readiness orchestration
Purpose: Derive one normalized guild installation/readiness projection and
orchestrate the GM-facing "Initialize DIBS" workflow over existing
authoritative modules (Governance, HistoricalBaseline, Sync).
Non-responsibilities: It owns no authority, ledger, baseline, or protocol
state of its own; every mutation is delegated to the module that already
validates it. It never mutates db.governance/db.ledger/db.sync.v2 directly.
SavedVariables: None (fully derived; no persisted installation state).
]]

local Dibs = _G.Dibs
Dibs.Installation = Dibs.Installation or {}
local Installation = Dibs.Installation

local function recordInstallationTiming(counter, startedAt)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", counter, startedAt)
  end
end

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

local function isOfficer(actor)
  if Dibs.Permissions and type(Dibs.Permissions.IsOfficer) == "function" then
    return Dibs.Permissions.IsOfficer(actor) == true
  end
  if not Dibs.Identity or type(Dibs.Identity.IsCurrentGuildOfficer) ~= "function" then return false end
  return Dibs.Identity.IsCurrentGuildOfficer(actor or localPlayer()) == true
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

-- Real existing Dibs data, independent of whether HistoricalBaseline evidence has
-- ever been collected. A guild is never "clean" merely because the evidence
-- cache is empty (see Installation_Initialization_V2_Architecture_Review.md).
-- SEASON_ALLOCATION transactions are excluded: Dibs.Initialize() creates a
-- default season and automatic rank allocations for every guild, so their
-- presence alone is not evidence of prior manual Dibs usage.
local function detectRealLegacyData(resolvedGuildDB)
  local hasLedgerHistory = false
  -- Resolve the current guild DB once, then let the active-ledger path reuse
  -- this verified snapshot instead of resolving the guild key again.
  local db = type(resolvedGuildDB) == "table" and resolvedGuildDB
    or Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  local ledgerIdStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  -- The initial legacy scan is scoped to the primary ledger. UI view/active
  -- ledger selection must not silently change which history is reconciled.
  local targetLedgerId = "guild-primary"
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "legacy-active-ledger-id", ledgerIdStartedAt)
  end
  local ledgerStatusRead, ledgerReadable = false, false
  local ledgerStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  if Dibs.Ledger and type(Dibs.Ledger.HasNonAllocationTransactions) == "function" then
    local ok, value = pcall(Dibs.Ledger.HasNonAllocationTransactions, targetLedgerId, db)
    if ok and type(value) == "boolean" then
      hasLedgerHistory = value
      ledgerStatusRead, ledgerReadable = true, true
    end
  end
  if not ledgerStatusRead and Dibs.Ledger and type(Dibs.Ledger.GetNonAllocationTransactionCount) == "function" then
    local ok, count = pcall(Dibs.Ledger.GetNonAllocationTransactionCount, targetLedgerId)
    if ok and tonumber(count) ~= nil then
      hasLedgerHistory = tonumber(count) > 0
      ledgerStatusRead, ledgerReadable = true, true
    end
  end
  if Dibs.Ledger and type(Dibs.Ledger.GetTransactionDiagnostics) == "function" then
    if not ledgerStatusRead then
      local ok, diagnostics = pcall(Dibs.Ledger.GetTransactionDiagnostics, targetLedgerId)
      local count = ok and type(diagnostics) == "table"
        and tonumber(diagnostics.nonAllocationTransactionCount) or nil
      if count ~= nil then
        hasLedgerHistory = count > 0
        ledgerStatusRead, ledgerReadable = true, true
      end
    end
  end
  if not ledgerStatusRead and Dibs.Ledger and type(Dibs.Ledger.GetAllTransactions) == "function" then
    local ok, transactions = pcall(Dibs.Ledger.GetAllTransactions, targetLedgerId)
    if ok and type(transactions) == "table" then
      ledgerStatusRead, ledgerReadable = true, true
      for _, tx in ipairs(transactions) do
        if tx.type ~= "SEASON_ALLOCATION" then hasLedgerHistory = true break end
      end
    end
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "legacy-ledger-count", ledgerStartedAt)
  end
  local preDibCount, preDibsReadable = 0, false
  local preDibsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  if Dibs.PreDibs and type(Dibs.PreDibs.GetHistoryCount) == "function" then
    local ok, count = pcall(Dibs.PreDibs.GetHistoryCount, targetLedgerId)
    if ok and tonumber(count) ~= nil then preDibCount, preDibsReadable = tonumber(count), true end
  end
  if not preDibsReadable and Dibs.PreDibs and type(Dibs.PreDibs.GetHistory) == "function" then
    local ok, requests = pcall(Dibs.PreDibs.GetHistory, targetLedgerId)
    if ok and type(requests) == "table" then preDibCount, preDibsReadable = #requests, true end
  end
  if not preDibsReadable and (not Dibs.PreDibs or type(Dibs.PreDibs.GetHistoryCount) ~= "function"
    and type(Dibs.PreDibs.GetHistory) ~= "function") and type(db) == "table"
    and type(db.preDibs) == "table" and type(db.preDibs.requests) == "table" then
    preDibCount, preDibsReadable = #db.preDibs.requests, true
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "legacy-predibs-count", preDibsStartedAt)
  end
  return hasLedgerHistory or preDibCount > 0, hasLedgerHistory and 1 or 0, preDibCount, targetLedgerId, db,
    { ledgerReadable = ledgerReadable, preDibsReadable = preDibsReadable }
end

---@param actor string|nil Optional actor override; defaults to the local player.
---@return table status Normalized installation/readiness projection.
---@doc.id guild.ledger.status
---@doc.category setup
---@doc.since 0.6.5
---@doc.audience officer,gm,developer
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_GUILD_LEDGER_STATUS
---@doc.label-key DOC_GUILD_LEDGER_STATUS_LABEL
function Installation.GetStatus(actor, dbOverride)
  local governanceStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local governanceSummary = Dibs.Governance and Dibs.Governance.GetInstallationSummary
    and Dibs.Governance.GetInstallationSummary(dbOverride)
  local governance, authority, protocolActive
  if type(governanceSummary) == "table" then
    governance = { status = governanceSummary.status, future = { protocolState = governanceSummary.protocolState } }
    authority = {
      state = governanceSummary.authorityState,
      coordinator = governanceSummary.coordinatorDisplayName and {
        displayName = governanceSummary.coordinatorDisplayName,
        memberKey = governanceSummary.coordinatorMemberKey,
      } or nil,
      ledgerEpoch = governanceSummary.ledgerEpoch,
    }
    protocolActive = governanceSummary.protocolActive == true
  else
    governance = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or { status = "POLICY_UNINITIALIZED" }
    authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState() or { state = "LEGACY_LOCAL" }
    protocolActive = Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced() == true
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "governance-authority", governanceStartedAt)
  end
  -- Resolve the active guild DB once for this synchronous status projection.
  -- The baseline summary and legacy-history check are read-only and can safely
  -- share this normalized snapshot instead of re-running Core's DB validation.
  local guildDBStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local statusDB = type(dbOverride) == "table" and dbOverride
    or (Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {}))
  recordInstallationTiming("guild-db-resolution", guildDBStartedAt)
  local baselineStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local baselineSummary = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetInstallationSummary
    and Dibs.HistoricalBaseline.GetInstallationSummary(statusDB)
  if type(baselineSummary) ~= "table" then
    local baselineState = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetState
      and Dibs.HistoricalBaseline.GetState() or { evidence = {}, sources = {} }
    local approvedBaseline = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetBaseline
      and Dibs.HistoricalBaseline.GetBaseline()
    local findings = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetFindings
      and Dibs.HistoricalBaseline.GetFindings() or {}
    baselineSummary = {
      evidenceCount = countTable(baselineState.evidence),
      openFindings = countFindingsOpen(findings),
      incompleteSources = hasIncompleteSources(baselineState),
      baselinePresent = approvedBaseline ~= nil,
      baselineHash = approvedBaseline and approvedBaseline.legacyBaselineHash or nil,
    }
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "historical-baseline-summary", baselineStartedAt)
  end
  local evidenceCount = tonumber(baselineSummary.evidenceCount) or 0
  local openFindings = tonumber(baselineSummary.openFindings) or 0
  local incompleteSources = baselineSummary.incompleteSources == true
  local baselinePresent = baselineSummary.baselinePresent == true
  local legacyStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local hasRealLegacyData, _, detectedPreDibCount, activeLedgerId, resolvedGuildDB, sourceReadability = detectRealLegacyData(statusDB)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "legacy-data-detection", legacyStartedAt)
  end
  local sources = baselineSummary.sources or {}
  local missingScanSources = {}
  local ledgerSourceFound, predibsSourceFound = false, false
  for sourceId, source in pairs(sources) do
    if type(source) == "table" then
      if source.sourceType == "LEDGER_TRANSACTION" then ledgerSourceFound = source.complete == true end
      if source.sourceType == "PREDIB_REQUEST" then predibsSourceFound = source.complete == true end
    end
    if type(sourceId) == "string" and baselineSummary.collectionProgress
      and baselineSummary.collectionProgress[sourceId] then
      local progress = baselineSummary.collectionProgress[sourceId]
      if progress.state ~= "COMPLETE" then
        if sourceId:find(":ledger", 1, true) then ledgerSourceFound = false end
        if sourceId:find(":predibs", 1, true) then predibsSourceFound = false end
      end
    end
  end
  if not sourceReadability.ledgerReadable or (hasLedgerHistory and not ledgerSourceFound) then
    missingScanSources[#missingScanSources + 1] = "ledger"
  end
  if not sourceReadability.preDibsReadable or (detectedPreDibCount > 0 and not predibsSourceFound) then
    missingScanSources[#missingScanSources + 1] = "predibs"
  end
  local hasUncollectedEvidence = #missingScanSources > 0 or (hasRealLegacyData and evidenceCount == 0)
  local reconciliationRequired = hasUncollectedEvidence or (evidenceCount > 0 and openFindings > 0)

  local identityStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local gmRoleStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local actorIsGM = isGM(actor)
  recordInstallationTiming("actor-gm-role", gmRoleStartedAt)
  local officerRoleStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local actorIsOfficer = isOfficer(actor)
  recordInstallationTiming("actor-officer-role", officerRoleStartedAt)
  local snapshotStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local snapshot = actorSnapshot(actor)
  recordInstallationTiming("actor-snapshot", snapshotStartedAt)
  local candidateDisplayName = (authority.coordinator and authority.coordinator.displayName) or (snapshot and snapshot.displayName)
  local syncBehindStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local syncBehind = Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind(resolvedGuildDB) == true
  recordInstallationTiming("sync-behind-check", syncBehindStartedAt)
  local compatibilityReady, compatibilityReason = true, nil
  if candidateDisplayName and Dibs.Sync and type(Dibs.Sync.CanEnforceV2) == "function" then
    local compatibilityStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    compatibilityReady, compatibilityReason = Dibs.Sync.CanEnforceV2({ candidateDisplayName }, resolvedGuildDB)
    recordInstallationTiming("sync-compatibility-check", compatibilityStartedAt)
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Installation data", "identity-sync-compatibility", identityStartedAt)
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
  if not actorIsGM and not actorIsOfficer then
    blockers[#blockers + 1] = "GUILD_MASTER_REQUIRED"
  elseif not actorIsGM and actorIsOfficer then
    if governance.status ~= "GOVERNANCE_ADOPTED" or not baselinePresent then
      warnings[#warnings + 1] = "GM_CONFIRMATION_PENDING"
    end
  end
  if hasUncollectedEvidence then
    local present = false
    for _, blocker in ipairs(blockers) do
      if blocker == "LEGACY_EVIDENCE_SCAN_REQUIRED" then present = true; break end
    end
    if not present then blockers[#blockers + 1] = "LEGACY_EVIDENCE_SCAN_REQUIRED" end
  end

  local result = {
    state = state,
    installType = hasRealLegacyData and "UPGRADE" or "CLEAN",
    actor = { isGM = actorIsGM, isOfficer = actorIsOfficer, displayName = snapshot and snapshot.displayName or nil },
    governance = { ready = governance.status == "GOVERNANCE_ADOPTED" },
    legacy = {
      evidenceCount = evidenceCount,
      openFindings = openFindings,
      incompleteSources = incompleteSources,
      hasUncollectedEvidence = hasUncollectedEvidence,
      reconciliationRequired = reconciliationRequired,
      missingScanSources = missingScanSources,
      sourceReadability = sourceReadability,
    },
    baseline = {
      ready = baselinePresent,
      type = baselinePresent and (evidenceCount == 0 and "GENESIS" or "RECONCILED") or nil,
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
      baselineHash = baselineSummary.baselineHash,
      coordinatorMemberKey = authority.coordinator and authority.coordinator.memberKey or nil,
    },
  }
  return result, activeLedgerId
end

---@doc.id setup.reconciliation
---@doc.category setup
---@doc.since 0.6.5
---@doc.audience officer,gm,developer
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_RECONCILIATION
---@doc.label-key DOC_GUILD_RECONCILIATION_LABEL
function Installation.GetReconciliationView()
  local evidence = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetEvidence and Dibs.HistoricalBaseline.GetEvidence() or {}
  local state = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetState and Dibs.HistoricalBaseline.GetState() or { decisions = {}, activeDecisionByEvidence = {} }
  local findings = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetFindings and Dibs.HistoricalBaseline.GetFindings() or {}
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
  local hasRealLegacyData, _, _, _, _, readability = detectRealLegacyData()
  local baselineState = Dibs.HistoricalBaseline.GetState()
  if not hasRealLegacyData then
    if not readability.ledgerReadable or not readability.preDibsReadable then return false, "LEGACY_SOURCE_READ_FAILED" end
    return true, "NO_ACTION_REQUIRED"
  end
  local summary = Dibs.HistoricalBaseline.GetInstallationSummary()
  local foundLedger, foundPreDibs = false, false
  for _, source in pairs(summary.sources or {}) do
    if source.sourceType == "LEDGER_TRANSACTION" and source.complete == true then foundLedger = true end
    if source.sourceType == "PREDIB_REQUEST" and source.complete == true then foundPreDibs = true end
  end
  if foundLedger and foundPreDibs then return true, "NO_ACTION_REQUIRED" end
  local result, reason = Dibs.HistoricalBaseline.CollectLocalEvidence(actor, "installation-wizard")
  if not result then return false, reason or "LEGACY_EVIDENCE_COLLECTION_FAILED" end
  return true, "COLLECTED"
end

local function stageBaseline(actor, options)
  local existing = Dibs.HistoricalBaseline.GetBaseline()
  if existing then return true, "ALREADY_APPROVED" end
  local baselineState = Dibs.HistoricalBaseline.GetState()
  local evidenceCount = countTable(baselineState.evidence)
  if evidenceCount > 0 then
    local findings = Dibs.HistoricalBaseline.GetFindings()
    local hasUndecidedEvidence = false
    for evidenceId in pairs(baselineState.evidence or {}) do
      if not (baselineState.activeDecisionByEvidence or {})[evidenceId] then
        hasUndecidedEvidence = true
        break
      end
    end
    if hasUndecidedEvidence or countFindingsOpen(findings) > 0 then
      return false, "LEGACY_RECONCILIATION_REQUIRED"
    end
  end
  local acknowledgeIncompleteEvidence = options and options.acknowledgeIncompleteEvidence == true
  local baseline, reason = Dibs.HistoricalBaseline.FinalizeBaseline(actor, { acknowledgeIncompleteEvidence = acknowledgeIncompleteEvidence })
  if not baseline then return false, reason end
  return true, "APPROVED"
end

local function stageCoordinator(actor)
  local authority = Dibs.Governance.GetAuthorityState()
  if authority.state == "ACTIVE" then return true, "ALREADY_ACTIVE" end
  if authority.state ~= "LEGACY_LOCAL" then return false, authority.state end
  local baseline = Dibs.HistoricalBaseline.GetBaseline()
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
---@doc.id guild.setup
---@doc.category setup
---@doc.since 0.6.5
---@doc.audience gm,developer
---@doc.scope guild
---@doc.audit true
---@doc.help-key UI_HELP_GUILD_SETUP
---@doc.label-key DOC_GUILD_SETUP_LABEL
function Installation.Initialize(actor, options)
  options = type(options) == "table" and options or {}
  local actorIsGM = isGM(actor)
  local actorIsOfficer = isOfficer(actor)
  if not actorIsGM and not actorIsOfficer then
    return { ok = false, stage = "actor", reasonCode = "GUILD_MASTER_REQUIRED", status = Installation.GetStatus(actor) }
  end
  if Installation.GetStatus(actor).protocol.active then
    return { ok = true, reasonCode = "ALREADY_INITIALIZED", status = Installation.GetStatus(actor) }
  end
  if not actorIsGM and actorIsOfficer then
    local discoveryOk, discoveryReason = stageLegacyDiscovery(actor)
    if not discoveryOk then
      return { ok = false, stage = "legacy", reasonCode = discoveryReason, status = Installation.GetStatus(actor) }
    end
    if not (Dibs.MultiLedger and type(Dibs.MultiLedger.ProposeLedger) == "function") then
      return { ok = false, stage = "proposal", reasonCode = "PROPOSAL_SERVICE_UNAVAILABLE", status = Installation.GetStatus(actor) }
    end
    local summary = Dibs.HistoricalBaseline.GetInstallationSummary()
    local counts, complete = { ledger = 0, predibs = 0 }, true
    for _, source in pairs(summary.sources or {}) do
      local key = source.sourceType == "LEDGER_TRANSACTION" and "ledger"
        or source.sourceType == "PREDIB_REQUEST" and "predibs" or nil
      if key then
        counts[key] = math.max(counts[key], tonumber(source.evidenceCount) or 0)
        if source.complete ~= true then complete = false end
      end
    end
    for _, progress in pairs(summary.collectionProgress or {}) do
      if type(progress) == "table" and progress.state ~= "COMPLETE" then complete = false end
    end
    local metadata = {
      purpose = complete and "GUILD_PRIMARY_MISSING" or "LEGACY_SCAN_INCOMPLETE",
      discoveredSources = { "ledger", "predibs" }, discoveredCounts = counts,
      unreadableSources = {}, scanComplete = complete,
    }
    local proposal = Dibs.MultiLedger.ProposeLedger(actor, "Guild Primary", metadata)
    if not proposal or proposal.ok ~= true or type(proposal.proposalId) ~= "string" then
      return { ok = false, stage = "proposal", reasonCode = proposal and proposal.reasonCode or "PROPOSAL_NOT_PERSISTED",
        status = Installation.GetStatus(actor) }
    end
    return { ok = true, reasonCode = "PROPOSAL_CREATED", proposalId = proposal.proposalId,
      ledgerId = proposal.ledgerId, status = Installation.GetStatus(actor) }
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
