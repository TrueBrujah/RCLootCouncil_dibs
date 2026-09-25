--[[
Module: Dibs.Wizard
Layer: Guided Setup orchestration/navigation
Purpose: Present one stepped, GM/Officer-facing configuration workflow that
navigates and composes existing systems (Installation, SetupAssistant/
Readiness, Seasons, RankRules, PreDibs, RCLootCouncil, Sync).
Non-responsibilities: It is not a second readiness engine, not a second
authorization model, and not a second ledger/governance/reconciliation
system. Every step status is derived from an existing authoritative or
readiness projection; this module owns no configuration truth of its own.
SavedVariables: None (guild-scoped). Persists only the last-viewed step index
in the existing per-character local UI-state store (Dibs.GetLocalSettings),
matching the precedent already used for developerModeEnabled.
]]

local Dibs = _G.Dibs
Dibs.Wizard = Dibs.Wizard or {}
local Wizard = Dibs.Wizard

local STEPS = {
  { id = "installation", label = "Installation" },
  { id = "guild", label = "Guild" },
  { id = "administration", label = "Administration" },
  { id = "seasons", label = "Seasons" },
  { id = "rankRules", label = "Rank Rules" },
  { id = "dibsRules", label = "Dibs Rules" },
  { id = "preDibs", label = "Pre-Dibs" },
  { id = "ledger", label = "Ledger" },
  { id = "rclootcouncil", label = "RCLootCouncil" },
  { id = "sync", label = "Synchronization" },
  { id = "review", label = "Review" },
  { id = "readiness", label = "Readiness" },
}

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, ...)
  if ok then return result end
  return nil
end

local function installationStatus()
  return Dibs.Installation and Dibs.Installation.GetStatus and Dibs.Installation.GetStatus() or {
    state = "NOT_INITIALIZED", governance = {}, legacy = {}, baseline = {}, coordinator = {},
    compatibility = {}, sync = {}, protocol = {}, technical = {},
  }
end

local function setupAssistantReport()
  return Dibs.SetupAssistant and Dibs.SetupAssistant.Evaluate and Dibs.SetupAssistant.Evaluate() or {
    status = "UNAVAILABLE", checks = {}, blockingCount = 0,
  }
end

local function findCheck(report, id)
  for _, check in ipairs(report.checks or {}) do
    if check.id == id then return check end
  end
  return nil
end

local function stepInstallation()
  local status = installationStatus()
  if not status.governance or not status.governance.ready then
    return { status = "ACTION_REQUIRED", summary = "Guild governance needs initialization." }
  end
  if status.state == "RECONCILIATION_REQUIRED" then
    return { status = "WARNING", summary = "Existing Dibs data requires review before continuing." }
  end
  if status.state == "COORDINATOR_UNAVAILABLE" or status.state == "RECOVERY_REQUIRED" or status.state == "BLOCKED" then
    return { status = "BLOCKED", summary = "Guild ledger authority requires attention." }
  end
  return { status = "READY", summary = "DIBS core and governance are initialized." }
end

local function stepGuild()
  local guildName = type(GetGuildInfo) == "function" and GetGuildInfo("player") or nil
  if not guildName or guildName == "" then
    return { status = "OPTIONAL", summary = "No guild detected; running in unguilded/character scope." }
  end
  return { status = "READY", summary = "Guild: " .. tostring(guildName) }
end

local function stepAdministration()
  local officers = call(Dibs.Permissions and Dibs.Permissions.GetAuthorizedOfficers) or {}
  local gmName, officerCount = nil, 0
  for _, entry in ipairs(officers) do
    if entry.role == "gm" then gmName = entry.playerName else officerCount = officerCount + 1 end
  end
  if not gmName then
    return { status = "WARNING", summary = "No Guild Master detected in the current roster." }
  end
  return { status = "READY", summary = string.format("GM: %s | %d officer(s) authorized.", gmName, officerCount) }
end

local function stepSeasons()
  local seasons = call(Dibs.Seasons and Dibs.Seasons.List, false) or {}
  if #seasons == 0 then
    return { status = "ACTION_REQUIRED", summary = "No season configured." }
  end
  return { status = "READY", summary = #seasons .. " season(s) configured." }
end

local function stepRankRules()
  local seasonId = call(Dibs.GetCurrentSeasonId)
  local rows = call(Dibs.RankRules and Dibs.RankRules.GetRankConfigurationSummary, seasonId) or {}
  local actionRequired, warning = 0, 0
  for _, row in ipairs(rows) do
    if row.status == "ACTION_REQUIRED" then actionRequired = actionRequired + 1
    elseif row.status == "WARNING" then warning = warning + 1 end
  end
  if actionRequired > 0 then
    return { status = "ACTION_REQUIRED", summary = actionRequired .. " rank(s) need a Dibs rule.", rows = rows }
  end
  if warning > 0 then
    return { status = "WARNING", summary = warning .. " rank(s) have pending allocation reconciliation.", rows = rows }
  end
  return { status = "READY", summary = "All active ranks have a configured rule.", rows = rows }
end

local function stepDibsRules(report)
  local check = findCheck(report, "loot_types")
  if not check then return { status = "READY", summary = "Loot type rules unavailable to check from here." } end
  if check.state == "ready" then return { status = "READY", summary = "Loot type rules are configured." } end
  if check.required ~= true then
    -- SetupAssistant does not treat this as blocking; the Wizard must defer
    -- to that readiness authority rather than being stricter than it.
    return { status = "OPTIONAL", summary = check.remediation or check.impact or "Loot type rules are not available in this context." }
  end
  return { status = "WARNING", summary = check.remediation or check.impact or "Loot type rules need review." }
end

local function stepPreDibs()
  local seasonId = call(Dibs.GetCurrentSeasonId)
  local summary = call(Dibs.PreDibs and Dibs.PreDibs.GetStatusSummary, seasonId) or {}
  if summary.publicEnabled == false then
    return { status = "OPTIONAL", summary = "Public Pre-Dibs is disabled for this guild.", detail = summary }
  end
  return {
    status = "READY",
    summary = string.format("Mode: %s | %d active, %d historical request(s).",
      tostring(summary.mode or "WILD_OPEN"), tonumber(summary.activeRequestCount) or 0, tonumber(summary.historyCount) or 0),
    detail = summary,
  }
end

local function stepLedger()
  local status = installationStatus()
  local label = ({
    READY = "Existing — Healthy", RECONCILIATION_REQUIRED = "Existing — Migration Required",
    READY_TO_INITIALIZE = "Not Initialized", NOT_INITIALIZED = "Not Initialized",
    COORDINATOR_UNAVAILABLE = "Existing — Warning", RECOVERY_REQUIRED = "Invalid / Blocked", BLOCKED = "Invalid / Blocked",
  })[status.state] or status.state
  if status.state == "READY" then
    return { status = "READY", summary = label .. ". Historical ledger data is preserved; no action required." }
  end
  if status.state == "RECONCILIATION_REQUIRED" then
    return { status = "WARNING", summary = label .. ". Review existing data before the ledger can be activated." }
  end
  if status.state == "COORDINATOR_UNAVAILABLE" or status.state == "RECOVERY_REQUIRED" or status.state == "BLOCKED" then
    return { status = "BLOCKED", summary = label }
  end
  return { status = "ACTION_REQUIRED", summary = label .. ". Complete Guild Setup to activate the guild ledger." }
end

local function stepRCLootCouncil()
  local status = call(Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus) or {}
  if status.availability == "operational" then
    return { status = "READY", summary = "RCLootCouncil detected and integration enabled.", detail = status }
  end
  if status.availability == "degraded" then
    return { status = "WARNING", summary = status.diagnostic or "RCLootCouncil integration is degraded.", detail = status }
  end
  return { status = "OPTIONAL", summary = "RCLootCouncil is not detected; DIBS runs standalone.", detail = status }
end

local function stepSync()
  local behind = call(Dibs.Sync and Dibs.Sync.IsSyncBehind) == true
  if behind then return { status = "WARNING", summary = "Synchronization is behind." } end
  return { status = "READY", summary = "Synchronization is ready." }
end

local STEP_STATUS = {
  installation = stepInstallation, guild = stepGuild, administration = stepAdministration,
  seasons = stepSeasons, rankRules = stepRankRules, preDibs = stepPreDibs, ledger = stepLedger,
  rclootcouncil = stepRCLootCouncil, sync = stepSync,
}

---@return table steps List of `{ id, label, status, summary }` for every step except review/readiness.
---@return table report The underlying `SetupAssistant.Evaluate()` report (reused, not recomputed).
local function computeSteps()
  local report = setupAssistantReport()
  local steps = {}
  for _, definition in ipairs(STEPS) do
    if definition.id == "review" or definition.id == "readiness" then
      -- computed after the loop; needs the other steps' results
    elseif definition.id == "dibsRules" then
      local computed = stepDibsRules(report)
      steps[#steps + 1] = { id = definition.id, label = definition.label, status = computed.status, summary = computed.summary, detail = computed.detail }
    else
      local computed = STEP_STATUS[definition.id]()
      steps[#steps + 1] = { id = definition.id, label = definition.label, status = computed.status, summary = computed.summary, detail = computed.detail or computed.rows }
    end
  end
  return steps, report
end

local function reviewStatus(steps)
  for _, step in ipairs(steps) do
    if step.status == "BLOCKED" then return { status = "BLOCKED", summary = "One or more sections are blocked." } end
  end
  for _, step in ipairs(steps) do
    if step.status == "ACTION_REQUIRED" or step.status == "WARNING" then
      return { status = "WARNING", summary = "One or more sections need attention." }
    end
  end
  return { status = "READY", summary = "All sections are configured." }
end

local function readinessStatus(report)
  local map = { READY_FOR_RAID = "READY", NEEDS_ATTENTION = "WARNING", UNAVAILABLE = "BLOCKED", DENIED = "BLOCKED" }
  return { status = map[report.status] or "WARNING", summary = "Readiness: " .. tostring(report.status), report = report }
end

---@param actor string|nil Reserved for future actor-scoped projections; unused today.
---@return table status `{ steps = {...}, overallState, mode }`.
function Wizard.GetStatus(actor)
  local steps, report = computeSteps()
  local review = reviewStatus(steps)
  local readiness = readinessStatus(report)
  steps[#steps + 1] = { id = "review", label = "Review", status = review.status, summary = review.summary }
  steps[#steps + 1] = { id = "readiness", label = "Readiness", status = readiness.status, summary = readiness.summary, detail = readiness.report }

  local installation = installationStatus()
  local overallState
  if not installation.governance or not installation.governance.ready then
    overallState = "NEW_INSTALLATION"
  elseif installation.state == "RECONCILIATION_REQUIRED" then
    overallState = "MIGRATION_REQUIRED"
  elseif installation.state == "COORDINATOR_UNAVAILABLE" or installation.state == "RECOVERY_REQUIRED" or installation.state == "BLOCKED" then
    overallState = "BLOCKED"
  elseif review.status == "READY" then
    -- Configuration completeness (steps 1-9) drives this label. The separate
    -- "readiness" step reflects Dibs.SetupAssistant's live-raid verdict on
    -- its own terms and is never folded back into "is the guild configured."
    overallState = "READY_FOR_RAID"
  else
    overallState = "PARTIALLY_CONFIGURED"
  end

  local mode
  if overallState == "NEW_INSTALLATION" then mode = "FIRST_TIME_SETUP"
  elseif overallState == "PARTIALLY_CONFIGURED" or overallState == "MIGRATION_REQUIRED" then mode = "COMPLETE_MISSING_CONFIGURATION"
  elseif overallState == "READY_FOR_RAID" then mode = "REVIEW_CONFIGURATION"
  else mode = "EDIT_CONFIGURATION" end

  return { steps = steps, overallState = overallState, mode = mode }
end

function Wizard.GetSteps()
  local copy = {}
  for _, definition in ipairs(STEPS) do copy[#copy + 1] = { id = definition.id, label = definition.label } end
  return copy
end

function Wizard.GetStepCount()
  return #STEPS
end

function Wizard.GetCurrentStepIndex()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings() or {}
  local index = tonumber(settings.wizardStepIndex)
  if not index or index < 1 or index > #STEPS then return 1 end
  return math.floor(index)
end

function Wizard.SetCurrentStepIndex(index)
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if not settings then return Wizard.GetCurrentStepIndex() end
  local clamped = math.max(1, math.min(math.floor(tonumber(index) or 1), #STEPS))
  settings.wizardStepIndex = clamped
  return clamped
end

return Wizard
