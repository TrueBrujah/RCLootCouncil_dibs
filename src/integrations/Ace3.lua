local Dibs = _G.Dibs
Dibs.Ace3 = Dibs.Ace3 or {}

local Adapter = Dibs.Ace3
Adapter.handlers = Adapter.handlers or { events = {}, comms = {} }

local function getLibrary(name)
  if _G.LibStub == nil then return nil end
  local ok, library = pcall(_G.LibStub, name, true)
  return ok and library or nil
end

Adapter.libs = Adapter.libs or {
  comm = getLibrary("AceComm-3.0"),
  serializer = getLibrary("AceSerializer-3.0"),
  event = getLibrary("AceEvent-3.0"),
  timer = getLibrary("AceTimer-3.0"),
  gui = getLibrary("AceGUI-3.0"),
  config = getLibrary("AceConfig-3.0"),
  dialog = getLibrary("AceConfigDialog-3.0"),
}

local function embed(library)
  if library and type(library.Embed) == "function" then
    pcall(library.Embed, library, Adapter)
  end
end

embed(Adapter.libs.comm)
embed(Adapter.libs.event)
embed(Adapter.libs.timer)

local aceRegisterComm = Adapter.RegisterComm
local aceSendCommMessage = Adapter.SendCommMessage
local aceRegisterEvent = Adapter.RegisterEvent
local aceScheduleTimer = Adapter.ScheduleTimer

function Adapter.Has(name)
  return Adapter.libs[name] ~= nil
end

function Adapter.Serialize(value)
  local serializer = Adapter.libs.serializer
  if not serializer or type(serializer.Serialize) ~= "function" then return nil end
  local ok, first, second = pcall(serializer.Serialize, serializer, value)
  if ok and type(first) == "string" and first ~= "" then return first end
  -- A few test doubles and older wrappers expose a `success, payload` pair.
  if ok and first == true and type(second) == "string" and second ~= "" then return second end
  return nil
end

function Adapter.Deserialize(payload)
  local serializer = Adapter.libs.serializer
  if not serializer or type(serializer.Deserialize) ~= "function" then return nil end
  local ok, success, value = pcall(serializer.Deserialize, serializer, payload)
  if ok and success == true then return value end
  return nil
end

function Adapter.SendComm(prefix, message, channel, target)
  local comm = Adapter.libs.comm
  local payload = Adapter.Serialize(message)
  if not comm or not payload or type(aceSendCommMessage) ~= "function" then return false end
  local ok, sent = pcall(aceSendCommMessage, Adapter, prefix, payload, channel, target)
  return ok and sent ~= false
end

function Adapter.RegisterComm(prefix, callback)
  if not Adapter.libs.comm or type(aceRegisterComm) ~= "function" then return false end
  Adapter.handlers.comms[prefix] = callback
  local ok = pcall(aceRegisterComm, Adapter, prefix, function(receivedPrefix, payload, channel, sender)
    local handler = Adapter.handlers.comms[receivedPrefix]
    if handler then return handler(receivedPrefix, payload, channel, sender) end
  end)
  return ok
end

function Adapter.RegisterEvent(event, callback)
  if not Adapter.libs.event or type(aceRegisterEvent) ~= "function" then return false end
  Adapter.handlers.events[event] = callback
  local ok = pcall(aceRegisterEvent, Adapter, event, function(receivedEvent, ...)
    local handler = Adapter.handlers.events[receivedEvent]
    if handler then return handler(receivedEvent, ...) end
  end)
  return ok
end

function Adapter.ScheduleTimer(callback, delay)
  if Adapter.libs.timer and type(aceScheduleTimer) == "function" then
    local ok, timer = pcall(aceScheduleTimer, Adapter, callback, delay)
    if ok then return timer end
  end
  if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
    return _G.C_Timer.After(delay, callback)
  end
  return nil
end

function Adapter.RegisterOptionsTable(name, options)
  local config = Adapter.libs.config
  if not config or type(config.RegisterOptionsTable) ~= "function" then return false end
  return pcall(config.RegisterOptionsTable, config, name, options)
end

function Adapter.AddToBlizOptions(name, displayName, parent, group)
  local dialog = Adapter.libs.dialog
  if not dialog or type(dialog.AddToBlizOptions) ~= "function" then return false end
  return pcall(dialog.AddToBlizOptions, dialog, name, displayName, parent, group)
end

if Dibs.SetupRuntimeEvents then Dibs.SetupRuntimeEvents() end
