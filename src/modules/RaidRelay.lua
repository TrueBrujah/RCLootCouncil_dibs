local Dibs = _G.Dibs
Dibs.RaidRelay = Dibs.RaidRelay or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
end

function Dibs.RaidRelay.SetActiveRelay(enabled)
  ensureState()
  Dibs.db.relay = Dibs.db.relay or {}
  Dibs.db.relay.active = enabled == true
  return Dibs.db.relay.active
end

function Dibs.RaidRelay.IsActiveRelay()
  ensureState()
  return Dibs.db.relay and Dibs.db.relay.active == true
end

function Dibs.RaidRelay.GetLocalState()
  return {
    currentSeason = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil,
    transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {},
    requests = Dibs.PreDibs and Dibs.PreDibs.GetHistory() or {},
  }
end

function Dibs.RaidRelay.Broadcast()
  local state = Dibs.RaidRelay.GetLocalState()
  Dibs.Sync = Dibs.Sync or {}
  Dibs.Sync.RegisterPeer("local-raid", state)
  return state
end
