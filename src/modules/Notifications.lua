--[[
Module: Dibs.Notifications
Layer: Local player presentation
Purpose: Emit bounded, localized, idempotent notifications for the local player.
Responsibilities: Per-character enablement, event deduplication, and safe message formatting.
Non-responsibilities: It never changes ledger, request, Vault, sync, or RCLootCouncil state.
SavedVariables: Existing per-character SavedVariables only.
]]

local Dibs = _G.Dibs
Dibs.Notifications = Dibs.Notifications or {}
local Notifications = Dibs.Notifications

local MESSAGE_KEYS = {
  PREDIB_CONFIRMED = "NOTIFY_PREDIB_CONFIRMED",
  PREDIB_CANCELLED = "NOTIFY_PREDIB_CANCELLED",
  AWARD_FINALIZED = "NOTIFY_AWARD_FINALIZED",
  DIB_CONSUMED = "NOTIFY_DIB_CONSUMED",
  REQUEST_RESOLVED = "NOTIFY_REQUEST_RESOLVED",
  VAULT_RECORDED = "NOTIFY_VAULT_RECORDED",
}
local MAX_SEEN = 128

local function localState()
  local root = Dibs.GetLocalDB and Dibs.GetLocalDB() or {}
  root.notifications = root.notifications or { enabled = true, seen = {} }
  root.notifications.seen = root.notifications.seen or {}
  if root.notifications.enabled == nil then root.notifications.enabled = true end
  return root.notifications
end

local function samePlayer(first, second)
  if not first or not second then return false end
  return string.lower(tostring(first)) == string.lower(tostring(second))
end

local function bounded(value, limit)
  local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if #text > limit then text = text:sub(1, limit) end
  return text
end

local function messageFor(kind, payload)
  local key = MESSAGE_KEYS[kind]
  local template = key and Dibs.L and Dibs.L[key]
  if not template then return nil end
  local item = bounded(payload.itemName or payload.itemLink or payload.itemID or "item", 96)
  return string.format(template, item)
end

function Notifications.IsEnabled()
  return localState().enabled ~= false
end

function Notifications.SetEnabled(enabled)
  local state = localState()
  state.enabled = enabled == true
  return state.enabled
end

function Notifications.GetStatus()
  local state = localState()
  local count = 0
  for _ in pairs(state.seen) do count = count + 1 end
  return { enabled = state.enabled ~= false, seenCount = count }
end

function Notifications.Notify(eventId, kind, payload)
  payload = type(payload) == "table" and payload or {}
  eventId = bounded(eventId, 128)
  if eventId == "" or not MESSAGE_KEYS[kind] then return false, "INVALID_NOTIFICATION" end
  if not Notifications.IsEnabled() then return false, "DISABLED" end
  local target = payload.targetPlayer or payload.playerName
  if target and not samePlayer(target, Dibs.GetPlayerName and Dibs.GetPlayerName() or nil) then
    return false, "NOT_LOCAL_PLAYER"
  end
  local state = localState()
  if state.seen[eventId] then return false, "DUPLICATE" end
  state.seen[eventId] = time()
  local text = messageFor(kind, payload)
  if text and type(Dibs.Message) == "function" then Dibs.Message(text) end
  local ids = {}
  for id, timestamp in pairs(state.seen) do ids[#ids + 1] = { id = id, timestamp = timestamp or 0 } end
  table.sort(ids, function(a, b) return a.timestamp < b.timestamp end)
  while #ids > MAX_SEEN do state.seen[ids[1].id] = nil; table.remove(ids, 1) end
  return true
end

return Notifications
