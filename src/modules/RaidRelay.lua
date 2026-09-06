local Dibs = _G.Dibs
Dibs.RaidRelay = Dibs.RaidRelay or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
end

local function localIsGuildAdmin()
  if not Dibs.Permissions or type(Dibs.Permissions.GetGuildRole) ~= "function" then return false end
  local role = Dibs.Permissions.GetGuildRole(nil)
  return role == "gm" or role == "officer"
end

local function emptyState()
  return {
    currentSeason = nil,
    transactions = {},
    requests = {},
  }
end

function Dibs.RaidRelay.SetActiveRelay(enabled, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  ensureState()
  Dibs.db.relay = Dibs.db.relay or {}
  Dibs.db.relay.active = enabled == true
  return Dibs.db.relay.active, nil
end

function Dibs.RaidRelay.IsActiveRelay()
  ensureState()
  return Dibs.db.relay and Dibs.db.relay.active == true
end

function Dibs.RaidRelay.GetLocalState()
  if not localIsGuildAdmin() then return emptyState() end
  return {
    currentSeason = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil,
    transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {},
    requests = Dibs.PreDibs and Dibs.PreDibs.GetHistory() or {},
  }
end

function Dibs.RaidRelay.Broadcast(channel)
  if not localIsGuildAdmin() then return emptyState(), false, "GUILD_ADMIN_REQUIRED" end
  local state = Dibs.RaidRelay.GetLocalState()
  Dibs.Sync = Dibs.Sync or {}
  Dibs.Sync.RegisterPeer("local-raid", state)
  if not Dibs.RaidRelay.IsActiveRelay() or type(Dibs.Sync.Send) ~= "function" then
    return state, false
  end

  local destination = channel or "RAID"
  local helloSent = Dibs.Sync.Send({
    type = "HELLO",
    senderId = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil,
  }, destination)
  local manifestSent = Dibs.Sync.BuildManifest and Dibs.Sync.Send(Dibs.Sync.BuildManifest(), destination) or false
  return state, helloSent == true and manifestSent == true
end

function Dibs.RaidRelay.SendReminder(message)
  local allowed, reason = false, "REMINDER_NOT_AUTHORIZED"
  if Dibs.Permissions and Dibs.Permissions.CanSendReminder then
    allowed, reason = Dibs.Permissions.CanSendReminder()
  end
  if allowed ~= true then return false, reason end
  if type(SendChatMessage) ~= "function" then return false, "REMINDER_CHANNEL_UNAVAILABLE" end
  local text = tostring(message or "")
  if text == "" and Dibs.PreDibs and Dibs.PreDibs.GetAnnouncementTemplates then
    text = Dibs.PreDibs.GetAnnouncementTemplates().reminder
  end
  if Dibs.PreDibs and Dibs.PreDibs.FormatAnnouncement then
    text = Dibs.PreDibs.FormatAnnouncement(text, { source = "Raid reminder" })
  end
  local ok = pcall(SendChatMessage, text, "RAID")
  return ok == true, ok and nil or "REMINDER_CHANNEL_UNAVAILABLE"
end
