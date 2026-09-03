local Dibs = _G.Dibs
Dibs.ProtectedActions = Dibs.ProtectedActions or {}

local function text(key, fallback)
  return (Dibs.L and Dibs.L[key]) or fallback
end

local VALID_ACTIONS = {
  ["season.create"] = true,
  ["season.set"] = true,
  ["rank.set"] = true,
  ["ledger.grant"] = true,
  ["ledger.use"] = true,
  ["ledger.refund"] = true,
  ["ledger.adjust"] = true,
  ["admin.list"] = true,
  ["admin.appoint"] = true,
  ["admin.revoke"] = true,
  ["award.finalize"] = true,
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
    seasonId = payload and payload.seasonId,
  }
end

local function executeSeasonCreate(actor, payload, decision)
  if not Dibs.Seasons or not Dibs.Seasons.Create then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local season = Dibs.Seasons.Create(payload and payload.name)
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
  if not Dibs.RankRules or not Dibs.RankRules.SetAllocation then
    return reject(decision, text("PROTECTED_ACTION_UNAVAILABLE", "Required module unavailable."))
  end
  local seasonId = payload and payload.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId())
  local rankIndex = payload and payload.rankIndex
  local allocation = payload and payload.allocation
  local rankName = payload and payload.rankName
  local rule = Dibs.RankRules.SetAllocation(seasonId, rankIndex, rankName, allocation)
  return buildResult(rule ~= nil, rule, decision)
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
    return true
  end
  local status = tostring(payload.sourceStatus or ""):lower()
  return status == "awarded" or status == "success" or status == "complete" or status == "finalized"
end

function Dibs.ProtectedActions.FinalizeAward(actor, payload)
  local command = payload or {}
  if not isFinalAward(command) then
    return buildResult(false, nil, nil, text("AWARD_NOT_FINAL", "Award is not finalized; no Dib consumed."))
  end
  if not command.awardRef or not command.playerName or not tonumber(command.itemID) then
    return buildResult(false, nil, nil, text("AWARD_INVALID", "Award payload is missing required fields."))
  end

  local existing = Dibs.Ledger and Dibs.Ledger.GetTransactionForAward and Dibs.Ledger.GetTransactionForAward(command.awardRef)
  if existing then
    return buildResult(true, existing, nil)
  end

  local result = Dibs.ProtectedActions.Execute("award.finalize", actor, command)
  if not result.ok then
    return result
  end

  if Dibs.PreDibs and Dibs.PreDibs.GetConfirmedRequestForPlayer and Dibs.PreDibs.Fulfill then
    local request = Dibs.PreDibs.GetConfirmedRequestForPlayer(command.playerName, command.itemID)
    if request and request.requestId then
      Dibs.PreDibs.Fulfill(request.requestId)
    end
  end

  return result
end

local function executeAwardFinalize(actor, payload, decision)
  local command = payload or {}
  if not isFinalAward(command) then
    return buildResult(false, nil, decision, text("AWARD_NOT_FINAL", "Award is not finalized; no Dib consumed."))
  end
  local existing = Dibs.Ledger and Dibs.Ledger.GetTransactionForAward and Dibs.Ledger.GetTransactionForAward(command.awardRef)
  if existing then
    return buildResult(true, existing, decision)
  end
  local tx = Dibs.Ledger.Use(command.playerName, 1, command.reason or "Finalized loot award", command.source or "rclootcouncil", command.seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId()), buildAudit("award.finalize", actor, command, decision))
  return buildResult(tx ~= nil, tx, decision, tx and nil or text("AWARD_CONSUME_FAILED", "Unable to consume Dib for award."))
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
  if actionId == "rank.set" then return executeRankSet(actor, command, decision) end
  if actionId == "ledger.grant" then return executeLedgerGrant(actor, command, decision) end
  if actionId == "ledger.use" then return executeLedgerUse(actor, command, decision) end
  if actionId == "ledger.refund" then return executeLedgerRefund(actor, command, decision) end
  if actionId == "ledger.adjust" then return executeLedgerAdjust(actor, command, decision) end
  if actionId == "admin.list" then return executeAdminList(actor, command, decision) end
  if actionId == "admin.appoint" then return executeAdminChange(actor, command, true, decision) end
  if actionId == "admin.revoke" then return executeAdminChange(actor, command, false, decision) end
  if actionId == "award.finalize" then return executeAwardFinalize(actor, command, decision) end

  return buildResult(false, nil, decision, text("AUTHORITY_INVALID_ACTION", "Unknown protected action."))
end
