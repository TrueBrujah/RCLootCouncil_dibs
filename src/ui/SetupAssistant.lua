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

local function lootTypesAvailability()
  if not Dibs.RCOptions or type(Dibs.RCOptions.GetLootTypeOptions) ~= "function" then
    return "unavailable", "LOOT_TYPES_UNAVAILABLE"
  end
  local ok, options = call(Dibs.RCOptions.GetLootTypeOptions)
  if not ok or type(options) ~= "table" or type(options.types) ~= "table" then
    return "unavailable", "LOOT_TYPES_UNAVAILABLE"
  end
  local lootTypes = options.types
  if type(lootTypes.values) ~= "function" or type(lootTypes.get) ~= "function" or type(lootTypes.set) ~= "function" then
    return "degraded", "LOOT_TYPES_INVALID"
  end
  local valuesOK, values = call(lootTypes.values)
  if not valuesOK or type(values) ~= "table" or next(values) == nil then
    return "degraded", "LOOT_TYPES_INVALID"
  end
  return "ready"
end

local function text(key, fallback)
  local value = Dibs.L and Dibs.L[key]
  if type(value) == "string" and value ~= "" then return value end
  return fallback
end

local CHECK_PRESENTATION = {
  season = { "core", "SEASON", "SEASONS", "seasons" },
  policy = { "core", "POLICY", "RANK_RULES", "ranks" },
  rank_rules = { "core", "RANK_RULES", "RANK_RULES", "ranks" },
  authority = { "core", "AUTHORITY", "GUILD_CONFIGURATION", "installation" },
  installation = { "core", "INSTALLATION", "SETTINGS", "settings" },
  local_state = { "core", "LOCAL_STATE", "GUILD_CONFIGURATION", "installation" },
  rclootcouncil = { "rclootcouncil", "RC", "RC", "integration" },
  dib_response_projection = { "rclootcouncil", "DIB_RESPONSE", "RC", "integration" },
  raid_context = { "raid", "RAID", "REFRESH" },
  channels = { "sync", "CHANNEL", "ANNOUNCEMENTS", "announcements" },
  sync_context = { "sync", "CHANNEL", "ANNOUNCEMENTS", "announcements" },
  local_services = { "sync", "SYNC", "SYNC", "sync" },
  guild_loot_rules = { "loot", "LOOT", "LOOT_RULES", "lootTypes" },
  loot_types = { "loot", "LOOT", "LOOT_RULES", "lootTypes" },
  guild_setup = { "core", "GUILD_SETUP", "GUILD_SETUP_CHECKS", "guildSetup" },
  sync_state = { "sync", "SYNC_STATE", "SYNC", "sync" },
  raid_members = { "raid", "RAID_MEMBERS", "SYNC", "sync" },
}
local GUIDANCE_ALIASES = {
  seasons = "season", policy = "rank_rules", rankRules = "rank_rules",
  administration = "authority", local_state = "ledger", sync_context = "channels",
  guild_loot_rules = "loot_types", dibsRules = "loot_types",
  sync = "sync_state", readiness = "guild_setup",
  operationalPolicy = "operational_policy", allocationReconciliation = "allocation",
  preDibs = "pre_dibs",
}

function SetupAssistant.GetCheckPresentation(id)
  local row = CHECK_PRESENTATION[id] or { "core", "OTHER", "REFRESH" }
  return {
    section = row[1], labelKey = "SETUP_ASSISTANT_CHECK_" .. row[2],
    actionKey = "SETUP_ASSISTANT_ACTION_" .. row[3], route = row[4],
  }
end

function SetupAssistant.GetGuidance(id, reasonCode, fallback)
  if reasonCode == "NO_RAID_CONTEXT" or reasonCode == "RC_LOADED_NO_RAID_CONTEXT" then
    return text("SETUP_HELP_NO_RAID", fallback)
  end
  if reasonCode == "RC_MASTER_LOOTER_UNVERIFIABLE" then
    if type(IsInRaid) == "function" and not IsInRaid() then
      return text("SETUP_HELP_NO_RAID", fallback)
    end
    return text("SETUP_HELP_MASTER_LOOTER", fallback)
  end
  if reasonCode == "SYNC_BEHIND" or reasonCode == "GUILD_LOOT_RULES_SYNC_BEHIND" then
    return text("SETUP_HELP_SYNC_STATE", fallback)
  end
  local key = "SETUP_HELP_" .. string.upper(GUIDANCE_ALIASES[id] or id or "unknown")
  return text(key, fallback or text("SETUP_HELP_UNKNOWN",
    "Refresh the checks. If this result persists, open Diagnostics and share the reason with a guild administrator."))
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
      local projected = check(id, state, probe.required, reasonCode,
        impact, remediation, "readiness")
      projected.statusCode = probe.statusCode
      report.checks[#report.checks + 1] = projected
      seen[id] = true
    end
  end
  return seen
end

-- Guild Setup covers one-time guild configuration; Raid Readiness covers the
-- live raid context. "all" keeps the historical combined report.
local GUILD_SETUP_CHECKS = {
  season = true, policy = true, rank_rules = true, authority = true, installation = true,
  local_state = true, guild_loot_rules = true, loot_types = true, local_services = true, sync_state = true,
}
local RAID_READINESS_CHECKS = {
  raid_context = true, rclootcouncil = true, dib_response_projection = true, channels = true, raid_members = true,
  guild_setup = true, sync_state = true,
}

local function syncStateCheck()
  local behind = Dibs.Sync and Dibs.Sync.IsSyncBehind and select(2, call(Dibs.Sync.IsSyncBehind)) == true
  if not behind then
    return check("sync_state", "ready", false, nil,
      text("SETUP_ASSISTANT_SYNC_STATE_READY", "This client is synchronized with the guild."),
      text("SETUP_ASSISTANT_NO_ACTION", "No action required."), "sync")
  end
  return check("sync_state", "degraded", false, "SYNC_BEHIND",
    text("SETUP_ASSISTANT_SYNC_STATE_BEHIND", "This client is behind on guild synchronization."),
    text("SETUP_ASSISTANT_SYNC_STATE_ACTION", "Open Synchronization and use Fix synchronization."), "sync")
end

local function raidMembersCheck()
  local inRaid = type(IsInRaid) == "function" and IsInRaid() == true
  if not inRaid then
    return check("raid_members", "unavailable", false, "NO_RAID_CONTEXT",
      text("SETUP_ASSISTANT_RAID_MEMBERS_NO_RAID", "Join the raid group to check which members have DIBS."),
      text("SETUP_ASSISTANT_ACTION_REFRESH_TEXT", "Refresh after joining the raid."), "sync")
  end
  local peers = Dibs.Sync and Dibs.Sync.GetPeerStatuses and select(2, call(Dibs.Sync.GetPeerStatuses, "RAID"))
  if type(peers) ~= "table" then
    return check("raid_members", "unavailable", false, "SYNC_UNAVAILABLE",
      text("SETUP_ASSISTANT_RAID_MEMBERS_UNAVAILABLE", "Raid member addon status is unavailable."),
      text("SETUP_ASSISTANT_ACTION_REFRESH_TEXT", "Refresh after joining the raid."), "sync")
  end
  local missing, outdated, offline, total = {}, {}, 0, 0
  for _, peer in ipairs(peers) do
    if not peer.isLocal then
      total = total + 1
      if peer.addonDetected == true then
        if peer.compatibility == "Update required" then outdated[#outdated + 1] = tostring(peer.playerName) end
      elseif peer.rosterOnline == false then
        offline = offline + 1
      else
        missing[#missing + 1] = tostring(peer.playerName)
      end
    end
  end
  if #missing == 0 and #outdated == 0 then
    return check("raid_members", "ready", false, nil,
      string.format(text("SETUP_ASSISTANT_RAID_MEMBERS_READY", "All %d online raid members answered with DIBS."), total - offline),
      text("SETUP_ASSISTANT_NO_ACTION", "No action required."), "sync")
  end
  local parts = {}
  if #missing > 0 then
    parts[#parts + 1] = string.format(text("SETUP_ASSISTANT_RAID_MEMBERS_MISSING", "No DIBS response (%d): %s"),
      #missing, table.concat(missing, ", "))
  end
  if #outdated > 0 then
    parts[#parts + 1] = string.format(text("SETUP_ASSISTANT_RAID_MEMBERS_OUTDATED", "Update required (%d): %s"),
      #outdated, table.concat(outdated, ", "))
  end
  local result = check("raid_members", "degraded", false, #outdated > 0 and "RAID_ADDON_OUTDATED" or "RAID_ADDON_MISSING",
    table.concat(parts, "\n"),
    text("SETUP_ASSISTANT_RAID_MEMBERS_ACTION", "Ask these players to install or update DIBS and reload; they can still loot, but cannot see or send Dibs."), "sync")
  result.missing, result.outdated = missing, outdated
  return result
end

local function guildSetupRollup(checks)
  local blocking, attention = {}, 0
  for _, item in ipairs(checks) do
    if item.state ~= "ready" and item.state ~= "skipped" then
      if item.required then blocking[#blocking + 1] = item.id else attention = attention + 1 end
    end
  end
  if #blocking > 0 then
    return check("guild_setup", "blocked", true, "GUILD_SETUP_INCOMPLETE",
      string.format(text("SETUP_ASSISTANT_GUILD_SETUP_BLOCKED", "Guild setup is incomplete: %d required item(s) must be fixed."), #blocking),
      text("SETUP_ASSISTANT_GUILD_SETUP_ACTION", "Open Guided Setup to finish the guild configuration."), "wizard")
  end
  if attention > 0 then
    return check("guild_setup", "degraded", false, "GUILD_SETUP_ATTENTION",
      string.format(text("SETUP_ASSISTANT_GUILD_SETUP_ATTENTION", "Guild setup is usable; %d item(s) need attention."), attention),
      text("SETUP_ASSISTANT_GUILD_SETUP_ACTION", "Open Guided Setup to finish the guild configuration."), "wizard")
  end
  return check("guild_setup", "ready", true, nil,
    text("SETUP_ASSISTANT_GUILD_SETUP_READY", "Guild setup is complete."),
    text("SETUP_ASSISTANT_NO_ACTION", "No action required."), "wizard")
end

---@doc.id setup.assistant.readiness
---@doc.category setup
---@doc.since 0.6.5
---@doc.audience officer,gm
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_SETUP_ASSISTANT
---@doc.label-key DOC_SETUP_ASSISTANT_LABEL
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
  local lootState, lootReason = lootTypesAvailability()
  local scopeLabel, scopeExplanation
  if lootState == "ready" then
    scopeLabel = (Dibs.L and Dibs.L.SETUP_ASSISTANT_LOOT_LOCAL_LABEL) or "Controls available"
    local scopeKey = report.actorRole == "gm" and "SETUP_ASSISTANT_LOOT_SCOPE_GM"
      or (report.actorRole == "officer" and "SETUP_ASSISTANT_LOOT_SCOPE_OFFICER" or "SETUP_ASSISTANT_LOOT_SCOPE_GENERIC")
    scopeExplanation = (Dibs.L and Dibs.L[scopeKey])
      or "Loot Rules controls are available; guild authority is reported separately in Raid Readiness."
  end
  local lootCheck = check("loot_types", lootState, false, lootReason,
    lootState == "ready" and scopeExplanation
      or (lootState == "degraded" and ((Dibs.L and Dibs.L.SETUP_ASSISTANT_LOOT_INVALID)
        or "Loot Rules controls are present but returned invalid configuration data.")
        or ((Dibs.L and Dibs.L.SETUP_ASSISTANT_LOOT_UNAVAILABLE)
          or "Loot type controls are not available in this client context.")),
    lootState == "ready" and scopeLabel
      or (lootState == "degraded" and ((Dibs.L and Dibs.L.SETUP_ASSISTANT_LOOT_INVALID_ACTION)
        or "Review the Loot Rules configuration controls.")
        or ((Dibs.L and Dibs.L.SETUP_ASSISTANT_ACTION_LOOT_RULES) or "Open Loot Rules")),
    "options")
  if scopeLabel then
    lootCheck.scopeLabel = scopeLabel
    lootCheck.scopeExplanation = scopeExplanation
  end
  report.checks[#report.checks + 1] = lootCheck

  local scope = (options.scope == "guild" or options.scope == "raid") and options.scope or "all"
  report.scope = scope
  if scope ~= "all" then
    report.checks[#report.checks + 1] = syncStateCheck()
    local guildChecks, raidChecks = {}, {}
    for _, item in ipairs(report.checks) do
      if GUILD_SETUP_CHECKS[item.id] then guildChecks[#guildChecks + 1] = item end
      if RAID_READINESS_CHECKS[item.id] then raidChecks[#raidChecks + 1] = item end
    end
    if scope == "guild" then
      report.checks = guildChecks
    else
      table.insert(raidChecks, 1, guildSetupRollup(guildChecks))
      raidChecks[#raidChecks + 1] = raidMembersCheck()
      report.checks = raidChecks
    end
  end

  for _, item in ipairs(report.checks) do
    if item.required and item.state ~= "ready" and item.state ~= "skipped" then
      report.blockingCount = report.blockingCount + 1
    end
  end
  if report.blockingCount > 0 then
    report.status = "NEEDS_ATTENTION"
  elseif scope ~= "guild" and readiness and readiness.status == "Unavailable" then
    report.status = "UNAVAILABLE"
  elseif scope == "guild" and not readiness then
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
