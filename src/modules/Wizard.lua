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
SavedVariables: None (guild-authoritative). Keeps allowlisted resumable form
and navigation state per guild in the existing character-local UI store.
]]

local Dibs = _G.Dibs
Dibs.Wizard = Dibs.Wizard or {}
local Wizard = Dibs.Wizard

local TURNKEY_STAGES = { "choose", "configure", "verify" }
local PROFILE_ORDER = { "progression", "broad", "custom" }
local PROFILE_DEFINITIONS = {
  progression = {
    presetKey = "progression",
    labelKey = "WIZARD_PROFILE_PROGRESSION",
    summaryKey = "WIZARD_PROFILE_PROGRESSION_SUMMARY",
    benefitKeys = { "WIZARD_PROFILE_PROGRESSION_BENEFIT_1", "WIZARD_PROFILE_PROGRESSION_BENEFIT_2" },
    changeKeys = { "WIZARD_CHANGE_INITIALIZE", "WIZARD_CHANGE_PROGRESSION_RULES", "WIZARD_CHANGE_POLICY" },
  },
  broad = {
    presetKey = "broad",
    labelKey = "WIZARD_PROFILE_BROAD",
    summaryKey = "WIZARD_PROFILE_BROAD_SUMMARY",
    benefitKeys = { "WIZARD_PROFILE_BROAD_BENEFIT_1", "WIZARD_PROFILE_BROAD_BENEFIT_2" },
    changeKeys = { "WIZARD_CHANGE_INITIALIZE", "WIZARD_CHANGE_BROAD_RULES", "WIZARD_CHANGE_POLICY" },
  },
  custom = {
    labelKey = "WIZARD_PROFILE_CUSTOM",
    summaryKey = "WIZARD_PROFILE_CUSTOM_SUMMARY",
    benefitKeys = { "WIZARD_PROFILE_CUSTOM_BENEFIT_1", "WIZARD_PROFILE_CUSTOM_BENEFIT_2" },
    changeKeys = {},
  },
}
local PRESERVED_KEYS = {
  "WIZARD_PRESERVE_LEDGER", "WIZARD_PRESERVE_HISTORY", "WIZARD_PRESERVE_EXISTING",
}

local STEPS = {
  { id = "installation", label = "Installation" },
  { id = "guild", label = "Guild" },
  { id = "administration", label = "Administration" },
  { id = "seasons", label = "Seasons" },
  { id = "rankRules", label = "Rank Rules" },
  { id = "allocationReconciliation", label = "Allocation Reconciliation" },
  { id = "dibsRules", label = "Dibs Rules" },
  { id = "preDibs", label = "Pre-Dibs" },
  { id = "ledger", label = "Ledger" },
  { id = "rclootcouncil", label = "RCLootCouncil" },
  { id = "sync", label = "Synchronization" },
  { id = "operationalPolicy", label = "Guild Policy" },
  { id = "review", label = "Review" },
  { id = "readiness", label = "Guild Setup Checks" },
}

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, ...)
  if ok then return result end
  return nil
end

local function text(key, fallback)
  return (Dibs.L and Dibs.L[key]) or fallback or key
end

local function copy(value)
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

local function localizedList(keys)
  local values = {}
  for _, key in ipairs(keys or {}) do values[#values + 1] = text(key) end
  return values
end

local function buildProfile(id)
  local definition = PROFILE_DEFINITIONS[id]
  if not definition then return nil end
  return {
    id = id,
    presetKey = definition.presetKey,
    label = text(definition.labelKey, id),
    summary = text(definition.summaryKey),
    benefits = localizedList(definition.benefitKeys),
    changes = localizedList(definition.changeKeys),
    preserves = localizedList(PRESERVED_KEYS),
  }
end

local function profileMatches(profileId)
  local definition = PROFILE_DEFINITIONS[profileId]
  if not definition or not definition.presetKey then return false end
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  local allowed = db.settings and db.settings.dibAllowedTypes or {}
  local expected = profileId == "progression"
    and { TOKEN = true, TOKEN_SET = true }
    or { TOKEN = true, TOKEN_SET = true, MOUNTS = true, PETS = true, RECIPE = true, OTHER = true }
  for _, key in ipairs({ "default", "TOKEN", "TOKEN_SET", "MOUNTS", "PETS", "RECIPE", "DECOR", "OTHER" }) do
    if (allowed[key] == true) ~= (expected[key] == true) then return false end
  end
  return true
end

local function installationStatus(dbOverride)
  if Dibs.Installation and Dibs.Installation.GetStatus then
    return Dibs.Installation.GetStatus(nil, dbOverride)
  end
  return {
    state = "NOT_INITIALIZED", governance = {}, legacy = {}, baseline = {}, coordinator = {},
    compatibility = {}, sync = {}, protocol = {}, technical = {},
  }
end

local function setupAssistantReport(dbOverride)
  -- Wizard has its own Sync step, so avoid Setup Assistant's duplicate optional
  -- sync probe while retaining its full guild-readiness verdict.
  return Dibs.SetupAssistant and Dibs.SetupAssistant.Evaluate
    and Dibs.SetupAssistant.Evaluate({ scope = "guild", includeSyncState = false, db = dbOverride }) or {
    status = "UNAVAILABLE", checks = {}, blockingCount = 0,
  }
end

local function findCheck(report, id)
  for _, check in ipairs(report.checks or {}) do
    if check.id == id then return check end
  end
  return nil
end

local function stepInstallation(status)
  status = status or installationStatus()
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

local function initialOperationalPolicyValues(seasons)
  local preDibModes = {}
  seasons = type(seasons) == "table" and seasons or call(Dibs.Seasons and Dibs.Seasons.List, false) or {}
  for _, season in ipairs(seasons) do
    if season.id ~= nil then
      local mode = call(Dibs.PreDibs and Dibs.PreDibs.GetModePolicy, season.id)
      preDibModes[tostring(season.id)] = mode and mode.mode or "WILD_OPEN"
    end
  end
  local channels = call(Dibs.PreDibs and Dibs.PreDibs.GetAnnouncementSettings) or {}
  return {
    allowPublicPreDibs = call(Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled) ~= false,
    preDibModes = preDibModes,
    announcementChannels = {
      publicChannel = channels.publicChannel or "GUILD",
      officerChannel = channels.officerChannel or "OFFICER",
    },
    modules = call(Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleValues) or {},
  }
end

local function stepOperationalPolicy(_, _, seasons, policySummary, dbOverride)
  local policy = Dibs.OperationalPolicy
  local state = policySummary
  if type(state) ~= "table" or type(state.status) ~= "string" then
    state = call(policy and policy.GetState) or {}
  end
  if state.status == "POLICY_ADOPTED" then
    return { status = "READY", summary = "Guild Policy is adopted at revision " .. tostring(state.policyRevision) .. "." }
  end
  local governanceStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  local governance = call(Dibs.Governance and Dibs.Governance.GetInstallationSummary, dbOverride) or {}
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "governance-status-summary", governanceStartedAt)
  end
  if governance.status ~= "GOVERNANCE_ADOPTED" then
    return { status = "BLOCKED", summary = "Initialize Guild Configuration before adopting Guild Policy." }
  end
  if call(Dibs.Permissions and Dibs.Permissions.IsGM) ~= true then
    return { status = "WARNING", summary = "Waiting for the Guild Master to review and adopt Guild Policy." }
  end
  return {
    status = "ACTION_REQUIRED",
    summary = "Review the local settings below, then explicitly adopt Guild Policy.",
    detail = initialOperationalPolicyValues(seasons),
  }
end

local function stepAdministration(dbOverride)
  local officersStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  local officers = call(Dibs.Permissions and Dibs.Permissions.GetAuthorizedOfficers, dbOverride) or {}
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "authorized-officer-read", officersStartedAt)
  end
  local gmName, officerCount = nil, 0
  for _, entry in ipairs(officers) do
    if entry.role == "gm" then gmName = entry.playerName else officerCount = officerCount + 1 end
  end
  if not gmName then
    return { status = "WARNING", summary = "No Guild Master detected in the current roster." }
  end
  return { status = "READY", summary = string.format("GM: %s | %d officer(s) authorized.", gmName, officerCount) }
end

local function stepSeasons(_, _, seasons)
  seasons = type(seasons) == "table" and seasons or call(Dibs.Seasons and Dibs.Seasons.List, false) or {}
  if #seasons == 0 then
    return { status = "ACTION_REQUIRED", summary = "No season configured." }
  end
  return { status = "READY", summary = #seasons .. " season(s) configured." }
end

local function stepRankRules(seasonId, rows, dbOverride, syncBehind)
  seasonId = seasonId or call(Dibs.GetCurrentSeasonId, dbOverride)
  rows = rows or call(Dibs.RankRules and Dibs.RankRules.GetRankConfigurationSummary, seasonId, dbOverride)
  if type(rows) ~= "table" then
    return { status = "WARNING", summary = "Guild rank configuration cannot be verified." }
  end
  local catalog = call(Dibs.Seasons and Dibs.Seasons.GetCatalogState, dbOverride) or {}
  local revision = tonumber(catalog.catalogRevision) or 0
  local record = revision > 0 and call(Dibs.Seasons and Dibs.Seasons.GetCatalogRecord, revision, dbOverride) or nil
  local publishedRules = record and record.rankRules and record.rankRules[tostring(seasonId)]
  local currentRules = call(Dibs.RankRules and Dibs.RankRules.GetRulesForSeason, seasonId, dbOverride) or {}
  local currentHash = Dibs.Sync and Dibs.Sync.CalculateContentHash and Dibs.Sync.CalculateContentHash(currentRules)
  local publishedHash = publishedRules and Dibs.Sync and Dibs.Sync.CalculateContentHash
    and Dibs.Sync.CalculateContentHash(publishedRules)
  if revision < 1 or not record or not publishedRules or currentHash ~= publishedHash then
    return { status = "ACTION_REQUIRED", summary = "Rank Rules are not published in the current SEASON_CATALOG revision.", rows = rows }
  end
  local actionRequired, warning, affected = 0, 0, {}
  for _, row in ipairs(rows) do
    if row.status == "ACTION_REQUIRED" then actionRequired = actionRequired + 1
    elseif row.status == "WARNING" then warning = warning + 1
    elseif row.status ~= "READY" and row.status ~= "OPTIONAL" then warning = warning + 1 end
    if row.status ~= "READY" and row.status ~= "OPTIONAL" then
      affected[#affected + 1] = tostring(row.rankName or ("Rank " .. tostring(row.rankIndex)))
    end
  end
  if actionRequired > 0 then
    return { status = "ACTION_REQUIRED", summary = "Rank Rules need configuration: " .. table.concat(affected, ", ") .. ".", rows = rows }
  end
  if warning > 0 then
    return { status = "WARNING", summary = "Rank Rules need review: " .. table.concat(affected, ", ") .. ".", rows = rows }
  end
  if syncBehind == nil and Dibs.Sync and Dibs.Sync.IsSyncBehind then
    syncBehind = Dibs.Sync.IsSyncBehind()
  end
  if syncBehind == true then
    return { status = "WARNING", summary = "Rank Rules are published, but SEASON_CATALOG synchronization is behind. Revision " .. tostring(revision) .. ".", rows = rows }
  end
  if #rows == 0 then
    return { status = "READY", summary = "Rank Rules are published through SEASON_CATALOG revision " .. tostring(revision) .. "; no current rank rows need configuration.", rows = rows }
  end
  return { status = "READY", summary = "Rank Rules are configured and synchronized through SEASON_CATALOG revision " .. tostring(revision) .. ".", rows = rows }
end

local function stepAllocationReconciliation(hasConfiguredSeason)
  if hasConfiguredSeason ~= true then
    return { status = "OPTIONAL", summary = text("WIZARD_ALLOCATION_RECONCILIATION_DEFERRED",
      "Create the first seasonal raid roster before reconciling member allocations.") }
  end
  return { status = "OPTIONAL", summary = text("WIZARD_SEASONAL_RECONCILIATION_PENDING",
    "Seasonal reconciliation is not available yet; it must use only approved participants in the active season.") }
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

local function stepPreDibs(_, activeLedgerId, seasonId, policySummary)
  seasonId = seasonId or call(Dibs.GetCurrentSeasonId)
  local summaryStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local summary = call(Dibs.PreDibs and Dibs.PreDibs.GetStatusSummary, seasonId, activeLedgerId, policySummary) or {}
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "predibs-status-summary", summaryStartedAt)
  end
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

local function stepLedger(status)
  status = status or installationStatus()
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

local function stepSync(syncStatus, behind)
  if type(syncStatus) ~= "table" or type(syncStatus.state) ~= "string" then
    return { status = "WARNING", summary = "Synchronization status is unavailable." }
  end
  if syncStatus.state == "SYNC_UNAVAILABLE" then
    return { status = "WARNING", summary = behind == true
      and "Synchronization transport is unavailable and this client is behind."
      or "Synchronization transport is unavailable." }
  end
  if behind == true or syncStatus.syncBehind == true or syncStatus.state == "SYNC_BEHIND" then
    return { status = "WARNING", summary = "Synchronization is behind." }
  end
  if syncStatus.state == "SYNC_READY" and (behind == false or syncStatus.syncBehind == false) then
    return { status = "READY", summary = "Synchronization is ready." }
  end
  return { status = "WARNING", summary = "Synchronization status needs review." }
end

local STEP_STATUS = {
  installation = stepInstallation, guild = stepGuild, administration = stepAdministration,
  seasons = stepSeasons, rankRules = stepRankRules, allocationReconciliation = stepAllocationReconciliation,
  preDibs = stepPreDibs, ledger = stepLedger, operationalPolicy = stepOperationalPolicy,
  rclootcouncil = stepRCLootCouncil, sync = stepSync,
}

---@return table steps List of `{ id, label, status, summary }` for every step except review/readiness.
---@return table report The underlying `SetupAssistant.Evaluate()` report (reused, not recomputed).
local function computeSteps(dbOverride)
  local installationStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local installation, activeLedgerId = installationStatus(dbOverride)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "installation-status", installationStartedAt)
  end
  local seasonsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local seasons = call(Dibs.Seasons and Dibs.Seasons.List, false, dbOverride) or {}
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "season-list", seasonsStartedAt)
  end
  local assistantStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local report = setupAssistantReport(dbOverride)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "setup-assistant", assistantStartedAt)
  end
  local steps = {}
  local seasonId, rankRows = call(Dibs.GetCurrentSeasonId, dbOverride), nil
  local hasConfiguredSeason = call(Dibs.SeasonalRoster and Dibs.SeasonalRoster.HasConfiguredSeason, dbOverride)
  local policySummaryStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local policySummary = call(Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetPreDibSummary,
    seasonId, activeLedgerId, dbOverride)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "operational-policy-summary", policySummaryStartedAt)
  end
  local syncStatusStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local getSyncStatus = Dibs.Sync and (Dibs.Sync.GetStatusSummary or Dibs.Sync.GetStatus)
  local syncStatus = call(getSyncStatus)
  local syncBehind
  if type(syncStatus) == "table" and type(syncStatus.syncBehind) == "boolean"
    and syncStatus.state ~= "SYNC_UNAVAILABLE" then
    syncBehind = syncStatus.syncBehind
  else
    syncBehind = call(Dibs.Sync and Dibs.Sync.IsSyncBehind)
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "sync-status", syncStatusStartedAt)
  end
  for _, definition in ipairs(STEPS) do
    if definition.id == "review" or definition.id == "readiness" then
      -- computed after the loop; needs the other steps' results
    elseif definition.id == "rankRules" then
      local rankSummaryStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
      rankRows = call(Dibs.RankRules and Dibs.RankRules.GetRankConfigurationSummary, seasonId, dbOverride)
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Wizard data", "rank-configuration-summary", rankSummaryStartedAt)
      end
      local computed = stepRankRules(seasonId, rankRows, dbOverride, syncBehind)
      steps[#steps + 1] = { id = definition.id, label = definition.label, status = computed.status, summary = computed.summary, detail = computed.detail or computed.rows }
    elseif definition.id == "allocationReconciliation" then
      local computed = stepAllocationReconciliation(hasConfiguredSeason)
      steps[#steps + 1] = { id = definition.id, label = definition.label, status = computed.status, summary = computed.summary, detail = computed.detail or computed.rows }
    elseif definition.id == "dibsRules" then
      local computed = stepDibsRules(report)
      steps[#steps + 1] = { id = definition.id, label = definition.label, status = computed.status, summary = computed.summary, detail = computed.detail }
    else
      local stepStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
      local computed
      if definition.id == "preDibs" then
        -- Keep the season ID distinct from the season list passed to the other steps.
        computed = STEP_STATUS[definition.id](installation, activeLedgerId, seasonId, policySummary)
      elseif definition.id == "sync" then
        computed = STEP_STATUS[definition.id](syncStatus, syncBehind)
      elseif definition.id == "administration" then
        computed = STEP_STATUS[definition.id](dbOverride)
      elseif definition.id == "operationalPolicy" then
        computed = STEP_STATUS[definition.id](installation, activeLedgerId, seasons, policySummary, dbOverride)
      else
        computed = STEP_STATUS[definition.id](installation, activeLedgerId, seasons, policySummary)
      end
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Wizard data", "step-evaluation", stepStartedAt)
        Dibs.UIRenderStats.Record("Wizard step", definition.id, stepStartedAt)
      end
      steps[#steps + 1] = { id = definition.id, label = definition.label, status = computed.status, summary = computed.summary, detail = computed.detail or computed.rows }
    end
  end
  return steps, report, installation
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
  return { status = map[report.status] or "BLOCKED", summary = "Readiness: " .. tostring(report.status), report = report }
end

---@param actor string|nil Reserved for future actor-scoped projections; unused today.
---@return table status `{ steps = {...}, overallState, mode }`.
function Wizard.GetStatus(actor, dbOverride)
  local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local steps, report, installation = computeSteps(dbOverride)
  local review = reviewStatus(steps)
  local readiness = readinessStatus(report)
  steps[#steps + 1] = { id = "review", label = "Review", status = review.status, summary = review.summary }
  steps[#steps + 1] = { id = "readiness", label = "Guild Setup Checks", status = readiness.status, summary = readiness.summary, detail = readiness.report }

  local overallState
  if not installation.governance or not installation.governance.ready then
    overallState = "NEW_INSTALLATION"
  elseif installation.state == "RECONCILIATION_REQUIRED" then
    overallState = "MIGRATION_REQUIRED"
  elseif installation.state == "COORDINATOR_UNAVAILABLE" or installation.state == "RECOVERY_REQUIRED" or installation.state == "BLOCKED" then
    overallState = "BLOCKED"
  elseif readiness.status ~= "READY" then
    overallState = "BLOCKED"
  elseif review.status == "READY" and readiness.status == "READY" then
    overallState = "READY_FOR_RAID"
  else
    overallState = "PARTIALLY_CONFIGURED"
  end

  local mode
  if overallState == "NEW_INSTALLATION" then mode = "FIRST_TIME_SETUP"
  elseif overallState == "PARTIALLY_CONFIGURED" or overallState == "MIGRATION_REQUIRED" then mode = "COMPLETE_MISSING_CONFIGURATION"
  elseif overallState == "READY_FOR_RAID" then mode = "REVIEW_CONFIGURATION"
  else mode = "EDIT_CONFIGURATION" end

  local status = { steps = steps, overallState = overallState, mode = mode }
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "status", renderStartedAt)
  end
  return status, installation
end

-- Navigation is a read-only projection, not an authorization or readiness
-- engine. Use compact installation/configuration snapshots; opening a page
-- must not re-run SetupAssistant or per-member allocation reconciliation.
function Wizard.GetNavigationAccess(actor, dbOverride)
  local db = type(dbOverride) == "table" and dbOverride
    or (Dibs.GetDB and Dibs.GetDB() or {})
  local install = call(Dibs.Installation and Dibs.Installation.GetStatus, actor, db) or {}
  local foundationReady = type(install.governance) == "table" and install.governance.ready == true
    and type(install.baseline) == "table" and install.baseline.ready == true
  local catalog = type(db.seasonCatalog) == "table" and db.seasonCatalog or {}
  local revision = tonumber(catalog.catalogRevision) or 0
  local record = type(catalog.records) == "table" and catalog.records[tostring(revision)] or nil
  local rosterStore = type(db.seasonalRoster) == "table" and db.seasonalRoster or {}
  local rosterSeasons = type(rosterStore.seasons) == "table" and rosterStore.seasons or {}
  local preDibs = type(db.preDibs) == "table" and db.preDibs or {}
  local disputes = type(db.disputes) == "table" and db.disputes or {}
  local hasAcquisitions = type(preDibs.acquisitions) == "table" and next(preDibs.acquisitions) ~= nil
  local hasRequests = type(disputes.requests) == "table" and next(disputes.requests) ~= nil
  local rosterConfigured = false
  for _, saved in pairs(rosterSeasons) do
    local current = type(saved) == "table" and type(saved.revisions) == "table"
      and saved.revisions[tostring(saved.currentRevision)] or nil
    if type(current) == "table" and (current.registrationState == "OPEN" or current.registrationState == "CLOSED") then
      rosterConfigured = true
      break
    end
  end
  local preservedHistory = install.installType == "UPGRADE" or revision > 0
    or next(rosterSeasons) ~= nil
    or hasAcquisitions or hasRequests
    or (type(install.legacy) == "table" and (tonumber(install.legacy.evidenceCount) or 0) > 0)
  local result = {
    firstInstall = not foundationReady and not preservedHistory,
    foundationReady = foundationReady,
    preservedHistory = preservedHistory,
    sections = {}, routes = {},
    dependencies = { seasonConfigured = false, rosterConfigured = rosterConfigured,
      ranksPublished = false, ledgerReady = false },
    reasonCode = foundationReady and "SEASON_CONFIGURATION_REQUIRED" or "GUILD_FOUNDATION_REQUIRED",
  }
  local function allow(section, ...)
    result.sections[section] = true
    for index = 1, select("#", ...) do result.routes[select(index, ...)] = true end
  end
  allow("GUILD SETUP", "wizard")
  if preservedHistory then
    allow("DIBS", "history")
    allow("GUILD SETUP", "installation", "reconciliation")
    if next(rosterSeasons) ~= nil then allow("GUILD SETUP", "seasonalRoster") end
    if hasAcquisitions then allow("REQUESTS", "vault") end
  end
  if not foundationReady then return result end

  local moduleValues = call(Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleValues, db) or {}
  local features = call(Dibs.FeatureRegistry and Dibs.FeatureRegistry.GetEffectiveStates, moduleValues) or {}
  local function enabled(key)
    return type(features[key]) == "table" and features[key].enabled == true
  end
  allow("GUILD SETUP", "guildSetup", "installation")
  allow("GUILD RULES", "seasons", "ranks")
  allow("SYSTEM", "settings", "modules", "sync", "diagnostics", "developer", "debug")
  if enabled("seasonalRoster") or next(rosterSeasons) ~= nil then
    allow("GUILD SETUP", "seasonalRoster")
  end
  if enabled("lootEligibility") then allow("GUILD RULES", "eligibility") end
  if enabled("lootRules") then allow("GUILD RULES", "lootTypes") end
  if enabled("preDibs") then allow("GUILD RULES", "preDibs") end
  if enabled("announcements") then allow("GUILD RULES", "announcements") end
  if enabled("rclootcouncil") then allow("INTEGRATIONS", "integration") end
  if enabled("independentRaid") then allow("INTEGRATIONS", "independentRaid") end

  local seasonId = db.currentSeasonId
  local season = type(db.seasons) == "table" and db.seasons[seasonId] or nil
  local catalogSeason = type(record) == "table" and type(record.seasons) == "table"
    and record.seasons[seasonId] or nil
  local configured = type(season) == "table" and season.isActive == true
    and season.isDraft ~= true and season.isArchived ~= true
    and type(catalogSeason) == "table" and record.currentSeasonId == seasonId
  local rosterSeason = rosterSeasons[seasonId]
  local rosterConfig = type(rosterSeason) == "table" and type(rosterSeason.revisions) == "table"
    and rosterSeason.revisions[tostring(rosterSeason.currentRevision)] or nil
  if type(rosterConfig) == "table" then
    -- Activation commits an immutable manifest; the configuration revision may
    -- intentionally remain REVIEW/READY (GetSeasonLifecycle derives ACTIVE).
    local lifecycle = rosterConfig.lifecycleState
    local activeLifecycle = lifecycle == "ACTIVE" or lifecycle == "READY" or lifecycle == "REVIEW"
    local now = call(Dibs.GetTimestamp) or (type(time) == "function" and time()) or 0
    configured = type(season) == "table" and season.isActive == true and season.isArchived ~= true
      and activeLifecycle and rosterSeason.activationAdopted == true
      and (not tonumber(rosterConfig.endAt) or now < tonumber(rosterConfig.endAt))
  end
  result.dependencies.seasonConfigured = configured == true
  local publishedRules = type(rosterConfig) == "table" and type(rosterConfig.rankAllocationSnapshot) == "table"
    and rosterConfig.rankAllocationSnapshot.rules
    or (type(record) == "table" and type(record.rankRules) == "table" and record.rankRules[tostring(seasonId)])
  local rules = type(db.rankRules) == "table" and db.rankRules[seasonId] or nil
  local hasher = Dibs.Sync and Dibs.Sync.CalculateContentHash
  local currentHash = type(rules) == "table" and next(rules) ~= nil and call(hasher, rules) or nil
  local publishedHash = type(publishedRules) == "table" and call(hasher, publishedRules) or nil
  local ranksPublished = currentHash ~= nil and currentHash == publishedHash
  result.dependencies.ranksPublished = ranksPublished
  local ledgerId = db.activeLedgerId
  local ledger = type(db.ledgers) == "table" and db.ledgers[ledgerId] or nil
  local authorityState = type(install.technical) == "table" and install.technical.authorityState or nil
  local ledgerReady = type(ledger) == "table" and ledger.status == "APPROVED"
    and type(ledger.transactions) == "table" and install.state ~= "RECOVERY_REQUIRED"
    and install.state ~= "BLOCKED" and authorityState ~= "RECOVERY_PENDING"
  result.dependencies.ledgerReady = ledgerReady
  if not configured then return result end
  if not ranksPublished then result.reasonCode = "RANK_RULES_PUBLICATION_REQUIRED"; return result end
  if not ledgerReady then result.reasonCode = "GUILD_LEDGER_REQUIRED"; return result end
  result.reasonCode = nil
  allow("OVERVIEW", "overview")
  if enabled("readiness") then allow("OVERVIEW", "setup") end
  allow("DIBS", "automaticDibs", "dibsAdmin", "history", "statistics")
  allow("REQUESTS", "pendingAwards")
  if enabled("greatVault") or hasAcquisitions then allow("REQUESTS", "vault") end
  if enabled("requests") then allow("REQUESTS", "disputes") end
  if enabled("preDibs") then allow("REQUESTS", "preDibRequests") end
  return result
end

function Wizard.GetInitialOperationalPolicyValues()
  return initialOperationalPolicyValues()
end

function Wizard.AdoptOperationalPolicy(actor)
  local policy = Dibs.OperationalPolicy
  if not policy or type(policy.AdoptInitial) ~= "function" then return false, "OPERATIONAL_POLICY_UNAVAILABLE" end
  return policy.AdoptInitial(actor, initialOperationalPolicyValues(), "GUIDED_SETUP")
end

function Wizard.GetProfiles()
  local profiles = {}
  for _, id in ipairs(PROFILE_ORDER) do profiles[#profiles + 1] = buildProfile(id) end
  return copy(profiles)
end

local SETUP_RESUME_ROUTES = {
  wizard = true, installation = true, settings = true, seasons = true,
  seasonalRoster = true, ranks = true, automaticDibs = true, lootTypes = true,
  preDibs = true, integration = true, sync = true, guildSetup = true, modules = true,
}

local function setupScope()
  local key = call(Dibs.GetGuildKey)
  if type(key) == "string" and key ~= "" then return key end
  return nil
end

local function validSetupStage(stage)
  for _, allowed in ipairs(TURNKEY_STAGES) do if stage == allowed then return true end end
  return false
end

-- These bounds match the season form's existing domain bounds. Incomplete
-- strings are retained while typing; creation still uses ValidateSeasonInput.
local DRAFT_TEXT_LIMITS = { name = 80, categories = 16 * 62, raidRules = 8000, timeZone = 64,
  operationId = 128 }
for _, field in ipairs({ "Start", "End", "RegistrationStart", "RegistrationEnd" }) do
  DRAFT_TEXT_LIMITS["seasonalRosterNew" .. field .. "Date"] = 10
  DRAFT_TEXT_LIMITS["seasonalRosterNew" .. field .. "Hour"] = 2
  DRAFT_TEXT_LIMITS["seasonalRosterNew" .. field .. "Minute"] = 2
end

local function resumeRaidDifficulties(values)
  if type(values) ~= "table" or getmetatable(values) ~= nil or #values > 3 then return nil end
  local valid, seen, count = { NORMAL = true, HEROIC = true, MYTHIC = true }, {}, 0
  for key in pairs(values) do
    if type(key) ~= "number" or key < 1 or key > 3 or key ~= math.floor(key) then return nil end
    count = count + 1
  end
  if count ~= #values then return nil end
  local result = {}
  for index = 1, count do
    local difficulty = values[index]
    if not valid[difficulty] or seen[difficulty] then return nil end
    seen[difficulty] = true
    result[index] = difficulty
  end
  return result
end

local function resumeSchedule(rows)
  if type(rows) ~= 'table' or getmetatable(rows) ~= nil or #rows > 7 then return nil end
  local result, count = {}, 0
  for key, row in pairs(rows) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #rows
      or type(row) ~= "table" or getmetatable(row) ~= nil then return nil end
    count = count + 1
    local entry = {}
    for field, value in pairs(row) do
      if field == "weekday" then
        if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > 7 then return nil end
      elseif field == "durationMinutes" then
        if type(value) ~= "number" or value % 1 ~= 0 or value < 30 or value > 600 then return nil end
      elseif field == "startTime" or field == "timeZone" then
        if type(value) ~= "string" or #value > (field == "startTime" and 5 or 64) then return nil end
      elseif field == "difficulty" then
        if value ~= "NORMAL" and value ~= "HEROIC" and value ~= "MYTHIC" then return nil end
      else return nil end
      entry[field] = value
    end
    result[key] = entry
  end
  if count ~= #rows then return nil end
  return result
end

local function resumeDraft(draft)
  if type(draft) ~= "table" or getmetatable(draft) ~= nil then return nil end
  local result = {}
  for key, value in pairs(draft) do
    if key == "enabled" then
      if type(value) ~= "boolean" then return nil end
      result[key] = value
    elseif key == "scheduleRows" then
      result[key] = resumeSchedule(value)
      if result[key] == nil then return nil end
    elseif key == "raidDifficulties" then
      result[key] = resumeRaidDifficulties(value)
      if result[key] == nil then return nil end
    elseif DRAFT_TEXT_LIMITS[key] then
      if type(value) ~= "string" or #value > DRAFT_TEXT_LIMITS[key] then return nil end
      if key == "operationId" and (#value == 0 or not value:match("^[%w_:%-%.]+$")) then return nil end
      result[key] = value
    else return nil end
  end
  return result
end

local function validateSetupPatch(patch)
  if type(patch) ~= "table" or getmetatable(patch) ~= nil then return nil end
  local result = {}
  for key, value in pairs(patch) do
    if key == "stage" then
      if not validSetupStage(value) then return nil end
    elseif key == "profileId" then
      if type(value) ~= "string" or not PROFILE_DEFINITIONS[value] then return nil end
    elseif key == "correctionRoute" then
      if value ~= false and (type(value) ~= "string" or not SETUP_RESUME_ROUTES[value]) then return nil end
    elseif key == "issueId" then
      if value ~= false and (type(value) ~= "string" or #value > 64
        or not value:match("^[%w_%-]+$")) then return nil end
    elseif key == "seasonDraft" then
      if value ~= false then
        value = resumeDraft(value)
        if not value then return nil end
      end
    else return nil end
    result[key] = value
  end
  return result
end

function Wizard.GetSetupProgress()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings() or {}
  local scopes, key = settings.turnkeySetupProgressByGuild, setupScope()
  local saved = type(scopes) == "table" and key and scopes[key]
  local progress = saved and validateSetupPatch(saved) or nil
  if not progress then
    progress = {}
    -- Legacy UI preferences contain no season data. Migrate only the first
    -- scope; a subsequent guild starts fresh instead of inheriting that stage.
    if type(scopes) ~= "table" or next(scopes) == nil then
      progress.stage = validSetupStage(settings.turnkeyWizardStage) and settings.turnkeyWizardStage or nil
      progress.profileId = PROFILE_DEFINITIONS[settings.turnkeyWizardProfileId] and settings.turnkeyWizardProfileId or nil
    end
  end
  progress.stage, progress.profileId = progress.stage or "choose", progress.profileId or "progression"
  return progress
end

function Wizard.SaveSetupProgress(patch)
  local validated = validateSetupPatch(patch)
  local key = setupScope()
  if not validated then return nil, "INVALID_SETUP_PROGRESS" end
  if not key then return nil, "SETUP_SCOPE_UNAVAILABLE" end
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if not settings then return nil, "LOCAL_SETTINGS_UNAVAILABLE" end
  local progress = Wizard.GetSetupProgress()
  for field, value in pairs(validated) do
    if value == false and field ~= "enabled" then progress[field] = nil else progress[field] = value end
  end
  if type(settings.turnkeySetupProgressByGuild) ~= "table" then settings.turnkeySetupProgressByGuild = {} end
  settings.turnkeySetupProgressByGuild[key] = progress
  return true
end

function Wizard.GetCurrentStage()
  return Wizard.GetSetupProgress().stage
end

function Wizard.SetCurrentStage(stage)
  stage = tostring(stage or "")
  local valid
  for _, allowed in ipairs(TURNKEY_STAGES) do
    if stage == allowed then valid = true break end
  end
  if not valid then stage = "choose" end
  Wizard.SaveSetupProgress({ stage = stage })
  return stage
end

function Wizard.GetSelectedProfileId()
  return Wizard.GetSetupProgress().profileId
end

function Wizard.SetSelectedProfileId(profileId)
  profileId = tostring(profileId or "")
  if not PROFILE_DEFINITIONS[profileId] then return nil, "UNKNOWN_SETUP_PROFILE" end
  Wizard.SaveSetupProgress({ profileId = profileId })
  return profileId
end

local function previewAction(id, disposition, titleKey, explanationKey, outcomeKey, reasonCode)
  return {
    id = id,
    disposition = disposition,
    title = text(titleKey),
    explanation = text(explanationKey),
    outcome = text(outcomeKey),
    reasonCode = reasonCode,
  }
end

local function seasonDraftInput(options)
  if options == nil then return nil end
  if type(options) ~= "table" then return nil, "INVALID_INPUT" end
  if options.seasonDraft == nil then return nil end
  local roster = Dibs.SeasonalRoster
  if not roster or type(roster.ValidateSeasonInput) ~= "function"
    or type(roster.GetPreservedHistory) ~= "function" or type(roster.CreateSeason) ~= "function" then
    return nil, "SEASON_SERVICE_UNAVAILABLE"
  end
  local operationId = options.seasonOperationId
  if type(options.seasonDraft) ~= "table" or type(operationId) ~= "string"
    or #operationId < 1 or #operationId > 128 or not operationId:match("^[%w_:%-%.]+$") then
    return nil, "INVALID_INPUT"
  end
  local input = copy(options.seasonDraft)
  if input.lifecycleState == nil then input.lifecycleState = "DRAFT" end
  if input.registrationState == nil then input.registrationState = "DRAFT" end
  local valid, normalized = roster.ValidateSeasonInput(input, true)
  if not valid then return nil, normalized end
  if normalized.lifecycleState ~= "DRAFT" or normalized.registrationState ~= "DRAFT" then
    return nil, "INITIAL_STATE_MUST_BE_DRAFT"
  end
  if not normalized.startAt or not normalized.registrationStartAt then return nil, "SEASON_DATES_REQUIRED" end
  return normalized
end

local function seasonDraftAction(actor)
  local history, reason = Dibs.SeasonalRoster.GetPreservedHistory(actor)
  local disposition = "APPLY"
  if type(history) ~= "table" then
    disposition, reason = "FAILED", reason or "SEASON_SERVICE_UNAVAILABLE"
  elseif #history > 0 then
    disposition = "ALREADY_READY"
  else
    local modules = call(Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleValues) or {}
    local states = call(Dibs.FeatureRegistry and Dibs.FeatureRegistry.GetEffectiveStates, modules) or {}
    if not states.seasonalRoster or states.seasonalRoster.enabled ~= true then
      disposition, reason = "DEFERRED", "MODULE_DISABLED"
    end
  end
  local action = previewAction("seasonDraft", disposition, "WIZARD_ACTION_SEASON_DRAFT_TITLE",
    "WIZARD_ACTION_SEASON_DRAFT_EXPLANATION", disposition == "ALREADY_READY"
      and "WIZARD_ACTION_SEASON_DRAFT_PRESERVED" or "WIZARD_ACTION_SEASON_DRAFT_OUTCOME", reason)
  if type(history) == "table" and history[1] then
    action.value, action.revision = history[1].seasonId, history[1].revision
  end
  return action
end

function Wizard.PreviewProfile(profileId, actor, options)
  local profile = buildProfile(profileId)
  if not profile then return nil, "UNKNOWN_SETUP_PROFILE" end
  if profileId == "custom" then
    return {
      profileId = profileId,
      canApply = false,
      actions = {
        previewAction("advanced", "ADVANCED_ONLY", "WIZARD_ACTION_ADVANCED_TITLE",
          "WIZARD_ACTION_ADVANCED_EXPLANATION", "WIZARD_ACTION_ADVANCED_OUTCOME"),
      },
      preserved = copy(profile.preserves),
      deferred = {},
    }
  end

  local draft, draftReason = seasonDraftInput(options)
  if draftReason then
    return { profileId = profileId, canApply = false, reasonCode = draftReason,
      actions = { previewAction("seasonDraft", "FAILED", "WIZARD_ACTION_SEASON_DRAFT_TITLE",
        "WIZARD_ACTION_SEASON_DRAFT_EXPLANATION", "WIZARD_ACTION_SEASON_DRAFT_OUTCOME", draftReason) },
      preserved = copy(profile.preserves), deferred = {} }
  end

  local status = installationStatus()
  local actions, deferred = {}, {}
  local active = status.protocol and status.protocol.active == true
  actions[#actions + 1] = previewAction("initialize", active and "ALREADY_READY" or "APPLY",
    "WIZARD_ACTION_INITIALIZE_TITLE", "WIZARD_ACTION_INITIALIZE_EXPLANATION",
    active and "WIZARD_ACTION_ALREADY_READY" or "WIZARD_ACTION_INITIALIZE_OUTCOME")

  actions[#actions + 1] = previewAction("lootRules", profileMatches(profileId) and "ALREADY_READY" or "APPLY",
    "WIZARD_ACTION_RULES_TITLE", "WIZARD_ACTION_RULES_EXPLANATION",
    profileMatches(profileId) and "WIZARD_ACTION_ALREADY_READY" or "WIZARD_ACTION_RULES_OUTCOME")

  local policy = call(Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState) or {}
  if policy.status == "POLICY_ADOPTED" then
    actions[#actions + 1] = previewAction("guildPolicy", "ALREADY_READY",
      "WIZARD_ACTION_POLICY_TITLE", "WIZARD_ACTION_POLICY_EXPLANATION", "WIZARD_ACTION_ALREADY_READY")
  else
    local governance = call(Dibs.Governance and Dibs.Governance.GetState) or {}
    local gm = call(Dibs.Permissions and Dibs.Permissions.IsGM, actor) == true
    local disposition = gm and (governance.status == "GOVERNANCE_ADOPTED" or not active) and "APPLY" or "DEFERRED"
    local reasonCode = disposition == "DEFERRED" and "GM_CONFIRMATION_REQUIRED" or nil
    local action = previewAction("guildPolicy", disposition,
      "WIZARD_ACTION_POLICY_TITLE", "WIZARD_ACTION_POLICY_EXPLANATION",
      disposition == "APPLY" and "WIZARD_ACTION_POLICY_OUTCOME" or "WIZARD_ACTION_POLICY_DEFERRED",
      reasonCode)
    actions[#actions + 1] = action
    if disposition == "DEFERRED" then deferred[#deferred + 1] = copy(action) end
  end

  local seasonAction = draft and seasonDraftAction(actor) or nil
  if seasonAction then
    actions[#actions + 1] = seasonAction
    if seasonAction.disposition == "DEFERRED" then deferred[#deferred + 1] = copy(seasonAction) end
  end
  return {
    profileId = profileId,
    canApply = not seasonAction or seasonAction.disposition ~= "FAILED",
    reasonCode = seasonAction and seasonAction.disposition == "FAILED" and seasonAction.reasonCode or nil,
    actions = actions,
    preserved = copy(profile.preserves),
    deferred = deferred,
  }
end

function Wizard.ApplyProfile(profileId, actor, options)
  local preview, previewReason = Wizard.PreviewProfile(profileId, actor, options)
  if not preview then return { ok = false, profileId = profileId, actions = {}, reasonCode = previewReason } end
  if profileId == "custom" then
    return { ok = true, profileId = profileId, actions = { { id = "advanced", outcome = "ADVANCED_ONLY" } } }
  end
  if not preview.canApply then
    return { ok = false, profileId = profileId, actions = {
      { id = "seasonDraft", outcome = "FAILED", reasonCode = preview.reasonCode, route = "seasonalRoster",
        title = text("WIZARD_ACTION_SEASON_DRAFT_TITLE") },
    }, reasonCode = preview.reasonCode }
  end

  local results, failed = {}, false
  for _, action in ipairs(preview.actions) do
    local result = { id = action.id, title = action.title }
    if action.disposition == "ALREADY_READY" then
      result.outcome = "ALREADY_READY"
      result.value, result.revision = action.value, action.revision
    elseif action.disposition == "DEFERRED" then
      result.outcome, result.reasonCode = "DEFERRED", action.reasonCode
    elseif action.id == "initialize" then
      local initialized = Dibs.Installation and Dibs.Installation.Initialize
        and Dibs.Installation.Initialize(actor, {}) or { ok = false, reasonCode = "INSTALLATION_UNAVAILABLE" }
      result.outcome = initialized.ok and "APPLIED" or "FAILED"
      if not initialized.ok then result.reasonCode = initialized.reasonCode end
      result.stage = initialized.stage
    elseif action.id == "lootRules" then
      local apply = Dibs.RCOptions and Dibs.RCOptions.ApplyInstallationPreset
      local applied, applyReason
      if type(apply) == "function" then
        applied, applyReason = apply(PROFILE_DEFINITIONS[profileId].presetKey, { silent = true })
      end
      applied = applied == true
      result.outcome = applied and "APPLIED" or "FAILED"
      if not applied then result.reasonCode = applyReason or "LOOT_RULE_PRESET_FAILED" end
    elseif action.id == "guildPolicy" then
      local adopted, reason = Wizard.AdoptOperationalPolicy(actor)
      result.outcome = adopted and "APPLIED" or "FAILED"
      if not adopted then result.reasonCode = reason end
    elseif action.id == "seasonDraft" then
      -- Re-read after foundation actions: a successful Officer proposal is not
      -- adoption, and a concurrent season must never be duplicated or replaced.
      local current = seasonDraftAction(actor)
      if current.disposition ~= "APPLY" then
        result.outcome, result.reasonCode = current.disposition, current.reasonCode
        result.value, result.revision = current.value, current.revision
      elseif failed then
        result.outcome, result.reasonCode = "DEFERRED", "SETUP_FOUNDATION_FAILED"
      elseif not Wizard.GetNavigationAccess(actor).foundationReady then
        result.outcome, result.reasonCode = "DEFERRED", "GUILD_FOUNDATION_REQUIRED"
      else
        local draft, reason = seasonDraftInput(options)
        local created = draft and Dibs.SeasonalRoster.CreateSeason(draft, options.seasonOperationId, actor)
          or { ok = false, code = reason }
        result.outcome = created.ok and "APPLIED" or "FAILED"
        if not created.ok then result.reasonCode = created.code end
        result.value, result.revision, result.idempotent = created.value, created.revision, created.idempotent
      end
    end
    result.route = result.reasonCode == "SYNC_BEHIND" and "sync"
      or action.id == "lootRules" and "lootTypes"
      or action.id == "guildPolicy" and "installation"
      or action.id == "initialize" and "installation"
      or action.id == "seasonDraft" and "seasonalRoster"
      or nil
    if result.outcome == "FAILED" then failed = true end
    results[#results + 1] = result
  end
  return {
    ok = not failed,
    profileId = profileId,
    actions = results,
    reasonCode = failed and "SETUP_PROFILE_PARTIAL_FAILURE" or nil,
  }
end

local TURNKEY_ROUTE = {
  installation = "installation", guild = "settings", administration = "settings",
  seasons = "seasons", rankRules = "ranks", allocationReconciliation = "automaticDibs",
  dibsRules = "lootTypes", preDibs = "preDibs", ledger = "installation",
  rclootcouncil = "integration", sync = "sync", operationalPolicy = "installation",
  readiness = "guildSetup",
}
local TURNKEY_CATEGORY = {
  installation = "WIZARD_CATEGORY_FOUNDATION", guild = "WIZARD_CATEGORY_FOUNDATION",
  administration = "WIZARD_CATEGORY_FOUNDATION", seasons = "WIZARD_CATEGORY_RULES",
  rankRules = "WIZARD_CATEGORY_RULES", allocationReconciliation = "WIZARD_CATEGORY_RULES",
  dibsRules = "WIZARD_CATEGORY_RULES", preDibs = "WIZARD_CATEGORY_RULES",
  ledger = "WIZARD_CATEGORY_LEDGER", rclootcouncil = "WIZARD_CATEGORY_INTEGRATIONS",
  sync = "WIZARD_CATEGORY_INTEGRATIONS", operationalPolicy = "WIZARD_CATEGORY_POLICY",
  readiness = "WIZARD_CATEGORY_READINESS",
}
local NON_BLOCKING_ACTION_REQUIRED = { allocationReconciliation = true, operationalPolicy = true }

local function turnkeySeverity(step)
  if step.status == "READY" then return "READY" end
  if step.status == "OPTIONAL" then return "OPTIONAL" end
  if step.status == "BLOCKED" then return "BLOCKING" end
  if step.status == "ACTION_REQUIRED" and not NON_BLOCKING_ACTION_REQUIRED[step.id] then return "BLOCKING" end
  return "WARNING"
end

function Wizard.GetTurnkeyStatus(actor, dbOverride)
  local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local legacy, install = Wizard.GetStatus(actor, dbOverride)
  local syncBlocking = install.sync and install.sync.behind == true
    and not (install.protocol and install.protocol.active == true)
  local verification, primaryIssueId, hasBlocking, hasWarning = {}, nil, false, false
  for _, step in ipairs(legacy.steps or {}) do
    if step.id ~= "review" then
      local severity = turnkeySeverity(step)
      if step.id == "sync" and syncBlocking then
        severity = "BLOCKING"
      end
      local deferredLedger = step.id == "ledger" and syncBlocking
        and step.status == "ACTION_REQUIRED" and install.state == "READY_TO_INITIALIZE"
      if deferredLedger then severity = "WARNING" end
      local result = {
        id = step.id,
        category = text(TURNKEY_CATEGORY[step.id] or "WIZARD_CATEGORY_OTHER"),
        severity = severity,
        title = step.label,
        explanation = tostring(step.summary or ""),
        impact = severity == "BLOCKING" and text("WIZARD_BLOCKING_IMPACT")
          or severity == "WARNING" and text("WIZARD_WARNING_IMPACT")
          or severity == "READY" and text("WIZARD_READY_IMPACT")
          or text("WIZARD_OPTIONAL_IMPACT"),
        nextAction = severity ~= "READY" and severity ~= "OPTIONAL"
          and Dibs.SetupAssistant.GetGuidance(step.id == "installation" and "ledger" or step.id,
            type(step.detail) == "table" and step.detail.reasonCode or nil) or nil,
        route = TURNKEY_ROUTE[step.id],
        sourceStatus = step.status,
      }
      if deferredLedger then
        result.explanation = text("WIZARD_LEDGER_SYNC_DEFERRED_EXPLANATION")
        result.impact = text("WIZARD_LEDGER_SYNC_DEFERRED_IMPACT")
        result.nextAction = text("WIZARD_SYNC_BLOCKING_ACTION")
        result.route = TURNKEY_ROUTE.sync
      end
      if step.id == "sync" and severity == "BLOCKING" then
        result.explanation = text("WIZARD_SYNC_BLOCKING_EXPLANATION")
        result.impact = text("WIZARD_SYNC_BLOCKING_IMPACT")
        result.nextAction = text("WIZARD_SYNC_BLOCKING_ACTION")
      end
      if step.id == "readiness" and severity ~= "READY" and type(step.detail) == "table" then
        local selectedFinding
        for _, finding in ipairs(step.detail.checks or {}) do
          if finding.state ~= "ready" and finding.state ~= "skipped" then
            selectedFinding = selectedFinding or finding
            if finding.required == true then selectedFinding = finding; break end
          end
        end
        if selectedFinding then
          result.explanation = tostring(selectedFinding.impact or selectedFinding.reasonCode or result.explanation)
          result.impact = tostring(selectedFinding.impact or result.impact)
          result.nextAction = Dibs.SetupAssistant.GetGuidance(selectedFinding.id, selectedFinding.reasonCode, selectedFinding.remediation)
        end
      end
      verification[#verification + 1] = result
      if severity == "BLOCKING" then
        hasBlocking = true
      elseif severity == "WARNING" then
        hasWarning = true
      end
    end
  end
  local priority = {
    "installation", "sync", "ledger", "seasons", "rankRules", "dibsRules",
    "allocationReconciliation", "operationalPolicy", "readiness",
  }
  for _, id in ipairs(priority) do
    for _, result in ipairs(verification) do
      if result.id == id and result.severity == "BLOCKING" then
        primaryIssueId = id
        break
      end
    end
    if primaryIssueId then break end
  end
  if not primaryIssueId then
    for _, result in ipairs(verification) do
      if result.severity == "WARNING" then primaryIssueId = result.id break end
    end
  end
  local overallState = hasBlocking and "BLOCKED"
    or hasWarning and "PARTIALLY_CONFIGURED"
    or "READY_FOR_RAID"
  local result = {
    currentStage = Wizard.GetCurrentStage(),
    selectedProfileId = Wizard.GetSelectedProfileId(),
    stages = {
      { id = "choose", status = "READY" },
      { id = "configure", status = legacy.overallState == "NEW_INSTALLATION" and "ACTION_REQUIRED" or "READY" },
      { id = "verify", status = primaryIssueId and "ATTENTION" or "READY" },
    },
    verification = verification,
    primaryIssueId = primaryIssueId,
    overallState = overallState,
    mode = legacy.mode,
  }
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Wizard data", "turnkey-status", renderStartedAt)
  end
  return result
end

local NEXT_STEP_COPY = {
  rankRules = { "RANK", "Set the Dibs allocation for each guild rank",
    "Choose which ranks receive Dibs and their starting allocation, then publish your choices.", "Configure rank allocations" },
  dibsRules = { "LOOT", "Confirm which loot uses Dibs",
    "Review the allowed loot types and have the Guild Master publish the guild's choices.", "Review loot rules" },
  sync = { "SYNC", "Receive the latest guild settings",
    "Keep an authorized guild member online and request the current guild settings before continuing.", "Open synchronization" },
  ledger = { "LEDGER", "Finish the shared Dibs account setup",
    "Review the shared guild account and resolve the reported setup requirement before continuing.", "Review guild account" },
  readiness = { "READINESS", "Review the remaining guild setup requirement",
    "Open the guild checks and follow the recommended correction for the remaining requirement.", "Review guild checks" },
  operationalPolicy = { "GUILD_POLICY", "Confirm the guild's operating choices",
    "The Guild Master must review and adopt the guild's choices before everyone can use them.", "Review guild policy" },
}

-- Guidance only: no stored completed flags, implicit publication or alternate
-- readiness verdict. Always recompute from authoritative reads after returning.
function Wizard.GetNextSetupStep(status, actor)
  status = status or Wizard.GetTurnkeyStatus(actor)
  local verification, completed = status.verification or {}, 0
  local byId = {}
  for _, finding in ipairs(verification) do
    byId[finding.id] = finding
    if finding.severity == "READY" or finding.severity == "OPTIONAL" then completed = completed + 1 end
  end
  local function project(finding, extra)
    local result = {
      id = finding.id, title = finding.title, explanation = finding.explanation,
      nextAction = finding.nextAction, route = finding.route, stage = "verify",
      severity = finding.severity, reasonCode = finding.reasonCode,
      tone = finding.severity == "BLOCKING" and "error" or "warning",
      index = math.min(completed + 1, #verification + (extra and 1 or 0)),
      total = #verification + (extra and 1 or 0), completed = completed, done = false,
    }
    local words = NEXT_STEP_COPY[finding.id]
    if words then
      result.title = text("WIZARD_NEXT_" .. words[1] .. "_TITLE", words[2])
      result.explanation = text("WIZARD_NEXT_" .. words[1] .. "_EXPLANATION", words[3])
      result.nextAction = text("WIZARD_NEXT_" .. words[1] .. "_ACTION", words[4])
    end
    return result
  end
  local access = Wizard.GetNavigationAccess(actor)
  if not access.foundationReady then
    local first = byId[status.primaryIssueId]
    local issue = project(first or { id = "installation", severity = "BLOCKING" })
    issue.title = text("WIZARD_NEXT_FOUNDATION_TITLE", "Prepare your guild's Dibs setup")
    issue.explanation = text("WIZARD_NEXT_FOUNDATION_EXPLANATION",
      "Choose a starting profile and apply it to prepare the shared guild foundation.")
    issue.nextAction = text("WIZARD_NEXT_FOUNDATION_ACTION", "Continue setup")
    issue.route, issue.stage = "wizard", "configure"
    return issue
  end
  -- Existing authority/recovery blockers precede any seasonal guidance.
  for _, id in ipairs({ "installation", "sync", "ledger" }) do
    if byId[id] and byId[id].severity == "BLOCKING" then return project(byId[id]) end
  end
  local module = call(Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleStatus, "seasonalRoster")
  if type(module) == "table" and module.enabled == true then
    local roster = Dibs.SeasonalRoster
    local history = call(roster and roster.GetPreservedHistory, actor)
    if type(history) == "table" and #history == 0 then
      local result = project({ id = "seasonDraft", severity = "WARNING",
        title = text("WIZARD_NEXT_SEASON_TITLE", "Prepare your raid season"),
        explanation = text("WIZARD_NEXT_SEASON_EXPLANATION",
          "Give the season a name and choose when registration and raiding begin. Your choices are saved as a draft."),
        nextAction = text("WIZARD_NEXT_SEASON_ACTION", "Configure the season"), route = "wizard" }, true)
      result.stage, result.prepareSeason = "configure", true
      return result
    end
    local seasons = type(history) == "table" and #history > 0 and call(roster and roster.ListSeasons)
    local draft, published
    for _, season in ipairs(seasons or {}) do
      local lifecycle = season.lifecycle or {}
      local state = lifecycle.seasonStatus or lifecycle.lifecycleState or season.persistedLifecycleState
      if state ~= "ARCHIVED" and state ~= "COMPLETED" then
        if season.registrationState ~= "DRAFT" then published = true end
        if season.registrationState == "DRAFT" and not draft then draft = season end
      end
    end
    if draft and not published then
      local result = project({ id = "seasonPublication", severity = "WARNING",
        title = text("WIZARD_NEXT_SEASON_PUBLISH_TITLE", "Review and publish your raid season"),
        explanation = text("WIZARD_NEXT_SEASON_PUBLISH_EXPLANATION",
          "Your season draft is saved. Review it and explicitly open registration before configuring the next seasonal steps."),
        nextAction = text("WIZARD_NEXT_SEASON_PUBLISH_ACTION", "Review the season draft"), route = "seasonalRoster" }, true)
      result.seasonId = draft.seasonId
      return result
    end
  end
  -- Retain the authoritative primary blocker, then the authoritative warning.
  local primary = byId[status.primaryIssueId]
  if primary and primary.severity == "BLOCKING" then return project(primary) end
  for _, finding in ipairs(verification) do
    if finding.severity == "BLOCKING" then return project(finding) end
  end
  if primary and primary.severity == "WARNING" then return project(primary) end
  for _, finding in ipairs(verification) do
    if finding.severity == "WARNING" then return project(finding) end
  end
  return { id = "done", title = text("WIZARD_NEXT_DONE_TITLE", "Your guild setup is ready"),
    explanation = text("WIZARD_NEXT_DONE_EXPLANATION", "All required setup checks are complete. You can return here whenever guild settings change."),
    nextAction = text("WIZARD_NEXT_DONE_ACTION", "View setup details"), route = "wizard", stage = "verify",
    index = #verification, total = #verification, completed = completed, done = true, tone = "success", severity = "READY" }
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
  if settings.wizardStepMigrationVersion ~= 1 and settings.wizardStepMigrationVersion ~= 2 then
    if index and index > 5 and index <= 12 then index = index + 1 end
    settings.wizardStepIndex = index
    settings.wizardStepMigrationVersion = 1
  end
  if settings.wizardStepMigrationVersion ~= 2 then
    if index and index >= 12 and index <= 13 then index = index + 1 end
    settings.wizardStepIndex = index
    settings.wizardStepMigrationVersion = 2
  end
  if not index or index < 1 or index > #STEPS then return 1 end
  return math.floor(index)
end

function Wizard.SetCurrentStepIndex(index)
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if not settings then return Wizard.GetCurrentStepIndex() end
  local clamped = math.max(1, math.min(math.floor(tonumber(index) or 1), #STEPS))
  settings.wizardStepIndex, settings.wizardStepMigrationVersion = clamped, 2
  return clamped
end

return Wizard
