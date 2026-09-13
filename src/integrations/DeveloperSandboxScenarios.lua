local Dibs = _G.Dibs
Dibs.DeveloperSandboxScenarios = Dibs.DeveloperSandboxScenarios or {}
local Scenarios = Dibs.DeveloperSandboxScenarios

local roles = { player = true, officer = true, guild_master = true, coordinator = true, recovery = true }
local faults = { missing_coordinator = true, stale_peer = true, duplicate_event = true, malformed_payload = true }

function Scenarios.Execute(scenarioId)
  if not Dibs.DeveloperSandbox or not Dibs.DeveloperSandbox.IsActive() then
    return { ok = false, reason = "SANDBOX_INACTIVE" }
  end
  local value = tostring(scenarioId or "")
  local role = value:match("^role_(.+)$")
  if role and roles[role] then
    local ok, reason = Dibs.DeveloperSandbox.SetRole(role)
    return { ok = ok == true, scenario = value, reason = ok and nil or reason }
  end
  if faults[value] then
    local ok, reason = Dibs.DeveloperSandbox.SetFault(value)
    return { ok = ok == true, scenario = value, reason = ok and nil or reason }
  end
  return { ok = false, reason = "UNKNOWN_SANDBOX_SCENARIO" }
end

return Scenarios