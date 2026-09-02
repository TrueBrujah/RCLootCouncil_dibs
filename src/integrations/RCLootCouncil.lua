local Dibs = _G.Dibs
Dibs.RCLootCouncil = Dibs.RCLootCouncil or {}

local function getRCAddon()
  if type(LibStub) ~= "function" then
    return nil
  end

  local aceAddon = LibStub("AceAddon-3.0", true)
  if not aceAddon or type(aceAddon.GetAddon) ~= "function" then
    return nil
  end

  return aceAddon:GetAddon("RCLootCouncil", true)
end

function Dibs.RCLootCouncil.IsAvailable()
  return type(getRCAddon()) == "table" or type(_G.RCLootCouncil) == "table"
end

function Dibs.RCLootCouncil.CanUseDibResponse()
  return Dibs.RCLootCouncil.IsAvailable() and Dibs.Permissions and Dibs.Permissions.CanManageDibs() == true
end

function Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  local name = playerName or Dibs.GetPlayerName()
  local targetItem = tonumber(itemID) or nil
  local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(name) or 0
  local preDib = nil

  if targetItem then
    preDib = Dibs.PreDibs and Dibs.PreDibs.GetConfirmedRequestForPlayer(name, targetItem)
  end

  local status = "none"
  if preDib then
    status = "pre-dib"
  elseif balance > 0 then
    status = "dib-available"
  end

  return {
    playerName = name,
    itemID = targetItem,
    balance = tonumber(balance) or 0,
    hasDibs = (tonumber(balance) or 0) > 0,
    hasPreDib = preDib ~= nil,
    canUseDib = (preDib ~= nil) or ((tonumber(balance) or 0) > 0),
    status = status,
    preDibRequest = preDib,
  }
end

function Dibs.RCLootCouncil.InjectCandidateStatus(candidates)
  if type(candidates) ~= "table" then
    return candidates
  end

  for _, candidate in ipairs(candidates) do
    if type(candidate) == "table" then
      local playerName = candidate.name or candidate.playerName or candidate.player or candidate.playerName or Dibs.GetPlayerName()
      local itemID = candidate.itemID or candidate.itemId or candidate.id or candidate.item_id
      local state = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
      candidate.dibsStatus = state.status
      candidate.dibsBalance = state.balance
      candidate.hasDibs = state.hasDibs
      candidate.hasPreDib = state.hasPreDib
      candidate.canUseDib = state.canUseDib
      candidate.dibsInfo = state
    end
  end

  return candidates
end

function Dibs.RCLootCouncil.WrapCandidatesGetter(originalGetter)
  if type(originalGetter) ~= "function" then
    return originalGetter
  end

  if originalGetter.__dibsWrapped then
    return originalGetter
  end

  local wrapped = function(...)
    local result = originalGetter(...)
    return Dibs.RCLootCouncil.InjectCandidateStatus(result)
  end

  wrapped.__dibsWrapped = true
  return wrapped
end

function Dibs.RCLootCouncil.Attach()
  if not Dibs.RCLootCouncil.IsAvailable() then
    return false
  end

  local rc = _G.RCLootCouncil or getRCAddon()
  if type(rc) ~= "table" then
    return false
  end

  rc.Dibs = rc.Dibs or {}
  rc.Dibs.GetStatusForCandidate = function(playerName, itemID)
    return Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  end
  rc.Dibs.InjectCandidateStatus = function(candidates)
    return Dibs.RCLootCouncil.InjectCandidateStatus(candidates)
  end
  rc.Dibs.IsEnabled = true

  if type(rc.GetCandidates) == "function" then
    rc.GetCandidates = Dibs.RCLootCouncil.WrapCandidatesGetter(rc.GetCandidates)
  end

  if type(rc.GetCandidateInfo) == "function" then
    rc.GetCandidateInfo = Dibs.RCLootCouncil.WrapCandidatesGetter(rc.GetCandidateInfo)
  end

  return true
end

function Dibs.RCLootCouncil.RegisterWithRC()
  if not Dibs.RCLootCouncil.IsAvailable() then
    return false
  end

  local rc = _G.RCLootCouncil or getRCAddon()
  if type(rc) ~= "table" then
    return false
  end

  rc.modules = rc.modules or {}
  rc.Dibs = rc.Dibs or {}
  rc.Dibs.moduleName = "RCLootCouncil_dibs"
  rc.Dibs.version = Dibs.VERSION
  rc.Dibs.enabled = true

  if type(rc.RegisterModule) == "function" then
    rc:RegisterModule("RCLootCouncil_dibs", {
      name = "RCLootCouncil_dibs",
      version = Dibs.VERSION,
      status = "enabled",
      getStatus = function()
        return Dibs.RCLootCouncil.GetLocalStatus()
      end,
    })
    return true
  end

  if type(rc.RegisterAddon) == "function" then
    rc:RegisterAddon("RCLootCouncil_dibs", {
      name = "RCLootCouncil_dibs",
      version = Dibs.VERSION,
      status = "enabled",
    })
    return true
  end

  if type(rc.AddModule) == "function" then
    rc:AddModule("RCLootCouncil_dibs", Dibs.RCLootCouncil)
    return true
  end

  if type(rc.Register) == "function" then
    rc:Register("RCLootCouncil_dibs", Dibs.RCLootCouncil)
    return true
  end

  rc.modules["RCLootCouncil_dibs"] = Dibs.RCLootCouncil
  return true
end

function Dibs.RCLootCouncil.TryUseRCModule()
  if Dibs.RCLootCouncil.rcModule then
    local module = Dibs.RCLootCouncil.rcModule
    if type(module.IsEnabled) == "function" and module:IsEnabled() then
      return true
    end

    if type(module.Enable) == "function" then
      module:Enable()
      return true
    end

    return true
  end

  local rcAddon = getRCAddon()
  if type(rcAddon) ~= "table" or type(rcAddon.NewModule) ~= "function" then
    return false
  end

  local module = rcAddon:NewModule("RCLootCouncil_dibs")
  module.OnEnable = function()
    Dibs.RCLootCouncil.attached = Dibs.RCLootCouncil.Attach()
    Dibs.RCLootCouncil.registered = Dibs.RCLootCouncil.RegisterWithRC()
    Dibs.Initialize()
  end

  Dibs.RCLootCouncil.rcModule = module
  Dibs.RCLootCouncil.registered = true
  return true
end

function Dibs.RCLootCouncil.Initialize()
  if Dibs.RCLootCouncil.TryUseRCModule() then
    return true
  end

  local registered = Dibs.RCLootCouncil.RegisterWithRC()
  local attached = Dibs.RCLootCouncil.Attach()
  Dibs.RCLootCouncil.attached = attached
  Dibs.RCLootCouncil.registered = registered
  return attached or registered
end

function Dibs.RCLootCouncil.GetLocalStatus()
  return {
    available = Dibs.RCLootCouncil.IsAvailable(),
    canUseDib = Dibs.RCLootCouncil.CanUseDibResponse(),
    protocolVersion = Dibs.PROTOCOL_VERSION,
    attached = Dibs.RCLootCouncil.attached == true,
    registered = Dibs.RCLootCouncil.registered == true,
  }
end

function Dibs.RCLootCouncil.BindDibResponseHandler(handler)
  Dibs.RCLootCouncil.pendingHandler = handler
  return handler
end
