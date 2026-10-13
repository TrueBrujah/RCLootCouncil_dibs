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
  { id = "readiness", label = "Readiness" },
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

local function initialOperationalPolicyValues()
  local preDibModes = {}
  local seasons = call(Dibs.Seasons and Dibs.Seasons.List, false) or {}
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

local function stepOperationalPolicy()
  local policy = Dibs.OperationalPolicy
  local state = call(policy and policy.GetState) or {}
  if state.status == "POLICY_ADOPTED" then
    return { status = "READY", summary = "Guild Policy is adopted at revision " .. tostring(state.policyRevision) .. "." }
  end
  local governance = call(Dibs.Governance and Dibs.Governance.GetState) or {}
  if governance.status ~= "GOVERNANCE_ADOPTED" then
    return { status = "BLOCKED", summary = "Initialize Guild Configuration before adopting Guild Policy." }
  end
  if call(Dibs.Permissions and Dibs.Permissions.IsGM) ~= true then
    return { status = "WARNING", summary = "Waiting for the Guild Master to review and adopt Guild Policy." }
  end
  return {
    status = "ACTION_REQUIRED",
    summary = "Review the local settings below, then explicitly adopt Guild Policy.",
    detail = initialOperationalPolicyValues(),
  }
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
  local rows = call(Dibs.RankRules and Dibs.RankRules.GetRankConfigurationSummary, seasonId)
  if type(rows) ~= "table" then
    return { status = "WARNING", summary = "Guild rank configuration cannot be verified." }
  end
  local catalog = call(Dibs.Seasons and Dibs.Seasons.GetCatalogState) or {}
  local revision = tonumber(catalog.catalogRevision) or 0
  local record = revision > 0 and call(Dibs.Seasons and Dibs.Seasons.GetCatalogRecord, revision) or nil
  local publishedRules = record and record.rankRules and record.rankRules[tostring(seasonId)]
  local currentRules = call(Dibs.RankRules and Dibs.RankRules.GetRulesForSeason, seasonId) or {}
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
  if Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() then
    return { status = "WARNING", summary = "Rank Rules are published, but SEASON_CATALOG synchronization is behind. Revision " .. tostring(revision) .. ".", rows = rows }
  end
  if #rows == 0 then
    return { status = "READY", summary = "Rank Rules are published through SEASON_CATALOG revision " .. tostring(revision) .. "; no current rank rows need configuration.", rows = rows }
  end
  return { status = "READY", summary = "Rank Rules are configured and synchronized through SEASON_CATALOG revision " .. tostring(revision) .. ".", rows = rows }
end

local function stepAllocationReconciliation()
  local seasonId = call(Dibs.GetCurrentSeasonId)
  local rows = call(Dibs.RankRules and Dibs.RankRules.GetAllocationReconciliation, seasonId)
  if type(rows) ~= "table" or #rows == 0 then
    local rankRows = call(Dibs.RankRules and Dibs.RankRules.GetRankConfigurationSummary, seasonId) or {}
    local allDisabled = #rankRows > 0
    for _, row in ipairs(rankRows) do
      if row.enabled ~= false then allDisabled = false; break end
    end
    if allDisabled then
      return { status = "OPTIONAL", summary = "All current guild ranks have Dibs allocation disabled." }
    end
    return { status = "WARNING", summary = "Member allocation reconciliation cannot be verified from the current roster." }
  end
  local needed, retained = 0, 0
  local unknown = 0
  for _, row in ipairs(rows) do
    local difference = tonumber(row.difference)
    if difference == nil then unknown = unknown + 1
    elseif difference > 0 then needed = needed + 1
    elseif difference < 0 then retained = retained + 1 end
  end
  if unknown > 0 then
    return { status = "WARNING", summary = "Member allocation reconciliation cannot be verified for " .. tostring(unknown) .. " roster row(s)." }
  end
  if needed > 0 then
    return { status = "ACTION_REQUIRED", summary = tostring(needed) .. " players need starting-allocation reconciliation.",
      detail = { needsReconciliation = needed, keepGranted = retained } }
  end
  return { status = "READY", summary = retained > 0
      and (tostring(retained) .. " existing allocations are retained after rank decreases.")
      or "No member allocation top-ups are currently required.",
    detail = { needsReconciliation = 0, keepGranted = retained } }
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
  local syncStatus = call(Dibs.Sync and Dibs.Sync.GetStatus)
  local behind = call(Dibs.Sync and Dibs.Sync.IsSyncBehind)
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
  return { status = map[report.status] or "BLOCKED", summary = "Readiness: " .. tostring(report.status), report = report }
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

  return { steps = steps, overallState = overallState, mode = mode }
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

function Wizard.GetCurrentStage()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings() or {}
  local stage = tostring(settings.turnkeyWizardStage or "choose")
  for _, allowed in ipairs(TURNKEY_STAGES) do
    if stage == allowed then return stage end
  end
  return "choose"
end

function Wizard.SetCurrentStage(stage)
  stage = tostring(stage or "")
  local valid
  for _, allowed in ipairs(TURNKEY_STAGES) do
    if stage == allowed then valid = true break end
  end
  if not valid then stage = "choose" end
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if settings then settings.turnkeyWizardStage = stage end
  return stage
end

function Wizard.GetSelectedProfileId()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings() or {}
  local profileId = tostring(settings.turnkeyWizardProfileId or "progression")
  return PROFILE_DEFINITIONS[profileId] and profileId or "progression"
end

function Wizard.SetSelectedProfileId(profileId)
  profileId = tostring(profileId or "")
  if not PROFILE_DEFINITIONS[profileId] then return nil, "UNKNOWN_SETUP_PROFILE" end
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if settings then settings.turnkeyWizardProfileId = profileId end
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

function Wizard.PreviewProfile(profileId, actor)
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

  return {
    profileId = profileId,
    canApply = true,
    actions = actions,
    preserved = copy(profile.preserves),
    deferred = deferred,
  }
end

function Wizard.ApplyProfile(profileId, actor)
  local preview, previewReason = Wizard.PreviewProfile(profileId, actor)
  if not preview then return { ok = false, profileId = profileId, actions = {}, reasonCode = previewReason } end
  if profileId == "custom" then
    return { ok = true, profileId = profileId, actions = { { id = "advanced", outcome = "ADVANCED_ONLY" } } }
  end

  local results, failed = {}, false
  for _, action in ipairs(preview.actions) do
    local result = { id = action.id, title = action.title }
    if action.disposition == "ALREADY_READY" then
      result.outcome = "ALREADY_READY"
    elseif action.disposition == "DEFERRED" then
      result.outcome, result.reasonCode = "DEFERRED", action.reasonCode
    elseif action.id == "initialize" then
      local initialized = Dibs.Installation and Dibs.Installation.Initialize
        and Dibs.Installation.Initialize(actor, {}) or { ok = false, reasonCode = "INSTALLATION_UNAVAILABLE" }
      result.outcome = initialized.ok and "APPLIED" or "FAILED"
      result.reasonCode = initialized.ok and nil or initialized.reasonCode
      result.stage = initialized.stage
    elseif action.id == "lootRules" then
      local apply = Dibs.RCOptions and Dibs.RCOptions.ApplyInstallationPreset
      local applied, applyReason
      if type(apply) == "function" then
        applied, applyReason = apply(PROFILE_DEFINITIONS[profileId].presetKey)
      end
      applied = applied == true
      result.outcome = applied and "APPLIED" or "FAILED"
      result.reasonCode = applied and nil or applyReason or "LOOT_RULE_PRESET_FAILED"
    elseif action.id == "guildPolicy" then
      local adopted, reason = Wizard.AdoptOperationalPolicy(actor)
      result.outcome = adopted and "APPLIED" or "FAILED"
      result.reasonCode = adopted and nil or reason
    end
    result.route = result.reasonCode == "SYNC_BEHIND" and "sync"
      or action.id == "lootRules" and "lootTypes"
      or action.id == "guildPolicy" and "installation"
      or action.id == "initialize" and "installation"
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
  readiness = "setup",
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

function Wizard.GetTurnkeyStatus(actor)
  local legacy = Wizard.GetStatus(actor)
  local install = installationStatus()
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
        nextAction = TURNKEY_ROUTE[step.id] and text("WIZARD_CORRECTION_ACTION") or nil,
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
      if step.id == "readiness" and type(step.detail) == "table" then
        for _, finding in ipairs(step.detail.checks or {}) do
          if finding.state ~= "ready" and finding.state ~= "skipped" then
            result.explanation = tostring(finding.impact or finding.reasonCode or result.explanation)
            result.impact = tostring(finding.impact or result.impact)
            result.nextAction = tostring(finding.remediation or result.nextAction or "")
            break
          end
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
  return {
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
