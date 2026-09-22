--[[
Module: Dibs.SetupAssistant
Layer: UI/domain projection
Purpose: Guide first installation through transient readiness checks and safe local validation.
Responsibilities: Compose existing readiness probes, normalize setup actions, and delegate dry-runs.
Non-responsibilities: It does not own authority, persistence, ledger state, or RCLootCouncil state.
Dependencies: Readiness, Permissions, ProtectedActions, DryRun, existing option projections.
SavedVariables: None.
SyncV2: None.
]]

local Dibs = _G.Dibs
Dibs.SetupAssistant = Dibs.SetupAssistant or {}

local SetupAssistant = Dibs.SetupAssistant
local ACTIONS = {
  ["season.create"] = true,
  ["season.set"] = true,
  ["rank.set"] = true,
  ["installation.mode.set"] = true,
  ["settings.modify"] = true,
}

local function call(fn, ...)
  if type(fn) ~= "function" then return false, nil, "UNAVAILABLE" end
  local ok, a, b = pcall(fn, ...)
  return ok, a, b
end

local function role()
  if Dibs.Permissions and Dibs.Permissions.GetGuildRole then
    local ok, value = call(Dibs.Permissions.GetGuildRole, nil)
    if ok then return value or "player" end
  end
  return "player"
end

local function isAdmin(value)
  return value == "gm" or value == "officer"
end

local function check(id, state, required, reasonCode, impact, remediation, source)
  return {
    id = id,
    state = state,
    required = required == true,
    reasonCode = reasonCode,
    impact = impact,
    remediation = remediation,
    source = source or "setup-assistant",
  }
end

local function countRules(seasonId)
  if not Dibs.RankRules or not Dibs.RankRules.GetRulesForSeason then return nil end
  local ok, rules = call(Dibs.RankRules.GetRulesForSeason, seasonId)
  if not ok or type(rules) ~= "table" then return nil end
  local count = 0
  for _ in pairs(rules) do count = count + 1 end
  return count
end

local function lootTypesAvailable()
  if not Dibs.RCOptions or type(Dibs.RCOptions.GetOptionsTable) ~= "function" then
    return nil
  end
  local ok, options = call(Dibs.RCOptions.GetOptionsTable)
  local groups = options and options.args and options.args.dibsSettings and options.args.dibsSettings.args
  local group = groups and (groups.integration or groups.officer)
  return ok and type(group) == "table" and group.args and group.args.lootTypes ~= nil or false
end

local function addReadinessChecks(report, readiness)
  local seen = {}
  for _, probe in ipairs(readiness and readiness.probes or {}) do
    local id = tostring(probe.name or "unknown")
    if id == "sync_context" then id = "channels" end
    local state = probe.state
    local reasonCode = probe.reasonCode
    local impact = probe.impact
    local remediation = probe.remediation
    -- Setup verifies installation separately from live raid readiness.
    if id == "rclootcouncil" and probe.reasonCode == "NO_RAID_CONTEXT" then
      state = "ready"
      reasonCode = "RC_LOADED_NO_RAID_CONTEXT"
      impact = "RCLootCouncil is installed and loaded; live award checks wait for a raid context."
      remediation = "Enter the intended raid and refresh to verify the live Master Looter and award profile."
    end
    if not seen[id] then
      report.checks[#report.checks + 1] = check(id, state, probe.required, reasonCode,
        impact, remediation, "readiness")
      seen[id] = true
    end
  end
  return seen
end

function SetupAssistant.Evaluate(options)
  options = type(options) == "table" and options or {}
  local actorRole = role()
  if actorRole == "player" and options.allowPlayer ~= true then
    return {
      status = "DENIED",
      actorRole = actorRole,
      checks = {},
      blockingCount = 0,
      checkedAt = time and time() or 0,
      reasonCode = "GUILD_ADMIN_REQUIRED",
    }
  end

  local report = {
    status = "UNAVAILABLE",
    actorRole = actorRole,
    checks = {},
    blockingCount = 0,
    checkedAt = time and time() or 0,
    dryRun = SetupAssistant.lastDryRun,
  }
  local readiness
  if Dibs.Readiness and Dibs.Readiness.Evaluate then
    local ok, value = call(Dibs.Readiness.Evaluate, { allowPlayer = true })
    if ok and type(value) == "table" then readiness = value end
  end
  local seen = addReadinessChecks(report, readiness)
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent and select(2, call(Dibs.Seasons.GetCurrent)) or nil
  if not season and not seen.season then
    report.checks[#report.checks + 1] = check("season", "blocked", true, "SEASON_UNAVAILABLE",
      "No active season is available.", "Create or activate a season through Officer controls.", "seasons")
  end
  if season and not seen.policy then
    local ruleCount = countRules(season.id)
    report.checks[#report.checks + 1] = check("rank_rules", ruleCount and ruleCount > 0 and "ready" or "blocked",
      true, ruleCount and ruleCount > 0 and nil or "POLICY_UNAVAILABLE",
      ruleCount and ruleCount > 0 and "Rank rules are available." or "No rank allocation policy is configured.",
      ruleCount and ruleCount > 0 and "No action required." or "Configure Rank Rules for the active season.", "rank-rules")
  end
  if not seen.channels then
    report.checks[#report.checks + 1] = check("channels", "unavailable", false, "RAID_DIBS_CHANNEL_UNAVAILABLE",
      "The optional Raid Dibs channel is not visible in this session.",
      "Join or configure the channel before relying on raid announcements.", "readiness")
  end
  local lootAvailable = lootTypesAvailable()
  report.checks[#report.checks + 1] = check("loot_types", lootAvailable == true and "ready" or "unavailable", false,
    lootAvailable == true and nil or "LOOT_TYPES_UNAVAILABLE",
    lootAvailable == true and "Loot type controls are available." or "Loot type controls are not available in this client context.",
    lootAvailable == true and "No action required." or "Open Officer Loot Rules when the configuration panel is available.", "options")

  for _, item in ipairs(report.checks) do
    if item.required and item.state ~= "ready" and item.state ~= "skipped" then
      report.blockingCount = report.blockingCount + 1
    end
  end
  if report.blockingCount > 0 then
    report.status = "NEEDS_ATTENTION"
  elseif readiness and readiness.status == "Unavailable" then
    report.status = "UNAVAILABLE"
  else
    report.status = "READY_FOR_RAID"
  end
  return report
end

function SetupAssistant.ExecuteAction(actionId, actor, payload)
  if not ACTIONS[actionId] then
    return { ok = false, reasonCode = "INVALID_SETUP_ACTION", diagnostic = "Unknown setup action." }
  end
  if type(payload) ~= "table" then
    return { ok = false, reasonCode = "INVALID_SETUP_PAYLOAD", diagnostic = "A setup payload is required." }
  end
  if not Dibs.ProtectedActions or type(Dibs.ProtectedActions.Execute) ~= "function" then
    return { ok = false, reasonCode = "PROTECTED_ACTION_UNAVAILABLE", diagnostic = "Protected setup actions are unavailable." }
  end
  payload.source = payload.source or "setup-assistant"
  return Dibs.ProtectedActions.Execute(actionId, actor, payload)
end

function SetupAssistant.RunDryRun(input, options)
  if not Dibs.DryRun or type(Dibs.DryRun.Run) ~= "function" then
    return nil, "DRY_RUN_UNAVAILABLE"
  end
  local result, reason = Dibs.DryRun.Run(input or {}, options or {})
  if result then SetupAssistant.lastDryRun = result end
  return result, reason
end

function SetupAssistant.GetLastDryRun()
  return SetupAssistant.lastDryRun
end

return SetupAssistant
