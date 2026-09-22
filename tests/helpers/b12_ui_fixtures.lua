local M = {}

local function merge(base, overrides)
  for key, value in pairs(overrides or {}) do base[key] = value end
  return base
end

function M.shell(role, overrides)
  return merge({
    role = role or "player",
    selectedRoute = "overview",
    mountedPage = "overview",
    primaryPageCount = 1,
    contentHost = { children = {} },
    footer = { stable = true, actions = {} },
    position = { point = "CENTER", x = 0, y = 0, restored = false },
    combat = { inCombat = false, refreshQueued = false },
    tree = { grouped = true, callbacks = {} },
    contextMenu = nil,
    rcCapabilities = { state = "absent", reasonCode = "RC_ABSENT" },
  }, overrides)
end

function M.playerShell(overrides)
  return M.shell("player", overrides)
end

function M.officerShell(overrides)
  return M.shell("officer", overrides)
end

function M.groupedRoute(section, route)
  return {
    value = tostring(section) .. string.char(1) .. tostring(route),
    section = section,
    route = route,
  }
end

function M.treeCallbacks(routes)
  local callbacks = {}
  for _, route in ipairs(routes or { "overview" }) do
    local entry = M.groupedRoute("section_" .. tostring(route), route)
    callbacks[route] = function()
      return entry.value
    end
  end
  return callbacks
end

function M.pageRoot(route, overrides)
  return merge({
    route = route or "overview",
    released = false,
    headers = { tostring(route or "overview") },
    controls = {},
  }, overrides)
end

function M.contextMenu(entries, overrides)
  return merge({
    open = true,
    entries = entries or {},
    owner = "request-row",
    replaced = false,
    closedOnRouteChange = true,
  }, overrides)
end

function M.combatState(inCombat, overrides)
  return merge({
    inCombat = inCombat == true,
    refreshQueued = inCombat == true,
    dangerousActionAllowed = inCombat ~= true,
  }, overrides)
end

function M.rcCapabilities(state, overrides)
  local reasonCodes = {
    absent = "RC_ABSENT",
    operational = nil,
    degraded = "RC_AWARD_IDENTITY_UNAVAILABLE",
    unsupported = "RC_RESPONSE_UNSUPPORTED",
  }
  return merge({
    state = state or "absent",
    reasonCode = reasonCodes[state or "absent"],
    capabilities = {},
  }, overrides)
end

return M
