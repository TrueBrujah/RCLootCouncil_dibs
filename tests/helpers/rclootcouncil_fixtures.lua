local M = {}

-- Small deterministic RC surfaces used by readiness and dry-run tests. They
-- intentionally expose only the capability fields needed by the adapter.
function M.valid(options)
  options = options or {}
  return {
    enabled = true,
    version = options.version or "3.23.3",
    masterLooter = options.masterLooter or { guid = "Player-1-TESTER", name = "Tester-Realm" },
    currentSessionId = options.currentSessionId or "fixture-session",
    RegisterMessage = function() end,
  }
end

function M.degraded(reason)
  local rc = M.valid()
  rc.masterLooter = {}
  rc.fixtureReason = reason or "RC_MASTER_LOOTER_UNVERIFIABLE"
  return rc
end

function M.blocked()
  local rc = M.valid()
  rc.currentSessionId = nil
  rc.sessionID = nil
  rc.lootSessionId = nil
  return rc
end

function M.unavailable()
  return nil
end

return M
