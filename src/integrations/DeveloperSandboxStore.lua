-- Separate, versioned local data for the developer sandbox. This store is
-- deliberately data-only and is never returned by Dibs.GetDB().
local Dibs = _G.Dibs
Dibs.DeveloperSandboxStore = Dibs.DeveloperSandboxStore or {}
local Store = Dibs.DeveloperSandboxStore

local SCHEMA = 1
local MAX_NODES = 20000
local persisted

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  return result
end

local function countNodes(value, seen, count)
  count = count or 0
  if type(value) ~= "table" then return count + 1 end
  seen = seen or {}
  if seen[value] then return count end
  seen[value] = true
  count = count + 1
  if count > MAX_NODES then return count end
  for key, item in pairs(value) do
    count = countNodes(key, seen, count)
    if count > MAX_NODES then return count end
    count = countNodes(item, seen, count)
    if count > MAX_NODES then return count end
  end
  return count
end

local function validate(value)
  if type(value) ~= "table" then return false, "INVALID_SANDBOX_STORE" end
  local schema = tonumber(value.schema)
  if not schema or schema > SCHEMA then return false, "FUTURE_SANDBOX_SCHEMA" end
  if schema < 1 then return false, "INVALID_SANDBOX_SCHEMA" end
  if type(value.payload) ~= "table" then return false, "INVALID_SANDBOX_PAYLOAD" end
  if countNodes(value.payload) > MAX_NODES then return false, "SANDBOX_STORE_TOO_LARGE" end
  return true
end

function Store.Initialize()
  if _G.RCLootCouncil_dibsSandboxDB == nil then
    _G.RCLootCouncil_dibsSandboxDB = { schema = SCHEMA, payload = nil, updatedAt = nil }
  end
  persisted = _G.RCLootCouncil_dibsSandboxDB
  if type(persisted) ~= "table" then return false, "INVALID_SANDBOX_STORE" end
  if persisted.schema == nil then persisted.schema = SCHEMA end
  return true
end

function Store.GetPersisted()
  return persisted and copy(persisted) or nil
end

function Store.GetPayload()
  if not persisted or type(persisted.payload) ~= "table" then return nil end
  return copy(persisted.payload)
end

function Store.Validate(value)
  return validate(value)
end

function Store.SavePayload(payload)
  if type(payload) ~= "table" then return false, "INVALID_SANDBOX_PAYLOAD" end
  local candidate = { schema = SCHEMA, payload = copy(payload), updatedAt = time() }
  local valid, reason = validate(candidate)
  if not valid then return false, reason end
  persisted = candidate
  _G.RCLootCouncil_dibsSandboxDB = persisted
  return true, copy(candidate)
end

function Store.CloneProduction()
  if not Dibs.GetDB then return false, "PRODUCTION_STORE_UNAVAILABLE" end
  return Store.SavePayload(Dibs.GetDB())
end

return Store