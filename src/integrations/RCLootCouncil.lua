local Dibs = _G.Dibs
Dibs.RCLootCouncil = Dibs.RCLootCouncil or {}

local function text(key, fallback) return (Dibs.L and Dibs.L[key]) or fallback end

local function getRCAddon()
  if type(LibStub) ~= "function" then return nil end
  local aceAddon = LibStub("AceAddon-3.0", true)
  if not aceAddon or type(aceAddon.GetAddon) ~= "function" then return nil end
  return aceAddon:GetAddon("RCLootCouncil", true)
end

local function isLoaded()
  if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
    local first, second = C_AddOns.IsAddOnLoaded("RCLootCouncil")
    return second == true or first == true
  end
  return type(_G.RCLootCouncil) == "table" or type(getRCAddon()) == "table"
end

local function getRC()
  return getRCAddon() or _G.RCLootCouncil
end

local function playerIdentity(value)
  if type(value) == "table" then
    if type(value.GetGUID) == "function" then
      local ok, guid = pcall(value.GetGUID, value)
      if ok and guid then return tostring(guid) end
    end
    if type(value.GetName) == "function" then
      local ok, name = pcall(value.GetName, value)
      if ok then value = name end
    else
      value = value.guid or value.name
    end
  end
  if value == nil then return nil end
  return Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId(value) or nil
end

local function playerNameIdentity(value)
  if type(value) == "table" then
    if type(value.GetName) == "function" then
      local ok, name = pcall(value.GetName, value)
      if ok then value = name end
    else value = value.name or value.playerName end
    if value == nil then return nil end
  end
  if value == nil and Dibs.GetPlayerName then value = Dibs.GetPlayerName() end
  if not value then return nil end
  local text = tostring(value)
  if not text:find("-", 1, true) and type(GetRealmName) == "function" then
    local realm = tostring(GetRealmName() or ""):gsub("[%s%-]", "")
    if realm ~= "" then text = text .. "-" .. realm end
  end
  return string.lower(text)
end

function Dibs.RCLootCouncil.GetAvailability()
  if not isLoaded() then return "absent" end
  local rc = getRC()
  if type(rc) ~= "table" then return "degraded" end
  if rc.enabled == false then return "absent" end
  if rc.enabled ~= true then return "degraded" end
  if not playerIdentity(rc.masterLooter) then return "degraded" end
  return "operational"
end

function Dibs.RCLootCouncil.IsAvailable()
  return Dibs.RCLootCouncil.GetAvailability() == "operational"
end

function Dibs.RCLootCouncil.EvaluateAuthority(actionId, actor)
  local before = Dibs.RCLootCouncil.GetAvailability()
  local actorId = actor == nil and Dibs.Permissions.CanonicalPlayerId(nil) or playerIdentity(actor)
  if before ~= "operational" or not actorId then
    return { allowed = false, authority = "rclootcouncil", availability = before, actionId = actionId, actorId = actorId, reasonCode = actorId and "RC_AUTHORITY_UNVERIFIABLE" or "INVALID_ACTOR", diagnostic = text("AUTHORITY_RC_UNVERIFIABLE", "RCLootCouncil authority could not be verified.") }
  end
  local rc = getRC()
  local masterId = rc and playerIdentity(rc.masterLooter)
  local after = Dibs.RCLootCouncil.GetAvailability()
  local currentRC = getRC()
  local currentMasterId = currentRC and playerIdentity(currentRC.masterLooter)
  if after ~= before or not masterId or currentMasterId ~= masterId then
    return { allowed = false, authority = "rclootcouncil", availability = "degraded", actionId = actionId, actorId = actorId, reasonCode = "RC_STATE_CHANGED", diagnostic = text("AUTHORITY_RC_STATE_CHANGED", "RCLootCouncil authority changed during evaluation.") }
  end
  local actorName = playerNameIdentity(actor)
  local masterName = playerNameIdentity(rc.masterLooter)
  local allowed = actorId == masterId or (actorName ~= nil and masterName ~= nil and actorName == masterName)
  return { allowed = allowed, authority = "rclootcouncil", availability = before, actionId = actionId, actorId = actorId, reasonCode = allowed and "RC_AUTHORIZED" or "RC_NOT_MASTER_LOOTER", diagnostic = allowed and text("AUTHORITY_RC_AUTHORIZED", "Authorized by RCLootCouncil.") or text("AUTHORITY_RC_NOT_MASTER_LOOTER", "Only the current RCLootCouncil Master Looter may perform this action.") }
end

function Dibs.RCLootCouncil.CanUseDibResponse(playerName, itemID)
  local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  return status.canUseDib == true
end

function Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  local name = playerName or Dibs.GetPlayerName()
  local targetItem = tonumber(itemID)
  local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(name) or 0
  local preDib = targetItem and Dibs.PreDibs and Dibs.PreDibs.GetConfirmedRequestForPlayer(name, targetItem) or nil
  local hasPriority = false
  if targetItem and Dibs.PreDibs then
    for _, request in ipairs(Dibs.PreDibs.GetRequestsForItem(targetItem)) do
      if request.status == "confirmed" then hasPriority = true break end
    end
  end
  local eligible = balance > 0 and (not hasPriority or preDib ~= nil)
  return { playerName = name, itemID = targetItem, balance = tonumber(balance) or 0, hasDibs = balance > 0, hasPreDib = preDib ~= nil, canUseDib = eligible, status = preDib and "pre-dib" or (eligible and "dib-available" or (balance > 0 and "ineligible" or "none")), preDibRequest = preDib }
end

function Dibs.RCLootCouncil.ValidateResponse(playerName, itemID, response)
  if response ~= "DIB" then return true end
  return Dibs.RCLootCouncil.CanUseDibResponse(playerName, itemID)
end

function Dibs.RCLootCouncil.OnAwardSuccess(_, session, winner, status, itemLink)
  if not Dibs.ProtectedActions or not winner or not itemLink then return end
  local itemID = tonumber(tostring(itemLink):match("item:(%d+)"))
  if not itemID then return end
  local rc = getRC()
  local actor = rc and rc.masterLooter
  local ref = table.concat({ "rclc", tostring(session or "?"), tostring(winner), tostring(itemID) }, ":")
  Dibs.ProtectedActions.FinalizeAward(actor, { awardRef = ref, playerName = winner, itemID = itemID, itemLink = itemLink, sourceStatus = status, finalized = true })
end

function Dibs.RCLootCouncil.Initialize()
  if Dibs.RCLootCouncil.initialized then return true end
  local rc = getRC()
  if type(rc) ~= "table" then return false end
  if type(rc.RegisterMessage) == "function" then
    pcall(rc.RegisterMessage, rc, "RCMLAwardSuccess", Dibs.RCLootCouncil.OnAwardSuccess)
  end
  Dibs.RCLootCouncil.initialized = true
  return true
end

function Dibs.RCLootCouncil.TryUseRCModule()
  Dibs.RCLootCouncil.Initialize()
  return false
end

function Dibs.RCLootCouncil.GetLocalStatus()
  return { availability = Dibs.RCLootCouncil.GetAvailability(), protocolVersion = Dibs.PROTOCOL_VERSION, initialized = Dibs.RCLootCouncil.initialized == true }
end
