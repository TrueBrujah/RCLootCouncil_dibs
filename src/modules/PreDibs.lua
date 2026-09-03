local Dibs = _G.Dibs
Dibs.PreDibs = Dibs.PreDibs or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.preDibs = Dibs.db.preDibs or { requests = {} }
  Dibs.db.preDibs.requests = Dibs.db.preDibs.requests or {}
end

function Dibs.PreDibs.Create(playerName, itemID, itemName, seasonId)
  ensureState()
  if not tonumber(itemID) or tonumber(itemID) <= 0 then return nil end

  local request = {
    requestId = Dibs.NewId("predib"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = tonumber(itemID) or 0,
    itemName = itemName or "Unknown item",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
    status = "pending",
    createdAt = time(),
    updatedAt = time(),
  }

  table.insert(Dibs.db.preDibs.requests, request)
  return request
end

function Dibs.PreDibs.UpdateStatus(requestId, status)
  ensureState()

  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId then
      request.status = status
      request.updatedAt = time()
      return request
    end
  end

  return nil
end

function Dibs.PreDibs.Confirm(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "confirmed")
end

function Dibs.PreDibs.Cancel(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "cancelled")
end

function Dibs.PreDibs.Invalidate(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "invalidated")
end

function Dibs.PreDibs.Fulfill(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "fulfilled")
end

function Dibs.PreDibs.GetActiveRequests(playerName)
  ensureState()
  local active = {}
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.playerName == (playerName or Dibs.GetPlayerName()) and request.status ~= "fulfilled" and request.status ~= "cancelled" and request.status ~= "invalidated" then
      table.insert(active, request)
    end
  end
  return active
end

function Dibs.PreDibs.GetRequestsForItem(itemID)
  ensureState()
  local list = {}
  local targetItem = tonumber(itemID) or 0
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if tonumber(request.itemID) == targetItem then
      table.insert(list, request)
    end
  end
  return list
end

function Dibs.PreDibs.GetConfirmedRequestForPlayer(playerName, itemID)
  ensureState()
  local targetPlayer = playerName or Dibs.GetPlayerName()
  local requests = Dibs.PreDibs.GetRequestsForItem(itemID)
  for _, request in ipairs(requests) do
    if request.playerName == targetPlayer and request.status == "confirmed" then
      return request
    end
  end
  return nil
end

function Dibs.PreDibs.GetHistory()
  ensureState()
  return Dibs.db.preDibs.requests
end
