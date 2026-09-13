--[[
Module: Dibs.EnvironmentAdapters
Layer: Optional presentation integration
Purpose: Accept allowlisted UI hints and always fall back to native Midnight.
Non-responsibilities: Authority, policy, sync, ledger, or RCLootCouncil state.
]]

local Dibs = _G.Dibs
Dibs.EnvironmentAdapters = Dibs.EnvironmentAdapters or {}
local Adapters = Dibs.EnvironmentAdapters

local ALLOWED = { font = true, statusbar = true, density = true, borderThickness = true, texture = true, scale = true }
local providers = {}
local providerNames = { "ELVUI", "TUKUI", "ELLESMERE", "BENIKUI" }

local function sanitize(hints)
  if type(hints) ~= "table" then return {} end
  local result = {}
  for key, value in pairs(hints) do
    if ALLOWED[key] then
      if key == "scale" then
        local number = tonumber(value)
        if number and number >= 0.75 and number <= 1.5 then result[key] = number end
      elseif key == "density" then
        if value == "compact" or value == "comfortable" then result[key] = value end
      elseif key == "borderThickness" then
        local number = tonumber(value)
        if number and number >= 0 and number <= 4 then result[key] = number end
      elseif type(value) == "string" and value ~= "" and #value <= 260 then
        result[key] = value
      end
    end
  end
  return result
end

function Adapters.Register(name, probe)
  name = string.upper(tostring(name or ""))
  if not providers[name] or type(probe) ~= "function" then return false end
  providers[name] = probe
  return true
end

for _, name in ipairs(providerNames) do
  providers[name] = function()
    local global = _G[name]
    if global == nil then return "absent", {}, "NOT_INSTALLED" end
    if type(global) ~= "table" then return "failed", {}, "INVALID_PROVIDER" end
    return "available", global.DibsPresentationHints or {}, "AVAILABLE"
  end
end

function Adapters.ProbeEnvironment()
  for _, name in ipairs(providerNames) do
    local probe = providers[name]
    local ok, status, hints, reason = pcall(probe)
    if ok and status == "available" then
      return { environment = name, status = status, hints = sanitize(hints), reasonCode = reason or "AVAILABLE", observedAt = type(time) == "function" and time() or 0 }
    end
    if ok and status == "failed" then
      return { environment = name, status = "failed", hints = {}, reasonCode = reason or "PROBE_FAILED", observedAt = type(time) == "function" and time() or 0 }
    end
  end
  return { environment = "NATIVE", status = "absent", hints = {}, reasonCode = "NATIVE_FALLBACK", observedAt = type(time) == "function" and time() or 0 }
end

function Adapters.ApplyHints(tokenSet, hints)
  local result = type(tokenSet) == "table" and Dibs.DeepCopy and Dibs.DeepCopy(tokenSet) or tokenSet
  if type(result) ~= "table" then return nil end
  hints = sanitize(hints)
  result.theme = "MIDNIGHT"
  result.adapterHints = hints
  if hints.font then result.typography.font = hints.font end
  if hints.statusbar or hints.texture then result.surfaces.statusbar = hints.statusbar or hints.texture end
  if hints.density then result.density = hints.density end
  if hints.scale then result.scale = hints.scale end
  if hints.borderThickness then result.surfaces.borderThickness = hints.borderThickness end
  return result
end

function Adapters.ResetToNative()
  return Dibs.Midnight and Dibs.Midnight.GetTokens and Dibs.Midnight.GetTokens() or nil
end

function Adapters.ResolveTokens()
  local native = Adapters.ResetToNative()
  local probe = Adapters.ProbeEnvironment()
  if probe.status ~= "available" then return native, probe end
  return Adapters.ApplyHints(native, probe.hints), probe
end

return Adapters
