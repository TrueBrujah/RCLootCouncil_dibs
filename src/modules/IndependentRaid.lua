--[[
Module: Dibs.IndependentRaid
Layer: Raid Session / Local Independent Raid
Purpose: Manage standalone local-only raid sessions for ad-hoc, alt, or community raids.
Responsibilities: Zero network sync on guild channels, local ephemeral point balances,
integration with vanilla RCLootCouncil voting, and post-raid award reconciliation.
Dependencies: Dibs.Permissions, Dibs.Ledger.
SavedVariables: db.independentSessions, db.activeIndependentSessionId.
]]

local Dibs = _G.Dibs
Dibs.IndependentRaid = Dibs.IndependentRaid or {}
local IndependentRaid = Dibs.IndependentRaid

local function ensureState()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.independentSessions = db.independentSessions or {}
  return db
end

local function normalizePlayer(name)
  if not name or name == "" then return nil end
  local value = tostring(name):match("^%s*(.-)%s*$")
  if not value:find("-", 1, true) and type(GetRealmName) == "function" then
    local realm = tostring(GetRealmName() or ""):gsub("[%s%-]", "")
    if realm ~= "" then value = value .. "-" .. realm end
  end
  return value
end

function IndependentRaid.StartSession(sessionName, startingPoints)
  local db = ensureState()
  if IndependentRaid.IsSessionActive() then
    return { ok = false, reasonCode = "SESSION_ALREADY_ACTIVE" }
  end

  local points = tonumber(startingPoints) or 1
  local now = time and time() or 0
  local sessionId = "IND-" .. tostring(now) .. "-" .. math.random(1000, 9999)
  local name = (sessionName and tostring(sessionName) ~= "") and sessionName
    or ("Independent Raid - " .. (date and date("%Y-%m-%d") or tostring(now)))

  local session = {
    id = sessionId,
    name = name,
    startingPoints = points,
    status = "ACTIVE",
    startedAt = now,
    balances = {},
    awards = {},
  }

  db.independentSessions[sessionId] = session
  db.activeIndependentSessionId = sessionId

  return { ok = true, sessionId = sessionId }
end

function IndependentRaid.GetActiveSessionId()
  local db = ensureState()
  local sessionId = db.activeIndependentSessionId
  if not sessionId then return nil end
  local session = db.independentSessions[sessionId]
  if session and session.status == "ACTIVE" then
    return sessionId
  end
  return nil
end

function IndependentRaid.GetActiveSession()
  local db = ensureState()
  local sessionId = IndependentRaid.GetActiveSessionId()
  return sessionId and db.independentSessions[sessionId] or nil
end

function IndependentRaid.IsSessionActive()
  return IndependentRaid.GetActiveSession() ~= nil
end

function IndependentRaid.ConcludeSession(sessionId)
  local db = ensureState()
  local targetId = sessionId or db.activeIndependentSessionId
  if not targetId or not db.independentSessions[targetId] then
    return { ok = false, reasonCode = "SESSION_NOT_FOUND" }
  end

  local session = db.independentSessions[targetId]
  session.status = "CONCLUDED"
  session.concludedAt = time and time() or 0

  if db.activeIndependentSessionId == targetId then
    db.activeIndependentSessionId = nil
  end

  return { ok = true }
end

function IndependentRaid.GetPastSessions()
  local db = ensureState()
  local list = {}
  for _, session in pairs(db.independentSessions or {}) do
    list[#list + 1] = session
  end
  table.sort(list, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
  return list
end

function IndependentRaid.GetPlayerBalance(playerName, sessionId)
  local player = normalizePlayer(playerName)
  if not player then return 0 end

  local db = ensureState()
  local targetId = sessionId or IndependentRaid.GetActiveSessionId()
  if not targetId or not db.independentSessions[targetId] then
    return 0
  end

  local session = db.independentSessions[targetId]
  if session.balances[player] == nil then
    return session.startingPoints or 1
  end
  return session.balances[player]
end

function IndependentRaid.RecordAward(winner, itemID, itemLink, isDib, evidence)
  local session = IndependentRaid.GetActiveSession()
  if not session then
    return { ok = false, reasonCode = "NO_ACTIVE_SESSION" }
  end

  local player = normalizePlayer(winner)
  if not player then
    return { ok = false, reasonCode = "INVALID_WINNER" }
  end

  local now = time and time() or 0
  local awardId = "AWD-" .. tostring(now) .. "-" .. (#session.awards + 1)

  if isDib then
    local currentBalance = IndependentRaid.GetPlayerBalance(player, session.id)
    if currentBalance <= 0 then
      return { ok = false, outcome = "insufficient_points", reasonCode = "INDEPENDENT_NO_POINTS" }
    end

    session.balances[player] = currentBalance - 1
    session.awards[#session.awards + 1] = {
      awardId = awardId,
      timestamp = now,
      recipient = player,
      itemID = itemID,
      itemLink = itemLink,
      isDib = true,
      dibsSpent = 1,
      reconciled = false,
      evidence = evidence,
    }
    return {
      ok = true,
      awardId = awardId,
      outcome = "independent_consumed",
      remainingBalance = session.balances[player],
    }
  else
    session.awards[#session.awards + 1] = {
      awardId = awardId,
      timestamp = now,
      recipient = player,
      itemID = itemID,
      itemLink = itemLink,
      isDib = false,
      dibsSpent = 0,
      reconciled = false,
      evidence = evidence,
    }
    return {
      ok = true,
      awardId = awardId,
      outcome = "independent_free_award",
      remainingBalance = IndependentRaid.GetPlayerBalance(player, session.id),
    }
  end
end

function IndependentRaid.GetVaultEligibility(playerName)
  if Dibs.GreatVault and type(Dibs.GreatVault.GetPlayerAcquisitions) == "function" then
    return Dibs.GreatVault.GetPlayerAcquisitions(playerName)
  end
  return {}
end

function IndependentRaid.ReconcileAward(actor, sessionId, awardId, targetLedgerId)
  local role = Dibs.Permissions and Dibs.Permissions.GetGuildRole and Dibs.Permissions.GetGuildRole(actor) or "player"
  if role ~= "gm" and role ~= "officer" then
    return { ok = false, reasonCode = "GUILD_ADMIN_REQUIRED" }
  end

  local db = ensureState()
  local session = db.independentSessions and db.independentSessions[sessionId]
  if not session then
    return { ok = false, reasonCode = "SESSION_NOT_FOUND" }
  end

  local targetAward = nil
  for _, award in ipairs(session.awards or {}) do
    if award.awardId == awardId then
      targetAward = award
      break
    end
  end
  if not targetAward then
    return { ok = false, reasonCode = "AWARD_NOT_FOUND" }
  end

  if targetAward.reconciled then
    return { ok = false, reasonCode = "ALREADY_RECONCILED" }
  end

  if targetAward.isDib and (targetAward.dibsSpent or 0) > 0 then
    if not (Dibs.Ledger and type(Dibs.Ledger.Use) == "function") then
      return { ok = false, reasonCode = "LEDGER_UNAVAILABLE" }
    end

    local seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or "season-1"
    local tx, err = Dibs.Ledger.Use(
      targetAward.recipient,
      targetAward.dibsSpent,
      "Independent Raid Award: " .. tostring(targetAward.itemLink or targetAward.itemID),
      "independent_raid",
      seasonId,
      { actor = actor },
      targetLedgerId or "guild-primary"
    )

    if not tx then
      return { ok = false, reasonCode = err or "LEDGER_TRANSACTION_FAILED" }
    end

    targetAward.reconciled = true
    targetAward.reconciledTransactionId = type(tx) == "table" and (tx.id or tx.transactionId)
      or ("TX-RECONCILED-" .. tostring(time and time() or 0))
    targetAward.reconciledLedgerId = targetLedgerId or "guild-primary"

    return { ok = true, transactionId = targetAward.reconciledTransactionId }
  else
    targetAward.reconciled = true
    targetAward.reconciledTransactionId = "FREE_AWARD"
    return { ok = true, transactionId = "FREE_AWARD" }
  end
end

return IndependentRaid
