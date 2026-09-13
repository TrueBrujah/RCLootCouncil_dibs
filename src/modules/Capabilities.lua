--[[
Module: Dibs.Capabilities
Layer: Runtime lifecycle boundary
Purpose: Isolate optional startup capabilities from required Dibs core services.
]]

local Dibs = _G.Dibs
local Capabilities = Dibs.Capabilities or {}
Dibs.Capabilities = Capabilities

local VALID_STATUS = { UNINITIALIZED = true, INITIALIZING = true, AVAILABLE = true, DEGRADED = true, RETRY_PENDING = true, UNAVAILABLE = true }
local entries = Capabilities.entries or {}
Capabilities.entries = entries

local function now() return (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time() end
local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local function concise(reason)
  reason = tostring(reason or "INITIALIZATION_FAILED")
  return reason:sub(1, 160)
end

function Capabilities.Register(id, definition)
  if type(id) ~= "string" or type(definition) ~= "table" or type(definition.initialize) ~= "function" then return nil, "INVALID_CAPABILITY" end
  local entry = entries[id]
  if entry then return entry end
  entry = { id = id, required = definition.required == true, status = "UNINITIALIZED", initialize = definition.initialize,
    retryEvents = copy(definition.retryEvents or {}), dependency = definition.dependency }
  entries[id] = entry
  return entry
end

local function attempt(entry, trigger)
  if entry.status == "AVAILABLE" then return true, "AVAILABLE" end
  entry.status, entry.lastAttempt, entry.lastTrigger = "INITIALIZING", now(), trigger or "STARTUP"
  local ok, result, reason = pcall(entry.initialize, trigger)
  if ok and result ~= false then
    entry.status, entry.reason = "AVAILABLE", nil
    return true, "AVAILABLE"
  end
  local failure = concise(ok and (reason or result) or result)
  entry.reason = failure
  entry.status = not ok and "DEGRADED" or (#entry.retryEvents > 0 and "RETRY_PENDING" or "UNAVAILABLE")
  return false, failure
end

function Capabilities.Initialize(id, trigger)
  local entry = entries[id]
  if not entry then return false, "UNKNOWN_CAPABILITY" end
  return attempt(entry, trigger)
end

function Capabilities.Retry(id, trigger)
  local entry = entries[id]
  if not entry then return false, "UNKNOWN_CAPABILITY" end
  if entry.status == "AVAILABLE" or entry.status == "INITIALIZING" then return entry.status == "AVAILABLE", entry.status end
  return attempt(entry, trigger)
end

function Capabilities.OnEvent(event)
  for _, entry in pairs(entries) do
    if entry.status ~= "AVAILABLE" then
      for _, retryEvent in ipairs(entry.retryEvents) do
        if retryEvent == event then Capabilities.Retry(entry.id, event); break end
      end
    end
  end
end

function Capabilities.Get(id)
  local entry = entries[id]
  if not entry then return nil end
  return { id = entry.id, required = entry.required, status = entry.status, reason = entry.reason,
    lastAttempt = entry.lastAttempt, lastTrigger = entry.lastTrigger, retryEvents = copy(entry.retryEvents), dependency = entry.dependency }
end

function Capabilities.List()
  local values = {}
  for id in pairs(entries) do values[#values + 1] = Capabilities.Get(id) end
  table.sort(values, function(a, b) return a.id < b.id end)
  return values
end

function Capabilities.FormatDiagnostics()
  local lines = {}
  for _, entry in ipairs(Capabilities.List()) do
    lines[#lines + 1] = entry.id .. ": " .. entry.status .. (entry.reason and (" (" .. entry.reason .. ")") or "")
  end
  return table.concat(lines, " | ")
end

return Capabilities
