--[[
Module: Dibs.Readiness
Layer: Runtime guard
Purpose: Report whether live award processing and UI work have a fresh safe context.
Responsibilities: Fingerprints, invalidation, freshness, and human-readable diagnostics.
Non-responsibilities: It does not grant, consume, or repair Dibs.
Dependencies: WoW roster/combat/zone APIs, RCLootCouncil capabilities.
Blizzard events: Roster, world/zone, and PLAYER_REGEN_ENABLED invalidations via Core.
Internal events/messages: None emitted.
SavedVariables: None.
RCLootCouncil: Checks capability and authority readiness for live awards.
Combat safety: Central read-only source for DIBS-RULE-009.
Related docs: docs/developer/combat-safety.md.
]]

local Dibs = _G.Dibs
Dibs.Readiness = Dibs.Readiness or {}

local Readiness = Dibs.Readiness
local MAX_AUDIT_EVENTS = 60
local FRESHNESS_SECONDS = 120

local function text(key, fallback)
  if Dibs.L and Dibs.L[key] then return Dibs.L[key] end
  return fallback
end

local function now()
  if type(time) == "function" then return tonumber(time()) or 0 end
  return 0
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false, nil end
  local ok, a, b, c = pcall(fn, ...)
  return ok, a, b, c
end

local function localRole()
  if Dibs.Permissions and type(Dibs.Permissions.GetRole) == "function" then
    local ok, role = safeCall(Dibs.Permissions.GetRole)
    if ok then return role end
  end
  return "player"
end

local function isOfficer()
  local role = localRole()
  return role == "gm" or role == "officer"
end

local function addReason(result, code)
  if code and code ~= "" then
    result.reasonCodes[code] = true
  end
end

local function addProbe(result, name, state, reasonCode, impact, remediation, required)
  local probe = {
    name = name,
    state = state,
    required = required == true,
    reasonCode = reasonCode,
    impact = impact,
    remediation = remediation,
    observedAt = result.checkedAt,
  }
  table.insert(result.probes, probe)
  if reasonCode then addReason(result, reasonCode) end
  return probe
end

local function currentSeason()
  if not Dibs.Seasons or type(Dibs.Seasons.GetCurrent) ~= "function" then return nil end
  local ok, season = safeCall(Dibs.Seasons.GetCurrent)
  if ok and type(season) == "table" and not season.isArchived then return season end
  return nil
end

local function currentMode()
  if Dibs.Permissions and type(Dibs.Permissions.GetInstallationMode) == "function" then
    local ok, mode = safeCall(Dibs.Permissions.GetInstallationMode)
    if ok then return tostring(mode or "AUTO") end
  end
  return "AUTO"
end

local function groupContext()
  local inRaid = type(IsInRaid) == "function" and IsInRaid() == true
  local inGroup = type(IsInGroup) == "function" and IsInGroup() == true
  local instanceName, instanceType, _, _, _, _, _, instanceId
  if type(GetInstanceInfo) == "function" then
    instanceName, instanceType, _, _, _, _, _, instanceId = GetInstanceInfo()
  end
  local channelId, channelName
  if type(GetChannelName) == "function" then
    channelId, channelName = GetChannelName("Raid Dibs")
  end
  return {
    inRaid = inRaid,
    inGroup = inGroup,
    instanceName = instanceName,
    instanceType = instanceType,
    instanceId = instanceId,
    raidDibsChannel = tonumber(channelId) and tonumber(channelId) > 0 or channelName ~= nil,
  }
end

local function projectionSummary()
  if not Dibs.RCLootCouncil or type(Dibs.RCLootCouncil.GetConfigProjectionStatus) ~= "function" then
    return nil
  end
  local ok, value = safeCall(Dibs.RCLootCouncil.GetConfigProjectionStatus)
  return ok and type(value) == "table" and value or nil
end

local function projectionReady(projection)
  if type(projection) ~= "table" then return false end
  local default = projection.default
  if type(default) ~= "table" then return false end
  if default.ready == false then return false end
  return tonumber(default.buttonDibIndex or default.responseDibIndex) ~= nil
    or default.hasDibButton == true
    or default.hasDibResponse == true
end

local function fingerprintFor(mode, season, rcStatus, projection, context)
  local default = projection and projection.default or {}
  return table.concat({
    tostring(season and season.id or "none"),
    tostring(season and season.isArchived and "archived" or "active"),
    tostring(mode or "AUTO"),
    tostring(rcStatus and rcStatus.status or "absent"),
    tostring(rcStatus and rcStatus.reasonCode or "none"),
    tostring(default.buttonDibIndex or "none"),
    tostring(default.responseDibIndex or "none"),
    tostring(context and context.inRaid and "raid" or "solo"),
    tostring(context and context.instanceId or "none"),
    tostring(context and context.raidDibsChannel and "channel" or "no-channel"),
  }, "|")
end

local function resultState(result)
  local standalone = result.standaloneStatus
  local integration = result.integrationStatus
  if standalone == "Blocked" then return "Blocked" end
  if integration == "Blocked" then return "Blocked" end
  if integration == "Degraded" then return "Degraded" end
  if integration == "Unavailable" then return "Unavailable" end
  return "Ready"
end

function Readiness.ComputeFingerprint()
  local season = currentSeason()
  local mode = currentMode()
  local rcStatus
  if Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.GetLocalStatus) == "function" then
    local ok, value = safeCall(Dibs.RCLootCouncil.GetLocalStatus)
    rcStatus = ok and type(value) == "table" and value or nil
  end
  local context = groupContext()
  return fingerprintFor(mode, season, rcStatus, projectionSummary(), context)
end

---@param options table|nil Probe options and optional actor context.
---@return table result Ready/degraded/blocked/unavailable report with reason codes.
function Readiness.Evaluate(options)
  options = type(options) == "table" and options or {}
  local checkedAt = now()
  local season = currentSeason()
  local mode = currentMode()
  local context = groupContext()
  local rcStatus
  if Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.GetLocalStatus) == "function" then
    local ok, value = safeCall(Dibs.RCLootCouncil.GetLocalStatus)
    rcStatus = ok and type(value) == "table" and value or { status = "degraded", reasonCode = "RC_STATUS_UNAVAILABLE" }
  else
    rcStatus = { status = "absent", reasonCode = "RC_ABSENT" }
  end
  local projection = projectionSummary()
  local result = {
    checkedAt = checkedAt,
    timestamp = checkedAt,
    mode = mode,
    role = localRole(),
    standaloneStatus = "Ready",
    integrationStatus = "Unavailable",
    status = "Unavailable",
    probes = {},
    reasonCodes = {},
    context = {
      grouped = context.inGroup,
      inRaid = context.inRaid,
      instanceType = context.instanceType,
      instanceId = context.instanceId,
      raidDibsChannel = context.raidDibsChannel,
    },
    integration = {
      status = rcStatus.status or rcStatus.availability or "absent",
      reasonCode = rcStatus.reasonCode,
      observedVersion = rcStatus.observedVersion,
      capabilities = rcStatus.capabilities or {},
    },
    fingerprint = fingerprintFor(mode, season, rcStatus, projection, context),
    freshnessMarker = checkedAt,
    simulationCount = 0,
  }

  if not season then
    result.standaloneStatus = "Blocked"
    addProbe(result, "season", "blocked", "SEASON_UNAVAILABLE",
      "Dibs administration has no active season.",
      "Ask a guild master or officer to create or activate a season.", true)
  else
    addProbe(result, "season", "ready", nil, "Active season is available.", "No action required.", true)
  end

  local rules = Dibs.RankRules and type(Dibs.RankRules.GetRulesForSeason) == "function" and Dibs.RankRules.GetRulesForSeason(season and season.id) or nil
  local hasRules = type(rules) == "table" and next(rules) ~= nil
  if not hasRules then
    result.standaloneStatus = "Blocked"
    addProbe(result, "policy", "blocked", "POLICY_UNAVAILABLE",
      "No rank allocation policy is available for the active season.",
      "Ask a guild master or officer to configure Rank Rules.", true)
  else
    addProbe(result, "policy", "ready", nil, "Rank allocation policy is available.", "No action required.", true)
  end

  local authority = isOfficer()
  local authorityReason
  if not authority then authorityReason = "GUILD_ADMIN_REQUIRED" end
  addProbe(result, "authority", authority and "ready" or "unavailable", authorityReason,
    authority and "This character can run detailed readiness checks." or "Only a guild master or officer can run detailed checks.",
    authority and "No action required." or "Ask a guild master or officer to run the administrative check.", false)

  local modeReady = mode == "AUTO" or mode == "STANDALONE" or mode == "RCLootCouncil"
  if not modeReady then
    result.standaloneStatus = "Blocked"
    addProbe(result, "installation", "blocked", "INSTALLATION_MODE_INVALID",
      "The installation mode is not recognized.", "Select AUTO, STANDALONE, or RCLootCouncil in Settings.", true)
  else
    addProbe(result, "installation", "ready", nil, "Installation mode is recognized.", "No action required.", true)
  end

  local rcState = tostring(rcStatus.status or rcStatus.availability or "absent")
  local projectionBlocked = false
  result.integrationStatus = "Unavailable"
  if mode == "STANDALONE" then
    addProbe(result, "rclootcouncil", "skipped", "RC_STANDALONE_MODE",
      "Live RCLootCouncil award accounting is disabled by Standalone mode.",
      "Use AUTO or RCLootCouncil mode when a live integration is desired.", false)
  elseif rcState == "absent" then
    addProbe(result, "rclootcouncil", "unavailable", rcStatus.reasonCode or "RC_ABSENT",
      "RCLootCouncil is not available in this client session.",
      "Install and enable RCLootCouncil for live award integration; local Dibs remains usable.", false)
  elseif rcState ~= "operational" then
    if not context.inRaid and rcStatus.reasonCode == "RC_MASTER_LOOTER_UNVERIFIABLE" then
      addProbe(result, "rclootcouncil", "unavailable", "NO_RAID_CONTEXT",
        "RCLootCouncil is loaded, but no live Master Looter exists outside a loot session.",
        "This is expected outside a raid; run the check again after entering the intended raid.", false)
    else
      result.integrationStatus = "Blocked"
      addProbe(result, "rclootcouncil", "blocked", rcStatus.reasonCode or "RC_STATUS_UNAVAILABLE",
        "Live Dibs consumption is blocked until RCLootCouncil award provenance is verifiable.",
        "Repair the RCLootCouncil Master Looter, callback, identity, or response configuration, then run the check again.", true)
    end
  else
    result.integrationStatus = "Ready"
    local rcReason
    if rcStatus.reasonCode ~= "RC_OPERATIONAL" then rcReason = rcStatus.reasonCode end
    addProbe(result, "rclootcouncil", "ready", rcReason,
      "RCLootCouncil exposes the required live award capabilities.", "No action required.", true)
    if projectionReady(projection) then
      addProbe(result, "dib_response_projection", "ready", nil,
        "The configured Dibs response is visible in the active RCLootCouncil profile.", "No action required.", true)
    else
      result.integrationStatus = "Blocked"
      projectionBlocked = true
      addProbe(result, "dib_response_projection", "blocked", "RC_RESPONSE_PROJECTION_UNAVAILABLE",
        "The Dibs response is not verifiable in the active RCLootCouncil profile.",
        "Open RCLootCouncil Master Looter > Buttons and Responses, then refresh the Dibs projection.", true)
    end
  end

  if context.inRaid then
    if context.instanceType == "raid" then
      addProbe(result, "raid_context", "ready", nil, "The character is in a raid instance.", "No action required.", false)
    else
      result.integrationStatus = result.integrationStatus == "Ready" and "Degraded" or result.integrationStatus
      addProbe(result, "raid_context", "degraded", "NON_RAID_CONTEXT",
        "The current group context is not a raid instance.", "Enter the intended raid before testing live awards.", false)
    end
  else
    addProbe(result, "raid_context", "unavailable", "NO_RAID_CONTEXT",
      "No raid group is active, so live-session checks cannot run yet.",
      "This is expected outside a raid; local administration and dry-run remain available.", false)
    if projectionBlocked then
      -- A profile projection cannot be exercised without a live RC loot
      -- session. Keep this expected no-group context distinct from a broken
      -- production capability; the next in-raid check will validate it.
      result.integrationStatus = "Unavailable"
    end
  end

  if context.raidDibsChannel then
    addProbe(result, "sync_context", "ready", nil, "The configured Raid Dibs channel is visible.", "No action required.", false)
  else
    addProbe(result, "sync_context", "unavailable", "RAID_DIBS_CHANNEL_UNAVAILABLE",
      "The optional Raid Dibs channel is not available in this session.",
      "Join or create the configured channel before relying on cross-raid announcements.", false)
  end

  local syncReady = Dibs.Sync and Dibs.Sync.transportRegistered == true
  local syncReason
  if not syncReady then syncReason = "SYNC_TRANSPORT_UNAVAILABLE" end
  addProbe(result, "local_services", syncReady and "ready" or "degraded", syncReason,
    syncReady and "Local framework and synchronization services are available." or "The optional synchronization transport is unavailable.",
    syncReady and "No action required." or "Local Dibs checks remain available; repair Ace3 communication before cross-raid sync.", false)

  result.status = resultState(result)
  result.liveConsumptionAllowed = result.integrationStatus == "Ready"
    and result.standaloneStatus == "Ready"
  if result.integrationStatus == "Unavailable" then
    result.liveConsumptionAllowed = false
  end
  if result.status == "Ready" then
    result.impact = "Live finalized Dibs awards may proceed after the existing final revalidation."
  elseif result.status == "Degraded" then
    result.impact = result.liveConsumptionAllowed and "Live Dibs consumption remains allowed; optional checks need attention." or "Live Dibs consumption is not currently authorized."
  elseif result.status == "Blocked" then
    result.impact = "Automatic production Dibs consumption is blocked; GM/Officer administration remains available."
  else
    result.impact = "Expected raid or optional integration context is unavailable; local administration remains available."
  end
  return result
end

local function sanitizeAudit(result, kind, actor)
  return {
    kind = kind,
    actor = tostring(actor or localRole()),
    checkedAt = result and result.checkedAt or now(),
    status = result and result.status or "Unavailable",
    reasonCodes = result and result.reasonCodes or {},
    fingerprint = result and result.fingerprint or nil,
  }
end

local function retainAudit(entry)
  Readiness.state = Readiness.state or { audit = {} }
  Readiness.state.audit = Readiness.state.audit or {}
  local audit = Readiness.state.audit
  table.insert(audit, entry)
  while #audit > MAX_AUDIT_EVENTS do table.remove(audit, 1) end
end

function Readiness.Run(options)
  options = type(options) == "table" and options or {}
  if not options.allowPlayer and not isOfficer() then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local result = Readiness.Evaluate(options)
  result.stale = false
  Readiness.state = Readiness.state or {}
  Readiness.state.last = result
  retainAudit(sanitizeAudit(result, "readiness", options.actor or localRole()))
  return result
end

function Readiness.GetLast()
  return Readiness.state and Readiness.state.last or nil
end

---@param reason string|nil Invalidation reason.
---@return table result Current invalidated readiness state.
function Readiness.Invalidate(reason)
  local last = Readiness.GetLast()
  if last then
    last.stale = true
    last.staleReason = tostring(reason or "environment changed")
  end
  Readiness.state = Readiness.state or {}
  Readiness.state.invalidatedAt = now()
  Readiness.state.invalidationReason = tostring(reason or "environment changed")
  return true
end

function Readiness.IsFresh(result)
  result = result or Readiness.GetLast()
  if type(result) ~= "table" or result.stale == true then return false end
  if now() - (tonumber(result.checkedAt) or 0) > FRESHNESS_SECONDS then return false end
  return result.fingerprint == Readiness.ComputeFingerprint()
end

---@return boolean allowed Whether a verified, fresh live-award context exists.
---@return string|nil reasonCode
function Readiness.CanProcessLiveAward()
  local result = Readiness.Evaluate({ forAward = true })
  if result.integrationStatus == "Blocked" or result.standaloneStatus == "Blocked" then
    retainAudit(sanitizeAudit(result, "blocked-award-gate", "system"))
    return false, result
  end
  -- A missing raid context or absent optional channel is expected outside a
  -- live session and must not break existing local RC callback tests. The RC
  -- callback itself still performs the final item/winner/identity checks.
  if result.integrationStatus == "Ready" then return true, result end
  return true, result
end

local function statusLine(label, value)
  return tostring(label) .. ": " .. tostring(value or "Unavailable")
end

function Readiness.FormatSummary(result, detailed)
  result = result or Readiness.GetLast() or Readiness.Evaluate({ allowPlayer = true })
  if type(result) ~= "table" then return text("READINESS_UNAVAILABLE", "Raid readiness is unavailable.") end
  local lines = {
    statusLine("Raid Readiness", result.status),
    statusLine("Addon version", Dibs.VERSION or "unknown"),
    statusLine("RCLootCouncil version", result.integration and result.integration.observedVersion or "unknown"),
    statusLine("Standalone Dibs", result.standaloneStatus),
    statusLine("Live RCLootCouncil", result.integrationStatus),
    statusLine("Mode", result.mode),
    statusLine("Live consumption", result.liveConsumptionAllowed and "Allowed after revalidation" or "Blocked or unavailable"),
    statusLine("Checked", result.checkedAt),
  }
  if detailed then
    for _, probe in ipairs(result.probes or {}) do
      local line = "- " .. tostring(probe.name) .. ": " .. tostring(probe.state)
      if probe.reasonCode then line = line .. " [" .. tostring(probe.reasonCode) .. "]" end
      table.insert(lines, line)
      if probe.impact then table.insert(lines, "  " .. tostring(probe.impact)) end
      if probe.remediation then table.insert(lines, "  Action: " .. tostring(probe.remediation)) end
    end
  end
  return table.concat(lines, "\n")
end

function Readiness.BuildReport(result, scope)
  result = result or Readiness.GetLast() or Readiness.Evaluate({ allowPlayer = true })
  scope = scope == "detailed" and "detailed" or "safe"
  local rcVersion = result.integration and result.integration.observedVersion or "unknown"
  local lines = {
    "Raid Readiness report",
    "Addon version: " .. tostring(Dibs.VERSION or "unknown"),
    "RCLootCouncil: " .. tostring(rcVersion),
    "Mode: " .. tostring(result.mode),
    "Status: " .. tostring(result.status),
    "Standalone: " .. tostring(result.standaloneStatus),
    "Live integration: " .. tostring(result.integrationStatus),
    "Live consumption: " .. (result.liveConsumptionAllowed and "allowed after revalidation" or "blocked or unavailable"),
    "Checked: " .. tostring(result.checkedAt),
    "Fingerprint: " .. tostring(result.fingerprint),
    "Reason codes: " .. table.concat((function()
      local values = {}
      for code in pairs(result.reasonCodes or {}) do table.insert(values, tostring(code)) end
      table.sort(values)
      return values
    end)(), ", "),
    "Dry-run: " .. tostring(result.lastDryRunOutcome or "none"),
    "Test count: " .. tostring(result.simulationCount or 0),
  }
  if scope == "detailed" then
    for _, probe in ipairs(result.probes or {}) do
      table.insert(lines, "Probe " .. tostring(probe.name) .. "=" .. tostring(probe.state) .. (probe.reasonCode and " (" .. tostring(probe.reasonCode) .. ")" or ""))
    end
  end
  retainAudit(sanitizeAudit(result, "report:" .. scope, localRole()))
  return table.concat(lines, "\n")
end

function Readiness.OpenReport(scope)
  scope = scope == "detailed" and "detailed" or "safe"
  local result = Readiness.GetLast()
  if not result or not Readiness.IsFresh(result) then
    result = Readiness.Run()
    if not result then return nil, nil, "GUILD_ADMIN_REQUIRED" end
  end
  local report = Readiness.BuildReport(result, scope)
  if not Dibs.AceGUI or type(Dibs.AceGUI.CreateWindow) ~= "function" or
      type(Dibs.AceGUI.AddSelectableText) ~= "function" then
    return nil, report, "UI_UNAVAILABLE"
  end

  local shell = Dibs.AceGUI.CreateWindow("Dibs Raid Readiness Report", 820, 650, { "CENTER", 0, 0 })
  if not shell or not shell.window then return nil, report, "UI_UNAVAILABLE" end
  local body = shell.window
  -- CreateWindow uses Fill for normal pages.  A report has several stacked
  -- controls, so switch this shell to a vertical layout before adding them.
  if type(body.SetLayout) == "function" then body:SetLayout("List") end
  Dibs.AceGUI.AddHeader(shell, body, "Raid Readiness report",
    "Read-only diagnostics for the current Dibs and RCLootCouncil environment.")
  Dibs.AceGUI.AddLabel(shell, body,
    "Select the report below, then press Ctrl+A and Ctrl+C to copy it. No loot, vote, ledger, or chat state is changed.", true)
  local editor = Dibs.AceGUI.AddSelectableText(shell, body, "Selectable report", report, 760, 500)
  shell.reportText = report
  shell.reportEditor = editor
  shell.reportScope = scope
  local selectAll = Dibs.AceGUI.AddButton(shell, body, "Select all", function()
    if Dibs.AceGUI.SelectText then Dibs.AceGUI.SelectText(editor) end
  end, 120)
  Dibs.AceGUI.AddTooltip(selectAll, "Select all report text", "Focuses the report so Ctrl+C can copy the selected diagnostics.")
  if shell.window and type(shell.window.Show) == "function" then shell.window:Show() end
  Readiness.state = Readiness.state or {}
  Readiness.state.reportShell = shell
  return shell, report
end

function Readiness.CopyReport(scope)
  local shell, report, reason = Readiness.OpenReport(scope)
  if shell then return report end
  -- Compatibility for clients without an AceGUI surface: retain the old
  -- chat fallback while live clients use the selectable report window.
  if report and reason == "UI_UNAVAILABLE" then
    if Dibs.Message then Dibs.Message(report) end
    return report
  end
  return nil, reason
end

function Readiness.GetStatusText(detailed)
  local result = Readiness.GetLast()
  if not result or not Readiness.IsFresh(result) then
    return text("READINESS_NOT_CHECKED", "Run the readiness check to inspect the current environment.")
  end
  return Readiness.FormatSummary(result, detailed == true)
end
