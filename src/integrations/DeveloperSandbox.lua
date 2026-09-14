-- Runtime provider boundary for the local developer sandbox.
local Dibs = _G.Dibs
Dibs.DeveloperSandbox = Dibs.DeveloperSandbox or {}
local Sandbox = Dibs.DeveloperSandbox

local ROLE_NAMES = { player = true, officer = true, guild_master = true, gm = true, coordinator = true, recovery = true }
local active

local function copy(value)
  if Dibs.DeepCopy then return Dibs.DeepCopy(value) end
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function developerEnabled()
  return Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() == true
end

local function warning()
  if active then return "SANDBOX_ACTIVE_PRODUCTION_UNTOUCHED" end
  return developerEnabled() and "SANDBOX_INACTIVE_PRODUCTION_ACTIVE" or "DEVELOPER_MODE_DISABLED"
end

function Sandbox.IsActive()
  return active ~= nil
end

function Sandbox.GetActiveProvider()
  return active and "sandbox" or "production"
end

function Sandbox.GetStatus()
  return {
    developerMode = developerEnabled(),
    active = active ~= nil,
    provider = Sandbox.GetActiveProvider(),
    role = active and active.role or nil,
    coordinatorState = active and active.coordinatorState or nil,
    authorityOrigin = active and active.authorityOrigin or "production",
    fault = active and active.fault or nil,
    warning = warning(),
    navigationVisible = developerEnabled(),
  }
end

function Sandbox.ResolveAuthority(operation, actor)
  if not active then return nil, "PRODUCTION_PROVIDER" end
  return { allowed = true, operation = operation, actor = actor, role = active.role,
    authorityOrigin = "simulated_sandbox", provider = "sandbox" }
end

function Sandbox.EnterSandbox(options)
  options = options or {}
  if not developerEnabled() then return false, "DEVELOPER_MODE_REQUIRED" end
  if active then return false, "SANDBOX_ALREADY_ACTIVE" end
  local store = Dibs.DeveloperSandboxStore
  if not store then return false, "SANDBOX_STORE_UNAVAILABLE" end
  local payload
  local retained = store.GetPersisted()
  if options.clone == true or (retained and retained.payload == nil) then
    local ok, reason = store.CloneProduction()
    if not ok then return false, reason end
    payload = store.GetPayload()
  else
    local valid, reason = store.Validate(retained)
    if not valid then return false, reason end
    payload = store.GetPayload()
  end
  if type(payload) ~= "table" then return false, "INVALID_SANDBOX_PAYLOAD" end
  active = { provider = "sandbox", role = nil, coordinatorState = "INACTIVE",
    authorityOrigin = "simulated_sandbox", payload = payload }
  if options.role then
    local ok, reason = Sandbox.SetRole(options.role)
    if not ok then active = nil; return false, reason end
  end
  return true, copy(active)
end

function Sandbox.SetRole(role)
  role = string.lower(tostring(role or ""))
  if not active then return false, "SANDBOX_INACTIVE" end
  if not ROLE_NAMES[role] then return false, "INVALID_SIMULATED_ROLE" end
  if role == "gm" then role = "guild_master" end
  active.role = role
  if role == "coordinator" then active.coordinatorState = "ACTIVE"
  elseif role == "recovery" then active.coordinatorState = "RECOVERY_PENDING"
  end
  return true, role
end

function Sandbox.RefreshSandbox()
  if not active then return false, "SANDBOX_INACTIVE" end
  local role, coordinatorState = active.role, active.coordinatorState
  local ok, reason = Dibs.DeveloperSandboxStore.CloneProduction()
  if not ok then return false, reason end
  active.payload = Dibs.DeveloperSandboxStore.GetPayload()
  active.role, active.coordinatorState = role, coordinatorState
  return true, copy(active)
end

function Sandbox.ResetSandbox()
  if not active then return false, "SANDBOX_INACTIVE" end
  local ok, reason = Dibs.DeveloperSandboxStore.CloneProduction()
  if not ok then return false, reason end
  active.payload = Dibs.DeveloperSandboxStore.GetPayload()
  active.role, active.coordinatorState, active.fault = "player", "INACTIVE", nil
  return true, copy(active)
end

function Sandbox.ExitSandbox()
  if not active then return false, "SANDBOX_INACTIVE" end
  active = nil
  return true, Sandbox.GetStatus()
end

function Sandbox.SetFault(fault)
  if not active then return false, "SANDBOX_INACTIVE" end
  active.fault = tostring(fault)
  return true, active.fault
end

return Sandbox