local Dibs = _G.Dibs
Dibs.ProtectedActions = Dibs.ProtectedActions or {}

local function text(key, fallback)
  return (Dibs.L and Dibs.L[key]) or fallback
end

local VALID_ACTIONS = {
  ["season.create"] = true,
  ["season.set"] = true,
  ["season.rename"] = true,
  ["season.archive"] = true,
  ["rank.set"] = true,
  ["settings.modify"] = true,
  ["installation.mode.set"] = true,
  ["ledger.grant"] = true,
  ["ledger.use"] = true,
  ["ledger.refund"] = true,
  ["ledger.adjust"] = true,
  ["admin.list"] = true,
  ["admin.appoint"] = true,
  ["admin.revoke"] = true,
  ["award.finalize"] = true,
  ["predib.mode.set"] = true,
  ["history.confirm"] = true,
  ["history.reject"] = true,
  ["backup.restore"] = true,
  ["data.import"] = true,
  ["profile.manage"] = true,
  ["eligibility.policy.set"] = true,
  ["eligibility.history.add"] = true,
  ["eligibility.relationship.review"] = true,
  ["eligibility.main.review"] = true,
  ["eligibility.exception.create"] = true,
}

local function isValidAction(actionId)
  return type(actionId) == "string" and VALID_ACTIONS[actionId] == true
end

local function buildResult(ok, value, decision, diagnostic)
  return {
    ok = ok == true,
    value = value,
    decision = decision,
    diagnostic = diagnostic,
    reasonCode = decision and decision.reasonCode or nil,
  }
end

local function reject(decision, fallbackMessage)
  local message = fallbackMessage or text("PROTECTED_ACTION_DENIED", "Action denied.")
  if decision and decision.diagnostic then
    message = decision.diagnostic
  end
  return buildResult(false, nil, decision, message)
end

local function getActorId(actor, decision)
  if decision and decision.actorId then
    return decision.actorId
  end
  if Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId then
    return Dibs.Permissions.CanonicalPlayerId(actor)
  end
  return nil
end

local function buildAudit(actionId, actor, payload, decision)
  return {
    action = actionId,
    actorId = getActorId(actor, decision) or "system:unknown",
    source = payload and payload.source or "protected",
    reason = payload and payload.reason,
    itemID = payload and payload.itemID,
    itemLink = payload and payload.itemLink,
    awardRef = payload and payload.awardRef,
    playerName = payload and payload.playerName,
    playerGuid = payload and (payload.playerGuid or payload.playerId),
    seasonId = payload and payload.seasonId,
    sourceStatus = payload and payload.sourceStatus,
    response = payload and payload.response,
    responseValidated = payload and payload.responseValidated == true or nil,
    reviewRequestId = payload and payload.reviewRequestId,
    evidenceId = payload and payload.evidenceId,
    originalTransactionId = payload and payload.originalTransactionId,
    correctionKey = payload and payload.correctionKey,
    confirmation = payload and payload.confirmation == true or nil,
  }
end

local function executeSeasonCreate(actor, payload, decision)
  if not Dibs.Seasons or not Dibs.Seasons.Create then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local name = payload and payload.name
  if name ~= nil then
    name = tostring(name):match("^%s*(.-)%s*$")
    if name == "" or #name > 80 then return reject(decision, "A valid season name is required.") end
  end
  local season = Dibs.Seasons.Create(name)
  return buildResult(season ~= nil, season, decision, season and nil or text("SEASON_CREATE_FAILED", "Failed to create season."))
end

local function executeSeasonSet(actor, payload, decision)
  local seasonId = payload and payload.seasonId
  if not seasonId or not Dibs.Seasons or not Dibs.Seasons.SetCurrent then
    return reject(decision, text("SEASON_NOT_FOUND", "Season not found."))
  end
  local ok = Dibs.Seasons.SetCurrent(seasonId)
  if not ok then
    return reject(decision, text("SEASON_NOT_FOUND", "Season not found."))
  end
  return buildResult(true, seasonId, decision)
end

local function executeRankSet(actor, payload, decision)
  if not Dibs.RankRules or not Dibs.RankRules.SetRankAllocation then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local seasonId = payload and payload.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId())
  local rankIndex = payload and payload.rankIndex
  local allocation = payload and payload.allocation
  local rankName = payload and payload.rankName
  local rule, reason = Dibs.RankRules.SetRankAllocation(seasonId, rankIndex, allocation, rankName)
  return buildResult(rule ~= nil, rule, decision, reason)
end

local function executeLedgerGrant(actor, payload, decision)
  if not Dibs.Ledger or not Dibs.Ledger.Grant then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local tx = Dibs.Ledger.Grant(payload and payload.playerName, payload and payload.amount, payload and payload.reason, payload and payload.source, payload and payload.seasonId, buildAudit("ledger.grant", actor, payload or {}, decision))
  return buildResult(tx ~= nil, tx, decision)
end

local function executeLedgerUse(actor, payload, decision)
  if not Dibs.Ledger or not Dibs.Ledger.Use then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local tx = Dibs.Ledger.Use(payload and payload.playerName, payload and payload.amount, payload and payload.reason, payload and payload.source, payload and payload.seasonId, buildAudit("ledger.use", actor, payload or {}, decision))
  return buildResult(tx ~= nil, tx, decision)
end

local function executeLedgerRefund(actor, payload, decision)
  if not Dibs.Ledger or not Dibs.Ledger.Refund then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local tx = Dibs.Ledger.Refund(payload and payload.playerName, payload and payload.amount, payload and payload.reason, payload and payload.source, payload and payload.seasonId, buildAudit("ledger.refund", actor, payload or {}, decision))
  return buildResult(tx ~= nil, tx, decision)
end

local function executeLedgerAdjust(actor, payload, decision)
  if not Dibs.Ledger or not Dibs.Ledger.AdminAdjust then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local tx = Dibs.Ledger.AdminAdjust(payload and payload.playerName, payload and payload.amount, payload and payload.reason, payload and payload.source, payload and payload.seasonId, buildAudit("ledger.adjust", actor, payload or {}, decision))
  return buildResult(tx ~= nil, tx, decision)
end

local function executeAdminList(actor, payload, decision)
  if not Dibs.GetDB then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local db = Dibs.GetDB()
  local admins = {}
  local source = db.permissions and db.permissions.activeStandaloneAdmins or {}
  for adminId, info in pairs(source) do
    table.insert(admins, { adminId = adminId, playerName = info.playerName, appointedBy = info.appointedBy, appointedAt = info.appointedAt })
  end
  table.sort(admins, function(a, b)
    return tostring(a.playerName or a.adminId) < tostring(b.playerName or b.adminId)
  end)
  return buildResult(true, admins, decision)
end

local function executeAdminChange(actor, payload, appoint, decision)
  if not Dibs.Permissions or not Dibs.Permissions.ChangeStandaloneAdmin then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local target = payload and payload.target
  if not target then
    return reject(decision, text("AUTHORITY_INVALID_ACTOR", "Unable to identify the actor."))
  end
  local event, finalDecision = Dibs.Permissions.ChangeStandaloneAdmin(target, appoint, actor, payload and payload.reason, decision)
  if not event then
    return reject(finalDecision or decision, text("STANDALONE_ADMIN_GM_ONLY", "Only the guild master can manage Dibs administrators."))
  end
  return buildResult(true, event, finalDecision or decision)
end

local function isFinalAward(payload)
  if not payload then
    return false
  end
  if payload.finalized == true then
    local forcedStatus = tostring(payload.sourceStatus or ""):lower()
    return forcedStatus ~= "test_mode" and forcedStatus ~= "test"
  end
  local status = tostring(payload.sourceStatus or ""):lower()
  return status == "awarded" or status == "success" or status == "complete" or status == "finalized"
    or status == "normal" or status == "indirect" or status == "manually_added"
end

local function isStableRCLootCouncilReference(value)
  local reference = tostring(value or "")
  return reference:match("^entry:") ~= nil
    or reference:match("^history:") ~= nil
    or reference:match("^session:") ~= nil
end

local function executeSeasonRename(actor, payload, decision)
  local seasonId = payload and payload.seasonId
  local name = tostring(payload and payload.name or ""):match("^%s*(.-)%s*$")
  if name == "" or #name > 80 then
    return reject(decision, "A valid season name is required.")
  end
  if not Dibs.Seasons or type(Dibs.Seasons.RenameSeason) ~= "function" then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local season = Dibs.Seasons.RenameSeason(seasonId, name)
  return buildResult(season ~= nil, season, decision, season and nil or text("SEASON_NOT_FOUND", "Season not found."))
end

local function executeSeasonArchive(actor, payload, decision)
  if not Dibs.Seasons or type(Dibs.Seasons.ArchiveSeason) ~= "function" or type(Dibs.Seasons.List) ~= "function" then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  if #Dibs.Seasons.List() <= 1 then
    return reject(decision, "At least one season must remain.")
  end
  local season = Dibs.Seasons.ArchiveSeason(payload and payload.seasonId)
  return buildResult(season ~= nil, season, decision, season and nil or text("SEASON_NOT_FOUND", "Season not found."))
end

function Dibs.ProtectedActions.FinalizeAward(actor, payload)
  local command = payload or {}
  if command.source == "rclootcouncil" then
    if command.responseValidated ~= true or not isStableRCLootCouncilReference(command.awardRef) then
      local result = buildResult(false, nil, nil, text("AWARD_DIB_RESPONSE_REQUIRED", "Only a finalized DIB response can consume a Dib."))
      result.outcome = "rejected"
      result.reasonCode = "AWARD_PROVENANCE_INVALID"
      return result
    end
    local linkedItem = tostring(command.itemLink or ""):match("item:(%d+)")
    if not linkedItem or tonumber(linkedItem) ~= tonumber(command.itemID) then
      local result = buildResult(false, nil, nil, text("AWARD_INVALID", "Award payload is missing required fields."))
      result.outcome = "rejected"
      result.reasonCode = "AWARD_INVALID_ITEM"
      return result
    end
    if Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.IsItemDibTypeAllowed) == "function"
      and command.responseType
      and not Dibs.RCLootCouncil.IsItemDibTypeAllowed(command.itemID, command.responseType)
    then
      local result = buildResult(false, nil, nil, text("AWARD_PERSONAL_ITEM", "Personal Catalyst items cannot consume Dibs."))
      result.outcome = "ignored"
      result.ignored = true
      result.reasonCode = "AWARD_PERSONAL_ITEM"
      return result
    end
  end
  if tostring(command.sourceStatus or ""):lower() == "test_mode" or command.testMode == true then
    local result = buildResult(false, nil, nil, text("AWARD_TEST_MODE", "Test awards cannot consume production Dibs."))
    result.outcome = "ignored"
    result.ignored = true
    result.reasonCode = "AWARD_TEST_MODE"
    return result
  end
  if not isFinalAward(command) then
    local result = buildResult(false, nil, nil, text("AWARD_NOT_FINAL", "Award is not finalized; no Dib consumed."))
    result.outcome = "ignored"
    result.ignored = true
    result.reasonCode = "AWARD_NOT_FINAL"
    return result
  end
  if not command.awardRef or not command.playerName or not tonumber(command.itemID) then
    local result = buildResult(false, nil, nil, text("AWARD_INVALID", "Award payload is missing required fields."))
    result.outcome = "rejected"
    result.reasonCode = "AWARD_INVALID"
    return result
  end

  local result = Dibs.ProtectedActions.Execute("award.finalize", actor, command)
  if not result.ok then
    result.outcome = result.outcome or (result.ignored and "ignored" or "rejected")
    return result
  end

  if Dibs.PreDibs and Dibs.PreDibs.GetConfirmedRequestForPlayer and Dibs.PreDibs.Fulfill then
    local request = Dibs.PreDibs.GetConfirmedRequestForPlayer(command.playerName, command.itemID, command.seasonId, command.difficulty)
    if request and request.requestId then
      Dibs.PreDibs.Fulfill(request.requestId)
    end
  end

  return result
end

local function executeAwardFinalize(actor, payload, decision)
  local command = payload or {}
  if command.source == "rclootcouncil" and command.responseValidated ~= true then
    local result = buildResult(false, nil, decision, text("AWARD_DIB_RESPONSE_REQUIRED", "Only a finalized DIB response can consume a Dib."))
    result.outcome = "rejected"
    result.reasonCode = "AWARD_PROVENANCE_INVALID"
    return result
  end
  if not isFinalAward(command) then
    local result = buildResult(false, nil, decision, text("AWARD_NOT_FINAL", "Award is not finalized; no Dib consumed."))
    result.outcome = "ignored"
    result.ignored = true
    result.reasonCode = "AWARD_NOT_FINAL"
    return result
  end
  local existing = Dibs.Ledger and Dibs.Ledger.GetTransactionForAward and Dibs.Ledger.GetTransactionForAward(command.awardRef)
  if existing then
    local replay = buildResult(true, existing, decision)
    replay.duplicate = true
    replay.outcome = "duplicate"
    return replay
  end
  if Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetStatusForCandidate then
    local candidate = Dibs.RCLootCouncil.GetStatusForCandidate(command.playerName, command.itemID, command.responseType, {
      ignorePublicPreDibRequirement = true,
    })
    if not candidate or candidate.canUseDib ~= true then
      local result = buildResult(false, nil, decision, text("AWARD_CONSUME_FAILED", "Unable to consume Dib for award."))
      result.eligibility = candidate and candidate.eligibility or nil
      result.outcome = candidate and candidate.eligibility and candidate.eligibility.outcome == "review" and "review" or "rejected"
      result.reasonCode = candidate and candidate.eligibility and candidate.eligibility.reasonCode or "AWARD_INELIGIBLE"
      if candidate and candidate.eligibility and candidate.eligibility.explanation then
        result.message = candidate.eligibility.explanation
      end
      return result
    end
  end
  local eligibilityDecision
  if Dibs.CharacterEligibility and Dibs.CharacterEligibility.Evaluate
    and Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetItemSemanticFamily
  then
    local family = Dibs.RCLootCouncil.GetItemSemanticFamily(command.itemID, command.responseType)
    if family == "TOKEN" or family == "TOKEN_SET" or family == "CATALYST" then
      eligibilityDecision = Dibs.CharacterEligibility.Evaluate({
        itemID = command.itemID, itemLink = command.itemLink, responseType = command.responseType,
        family = family, difficulty = command.difficulty, slot = command.slot,
        tokenGroup = command.tokenGroup, classID = command.classID, upgradeTrack = command.upgradeTrack,
        isMainSpec = command.isMainSpec,
      }, command.playerName, command.seasonId)
      if eligibilityDecision.outcome ~= "allow" and eligibilityDecision.outcome ~= "warn" then
        local blocked = buildResult(false, nil, decision, eligibilityDecision.explanation)
        blocked.outcome = eligibilityDecision.outcome == "review" and "review" or "rejected"
        blocked.reasonCode = eligibilityDecision.reasonCode or "ELIGIBILITY_BLOCKED"
        blocked.eligibility = eligibilityDecision
        return blocked
      end
    end
  end
  local tx = Dibs.Ledger.Use(command.playerName, 1, command.reason or "Finalized loot award", command.source or "rclootcouncil", command.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId()), buildAudit("award.finalize", actor, command, decision))
  local result = buildResult(tx ~= nil, tx, decision, tx and nil or text("AWARD_CONSUME_FAILED", "Unable to consume Dib for award."))
  result.outcome = tx and "awarded" or "rejected"
  result.eligibility = eligibilityDecision
  if tx and eligibilityDecision and Dibs.CharacterEligibility.ConsumeException then
    Dibs.CharacterEligibility.ConsumeException(eligibilityDecision)
  end
  if tx and eligibilityDecision and Dibs.CharacterEligibility.RecordAcquisition then
    local recorded = Dibs.CharacterEligibility.RecordAcquisition({
      seasonId = command.seasonId, family = eligibilityDecision.family, itemID = command.itemID,
      itemLink = command.itemLink, itemName = command.itemName, difficulty = command.difficulty,
      slot = command.slot, tokenGroup = command.tokenGroup, classID = command.classID,
      upgradeTrack = command.upgradeTrack, characterName = command.playerName,
      source = command.source or "rclootcouncil", awardRef = command.awardRef,
      acquiredAt = command.originalAwardTime, reason = command.reason or "Finalized protected-loot award",
    }, actor, true)
    result.acquisition = recorded
  end
  return result
end

local function historicalStableReference(command)
  local awardRef = tostring(command.awardRef or "")
  local evidenceId = tostring(command.evidenceId or "")
  return (awardRef ~= "" and (awardRef:match("^history:") or awardRef:match("^entry:") or awardRef:match("^session:")))
    or (evidenceId ~= "" and evidenceId:match("^reconciliation:"))
end

local function executeHistoryConfirm(actor, payload, decision)
  local command = payload or {}
  local mode = tostring(command.mode or "guided"):lower()
  if mode ~= "guided" and mode ~= "manual" then
    return reject(decision, "A guided or manual reconciliation mode is required.")
  end
  if not command.seasonId or not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(command.seasonId) then
    return reject(decision, text("SEASON_NOT_FOUND", "Season not found."))
  end
  if not command.playerName or tostring(command.playerName) == "" or not tonumber(command.itemID) then
    return reject(decision, text("AWARD_INVALID", "Award payload is missing required fields."))
  end
  if not historicalStableReference(command) then
    return reject(decision, text("HISTORY_IDENTITY_REQUIRED", "A stable history identity is required."))
  end
  local existing = Dibs.Ledger and Dibs.Ledger.GetTransactionForEvidence and Dibs.Ledger.GetTransactionForEvidence(command.evidenceId)
  existing = existing or (Dibs.Ledger and Dibs.Ledger.GetTransactionForAward and Dibs.Ledger.GetTransactionForAward(command.awardRef))
  if existing then
    local replay = buildResult(true, existing, decision)
    replay.duplicate = true
    replay.outcome = "duplicate"
    return replay
  end
  if mode == "guided" then
    if (command.classification ~= nil and command.classification ~= "eligible")
      or command.responseValidated ~= true or not command.aliasUsed or not isFinalAward(command) then
      return reject(decision, text("HISTORY_GUIDED_CONFIRM_REQUIRED", "Guided confirmation requires a final award and an explicit response alias."))
    end
  else
    if command.classification and command.classification ~= "ambiguous" and command.classification ~= "unsupported" and command.classification ~= "eligible" then
      return reject(decision, text("AWARD_NOT_FINAL", "Award is not finalized; no Dib consumed."))
    end
    local manualStatus = tostring(command.sourceStatus or ""):lower()
    if manualStatus == "test" or manualStatus == "test_mode" or manualStatus == "pending" or manualStatus == "rejected" then
      return reject(decision, text("AWARD_NOT_FINAL", "Award is not finalized; no Dib consumed."))
    end
    if command.confirmation ~= true or command.manualAcknowledgement ~= true then
      return reject(decision, text("HISTORY_MANUAL_ACK_REQUIRED", "Manual confirmation requires explicit acknowledgement."))
    end
    if tostring(command.reason or ""):match("^%s*$") then
      return reject(decision, text("HISTORY_REASON_REQUIRED", "A reason is required for manual historical confirmation."))
    end
  end
  if not Dibs.Ledger or type(Dibs.Ledger.RecordHistoricalAward) ~= "function" then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local audit = buildAudit("history.confirm", actor, command, decision)
  audit.historySource = command.historySource or "RCLootCouncil"
  audit.historyEvent = command.historyEvent or "unknown"
  audit.sourceEvent = command.historyEvent or "RCMLAwardSuccess"
  audit.accountingAction = "FinalizeAward"
  audit.originalAwardTime = command.originalAwardTime or "unknown"
  audit.responseText = command.responseText or command.response or "unknown"
  audit.responseIdentity = command.responseIdentity or "unknown"
  audit.aliasUsed = command.aliasUsed or "unknown"
  audit.reconciliationSessionId = command.reconciliationSessionId or "unknown"
  audit.difficulty = command.difficulty or "unknown"
  audit.importedAt = time()
  audit.importReason = command.reason
  audit.reviewMode = mode
  audit.manualAcknowledgement = command.manualAcknowledgement == true
  local tx = Dibs.Ledger.RecordHistoricalAward(command.playerName, command.seasonId, command.awardRef, command.evidenceId, command.reason or "Historical RCLootCouncil award", audit)
  local result = buildResult(tx ~= nil, tx, decision, tx and nil or text("AWARD_CONSUME_FAILED", "Unable to consume Dib for historical award."))
  result.outcome = tx and "awarded" or "rejected"
  return result
end

local function executeHistoryReject(actor, payload, decision)
  local command = payload or {}
  if not command.reconciliationSessionId or not command.candidateId then
    return reject(decision, "A reconciliation session and candidate are required.")
  end
  if tostring(command.reason or ""):match("^%s*$") then
    return reject(decision, text("HISTORY_REASON_REQUIRED", "A reason is required for manual historical confirmation."))
  end
  return buildResult(true, {
    sessionId = command.reconciliationSessionId,
    candidateId = command.candidateId,
    outcome = "rejected",
    reason = command.reason,
    actorId = getActorId(actor, decision),
    createdAt = time(),
  }, decision)
end

local function executePreDibModeSet(actor, payload, decision)
  if not Dibs.PreDibs or not Dibs.PreDibs.SetModePolicy then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local policy, reason = Dibs.PreDibs.SetModePolicy(payload and payload.seasonId, payload and payload.mode, actor)
  return buildResult(policy ~= nil, policy, decision, reason)
end

local function executeInstallationModeSet(actor, payload, decision)
  if not Dibs.Permissions or not Dibs.Permissions.SetInstallationMode then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local mode, reason = Dibs.Permissions.SetInstallationMode(payload and payload.mode, actor)
  return buildResult(mode ~= nil, mode, decision, reason)
end

local function executeBackupRestore(actor, payload, decision)
  if not Dibs.Backup or type(Dibs.Backup.Restore) ~= "function" then return reject(decision, "Backup module unavailable.") end
  local value, reason = Dibs.Backup.Restore(payload and payload.previewId, payload and payload.confirmation == true, payload and payload.reason, actor)
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeDataImport(actor, payload, decision)
  if not Dibs.ImportExport or type(Dibs.ImportExport.Apply) ~= "function" then return reject(decision, "Import/export module unavailable.") end
  local value, reason = Dibs.ImportExport.Apply(payload and payload.previewId, payload and payload.confirmation == true, payload and payload.reason, actor)
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeProfileManage(actor, payload, decision)
  if not Dibs.Profiles then return reject(decision, "Profiles module unavailable.") end
  local op = tostring(payload and payload.operation or ""):lower(); local value, reason
  if op == "create" then value, reason = Dibs.Profiles.Create(payload.name, payload.scope, payload, actor)
  elseif op == "copy" then value, reason = Dibs.Profiles.Copy(payload.source, payload.name, payload.scope, actor)
  elseif op == "rename" then value, reason = Dibs.Profiles.Rename(payload.name, payload.newName, payload.scope, actor)
  elseif op == "activate" then value, reason = Dibs.Profiles.Activate(payload.name, payload.scope, actor, payload.confirmation == true)
  elseif op == "reset" then value, reason = Dibs.Profiles.Reset(payload.name, payload.scope, actor)
  elseif op == "delete" then value, reason = Dibs.Profiles.Delete(payload.name, payload.scope, actor)
  else return reject(decision, "Unknown profile operation.") end
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeEligibilityPolicySet(actor, payload, decision)
  if not Dibs.CharacterEligibility or type(Dibs.CharacterEligibility.SetPolicy) ~= "function" then
    return reject(decision, "Character eligibility module unavailable.")
  end
  local value, reason = Dibs.CharacterEligibility.SetPolicy(payload or {}, actor)
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeEligibilityHistoryAdd(actor, payload, decision)
  if not Dibs.CharacterEligibility or type(Dibs.CharacterEligibility.RecordAcquisition) ~= "function" then
    return reject(decision, "Character eligibility module unavailable.")
  end
  local value, reason = Dibs.CharacterEligibility.RecordAcquisition(payload or {}, actor, false)
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeEligibilityRelationshipReview(actor, payload, decision)
  if not Dibs.CharacterEligibility or type(Dibs.CharacterEligibility.ReviewRelationship) ~= "function" then
    return reject(decision, "Character eligibility module unavailable.")
  end
  local value, reason = Dibs.CharacterEligibility.ReviewRelationship(payload and payload.relationshipId, payload and payload.status, actor, payload and payload.reason)
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeEligibilityMainReview(actor, payload, decision)
  if not Dibs.CharacterEligibility or type(Dibs.CharacterEligibility.ApproveMainChange) ~= "function" then
    return reject(decision, "Character eligibility module unavailable.")
  end
  local value, reason = Dibs.CharacterEligibility.ApproveMainChange(payload and payload.changeId, payload or {}, actor)
  return buildResult(value ~= nil, value, decision, reason)
end

local function executeEligibilityException(actor, payload, decision)
  if not Dibs.CharacterEligibility or type(Dibs.CharacterEligibility.CreateProbationException) ~= "function" then
    return reject(decision, "Character eligibility module unavailable.")
  end
  local value, reason = Dibs.CharacterEligibility.CreateProbationException(payload or {}, actor)
  return buildResult(value ~= nil, value, decision, reason)
end

function Dibs.ProtectedActions.Execute(actionId, actor, payload)
  local command = payload or {}
  if not isValidAction(actionId) then
    return buildResult(false, nil, { reasonCode = "INVALID_ACTION" }, text("AUTHORITY_INVALID_ACTION", "Unknown protected action."))
  end
  if not Dibs.Permissions or not Dibs.Permissions.Evaluate then
    return buildResult(false, nil, { reasonCode = "AUTHORITY_UNAVAILABLE" }, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end

  local decision = Dibs.Permissions.Evaluate(actionId, actor)
  if not decision.allowed then
    return reject(decision)
  end

  if actionId == "season.create" then return executeSeasonCreate(actor, command, decision) end
  if actionId == "season.set" then return executeSeasonSet(actor, command, decision) end
  if actionId == "season.rename" then return executeSeasonRename(actor, command, decision) end
  if actionId == "season.archive" then return executeSeasonArchive(actor, command, decision) end
  if actionId == "rank.set" then return executeRankSet(actor, command, decision) end
  if actionId == "ledger.grant" then return executeLedgerGrant(actor, command, decision) end
  if actionId == "ledger.use" then return executeLedgerUse(actor, command, decision) end
  if actionId == "ledger.refund" then return executeLedgerRefund(actor, command, decision) end
  if actionId == "ledger.adjust" then return executeLedgerAdjust(actor, command, decision) end
  if actionId == "admin.list" then return executeAdminList(actor, command, decision) end
  if actionId == "admin.appoint" then return executeAdminChange(actor, command, true, decision) end
  if actionId == "admin.revoke" then return executeAdminChange(actor, command, false, decision) end
  if actionId == "award.finalize" then return executeAwardFinalize(actor, command, decision) end
  if actionId == "history.confirm" then return executeHistoryConfirm(actor, command, decision) end
  if actionId == "history.reject" then return executeHistoryReject(actor, command, decision) end
  if actionId == "predib.mode.set" then return executePreDibModeSet(actor, command, decision) end
  if actionId == "installation.mode.set" then return executeInstallationModeSet(actor, command, decision) end
  if actionId == "backup.restore" then return executeBackupRestore(actor, command, decision) end
  if actionId == "data.import" then return executeDataImport(actor, command, decision) end
  if actionId == "profile.manage" then return executeProfileManage(actor, command, decision) end
  if actionId == "eligibility.policy.set" then return executeEligibilityPolicySet(actor, command, decision) end
  if actionId == "eligibility.history.add" then return executeEligibilityHistoryAdd(actor, command, decision) end
  if actionId == "eligibility.relationship.review" then return executeEligibilityRelationshipReview(actor, command, decision) end
  if actionId == "eligibility.main.review" then return executeEligibilityMainReview(actor, command, decision) end
  if actionId == "eligibility.exception.create" then return executeEligibilityException(actor, command, decision) end
  if actionId == "settings.modify" then return buildResult(true, true, decision) end

  return buildResult(false, nil, decision, text("AUTHORITY_INVALID_ACTION", "Unknown protected action."))
end
