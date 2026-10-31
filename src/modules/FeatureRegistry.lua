--[[
Module: Dibs.FeatureRegistry
Layer: Feature configuration boundary
Purpose: Provide the single centralized registry and the single enforcement gate
for guild-configurable optional features.
Non-responsibilities: It does not own accounting policy, persistence layout,
synchronization transport, or the operational policy record format. It reads the
canonical module definitions from Dibs.OperationalPolicy and never duplicates
them, so there is exactly one source of truth for what exists.
Dependencies: Dibs.OperationalPolicy (canonical definitions and values),
Dibs.Sync (content hashing), Dibs.DeveloperSandbox (production guard).
]]

local Dibs = _G.Dibs
Dibs.FeatureRegistry = Dibs.FeatureRegistry or {}
local Registry = Dibs.FeatureRegistry

--- Reason codes returned by the registry. These are stable identifiers and are
--- surfaced verbatim in the officer interface and in the local diagnostic report.
local REASON = {
  ENABLED = nil,
  REQUIRED_ALWAYS_ON = "FEATURE_REQUIRED_ALWAYS_ON",
  DISABLED_BY_POLICY = "FEATURE_DISABLED_BY_POLICY",
  DISABLED_BY_DEPENDENCY = "FEATURE_DISABLED_BY_DEPENDENCY",
  UNKNOWN_FEATURE = "FEATURE_UNKNOWN",
  INCOMPATIBLE_VERSION = "FEATURE_INCOMPATIBLE_VERSION",
  SANDBOX_ACTIVE = "FEATURE_SANDBOX_ACTIVE",
  BLOCKED_IN_FLIGHT = "FEATURE_BLOCKED_IN_FLIGHT",
  CORE_IMMUTABLE = "FEATURE_CORE_IMMUTABLE",
}

Registry.REASON = REASON

-- Version of the registry contract itself. Bumped when the shape of a feature
-- definition changes in a way that older clients cannot interpret. The value is
-- compared against the operational policy record so that a client running an
-- older build never silently ignores a guild configuration it does not
-- understand.
local REGISTRY_VERSION = 1

Registry.VERSION = REGISTRY_VERSION

-- Minimum operational policy schema understood by this client.
local MINIMUM_POLICY_SCHEMA = 1

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local function now() return (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time() end

-- Feature definitions are normalized once per call from the canonical policy
-- module so that a change to the policy module is picked up without a second
-- list to keep in sync.
local function policyModule()
  return Dibs.OperationalPolicy
end

local function definitions()
  local policy = policyModule()
  if not policy then return {}, {} end
  local optional = policy.GetModuleDefinitions and policy.GetModuleDefinitions() or {}
  local required = policy.GetCoreModuleDefinitions and policy.GetCoreModuleDefinitions() or {}
  return required, optional
end

-- Build the public descriptor for one feature. Required features never expose
-- an enable toggle and always report an enabled effective state.
local function describe(definition, required)
  if not definition then return nil end
  local isRequired = required == true
  return {
    id = definition.key,
    key = definition.key,
    label = definition.label or definition.key,
    description = definition.description or "",
    category = definition.category or (isRequired and "core" or "optional"),
    required = isRequired,
    alwaysEnabled = definition.alwaysEnabled == true,
    defaultEnabled = definition.defaultEnabled ~= false,
    requires = definition.requires,
    scope = definition.scope or "guild",
    -- A required feature is never configurable and can never be disabled.
    configurable = (not isRequired) and definition.configurable ~= false,
    canDisable = (not isRequired) and definition.configurable ~= false
      and definition.alwaysEnabled ~= true and definition.defaultEnabled ~= false,
    version = definition.version or REGISTRY_VERSION,
    reasonCodes = definition.reasonCodes,
  }
end

-- The registry keeps a stable, sorted view of every known feature.
function Registry.ListFeatures()
  local required, optional = definitions()
  local result = {}
  for _, definition in ipairs(required) do
    local entry = describe(definition, true)
    if entry then result[#result + 1] = entry end
  end
  for _, definition in ipairs(optional) do
    local entry = describe(definition, false)
    if entry then result[#result + 1] = entry end
  end
  table.sort(result, function(a, b)
    if a.required ~= b.required then return a.required == true end
    return a.id < b.id
  end)
  return result
end

function Registry.GetDefinition(featureId)
  if type(featureId) ~= "string" then return nil end
  local required, optional = definitions()
  for _, definition in ipairs(required) do
    if definition.key == featureId then return describe(definition, true) end
  end
  for _, definition in ipairs(optional) do
    if definition.key == featureId then return describe(definition, false) end
  end
  return nil
end

function Registry.IsRequired(featureId)
  local definition = Registry.GetDefinition(featureId)
  return definition ~= nil and definition.required == true
end

-- Resolve the effective state of a feature. The precedence is fixed and
-- deterministic:
--   1. Required features are always enabled and can never be turned off.
--   2. An unknown feature fails closed.
--   3. A feature whose dependency is disabled is disabled.
--   4. Otherwise the canonical guild policy value decides.
local function resolve(featureId)
  local definition = Registry.GetDefinition(featureId)
  if not definition then
    return { id = featureId, known = false, enabled = false, required = false, reasonCode = REASON.UNKNOWN_FEATURE }
  end
  local result = {
    id = definition.id, known = true, enabled = false, required = definition.required,
    alwaysEnabled = definition.alwaysEnabled, label = definition.label,
    canDisable = definition.canDisable, reasonCode = nil,
  }
  if definition.required or definition.alwaysEnabled then
    result.enabled = true
    result.reasonCode = nil
    result.locked = true
    return result
  end
  local policy = policyModule()
  local values = policy and policy.GetModuleValues and policy.GetModuleValues() or {}
  local enabled = values[featureId] == true
  if not enabled then
    result.enabled = false
    result.reasonCode = REASON.DISABLED_BY_POLICY
    return result
  end
  if definition.requires then
    local dependency = resolve(definition.requires)
    if not dependency.enabled then
      result.enabled = false
      result.reasonCode = REASON.DISABLED_BY_DEPENDENCY
      result.dependency = definition.requires
      result.dependencyReasonCode = dependency.reasonCode
      return result
    end
  end
  result.enabled = true
  return result
end

-- Public effective-state query. Returns the resolved record.
function Registry.GetEffectiveState(featureId)
  local state = resolve(featureId)
  if not state.known then return nil, REASON.UNKNOWN_FEATURE end
  return state
end

-- Convenience boolean query. Unknown features fail closed.
function Registry.IsEnabled(featureId)
  local state = resolve(featureId)
  if not state.known then return false, REASON.UNKNOWN_FEATURE end
  return state.enabled, state.reasonCode
end

-- The single enforcement gate. Every optional feature must be reached through
-- this function so that a disabled feature cannot be used by an alternate path.
-- Returns true when the feature may proceed, otherwise false plus a reason code
-- and a user facing message.
function Registry.RequireEnabled(featureId, context)
  local state = resolve(featureId)
  if not state.known then
    return false, REASON.UNKNOWN_FEATURE, "Unknown feature: " .. tostring(featureId)
  end
  if state.enabled then return true, nil, nil end
  local label = state.label or tostring(featureId)
  local message = label .. " is disabled by the Guild Master."
  if state.reasonCode == REASON.DISABLED_BY_DEPENDENCY then
    message = label .. " is disabled because " .. tostring(state.dependency) .. " is disabled."
  end
  if context and context.silent then return false, state.reasonCode, message end
  return false, state.reasonCode, message
end

-- Dependency resolution for one feature. Returns the direct dependency list
-- and the transitive closure of required-but-missing dependencies.
function Registry.GetDependencies(featureId)
  local definition = Registry.GetDefinition(featureId)
  if not definition then return nil, REASON.UNKNOWN_FEATURE end
  local direct = {}
  if definition.requires then direct[#direct + 1] = definition.requires end
  local closure = {}
  local visited = {}
  local function walk(id)
    if visited[id] then return end
    visited[id] = true
    local entry = Registry.GetDefinition(id)
    if not entry then return end
    if entry.requires then
      closure[#closure + 1] = entry.requires
      walk(entry.requires)
    end
  end
  walk(featureId)
  return { id = featureId, direct = direct, transitive = closure }
end

-- Reverse dependency map: which optional features would break if the given
-- feature were disabled.
function Registry.GetDependents(featureId)
  local dependents = {}
  for _, entry in ipairs(Registry.ListFeatures()) do
    if entry.requires == featureId then dependents[#dependents + 1] = entry.id end
  end
  table.sort(dependents)
  return dependents
end

-- Determine whether a feature may be disabled right now. In-flight operations
-- are checked through the supplied guard provider so that this module does not
-- need to know the internals of every domain module.
local function inFlightBlock(featureId)
  local guards = Registry.guards
  if type(guards) ~= "table" then return nil end
  local guard = guards[featureId]
  if type(guard) ~= "function" then return nil end
  local ok, reason = guard()
  if not ok then return reason or "BLOCKED_IN_FLIGHT" end
  return nil
end

-- Can the given feature be disabled by the current configuration state?
function Registry.CanDisable(featureId, actor)
  local definition = Registry.GetDefinition(featureId)
  if not definition then return false, REASON.UNKNOWN_FEATURE end
  if definition.required or definition.alwaysEnabled then
    return false, REASON.CORE_IMMUTABLE
  end
  if not definition.canDisable then
    return false, REASON.CORE_IMMUTABLE
  end
  local state = resolve(featureId)
  if not state.enabled then
    -- Already disabled: disabling again is a no-op and is therefore allowed.
    return true, nil
  end
  local blocked = inFlightBlock(featureId)
  if blocked then return false, blocked end
  -- Every dependent that is currently enabled must be disabled in the same
  -- change, otherwise the change would leave the guild in an invalid state.
  local dependents = Registry.GetDependents(featureId)
  local activeDependents = {}
  for _, id in ipairs(dependents) do
    local dependentState = resolve(id)
    if dependentState.enabled then activeDependents[#activeDependents + 1] = id end
  end
  if #activeDependents > 0 then
    return false, "FEATURE_DEPENDENTS_ACTIVE", activeDependents
  end
  return true, nil
end

-- Validate a proposed patch of feature states before it is applied. Returns the
-- normalized patch, or nil plus a reason code. Required features may never
-- appear in a patch.
--
-- `options.ignoreDependencies` is used by the preview path, which must be able
-- to describe the consequence of a patch that would violate a dependency
-- instead of refusing to describe it.
function Registry.ValidatePatch(patch, options)
  local ignoreDependencies = options and options.ignoreDependencies == true
  if type(patch) ~= "table" then return nil, "INVALID_FEATURE_PATCH" end
  local normalized = {}
  for featureId, enabled in pairs(patch) do
    if type(featureId) ~= "string" then return nil, "INVALID_FEATURE_PATCH" end
    if type(enabled) ~= "boolean" then return nil, "INVALID_FEATURE_PATCH" end
    local definition = Registry.GetDefinition(featureId)
    if not definition then return nil, REASON.UNKNOWN_FEATURE end
    if definition.required or definition.alwaysEnabled then
      return nil, REASON.CORE_IMMUTABLE
    end
    if not definition.canDisable then
      return nil, REASON.CORE_IMMUTABLE
    end
    normalized[featureId] = enabled
  end
  if ignoreDependencies then return normalized end
  -- A feature that is being enabled must have its dependency enabled in the
  -- resulting state.
  for featureId, enabled in pairs(normalized) do
    local definition = Registry.GetDefinition(featureId)
    if definition and definition.requires and enabled == true then
      local dependencyState = resolve(definition.requires)
      local dependencyPatch = normalized[definition.requires]
      local dependencyEnabled = dependencyPatch
      if dependencyEnabled == nil then dependencyEnabled = dependencyState.enabled end
      if not dependencyEnabled then
        return nil, REASON.DISABLED_BY_DEPENDENCY
      end
    end
  end
  -- A dependency that is being disabled must have its dependents disabled too.
  for featureId, enabled in pairs(normalized) do
    if enabled == false then
      for _, dependentId in ipairs(Registry.GetDependents(featureId)) do
        local dependentPatch = normalized[dependentId]
        local dependentEnabled = dependentPatch
        if dependentEnabled == nil then
          local dependentState = resolve(dependentId)
          dependentEnabled = dependentState.enabled
        end
        if dependentEnabled then
          return nil, "FEATURE_DEPENDENTS_ACTIVE", { dependentId }
        end
      end
    end
  end
  return normalized
end

-- Compute the effective state a feature would have under a proposed patch,
-- without mutating any state. Used by the officer interface to preview the
-- consequences of a change before it is confirmed.
function Registry.PreviewState(featureId, patch)
  local definition = Registry.GetDefinition(featureId)
  if not definition then return nil, REASON.UNKNOWN_FEATURE end
  local normalized = patch
  if type(patch) == "table" then
    -- The preview must be able to DESCRIBE a patch that would violate a
    -- dependency rule, so the dependency constraint is not enforced here.
    local valid, reason = Registry.ValidatePatch(patch, { ignoreDependencies = true })
    if not valid then return nil, reason end
    normalized = valid
  end
  local state = resolve(featureId)
  if normalized and normalized[featureId] ~= nil then
    local enabled = normalized[featureId]
    if not enabled then
      state.enabled = false
      state.reasonCode = REASON.DISABLED_BY_POLICY
    else
      local dependencyEnabled = true
      if definition.requires then
        local dependencyDefinition = Registry.GetDefinition(definition.requires)
        if dependencyDefinition then
          local dependencyValue = normalized[definition.requires]
          if dependencyValue == nil then
            local dependencyState = resolve(definition.requires)
            dependencyEnabled = dependencyState.enabled
          else
            dependencyEnabled = dependencyValue
          end
        end
      end
      state.enabled = dependencyEnabled
      state.reasonCode = dependencyEnabled and nil or REASON.DISABLED_BY_DEPENDENCY
    end
  end
  return state
end

-- Compatibility state. A client reports the registry version it understands
-- together with the operational policy revision it has applied. The caller can
-- compare this against a peer to detect a version mismatch.
function Registry.GetCompatibility()
  local policy = policyModule()
  local state = policy and policy.GetState and policy.GetState() or {}
  return {
    registryVersion = REGISTRY_VERSION,
    minimumPolicySchema = MINIMUM_POLICY_SCHEMA,
    policySchema = state.schema or MINIMUM_POLICY_SCHEMA,
    policyRevision = tonumber(state.policyRevision) or 0,
    policyAdopted = policy and policy.IsAdopted and policy.IsAdopted() == true,
    policyHash = state.hash,
  }
end

-- True when this client can interpret the given operational policy record. A
-- record produced by a newer registry version is refused rather than applied
-- partially.
function Registry.CanApplyRecord(record)
  if type(record) ~= "table" then return false, "INVALID_POLICY_RECORD" end
  local version = tonumber(record.registryVersion) or MINIMUM_POLICY_SCHEMA
  if version > REGISTRY_VERSION then
    return false, REASON.INCOMPATIBLE_VERSION
  end
  if type(record.values) == "table" and type(record.values.modules) == "table" then
    for featureId in pairs(record.values.modules) do
      if not Registry.GetDefinition(featureId) then
        -- An unknown optional feature is ignored on older clients; it is not a
        -- hard failure because required features are closed and therefore
        -- always present in every definition set.
        local known = Registry.GetDefinition(featureId)
        if known == nil then
          record.registryUnknownFeatures = record.registryUnknownFeatures or {}
          record.registryUnknownFeatures[featureId] = true
        end
      end
    end
  end
  return true
end

-- Diagnostic report used by the health dashboard and the debug report.
function Registry.GetDiagnostics()
  local lines = {}
  local compatibility = Registry.GetCompatibility()
  lines[#lines + 1] = "Registry v" .. tostring(compatibility.registryVersion)
    .. " policy r" .. tostring(compatibility.policyRevision)
    .. " adopted=" .. tostring(compatibility.policyAdopted)
  for _, state in ipairs(Registry.ListFeatures()) do
    local resolved = resolve(state.id)
    lines[#lines + 1] = state.id .. ": " .. (resolved.enabled and "ENABLED" or "DISABLED")
      .. (resolved.reasonCode and (" (" .. tostring(resolved.reasonCode) .. ")") or "")
  end
  return lines
end

-- Audit trail of configuration changes, sourced from the operational policy
-- audit log so that the two systems cannot diverge.
function Registry.GetChangeHistory(limit)
  local policy = policyModule()
  if not policy or not policy.GetState then return {} end
  local state = policy.GetState()
  local audit = state.auditLog or {}
  local count = tonumber(limit) or 20
  local result = {}
  local startIndex = #audit - count + 1
  if startIndex < 1 then startIndex = 1 end
  for index = startIndex, #audit do
    local entry = audit[index]
    if type(entry) == "table" then
      local copyEntry = copy(entry)
      copyEntry.timestamp = copyEntry.timestamp or now()
      result[#result + 1] = copyEntry
    end
  end
  return result
end

return Registry
