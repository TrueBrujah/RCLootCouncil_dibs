--[[
Module: Dibs.OfficerUI
Layer: Officer UI controller
Purpose: Provide navigation and actions for seasons, rules, requests, history, and audits.
Responsibilities: Build permission-filtered views and delegate mutations to services.
Non-responsibilities: It does not contain the accounting source of truth.
Dependencies: AceGUI, CoreAPI, all officer-facing domain modules, optional RCOptions.
Blizzard events: PLAYER_REGEN_ENABLED for deferred UI work.
Internal events/messages: UI callbacks and refreshes.
SavedVariables: Through delegated services.
RCLootCouncil: Shows capability/status and reconciliation tools.
Combat safety: ProtectedActions and readiness gate authoritative callbacks.
Invariants: DIBS-RULE-007, DIBS-RULE-008, DIBS-RULE-009.
Related docs: docs/officer/README.md.
]]

local Dibs = _G.Dibs
Dibs.OfficerUI = Dibs.OfficerUI or {}

local RANK_LABELS = {
  [0] = "Guild Master",
  [1] = "Officer",
  [2] = "Veteran",
  [3] = "Member",
  [4] = "Initiate",
  [5] = "Alt",
}

local ANNOUNCEMENT_CHANNEL_VALUES = {
  NONE = "None",
  RAID = "Raid",
  RAID_WARNING = "Raid Warning",
  RAID_DIBS = "Raid Dibs",
  SAY = "Say",
  YELL = "Yell",
  GUILD = "Guild",
  OFFICER = "Officer",
  PARTY = "Party",
  INSTANCE_CHAT = "Instance Chat",
}
local DEFAULT_PREDIB_TEMPLATE = "[Dibs] %player requested %item (%difficulty) - %date %time"
local DEFAULT_REMINDER_TEMPLATE = "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]"

local function uiDebug(message)
  if Dibs.DebugLogs and type(Dibs.DebugLogs.Add) == "function" then
    Dibs.DebugLogs.Add("ui", 4, tostring(message))
  elseif type(Dibs.Message) == "function" then
    Dibs.Message("[ui debug] " .. tostring(message))
  end
end

local function moduleUiDebug(message)
  if Dibs.DebugEnabled and Dibs.DebugEnabled("ui", 4) then uiDebug(message) end
end

local function widgetIdentity(widget)
  return widget and tostring(widget) or "nil"
end

local OFFICER_NAV_TREE = {
  { section = "OVERVIEW", text = "Dashboard", value = "overview" },
  { section = "OVERVIEW", text = "Setup Assistant", value = "setup" },
  { section = "DIBS", text = "Requests", value = "disputes", module = "requests" },
  { section = "DIBS", text = "Pre-Dibs", value = "preDibs", module = "preDibs" },
  { section = "DIBS", text = "Pending Awards", value = "pendingAwards" },
  { section = "DIBS", text = "History", value = "history" },
  { section = "DIBS", text = "Automatic Dibs", value = "automaticDibs" },
  { section = "DIBS", text = "Vault Review", value = "vault" },
  { section = "GUILD RULES", text = "Seasons", value = "seasons" },
  { section = "GUILD RULES", text = "Rank Rules", value = "ranks" },
  { section = "GUILD RULES", text = "Loot Rules", value = "lootTypes" },
  { section = "GUILD RULES", text = "Announcements", value = "announcements", module = "announcements" },
  { section = "INTEGRATIONS", text = "RCLootCouncil", value = "integration", module = "rclootcouncil" },
  { section = "SYSTEM", text = "Settings", value = "settings" },
  { section = "SYSTEM", text = "Modules", value = "modules" },
  { section = "SYSTEM", text = "Synchronization", value = "sync" },
  { section = "SYSTEM", text = "Diagnostics", value = "diagnostics" },
  { section = "SYSTEM", text = "Loot Eligibility", value = "eligibility", module = "lootEligibility" },
  { section = "DEVELOPER", text = "Developer", value = "developer" },
  { section = "DEVELOPER", text = "Debug", value = "debug" },
}

-- Keep the old programmatic names working for macros and existing tests while
-- presenting the same Officer tree as the RCLootCouncil options panel.
local OFFICER_TAB_ALIASES = {
  dashboard = "overview",
  requests = "disputes",
  lootRules = "lootTypes",
  rclootcouncil = "integration",
  predibs = "preDibs",
  dispute = "disputes",
  review = "disputes",
  historyReconciliation = "reconciliation",
  rcHistory = "reconciliation",
}

local canViewOfficerData

local function moduleEnabled(moduleKey)
  return not moduleKey or not Dibs.OperationalPolicy or not Dibs.OperationalPolicy.GetModuleStatus
    or Dibs.OperationalPolicy.GetModuleStatus(moduleKey).enabled == true
end

local function getOfficerNavigationTree()
  local role = Dibs.OfficerUI.GetPresentationRole()
  if role ~= "gm" and role ~= "officer" then return {} end
  local developerEnabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() == true
  local tree = {}
  for _, entry in ipairs(OFFICER_NAV_TREE) do
    if ((entry.value ~= "developer" and entry.value ~= "debug") or developerEnabled) and moduleEnabled(entry.module) then
      table.insert(tree, { section = entry.section, text = entry.text, value = entry.value })
    end
  end
  return tree
end

local function buildOfficerTree(entries)
  local sections, order = {}, {}
  for _, entry in ipairs(entries or {}) do
    if not sections[entry.section] then
      sections[entry.section] = { text = entry.section, value = "section_" .. string.lower((entry.section or ""):gsub("%s+", "_")), children = {} }
      table.insert(order, sections[entry.section])
    end
    table.insert(sections[entry.section].children, { text = entry.text, value = entry.value })
  end
  return order
end

local function normalizeOfficerTab(tab)
  local route = tab
  if type(tab) == "string" then
    local separator = string.char(1)
    for segment in tab:gmatch("[^" .. separator .. "]+") do route = segment end
  end
  return OFFICER_TAB_ALIASES[route] or route
end

local function officerTreeSelectionValue(route)
  for _, entry in ipairs(getOfficerNavigationTree()) do
    if entry.value == route then
      local section = "section_" .. string.lower((entry.section or ""):gsub("%s+", "_"))
      return section .. string.char(1) .. entry.value
    end
  end
  return route
end

local function officerRouteVisible(route)
  if (route == "developer" or route == "debug") and Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled then
    if Dibs.DeveloperMode.IsEnabled() == true then return true end
    if canViewOfficerData() then return true end
  end
  local routeModules = {
    disputes = "requests", preDibs = "preDibs", announcements = "announcements",
    integration = "rclootcouncil", eligibility = "lootEligibility",
  }
  if routeModules[route] and not moduleEnabled(routeModules[route]) then return false end
  for _, entry in ipairs(getOfficerNavigationTree()) do
    if entry.value == route then return true end
  end
  return route == "overview" or route == "reconciliation"
end

function Dibs.OfficerUI.GetNavigationTree()
  return getOfficerNavigationTree()
end

function Dibs.OfficerUI.GetPresentationRole()
  if Dibs.DeveloperSandbox and Dibs.DeveloperSandbox.IsActive and Dibs.DeveloperSandbox.IsActive()
    and Dibs.DeveloperSandbox.GetStatus then
    local status = Dibs.DeveloperSandbox.GetStatus()
    if status.role == "guild_master" then return "gm" end
    if status.role == "officer" then return "officer" end
    return "player"
  end
  if Dibs.Permissions and type(Dibs.Permissions.GetGuildRole) == "function" then
    local ok, role = pcall(Dibs.Permissions.GetGuildRole, nil)
    if ok then return role end
  end
  return "player"
end

-- Officer views contain the guild-wide ledger, Pre-Dibs history and rank
-- diagnostics.  Keep the authorization check at the read boundary so a
-- normal player cannot bypass the UI by calling these Lua functions directly.
canViewOfficerData = function()
  local role = Dibs.OfficerUI.GetPresentationRole()
  return role == "gm" or role == "officer"
end

local function trimText(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local REQUEST_STATUS_PRESENTATIONS = {
  ["Open"] = { label = "Open", nextAction = "Review request", explanation = "An Officer can review the request and its attached evidence." },
  ["Under review"] = { label = "Under review", nextAction = "Continue review", explanation = "An Officer is reviewing the request." },
  ["Need information"] = { label = "Need information", nextAction = "Reply to Officer", explanation = "The Officer requested more information before deciding." },
  pending = { label = "Pending", nextAction = "Wait for Officer confirmation", explanation = "The request is waiting for confirmation." },
  confirmed = { label = "Confirmed", nextAction = "Review before encounter", explanation = "The Pre-Dib is confirmed for the recorded item and difficulty." },
  fulfilled = { label = "Fulfilled", nextAction = "View history", explanation = "The request was fulfilled and remains available in history." },
  cancelled = { label = "Cancelled", nextAction = "View history", explanation = "The request was cancelled and cannot be reused." },
  invalidated = { label = "Unavailable", nextAction = "Contact an Officer", explanation = "This request is no longer available for the current workflow." },
  Resolved = { label = "Resolved", nextAction = "View resolution", explanation = "The Officer completed the review." },
  Rejected = { label = "Rejected", nextAction = "View resolution", explanation = "The Officer rejected the request with an audit reason." },
}

local function boundedPresentationText(value, limit)
  local text = trimText(value)
  local maximum = tonumber(limit) or 240
  if #text > maximum then return text:sub(1, maximum) end
  return text
end

local function requestStatusPresentation(status, unavailable)
  if unavailable == "SYNC_BEHIND" then
    return { label = "Syncing guild data", nextAction = "Try again shortly", explanation = "The request data is catching up. Try again shortly.", tone = "warning" }
  end
  if unavailable == "RECOVERY_PENDING" then
    return { label = "Recovery in progress", nextAction = "Try again later", explanation = "Guild Dibs is restoring shared request data.", tone = "warning" }
  end
  if unavailable then
    return { label = "Unavailable", nextAction = "Contact an Officer", explanation = "Request details are unavailable right now.", tone = "warning" }
  end
  local presentation = REQUEST_STATUS_PRESENTATIONS[status] or {
    label = tostring(status or "Unavailable"), nextAction = "Review status", explanation = "The request status is available for review.",
  }
  return { label = presentation.label, nextAction = presentation.nextAction, explanation = presentation.explanation, tone = "normal" }
end

local requestEvidencePresentation

local function requestPlayerPresentation(request)
  if request and request.privacyFiltered then return "" end
  return boundedPresentationText(request and request.player and request.player.name or request and request.playerName, 80)
end

local REQUEST_CATEGORY_PRESENTATIONS = {
  missing_debit = "Missing Dib",
  wrong_debit = "Incorrect removal",
  wrong_item_player = "Wrong player/item",
  wrong_recipient = "Wrong recipient",
  award_recipient_mismatch = "Award-recipient mismatch",
  predib_problem = "Pre-Dib problem",
  refund_request = "Refund request",
  history_problem = "History problem",
  general_dibs_question = "General Dibs question",
  other = "Other",
  duplicate = "Duplicate",
  eligibility = "Eligibility decision",
  integration = "Integration problem",
}

local REQUEST_CATEGORY_ALIASES = {
  missing_dibs = "missing_debit",
  incorrect_removal = "wrong_debit",
  wrong_item_or_player = "wrong_item_player",
  wrong_player_item = "wrong_item_player",
  pre_dib_problem = "predib_problem",
  general_question = "general_dibs_question",
}

local function requestCategoryPresentation(request)
  local raw = request and (request.category or request.categoryLabel)
  local key = string.lower(trimText(raw)):gsub("%s+", "_"):gsub("-", "_"):gsub("/", "_")
  key = REQUEST_CATEGORY_ALIASES[key] or key
  return REQUEST_CATEGORY_PRESENTATIONS[key] or "Other"
end

local function buildOfficerRequestRow(request)
  local evidence = request and request.evidence and request.evidence[1] or {}
  local status = requestStatusPresentation(request and request.status, request and (request.unavailable or request.status == "Unavailable"))
  local summary = requestEvidencePresentation(request, evidence)
  return {
    requestId = request and request.requestId,
    status = status,
    nextAction = status.nextAction,
    explanation = status.explanation,
    details = {
      player = summary.player,
      category = summary.issue,
      item = summary.item,
      note = summary.note,
      source = boundedPresentationText(evidence.source, 80),
      evidence = summary.evidence,
    },
  }
end

requestEvidencePresentation = function(request, evidence)
  evidence = evidence or {}
  local unavailable = type(evidence.unavailableFields) == "table" and #evidence.unavailableFields > 0
  local hasItem = trimText(evidence.item or evidence.itemID) ~= ""
  local hasSource = trimText(evidence.source) ~= ""
  return {
    player = requestPlayerPresentation(request),
    item = boundedPresentationText(evidence.item or evidence.itemID, 180),
    issue = requestCategoryPresentation(request),
    note = boundedPresentationText(request and request.note, 240),
    evidence = (unavailable or not hasItem or not hasSource) and "Evidence incomplete" or "Evidence available",
  }
end

---@param request table|nil Permission-filtered request record.
---@return table projection Transient support-ticket detail projection.
function Dibs.OfficerUI.BuildRequestDetailView(request)
  request = type(request) == "table" and request or {}
  local evidence = request.evidence and request.evidence[1] or {}
  local status = requestStatusPresentation(request.status, request.unavailable or request.status == "Unavailable")
  return {
    requestId = request.requestId,
    status = status,
    nextAction = status.nextAction,
    explanation = status.explanation,
    summary = requestEvidencePresentation(request, evidence),
  }
end

local function buildPreDibRow(request)
  local status = requestStatusPresentation(request and request.status)
  return {
    requestId = request and request.requestId,
    status = status,
    nextAction = status.nextAction,
    explanation = status.explanation,
    details = {
      player = boundedPresentationText(request and request.playerName, 80),
      item = boundedPresentationText(request and (request.itemName or request.itemLink or request.itemID), 180),
      difficulty = boundedPresentationText(request and request.difficulty, 32),
      mode = boundedPresentationText(request and request.modeAtCreation, 32),
      delivery = boundedPresentationText(request and request.delivery and request.delivery.state, 32),
    },
  }
end

---@param scope string "officer" or "player".
---@param filter table|nil Permission-filtered request options.
---@return table rows Bounded request rows for the requested scope.
function Dibs.OfficerUI.BuildRequestView(scope, filter)
  filter = type(filter) == "table" and filter or {}
  if scope == "player" then
    return {}
  end
  if not canViewOfficerData() then
    return {}
  end
  local source, reason
  if filter.kind == "predibs" then
    source = Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}
  elseif Dibs.Disputes and Dibs.Disputes.ListForOfficer then
    source, reason = Dibs.Disputes.ListForOfficer(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, filter)
  else
    source = {}
  end
  if reason then return {} end
  local rows, limit = {}, math.max(1, math.min(50, tonumber(filter.limit) or 25))
  for _, request in ipairs(source or {}) do
    if #rows >= limit then break end
    if filter.kind == "predibs" then
      table.insert(rows, buildPreDibRow(request))
    else
      table.insert(rows, buildOfficerRequestRow(request))
    end
  end
  return rows
end

local ELIGIBILITY_CATEGORY_DEFINITIONS = {
  { key = "curio", label = "Curio", family = "TOKEN", recommended = "allow", reasonCode = "CURIO_POLICY", reason = "Curio progress follows the active protected-loot policy." },
  { key = "tier_set", label = "Tier Set", family = "TOKEN_SET", recommended = "allow", reasonCode = "TIER_SET_POLICY", reason = "Tier Set progress follows the class-token policy." },
  { key = "token", label = "Token", family = "TOKEN", recommended = "allow", reasonCode = "TOKEN_POLICY", reason = "Recognized progression tokens are eligible for the current round." },
  { key = "mount", label = "Mount", family = "MOUNTS", recommended = "block", reasonCode = "NON_PROGRESSION_FAMILY", reason = "Mounts are not a protected progression family in the Recommended preset." },
  { key = "pet", label = "Pet", family = "PETS", recommended = "block", reasonCode = "NON_PROGRESSION_FAMILY", reason = "Pets are not a protected progression family in the Recommended preset." },
  { key = "cosmetic", label = "Cosmetic", family = "COSMETIC", recommended = "block", reasonCode = "COSMETIC_PERSONAL", reason = "Cosmetic items do not use Dibs eligibility." },
  { key = "catalyst", label = "Catalyst", family = "CATALYST", recommended = "block", reasonCode = "CATALYST_PERSONAL", reason = "Catalyst progress is personal and cannot use Dibs." },
}

local function copyProjection(value)
  if Dibs.DeepCopy then return Dibs.DeepCopy(value) end
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copyProjection(item) end
  return result
end

---@param seasonId string|number|nil Season scope.
---@param options table|nil Expansion and unsaved draft options.
---@return table projection Recommended-first eligibility presentation.
function Dibs.OfficerUI.GetEligibilityProjection(seasonId, options)
  options = type(options) == "table" and options or {}
  if not canViewOfficerData() then return { hidden = true, categories = {}, byFamily = {} } end
  local projection = {
    preset = { key = "recommended", label = "Recommended", description = "Common progression loot first; personal and collection items stay blocked." },
    customize = { visible = true, label = "Customize" },
    advanced = { expanded = options.expanded == true },
    seasonId = seasonId,
    categories = {},
    byFamily = {},
    unsaved = type(options.draft) == "table" and next(options.draft) ~= nil or false,
  }
  for _, definition in ipairs(ELIGIBILITY_CATEGORY_DEFINITIONS) do
    local category = {
      key = definition.key, label = definition.label, semanticFamily = definition.family,
      state = definition.recommended, reasonCode = definition.reasonCode, reason = definition.reason,
      editable = definition.family == "TOKEN" or definition.family == "TOKEN_SET",
      customizable = definition.family ~= "CATALYST",
      currentState = { enabled = definition.recommended == "allow", source = "recommended" },
    }
    if (definition.family == "TOKEN" or definition.family == "TOKEN_SET") and Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetPolicy then
      local policy = Dibs.CharacterEligibility.GetPolicy(seasonId, definition.family)
      category.currentState = copyProjection(policy or category.currentState)
      local draft = options.draft and options.draft[definition.family]
      if type(draft) == "table" then
        for key, value in pairs(draft) do category.currentState[key] = copyProjection(value) end
      end
      if category.currentState.enabled == false then category.state = "block" end
      projection.byFamily[definition.family] = category
    end
    if projection.advanced.expanded then
      category.advanced = { semanticCategory = definition.label, reason = definition.reason, currentState = copyProjection(category.currentState) }
    end
    table.insert(projection.categories, category)
  end
  return projection
end

local function emptyOfficerPage(view, query)
  local selectedView = view == "actions" and "actions" or (view == "predibs" and "predibs" or "players")
  local title = selectedView == "actions" and "Actions"
    or (selectedView == "predibs" and "Pre-Dibs" or "Players")
  return {
    title = title,
    lines = { "Officer access required." },
    page = 1,
    totalPages = 1,
    totalCount = 0,
    query = string.lower(tostring(query or "")),
    hiddenCount = 0,
  }
end

local HAS_DROPDOWN = type(_G.UIDropDownMenu_Initialize) == "function"
  and type(_G.UIDropDownMenu_CreateInfo) == "function"
  and type(_G.UIDropDownMenu_AddButton) == "function"
  and type(_G.UIDropDownMenu_SetText) == "function"

local function sortedLabels(values)
  local entries = {}
  for key, label in pairs(values or {}) do
    table.insert(entries, { key = key, label = label })
  end
  table.sort(entries, function(a, b) return tostring(a.label) < tostring(b.label) end)
  local result = {}
  for _, entry in ipairs(entries) do result[entry.key] = entry.label end
  return result
end

local function disputeStatusText(request)
  if not request then return "" end
  return tostring(request.status or "Open") .. " | " .. tostring(request.categoryLabel or request.category or "Other")
end

local function setControlText(control, text)
  if not control then
    return
  end
  control._dibsText = tostring(text or "")
  if control.SetText then
    control:SetText(control._dibsText)
  end
end

local function getControlText(control)
  if not control then
    return ""
  end
  if control.GetText then
    local ok, value = pcall(control.GetText, control)
    if ok then
      return tostring(value or "")
    end
  end
  return tostring(control._dibsText or "")
end

local function setDropdownText(control, text)
  if control and HAS_DROPDOWN and _G.UIDropDownMenu_SetText then
    _G.UIDropDownMenu_SetText(control, tostring(text or ""))
  elseif control and control.SetText then
    control:SetText(tostring(text or ""))
  end
end

local function setControlsVisible(controls, visible)
  for _, control in ipairs(controls or {}) do
    if control then
      if visible and control.Show then
        control:Show()
      elseif not visible and control.Hide then
        control:Hide()
      end
    end
  end
end

local function formatHistoryDate(timestamp, fallback)
  local value = tonumber(timestamp)
  if type(date) == "function" and value and value > 0 then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", value)
    if ok and formatted then
      return tostring(formatted)
    end
  end
  local text = trimText(fallback)
  if text ~= "" and not text:match("^0[%s:/%-]*0?$") then return text end
  return "Unknown date"
end

local HISTORY_REVIEW_LABELS = {
  HISTORY_FINAL_STATUS_INFERRED = "Final status inferred from RC history",
  HISTORY_FINAL_STATUS_UNKNOWN = "Final status missing",
  HISTORY_RESPONSE_IDENTITY_AMBIGUOUS = "Response identity needs review",
  HISTORY_IDENTITY_REQUIRED = "Stable history identity missing",
  HISTORY_UNSUPPORTED = "Item or winner is missing",
  HISTORY_NON_FINAL = "Award is not finalized",
  HISTORY_ALREADY_ACCOUNTED = "Already transferred",
  HISTORY_REJECTED_BY_OFFICER = "Rejected by Officer",
  NON_DIB_RESPONSE = "Response is not a DIB alias",
}

local function historyReviewLabel(candidate)
  local sourceReason = trimText(candidate and candidate.awardReason)
  if sourceReason ~= "" then return sourceReason end
  local code = tostring(candidate and candidate.reasonCode or "ready")
  return HISTORY_REVIEW_LABELS[code] or code
end

local function configureDropdown(control, width, initializer)
  if not control or not HAS_DROPDOWN then
    return false
  end
  if _G.UIDropDownMenu_SetWidth then
    _G.UIDropDownMenu_SetWidth(control, width or 120)
  end
  if _G.UIDropDownMenu_JustifyText then
    _G.UIDropDownMenu_JustifyText(control, "LEFT")
  end
  _G.UIDropDownMenu_Initialize(control, initializer)
  return true
end

local function getSeasonList()
  local seasons = Dibs.Seasons and Dibs.Seasons.List and Dibs.Seasons.List() or {}
  table.sort(seasons, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)
  return seasons
end

local function findSeasonById(seasonId)
  return Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId) or nil
end

local function getSelectedSeason(frame)
  local selected = frame and frame.selectedSeasonId or nil
  local season = selected and findSeasonById(selected) or nil
  if season and not season.isArchived then
    return season
  end
  return Dibs.Seasons and Dibs.Seasons.GetCurrent and Dibs.Seasons.GetCurrent() or nil
end

local function getGuildRankNames()
  local names = {}

  if type(_G.GuildControlGetNumRanks) == "function" and type(_G.GuildControlGetRankName) == "function" then
    local okCount, rankCount = pcall(_G.GuildControlGetNumRanks)
    if okCount and tonumber(rankCount) then
      for i = 1, tonumber(rankCount) do
        local okName, rankName = pcall(_G.GuildControlGetRankName, i)
        if okName and rankName and rankName ~= "" then
          names[i - 1] = tostring(rankName)
        end
      end
    end
  end

  if next(names) == nil and type(_G.GetNumGuildMembers) == "function" and type(_G.GetGuildRosterInfo) == "function" then
    local memberCount = _G.GetNumGuildMembers()
    local count = tonumber(memberCount) or 0
    for i = 1, count do
      local _, rankName, rankIndex = _G.GetGuildRosterInfo(i)
      local idx = tonumber(rankIndex)
      if idx ~= nil and rankName and rankName ~= "" and names[idx] == nil then
        names[idx] = tostring(rankName)
      end
    end
  end

  for idx, fallback in pairs(RANK_LABELS) do
    if names[idx] == nil then
      names[idx] = fallback
    end
  end

  return names
end

local function getCurrentGuildMemberNames()
  if type(_G.GetNumGuildMembers) ~= "function" or type(_G.GetGuildRosterInfo) ~= "function" then
    return nil
  end

  local memberNames = {}
  local memberCount = _G.GetNumGuildMembers()
  local count = tonumber(memberCount) or 0
  for index = 1, count do
    local name = _G.GetGuildRosterInfo(index)
    if name and name ~= "" then
      local fullName = string.lower(tostring(name))
      memberNames[fullName] = tostring(name)
      local shortName = fullName:match("^([^-]+)")
      if shortName then
        memberNames[shortName] = tostring(name)
      end
    end
  end

  return next(memberNames) and memberNames or nil
end

local function getCurrentGuildMemberName(memberNames, playerName)
  if not memberNames then
    return tostring(playerName or "Unknown")
  end
  local fullName = string.lower(tostring(playerName or ""))
  local shortName = fullName:match("^([^-]+)")
  return memberNames[fullName] or (shortName ~= nil and memberNames[shortName]) or nil
end

local function classColorCode(classFileName)
  local colors = _G.RAID_CLASS_COLORS
  local color = colors and classFileName and colors[classFileName]
  return color and color.colorStr or "ffffffff"
end

local function buildGuildMemberChoices(query, selectedName)
  local roster = getCurrentGuildMemberNames() or {}
  local unique = {}
  for _, name in pairs(roster) do
    if name and name ~= "" then unique[tostring(name)] = true end
  end

  local needle = string.lower(trimText(query))
  local values = {}
  local count = 0
  for name in pairs(unique) do
    local matches = needle == "" or string.find(string.lower(name), needle, 1, true) ~= nil
    if matches or (selectedName and string.lower(name) == string.lower(tostring(selectedName))) then
      values[name] = name
      count = count + 1
    end
  end
  return sortedLabels(values), count
end

local function normalizeCandidateText(value)
  return string.lower(trimText(value))
end

local function itemCandidateContext(request, evidence)
  local attached = request and request.attachedContext or {}
  local current = Dibs.EncounterJournal and Dibs.EncounterJournal.GetCurrentLootContext
    and Dibs.EncounterJournal.GetCurrentLootContext() or {}
  return {
    explicitInstanceID = tonumber(attached.instanceID or attached.raidID or attached.dungeonID or evidence and evidence.instanceID),
    expansionID = attached.expansionID or evidence and evidence.expansionID,
    seasonID = attached.seasonID or evidence and evidence.seasonID,
    instanceID = tonumber(attached.instanceID or attached.raidID or attached.dungeonID or evidence and evidence.instanceID),
    instanceName = attached.instanceName or attached.raidName or attached.dungeonName or evidence and evidence.instanceName
      or nil,
    encounterID = tonumber(attached.encounterID or evidence and evidence.encounterID or current.encounterID),
    encounterName = attached.encounterName or attached.bossName or evidence and evidence.encounterName
      or current.encounterName,
  }
end

local function getCurrentExpansionID()
  if type(_G.GetExpansionLevel) == "function" then
    local ok, level = pcall(_G.GetExpansionLevel)
    if ok and tonumber(level) then return tonumber(level) end
  end
  return nil
end

local function expansionLabel(expansionID)
  local key = tonumber(expansionID)
  local label = key and _G["EXPANSION_NAME" .. tostring(key)] or nil
  return type(label) == "string" and label ~= "" and label or (key and ("Expansion " .. tostring(key)) or "Unknown expansion")
end

local function filterValue(value)
  local text = trimText(value)
  return text ~= "" and text or nil
end

local function addFilterChoice(values, key, label)
  if key ~= nil and tostring(key) ~= "" then values[tostring(key)] = tostring(label or key) end
end

local function buildAdventureGuideFilterChoices(catalog, state)
  local expansions, seasons, raids, bosses = { [""] = "All expansions" }, { [""] = "All seasons" }, { [""] = "All raids" }, { [""] = "All bosses" }
  local expansionSet, seasonSet, raidSet, bossSet = {}, {}, {}, {}
  for _, item in ipairs(catalog or {}) do
    local expansionID = item.expansionID and tostring(item.expansionID) or nil
    if expansionID and not expansionSet[expansionID] then
      expansionSet[expansionID] = true
      addFilterChoice(expansions, expansionID, expansionLabel(expansionID))
    end
  end
  local selectedExpansion = filterValue(state and state.expansionID)
  local selectedSeason = filterValue(state and state.seasonID)
  for _, item in ipairs(catalog or {}) do
    if not selectedExpansion or tostring(item.expansionID) == selectedExpansion then
      local seasonID = item.seasonID and tostring(item.seasonID) or nil
      if seasonID and not seasonSet[seasonID] then
        seasonSet[seasonID] = true
        addFilterChoice(seasons, seasonID, item.seasonName or seasonID)
      end
    end
  end
  for _, item in ipairs(catalog or {}) do
    local inExpansion = not selectedExpansion or tostring(item.expansionID) == selectedExpansion
    local inSeason = not selectedSeason or tostring(item.seasonID) == selectedSeason
    if inExpansion and inSeason then
      local raidID = item.instanceID and tostring(item.instanceID) or nil
      if raidID and not raidSet[raidID] then
        raidSet[raidID] = true
        addFilterChoice(raids, raidID, item.instanceName)
      end
    end
  end
  local selectedRaid = filterValue(state and state.raidID)
  for _, item in ipairs(catalog or {}) do
    local inExpansion = not selectedExpansion or tostring(item.expansionID) == selectedExpansion
    local inSeason = not selectedSeason or tostring(item.seasonID) == selectedSeason
    local inRaid = not selectedRaid or tostring(item.instanceID) == selectedRaid
    if inExpansion and inSeason and inRaid then
      local bossID = item.encounterID and tostring(item.encounterID) or nil
      if bossID and not bossSet[bossID] then
        bossSet[bossID] = true
        addFilterChoice(bosses, bossID, item.bossName .. " (" .. bossID .. ")")
      end
    end
  end
  return sortedLabels(expansions), sortedLabels(seasons), sortedLabels(raids), sortedLabels(bosses), {
    hasSeasonMetadata = next(seasonSet) ~= nil,
    hasExpansionMetadata = next(expansionSet) ~= nil,
  }
end

local function isSafeDibsCandidate(item)
  local rclc = Dibs.RCLootCouncil
  if type(rclc) ~= "table" or type(rclc.GetItemSemanticFamily) ~= "function"
    or type(rclc.IsItemDibTypeAllowed) ~= "function" then
    return false
  end
  local family = rclc.GetItemSemanticFamily(tonumber(item.itemID), item.responseType)
  if not family or tostring(family) == "" or tostring(family) == "UNKNOWN" then return false end
  local ok, allowed = pcall(rclc.IsItemDibTypeAllowed, tonumber(item.itemID), item.responseType, { strictWhitelist = true })
  return ok and allowed == true
end

local function itemMatchesScope(item, context)
  if context.expansionID and tostring(item.expansionID) ~= tostring(context.expansionID) then return false end
  if context.seasonID and tostring(item.seasonID) ~= tostring(context.seasonID) then return false end
  if context.raidID and tostring(item.instanceID) ~= tostring(context.raidID) then return false end
  if context.bossID and tostring(item.encounterID) ~= tostring(context.bossID) then return false end
  if context.instanceID and tostring(item.instanceID) ~= tostring(context.instanceID) then return false end
  if not context.instanceID and trimText(context.instanceName) ~= ""
    and normalizeCandidateText(item.instanceName) ~= normalizeCandidateText(context.instanceName) then return false end
  return true
end

local function buildAdventureGuideItemChoices(catalog, query, selectedKey, maxResults, context)
  local needle = string.lower(trimText(query))
  local resultLimit = math.max(1, tonumber(maxResults) or 200)
  local values = {}
  local ranked = {}
  local count = 0
  local matchingCatalogItems = 0
  for _, item in ipairs(catalog or {}) do
    if itemMatchesScope(item, context or {}) then
      local searchable = string.lower(table.concat({ tostring(item.itemName or ""), tostring(item.itemID or ""), tostring(item.bossName or ""), tostring(item.encounterID or ""), tostring(item.instanceName or ""), tostring(item.expansionName or "") }, " "))
      local matches = needle == "" or string.find(searchable, needle, 1, true) ~= nil
      if matches then
        matchingCatalogItems = matchingCatalogItems + 1
        local selected = selectedKey and tostring(item.key) == tostring(selectedKey)
        if isSafeDibsCandidate(item) or selected then
          local rank = context and context.encounterID and tonumber(item.encounterID) == context.encounterID and 0 or 1
          table.insert(ranked, { item = item, rank = rank })
        end
      end
    end
  end
  table.sort(ranked, function(left, right)
    local leftItem, rightItem = left.item, right.item
    if left.rank ~= right.rank then return left.rank < right.rank end
    local leftName = string.lower(tostring(leftItem.itemName or ""))
    local rightName = string.lower(tostring(rightItem.itemName or ""))
    if leftName ~= rightName then return leftName < rightName end
    return tostring(leftItem.itemID or "") < tostring(rightItem.itemID or "")
  end)
  for _, entry in ipairs(ranked) do
    if count >= resultLimit and not (selectedKey and tostring(entry.item.key) == tostring(selectedKey)) then break end
    local item = entry.item
    local contextParts = {}
    if trimText(item.expansionName) ~= "" then table.insert(contextParts, tostring(item.expansionName)) end
    if trimText(item.seasonName) ~= "" then table.insert(contextParts, tostring(item.seasonName)) end
    if trimText(item.instanceName) ~= "" then table.insert(contextParts, tostring(item.instanceName)) end
    if trimText(item.bossName) ~= "" and item.bossName ~= "Unknown boss" then
      table.insert(contextParts, tostring(item.bossName) .. " (" .. tostring(item.encounterID or "?") .. ")")
    end
    table.insert(contextParts, tostring(item.itemName or ("Item " .. tostring(item.itemID))) .. " (" .. tostring(item.itemID or "?") .. ")")
    local label = table.concat(contextParts, " | ")
    values[tostring(item.key)] = label
    count = count + 1
  end
  return sortedLabels(values), count, matchingCatalogItems > 0 and count == 0
end

local function getRankName(rankIndex)
  local idx = tonumber(rankIndex) or 0
  local names = getGuildRankNames()
  return names[idx] or ("Rank " .. tostring(idx))
end

local function buildRankLabel(rankIndex)
  local idx = tonumber(rankIndex) or 0
  return tostring(idx) .. " - " .. getRankName(idx)
end

local function getExpansionName()
  if type(_G.GetExpansionLevel) == "function" then
    local ok, level = pcall(_G.GetExpansionLevel)
    local idx = ok and tonumber(level) or nil
    if idx then
      local current = _G["EXPANSION_NAME" .. tostring(idx)]
      if type(current) == "string" and current ~= "" then
        return current
      end
    end
  end

  if type(_G.GetBuildInfo) == "function" then
    local ok, _, _, interfaceVersion = pcall(_G.GetBuildInfo)
    local iv = ok and tonumber(interfaceVersion) or nil
    if iv then
      local idx = math.floor(iv / 10000)
      local fromBuild = _G["EXPANSION_NAME" .. tostring(idx)]
      if type(fromBuild) == "string" and fromBuild ~= "" then
        return fromBuild
      end
    end
  end

  for i = 1, 20 do
    local name = _G["EXPANSION_NAME" .. tostring(i)]
    if type(name) == "string" and name ~= "" and not string.find(name, "^Expansion%d+$") then
      return name
    end
  end

  return "Season"
end

local function getDefaultSeasonName()
  local count = #getSeasonList()
  local expansion = tostring(getExpansionName()):gsub("%s+", "")
  if expansion == "" then
    expansion = "Season"
  end
  return expansion .. "_Season" .. tostring(count + 1)
end

local function normalizeSeasonName(name)
  return trimText(name):lower()
end

local function findSeasonByName(name, excludeSeasonId)
  local needle = normalizeSeasonName(name)
  if needle == "" then
    return nil
  end
  for _, season in ipairs(getSeasonList()) do
    if season.id ~= excludeSeasonId and normalizeSeasonName(season.name) == needle then
      return season
    end
  end
  return nil
end

local function makeUniqueSeasonName(name)
  local base = trimText(name)
  if base == "" then
    base = getDefaultSeasonName()
  end
  if not findSeasonByName(base, nil) then
    return base
  end

  local suffix = 2
  while suffix < 999 do
    local candidate = base .. "_" .. tostring(suffix)
    if not findSeasonByName(candidate, nil) then
      return candidate
    end
    suffix = suffix + 1
  end

  return base .. "_dup"
end

local function applyRankRule(frame, row)
  local season = getSelectedSeason(frame)
  if not season then
    frame:SetStatus("No active season available.")
    return
  end

  local rankIndex = tonumber(row.rankIndex) or 0
  local allocation = tonumber(row.allocation) or 0
  if allocation < 0 then
    allocation = 0
  end

  local result = Dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = season.id,
    rankIndex = rankIndex,
    rankName = getRankName(rankIndex),
    allocation = allocation,
  })

  frame:SetStatus(result.ok and ("Saved " .. buildRankLabel(rankIndex) .. " = " .. tostring(allocation)) or result.diagnostic)
  frame:Refresh()
end

local function refreshRankRowVisual(row)
  if not row then
    return
  end
  if row.rankButton then
    row.rankButton:SetText(buildRankLabel(row.rankIndex))
  end
  if row.rankDropdown then
    setDropdownText(row.rankDropdown, buildRankLabel(row.rankIndex))
  end
  if row.valueText then
    row.valueText:SetText("Dibs: " .. tostring(row.allocation))
  end
end

local function createRankRow(frame, index)
  local row = CreateFrame("Frame", nil, frame)
  row:SetSize(600, 24)
  row:SetPoint("TOPLEFT", 14, -310 - ((index - 1) * 26))
  row.rankIndex = index - 1
  row.allocation = 1

  local rankButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  rankButton:SetSize(160, 22)
  rankButton:SetPoint("LEFT", 0, 0)
  rankButton:SetScript("OnClick", function()
    row.rankIndex = ((tonumber(row.rankIndex) or 0) + 1) % 10
    refreshRankRowVisual(row)
  end)
  row.rankButton = rankButton

  if HAS_DROPDOWN then
    local rankDropdown = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
    rankDropdown:SetPoint("LEFT", -12, 0)
    configureDropdown(rankDropdown, 150, function(_, level)
      if level ~= 1 then
        return
      end
      local maxRank = math.max(9, (_G.GuildControlGetNumRanks and _G.GuildControlGetNumRanks() - 1) or 9)
      for idx = 0, maxRank do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = buildRankLabel(idx)
        info.func = function()
          row.rankIndex = idx
          refreshRankRowVisual(row)
        end
        info.checked = tonumber(row.rankIndex) == idx
        _G.UIDropDownMenu_AddButton(info, level)
      end
    end)
    row.rankDropdown = rankDropdown
    if row.rankButton.Hide then
      row.rankButton:Hide()
    end
  end

  local minusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  minusButton:SetSize(28, 22)
  minusButton:SetPoint("LEFT", rankButton, "RIGHT", 8, 0)
  minusButton:SetText("-")
  minusButton:SetScript("OnClick", function()
    row.allocation = math.max(0, (tonumber(row.allocation) or 0) - 1)
    refreshRankRowVisual(row)
  end)

  local plusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  plusButton:SetSize(28, 22)
  plusButton:SetPoint("LEFT", minusButton, "RIGHT", 4, 0)
  plusButton:SetText("+")
  plusButton:SetScript("OnClick", function()
    row.allocation = (tonumber(row.allocation) or 0) + 1
    refreshRankRowVisual(row)
  end)

  local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  valueText:SetPoint("LEFT", plusButton, "RIGHT", 10, 0)
  valueText:SetWidth(90)
  valueText:SetJustifyH("LEFT")
  row.valueText = valueText

  local applyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  applyButton:SetSize(72, 22)
  applyButton:SetPoint("LEFT", valueText, "RIGHT", 8, 0)
  applyButton:SetText("Set")
  applyButton:SetScript("OnClick", function()
    applyRankRule(frame, row)
  end)

  refreshRankRowVisual(row)
  return row
end

local function syncRowsToSeason(frame, season)
  local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason and Dibs.RankRules.GetRulesForSeason(season and season.id or Dibs.GetCurrentSeasonId()) or {}
  local list = {}
  for _, rule in pairs(rules) do
    table.insert(list, rule)
  end
  table.sort(list, function(a, b)
    return (a.rankIndex or 0) < (b.rankIndex or 0)
  end)

  if #list == 0 then
    list = {
      { rankIndex = 0, allocation = 1 },
      { rankIndex = 1, allocation = 1 },
    }
  end

  for i, row in ipairs(frame.rankRows or {}) do
    local source = list[i]
    if source then
      row.rankIndex = tonumber(source.rankIndex) or 0
      row.allocation = tonumber(source.allocation) or 0
      if row.Show then
        row:Show()
      end
      refreshRankRowVisual(row)
    elseif row.Hide then
      row:Hide()
    end
  end
end

function Dibs.OfficerUI.GetLedgerOverview()
  if not canViewOfficerData() then
    return { count = 0, transactions = {}, isOfficer = false, hidden = true }
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {}
  return {
    count = #transactions,
    transactions = transactions,
    isOfficer = Dibs.Permissions and Dibs.Permissions.IsOfficer() or false,
  }
end

function Dibs.OfficerUI.BuildLedgerDetails(seasonId, filter)
  if not canViewOfficerData() then
    return { players = {}, actions = {}, transactionCount = 0, hiddenTransactionCount = 0, hidden = true }
  end
  filter = type(filter) == "table" and filter or {}
  local allTransactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(seasonId) or {}
  local memberNames = getCurrentGuildMemberNames()
  local transactions = {}
  local hiddenTransactionCount = 0
  for _, tx in ipairs(allTransactions) do
    local playerName = getCurrentGuildMemberName(memberNames, tx.playerName or tx.playerKey or tx.playerId)
    local timestamp = tonumber(tx.createdAt or tx.timestamp) or 0
    local matchesPlayer = not filter.playerName or string.lower(playerName or "") == string.lower(tostring(filter.playerName))
    local matchesType = not filter.actionType or tostring(tx.type or tx.actionType) == tostring(filter.actionType)
    local matchesSource = not filter.source or tostring(tx.source or "") == tostring(filter.source)
    local matchesFrom = not filter.fromTime or timestamp >= tonumber(filter.fromTime)
    local matchesTo = not filter.toTime or timestamp <= tonumber(filter.toTime)
    if playerName and matchesPlayer and matchesType and matchesSource and matchesFrom and matchesTo then
      table.insert(transactions, { transaction = tx, playerName = playerName })
    else
      hiddenTransactionCount = hiddenTransactionCount + 1
    end
  end
  local players = {}

  for _, entry in ipairs(transactions) do
    local tx = entry.transaction
    local playerName = entry.playerName
    local playerKey = string.lower(playerName)
    if not players[playerKey] then
      local rankInfo = Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo and Dibs.RankRules.GetPlayerRankInfo(playerName) or {}
      local allocation = Dibs.RankRules and Dibs.RankRules.GetAllocation and Dibs.RankRules.GetAllocation(seasonId, rankInfo.rankIndex) or 0
      players[playerKey] = {
        name = playerName,
        balance = tonumber(allocation) or 0,
        count = 0,
      }
    end
    players[playerKey].count = players[playerKey].count + 1
    if tx.type ~= "SEASON_ALLOCATION" then
      players[playerKey].balance = players[playerKey].balance + (tonumber(tx.amount or tx.quantityDelta) or 0)
    end
  end

  local playerLines = {}
  for _, player in pairs(players) do
    table.insert(playerLines, player.name .. " | " .. tostring(player.balance) .. " dibs | " .. tostring(player.count) .. " actions")
  end
  table.sort(playerLines)

  table.sort(transactions, function(a, b)
    local first = a.transaction
    local second = b.transaction
    return (first.createdAt or first.timestamp or 0) > (second.createdAt or second.timestamp or 0)
  end)
  local actionLines = {}
  for index = 1, #transactions do
    local entry = transactions[index]
    local tx = entry.transaction
    local amount = tonumber(tx.amount or tx.quantityDelta) or 0
    local sign = amount >= 0 and "+" or ""
    table.insert(actionLines, formatHistoryDate(tx.createdAt or tx.timestamp) .. " | " .. entry.playerName .. " | " .. tostring(tx.type or tx.actionType or "UNKNOWN") .. " | " .. sign .. tostring(amount) .. " | " .. tostring(tx.reason or ""))
  end

  return {
    players = playerLines,
    actions = actionLines,
    transactionCount = #transactions,
    hiddenTransactionCount = hiddenTransactionCount,
  }
end

function Dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId)
  if not canViewOfficerData() then
    return { allocations = {}, hiddenTransactionCount = 0, hidden = true }
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(seasonId) or {}
  local roster = {}
  if type(_G.GetNumGuildMembers) == "function" and type(_G.GetGuildRosterInfo) == "function" then
    for index = 1, _G.GetNumGuildMembers() do
      local name, rankName, rankIndex, _, className, _, _, _, _, _, classFileName = _G.GetGuildRosterInfo(index)
      if name and name ~= "" then
        roster[string.lower(tostring(name))] = {
          playerName = tostring(name), rankName = rankName, rankIndex = tonumber(rankIndex), className = className, classFileName = classFileName,
        }
      end
    end
  end
  local rows = {}
  local assignedPlayers = {}
  for _, tx in ipairs(transactions) do
    local isAssignment = tx.source == "automatic_rank_assignment"
      or tx.source == "rank_reconciliation"
      or tx.source == "manual_live_adjustment"
    if isAssignment then
      local amount = tonumber(tx.amount or tx.quantityDelta) or 0
      local playerName = tx.playerName or tx.playerKey or "Unknown"
      assignedPlayers[string.lower(tostring(playerName))] = true
      local rosterInfo = roster[string.lower(tostring(playerName))] or {}
      local rankInfo = Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo and Dibs.RankRules.GetPlayerRankInfo(playerName) or {}
      local source = tx.source or "system"
      local action = source == "automatic_rank_assignment" and "Auto"
        or (source == "manual_live_adjustment" and ((tx.context and tx.context.authority) or "GM/Officer") or "Roster reconciliation")
      local balance = Dibs.Ledger.GetBalance(playerName, seasonId)
      table.insert(rows, {
        timestamp = tx.createdAt or tx.timestamp or 0,
        dateText = formatHistoryDate(tx.createdAt or tx.timestamp),
        playerName = "|c" .. classColorCode(rosterInfo.classFileName) .. playerName .. "|r",
        plainPlayerName = playerName,
        className = rosterInfo.className,
        classFileName = rosterInfo.classFileName,
        rankIndex = tonumber(tx.rankIndex) or tonumber(rosterInfo.rankIndex) or tonumber(rankInfo.rankIndex),
        rankName = tx.rankName or rosterInfo.rankName or rankInfo.rankName or "",
        expected = tonumber(tx.expectedAllocation) or (Dibs.RankRules and Dibs.RankRules.GetAllocationForPlayer and Dibs.RankRules.GetAllocationForPlayer(playerName, seasonId) or 0),
        amount = amount,
        balance = tonumber(balance) or 0,
        action = action,
        reason = tx.reason or "Automatic rank allocation",
      })
    end
  end
  if #rows == 0 then
    for _, member in pairs(roster) do
      local expected = Dibs.RankRules and Dibs.RankRules.GetAllocationForPlayer
        and Dibs.RankRules.GetAllocationForPlayer(member.playerName, seasonId) or 0
      local balance = Dibs.Ledger.GetBalance(member.playerName, seasonId)
      local missing = math.max(0, expected - balance)
      table.insert(rows, {
        timestamp = 0,
        dateText = "Current",
        playerName = "|c" .. classColorCode(member.classFileName) .. member.playerName .. "|r",
        plainPlayerName = member.playerName,
        className = member.className,
        classFileName = member.classFileName,
        rankIndex = member.rankIndex,
        rankName = member.rankName or "Guild Member",
        expected = expected,
        amount = balance,
        balance = balance,
        action = missing > 0 and "Pending auto" or "Current",
        reason = missing > 0 and ("Missing " .. tostring(missing) .. " Dibs") or "No assignment event recorded yet",
      })
    end
  else
    for playerKey, member in pairs(roster) do
      if not assignedPlayers[playerKey] then
        local expected = Dibs.RankRules and Dibs.RankRules.GetAllocationForPlayer
          and Dibs.RankRules.GetAllocationForPlayer(member.playerName, seasonId) or 0
        local balance = Dibs.Ledger.GetBalance(member.playerName, seasonId)
        local missing = math.max(0, expected - balance)
        table.insert(rows, {
          timestamp = 0,
          dateText = "Current",
          playerName = "|c" .. classColorCode(member.classFileName) .. member.playerName .. "|r",
          plainPlayerName = member.playerName,
          className = member.className,
          classFileName = member.classFileName,
          rankIndex = member.rankIndex,
          rankName = member.rankName or "Guild Member",
          expected = expected,
          amount = balance,
          balance = balance,
          action = missing > 0 and "Pending auto" or "Current",
          reason = missing > 0 and ("Missing " .. tostring(missing) .. " Dibs") or "No assignment event recorded yet",
        })
      end
    end
  end
  table.sort(rows, function(left, right)
    return left.timestamp == right.timestamp and tostring(left.playerName) < tostring(right.playerName) or left.timestamp > right.timestamp
  end)
  local lines = {}
  for _, row in ipairs(rows) do
    local rank = row.rankName ~= "" and row.rankName or (row.rankIndex ~= nil and ("Rank " .. tostring(row.rankIndex)) or "Unknown")
    local sign = row.amount >= 0 and "+" or ""
    table.insert(lines, table.concat({ row.dateText, row.playerName, rank, tostring(row.expected), sign .. tostring(row.amount), row.action, row.reason }, " | "))
  end
  return { allocations = lines, rows = rows, hiddenTransactionCount = 0 }
end

function Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  if not canViewOfficerData() then
    return { requests = {}, activeRequestCount = 0, hiddenRequestCount = 0, hidden = true }
  end
  local memberNames = getCurrentGuildMemberNames()
  local lines = {}
  local hiddenRequestCount = 0
  local requests = Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}
  local activeRequestCount = 0

  for _, request in ipairs(requests) do
    local isActive = request.status == "pending" or request.status == "confirmed"
    if request.seasonId == seasonId then
      local playerName = getCurrentGuildMemberName(memberNames, request.playerName)
      if playerName then
        if isActive then
          activeRequestCount = activeRequestCount + 1
        end
        table.insert(lines, {
          createdAt = request.createdAt or 0,
          text = formatHistoryDate(request.createdAt) .. " | " .. playerName .. " | " .. tostring(request.status) .. " | " .. tostring(request.itemName or ("Item " .. tostring(request.itemID or "?"))) .. " | " .. tostring(request.difficulty or "UNKNOWN") .. " | " .. tostring(request.modeAtCreation or "WILD_OPEN") .. " | " .. tostring(request.delivery and request.delivery.state or "PENDING"),
        })
      else
        hiddenRequestCount = hiddenRequestCount + 1
      end
    end
  end

  local acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitions and Dibs.PreDibs.GetAcquisitions() or {}
  for _, record in ipairs(acquisitions) do
    if record.seasonId == nil or record.seasonId == seasonId then
      local playerName = getCurrentGuildMemberName(memberNames, record.playerName)
      if playerName then
        table.insert(lines, {
          createdAt = record.acquiredAt or 0,
          text = formatHistoryDate(record.acquiredAt) .. " | " .. playerName .. " | Acquired | Item " .. tostring(record.itemID) .. " | " .. tostring(record.difficulty or "UNKNOWN") .. " | " .. tostring(record.source or "VAULT"),
        })
      else
        hiddenRequestCount = hiddenRequestCount + 1
      end
    end
  end

  table.sort(lines, function(a, b)
    return a.createdAt > b.createdAt
  end)

  local result = {}
  for _, line in ipairs(lines) do
    table.insert(result, line.text)
  end
  return { requests = result, activeRequestCount = activeRequestCount, hiddenRequestCount = hiddenRequestCount }
end

function Dibs.OfficerUI.BuildVaultAcquisitionReview(filter)
  filter = type(filter) == "table" and filter or {}
  if not canViewOfficerData() then return { rows = {}, hidden = true, hiddenCount = 0 } end
  local query = string.lower(trimText(filter.query))
  local requestedState = trimText(filter.verificationState or filter.status)
  local rows, hiddenCount = {}, 0
  local members = getCurrentGuildMemberNames()
    for _, conflict in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetVaultConflicts and Dibs.PreDibs.GetVaultConflicts() or {}) do
      local incoming = conflict.incoming or {}
      local playerName = getCurrentGuildMemberName(members, incoming.playerName)
      if playerName and conflict.status == "REVIEW_REQUIRED" then
        rows[#rows + 1] = {
          acquisitionId = conflict.acquisitionId, conflictId = conflict.conflictId, conflict = true,
          playerName = playerName, projection = incoming,
          text = table.concat({ formatHistoryDate(conflict.createdAt), playerName, "CONFLICT_REVIEW_REQUIRED",
            incoming.itemName or ("Item " .. tostring(incoming.itemID)), incoming.source or "VAULT",
            incoming.resetId or "UNKNOWN", incoming.syncState or "SYNCED", "Immutable identity conflict" }, " | "),
        }
      end
    end
  for _, record in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetAcquisitions and Dibs.PreDibs.GetAcquisitions() or {}) do
    local playerName = getCurrentGuildMemberName(members, record.playerName)
    if not playerName then
      hiddenCount = hiddenCount + 1
    elseif (not filter.seasonId or record.seasonId == nil or record.seasonId == filter.seasonId)
      and (requestedState == "" or record.verificationState == requestedState) then
      local projection = Dibs.PreDibs.ProjectVaultAcquisition(record, "officer")
      local searchable = string.lower(table.concat({ tostring(playerName), tostring(record.itemName or record.itemID or ""),
        tostring(record.source or ""), tostring(record.verificationState or ""), tostring(record.resetId or ""),
        tostring(record.syncState or "") }, " "))
      if query == "" or string.find(searchable, query, 1, true) then
        rows[#rows + 1] = {
          acquisitionId = record.acquisitionId,
          projection = projection,
          playerName = playerName,
          text = table.concat({ formatHistoryDate(record.acquiredAt or record.createdAt), playerName,
            record.verificationState or "UNVERIFIED", record.itemName or ("Item " .. tostring(record.itemID)),
            record.source or "VAULT", record.resetId or "UNKNOWN", record.syncState or "LOCAL",
            record.review and record.review.reason or "" }, " | "),
        }
      end
    end
  end
  table.sort(rows, function(first, second)
    return (first.projection.acquiredAt or first.projection.createdAt or 0) > (second.projection.acquiredAt or second.projection.createdAt or 0)
  end)
  return { rows = rows, hiddenCount = hiddenCount }
end

function Dibs.OfficerUI.BuildVaultMigrationPreview(filter)
  filter = type(filter) == "table" and filter or {}
  return Dibs.OfficerUI.BuildVaultAcquisitionReview({
    seasonId = filter.seasonId, query = filter.query, verificationState = "LEGACY_RECORDED",
  })
end

function Dibs.OfficerUI.ReviewVaultAcquisition(acquisitionId, decision, reason, actor)
  if not canViewOfficerData() then return nil, "GUILD_ADMIN_REQUIRED" end
  local reviewer = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  return Dibs.PreDibs and Dibs.PreDibs.ReviewVaultAcquisition
    and Dibs.PreDibs.ReviewVaultAcquisition(acquisitionId, decision, reviewer, reason)
    or nil, "ACQUISITIONS_UNAVAILABLE"
end

function Dibs.OfficerUI.ResolveVaultConflict(conflictId, decision, reason, actor)
  if not canViewOfficerData() then return nil, "GUILD_ADMIN_REQUIRED" end
  local reviewer = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  return Dibs.PreDibs and Dibs.PreDibs.ResolveVaultConflict
    and Dibs.PreDibs.ResolveVaultConflict(conflictId, decision, reviewer, reason)
    or nil, "CONFLICTS_UNAVAILABLE"
end

---@param view string Officer view identifier.
---@param seasonId string|nil Season scope.
---@param page integer|nil One-based page number.
---@param pageSize integer|nil Bounded page size.
---@param query string|nil Search/filter text.
---@return table page Paged rows and pagination metadata.
function Dibs.OfficerUI.GetPagedView(view, seasonId, page, pageSize, query, statusFilter)
  if not canViewOfficerData() then
    return emptyOfficerPage(view, query)
  end
  local selectedView = view == "actions" and "actions" or (view == "automaticDibs" and "automaticDibs" or (view == "predibs" and "predibs" or (view == "vault" and "vault" or "players")))
  local structuredFilter = type(statusFilter) == "table" and statusFilter or {}
  if type(query) == "table" then
    structuredFilter = query
    query = query.query
  end
  local ledger = Dibs.OfficerUI.BuildLedgerDetails(seasonId, structuredFilter)
  local automatic = Dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId)
  local preDibs = Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  local vault = Dibs.OfficerUI.BuildVaultAcquisitionReview({ seasonId = seasonId, query = query, verificationState = statusFilter })
  local lines = selectedView == "actions" and ledger.actions
    or (selectedView == "automaticDibs" and automatic.allocations
    or (selectedView == "predibs" and preDibs.requests
      or (selectedView == "vault" and (function()
        local result = {}
        for _, row in ipairs(vault.rows) do result[#result + 1] = row.text end
        return result
      end)() or ledger.players)))
  local emptyText = selectedView == "actions" and "No history for this season."
    or (selectedView == "automaticDibs" and "No automatic Dibs allocations for this season."
    or (selectedView == "predibs" and "No pre-Dibs for this season."
      or (selectedView == "vault" and "No Great Vault records for this season." or "No player activity for this season.")))
  local title = selectedView == "actions" and "Actions"
    or (selectedView == "automaticDibs" and "Automatic Dibs"
    or (selectedView == "predibs" and "Pre-Dibs" or (selectedView == "vault" and "Vault Review" or "Players")))
  local automaticRows = automatic.rows or {}
  local needle = string.lower(tostring(query or ""))
  if needle ~= "" then
    local filtered, filteredRows = {}, {}
    for originalIndex, line in ipairs(lines) do
      if string.find(string.lower(line), needle, 1, true) then
        table.insert(filtered, line)
        if selectedView == "automaticDibs" then table.insert(filteredRows, automaticRows[originalIndex]) end
      end
    end
    lines = filtered
    if selectedView == "automaticDibs" then automaticRows = filteredRows end
  end
  local size = math.max(1, tonumber(pageSize) or 8)
  local totalPages = math.max(1, math.ceil(#lines / size))
  local currentPage = math.max(1, math.min(tonumber(page) or 1, totalPages))
  local first = ((currentPage - 1) * size) + 1
  local visible = {}
  local visibleRows = {}
  for index = first, math.min(first + size - 1, #lines) do
    table.insert(visible, lines[index])
    if selectedView == "automaticDibs" and automaticRows[index] then table.insert(visibleRows, automaticRows[index]) end
  end
  if #visible == 0 then
    visible[1] = emptyText
  end

  return {
    title = title,
    lines = visible,
    rows = visibleRows,
    page = currentPage,
    totalPages = totalPages,
    totalCount = #lines,
    query = needle,
    hiddenCount = selectedView == "automaticDibs" and automatic.hiddenTransactionCount
      or (selectedView == "predibs" and preDibs.hiddenRequestCount
      or (selectedView == "vault" and vault.hiddenCount or ledger.hiddenTransactionCount)),
  }
end

function Dibs.OfficerUI.BuildSeasonStatistics(seasonId)
  if not canViewOfficerData() then
    return {
      players = 0,
      transactions = 0,
      granted = 0,
      used = 0,
      awards = 0,
      corrections = 0,
      activePreDibs = 0,
      fairness = { awardCount = {}, meanAwards = 0, medianAwards = 0, minAwards = 0, maxAwards = 0 },
      hidden = true,
    }
  end
  local memberNames = getCurrentGuildMemberNames()
  local transactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(seasonId) or {}
  local players = {}
  local awardCount = {}
  local granted, used, corrections, awards = 0, 0, 0, 0

  for _, tx in ipairs(transactions) do
    local playerName = getCurrentGuildMemberName(memberNames, tx.playerName or tx.playerKey or tx.playerId)
    if playerName then
      players[string.lower(playerName)] = true
      local amount = tonumber(tx.amount or tx.quantityDelta) or 0
      if tx.type == "DIB_GRANTED" then
        granted = granted + amount
      elseif tx.type == "DIB_USED" then
        used = used + math.abs(amount)
        awards = awards + 1
        local key = string.lower(playerName)
        awardCount[key] = (awardCount[key] or 0) + 1
      elseif tx.type == "DIB_REFUNDED" or tx.type == "DIB_REVOKED" or tx.type == "DIB_ADMIN_ADJUSTMENT" then
        corrections = corrections + 1
      end
    end
  end

  local activePreDibs = Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  local playerCount = 0
  for _ in pairs(players) do playerCount = playerCount + 1 end
  local awardValues = {}
  for _, count in pairs(awardCount) do awardValues[#awardValues + 1] = count end
  table.sort(awardValues)
  local awardTotal = 0
  for _, count in ipairs(awardValues) do awardTotal = awardTotal + count end
  local median = 0
  if #awardValues > 0 then
    local middle = math.floor((#awardValues + 1) / 2)
    median = #awardValues % 2 == 1 and awardValues[middle] or (awardValues[middle] + awardValues[middle + 1]) / 2
  end
  return {
    players = playerCount,
    transactions = #transactions,
    granted = granted,
    used = used,
    awards = awards,
    corrections = corrections,
    activePreDibs = activePreDibs.activeRequestCount,
    fairness = {
      awardCount = awardCount,
      meanAwards = #awardValues > 0 and awardTotal / #awardValues or 0,
      medianAwards = median,
      minAwards = awardValues[1] or 0,
      maxAwards = awardValues[#awardValues] or 0,
    },
  }
end

local function dashboardStatus(label, explanation, technical)
  return { label = label, explanation = explanation, technical = technical }
end

local function syncDashboardStatus(status)
  status = status or {}
  local state = status.state or status.status
  if state == "SYNC_BEHIND" then return dashboardStatus("Behind / Synchronizing", "The guild ledger is catching up.", status) end
  if state == "SYNC_UNAVAILABLE" then return dashboardStatus("Unavailable", "Synchronization is unavailable.", status) end
  return dashboardStatus("Ready", "Synchronization is ready.", status)
end

local function coordinatorDashboardStatus(authority)
  authority = authority or {}
  local state = authority.state or "LEGACY_LOCAL"
  if state == "RECOVERY_PENDING" then return dashboardStatus("Recovery in progress", "Coordinator recovery is in progress.", authority) end
  if state == "COORDINATOR_UNAVAILABLE" then return dashboardStatus("Unavailable", "The coordinator is unavailable.", authority) end
  if state == "ACTIVE" then return dashboardStatus("Active", "Coordinator authority is active.", authority) end
  return dashboardStatus("Local only", "No distributed coordinator is active.", authority)
end

local function rclootCouncilDashboardStatus(status)
  status = status or {}
  local availability = status.availability or status.status
  if availability == "degraded" then return dashboardStatus("Degraded", "RCLootCouncil is available with limitations.", status) end
  if availability == "operational" or availability == "ready" then return dashboardStatus("Operational", "RCLootCouncil is operational.", status) end
  return dashboardStatus("Unavailable", "RCLootCouncil is unavailable.", status)
end

function Dibs.OfficerUI.GetDashboardProjection()
  if not canViewOfficerData() then
    return { hidden = true, role = Dibs.OfficerUI.GetPresentationRole(), provider = "production" }
  end

  local role = Dibs.OfficerUI.GetPresentationRole()
  local sandboxStatus = Dibs.DeveloperSandbox and Dibs.DeveloperSandbox.GetStatus and Dibs.DeveloperSandbox.GetStatus() or {}
  local provider = sandboxStatus.active and "sandbox" or "production"
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent and Dibs.Seasons.GetCurrent() or nil
  local seasonId = season and season.id or nil
  local statistics = Dibs.OfficerUI.BuildSeasonStatistics(seasonId)
  local predibs = Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  local pendingRequests = 0
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}) do
    if request.seasonId == seasonId and request.status == "pending" then pendingRequests = pendingRequests + 1 end
  end
  local sync = Dibs.Sync and Dibs.Sync.GetStatus and Dibs.Sync.GetStatus() or {}
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState() or {}
  local rc = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or {}
  local recent = {}
  local ledgerPage = Dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 5)
  local preDibPage = Dibs.OfficerUI.GetPagedView("predibs", seasonId, 1, 5)
  for _, line in ipairs(ledgerPage.lines or {}) do
    if #recent < 5 and line ~= "No history for this season." then table.insert(recent, line) end
  end
  for _, line in ipairs(preDibPage.lines or {}) do
    if #recent < 5 and line ~= "No pre-Dibs for this season." then table.insert(recent, line) end
  end
  local ledgerStatus = season and dashboardStatus("Healthy", "The active season ledger is available.", { state = "HEALTHY", seasonId = seasonId })
    or dashboardStatus("Unavailable", "No active season is configured.", { state = "NO_ACTIVE_SEASON" })

  return {
    role = role,
    provider = provider,
    authorityOrigin = sandboxStatus.authorityOrigin or "production",
    season = { id = seasonId, name = season and season.name or "No active season" },
    metrics = {
      activePlayers = statistics.players,
      pendingRequests = pendingRequests,
      activePreDibs = predibs.activeRequestCount,
      transactions = statistics.transactions,
      awards = statistics.awards,
    },
    status = {
      ledger = ledgerStatus,
      sync = syncDashboardStatus(sync),
      coordinator = coordinatorDashboardStatus(authority),
      rclootcouncil = rclootCouncilDashboardStatus(rc),
    },
    recentActivity = recent,
    empty = {
      pendingRequests = predibs.activeRequestCount == 0 and "No pending requests." or nil,
      activePreDibs = predibs.activeRequestCount == 0 and "No active Pre-Dibs." or nil,
      recentActivity = #recent == 0 and "No recent activity." or nil,
    },
    technical = { sync = sync, coordinator = authority, rclootcouncil = rc },
    capabilities = { governance = role == "gm", manageDibs = true, reviewRequests = true },
  }
end

local function renderDashboard(shell, parent, frame)
  local dashboard = Dibs.OfficerUI.GetDashboardProjection()
  if dashboard.hidden then
    Dibs.AceGUI.AddHeading(shell, parent, "Officer dashboard")
    Dibs.AceGUI.AddLabel(shell, parent, "Officer access required.", true)
    return
  end
  local function addStatus(key, value)
    local tone = value and value.label == "Ready" and "ready" or (value and value.label == "Operational" and "success" or "info")
    if value and (value.label == "Unavailable" or value.label == "Degraded" or value.label == "Recovery in progress" or value.label == "Behind / Synchronizing") then
      tone = "warning"
    end
    Dibs.Midnight.AddStatusBadge(shell, parent, tone, key .. ": " .. tostring(value and value.label or "Unavailable"))
    Dibs.AceGUI.AddLabel(shell, parent, tostring(value and value.explanation or "Unavailable."), true)
  end
  Dibs.AceGUI.AddHeading(shell, parent, "Officer dashboard", "Guild-wide operational summary for authorized Officers and GM.")
  Dibs.AceGUI.AddLabel(shell, parent, "Season: " .. tostring(dashboard.season and dashboard.season.name or "No active season"), true)
  Dibs.AceGUI.AddLabel(shell, parent, "Requests pending: " .. tostring(dashboard.metrics.pendingRequests)
    .. " | Active Pre-Dibs: " .. tostring(dashboard.metrics.activePreDibs)
    .. " | Active players: " .. tostring(dashboard.metrics.activePlayers), true)
  addStatus("Ledger", dashboard.status.ledger)
  addStatus("Sync", dashboard.status.sync)
  addStatus("Coordinator", dashboard.status.coordinator)
  addStatus("RCLootCouncil", dashboard.status.rclootcouncil)
  local recentText = #dashboard.recentActivity > 0 and table.concat(dashboard.recentActivity, "\n") or dashboard.empty.recentActivity
  Dibs.AceGUI.AddHeader(shell, parent, "Recent activity", "Latest bounded Officer-visible activity.")
  Dibs.AceGUI.AddLabel(shell, parent, recentText, true)
  Dibs.AceGUI.AddButton(shell, parent, frame.showDashboardTechnical and "Hide technical details" or "Show technical details", function()
    frame.showDashboardTechnical = not frame.showDashboardTechnical
    frame:Refresh()
  end, 190)
  if frame.showDashboardTechnical then
    Dibs.AceGUI.AddHeader(shell, parent, "Technical details", "Normalized service state and diagnostic reason codes.")
    Dibs.AceGUI.AddLabel(shell, parent, "Sync state: " .. tostring(dashboard.technical.sync.state or "unknown"), true)
    Dibs.AceGUI.AddLabel(shell, parent, "Coordinator state: " .. tostring(dashboard.technical.coordinator.state or "unknown"), true)
    Dibs.AceGUI.AddLabel(shell, parent, "RCLootCouncil reason: " .. tostring(dashboard.technical.rclootcouncil.reasonCode or "none"), true)
  end
end

function Dibs.OfficerUI.BuildDashboardDetails(season)
  if not canViewOfficerData() then
    return { "Officer access required." }
  end
  local seasonId = season and season.id or nil
  local statistics = Dibs.OfficerUI.BuildSeasonStatistics(seasonId)
  local actions = Dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 1)
  return {
    "Season: " .. tostring(season and season.name or "None"),
    "Pre-Dib mode: " .. tostring(Dibs.PreDibs and Dibs.PreDibs.GetModePolicy and Dibs.PreDibs.GetModePolicy(seasonId).mode or "WILD_OPEN"),
    "Players active: " .. tostring(statistics.players),
    "Active pre-Dibs: " .. tostring(statistics.activePreDibs),
    "Actions this season: " .. tostring(statistics.transactions),
    "Latest action: " .. tostring(actions.lines[1] or "None"),
  }
end

function Dibs.OfficerUI.SetPreDibMode(seasonId, mode)
  return Dibs.ProtectedActions.Execute("predib.mode.set", nil, { seasonId = seasonId, mode = mode, source = "officer-ui" })
end

function Dibs.OfficerUI.SavePreDibMode(seasonId, mode)
  return Dibs.ProtectedActions.Execute("predib.mode.set", nil, { seasonId = seasonId, mode = mode, source = "officer-ui" })
end

function Dibs.OfficerUI.SaveEligibilityPolicy(payload)
  return Dibs.ProtectedActions.Execute("eligibility.policy.set", nil, payload or {})
end

function Dibs.OfficerUI.GetRankChangeDiagnostics()
  if not canViewOfficerData() then
    return { playersWithRankTransitions = 0, totalPlayersInLedger = 0, hidden = true }
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {}
  local playerRanks = {}

  for _, tx in ipairs(transactions) do
    local player = string.lower(tostring(tx.playerName or tx.playerId or tx.playerGuid or "unknown"))
    local rank = tonumber(tx.playerRankIndex or tx.playerRank)
    if rank ~= nil then
      playerRanks[player] = playerRanks[player] or {}
      playerRanks[player][rank] = true
    end
  end

  local changingPlayers = 0
  local totalPlayers = 0
  for _, ranks in pairs(playerRanks) do
    totalPlayers = totalPlayers + 1
    local count = 0
    for _ in pairs(ranks) do
      count = count + 1
    end
    if count > 1 then
      changingPlayers = changingPlayers + 1
    end
  end

  return {
    playersWithRankTransitions = changingPlayers,
    totalPlayersInLedger = totalPlayers,
  }
end

function Dibs.OfficerUI.BuildStatusText(selectedSeason)
  if not canViewOfficerData() then
    return "Officer access required."
  end
  local season = selectedSeason or (Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil)
  local seasons = Dibs.Seasons and Dibs.Seasons.List() or {}
  local overview = Dibs.OfficerUI.GetLedgerOverview()
  local rankDiagnostics = Dibs.OfficerUI.GetRankChangeDiagnostics()
  local permissions = Dibs.GetDB().permissions or {}
  local adminCount = 0
  for _ in pairs(permissions.activeStandaloneAdmins or {}) do
    adminCount = adminCount + 1
  end
  local size = Dibs.ImportExport and Dibs.ImportExport.GetSizeDiagnostics and Dibs.ImportExport.GetSizeDiagnostics() or {}
  local formatSize = Dibs.ImportExport and Dibs.ImportExport.FormatSize or tostring

  return "Season selected: " .. tostring(season and season.name or "None") .. "\n" ..
    "Seasons: " .. tostring(#seasons) .. " | Ledger transactions (all seasons): " .. tostring(overview.count) .. "\n" ..
    "Rank transitions: " .. tostring(rankDiagnostics.playersWithRankTransitions) .. "/" .. tostring(rankDiagnostics.totalPlayersInLedger) .. " players\n" ..
    "Standalone admins: " .. tostring(adminCount) .. " (events: " .. tostring(#(permissions.adminEvents or {})) .. ")\n" ..
    "Dibs database: " .. formatSize(size.databaseBytes) .. " | Full backup package: " .. formatSize(size.fullPackageBytes) .. " / " .. formatSize(size.backupLimitBytes) .. "\n" ..
    "Role: " .. tostring(Dibs.Permissions and Dibs.Permissions.GetRole() or "player") .. "\n" ..
    "RCLootCouncil: " .. tostring(Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetAvailability and Dibs.RCLootCouncil.GetAvailability() or "absent")
end

function Dibs.OfficerUI.BuildSynchronizationStatus()
  local status = Dibs.Sync and Dibs.Sync.GetSynchronizationStatus and Dibs.Sync.GetSynchronizationStatus() or {}
  local messages = {}
  if status.operationalPolicyAdopted ~= true then table.insert(messages, (Dibs.L and Dibs.L.SYNC_POLICY_NOT_ADOPTED) or "Guild-wide rules are not active.") end
  if status.lastProtocolMismatch then
    table.insert(messages, string.format((Dibs.L and Dibs.L.SYNC_PROTOCOL_MISMATCH) or "Protocol mismatch with %s.", tostring(status.lastProtocolMismatch.sender or "unknown")))
  end
  if status.lastAddonVersionMismatch then
    local key = status.lastAddonVersionMismatch.reasonCode == "REMOTE_ADDON_VERSION_UNKNOWN" and "SYNC_ADDON_VERSION_UNKNOWN" or "SYNC_ADDON_VERSION_MISMATCH"
    table.insert(messages, string.format((Dibs.L and Dibs.L[key]) or "Addon update required for %s.", tostring(status.lastAddonVersionMismatch.sender or "unknown")))
  end
  return table.concat(messages, "\n")
end

function Dibs.OfficerUI.BuildSynchronizationProjection()
  local status = Dibs.Sync and Dibs.Sync.GetSynchronizationStatus and Dibs.Sync.GetSynchronizationStatus() or {}
  local peers = Dibs.Sync and Dibs.Sync.GetPeerStatuses and Dibs.Sync.GetPeerStatuses() or {}
  return {
    state = Dibs.Sync and Dibs.Sync.GetStatus and Dibs.Sync.GetStatus() or {},
    protocolState = Dibs.Sync and Dibs.Sync.GetProtocolState and Dibs.Sync.GetProtocolState() or "Unknown",
    policy = status.operationalPolicyAdopted == true and "Adopted" or "Not adopted",
    seasonCatalogRevision = tonumber(status.seasonCatalogRevision) or 0,
    pendingAwardProposals = tonumber(status.pendingAwardProposals) or 0,
    peers = peers,
  }
end

function Dibs.OfficerUI.GetPendingAwardProposals()
  if not canViewOfficerData() or not (Dibs.Governance and Dibs.Governance.GetPendingCoordinatorProposals) then return {} end
  local rows = {}
  for _, proposal in ipairs(Dibs.Governance.GetPendingCoordinatorProposals()) do
    rows[#rows + 1] = {
      proposalId = proposal.proposalId,
      playerName = proposal.playerSnapshot and proposal.playerSnapshot.displayName or "Unknown",
      itemID = proposal.itemID,
      itemLink = proposal.itemLink,
      awardRef = proposal.awardRef,
      submittedBy = proposal.actorSnapshot and proposal.actorSnapshot.displayName,
    }
  end
  return rows
end

function Dibs.OfficerUI.ConfirmPendingAwardProposal(proposalId)
  if not canViewOfficerData() then return { accepted = false, reasonCode = "OFFICER_ACCESS_REQUIRED" } end
  if not (Dibs.Ledger and Dibs.Ledger.CommitAwardProposal) then return { accepted = false, reasonCode = "LEDGER_UNAVAILABLE" } end
  return Dibs.Ledger.CommitAwardProposal({ actor = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, action = "ledger.use" }, proposalId, {})
end

local function splitPipeLine(line, expected)
  local cells = {}
  for cell in (tostring(line or "") .. "|"):gmatch("(.-)|") do
    table.insert(cells, cell:match("^%s*(.-)%s*$"))
  end
  while #cells < (expected or 1) do table.insert(cells, "") end
  return cells
end

local function createAceWindow(initialRoute)
  local shell = Dibs.AceGUI.CreateWindow("RCLootCouncil - Dibs | Officer", 980, 760, { "CENTER", 280, 0 }, "OfficerWindowPosition")
  if not shell then return nil end
  local frame = shell.frame
  if frame and frame.SetUserPlaced then frame:SetUserPlaced(true) end
  frame.dibsAceGUIShell = shell
  frame._dibsUiShell = shell
  frame.activeTab = normalizeOfficerTab(initialRoute or "overview")
  frame.selectedRoute = frame.activeTab
  frame.routeDispatchCount = 0
  frame.ledgerPage = 1
  frame.rankRows = {}
  frame.rankDrafts = {}
  frame.rankRowCount = 3
  frame.inputBoundSeasonId = nil

  local historyTransferShell
  local historyTransferRoot
  local closeHistoryTransfer

  local function historyTransferDetails(candidate)
    return {
      { "Classification", tostring(candidate.classification or "Unavailable") },
      { "History reference", tostring(candidate.historyRef or "Unavailable") },
      { "Winner", tostring(candidate.playerName or "Unavailable") },
      { "Original owner", tostring(candidate.originalOwner or "Unavailable") },
      { "Item", tostring(candidate.itemLink or candidate.itemID or "Unavailable") },
      { "Original award time", formatHistoryDate(candidate.originalAwardTime, candidate.originalAwardTimeText) },
      { "Difficulty", tostring(candidate.difficultyText or candidate.difficulty or "Unavailable") },
      { "Instance / encounter", tostring(candidate.instanceName or "Unavailable") .. " / " .. tostring(candidate.encounterName or "Unavailable") },
      { "Votes recorded", tostring(candidate.voteCount or "Unavailable") },
      { "Related rows for this item", tostring(candidate.relatedHistoryCount or 0) },
      { "Related winners", tostring(candidate.relatedWinners or "None") },
      { "Difficulty variants", tostring(candidate.relatedDifficulties or candidate.difficultyText or candidate.difficulty or "Unavailable") },
      { "Original response", tostring(candidate.responseText or "Unavailable") },
      { "Final status", tostring(candidate.sourceStatus or "Unavailable") },
      { "RCLootCouncil award reason", tostring(candidate.awardReason or "Unavailable") },
      { "Review result", historyReviewLabel(candidate) .. " (" .. tostring(candidate.reasonCode or "ready") .. ")" },
      { "Evidence", tostring(candidate.evidenceId or "Unavailable") },
    }
  end

  local function createHistoryTransferShell()
    if historyTransferShell and historyTransferShell.frame and historyTransferShell.window then
      return historyTransferShell
    end
    historyTransferShell = Dibs.AceGUI.CreateWindow("RCLootCouncil - Dibs | Transfer", 720, 620, { "CENTER", 0, 0 })
    if not historyTransferShell then return nil end
    historyTransferRoot = Dibs.AceGUI.Create(historyTransferShell, "SimpleGroup", historyTransferShell.window)
    if not historyTransferRoot then return nil end
    if historyTransferRoot.SetFullWidth then historyTransferRoot:SetFullWidth(true) end
    if historyTransferRoot.SetFullHeight then historyTransferRoot:SetFullHeight(true) end
    if historyTransferRoot.SetLayout then historyTransferRoot:SetLayout("List") end
    return historyTransferShell
  end

  closeHistoryTransfer = function()
    if historyTransferRoot then Dibs.AceGUI.Clear(historyTransferRoot) end
    if historyTransferShell and historyTransferShell.window then historyTransferShell.window:Hide() end
    frame.transferTechnicalExpanded = false
    frame.historyTransferOpen = false
  end

  local function openHistoryTransfer(session, candidate)
    if not session or not candidate then return false end
    local transferShell = createHistoryTransferShell()
    if not transferShell or not historyTransferRoot then return false end
    Dibs.AceGUI.Clear(historyTransferRoot)
    frame.reconSelectedCandidate = candidate.candidateId
    frame.reconReason = ""
    frame.historyTransferOpen = true

    local page = Dibs.AceGUI.AddScrollableList(transferShell, historyTransferRoot, 540) or historyTransferRoot
    Dibs.AceGUI.AddHeading(transferShell, page, "Historical DIB transfer")
    Dibs.AceGUI.AddHeader(transferShell, page, "Review before recording", "The values below come from read-only RCLootCouncil evidence. Technical details stay in this secondary review window.")
    local summary = Dibs.AceGUI.AddSection(transferShell, page, "Award summary", "Human-readable evidence for the normal review path.")
    for _, entry in ipairs({
      { "Item", candidate.itemLink or candidate.itemID or "Unavailable" },
      { "Winner", candidate.playerName or "Unavailable" },
      { "Difficulty", candidate.difficultyText or candidate.difficulty or "Unavailable" },
      { "Encounter", (candidate.instanceName or "Unavailable") .. " - " .. (candidate.encounterName or "Unavailable") },
      { "Award date", formatHistoryDate(candidate.originalAwardTime, candidate.originalAwardTimeText) },
      { "Evidence", historyReviewLabel(candidate) },
    }) do
      Dibs.AceGUI.AddLabel(transferShell, summary, entry[1] .. ": " .. tostring(entry[2]), true)
    end
    Dibs.AceGUI.AddButton(transferShell, page, frame.transferTechnicalExpanded and "Hide technical evidence" or "Show technical evidence", function()
      frame.transferTechnicalExpanded = not frame.transferTechnicalExpanded
      openHistoryTransfer(session, candidate)
    end, 210)
    if frame.transferTechnicalExpanded then
      Dibs.AceGUI.AddHeader(transferShell, page, "Technical evidence", "Raw field/value evidence is available when needed for an audit review.")
      Dibs.AceGUI.AddPropertyTable(transferShell, page, historyTransferDetails(candidate), 250)
    end
    if Dibs.EncounterJournal and type(Dibs.EncounterJournal.OpenLootItem) == "function" then
      Dibs.AceGUI.AddButton(transferShell, page, "Open in Adventure Guide", function()
        Dibs.EncounterJournal.OpenLootItem(candidate)
      end, 210)
    end
    Dibs.AceGUI.AddLabel(transferShell, page, "Add the accounting note, verify it below, then confirm the transfer.", true)
    local confirm
    local note = Dibs.AceGUI.AddEditBox(transferShell, page, "Transfer note (required)", function(value)
      frame.reconReason = value or ""
      if confirm then
        Dibs.AceGUI.SetDisabled(confirm, candidate.classification ~= "eligible" or trimText(frame.reconReason) == "")
      end
    end, 580)
    setControlText(note, frame.reconReason)
    local actions = Dibs.AceGUI.AddInlineGroup(transferShell, page)
    confirm = Dibs.AceGUI.AddButton(transferShell, actions, "Confirm as DIB", function()
      local noteText = trimText(frame.reconReason)
      if noteText == "" then return end
      local outcome = Dibs.LogsUI and Dibs.LogsUI.ConfirmCandidate and Dibs.LogsUI.ConfirmCandidate(session.sessionId, candidate.candidateId, noteText, {
        mode = "manual", confirmation = true, manualAcknowledgement = true,
      }) or { ok = false, reasonCode = "PROTECTED_ACTION_UNAVAILABLE" }
      local result, decision = outcome.result, outcome.decision
      frame.reconStatus = outcome.ok and (result and result.duplicate and "Already accounted; no second debit was appended." or "Historical Dibs recorded.")
        or ("Unable to confirm: " .. tostring(outcome.reasonCode or decision and decision.reasonCode or result and result.reasonCode or "unknown"))
      if historyTransferShell and historyTransferShell.window then historyTransferShell.window:Hide() end
      frame.historyTransferOpen = false
      frame:Refresh()
    end, 170)
    local reject = Dibs.AceGUI.AddButton(transferShell, actions, "Reject row", function()
      local outcome = Dibs.LogsUI and Dibs.LogsUI.RejectCandidate and Dibs.LogsUI.RejectCandidate(session.sessionId, candidate.candidateId, frame.reconReason)
        or { ok = false, reasonCode = "PROTECTED_ACTION_UNAVAILABLE" }
      frame.reconStatus = outcome.ok and "History row rejected; no ledger change was made." or ("Unable to reject history row: " .. tostring(outcome.reasonCode or "unknown"))
      if historyTransferShell and historyTransferShell.window then historyTransferShell.window:Hide() end
      frame.historyTransferOpen = false
      frame:Refresh()
    end, 120)
    Dibs.AceGUI.SetDisabled(confirm, candidate.classification ~= "eligible" or trimText(frame.reconReason) == "")
    Dibs.AceGUI.AddLabel(transferShell, page, "The note is stored in the audit trail with the exact date, time, response, difficulty and vote evidence.", true)
    transferShell.window:Show()
    if transferShell.window.DoLayout then transferShell.window:DoLayout() end
    return true
  end

  frame.SetStatus = function(self, message)
    self.statusMessage = tostring(message or "")
    Dibs.Message(self.statusMessage)
  end

  frame.CloseHistoryTransfer = function()
    if closeHistoryTransfer then closeHistoryTransfer() end
  end

  local requestDetailShell
  local requestDetailRoot
  local requestChildDialog
  local openRequestDetail

  local function closeRequestChildren()
    if Dibs.AceGUI and Dibs.AceGUI.HideContextMenu then Dibs.AceGUI.HideContextMenu() end
    if requestChildDialog and requestChildDialog.window then requestChildDialog.window:Hide() end
    requestChildDialog = nil
  end

  local function closeRequestDetail()
    closeRequestChildren()
    if requestDetailRoot then Dibs.AceGUI.Clear(requestDetailRoot) end
    if requestDetailShell and requestDetailShell.window then requestDetailShell.window:Hide() end
    frame.disputeDetailOpen = false
  end

  local function openDibsAccountingWorkflow(request)
    closeRequestChildren()
    local playerDisplayName = request.player and request.player.name or request.playerName or ""
    local playerName = playerDisplayName
    if Dibs.Identity and type(Dibs.Identity.ResolveRosterMember) == "function" and playerName ~= "" then
      local ok, resolved = pcall(Dibs.Identity.ResolveRosterMember, playerName)
      if ok and type(resolved) == "table" and resolved.status == "RESOLVED" then playerName = resolved.displayName or playerName end
    end
    local draft = frame.requestAccountingDraft
    if type(draft) ~= "table" or draft.requestID ~= request.requestId then
      draft = { requestID = request.requestId, playerIdentity = playerName, playerDisplayName = playerDisplayName, action = "add", amount = "", reason = "", acknowledged = false }
      frame.requestAccountingDraft = draft
    end
    local function traceAccounting(event, details)
      local developerEnabled = Dibs.DeveloperMode and type(Dibs.DeveloperMode.IsEnabled) == "function"
        and Dibs.DeveloperMode.IsEnabled()
      local debugLogger = _G.Dibs and _G.Dibs.Debug
      if developerEnabled and type(debugLogger) == "function" then
        debugLogger("AdjustDibs " .. tostring(event), details)
      end
    end
    local isReview = frame.requestAccountingReview == true
    requestChildDialog = Dibs.AceGUI.CreateWindow("Dibs | Adjust Dibs", 540, 460, { "CENTER", 0, 0 }, "DibsAccountingWorkflow")
    if not requestChildDialog then return false end
    local host = Dibs.AceGUI.Create(requestChildDialog, "SimpleGroup", requestChildDialog.window)
    if not host then requestChildDialog.window:Hide(); requestChildDialog = nil; return false end
    host:SetFullWidth(true); host:SetFullHeight(true); host:SetLayout("List")
    local body = Dibs.AceGUI.Create(requestChildDialog, "SimpleGroup", host)
    local footer = Dibs.AceGUI.Create(requestChildDialog, "SimpleGroup", host)
    if not body or not footer then requestChildDialog.window:Hide(); requestChildDialog = nil; return false end
    body:SetFullWidth(true); body:SetHeight(408); body:SetLayout("List")
    footer:SetFullWidth(true); footer:SetHeight(42); footer:SetLayout("Flow")
    local panel = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestChildDialog, body, "Dibs | Adjust Dibs") or body
    local actionLabels = { add = "Add / Bonus", refund = "Refund", revoke = "Revoke", manual = "Manual correction" }
    local actionValues = { add = "Add / Bonus", refund = "Refund", revoke = "Revoke", manual = "Manual correction" }
    local balanceState = Dibs.Ledger and Dibs.Ledger.GetPlayerState and Dibs.Ledger.GetPlayerState(playerName) or nil
    local before = balanceState and tonumber(balanceState.balance or balanceState.currentBalance)
    local limit = balanceState and tonumber(balanceState.limit or balanceState.maxBalance)
    local reviewBefore = isReview and tonumber(draft.reviewBefore) or before
    if isReview then before = reviewBefore end
    local magnitude = tonumber(draft.amount)
    local delta = magnitude and math.abs(magnitude) or 0
    if draft.action == "revoke" then delta = -delta elseif draft.action == "manual" then delta = magnitude or 0 end
    local after = before and before + delta or nil
    local message
    local function setMessage(text) if message then message:SetText(text or "") end end
    local function validate()
      local currentMagnitude = tonumber(draft.amount)
      local currentDelta = currentMagnitude and math.abs(currentMagnitude) or 0
      if draft.action == "revoke" then currentDelta = -currentDelta elseif draft.action == "manual" then currentDelta = currentMagnitude or 0 end
      local currentAfter = before and before + currentDelta or nil
      if trimText(draft.playerIdentity) == "" then return false, "Player identity could not be resolved." end
      if not currentMagnitude or currentMagnitude == 0 then return false, "Amount must be greater than zero." end
      if draft.action == "manual" and currentMagnitude == 0 then return false, "Enter a signed amount." end
      if trimText(draft.reason) == "" then return false, "Reason is required." end
      if draft.acknowledged ~= true then return false, "Acknowledge the recorded Dibs change first." end
      if not before then return false, "Canonical Dibs state is unavailable." end
      if limit and currentAfter and currentAfter > limit then return false, "The resulting balance exceeds the current policy limit." end
      return true
    end
    if isReview then
      Dibs.AceGUI.AddHeading(requestChildDialog, panel, "Adjust Dibs", "Review the append-only accounting change before confirmation.")
      for _, row in ipairs({
        { "Player", draft.playerIdentity }, { "Action", actionLabels[draft.action] or actionLabels.add },
        { "Before", before and tostring(before) or "Unavailable" }, { "Change", (delta >= 0 and "+" or "") .. tostring(delta) },
        { "After", after and tostring(after) or "Unavailable" }, { "Reason", draft.reason },
      }) do Dibs.AceGUI.AddLabel(requestChildDialog, panel, row[1] .. "\n" .. tostring(row[2] or "Unavailable"), true) end
      Dibs.AceGUI.AddLabel(requestChildDialog, panel, "This correction will be permanently logged. Original history will not be deleted.", true)
    else
      Dibs.AceGUI.AddHeading(requestChildDialog, panel, "Adjust Dibs", "Use one accounting workflow for bonuses, refunds, revokes, and manual corrections.")
      Dibs.AceGUI.AddSummaryRow(requestChildDialog, panel, "Player", playerName, 30)
      local dropdown = Dibs.AceGUI.AddFormRow(requestChildDialog, panel, "Action", function(row)
        return Dibs.AceGUI.AddDropdown(requestChildDialog, row, "", actionValues, function(value)
          draft.action = value or "add"
          openDibsAccountingWorkflow(request)
        end, 300)
      end, 56)
      Dibs.AceGUI.SetValue(dropdown, draft.action)
      Dibs.AceGUI.AddSummaryRow(requestChildDialog, panel, "Current balance", (before and tostring(before) or "Unavailable") .. (limit and (" / " .. tostring(limit)) or ""), 28)
      local changeLabel
      local resultLabel
      local function refreshPreview(value)
        draft.amount = value or ""
        local currentMagnitude = tonumber(draft.amount)
        local currentDelta = currentMagnitude and math.abs(currentMagnitude) or 0
        if draft.action == "revoke" then currentDelta = -currentDelta elseif draft.action == "manual" then currentDelta = currentMagnitude or 0 end
        local currentAfter = before and before + currentDelta or nil
        if changeLabel and changeLabel.SetText then changeLabel:SetText((currentDelta >= 0 and "+" or "") .. tostring(currentDelta)) end
        if resultLabel and resultLabel.SetText then resultLabel:SetText((currentAfter and tostring(currentAfter) or "Unavailable") .. (limit and (" / " .. tostring(limit)) or "")) end
      end
      local amount = Dibs.AceGUI.AddFormRow(requestChildDialog, panel, "Amount", function(row)
        return Dibs.AceGUI.AddEditBox(requestChildDialog, row, "", refreshPreview, 160)
      end, 54)
      setControlText(amount, draft.amount)
      changeLabel = Dibs.AceGUI.AddSummaryRow(requestChildDialog, panel, "Change", (delta >= 0 and "+" or "") .. tostring(delta), 28)
      resultLabel = Dibs.AceGUI.AddSummaryRow(requestChildDialog, panel, "Result", (after and tostring(after) or "Unavailable") .. (limit and (" / " .. tostring(limit)) or ""), 28)
      local reason = Dibs.AceGUI.AddFormRow(requestChildDialog, panel, "Reason", function(row)
        local edit = Dibs.AceGUI.AddMultilineEditBox(requestChildDialog, row, "", function(value) draft.reason = value or "" end, 460, 76)
        setControlText(edit, draft.reason)
        return edit
      end, 106)
      Dibs.AceGUI.AddFormRow(requestChildDialog, panel, "", function(row)
        return Dibs.AceGUI.AddCheckBox(requestChildDialog, row, "I understand this changes recorded Dibs data", draft.acknowledged, function(value) draft.acknowledged = value == true end, 460)
      end, 34)
      message = Dibs.AceGUI.AddLabel(requestChildDialog, panel, "", true)
      if before and magnitude and limit and after > limit then setMessage("The resulting balance exceeds the current policy limit.") end
    end
    Dibs.AceGUI.AddButton(requestChildDialog, footer, isReview and "Back" or "Cancel", function()
      if isReview then frame.requestAccountingReview = false; openDibsAccountingWorkflow(request) else closeRequestChildren() end
    end, 100)
    local primary = Dibs.AceGUI.AddButton(requestChildDialog, footer, isReview and "Confirm action" or "Review", function()
      traceAccounting("Confirm clicked", {
        requestID = draft.requestID, player = draft.playerIdentity, action = draft.action,
        amount = draft.amount, reason = draft.reason, acknowledged = draft.acknowledged,
      })
      if isReview and draft.committing == true then
        setMessage("Adjustment is already being applied.")
        return
      end
      if not isReview then
        local valid, reason = validate()
        if not valid then
          traceAccounting("Review rejected", reason)
          setMessage(reason)
          return
        end
        draft.reviewBefore = before
        frame.requestAccountingReview = true
        openDibsAccountingWorkflow(request)
        return
      end
      local valid, reason = validate()
      if not valid then setMessage(reason); return end
      local currentState = Dibs.Ledger and Dibs.Ledger.GetPlayerState and Dibs.Ledger.GetPlayerState(playerName) or nil
      local currentBefore = currentState and tonumber(currentState.balance or currentState.currentBalance)
      if not currentBefore then setMessage("Canonical Dibs state is unavailable."); return end
      if currentBefore ~= reviewBefore then setMessage("Balance changed since Review. Please review again."); return end
      local actionPermission = draft.action == "refund" and "ledger.refund" or "ledger.adjust"
      local permissionDecision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate(actionPermission, nil)
      if not permissionDecision or permissionDecision.allowed ~= true then
        traceAccounting("Permission rejected", permissionDecision)
        setMessage(permissionDecision and permissionDecision.diagnostic or "You do not have permission.")
        return
      end
      local action = draft.action == "refund" and "refund" or draft.action == "revoke" and "revoke" or "adjustment"
      local options = { amount = draft.action == "manual" and tonumber(draft.amount) or math.abs(tonumber(draft.amount)), reason = draft.reason, confirmed = true }
      draft.committing = true
      local callOK, result, reasonCode = pcall(Dibs.Disputes.Resolve, request.requestId, action, options, Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
      if not callOK then
        draft.committing = false
        traceAccounting("Resolve error", result)
        setMessage("Unable to apply Dibs adjustment: " .. tostring(result))
        return
      end
      traceAccounting("Resolve returned", { ok = result and result.ok, reasonCode = reasonCode, transaction = result and result.transaction and result.transaction.transactionId })
      if not result or result.ok == false then
        draft.committing = false
        setMessage("Unable to apply Dibs adjustment: " .. tostring(reasonCode or result and (result.reasonCode or result.diagnostic) or "unknown error"))
        return
      end
      local refreshed = Dibs.Ledger and Dibs.Ledger.GetPlayerState and Dibs.Ledger.GetPlayerState(playerName) or nil
      local canonicalAfter = refreshed and tonumber(refreshed.balance or refreshed.currentBalance)
      if not canonicalAfter or canonicalAfter ~= reviewBefore + delta then
        draft.committing = false
        traceAccounting("Canonical verification failed", { expected = reviewBefore + delta, actual = canonicalAfter })
        setMessage("The canonical balance could not be verified after the adjustment.")
        return
      end
      local reference = result.transaction and result.transaction.transactionId or result.value and result.value.transactionId or result.correctionTransactionId
      frame.requestAccountingSuccess = { requestID = request.requestId, player = playerName, before = reviewBefore, delta = delta, after = canonicalAfter, reference = reference, reason = draft.reason }
      frame.requestAccountingReview = false
      closeRequestChildren()
      frame:Refresh()
      local updated = Dibs.Disputes.GetRequest(request.requestId, nil)
      if updated then openRequestDetail(updated) end
    end, 150)
    if not isReview and before and magnitude and limit and after > limit then Dibs.AceGUI.SetDisabled(primary, true) end
    requestChildDialog.window:Show()
    return true
  end

  local function openRequestActionDialog(request, action, title)
    if request and (request.unavailable == true or request.status == "Unavailable") then return false end
    if action == "correct_balance" or action == "refund" or action == "revoke" or action == "adjustment" then
      return openDibsAccountingWorkflow(request)
    end
    closeRequestChildren()
    if action == "historical_import" and not frame.requestHistoricalCandidate then
      local candidate = request.reconciliationCandidate or request.historicalCandidate or request.candidate
      if type(candidate) == "table" and candidate.candidateId then frame.requestHistoricalCandidate = candidate end
    end
    requestChildDialog = Dibs.AceGUI.CreateWindow("Dibs | " .. title, 540, 460, { "CENTER", 0, 0 })
    if not requestChildDialog then return false end
    local root = Dibs.AceGUI.Create(requestChildDialog, "SimpleGroup", requestChildDialog.window)
    if not root then requestChildDialog.window:Hide(); requestChildDialog = nil; return false end
    root:SetFullWidth(true); root:SetFullHeight(true); root:SetLayout("List")
    local body = Dibs.AceGUI.Create(requestChildDialog, "SimpleGroup", root)
    local footer = Dibs.AceGUI.Create(requestChildDialog, "SimpleGroup", root)
    if not body or not footer then requestChildDialog.window:Hide(); requestChildDialog = nil; return false end
    body:SetFullWidth(true); body:SetHeight(408); body:SetLayout("List")
    footer:SetFullWidth(true); footer:SetHeight(42); footer:SetLayout("Flow")
    local workflowPanel = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestChildDialog, body, title) or body
    if workflowPanel and workflowPanel ~= root then root = workflowPanel end
    local isReview = frame.requestActionReview == action
    local applyCorrection
    local function updateCorrectionButton()
      if applyCorrection then
        Dibs.AceGUI.SetDisabled(applyCorrection, trimText(frame.disputeCorrectPlayer) == ""
          and (frame.disputeCorrectItemKey == nil or trimText(frame.disputeCorrectItem) == ""))
      end
    end
    Dibs.AceGUI.AddHeading(requestChildDialog, root, title, "This action records through the existing protected request service.")

    local actionPermission = {
      correct_target = "ledger.adjust", correct_balance = "ledger.adjust", refund = "ledger.refund", revoke = "ledger.adjust",
      historical_import = "history.confirm",
    }
    local function permissionDecision()
      local actionId = actionPermission[action]
      if not actionId or not Dibs.Permissions or type(Dibs.Permissions.Evaluate) ~= "function" then return true, nil end
      local ok, decision = pcall(Dibs.Permissions.Evaluate, actionId, nil)
      if not ok or not decision or decision.allowed ~= true then
        return false, decision and (decision.diagnostic or decision.reasonCode) or "Required permission is unavailable."
      end
      return true, nil
    end
    local function errorText(reasonCode)
      local messages = {
        QUESTION_REQUIRED = "A question is required.", REASON_REQUIRED = "A reason is required.",
        AMOUNT_REQUIRED = "Enter a non-zero numeric amount.", CONFIRMATION_REQUIRED = "Explicit confirmation is required.",
        GUILD_ADMIN_REQUIRED = "Officer permission is required for this action.",
        PROTECTED_ACTION_UNAVAILABLE = "The protected action service is unavailable.",
        CORRECTION_TARGET_REQUIRED = "Select a replacement player or item first.",
        HISTORY_CANDIDATE_REQUIRED = "Select a valid historical candidate first.",
      }
      return messages[tostring(reasonCode)] or ("Action failed: " .. tostring(reasonCode or "unknown error"))
    end
    local function addMultiline(label, stateKey, height)
      return Dibs.AceGUI.AddFormRow(requestChildDialog, root, label, function(row)
        local edit = Dibs.AceGUI.AddMultilineEditBox(requestChildDialog, row, "", function(value) frame[stateKey] = value or "" end, 460, height or 64)
        setControlText(edit, frame[stateKey] or "")
        return edit
      end, (height or 64) + 36)
    end
    local function executeRequestAction(options, validate, successText, service)
      local allowed, permissionReason = permissionDecision()
      if not allowed then return false, permissionReason end
      if validate then
        local valid, validationReason = validate(options)
        if not valid then return false, validationReason end
      end
      local result, reasonCode
      if service then result, reasonCode = service(options) else result, reasonCode = Dibs.Disputes.Resolve(request.requestId, action, options, nil) end
      if not result or result.ok == false then return false, reasonCode or result and (result.reasonCode or result.diagnostic) or "SERVICE_FAILED" end
      frame.disputeStatusMessage = successText
      frame.requestActionReview = nil
      frame.requestSuccess = {
        requestId = request.requestId, action = successText,
        transaction = result.transaction or result.value, reference = result.transaction and result.transaction.transactionId or result.value and result.value.transactionId,
      }
      if requestChildDialog and requestChildDialog.window then requestChildDialog.window:Hide() end
      requestChildDialog = nil
      frame:Refresh()
      local updated = Dibs.Disputes.GetRequest(request.requestId, nil)
      if updated then openRequestDetail(updated) end
      return true
    end

    if action ~= "correct_target" then
      local stateKey = action == "ask_information" and "requestQuestion"
        or action == "no_correction" and "requestResolutionNote"
        or action == "reject" and "requestRejectReason"
        or "requestActionReason"
      local label = action == "ask_information" and "Message / question"
        or action == "no_correction" and "Resolution note"
        or action == "reject" and "Reason" or "Reason / note"
      local playerName = request.player and request.player.name or request.playerName or "Unavailable"
      if action == "correct_balance" or action == "refund" or action == "revoke" then
        Dibs.AceGUI.AddSummaryRow(requestChildDialog, root, "Player", playerName, 30)
        local balance = Dibs.Ledger and Dibs.Ledger.GetPlayerState and Dibs.Ledger.GetPlayerState(playerName) or {}
        if action == "correct_balance" then
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "Adjust Dibs for " .. tostring(request.categoryLabel or request.category or "this request"), true)
          Dibs.AceGUI.AddSummaryRow(requestChildDialog, root, "Current balance", balance.balance or "Unavailable", 28)
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "The request category determines whether the adjustment adds or refunds Dibs.", true)
        elseif action == "refund" then
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "Refund the recorded Dib for this request.", true)
        else
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "Revoke a Dib by appending a negative ledger adjustment.", true)
        end
        if not isReview then
          frame.requestActionAmount = frame.requestActionAmount or ""
          Dibs.AceGUI.AddFormRow(requestChildDialog, root, action == "correct_balance" and "Dib adjustment amount" or "Dib amount", function(row)
            return Dibs.AceGUI.AddEditBox(requestChildDialog, row, "", function(value) frame.requestActionAmount = value or "" end, 180)
          end, 54)
          local amount = Dibs.AceGUI.AddLabel(requestChildDialog, root, "Enter a positive integer amount; the service applies the authoritative sign.", true)
          Dibs.AceGUI.AddTooltip(amount, "Amount", "This value is sent to the existing ledger correction service.")
          addMultiline("Reason", stateKey, 54)
          if frame.requestActionConfirmed == nil then frame.requestActionConfirmed = false end
          Dibs.AceGUI.AddFormRow(requestChildDialog, root, "", function(row)
            return Dibs.AceGUI.AddCheckBox(requestChildDialog, row, "I understand this changes recorded Dibs data", frame.requestActionConfirmed, function(value) frame.requestActionConfirmed = value == true end, 460)
          end, 34)
        end
      elseif action == "historical_import" then
        local candidate = frame.requestHistoricalCandidate
        if candidate then
          for _, entry in ipairs({ { "Item", candidate.itemLink or candidate.itemID }, { "Winner", candidate.playerName }, { "Encounter", tostring(candidate.instanceName or "Unavailable") .. " / " .. tostring(candidate.encounterName or "Unavailable") }, { "Difficulty", candidate.difficultyText or candidate.difficulty }, { "Award date", candidate.originalAwardTimeText or candidate.originalAwardTime }, { "Evidence", candidate.classification } }) do
            Dibs.AceGUI.AddLabel(requestChildDialog, root, entry[1] .. ": " .. tostring(entry[2] or "Unavailable"), true)
          end
        else
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "No valid historical candidate is selected.", true)
        end
        if not isReview then addMultiline("Reason / note", stateKey, 54) end
      else
        if not isReview then addMultiline(label, stateKey, 64) end
      end
      if isReview then
        Dibs.AceGUI.AddHeading(requestChildDialog, root, "Review", "Confirm the exact action below. Original history is preserved.")
        Dibs.AceGUI.AddSummaryRow(requestChildDialog, root, "Request", request.requestId or "Unavailable", 28)
        Dibs.AceGUI.AddSummaryRow(requestChildDialog, root, "Action", title, 28)
        if action == "refund" or action == "revoke" or action == "correct_balance" or action == "adjustment" then
          Dibs.AceGUI.AddSummaryRow(requestChildDialog, root, "Amount", frame.requestActionAmount or "Unavailable", 28)
        end
        Dibs.AceGUI.AddSummaryRow(requestChildDialog, root, "Reason", frame[stateKey] or "Unavailable", 34)
        Dibs.AceGUI.AddLabel(requestChildDialog, root, "This correction will be permanently logged. Original history will not be deleted.", true)
      end
      local message = Dibs.AceGUI.AddLabel(requestChildDialog, root, "", true)
      local cancel = Dibs.AceGUI.AddButton(requestChildDialog, footer, isReview and "Back" or "Cancel", function()
        if isReview then frame.requestActionReview = nil; openRequestActionDialog(request, action, title) else closeRequestChildren() end
      end, 90)
      local actionText = isReview and (action == "ask_information" and "Confirm question" or action == "no_correction" and "Confirm resolve" or action == "reject" and "Confirm reject" or action == "refund" and "Confirm refund" or action == "revoke" and "Confirm revoke" or action == "historical_import" and "Confirm import" or action == "adjustment" and "Confirm adjustment" or "Confirm action") or "Review"
      local confirm = Dibs.AceGUI.AddButton(requestChildDialog, footer, actionText, function()
        if not isReview then frame.requestActionReview = action; openRequestActionDialog(request, action, title); return end
        local options = { reason = frame[stateKey] or "", question = frame[stateKey] or "" }
        local amount = tonumber(frame.requestActionAmount)
        if action == "correct_balance" or action == "refund" or action == "revoke" then options.amount = amount; options.confirmed = frame.requestActionConfirmed == true end
        local candidate = frame.requestHistoricalCandidate
        if action == "historical_import" then
          if not candidate then message:SetText(errorText("HISTORY_CANDIDATE_REQUIRED")); return end
          options = { reason = frame[stateKey] or "", mode = "manual", confirmation = true, manualAcknowledgement = true, candidate = candidate }
        end
        local ok, failure = executeRequestAction(options, function(payload)
          if action == "historical_import" then
            return frame.requestHistoricalCandidate and frame.requestHistoricalCandidate.candidateId ~= nil, "HISTORY_CANDIDATE_REQUIRED"
          end
          if action == "ask_information" and trimText(payload.question) == "" then return false, "QUESTION_REQUIRED" end
          if action ~= "under_review" and action ~= "reopen" and trimText(payload.reason) == "" then return false, "REASON_REQUIRED" end
          if action == "correct_balance" or action == "refund" or action == "revoke" then
            if payload.amount == nil or payload.amount == 0 then return false, "AMOUNT_REQUIRED" end
            if payload.confirmed ~= true then return false, "CONFIRMATION_REQUIRED" end
          end
          return true
        end, action == "ask_information" and "Information requested." or action == "no_correction" and "Request resolved." or action == "reject" and "Request rejected." or action == "historical_import" and "Historical record imported." or "Request updated.", action == "historical_import" and function(payload)
          local candidate = payload.candidate
          return Dibs.RCLootCouncil.ConfirmReconciliationCandidate(candidate.reconciliationSessionId or candidate.sessionId, candidate.candidateId, payload, nil)
        end or nil)
        if not ok then message:SetText(errorText(failure)) end
      end, 150)
      local allowed, permissionReason = permissionDecision()
      if not allowed then Dibs.AceGUI.SetDisabled(confirm, true); message:SetText(errorText(permissionReason)) end
      requestChildDialog.window:Show()
      return true
    end

    if action == "correct_target" then
      if not isReview then
        local evidence = request.evidence and request.evidence[1] or {}
      Dibs.AceGUI.AddLabel(requestChildDialog, root, "Reassign loot: select the replacement player, item, or both from authoritative guild and Adventure Guide data.", true)
      if frame.disputeTargetRequestId ~= request.requestId then
        frame.disputeTargetRequestId = request.requestId
        frame.disputeCorrectPlayer, frame.disputeCorrectItem = nil, nil
        frame.disputeCorrectItemKey = nil
      end
      local playerChoices = buildGuildMemberChoices("", frame.disputeCorrectPlayer)
      local playerDropdown = Dibs.AceGUI.AddDropdown(requestChildDialog, root, "Correct player", playerChoices, function(value)
        frame.disputeCorrectPlayer = value and tostring(value) ~= "" and tostring(value) or nil
        frame.disputeTargetRequestId = request.requestId
        updateCorrectionButton()
      end, 320)
      if playerDropdown then
        if frame.disputeCorrectPlayer then Dibs.AceGUI.SetValue(playerDropdown, frame.disputeCorrectPlayer)
        else Dibs.AceGUI.SetText(playerDropdown, "Select a guild player...") end
      end
      local itemCatalog = {}
      if Dibs.EncounterJournal and type(Dibs.EncounterJournal.GetLootCatalog) == "function" then
        itemCatalog = Dibs.EncounterJournal.GetLootCatalog("", { limit = 3500 }) or {}
      end
      frame.disputeCorrectPlayer = frame.disputeCorrectPlayer
      frame.disputeCorrectItemQuery = frame.disputeCorrectItemQuery or ""
      frame.disputeItemCatalogByKey = {}
      for _, candidate in ipairs(itemCatalog) do frame.disputeItemCatalogByKey[tostring(candidate.key)] = candidate end
      local itemChoices, itemMeta = {}, {}
      local function openLootRules()
        closeRequestChildren()
        frame:SelectTab("lootTypes")
      end
      local function showItemSearchState(filteredByRules)
        if filteredByRules then
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "No eligible items match the current Loot Rules.", true)
          Dibs.AceGUI.AddButton(requestChildDialog, root, "Open Loot Rules", openLootRules, 150)
        elseif next(itemChoices or {}) == nil then
          Dibs.AceGUI.AddLabel(requestChildDialog, root, "No eligible raid items found.", true)
        end
      end
      local itemDropdown
      local search = Dibs.AceGUI.AddEditBox(requestChildDialog, root, "Search Adventure Guide", function(value)
        frame.disputeCorrectItemQuery = value or ""
        local context = itemCandidateContext(request, evidence)
        context.expansionID, context.seasonID = frame.disputeCorrectExpansionID, frame.disputeCorrectSeasonID
        context.raidID, context.bossID = frame.disputeCorrectRaidID, frame.disputeCorrectBossID
        local choices, _, filteredByRules = buildAdventureGuideItemChoices(itemCatalog, frame.disputeCorrectItemQuery, frame.disputeCorrectItemKey, 200, context)
        if itemDropdown and itemDropdown.SetList then itemDropdown:SetList(choices) end
        itemChoices = choices or {}
        showItemSearchState(filteredByRules)
      end, 360)
      setControlText(search, frame.disputeCorrectItemQuery)
      local function refreshCorrectionItems()
        local context = itemCandidateContext(request, evidence)
        context.expansionID, context.seasonID = frame.disputeCorrectExpansionID, frame.disputeCorrectSeasonID
        context.raidID, context.bossID = frame.disputeCorrectRaidID, frame.disputeCorrectBossID
        local filteredByRules
        itemChoices, _, filteredByRules = buildAdventureGuideItemChoices(itemCatalog, frame.disputeCorrectItemQuery, frame.disputeCorrectItemKey, 200, context)
        if itemDropdown and itemDropdown.SetList then itemDropdown:SetList(itemChoices) end
        showItemSearchState(filteredByRules)
      end
      refreshCorrectionItems()
      itemDropdown = Dibs.AceGUI.AddDropdown(requestChildDialog, root, "Correct item", itemChoices, function(value)
        local item = itemCatalog and frame.disputeItemCatalogByKey and frame.disputeItemCatalogByKey[tostring(value)]
        if not item then
          for _, candidate in ipairs(itemCatalog or {}) do if tostring(candidate.key) == tostring(value) then item = candidate break end end
        end
        frame.disputeCorrectItemKey = item and tostring(item.key) or nil
        frame.disputeCorrectItem = item and (item.itemLink or ("item:" .. tostring(item.itemID))) or nil
        frame.disputeTargetRequestId = request.requestId
        updateCorrectionButton()
      end, 360)
      if itemDropdown then
        if frame.disputeCorrectItemKey and itemChoices[frame.disputeCorrectItemKey] then Dibs.AceGUI.SetValue(itemDropdown, frame.disputeCorrectItemKey)
        else Dibs.AceGUI.SetText(itemDropdown, "Select an Adventure Guide item...") end
      end
      local filterState = {
        expansionID = frame.disputeCorrectExpansionID,
        seasonID = frame.disputeCorrectSeasonID,
        raidID = frame.disputeCorrectRaidID,
        bossID = frame.disputeCorrectBossID,
      }
      if not filterState.expansionID then filterState.expansionID = getCurrentExpansionID() and tostring(getCurrentExpansionID()) or nil end
      if not filterState.seasonID and filterState.expansionID and Dibs.EncounterJournal and Dibs.EncounterJournal.GetCurrentGameSeason then
        local currentSeason = select(1, Dibs.EncounterJournal.GetCurrentGameSeason())
        filterState.seasonID = currentSeason and tostring(currentSeason) or nil
      end
      frame.disputeCorrectExpansionID, frame.disputeCorrectSeasonID = filterState.expansionID, filterState.seasonID
      local expansionChoices, seasonChoices, raidChoices, bossChoices = buildAdventureGuideFilterChoices(itemCatalog, filterState)
      local expansionDropdown, seasonDropdown, raidDropdown, bossDropdown
      local function filterChanged(field, value)
        local previous = frame[field]
        frame[field] = filterValue(value)
        if field == "disputeCorrectExpansionID" and previous ~= frame[field] then
          frame.disputeCorrectSeasonID, frame.disputeCorrectRaidID, frame.disputeCorrectBossID = nil, nil, nil
        elseif field == "disputeCorrectSeasonID" and previous ~= frame[field] then
          frame.disputeCorrectRaidID, frame.disputeCorrectBossID = nil, nil
        elseif field == "disputeCorrectRaidID" and previous ~= frame[field] then
          frame.disputeCorrectBossID = nil
        end
        if previous ~= frame[field] then
          frame.disputeCorrectItemKey, frame.disputeCorrectItem = nil, nil
        end
        refreshCorrectionItems()
        local state = {
          expansionID = frame.disputeCorrectExpansionID,
          seasonID = frame.disputeCorrectSeasonID,
          raidID = frame.disputeCorrectRaidID,
          bossID = frame.disputeCorrectBossID,
        }
        local nextExpansion, nextSeason, nextRaid, nextBoss = buildAdventureGuideFilterChoices(itemCatalog, state)
        if expansionDropdown then expansionDropdown:SetList(nextExpansion) end
        if seasonDropdown then seasonDropdown:SetList(nextSeason) end
        if raidDropdown then raidDropdown:SetList(nextRaid) end
        if bossDropdown then bossDropdown:SetList(nextBoss) end
      end
      expansionDropdown = Dibs.AceGUI.AddDropdown(requestChildDialog, root, "Expansion", expansionChoices, function(value) filterChanged("disputeCorrectExpansionID", value) end, 180)
      seasonDropdown = Dibs.AceGUI.AddDropdown(requestChildDialog, root, "Season", seasonChoices, function(value) filterChanged("disputeCorrectSeasonID", value) end, 180)
      raidDropdown = Dibs.AceGUI.AddDropdown(requestChildDialog, root, "Raid", raidChoices, function(value) filterChanged("disputeCorrectRaidID", value) end, 180)
      bossDropdown = Dibs.AceGUI.AddDropdown(requestChildDialog, root, "Boss", bossChoices, function(value) filterChanged("disputeCorrectBossID", value) end, 180)
        frame.disputeCorrectPlayer = frame.disputeCorrectPlayer
      end
    end
    local actionMessage = Dibs.AceGUI.AddLabel(requestChildDialog, root, "", true)
    if not isReview then
      local reason = Dibs.AceGUI.AddFormRow(requestChildDialog, root, "Reason", function(row)
        return Dibs.AceGUI.AddEditBox(requestChildDialog, row, "", function(value) frame.requestDetailReason = value or "" end, 360)
      end, 54)
      setControlText(reason, frame.requestDetailReason or "")
      if frame.requestActionConfirmed == nil then frame.requestActionConfirmed = false end
      Dibs.AceGUI.AddFormRow(requestChildDialog, root, "", function(row)
        return Dibs.AceGUI.AddCheckBox(requestChildDialog, row, "I understand this changes recorded Dibs data", frame.requestActionConfirmed, function(value)
          frame.requestActionConfirmed = value == true
        end, 360)
      end, 34)
    end
    local actions = Dibs.AceGUI.AddInlineGroup(requestChildDialog, footer)
    Dibs.AceGUI.AddButton(requestChildDialog, actions, isReview and "Back" or "Cancel", function()
      if isReview then frame.requestActionReview = nil; openRequestActionDialog(request, action, title) else requestChildDialog.window:Hide(); requestChildDialog = nil end
    end, 90)
    if isReview then
      Dibs.AceGUI.AddHeading(requestChildDialog, root, "Review", "Confirm the exact target correction. Original evidence remains immutable.")
      Dibs.AceGUI.AddLabel(requestChildDialog, root, "Player: " .. tostring(frame.disputeCorrectPlayer or "Unchanged"), true)
      Dibs.AceGUI.AddLabel(requestChildDialog, root, "Item: " .. tostring(frame.disputeCorrectItem or "Unchanged"), true)
      Dibs.AceGUI.AddLabel(requestChildDialog, root, "Reason: " .. tostring(frame.requestDetailReason or "Unavailable"), true)
      Dibs.AceGUI.AddLabel(requestChildDialog, root, "This correction creates an append-only audited record.", true)
    end
    applyCorrection = Dibs.AceGUI.AddButton(requestChildDialog, actions, isReview and "Confirm reassign" or "Review", function()
      if not isReview then frame.requestActionReview = action; openRequestActionDialog(request, action, title); return end
      if action == "correct_target" and trimText(frame.disputeCorrectPlayer) == ""
        and (frame.disputeCorrectItemKey == nil or trimText(frame.disputeCorrectItem) == "") then return end
      local options = { reason = frame.requestDetailReason or "", confirmed = frame.requestActionConfirmed == true }
      if action == "correct_target" then
        options.playerName = frame.disputeCorrectPlayer
        options.itemLink = frame.disputeCorrectItem
        local item = frame.disputeItemCatalogByKey and frame.disputeItemCatalogByKey[frame.disputeCorrectItemKey]
        options.itemID = item and item.itemID or nil
      end
      local result, reasonCode = Dibs.Disputes.Resolve(request.requestId, action, options, nil)
      frame.disputeStatusMessage = result and "Request updated." or ("Unable to update request: " .. tostring(reasonCode or "unknown"))
      if not result then actionMessage:SetText(errorText(reasonCode)); return end
      frame.requestActionReview = nil
      frame.requestSuccess = { requestId = request.requestId, action = "Reassign loot applied", reference = result.correctionTransactionId or result.transaction and result.transaction.transactionId }
      if requestChildDialog and requestChildDialog.window then requestChildDialog.window:Hide() end
      requestChildDialog = nil
      closeRequestDetail(); frame:Refresh()
    end, 150)
    if action == "correct_target" then Dibs.AceGUI.SetDisabled(applyCorrection, true) end
    updateCorrectionButton()
    requestChildDialog.window:Show()
    return true
  end

  openRequestDetail = function(request)
    if not request then return false end
    if not requestDetailShell or not requestDetailShell.window then
      requestDetailShell = Dibs.AceGUI.CreateWindow("RCLootCouncil - Dibs | Request", 600, 430, { "CENTER", 0, 0 }, "OfficerRequestDetail")
      if not requestDetailShell then return false end
      frame.requestDetailShell = requestDetailShell
      requestDetailRoot = Dibs.AceGUI.Create(requestDetailShell, "SimpleGroup", requestDetailShell.window)
    end
    if not requestDetailRoot then return false end
    frame.requestDetailRoot = requestDetailRoot
    Dibs.AceGUI.Clear(requestDetailRoot)
    requestDetailRoot:SetFullWidth(true); requestDetailRoot:SetFullHeight(true); requestDetailRoot:SetLayout("List")
    frame.disputeDetailOpen = true
    frame.disputeSelectedId = request.requestId
    local evidence = request.evidence and request.evidence[1] or {}
    local summary = requestEvidencePresentation(request, evidence)
    Dibs.AceGUI.AddHeading(requestDetailShell, requestDetailRoot, "Request #" .. tostring(request.requestId or "Unavailable"), "Review this request and choose a normal support action.")
    if frame.requestAccountingSuccess and frame.requestAccountingSuccess.requestID == request.requestId then
      local success = frame.requestAccountingSuccess
      local successSection = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestDetailShell, requestDetailRoot, "Dibs adjustment applied") or requestDetailRoot
      for _, row in ipairs({
        { "Player", success.player }, { "Before", success.before },
        { "Change", (tonumber(success.delta) or 0) >= 0 and "+" .. tostring(success.delta) or tostring(success.delta) },
        { "After", success.after }, { "Reference", success.reference or "audit event recorded" }, { "Reason", success.reason },
      }) do Dibs.AceGUI.AddLabel(requestDetailShell, successSection, row[1] .. "\n" .. tostring(row[2] or "Unavailable"), true) end
      Dibs.AceGUI.AddButton(requestDetailShell, successSection, "Back to Request", function()
        frame.requestAccountingSuccess = nil
        frame.requestAccountingDraft = nil
        openRequestDetail(request)
      end, 150)
    end
    if frame.requestSuccess and frame.requestSuccess.requestId == request.requestId then
      local successSection = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestDetailShell, requestDetailRoot, "Action applied") or requestDetailRoot
      Dibs.AceGUI.AddHeading(requestDetailShell, successSection, tostring(frame.requestSuccess.action or "Correction applied"), "The canonical service accepted the action.")
      Dibs.AceGUI.AddLabel(requestDetailShell, successSection, "Player: " .. tostring(request.player and request.player.name or request.playerName or "Unavailable"), true)
      Dibs.AceGUI.AddLabel(requestDetailShell, successSection, "Reference: " .. tostring(frame.requestSuccess.reference or "audit event recorded"), true)
      Dibs.AceGUI.AddLabel(requestDetailShell, successSection, "Original history was preserved; the change was appended to the audit trail.", true)
      Dibs.AceGUI.AddButton(requestDetailShell, successSection, "Back to Request", function() frame.requestSuccess = nil; openRequestDetail(request) end, 150)
    end
    local summarySection = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestDetailShell, requestDetailRoot, "Request summary") or requestDetailRoot
    local function addRequestField(label, value)
      Dibs.AceGUI.AddLabel(requestDetailShell, summarySection, label, true)
      Dibs.AceGUI.AddLabel(requestDetailShell, summarySection, tostring(value or "Unavailable"), true)
    end
    addRequestField("Player", summary.player ~= "" and summary.player or "Unavailable")
    addRequestField("Issue", summary.issue ~= "" and summary.issue or "Other")
    addRequestField("Item", summary.item ~= "" and summary.item or "Unavailable")
    addRequestField("Status", tostring(request.status or "Open"))
    addRequestField("Description", summary.note ~= "" and summary.note or "No note provided")
    addRequestField("Evidence", summary.evidence)
    Dibs.AceGUI.AddButton(requestDetailShell, summarySection, frame.disputeTechnicalExpanded and "Hide technical details" or "Show technical details", function()
      frame.disputeTechnicalExpanded = not frame.disputeTechnicalExpanded
      openRequestDetail(request)
    end, 180)
    if frame.disputeTechnicalExpanded then
      local technicalSection = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestDetailShell, requestDetailRoot, "Technical details") or requestDetailRoot
      for _, field in ipairs({
        { "Evidence source", evidence.source }, { "Integration", evidence.integrationStatus },
        { "Transaction", evidence.transactionRef }, { "Award/history reference", evidence.awardRef or evidence.historyRef },
      }) do
        Dibs.AceGUI.AddLabel(requestDetailShell, technicalSection, field[1] .. ": " .. tostring(field[2] or "Unavailable"), true)
      end
    end
    local actionSection = Dibs.Midnight and Dibs.Midnight.CreatePanel and Dibs.Midnight.CreatePanel(requestDetailShell, requestDetailRoot, "Officer actions") or requestDetailRoot
    local actions = Dibs.AceGUI.AddInlineGroup(requestDetailShell, actionSection)
    local terminal = request.status == "Resolved" or request.status == "Rejected"
    if request.status == "Open" or request.status == "Pending" then
      Dibs.AceGUI.AddButton(requestDetailShell, actions, "Start review", function() openRequestActionDialog(request, "under_review", "Start review") end, 110)
    end
    if not terminal then
      Dibs.AceGUI.AddButton(requestDetailShell, actions, "Ask for information", function() openRequestActionDialog(request, "ask_information", "Ask for information") end, 155)
      Dibs.AceGUI.AddButton(requestDetailShell, actions, "Resolve", function() openRequestActionDialog(request, "no_correction", "Resolve") end, 90)
      Dibs.AceGUI.AddButton(requestDetailShell, actions, "Reject", function() openRequestActionDialog(request, "reject", "Reject") end, 90)
    else
      Dibs.AceGUI.AddButton(requestDetailShell, actions, "Reopen", function() openRequestActionDialog(request, "reopen", "Reopen") end, 90)
    end
    local unavailable = request.unavailable == true or request.status == "Unavailable"
    if unavailable then frame.disputeAdvancedExpanded = false end
    if not unavailable then
      Dibs.AceGUI.AddButton(requestDetailShell, requestDetailRoot, frame.disputeAdvancedExpanded and "Hide advanced officer tools" or "Advanced Officer Tools", function()
        frame.disputeAdvancedExpanded = not frame.disputeAdvancedExpanded
        openRequestDetail(request)
      end, 190)
    end
    if not unavailable and frame.disputeAdvancedExpanded then
      local advancedSection = Dibs.AceGUI.AddSection(requestDetailShell, requestDetailRoot, "Advanced Officer Tools", "Secondary accounting and correction workflows.")
      local advancedPermissions = {
        correct_target = "ledger.adjust",
        correct_balance = "ledger.adjust",
        refund = "ledger.refund",
        revoke = "ledger.adjust",
        historical_import = "history.confirm",
      }
      local function advancedAllowed(action)
        local permission = advancedPermissions[action]
        if not permission or not Dibs.Permissions or type(Dibs.Permissions.Evaluate) ~= "function" then return false end
        local decision = Dibs.Permissions.Evaluate(permission, nil)
        return decision and decision.allowed == true
      end
      if advancedAllowed("correct_target") then
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Correct player / item", function() openRequestActionDialog(request, "correct_target", "Correct player / item") end, 180)
      end
      if advancedAllowed("correct_balance") then
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Correct balance", function() openRequestActionDialog(request, "correct_balance", "Correct balance") end, 150)
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Adjust Dibs", function() openDibsAccountingWorkflow(request) end, 150)
      end
      if advancedAllowed("refund") then
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Refund Dib", function() openRequestActionDialog(request, "refund", "Refund Dib") end, 130)
      end
      if advancedAllowed("revoke") then
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Revoke Dib", function() openRequestActionDialog(request, "revoke", "Revoke Dib") end, 130)
      end
      if advancedAllowed("historical_import") then
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Import historical", function() openRequestActionDialog(request, "historical_import", "Import historical") end, 150)
      end
      local adminDecision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate("ledger.adjust", nil)
      if adminDecision and adminDecision.allowed == true and adminDecision.role == "gm" then
        Dibs.AceGUI.AddButton(requestDetailShell, advancedSection, "Admin adjustment", function() openRequestActionDialog(request, "adjustment", "Admin adjustment") end, 150)
      end
    end
    Dibs.AceGUI.AddButton(requestDetailShell, requestDetailRoot, "Close", closeRequestDetail, 90)
    requestDetailShell.window:Show()
    if requestDetailShell.window.DoLayout then requestDetailShell.window:DoLayout() end
    return true
  end

  frame.CloseRequestDetail = closeRequestDetail
  frame.OpenRequestDetail = openRequestDetail

  local function selectSeason(offset)
    local seasons = getSeasonList()
    if #seasons == 0 then return end
    local index = 1
    for i, season in ipairs(seasons) do
      if season.id == frame.selectedSeasonId then index = i break end
    end
    index = ((index - 1 + offset) % #seasons) + 1
    frame.selectedSeasonId = seasons[index].id
    frame.inputBoundSeasonId = nil
    frame:Refresh()
  end

  local function renderSeasonsPage(shell, parent)
    local allSeasons = Dibs.Seasons and Dibs.Seasons.List and Dibs.Seasons.List(true) or {}
    local activeSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
    local selected = frame.selectedSeasonId and findSeasonById(frame.selectedSeasonId) or nil
    if not selected then
      selected = getSelectedSeason(frame) or allSeasons[#allSeasons]
      frame.selectedSeasonId = selected and selected.id or nil
    end

    Dibs.AceGUI.AddHeading(shell, parent, "Seasons", "Select a season to view details. Secondary actions are available from the row context menu.")
    local rows = {}
    for _, season in ipairs(allSeasons) do
      rows[#rows + 1] = {
        tostring(season.name or season.id),
        season.id == activeSeasonId and "ACTIVE" or (season.isArchived and "Archived" or "Available"),
        season.createdAt and date("%b %Y", season.createdAt) or "Unknown",
        season = season,
      }
    end
    if #rows == 0 then rows[1] = { "No seasons", "", "" } end

    local function selectRow(row)
      if row and row.season then
        frame.selectedSeasonId = row.season.id
        frame.seasonEditId = nil
        frame.seasonArchivePendingId = nil
        frame:Refresh()
      end
    end
    local function executeSeason(action, seasonId, payload)
      local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
        and Dibs.ProtectedActions.Execute(action, nil, payload or { seasonId = seasonId })
        or { ok = false, diagnostic = "Protected actions unavailable." }
      frame:SetStatus(result.ok and (action == "season.set" and "Active season updated." or "Season updated.")
        or (result.diagnostic or "Season action failed."))
      frame:Refresh()
    end
    local tableOptions = {
      onRowClick = function(row) selectRow(row) end,
      contextMenu = function(row)
        local season = row and row.season
        if not season then return {} end
        frame.selectedSeasonId = season.id
        local menu = {
          { text = "View details", callback = function() frame.seasonEditId = nil; frame:Refresh() end },
        }
        if not season.isArchived and season.id ~= activeSeasonId then
          menu[#menu + 1] = { text = "Set active", callback = function() executeSeason("season.set", season.id) end }
        end
        if not season.isArchived then
          menu[#menu + 1] = { text = "Rename", callback = function() frame.seasonEditId = season.id; frame:Refresh() end }
          if #allSeasons > 1 then
            menu[#menu + 1] = { text = "Archive", callback = function() frame.seasonArchivePendingId = season.id; frame:Refresh() end }
          end
        end
        return menu
      end,
    }
    Dibs.AceGUI.AddTable(shell, parent, {
      { title = "Season", width = 250, tooltip = "Season name." },
      { title = "State", width = 110, tooltip = "Active, available or archived." },
      { title = "Created", width = 120, tooltip = "Season creation month." },
    }, rows, 190, nil, tableOptions)

    if selected then
      Dibs.AceGUI.AddHeader(shell, parent, "Selected season", "Details and primary actions for the selected season.")
      Dibs.AceGUI.AddLabel(shell, parent, tostring(selected.name or selected.id) .. "  |  "
        .. (selected.id == activeSeasonId and "ACTIVE" or (selected.isArchived and "Archived" or "Available")), true)
      Dibs.AceGUI.AddLabel(shell, parent, (selected.createdAt and date("%b %Y", selected.createdAt) or "Unknown")
        .. " - " .. (selected.isArchived and "Archived" or "Current"), true)
      local actions = Dibs.AceGUI.AddInlineGroup(shell, parent)
      if not selected.isArchived and selected.id ~= activeSeasonId then
        Dibs.AceGUI.AddButton(shell, actions, "Set active", function() executeSeason("season.set", selected.id) end, 120)
      end
      if frame.seasonArchivePendingId == selected.id then
        Dibs.AceGUI.AddLabel(shell, actions, "Archive this season?", false)
        Dibs.AceGUI.AddButton(shell, actions, "Confirm archive", function()
          executeSeason("season.archive", selected.id)
          frame.seasonArchivePendingId = nil
        end, 130)
        Dibs.AceGUI.AddButton(shell, actions, "Cancel", function()
          frame.seasonArchivePendingId = nil
          frame:Refresh()
        end, 80)
      end
      if frame.seasonEditId == selected.id then
        local rename = Dibs.AceGUI.AddEditBox(shell, parent, "Rename season", function(value)
          frame.seasonRenameName = value or ""
        end, 300)
        setControlText(rename, frame.seasonRenameName or selected.name or "")
        Dibs.AceGUI.AddButton(shell, parent, "Save name", function()
          local name = trimText(frame.seasonRenameName or "")
          if name == "" then return end
          executeSeason("season.rename", selected.id, { seasonId = selected.id, name = name })
          frame.seasonEditId = nil
        end, 120)
      end
    end

    local createActions = Dibs.AceGUI.AddInlineGroup(shell, parent)
    local createInput = Dibs.AceGUI.AddEditBox(shell, createActions, "New season", function(value)
      frame.newSeasonName = value or ""
    end, 260)
    setControlText(createInput, frame.newSeasonName or "")
    Dibs.AceGUI.AddButton(shell, createActions, "Create", function()
      local name = trimText(frame.newSeasonName or "")
      local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
        and Dibs.ProtectedActions.Execute("season.create", nil, { name = name ~= "" and name or nil })
        or { ok = false, diagnostic = "Protected actions unavailable." }
      if result.ok and result.value then
        frame.selectedSeasonId = result.value.id
        frame.newSeasonName = ""
      end
      frame:SetStatus(result.ok and "Season created." or (result.diagnostic or "Unable to create season."))
      frame:Refresh()
    end, 90)
  end

  local activateRoute
  local navigation = Dibs.AceGUI.AddTree(shell, buildOfficerTree(getOfficerNavigationTree()), function(value)
    if frame._dibsRouteSyncing then return end
    if activateRoute then activateRoute(value, false) end
  end, 190)
  local contentHost = Dibs.AceGUI.Create(shell, "SimpleGroup", navigation)
  if contentHost then
    if contentHost.SetFullWidth then contentHost:SetFullWidth(true) end
    if contentHost.SetFullHeight then contentHost:SetFullHeight(true) end
    if contentHost.SetLayout then contentHost:SetLayout("List") end
  end
  frame.aceTabs = navigation
  frame.contentHost = contentHost
  frame.SelectTab = function(tab)
    if activateRoute then activateRoute(tab, true) end
  end

  local function renderRoute(self)
    self.activeTab = normalizeOfficerTab(self.activeTab or "overview")
    self.selectedRoute = self.activeTab
    if self.activeTab ~= "history" and self.activeTab ~= "reconciliation" and closeHistoryTransfer then
      closeHistoryTransfer()
    end
    if not contentHost then return end
    Dibs.AceGUI.Clear(contentHost)
    local pageRoot = Dibs.AceGUI.Create(shell, "SimpleGroup", contentHost) or contentHost
    if pageRoot ~= contentHost then
      if pageRoot.SetFullWidth then pageRoot:SetFullWidth(true) end
      if pageRoot.SetFullHeight then pageRoot:SetFullHeight(true) end
      if pageRoot.SetLayout then pageRoot:SetLayout("List") end
    end
    self.mountedPage = self.activeTab
    self.mountedPageHost = pageRoot
    self.primaryPageCount = 1
    pageRoot._dibsRoute = self.activeTab
    pageRoot._dibsOwner = self
    contentHost._dibsCurrentPageRoot = pageRoot
    local tabs = pageRoot
    local routeModules = {
      disputes = "requests", preDibs = "preDibs", announcements = "announcements",
      integration = "rclootcouncil", eligibility = "lootEligibility",
    }
    local disabledModule = routeModules[self.activeTab]
    if disabledModule and not moduleEnabled(disabledModule) then
      local status = Dibs.OperationalPolicy.GetModuleStatus(disabledModule)
      Dibs.AceGUI.AddHeader(shell, tabs, status.label or disabledModule, "Feature unavailable")
      Dibs.AceGUI.AddLabel(shell, tabs, (status.label or disabledModule) .. " is disabled by the Guild Master.", true)
      return
    end
    local routeTitles = {
      disputes = "Requests", preDibs = "Pre-Dibs", pendingAwards = "Pending Awards", history = "History", reconciliation = "History", seasons = "Seasons",
      ranks = "Rank Rules", lootTypes = "Loot Rules", announcements = "Announcements",
      integration = "RCLootCouncil", settings = "Settings", diagnostics = "Diagnostics", vault = "Vault Review",
      eligibility = "Loot Eligibility", modules = "Modules", developer = "Developer", debug = "Debug", setup = "Setup Assistant",
    }
    if self.activeTab == "preDibs" or self.activeTab == "modules" or self.activeTab == "seasons" or self.activeTab == "ranks" or self.activeTab == "lootTypes" or self.activeTab == "announcements" then
      local syncStatus = Dibs.OfficerUI.BuildSynchronizationStatus()
      if syncStatus ~= "" then Dibs.AceGUI.AddLabel(shell, tabs, syncStatus, true) end
    end
    if self.activeTab == "developer" then
      if Dibs.DeveloperUI and Dibs.DeveloperUI.GetProjection then
        local projection = Dibs.DeveloperUI.GetProjection()
        if projection.visible then
          self.developerSandboxButton = Dibs.AceGUI.AddButton(shell, tabs, projection.active and "Refresh developer sandbox" or "Open developer sandbox", function()
            local sandbox = Dibs.DeveloperSandbox
            local ok, reason = true, nil
            if sandbox and not sandbox.IsActive() then
              ok, reason = sandbox.EnterSandbox({ clone = true })
            elseif sandbox and sandbox.RefreshSandbox then
              ok, reason = sandbox.RefreshSandbox()
            end
            if not ok then
              self:SetStatus("Unable to activate developer sandbox: " .. tostring(reason or "unknown error"))
            end
            self:Refresh()
          end, 210)
          if Dibs.Midnight and Dibs.Midnight.AddSandboxBanner then
            Dibs.Midnight.AddSandboxBanner(shell, tabs, projection)
          end
          Dibs.AceGUI.AddLabel(shell, tabs, "Provider: " .. tostring(projection.provider) .. " | Role: " .. tostring(projection.role or "none")
            .. " | Coordinator: " .. tostring(projection.coordinatorState), true)
        else
          Dibs.AceGUI.AddLabel(shell, tabs, "Developer Mode required.", true)
        end
      end
      return
    end
    if self.activeTab == "diagnostics" then
      local healthText = Dibs.L or {}
      local health = Dibs.HealthUI and Dibs.HealthUI.Evaluate and Dibs.HealthUI.Evaluate() or nil
      Dibs.AceGUI.AddHeader(shell, tabs, healthText.HEALTH_DASHBOARD_TITLE or "Data health",
        healthText.HEALTH_DASHBOARD_INTRO or "Bounded operational health for the current guild and client.")
      if health and health.status ~= "DENIED" then
        local summary = Dibs.AceGUI.AddInlineGroup(shell, tabs)
        Dibs.Midnight.AddStatusBadge(shell, summary, health.status == "READY" and "success" or "warning",
          tostring(health.status))
        Dibs.AceGUI.AddLabel(shell, summary, string.format(healthText.HEALTH_DASHBOARD_VERSION or "Addon version: %s | SavedVariables schema: %s",
          tostring(health.version), tostring(health.schemaVersion or "unknown")), false)
        Dibs.AceGUI.AddLabel(shell, tabs, string.format(healthText.HEALTH_DASHBOARD_STATUS or "Overall status: %s | Blocking: %d | Warnings: %d",
          tostring(health.status), tonumber(health.blockingCount) or 0, tonumber(health.warningCount) or 0), true)
        Dibs.AceGUI.AddHeader(shell, tabs, "Service status", "A quick view of the services used by the addon.")
        for _, item in ipairs(health.checks or {}) do
          local checkRow = Dibs.AceGUI.AddInlineGroup(shell, tabs)
          local tone = item.state == "ready" and "success" or (item.state == "blocked" and "danger" or "warning")
          Dibs.Midnight.AddStatusBadge(shell, checkRow, tone, tostring(item.state):upper())
          local checkText = Dibs.AceGUI.AddLabel(shell, checkRow, tostring(item.id), false)
          if checkText and checkText.SetWidth then checkText:SetWidth(145) end
          local detail = item.reason and tostring(item.reason) or tostring(item.detail or "No additional details.")
          Dibs.AceGUI.AddLabel(shell, checkRow, detail, false)
        end
        Dibs.AceGUI.AddButton(shell, tabs, self.showHealthTechnical and (healthText.HEALTH_DASHBOARD_HIDE_DETAILS or "Hide technical health details")
          or (healthText.HEALTH_DASHBOARD_DETAILS or "Show technical health details"), function()
          self.showHealthTechnical = not self.showHealthTechnical
          self:Refresh()
        end, 240)
        if self.showHealthTechnical then
          Dibs.AceGUI.AddHeader(shell, tabs, "Technical details", "Detailed service state for troubleshooting.")
          local technical = Dibs.AceGUI.AddInlineGroup(shell, tabs)
          Dibs.AceGUI.AddLabel(shell, technical, "Persistence\n" .. tostring(health.persistence and health.persistence.state or "unknown"), false)
          Dibs.AceGUI.AddLabel(shell, technical, "Synchronization\n" .. tostring(health.sync and health.sync.state or "unknown"), false)
          Dibs.AceGUI.AddLabel(shell, technical, "RCLootCouncil\n" .. tostring(health.rclootcouncil and health.rclootcouncil.status or "unknown"), false)
        end
      else
        Dibs.AceGUI.AddLabel(shell, tabs, healthText.HEALTH_DASHBOARD_NO_REPORT or "Health report unavailable.", true)
      end
      Dibs.AceGUI.AddButton(shell, tabs, self.showRuntimeDiagnostics
        and (healthText.HEALTH_DASHBOARD_HIDE_RUNTIME or "Hide runtime diagnostics")
        or (healthText.HEALTH_DASHBOARD_SHOW_RUNTIME or "Show runtime diagnostics"), function()
        self.showRuntimeDiagnostics = not self.showRuntimeDiagnostics
        self:Refresh()
      end, 240)
      if self.showRuntimeDiagnostics then
        Dibs.AceGUI.AddHeader(shell, tabs, "Runtime diagnostics", "Bounded diagnostic information for the local Officer session.")
        Dibs.AceGUI.AddSelectableText(shell, tabs, "Copyable report", Dibs.BuildDebugReport and Dibs.BuildDebugReport() or "Diagnostics unavailable.", 820, 220)
        local moduleDiagnostics = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleManagementDiagnostics
          and Dibs.OperationalPolicy.GetModuleManagementDiagnostics(nil)
        if moduleDiagnostics then
          Dibs.AceGUI.AddHeader(shell, tabs, "Module management", "Bounded governance and authorization state.")
          Dibs.AceGUI.AddLabel(shell, tabs,
            "Governance initialized: " .. (moduleDiagnostics.governanceInitialized and "yes" or "no") .. "\n" ..
            "Governance active: " .. (moduleDiagnostics.governanceActive and "yes" or "no") .. "\n" ..
            "Governance revision: " .. tostring(moduleDiagnostics.governanceRevision) .. "\n" ..
            "Canonical player: " .. tostring(moduleDiagnostics.canonicalPlayer or "unavailable") .. "\n" ..
            "Governance GM: " .. tostring(moduleDiagnostics.governanceGM or "unavailable") .. "\n" ..
            "GM identity match: " .. (moduleDiagnostics.gmIdentityMatch and "yes" or "no") .. "\n" ..
            "Operational policy ready: " .. (moduleDiagnostics.operationalPolicyReady and "yes" or "no") .. "\n" ..
            "canManageModules: " .. (moduleDiagnostics.canManageModules and "yes" or "no") .. "\n" ..
            "Blocking reason: " .. tostring(moduleDiagnostics.blockingReason or "none"), true)
        end
      end
      return
    end
    if self.activeTab == "sync" then
      local projection = Dibs.OfficerUI.BuildSynchronizationProjection()
      local groupCount = type(GetNumGroupMembers) == "function" and tonumber(GetNumGroupMembers()) or 0
      local rosterScope = groupCount > 0 and ("Current group/raid (" .. tostring(groupCount) .. " members)") or "Guild roster (no group active)"
      Dibs.AceGUI.AddHeading(shell, tabs, "Guild synchronization", "Shows the shared Dibs data scope and the latest addon handshake observed for the current group or raid.")
      Dibs.AceGUI.AddLabel(shell, tabs,
        "Transport: " .. tostring(projection.state.state or "unknown") ..
        " | Protocol: " .. tostring(projection.protocolState) ..
        " | Policy: " .. tostring(projection.policy) ..
        " | Season catalog revision: " .. tostring(projection.seasonCatalogRevision) ..
        " | Pending award proposals: " .. tostring(projection.pendingAwardProposals) ..
        "\nRoster scope: " .. rosterScope, true)
      Dibs.AceGUI.AddLabel(shell, tabs, "Synchronized: Pre-Dibs requests, guild policy, season catalog, vault acquisition summaries, and ledger digests when V2 enforcement is active. Live loot candidates, votes, responses, and item transfers are never synchronized.", true)
      Dibs.AceGUI.AddButton(shell, tabs, "Announce presence", function()
        local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
        if tonumber(catalog.catalogRevision) == 0 and Dibs.Seasons and Dibs.Seasons.PublishCatalog then
          Dibs.Seasons.PublishCatalog(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, "SYNC_BOOTSTRAP")
        end
        if Dibs.Sync and Dibs.Sync.OnLifecycle then
          Dibs.Sync.OnLifecycle("OFFICER_SYNC_PAGE")
        elseif Dibs.Sync and Dibs.Sync.Send then
          Dibs.Sync.Send({ type = "HELLO", protocolState = Dibs.Sync.GetProtocolState and Dibs.Sync.GetProtocolState() or "LEGACY_LOCAL", lifecycle = "OFFICER_SYNC_PAGE" }, "GUILD")
        end
        self:Refresh()
      end, 130)
      if Dibs.Permissions and Dibs.Permissions.IsGM and Dibs.Permissions.IsGM()
        and Dibs.Governance and Dibs.Governance.ActivateV2 then
        Dibs.AceGUI.AddButton(shell, tabs, "Approve baseline and enable V2", function()
          local ok, reason = Dibs.Governance.ActivateV2(nil)
          if ok and Dibs.Sync and Dibs.Sync.AnnounceGovernance then Dibs.Sync.AnnounceGovernance() end
          self:SetStatus(ok and "V2 Ledger is now enforced." or "V2 Ledger activation blocked: " .. tostring(reason or "unknown"))
          self:Refresh()
        end, 150)
      end
      local rows = {}
      for _, peer in ipairs(projection.peers) do
        rows[#rows + 1] = {
          peer.playerName,
          peer.online and "Online" or "Offline",
          peer.addonStatus,
          peer.addonVersion,
          peer.compatibility,
          peer.syncStatus,
          tostring(peer.seasonCatalogRevision or 0),
          tostring(peer.policyRevision or 0),
          tostring(peer.governanceRevision or 0),
          tostring(peer.predibRevision or 0),
          tostring(peer.vaultRevision or 0),
          tostring(peer.ledgerRevision or 0),
          peer.lastSeenAt > 0 and date("%Y-%m-%d %H:%M", peer.lastSeenAt) or "Never",
        }
      end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Player", width = 170, tooltip = "Guild member." },
        { title = "Online", width = 75, tooltip = "Current guild roster presence." },
        { title = "Addon", width = 100, tooltip = "Detected when the player answers a Dibs HELLO or sync message." },
        { title = "Version", width = 90, tooltip = "Last Dibs addon version reported by the player." },
        { title = "Compatibility", width = 110, tooltip = "Compatibility with this client version." },
        { title = "Sync", width = 100, tooltip = "Whether the player has the same known synchronization revisions as this client." },
        { title = "Catalog", width = 70, tooltip = "Season, rank rules, and guild configuration revision reported by this player." },
        { title = "Policy", width = 65, tooltip = "Operational policy revision reported by this player." },
        { title = "Governance", width = 80, tooltip = "Governance revision reported by this player." },
        { title = "Requests", width = 70, tooltip = "Pre-Dibs request index revision reported by this player." },
        { title = "Vault", width = 60, tooltip = "Vault acquisition index revision reported by this player." },
        { title = "History", width = 65, tooltip = "Ledger revision reported by this player when V2 enforcement is active." },
        { title = "Last response", width = 125, tooltip = "Last response received from this player." },
      }, rows, 430)
      return
    end
    local seasons = getSeasonList()
    local current = getSelectedSeason(self)
    if not current and #seasons > 0 then
      current = seasons[#seasons]
      self.selectedSeasonId = current.id
    end
    local currentId = current and current.id or nil

    if self.activeTab == "overview" then
      renderDashboard(shell, tabs, self)
      return
    end

    if self.activeTab == "setup" then
      local setupText = Dibs.L or {}
      local report = Dibs.SetupAssistant and Dibs.SetupAssistant.Evaluate and Dibs.SetupAssistant.Evaluate() or {
        status = "UNAVAILABLE", checks = {}, blockingCount = 0,
      }
      Dibs.AceGUI.AddHeader(shell, tabs, setupText.SETUP_ASSISTANT_TITLE or "First installation assistant",
        setupText.SETUP_ASSISTANT_INTRO or "Check the guild setup before the first raid without editing SavedVariables.")
      Dibs.AceGUI.AddLabel(shell, tabs,
        string.format(setupText.SETUP_ASSISTANT_STATUS or "Status: %s | Blocking checks: %d",
          tostring(report.status), tonumber(report.blockingCount) or 0), true)
      local rows = {}
      for _, item in ipairs(report.checks or {}) do
        rows[#rows + 1] = {
          tostring(item.id), tostring(item.state), item.required and "Yes" or "No",
          tostring(item.remediation or item.impact or "No action"),
          _setupCheckId = item.id,
        }
      end
      local setupRoutes = {
        season = "seasons", policy = "ranks", rank_rules = "ranks", authority = "settings",
        installation = "settings", rclootcouncil = "integration", channels = "announcements",
        loot_types = "lootTypes",
      }
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = setupText.SETUP_ASSISTANT_CHECK or "Check", width = 150, tooltip = setupText.SETUP_ASSISTANT_CHECK_TOOLTIP or "Installation prerequisite." },
        { title = setupText.SETUP_ASSISTANT_STATE or "State", width = 110, tooltip = setupText.SETUP_ASSISTANT_STATE_TOOLTIP or "Current state of the prerequisite." },
        { title = setupText.SETUP_ASSISTANT_BLOCKS or "Blocks", width = 70, tooltip = setupText.SETUP_ASSISTANT_BLOCKS_TOOLTIP or "Whether this check blocks Ready for raid." },
        { title = setupText.SETUP_ASSISTANT_NEXT_ACTION or "Next action", width = 430, tooltip = setupText.SETUP_ASSISTANT_NEXT_ACTION_TOOLTIP or "Remediation or current limitation." },
        { title = setupText.SETUP_ASSISTANT_ACTION or "Setup", width = 130, action = true, tooltip = setupText.SETUP_ASSISTANT_ACTION_TOOLTIP or "Open the relevant configuration or refresh this check." },
      }, rows, 300, function(row)
        local route = setupRoutes[row._setupCheckId]
        return {
          text = route and (setupText.SETUP_ASSISTANT_OPEN_CONFIGURATION or "Open configuration")
            or (setupText.SETUP_ASSISTANT_REFRESH_CHECK or "Refresh check"),
          callback = function()
            if route then self:ActivateRoute(route) else self:Refresh() end
          end,
        }
      end)
      Dibs.AceGUI.AddButton(shell, tabs, setupText.SETUP_ASSISTANT_REFRESH or "Refresh checklist", function()
        self:Refresh()
      end, 150)
      Dibs.AceGUI.AddButton(shell, tabs, setupText.SETUP_ASSISTANT_DRY_RUN or "Run local dry-run", function()
        local result, reason
        if Dibs.SetupAssistant and Dibs.SetupAssistant.RunDryRun then
          result, reason = Dibs.SetupAssistant.RunDryRun({
            item = 275658,
            winner = Dibs.GetPlayerName and Dibs.GetPlayerName() or "",
            response = "DIB",
            status = "test",
            sessionIdentity = "setup-assistant-ui",
          }, { allowPlayer = true })
        end
        self:SetStatus(result and string.format(setupText.SETUP_ASSISTANT_DRY_RUN_RESULT or "Local dry-run: %s", tostring(result.outcome))
          or string.format(setupText.SETUP_ASSISTANT_DRY_RUN_UNAVAILABLE or "Dry-run unavailable: %s", tostring(reason)))
        self:Refresh()
      end, 150)
      self.setupSeasonInput = Dibs.AceGUI.AddEditBox(shell, tabs, setupText.SETUP_ASSISTANT_NEW_SEASON or "New season name", nil, 240)
      setControlText(self.setupSeasonInput, setupText.SETUP_ASSISTANT_DEFAULT_SEASON or "Season 1")
      Dibs.AceGUI.AddButton(shell, tabs, setupText.SETUP_ASSISTANT_CREATE_SEASON or "Create season", function()
        local name = trimText(getControlText(self.setupSeasonInput))
        local result = Dibs.SetupAssistant.ExecuteAction("season.create", nil, { name = name, source = "setup-assistant" })
        self:SetStatus(result and result.ok and (setupText.SETUP_ASSISTANT_SEASON_CREATED or "Season created.")
          or (result and result.diagnostic) or (setupText.SETUP_ASSISTANT_SEASON_CREATE_FAILED or "Unable to create season."))
        self:Refresh()
      end, 120)
      local modeValues = { AUTO = "Automatic", STANDALONE = "Standalone", RCLootCouncil = "RCLootCouncil" }
      self.setupModeControl = Dibs.AceGUI.AddDropdown(shell, tabs, setupText.SETUP_ASSISTANT_INSTALLATION_MODE or "Installation mode", modeValues, function(value)
        self.setupModeValue = value
      end, 220)
      self.setupModeValue = self.setupModeValue or (Dibs.Permissions and Dibs.Permissions.GetInstallationMode and Dibs.Permissions.GetInstallationMode() or "AUTO")
      Dibs.AceGUI.SetValue(self.setupModeControl, self.setupModeValue)
      Dibs.AceGUI.AddButton(shell, tabs, setupText.SETUP_ASSISTANT_APPLY_MODE or "Apply mode", function()
        local result = Dibs.SetupAssistant.ExecuteAction("installation.mode.set", nil, { mode = self.setupModeValue, source = "setup-assistant" })
        self:SetStatus(result and result.ok and (setupText.SETUP_ASSISTANT_MODE_UPDATED or "Installation mode updated.")
          or (result and result.diagnostic) or (setupText.SETUP_ASSISTANT_MODE_UPDATE_FAILED or "Unable to update installation mode."))
        self:Refresh()
      end, 100)
      if report.dryRun then
        Dibs.AceGUI.AddLabel(shell, tabs, string.format(setupText.SETUP_ASSISTANT_LAST_DRY_RUN or "Last local dry-run: %s (%s)",
          tostring(report.dryRun.outcome or "unknown"), tostring(setupText.SETUP_ASSISTANT_NO_LIVE_CHANGES or "no live changes")), true)
      end
      return
    end

    if self.activeTab == "seasons" then
      renderSeasonsPage(shell, tabs)
      return
    end

    if self.activeTab == "modules" then
      local policy = Dibs.OperationalPolicy
      local coreDefinitions = policy and policy.GetCoreModuleDefinitions and policy.GetCoreModuleDefinitions() or {}
      local definitions = policy and policy.GetModuleDefinitions and policy.GetModuleDefinitions() or {}
      local canonicalModules = policy and policy.GetModuleValues and policy.GetModuleValues() or {}
      local copyModules = function(value)
        return Dibs.DeepCopy and Dibs.DeepCopy(value or {}) or value or {}
      end
      if not self.moduleAuthoritativeModules then self.moduleAuthoritativeModules = copyModules(canonicalModules) end
      if not self.moduleDraft then self.moduleDraft = copyModules(self.moduleAuthoritativeModules) end
      local draft = self.moduleDraft
      local authoritativeModules = self.moduleAuthoritativeModules
      for _, definition in ipairs(definitions) do
        if draft[definition.key] == nil then draft[definition.key] = canonicalModules[definition.key] == true end
      end
      local dirty = false
      for _, definition in ipairs(definitions) do
        if draft[definition.key] ~= authoritativeModules[definition.key] then dirty = true; break end
      end
      local moduleDiagnostics = policy and policy.GetModuleManagementDiagnostics and policy.GetModuleManagementDiagnostics(nil) or {
        canManageModules = false, blockingReason = "POLICY_UNAVAILABLE", blockingMessage = "Module management unavailable.",
      }
      local canWrite = moduleDiagnostics.canManageModules == true
      if dirty then
        moduleUiDebug("MODULE_UI_DIRTY dirty=true")
      end
      local governanceState = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
      local governanceReady = governanceState.status == "GOVERNANCE_ADOPTED"
      Dibs.AceGUI.AddHeader(shell, tabs, "Module Policy", "GM authority: " .. (canWrite and "Ready" or "Read-only")
        .. " | Governance: " .. (governanceReady and "Active" or "Not initialized")
        .. " | Revision: " .. tostring(policy and policy.GetState and policy.GetState().policyRevision or 0))
      if not governanceReady then
        Dibs.AceGUI.AddLabel(shell, tabs, "Module management unavailable", true)
        Dibs.AceGUI.AddLabel(shell, tabs, "Guild governance must be initialized first.", true)
        local canInitialize = Dibs.Governance and Dibs.Governance.CanAdoptInitial and Dibs.Governance.CanAdoptInitial(nil) == true
        if canInitialize then
          Dibs.AceGUI.AddLabel(shell, tabs, "Only the verified Guild Master can initialize module governance.", true)
          if self.governanceBootstrapPending then
            Dibs.AceGUI.AddHeader(shell, tabs, "Initialize Guild Governance", "Review this canonical guild bootstrap before confirming.")
            local guildName = type(GetGuildInfo) == "function" and GetGuildInfo("player") or "Unavailable"
            Dibs.AceGUI.AddLabel(shell, tabs, "Guild\n" .. tostring(guildName or "Unavailable")
              .. "\n\nGuild Master\n" .. tostring(Dibs.GetPlayerName and Dibs.GetPlayerName() or "Unavailable")
              .. "\n\nThis will initialize canonical Dibs governance for this guild.\nIt does not delete or modify existing Dibs history.", true)
            Dibs.AceGUI.AddButton(shell, tabs, "Cancel", function()
              self.governanceBootstrapPending = nil
              self:Refresh()
            end, 90)
            Dibs.AceGUI.AddButton(shell, tabs, "Initialize", function()
              local authorized, authorizationReason = Dibs.Governance.CanAdoptInitial(nil)
              if not authorized then
                self.governanceBootstrapError = authorizationReason or "GUILD_MASTER_REQUIRED"
                self.governanceBootstrapPending = nil
                self:Refresh()
                return
              end
              local ok, reason = Dibs.Governance.AdoptInitial(nil, {
                reason = "MODULE_MANAGEMENT_BOOTSTRAP",
                officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
                policyWriterRule = { kind = "GOVERNANCE_ONLY" },
              })
              if not ok then
                self.governanceBootstrapError = reason or "GOVERNANCE_BOOTSTRAP_FAILED"
              else
                self.governanceBootstrapError = nil
              end
              self.governanceBootstrapPending = nil
              self:Refresh()
            end, 100)
          else
            Dibs.AceGUI.AddButton(shell, tabs, "Initialize Guild Governance", function()
              self.governanceBootstrapPending = true
              self.governanceBootstrapError = nil
              self:Refresh()
            end, 210)
          end
        else
          Dibs.AceGUI.AddLabel(shell, tabs, "Only the Guild Master can initialize it.", true)
        end
        if self.governanceBootstrapError then
          Dibs.AceGUI.AddLabel(shell, tabs, "Initialization failed: " .. tostring(self.governanceBootstrapError), true)
        end
      elseif not canWrite then
        Dibs.AceGUI.AddLabel(shell, tabs, "Module management unavailable", true)
        Dibs.AceGUI.AddLabel(shell, tabs, moduleDiagnostics.blockingMessage or tostring(moduleDiagnostics.blockingReason or "Authorization could not be verified."), true)
      end
      Dibs.AceGUI.AddHeader(shell, tabs, "Core Services", "These services are always enabled and cannot be changed.")
      for _, definition in ipairs(coreDefinitions) do
        Dibs.AceGUI.AddLabel(shell, tabs, definition.label .. " - Always enabled", true)
      end
      Dibs.AceGUI.AddHeader(shell, tabs, "Optional Features", "Guild-wide activation is stored in the operational policy.")
      for _, definition in ipairs(definitions) do
        local dependencyBlocked = definition.requires and draft[definition.requires] ~= true
        local control = Dibs.AceGUI.AddCheckBox(shell, tabs, definition.label, draft[definition.key], function(value)
          local oldDraft = self.moduleDraft[definition.key]
          self.moduleDraft[definition.key] = value == true
          if definition.key == "rclootcouncil" and value ~= true and self.moduleDraft.historicalReconciliation ~= false then
            self.moduleDraft.historicalReconciliation = false
          end
          moduleUiDebug("MODULE_UI_CLICK module=" .. tostring(definition.key)
            .. " oldDraft=" .. tostring(oldDraft)
            .. " newDraft=" .. tostring(self.moduleDraft[definition.key])
            .. " canManageModules=" .. tostring(canWrite))
          local refresh = function()
            if self.activeTab == "modules" then self:Refresh() end
          end
          if Dibs.AceGUI.RequestRefresh then
            Dibs.AceGUI.RequestRefresh("MODULE_UI_CLICK", refresh)
          else
            refresh()
          end
        end, 260)
        Dibs.AceGUI.SetValue(control, draft[definition.key])
        Dibs.AceGUI.SetDisabled(control, not canWrite or dependencyBlocked)
        if definition.requires then
          Dibs.AceGUI.AddLabel(shell, tabs, dependencyBlocked and ("Requires " .. tostring(definition.requires) .. ".") or "", true)
        end
      end
      if dirty then
        Dibs.AceGUI.AddLabel(shell, tabs, "Modules - Unsaved changes", true)
        Dibs.AceGUI.AddButton(shell, tabs, "Reset", function()
          self.moduleDraft = copyModules(self.moduleAuthoritativeModules)
          self:Refresh()
        end, 80)
      end
      if dirty then
        local save = Dibs.AceGUI.AddButton(shell, tabs, "Save changes", function()
        local authorized, authorizationReason = policy.CanChangeModules(nil)
        if not authorized then self:SetStatus("Unable to save module settings: " .. tostring(authorizationReason or "authorization required")); return end
        local ok, reason = policy.ChangeModules(self.moduleDraft, nil, "MODULE_ENABLEMENT")
        self:SetStatus(ok and "Module settings saved." or (reason == "MODULE_DEPENDENCY_RCLootCouncil" and "Historical Reconciliation requires RCLootCouncil." or "Unable to save module settings: " .. tostring(reason or "unknown error")))
        if ok then
          self.moduleAuthoritativeModules = copyModules(policy.GetModuleValues and policy.GetModuleValues() or self.moduleDraft)
          self.moduleDraft = copyModules(self.moduleAuthoritativeModules)
        end
        self:Refresh()
        end, 140)
        Dibs.AceGUI.SetDisabled(save, not canWrite)
      end
      return
    end

    -- Render the canonical Officer options directly from the shared
    -- AceConfig table.  This keeps Seasons, Rank Rules, Settings, Pre-Dibs,
    -- Announcements, Developer, RCLootCouncil and Debug in lockstep with the
    -- options visible in RCLootCouncil's own panel.
    local optionGroup
    local optionsTable
    if Dibs.RCOptions and Dibs.RCOptions.GetOptionsTable then
      optionsTable = Dibs.RCOptions.GetOptionsTable()
      local groups = optionsTable and optionsTable.args and optionsTable.args.dibsSettings and optionsTable.args.dibsSettings.args
      if groups then
        optionGroup = self.activeTab == "overview" and groups.overview
          or (self.activeTab == "preDibs" and groups.preDibs)
          -- Review Requests is a custom OfficerUI page.  The options table
          -- also exposes a small entry point with the same key, but rendering
          -- that AceConfig group here hides the actual queue and its actions.
          or (self.activeTab ~= "disputes" and self.activeTab ~= "reconciliation" and self.activeTab ~= "eligibility" and self.activeTab ~= "debug" and groups.officer and groups.officer.args and groups.officer.args[self.activeTab])
      end
    end
    if not optionGroup and self.activeTab ~= "overview" then
      Dibs.AceGUI.AddHeading(shell, tabs, routeTitles[self.activeTab] or "Officer", "Officer controls and current local projection.")
    end
    if optionGroup and Dibs.AceGUI.RenderOptionsGroup then
      self.lootTypeControls = self.activeTab == "integration" and {} or nil
      local controlMap = self.lootTypeControls
      -- Overview is intentionally short; render it directly in the TreeGroup
      -- content so a fixed 680px scroll frame does not push its launch actions
      -- to the bottom of a mostly empty page. Other canonical option pages keep
      -- their bounded scroll frame for long settings lists.
      local renderedTarget
      Dibs.AceGUI.RenderOptionsGroup(shell, tabs, optionGroup, {
        controlMap = controlMap,
        scroll = self.activeTab ~= "overview",
        renderGroupTitle = true,
        flattenInlineGroups = true,
        onRendered = function(target) renderedTarget = target end,
        onChanged = function()
          self:Refresh()
        end,
      })
      local actionParent = renderedTarget or tabs
      if self.activeTab == "overview" then
        local officerRoot = optionsTable and optionsTable.args and optionsTable.args.dibsSettings
          and optionsTable.args.dibsSettings.args and optionsTable.args.dibsSettings.args.officer
        local openLogs = officerRoot and officerRoot.args and officerRoot.args.openLogs
        if Dibs.RCOptions and Dibs.RCOptions.Open then
          Dibs.AceGUI.AddButton(shell, actionParent, "Open full options", function() Dibs.RCOptions.Open() end, 180)
        end
        if openLogs then
          Dibs.AceGUI.AddHeader(shell, actionParent, "Officer management", "Open the detailed player, Pre-Dib and history logs.")
          Dibs.AceGUI.AddButton(shell, actionParent, tostring(type(openLogs.name) == "function" and openLogs.name() or openLogs.name or "Open logs window"), function()
            if type(openLogs.func) == "function" then pcall(openLogs.func) end
          end, 220)
        end
      end
      if self.activeTab == "integration" and controlMap then
        self.enableLootTypes = controlMap.enable
        self.defaultLootTypes = controlMap.disable
      end
      return
    end

    if self.activeTab == "eligibility" then
      local scroll = Dibs.AceGUI.AddScrollableList(shell, tabs, 700) or tabs
      local seasonId = currentId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
      self.eligibilityAdvanced = self.eligibilityAdvanced == true
      local eligibilityProjection = Dibs.OfficerUI.GetEligibilityProjection(seasonId, { expanded = self.eligibilityAdvanced })
      Dibs.AceGUI.AddHeading(shell, scroll, "Protected loot eligibility", "Start with the Recommended preset. Customize advanced policy only when needed.")
      Dibs.AceGUI.AddLabel(shell, scroll, eligibilityProjection.preset.label .. ": " .. eligibilityProjection.preset.description, true)
      local categoryRows = {}
      for _, category in ipairs(eligibilityProjection.categories or {}) do
        categoryRows[#categoryRows + 1] = {
          category.label,
          category.state == "allow" and "Allowed" or "Blocked",
          category.reason,
          category = category,
        }
      end
      Dibs.AceGUI.AddTable(shell, scroll, {
        { title = "Category", width = 150, tooltip = "Semantic loot category." },
        { title = "Recommended", width = 100, tooltip = "Recommended presentation state." },
        { title = "Reason", width = 420, tooltip = "Safe explanation for the current state." },
      }, categoryRows, 220, nil, { noScrolling = true })
      Dibs.AceGUI.AddButton(shell, scroll, self.eligibilityAdvanced and "Hide Customize" or "Customize", function()
        self.eligibilityAdvanced = not self.eligibilityAdvanced
        self:Refresh()
      end, 140)
      if not self.eligibilityAdvanced then
        return
      end
      local customRows = {}
      for _, category in ipairs(eligibilityProjection.categories or {}) do
        local enabled = category.currentState and category.currentState.enabled
        customRows[#customRows + 1] = {
          category.label,
          enabled == false and "Blocked" or "Allowed",
          category = category,
        }
      end
      self.eligibilityCategoryKey = self.eligibilityCategoryKey or (eligibilityProjection.categories[1] and eligibilityProjection.categories[1].key)
      local selectedCategory
      for _, category in ipairs(eligibilityProjection.categories or {}) do
        if category.key == self.eligibilityCategoryKey then selectedCategory = category break end
      end
      Dibs.AceGUI.AddHeading(shell, scroll, "Loot Eligibility - Custom", "Select a category for details. Use the row context menu for secondary state changes.")
      Dibs.AceGUI.AddTable(shell, scroll, {
        { title = "Category", width = 220, tooltip = "Semantic loot category." },
        { title = "State", width = 110, tooltip = "Current policy state." },
      }, customRows, 190, nil, {
        onRowClick = function(row)
          if row and row.category then self.eligibilityCategoryKey = row.category.key; self:Refresh() end
        end,
        contextMenu = function(row)
          local category = row and row.category
          if not category then return {} end
          self.eligibilityCategoryKey = category.key
          if not category.editable then return { { text = "View reason", callback = function() self:Refresh() end } } end
          return {
            { text = "Allow", callback = function() self.eligibilityDraftState = "allow"; self:Refresh() end },
            { text = "Block", callback = function() self.eligibilityDraftState = "block"; self:Refresh() end },
            { text = "Reset to recommended", callback = function() self.eligibilityDraftState = nil; self:Refresh() end },
            { text = "View reason", callback = function() self:Refresh() end },
          }
        end,
      })
      if selectedCategory then
        local family = selectedCategory.semanticFamily
        local policy = Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetPolicy
          and Dibs.CharacterEligibility.GetPolicy(seasonId, family) or nil
        local enabled = self.eligibilityDraftState == "allow"
          or (self.eligibilityDraftState ~= "block" and selectedCategory.currentState.enabled ~= false)
        Dibs.AceGUI.AddHeader(shell, scroll, "Selected category", "The explanation remains visible without expanding the whole policy matrix.")
        Dibs.AceGUI.AddLabel(shell, scroll, tostring(selectedCategory.label) .. "  |  " .. (enabled and "Allowed" or "Blocked"), true)
        Dibs.AceGUI.AddLabel(shell, scroll, tostring(selectedCategory.reason or "No additional reason available."), true)
        if selectedCategory.editable then
          local detail = Dibs.AceGUI.AddInlineGroup(shell, scroll)
          local scope = Dibs.AceGUI.AddDropdown(shell, detail, "Difficulty scope", { ALL = "All difficulties", SAME = "Same difficulty" }, nil, 220)
          Dibs.AceGUI.SetValue(scope, policy and policy.difficultyScope or "ALL")
          local outcome = Dibs.AceGUI.AddDropdown(shell, detail, "Duplicate outcome", { block = "Block", downgrade = "Downgrade", review = "Officer review", warn = "Warn", allow = "Allow" }, nil, 220)
          Dibs.AceGUI.SetValue(outcome, policy and policy.enforcementOutcome or "block")
          local threshold
          if family == "TOKEN" then
            threshold = Dibs.AceGUI.AddEditBox(shell, detail, "Curio completion slots", nil, 120)
            setControlText(threshold, tostring(policy and policy.completionThreshold or 4))
          end
          Dibs.AceGUI.AddButton(shell, detail, "Save", function()
            local payload = {
              seasonId = seasonId, family = family, enabled = enabled,
              difficultyScope = policy and policy.difficultyScope or "ALL",
              enforcementOutcome = policy and policy.enforcementOutcome or "BLOCK",
            }
            if scope and scope.GetValue then payload.difficultyScope = scope:GetValue() end
            if outcome and outcome.GetValue then payload.enforcementOutcome = outcome:GetValue() end
            if threshold then payload.completionThreshold = tonumber(getControlText(threshold)) or 4 end
            local result = Dibs.OfficerUI.SaveEligibilityPolicy(payload)
            self.eligibilityDraftState = nil
            self:SetStatus(result.ok and "Protected-loot policy saved." or (result.diagnostic or "Unable to save protected-loot policy."))
            self:Refresh()
          end, 90)
          Dibs.AceGUI.AddButton(shell, detail, "Cancel", function()
            self.eligibilityDraftState = nil
            self.eligibilityAdvanced = false
            self:Refresh()
          end, 90)
        end
      end
      return
    end

    if self.activeTab == "disputes" then
      -- The queue can contain evidence, controls and a full audit timeline;
      -- keep it inside its own scrollable content area instead of letting the
      -- TreeGroup clip the resolution actions below the fold.
      local requestPageRoot = tabs
      local requestChildrenBefore = #(requestPageRoot.children or {})
      local requestRenderComplete = false
      local function finishRequestRender(requestCount)
        if requestRenderComplete then return end
        requestRenderComplete = true
        uiDebug("ROUTE=requests RENDER_END PAGE_ROOT=" .. widgetIdentity(requestPageRoot)
          .. " CONTENT_HOST=" .. widgetIdentity(contentHost)
          .. " REQUEST_COUNT=" .. tostring(tonumber(requestCount) or 0)
          .. " SELECTED_REQUEST=" .. tostring(self.disputeSelectedId or "nil")
          .. " CHILD_COUNT_BEFORE=" .. tostring(requestChildrenBefore)
          .. " CHILD_COUNT_AFTER=" .. tostring(#(requestPageRoot.children or {})))
      end
      uiDebug("ROUTE=requests RENDER_BEGIN PAGE_ROOT=" .. widgetIdentity(requestPageRoot)
        .. " CONTENT_HOST=" .. widgetIdentity(contentHost)
        .. " REQUEST_COUNT=pending SELECTED_REQUEST=" .. tostring(self.disputeSelectedId or "nil")
        .. " CHILD_COUNT_BEFORE=" .. tostring(requestChildrenBefore))
      local tabs = Dibs.AceGUI.AddScrollableList(shell, tabs, 660) or tabs
      Dibs.AceGUI.AddHeader(shell, tabs, "Officer review requests", "Review player reports with the attached Dibs and RCLootCouncil evidence. Every resolution records an auditable reason.")
      local statusChoices = { [""] = "All statuses" }
      for key, value in pairs(Dibs.Disputes and Dibs.Disputes.GetStatuses and Dibs.Disputes.GetStatuses() or {}) do
        statusChoices[value] = value
      end
      self.disputeStatusFilter = self.disputeStatusFilter or ""
      self.disputeQuery = self.disputeQuery or ""
      local filterSection = Dibs.AceGUI.AddSection(shell, tabs, "Queue filters", "Filter by lifecycle status or search the player, item and report note.")
      local filter = Dibs.AceGUI.AddDropdown(shell, filterSection, "Status", statusChoices, function(value)
        self.disputeStatusFilter = value or ""
        self.disputePage = 1
        self:Refresh()
      end, 190)
      Dibs.AceGUI.SetValue(filter, self.disputeStatusFilter)
      self.disputeSearchBox = Dibs.AceGUI.AddEditBox(shell, filterSection, "Search", function(value)
        self.disputeQuery = value or ""
        self.disputePage = 1
        self:Refresh()
      end, 300)
      setControlText(self.disputeSearchBox, self.disputeQuery)
      Dibs.AceGUI.AddButton(shell, filterSection, "Clear", function()
        self.disputeQuery, self.disputeStatusFilter, self.disputeSelectedId = "", "", nil
        self:Refresh()
      end, 70)

      local requests, queueReason = {}, nil
      if Dibs.Disputes and Dibs.Disputes.ListForOfficer then
        requests, queueReason = Dibs.Disputes.ListForOfficer(nil, {
          status = self.disputeStatusFilter ~= "" and self.disputeStatusFilter or nil,
          query = self.disputeQuery,
        })
      end
      if queueReason then
        Dibs.AceGUI.AddLabel(shell, tabs, "Officer access required: " .. tostring(queueReason), true)
        finishRequestRender(0)
        return
      end
      uiDebug("ROUTE=requests REQUEST_COUNT=" .. tostring(#(requests or {})))
      local pageSize = 10
      local totalPages = math.max(1, math.ceil(#(requests or {}) / pageSize))
      self.disputePage = math.min(math.max(1, self.disputePage or 1), totalPages)
      local firstRequest = ((self.disputePage - 1) * pageSize) + 1
      local lastRequest = math.min(#(requests or {}), self.disputePage * pageSize)
      local requestRows = {}
      for index = firstRequest, lastRequest do
        local request = requests[index]
        local presentation = buildOfficerRequestRow(request)
        requestRows[#requestRows + 1] = {
          formatHistoryDate(request.createdAt or request.updatedAt),
          presentation.details.player,
          presentation.details.item,
          presentation.status.label,
          request = request,
        }
      end
      if #requestRows == 0 then requestRows[1] = { "", "No requests", "", "" } end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145, tooltip = "When the player submitted the request." },
        { title = "Player", width = 125, tooltip = "Character that submitted the request." },
        { title = "Item / Request", width = 220, tooltip = "Item or request being reviewed." },
        { title = "Status", width = 135, tooltip = "Current review status." },
      }, requestRows, 270, nil, {
        allowTableSort = false,
        onRowClick = function(row)
          if row and row.request then
            openRequestDetail(row.request)
          end
        end,
        contextMenu = function(row)
          if not row.request then return nil end
          return {
            { text = "Open request", callback = function() openRequestDetail(row.request) end },
            { text = "View player Dibs", callback = function()
              local playerName = requestPlayerPresentation(row.request)
              if Dibs.PlayerUI and Dibs.PlayerUI.Show then Dibs.PlayerUI.Show(playerName ~= "" and playerName or nil) end
            end },
            { text = "View player history", callback = function()
              local playerName = requestPlayerPresentation(row.request)
              if Dibs.Message then Dibs.Message("Player history: " .. tostring(playerName ~= "" and playerName or "Unavailable")) end
            end },
            { text = "Copy Name-Realm", callback = function()
              local playerName = requestPlayerPresentation(row.request)
              if Dibs.Message then Dibs.Message("Name-Realm: " .. tostring(playerName ~= "" and playerName or "Unavailable")) end
            end },
            { text = "Copy item link", callback = function()
              local evidence = row.request.evidence and row.request.evidence[1] or {}
              local item = evidence.item or evidence.itemID or row.request.itemName or row.request.itemID or "Unavailable"
              if Dibs.Message then Dibs.Message("Item: " .. tostring(item)) end
            end },
          }
        end,
      })
      local pageControls = Dibs.AceGUI.AddInlineGroup(shell, tabs)
      local previousPage = Dibs.AceGUI.AddButton(shell, pageControls, "Previous", function()
        self.disputePage = math.max(1, self.disputePage - 1)
        self:Refresh()
      end, 90)
      local pageLabel = Dibs.AceGUI.AddLabel(shell, pageControls, "Page " .. tostring(self.disputePage) .. "/" .. tostring(totalPages))
      local nextPage = Dibs.AceGUI.AddButton(shell, pageControls, "Next", function()
        self.disputePage = math.min(totalPages, self.disputePage + 1)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.SetDisabled(previousPage, self.disputePage <= 1)
      Dibs.AceGUI.SetDisabled(nextPage, self.disputePage >= totalPages)
      Dibs.AceGUI.AddTooltip(pageLabel, "Page", "Current review queue page.")
      if totalPages == 1 then
        setControlsVisible({ previousPage, pageLabel, nextPage }, false)
      end

      finishRequestRender(#(requests or {}))

      if false and self.disputeSelectedId then
        local selected = Dibs.Disputes.GetRequest(self.disputeSelectedId, nil)
        if selected then
          local evidence = selected.evidence and selected.evidence[1] or {}
          local summary = requestEvidencePresentation(selected, evidence)
          local detailSection = Dibs.AceGUI.AddSection(shell, tabs, "Request", "Review the request in plain language before opening advanced officer tools.")
          Dibs.AceGUI.AddPropertyTable(shell, detailSection, {
            { "Player", summary.player ~= "" and summary.player or "Missing player information" },
            { "Item / request", summary.item ~= "" and summary.item or "Missing item information" },
            { "Status", tostring(selected.status or "Open") },
            { "Issue", summary.issue ~= "" and summary.issue or "Other" },
            { "Note", summary.note ~= "" and summary.note or "No note provided" },
            { "Evidence", summary.evidence },
          }, 260)
          self.disputeTechnicalExpanded = self.disputeTechnicalExpanded == true
          Dibs.AceGUI.AddButton(shell, tabs, self.disputeTechnicalExpanded and "Hide technical details" or "Show technical details", function()
            self.disputeTechnicalExpanded = not self.disputeTechnicalExpanded
            self:Refresh()
          end, 190)
          if self.disputeTechnicalExpanded then
            local technicalSection = Dibs.AceGUI.AddSection(shell, tabs, "Technical details", "Diagnostic evidence is available when an Officer needs to investigate the request.")
            local unavailable = evidence.unavailableFields and table.concat(evidence.unavailableFields, ", ") or "none"
            Dibs.AceGUI.AddPropertyTable(shell, technicalSection, {
              { "Evidence source", tostring(evidence.source or "Unavailable") },
              { "Integration", tostring(evidence.integrationStatus or "Unavailable") },
              { "Integration reason", tostring(evidence.integrationReason or "Unavailable") },
              { "Transaction", tostring(evidence.transactionRef or "Unavailable") },
              { "Award/history reference", tostring(evidence.awardRef or evidence.historyRef or "Unavailable") },
              { "Unavailable fields", unavailable },
            }, 260)
          end

          local resolutionSection = Dibs.AceGUI.AddSection(shell, tabs, "Review actions", "Choose the normal next step. Advanced officer tools are separate.")
          self.disputeReason = self.disputeReason or ""
          local dangerousButtons = {}
          local updateDangerousButtons
          local reason = Dibs.AceGUI.AddEditBox(shell, resolutionSection, "Reason or question", function(value)
            self.disputeReason = value or ""
            if updateDangerousButtons then updateDangerousButtons() end
          end, 540)
          setControlText(reason, self.disputeReason)

          local function resolve(action, options)
            options = options or {}
            options.reason = self.disputeReason
            local result, resolveReason = Dibs.Disputes.Resolve(self.disputeSelectedId, action, options, nil)
            self.disputeStatusMessage = result and ("Request updated: " .. tostring(result.request and result.request.status or "done"))
              or ("Unable to update request: " .. tostring(resolveReason or "unknown error"))
            if result then
              self.disputeReason, self.disputeAmount = "", ""
              self.disputeCorrectPlayer, self.disputeCorrectItem = nil, nil
              self.disputeCorrectPlayerQuery, self.disputeCorrectItemQuery = "", ""
              self.disputeCorrectItemKey = nil
              self.disputeCorrectionFiltersInitialized = false
              self.disputeTargetRequestId = nil
              self.disputeConfirmed = false
            end
            self:Refresh()
          end

          local function protectedActionDecision(actionId)
            if not Dibs.Permissions or type(Dibs.Permissions.Evaluate) ~= "function" then return nil end
            local ok, decision = pcall(Dibs.Permissions.Evaluate, actionId, nil)
            return ok and decision or nil
          end
          local function protectedActionAllowed(actionId)
            local decision = protectedActionDecision(actionId)
            return decision and decision.allowed == true
          end
          local function hasTargetCorrectionSelection()
            return trimText(self.disputeCorrectPlayer) ~= ""
              or (self.disputeCorrectItemKey ~= nil and trimText(self.disputeCorrectItem) ~= "")
          end
          local terminal = selected.status == "Resolved" or selected.status == "Rejected"
          updateDangerousButtons = function()
            local authorized = trimText(self.disputeReason) ~= "" and self.disputeConfirmed == true and not terminal
            local adjustmentDecision = protectedActionDecision("ledger.adjust")
            local allowed = {
              authorized and protectedActionAllowed("ledger.adjust"),
              authorized and protectedActionAllowed("ledger.refund"),
              authorized and protectedActionAllowed("ledger.adjust"),
              authorized and protectedActionAllowed("ledger.adjust"),
              authorized and adjustmentDecision and adjustmentDecision.allowed and adjustmentDecision.role == "gm",
              authorized and hasTargetCorrectionSelection(),
            }
            for index, control in ipairs(dangerousButtons) do
              Dibs.AceGUI.SetDisabled(control, not allowed[index])
            end
          end
          local actionGroup = Dibs.AceGUI.AddInlineGroup(shell, resolutionSection)
          local reviewButton = Dibs.AceGUI.AddButton(shell, actionGroup, "Start review", function() resolve("under_review") end, 110)
          local questionButton = Dibs.AceGUI.AddButton(shell, actionGroup, "Ask for information", function() resolve("ask_information", { question = self.disputeReason }) end, 150)
          local noCorrection = Dibs.AceGUI.AddButton(shell, actionGroup, "Resolve: no correction", function() resolve("no_correction") end, 155)
          local duplicate = Dibs.AceGUI.AddButton(shell, actionGroup, "Mark duplicate", function() resolve("duplicate", { duplicateOf = self.disputeDuplicateId }) end, 110)
          local reject = Dibs.AceGUI.AddButton(shell, actionGroup, "Reject", function() resolve("reject") end, 80)
          local reopen = Dibs.AceGUI.AddButton(shell, actionGroup, "Reopen", function() resolve("reopen") end, 80)
          Dibs.AceGUI.SetDisabled(reviewButton, terminal)
          Dibs.AceGUI.SetDisabled(questionButton, terminal)
          Dibs.AceGUI.SetDisabled(noCorrection, terminal or trimText(self.disputeReason) == "")
          Dibs.AceGUI.SetDisabled(duplicate, terminal)
          Dibs.AceGUI.SetDisabled(reject, terminal or trimText(self.disputeReason) == "")
          Dibs.AceGUI.SetDisabled(reopen, not terminal)
          Dibs.AceGUI.AddLabel(shell, resolutionSection, self.disputeStatusMessage or "Choose an action. Advanced officer tools require authorization, a reason, and explicit confirmation.", true)

          self.disputeAdvancedExpanded = self.disputeAdvancedExpanded == true
          Dibs.AceGUI.AddButton(shell, tabs, self.disputeAdvancedExpanded and "Hide advanced officer tools" or "Show advanced officer tools", function()
            self.disputeAdvancedExpanded = not self.disputeAdvancedExpanded
            self:Refresh()
          end, 230)

          local targetButton
          local correction, refund, revoke, import, adjustment
          if self.disputeAdvancedExpanded then
            local advancedSection = Dibs.AceGUI.AddSection(shell, tabs, "Advanced officer tools", "Administrative corrections are separate from the normal review workflow.")
            self.disputeAmount = self.disputeAmount or ""
            local amount = Dibs.AceGUI.AddEditBox(shell, advancedSection, "Balance change", function(value) self.disputeAmount = value or "" end, 180)
            setControlText(amount, self.disputeAmount)
            self.disputeConfirmed = self.disputeConfirmed == true
            Dibs.AceGUI.AddCheckBox(shell, advancedSection, "I understand this changes recorded Dibs data", self.disputeConfirmed, function(value)
              self.disputeConfirmed = value == true
              if updateDangerousButtons then updateDangerousButtons() end
            end, 360)

            if selected.category == "wrong_item_player" then
              local targetSection = Dibs.AceGUI.AddSection(shell, advancedSection, "Correct item or player", "Use this only when the request target is wrong. The existing correction service keeps original evidence immutable.")
            Dibs.AceGUI.AddPropertyTable(shell, targetSection, {
              { "Current player", tostring(evidence.winner or selected.player and selected.player.name or "Unavailable") },
              { "Current item", tostring(evidence.item or evidence.itemID or "Unavailable") },
            }, 90)
            if self.disputeTargetRequestId ~= selected.requestId then
              self.disputeTargetRequestId = selected.requestId
              self.disputeCorrectPlayer, self.disputeCorrectItem = nil, nil
              self.disputeCorrectPlayerQuery, self.disputeCorrectItemQuery = "", ""
              self.disputeCorrectItemKey = nil
            end
            self.disputeCorrectPlayerQuery = self.disputeCorrectPlayerQuery or ""
            self.disputeCorrectItemQuery = self.disputeCorrectItemQuery or ""

            local playerGroup = Dibs.AceGUI.AddInlineGroup(shell, targetSection)
            local playerChoices, playerCount = buildGuildMemberChoices("", self.disputeCorrectPlayer)
            local correctedPlayerDropdown
            local correctedPlayerSearch = Dibs.AceGUI.AddEditBox(shell, playerGroup, "Search guild players", function(value)
              self.disputeCorrectPlayerQuery = value or ""
              local choices = buildGuildMemberChoices(self.disputeCorrectPlayerQuery, self.disputeCorrectPlayer)
              if self.disputeCorrectPlayer and choices[self.disputeCorrectPlayer] == nil then
                self.disputeCorrectPlayer = nil
              end
              if correctedPlayerDropdown and correctedPlayerDropdown.SetList then correctedPlayerDropdown:SetList(choices) end
              if correctedPlayerDropdown then
                if self.disputeCorrectPlayer then Dibs.AceGUI.SetValue(correctedPlayerDropdown, self.disputeCorrectPlayer)
                else Dibs.AceGUI.SetText(correctedPlayerDropdown, "Select a guild player...") end
              end
            end, 250)
            setControlText(correctedPlayerSearch, self.disputeCorrectPlayerQuery)
            correctedPlayerDropdown = Dibs.AceGUI.AddDropdown(shell, playerGroup, "Correct player", playerChoices, function(value)
              self.disputeCorrectPlayer = value and tostring(value) ~= "" and tostring(value) or nil
            end, 270)
            if correctedPlayerDropdown then
              if self.disputeCorrectPlayer and playerChoices[self.disputeCorrectPlayer] then
                Dibs.AceGUI.SetValue(correctedPlayerDropdown, self.disputeCorrectPlayer)
                Dibs.AceGUI.SetText(correctedPlayerDropdown, playerChoices[self.disputeCorrectPlayer])
              else
                self.disputeCorrectPlayer = nil
                Dibs.AceGUI.SetText(correctedPlayerDropdown, "Select a guild player...")
              end
            end
            if playerCount == 0 then
              Dibs.AceGUI.AddLabel(shell, targetSection, "No guild roster is available. Refresh the guild roster before correcting a player.", true)
              Dibs.AceGUI.AddButton(shell, targetSection, "Refresh guild roster", function()
                if type(_G.GuildRoster) == "function" then pcall(_G.GuildRoster) end
                self:Refresh()
              end, 150)
            end

            local itemCatalog, itemMeta = {}, {}
            if Dibs.EncounterJournal and type(Dibs.EncounterJournal.GetLootCatalog) == "function" then
              itemCatalog, itemMeta = Dibs.EncounterJournal.GetLootCatalog("", { limit = 3500 })
            end
                    local candidateContext = itemCandidateContext(selected, evidence)
            self.disputeItemCatalogByKey = {}
            for _, item in ipairs(itemCatalog or {}) do self.disputeItemCatalogByKey[tostring(item.key)] = item end

            self.disputeCorrectExpansionID = filterValue(self.disputeCorrectExpansionID)
            self.disputeCorrectSeasonID = filterValue(self.disputeCorrectSeasonID)
            self.disputeCorrectRaidID = filterValue(self.disputeCorrectRaidID)
            self.disputeCorrectBossID = filterValue(self.disputeCorrectBossID)
            local initialFilterRender = not self.disputeCorrectionFiltersInitialized
            local currentExpansion = getCurrentExpansionID()
            if initialFilterRender and self.disputeCorrectExpansionID == nil and currentExpansion ~= nil then
              self.disputeCorrectExpansionID = tostring(currentExpansion)
            end
            local function normalizeCorrectionFilters()
              local state = {
                expansionID = self.disputeCorrectExpansionID,
                seasonID = self.disputeCorrectSeasonID,
                raidID = self.disputeCorrectRaidID,
                bossID = self.disputeCorrectBossID,
              }
              local expansionChoices, seasonChoices, raidChoices, bossChoices, filterMeta
              for _ = 1, 4 do
                expansionChoices, seasonChoices, raidChoices, bossChoices, filterMeta = buildAdventureGuideFilterChoices(itemCatalog, state)
                local changed = false
                if not state.expansionID and state.seasonID then state.seasonID = nil; changed = true end
                if state.expansionID and not expansionChoices[state.expansionID] then state.expansionID = nil; changed = true end
                if state.seasonID and not seasonChoices[state.seasonID] then state.seasonID = nil; changed = true end
                if state.raidID and not raidChoices[state.raidID] then state.raidID = nil; changed = true end
                if state.bossID and not bossChoices[state.bossID] then state.bossID = nil; changed = true end
                if not changed then break end
              end
              self.disputeCorrectExpansionID = state.expansionID
              self.disputeCorrectSeasonID = state.seasonID
              self.disputeCorrectRaidID = state.raidID
              self.disputeCorrectBossID = state.bossID
              return expansionChoices, seasonChoices, raidChoices, bossChoices, filterMeta
            end
            local expansionChoices, seasonChoices, raidChoices, bossChoices, filterMeta = normalizeCorrectionFilters()
            if initialFilterRender and not self.disputeCorrectSeasonID and self.disputeCorrectExpansionID then
              local currentSeasonID = Dibs.EncounterJournal and Dibs.EncounterJournal.GetCurrentGameSeason
                and select(1, Dibs.EncounterJournal.GetCurrentGameSeason()) or nil
              if currentSeasonID and seasonChoices[tostring(currentSeasonID)] then
                self.disputeCorrectSeasonID = tostring(currentSeasonID)
                expansionChoices, seasonChoices, raidChoices, bossChoices, filterMeta = normalizeCorrectionFilters()
              end
            end
            self.disputeCorrectionFiltersInitialized = true
            local filterGroup = Dibs.AceGUI.AddInlineGroup(shell, targetSection)
            local function refreshCorrectionFilters()
              self:Refresh()
            end
            local expansionDropdown = Dibs.AceGUI.AddDropdown(shell, filterGroup, "Expansion", expansionChoices, function(value)
              self.disputeCorrectExpansionID = filterValue(value)
              refreshCorrectionFilters()
            end, 180)
            local seasonDropdown = Dibs.AceGUI.AddDropdown(shell, filterGroup, "Season", seasonChoices, function(value)
              self.disputeCorrectSeasonID = filterValue(value)
              refreshCorrectionFilters()
            end, 180)
            local raidDropdown = Dibs.AceGUI.AddDropdown(shell, filterGroup, "Raid", raidChoices, function(value)
              self.disputeCorrectRaidID = filterValue(value)
              refreshCorrectionFilters()
            end, 220)
            local bossDropdown = Dibs.AceGUI.AddDropdown(shell, filterGroup, "Boss", bossChoices, function(value)
              self.disputeCorrectBossID = filterValue(value)
              refreshCorrectionFilters()
            end, 220)
            Dibs.AceGUI.SetValue(expansionDropdown, self.disputeCorrectExpansionID or "")
            Dibs.AceGUI.SetValue(seasonDropdown, self.disputeCorrectSeasonID or "")
            Dibs.AceGUI.SetValue(raidDropdown, self.disputeCorrectRaidID or "")
            Dibs.AceGUI.SetValue(bossDropdown, self.disputeCorrectBossID or "")
            Dibs.AceGUI.SetDisabled(seasonDropdown, not self.disputeCorrectExpansionID or not filterMeta.hasSeasonMetadata)

            local itemGroup = Dibs.AceGUI.AddInlineGroup(shell, targetSection)
            local searchGroup = Dibs.AceGUI.AddInlineGroup(shell, targetSection)
            local correctedItemDropdown
            local itemSearchState
            local openLootRules = function()
              self:SelectTab("lootTypes")
            end
            local correctedItemSearch = Dibs.AceGUI.AddEditBox(shell, searchGroup, "Search Adventure Guide", function(value)
              self.disputeCorrectItemQuery = value or ""
              local searchContext = itemCandidateContext(selected, evidence)
              searchContext.expansionID = self.disputeCorrectExpansionID
              searchContext.seasonID = self.disputeCorrectSeasonID
              searchContext.raidID = self.disputeCorrectRaidID
              searchContext.bossID = self.disputeCorrectBossID
              local choices, _, filteredByRules = buildAdventureGuideItemChoices(itemCatalog, self.disputeCorrectItemQuery, self.disputeCorrectItemKey, 200, searchContext)
              if self.disputeCorrectItemKey and choices[self.disputeCorrectItemKey] == nil then
                self.disputeCorrectItemKey, self.disputeCorrectItem = nil, nil
              end
              if correctedItemDropdown and correctedItemDropdown.SetList then correctedItemDropdown:SetList(choices) end
              if correctedItemDropdown then
                if self.disputeCorrectItemKey then Dibs.AceGUI.SetValue(correctedItemDropdown, self.disputeCorrectItemKey)
                else Dibs.AceGUI.SetText(correctedItemDropdown, "Select an Adventure Guide item...") end
              end
              if itemSearchState then
                itemSearchState:SetText(filteredByRules and "No eligible items match the current Loot Rules." or (next(choices or {}) == nil and "No eligible raid items found." or ""))
              end
            end, 360)
            setControlText(correctedItemSearch, self.disputeCorrectItemQuery)
            local filteredContext = itemCandidateContext(selected, evidence)
            filteredContext.expansionID = self.disputeCorrectExpansionID
            filteredContext.seasonID = self.disputeCorrectSeasonID
            filteredContext.raidID = self.disputeCorrectRaidID
            filteredContext.bossID = self.disputeCorrectBossID
            local itemChoices, itemCount, filteredByRules = buildAdventureGuideItemChoices(itemCatalog, self.disputeCorrectItemQuery, self.disputeCorrectItemKey, 200, filteredContext)
            correctedItemDropdown = Dibs.AceGUI.AddDropdown(shell, itemGroup, "Correct item", itemChoices, function(value)
              local item = value and self.disputeItemCatalogByKey and self.disputeItemCatalogByKey[tostring(value)] or nil
              if item then
                self.disputeCorrectItemKey = tostring(item.key)
                self.disputeCorrectItem = item.itemLink or ("item:" .. tostring(item.itemID))
              else
                self.disputeCorrectItemKey, self.disputeCorrectItem = nil, nil
              end
            end, 430)
            if correctedItemDropdown then
              if self.disputeCorrectItemKey and itemChoices[self.disputeCorrectItemKey] then
                Dibs.AceGUI.SetValue(correctedItemDropdown, self.disputeCorrectItemKey)
                Dibs.AceGUI.SetText(correctedItemDropdown, itemChoices[self.disputeCorrectItemKey])
              else
                self.disputeCorrectItemKey, self.disputeCorrectItem = nil, nil
                Dibs.AceGUI.SetText(correctedItemDropdown, "Select an Adventure Guide item...")
              end
            end
            if not itemMeta.available then
              local reason = tostring(itemMeta.reason or "ADVENTURE_GUIDE_UNAVAILABLE")
              Dibs.AceGUI.AddLabel(shell, targetSection, "Adventure Guide items are unavailable (" .. reason .. "). Open the Adventure Guide once, then reopen this request.", true)
              Dibs.AceGUI.AddButton(shell, targetSection, "Refresh Adventure Guide items", function()
                if Dibs.EncounterJournal and type(Dibs.EncounterJournal.InvalidateLootCatalog) == "function" then
                  Dibs.EncounterJournal.InvalidateLootCatalog()
                end
                self:Refresh()
              end, 210)
            else
              itemSearchState = Dibs.AceGUI.AddLabel(shell, targetSection, filteredByRules
                and "No eligible items match the current Loot Rules."
                or (itemCount > 0
                and (tostring(itemCount) .. " eligible raid item candidates loaded. Search matches boss, item name, and ID.")
                or "No eligible raid items found."), true)
              if filteredByRules then Dibs.AceGUI.AddButton(shell, targetSection, "Open Loot Rules", openLootRules, 150) end
            end
            targetButton = Dibs.AceGUI.AddButton(shell, targetSection, "Apply target correction", function()
              if not hasTargetCorrectionSelection() then
                self.disputeStatusMessage = "Select a replacement player or item before applying the correction."
                self:Refresh()
                return
              end
              resolve("correct_target", {
                confirmed = self.disputeConfirmed,
                playerName = trimText(self.disputeCorrectPlayer) ~= "" and trimText(self.disputeCorrectPlayer) or nil,
                itemID = self.disputeCorrectItemKey and self.disputeItemCatalogByKey and self.disputeItemCatalogByKey[self.disputeCorrectItemKey] and self.disputeItemCatalogByKey[self.disputeCorrectItemKey].itemID or nil,
                itemLink = trimText(self.disputeCorrectItem) ~= "" and trimText(self.disputeCorrectItem) or nil,
              })
            end, 180)
            end

            local administrativeGroup = Dibs.AceGUI.AddSection(shell, advancedSection, "Administrative correction", "These actions write auditable corrections through the existing request service.")
            local adjustmentDecision = protectedActionDecision("ledger.adjust")
            correction = Dibs.AceGUI.AddButton(shell, administrativeGroup, "Adjust Dibs", function()
              local options = { confirmed = self.disputeConfirmed }
              local parsed = tonumber(trimText(self.disputeAmount))
              if parsed then options.amount = parsed end
              resolve("correct_balance", options)
            end, 120)
            import = Dibs.AceGUI.AddButton(shell, administrativeGroup, "Import historical", function()
              local options = { confirmed = self.disputeConfirmed }
              local parsed = tonumber(trimText(self.disputeAmount))
              if parsed then options.amount = parsed end
              resolve("historical_import", options)
            end, 125)
            if adjustmentDecision and adjustmentDecision.allowed and adjustmentDecision.role == "gm" then
              adjustment = Dibs.AceGUI.AddButton(shell, administrativeGroup, "Admin adjustment", function()
                local options = { confirmed = self.disputeConfirmed }
                local parsed = tonumber(trimText(self.disputeAmount))
                if parsed then options.amount = parsed end
                resolve("adjustment", options)
              end, 120)
            end

            local dibAccountingGroup = Dibs.AceGUI.AddSection(shell, advancedSection, "Dib accounting", "Use only when the evidence supports a balance correction.")
            refund = Dibs.AceGUI.AddButton(shell, dibAccountingGroup, "Refund Dib", function()
              local options = { confirmed = self.disputeConfirmed }
              local parsed = tonumber(trimText(self.disputeAmount))
              if parsed then options.amount = parsed end
              resolve("refund", options)
            end, 95)
            revoke = Dibs.AceGUI.AddButton(shell, dibAccountingGroup, "Revoke Dib", function()
              local options = { confirmed = self.disputeConfirmed }
              local parsed = tonumber(trimText(self.disputeAmount))
              if parsed then options.amount = parsed end
              resolve("revoke", options)
            end, 95)

            dangerousButtons = { correction, refund, revoke, import, adjustment, targetButton }
            updateDangerousButtons()
          end

          local timelineRows = {}
          for _, event in ipairs(Dibs.Disputes.GetTimeline(self.disputeSelectedId, nil) or {}) do
            timelineRows[#timelineRows + 1] = { tostring(event.timestamp or ""), tostring(event.action or ""), tostring(event.actorName or ""), tostring(event.reason or "") }
          end
          if #timelineRows > 0 then
            self.disputeHistoryExpanded = self.disputeHistoryExpanded == true
            Dibs.AceGUI.AddButton(shell, tabs, self.disputeHistoryExpanded and "Hide history (" .. tostring(#timelineRows) .. " events)" or "Show history (" .. tostring(#timelineRows) .. " events)", function()
              self.disputeHistoryExpanded = not self.disputeHistoryExpanded
              self:Refresh()
            end, 190)
            if self.disputeHistoryExpanded then
              Dibs.AceGUI.AddTable(shell, tabs, {
                { title = "Date", width = 130, tooltip = "Audit event time." },
                { title = "Actor", width = 140, tooltip = "Actor identity is officer-only." },
                { title = "Action", width = 150, tooltip = "Recorded action." },
                { title = "Reason", width = 300, tooltip = "Recorded justification." },
              }, timelineRows, 190)
            end
          end
        end
      end
      finishRequestRender(#(requests or {}))
      return
    end

    if self.activeTab == "history" or self.activeTab == "reconciliation" then
      local scroll = Dibs.AceGUI.AddScrollableList(shell, tabs, 660) or tabs
      Dibs.AceGUI.AddHeader(shell, scroll, "RCLootCouncil History", "Search read-only award evidence first. Confirmation and rejection use the existing protected reconciliation service.")
      local rcStatus = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or {}
      if not Dibs.RCLootCouncil or type(Dibs.RCLootCouncil.GetHistoryRows) ~= "function" then
        Dibs.AceGUI.AddLabel(shell, scroll, "History reconciliation is unavailable until RCLootCouncil exposes its read-only history.", true)
        return
      end
      local seasons = getSeasonList()
      local seasonChoices = {}
      for _, season in ipairs(seasons) do seasonChoices[season.id] = tostring(season.name or season.id) end
      self.reconSeasonId = self.reconSeasonId or currentId
      if not self.reconAliasesText then
        local savedAliases = Dibs.RCLootCouncil.GetReconciliationAliases(self.reconSeasonId) or {}
        self.reconAliasesText = #savedAliases > 0 and table.concat(savedAliases, ", ") or "DIB"
      end
      -- Historical DIB confirmation is deliberately one manual decision:
      -- the Officer adds an annotation and confirms the row as a DIB.
      self.reconMode = "manual"
      self.reconInferFinalStatus = self.reconInferFinalStatus ~= false
      self.reconLimit = self.reconLimit or "200"
      self.reconFromTime = self.reconFromTime or ""
      self.reconToTime = self.reconToTime or ""
      local form = Dibs.AceGUI.AddSection(shell, scroll, "Search History", "Use exact response labels. Matching trims whitespace and ignores case; it never performs fuzzy matching.")
      local seasonControl = Dibs.AceGUI.AddDropdown(shell, form, "Target season", seasonChoices, function(value)
        self.reconSeasonId = value
        local savedAliases = Dibs.RCLootCouncil.GetReconciliationAliases(value) or {}
        self.reconAliasesText = #savedAliases > 0 and table.concat(savedAliases, ", ") or "DIB"
      end, 240)
      if self.reconSeasonId then Dibs.AceGUI.SetValue(seasonControl, self.reconSeasonId) end
      local aliases = Dibs.AceGUI.AddEditBox(shell, form, "DIB response aliases (comma separated)", function(value) self.reconAliasesText = value or "" end, 500)
      setControlText(aliases, self.reconAliasesText)
      Dibs.AceGUI.AddCheckBox(shell, form, "Use recorded RC history when final status is missing", self.reconInferFinalStatus, function(value)
        self.reconInferFinalStatus = value == true
      end, 500)
      local limit = Dibs.AceGUI.AddEditBox(shell, form, "Maximum rows (1-500)", function(value) self.reconLimit = value or "200" end, 150)
      setControlText(limit, self.reconLimit)
      local fromTime = Dibs.AceGUI.AddEditBox(shell, form, "From timestamp (optional)", function(value) self.reconFromTime = value or "" end, 190)
      setControlText(fromTime, self.reconFromTime)
      local toTime = Dibs.AceGUI.AddEditBox(shell, form, "To timestamp (optional)", function(value) self.reconToTime = value or "" end, 190)
      setControlText(toTime, self.reconToTime)
      Dibs.AceGUI.AddButton(shell, form, "Save aliases", function()
        local saved, saveReason = Dibs.RCLootCouncil.SetReconciliationAliases(self.reconSeasonId, self.reconAliasesText, nil)
        self.reconStatus = saved and "Aliases saved." or ("Unable to save aliases: " .. tostring(saveReason or "unknown"))
        self:Refresh()
      end, 120)
      Dibs.AceGUI.AddButton(shell, form, "Search history (preview)", function()
        local search = Dibs.LogsUI and Dibs.LogsUI.SearchHistory and Dibs.LogsUI.SearchHistory({
          seasonId = self.reconSeasonId, aliases = self.reconAliasesText, mode = self.reconMode, limit = tonumber(self.reconLimit) or 200,
          fromTime = trimText(self.reconFromTime) ~= "" and tonumber(self.reconFromTime) or nil,
          toTime = trimText(self.reconToTime) ~= "" and tonumber(self.reconToTime) or nil,
          inferFinalStatus = self.reconInferFinalStatus,
        }) or { ok = false, reasonCode = "HISTORY_UNAVAILABLE" }
        local session = search.session
        self.reconSessionId = session and session.sessionId or nil
        self.reconStage = search.ok and "review" or "search"
        self.reconSelectedCandidate = nil
        self.reconReason = ""
        self.reconPage = 1
        self.reconStatus = search.ok and "History scan complete. No ledger or RCLootCouncil history was changed." or ("Unable to search history: " .. tostring(search.reasonCode or "unknown"))
        self:Refresh()
      end, 190)
      if rcStatus.availability ~= "operational" then
        local availability = Dibs.LogsUI and Dibs.LogsUI.GetReconciliationAvailability and Dibs.LogsUI.GetReconciliationAvailability() or {}
        Dibs.AceGUI.AddLabel(shell, scroll, tostring(availability.label or "Unavailable") .. ": " .. tostring(availability.explanation or "History reconciliation is unavailable."), true)
      end
      if self.reconStatus then Dibs.AceGUI.AddLabel(shell, scroll, self.reconStatus, true) end
      local session = self.reconSessionId and Dibs.RCLootCouncil.GetReconciliationSession(self.reconSessionId, nil) or nil
      if not session then return end
      local workflow = Dibs.LogsUI and Dibs.LogsUI.BuildReconciliationView and Dibs.LogsUI.BuildReconciliationView(session.sessionId) or {}
      local summary = workflow.summary or {}
      if workflow.stage == "complete" then
        Dibs.AceGUI.AddHeader(shell, scroll, "Reconciliation complete", "Every candidate in this bounded review has a recorded disposition.")
        Dibs.AceGUI.AddLabel(shell, scroll, "Confirmed as DIB: " .. tostring(summary.confirmed or 0) .. " | Rejected: " .. tostring(summary.rejected or 0) .. " | Unresolved: " .. tostring(summary.unresolved or 0), true)
      else
        Dibs.AceGUI.AddHeader(shell, scroll, "History scan complete", "Review candidates individually. Ambiguous or incomplete evidence cannot be confirmed as a DIB.")
        Dibs.AceGUI.AddLabel(shell, scroll, "Rows scanned: " .. tostring(summary.rowsScanned or 0) .. " | Possible Dibs: " .. tostring(summary.possibleDibs or 0) .. " | Ignored: " .. tostring(summary.ignored or 0) .. " | Ambiguous: " .. tostring(summary.ambiguous or 0), true)
      end
      Dibs.AceGUI.AddButton(shell, scroll, "Review Candidates", function()
        self.reconStage = "review"
        self:Refresh()
      end, 160)
      -- RCLootCouncil uses a virtualized scrolling table. Keep the Dibs
      -- preview equally light by rendering one bounded page of rows instead
      -- of constructing hundreds of AceGUI labels in a single refresh.
      local pageSize = 40
      local candidateCount = #(session.candidates or {})
      local pageCount = math.max(1, math.ceil(candidateCount / pageSize))
      self.reconPage = math.min(math.max(1, tonumber(self.reconPage) or 1), pageCount)
      local pageStart = candidateCount > 0 and ((self.reconPage - 1) * pageSize + 1) or 1
      local pageEnd = math.min(candidateCount, pageStart + pageSize - 1)
      local candidateRows = {}
      local projectedById = {}
      for _, projected in ipairs(workflow.candidates or {}) do projectedById[projected.candidateId] = projected end
      for index = pageStart, pageEnd do
        local candidate = session.candidates[index]
        local projected = projectedById[candidate.candidateId] or {}
        candidateRows[#candidateRows + 1] = {
          projected.date or formatHistoryDate(candidate.originalAwardTime, candidate.originalAwardTimeText),
          projected.status and projected.status.label or "Needs review", projected.winner or "Unknown",
          projected.item or "Unavailable", projected.difficulty or "Unavailable", projected.encounter or "Unavailable",
          projected.classification or "unsupported", projected.evidenceSummary or historyReviewLabel(candidate), "", candidate = candidate,
        }
      end
      if #candidateRows == 0 then candidateRows[1] = { "", "No history rows", "", "", "", "", "" } end
      Dibs.AceGUI.AddTable(shell, scroll, {
        { title = "Date / time", width = 180, tooltip = "Original RCLootCouncil award date and time." },
        { title = "Status", width = 100, tooltip = "Human-readable reconciliation state." },
        { title = "Winner", width = 120, tooltip = "Character recorded as the awarded player." },
        { title = "Item", width = 170, tooltip = "Read-only RCLootCouncil item evidence." },
        { title = "Difficulty", width = 95, tooltip = "Recorded raid difficulty." },
        { title = "Encounter", width = 150, tooltip = "Recorded instance and encounter." },
        { title = "Classification", width = 125, tooltip = "Reconciliation classification." },
        { title = "Evidence", width = 180, tooltip = "Concise evidence result; technical details are secondary." },
        { title = "Review", width = 90, tooltip = "Open candidate details." },
      }, candidateRows, 250, function(row)
        if not row.candidate then return nil end
        return { text = "Review", callback = function()
          self.reconSelectedCandidate = row.candidate.candidateId
          self.transferTechnicalExpanded = false
          openHistoryTransfer(session, row.candidate)
        end }
      end, {
        allowTableSort = false,
        contextMenu = function(row)
          if not row or not row.candidate then return nil end
          local candidate = row.candidate
          local entries = {
            { text = "Review transfer", callback = function()
              self.transferTechnicalExpanded = false
              openHistoryTransfer(session, candidate)
            end },
            { text = "Show technical evidence", callback = function()
              self.transferTechnicalExpanded = true
              openHistoryTransfer(session, candidate)
            end },
          }
          if Dibs.EncounterJournal and type(Dibs.EncounterJournal.OpenLootItem) == "function" then
            entries[#entries + 1] = { text = "Open Adventure Guide", callback = function() Dibs.EncounterJournal.OpenLootItem(candidate) end }
          end
          return entries
        end,
      })
      local pageControls = Dibs.AceGUI.AddInlineGroup(shell, scroll)
      local previousPage = Dibs.AceGUI.AddButton(shell, pageControls, "Previous", function()
        self.reconPage = math.max(1, self.reconPage - 1)
        self:Refresh()
      end, 90)
      local pageLabel = Dibs.AceGUI.AddLabel(shell, pageControls,
        candidateCount > 0 and ("Rows " .. tostring(pageStart) .. "-" .. tostring(pageEnd) .. " of " .. tostring(candidateCount) .. " | Page " .. tostring(self.reconPage) .. "/" .. tostring(pageCount)) or "No history rows")
      local nextPage = Dibs.AceGUI.AddButton(shell, pageControls, "Next", function()
        self.reconPage = math.min(pageCount, self.reconPage + 1)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.SetDisabled(previousPage, self.reconPage <= 1)
      Dibs.AceGUI.SetDisabled(nextPage, self.reconPage >= pageCount)
      if pageCount == 1 then
        setControlsVisible({ previousPage, pageLabel, nextPage }, false)
      end
      return
    end

    if self.activeTab == "announcements" then
      local templates = Dibs.PreDibs.GetAnnouncementTemplates()
      local announcementSettings = Dibs.PreDibs.GetAnnouncementSettings()
      local updatePreview = function()
        if self.announcementPreview then
          local sample = {
            playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or "Player-Realm",
            itemName = "Example item",
            itemID = 12345,
            difficulty = "Mythic",
            modeAtCreation = "WILD_OPEN",
            status = "confirmed",
            seasonId = currentId or "Current season",
            requestId = "example-request",
            source = "Officer UI preview",
          }
          local preDib = Dibs.PreDibs.FormatAnnouncement(getControlText(self.preDibTemplateInput), sample)
          local reminder = Dibs.PreDibs.FormatAnnouncement(getControlText(self.reminderTemplateInput), { source = "Raid reminder" })
          self.announcementPreview:SetText("Pre-Dib: " .. preDib .. "\nReminder: " .. reminder)
        end
      end
      Dibs.AceGUI.AddLabel(shell, tabs, "Announcement templates and facts", true)
      Dibs.AceGUI.AddLabel(shell, tabs, "Variables: %player %item %itemID %difficulty %mode %status %season %date %time %requestID %source %channel", true)
      self.preDibTemplateInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Pre-Dib announcement", function(value)
        local currentTemplates = Dibs.PreDibs.GetAnnouncementTemplates()
        Dibs.PreDibs.SetAnnouncementTemplates(value, currentTemplates.reminder)
        updatePreview()
      end, 520)
      setControlText(self.preDibTemplateInput, templates.preDib)
      self.reminderTemplateInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Raid reminder", function(value)
        local currentTemplates = Dibs.PreDibs.GetAnnouncementTemplates()
        Dibs.PreDibs.SetAnnouncementTemplates(currentTemplates.preDib, value)
        updatePreview()
      end, 520)
      setControlText(self.reminderTemplateInput, templates.reminder)
      self.publicAnnouncementChannel = Dibs.AceGUI.AddDropdown(shell, tabs, "Public pre-dib announce channel", ANNOUNCEMENT_CHANNEL_VALUES, function(value)
        local announcementState = Dibs.PreDibs.GetAnnouncementSettings()
        Dibs.PreDibs.SetAnnouncementChannels(value, announcementState.officerChannel)
      end, 180)
      Dibs.AceGUI.SetValue(self.publicAnnouncementChannel, announcementSettings.publicChannel)
      self.officerAnnouncementChannel = Dibs.AceGUI.AddDropdown(shell, tabs, "Officer pre-dib announce channel", ANNOUNCEMENT_CHANNEL_VALUES, function(value)
        local announcementState = Dibs.PreDibs.GetAnnouncementSettings()
        Dibs.PreDibs.SetAnnouncementChannels(announcementState.publicChannel, value)
      end, 180)
      Dibs.AceGUI.SetValue(self.officerAnnouncementChannel, announcementSettings.officerChannel)
      Dibs.AceGUI.AddButton(shell, tabs, "Test public channel", function()
        local settings = Dibs.PreDibs.GetAnnouncementSettings()
        local ok, reason = Dibs.PreDibs.SendTestAnnouncement(settings.publicChannel, "Public")
        Dibs.Message(ok and "Public announcement test sent." or ((reason == "RAID_DIBS_NOT_JOINED" or reason == "RAID_DIBS_UNAVAILABLE") and "Raid Dibs is not joined on this character." or ("Public announcement channel is unavailable (" .. tostring(reason) .. ").")))
      end, 150)
      Dibs.AceGUI.AddButton(shell, tabs, "Test officer channel", function()
        local settings = Dibs.PreDibs.GetAnnouncementSettings()
        local ok, reason = Dibs.PreDibs.SendTestAnnouncement(settings.officerChannel, "Officer")
        Dibs.Message(ok and "Officer announcement test sent." or ((reason == "RAID_DIBS_NOT_JOINED" or reason == "RAID_DIBS_UNAVAILABLE") and "Raid Dibs is not joined on this character." or ("Officer announcement channel is unavailable (" .. tostring(reason) .. ").")))
      end, 150)
      Dibs.AceGUI.AddButton(shell, tabs, "Reset templates", function()
        Dibs.PreDibs.SetAnnouncementTemplates(DEFAULT_PREDIB_TEMPLATE, DEFAULT_REMINDER_TEMPLATE)
        self:Refresh()
      end, 120)
      self.announcementPreview = Dibs.AceGUI.AddLabel(shell, tabs, "", true)
      updatePreview()
      return
    end

    if self.activeTab == "lootTypes" then
      local options = Dibs.RCOptions.GetLootTypeOptions()
      local policy = options and options.types
      local columns = Dibs.AceGUI.AddInlineGroup(shell, tabs)
      local buttonsColumn = Dibs.AceGUI.AddSection(shell, columns, "Loot type buttons", "Enable the Dibs button in RCLootCouncil and/or allow the category in the Adventure Guide.")
      if buttonsColumn and buttonsColumn.SetWidth then buttonsColumn:SetWidth(520) end

      local projection = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetConfigProjectionStatus
        and Dibs.RCLootCouncil.GetConfigProjectionStatus() or { addonFound = false, additional = {} }
      if projection.addonFound ~= true then
        Dibs.AceGUI.AddLabel(shell, buttonsColumn, "RCLootCouncil is not loaded. Dibs remains available in Standalone mode.", true)
      else
        Dibs.AceGUI.AddLabel(shell, buttonsColumn,
          "When RC is enabled, the template below creates or updates the Dibs button for that loot type.", true)
        local default = projection.default
        Dibs.AceGUI.AddLabel(shell, buttonsColumn,
          "Default response set: " .. ((default and default.buttonDibIndex and default.responseDibIndex) and "Dibs ready" or "Waiting for RCLootCouncil"), true)
      end

      self.lootTypeControls = {}
      self.rcLootTypeControls = {}
      local values = policy and policy.values and policy.values() or {}
      local semanticKeys = {
        default = true, MOUNTS = true, PETS = true, TOKEN = true, TOKEN_SET = true,
        RECIPE = true, DECOR = true, OTHER = true, COSMETIC = true,
      }
      local displayLabels = {
        default = "Default", MOUNTS = "Mounts", PETS = "Pets", TOKEN = "Curio Tokens",
        TOKEN_SET = "Tier Set Tokens", RECIPE = "Recipes", DECOR = "Decor",
        OTHER = "Other Loot", COSMETIC = "Cosmetic Items",
      }
      local keys = {}
      for key in pairs(values) do
        if semanticKeys[key] then keys[#keys + 1] = key end
      end
      table.sort(keys, function(a, b) return tostring(displayLabels[a] or values[a]) < tostring(displayLabels[b] or values[b]) end)
      local header = Dibs.AceGUI.AddInlineGroup(shell, buttonsColumn)
      Dibs.AceGUI.AddLabel(shell, header, "Loot type", false)
      Dibs.AceGUI.AddLabel(shell, header, "Enable Button RC", false)
      Dibs.AceGUI.AddLabel(shell, header, "Enable Button Adventure Guide", false)
      for _, key in ipairs(keys) do
        local row = Dibs.AceGUI.AddInlineGroup(shell, buttonsColumn)
        Dibs.AceGUI.AddLabel(shell, row, tostring(displayLabels[key] or values[key]), false)
        local rcCheckbox = Dibs.AceGUI.AddCheckBox(shell, row, "", Dibs.RCLootCouncil.IsRCButtonEnabledForType(key), function(value)
          local ok, reason = Dibs.RCLootCouncil.SetRCButtonEnabledForType(key, value == true)
          if not ok then self:SetStatus("Unable to change RC button: " .. tostring(reason)); return end
          Dibs.RCLootCouncil.RefreshConfigProjection()
          self:Refresh()
        end, 120)
        local guideCheckbox = Dibs.AceGUI.AddCheckBox(shell, row, "", policy.get(nil, key), function(value)
          policy.set(nil, key, value == true)
          Dibs.RCLootCouncil.RefreshConfigProjection()
          self:Refresh()
        end, 180)
        self.rcLootTypeControls[key] = rcCheckbox
        self.lootTypeControls[key] = guideCheckbox
      end
      -- Keep technical RC slot controls available to older callers without
      -- putting those implementation details back into the primary grid.
      for key in pairs(values) do
        if not semanticKeys[key] and type(key) == "string" then
          local hiddenControl = Dibs.AceGUI.AddCheckBox(shell, buttonsColumn, "", policy.get(nil, key), function(value)
            policy.set(nil, key, value == true)
            Dibs.RCLootCouncil.RefreshConfigProjection()
          end, 1)
          if hiddenControl and hiddenControl.SetHidden then hiddenControl:SetHidden(true) end
          self.lootTypeControls[key] = hiddenControl
        end
      end
      -- Keep the old callback shape for integrations and tests without adding
      -- the old bulk-action buttons back to the user-facing page.
      self.enableLootTypes = { callbacks = { OnClick = function()
        options.enable.func()
        self:Refresh()
      end } }
      self.defaultLootTypes = { callbacks = { OnClick = function()
        options.disable.func()
        self:Refresh()
      end } }
      return
    end
    if self.activeTab == "debug" then
      self.debugControls = {}
      Dibs.AceGUI.AddHeading(shell, tabs, "Debug", "Adjust module verbosity and open diagnostic logs.")
      local verbosity = Dibs.AceGUI.AddSection(shell, tabs, "Module verbosity", "0 disables diagnostics, 1 is normal, and 5 is maximum diagnostics.")
      for _, entry in ipairs({ { "All", "all" }, { "Announcements", "announce" }, { "Sync", "sync" }, { "UI", "ui" }, { "Adventure Guide", "encounter_journal" } }) do
        local key, label = entry[2], entry[1]
        local debugLevel = tonumber(Dibs.GetDebugLevels()[key]) or tonumber(Dibs.GetDebugLevels().all) or 1
        local control = Dibs.AceGUI.AddDropdown(shell, verbosity, label .. " level", { [0]="0 - disabled", [1]="1 - normal", [2]="2", [3]="3", [4]="4", [5]="5 - maximum" }, function(value)
          Dibs.SetDebugLevel(key, tonumber(value) or 0); self:Refresh()
        end, 220)
        Dibs.AceGUI.SetValue(control, debugLevel)
        self.debugControls[key] = control
      end
      local logs = Dibs.AceGUI.AddSection(shell, tabs, "Logs", "Open the separate diagnostic log window when detailed events are needed.")
      self.debugLogsButton = Dibs.AceGUI.AddButton(shell, logs, "Open debug logs", function()
        if Dibs.DebugLogs and Dibs.DebugLogs.Open then
          local opened, reason = Dibs.DebugLogs.Open(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
          if not opened then self:SetStatus("Unable to open debug logs: " .. tostring(reason or "UI_UNAVAILABLE")) end
        end
      end, 160)
      self.debugReportExpanded = self.debugReportExpanded == true
      self.debugReportButton = Dibs.AceGUI.AddButton(shell, tabs, self.debugReportExpanded and "Hide debug report" or "Show debug report", function()
        self.debugReportExpanded = not self.debugReportExpanded
        self:Refresh()
      end, 170)
      if self.debugReportExpanded then
        local report = Dibs.AceGUI.AddSection(shell, tabs, "Diagnostic report", "Technical runtime details are available on demand.")
        Dibs.AceGUI.AddSelectableText(shell, report, "Report", Dibs.BuildDebugReport and Dibs.BuildDebugReport() or "Diagnostics unavailable.", 820, 220)
        Dibs.AceGUI.AddButton(shell, report, "Copy report to chat", function() Dibs.Message(Dibs.BuildDebugReport()) end, 180)
      end
      local catalogDiagnostics = Dibs.EncounterJournal and Dibs.EncounterJournal.GetLootCatalogDiagnostics
        and Dibs.EncounterJournal.GetLootCatalogDiagnostics() or {}
      Dibs.AceGUI.AddPropertyTable(shell, tabs, {
        { "Adventure Guide expansions", tostring(catalogDiagnostics.expansionCount or 0) },
        { "Adventure Guide game seasons", tostring(catalogDiagnostics.seasonCount or 0) },
        { "Adventure Guide raids", tostring(catalogDiagnostics.raidCount or 0) },
        { "Adventure Guide encounters", tostring(catalogDiagnostics.encounterCount or 0) },
        { "Adventure Guide items", tostring(catalogDiagnostics.eligibleItemCount or 0) },
        { "Current expansion", tostring(catalogDiagnostics.currentExpansionID or "unresolved") .. " / " .. tostring(catalogDiagnostics.currentExpansionName or "unresolved") },
        { "Current game season", tostring(catalogDiagnostics.currentGameSeasonID or "unresolved") .. " / " .. tostring(catalogDiagnostics.currentGameSeasonName or "unresolved") },
        { "Selected expansion", tostring(self.disputeCorrectExpansionID or "All expansions") },
        { "Selected game season", tostring(self.disputeCorrectSeasonID or "All seasons") },
      }, 300)
      return
    end

    if self.activeTab == "settings" then
      local seasonValues = {}
      for _, season in ipairs(seasons) do seasonValues[season.id] = season.name end
      self.seasonDropdown = Dibs.AceGUI.AddDropdown(shell, tabs, "Selected season", seasonValues, function(value)
        self.selectedSeasonId, self.inputBoundSeasonId = value, nil
        self:Refresh()
      end, 240)
      Dibs.AceGUI.SetValue(self.seasonDropdown, currentId)
      Dibs.AceGUI.AddButton(shell, tabs, "Previous", function() selectSeason(-1) end, 80)
      Dibs.AceGUI.AddButton(shell, tabs, "Next", function() selectSeason(1) end, 60)
      Dibs.AceGUI.AddButton(shell, tabs, "Activate", function()
        local selected = getSelectedSeason(self)
        local result = selected and Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = selected.id })
        self:SetStatus(result and result.ok and ("Active season: " .. selected.name) or (result and result.diagnostic) or "No season selected.")
        self:Refresh()
      end, 80)
      self.seasonLabel = Dibs.AceGUI.AddLabel(shell, tabs, "Season: " .. tostring(current and current.name or "None"), true)
      self.seasonNameInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Season name", nil, 260)
      setControlText(self.seasonNameInput, current and current.name or getDefaultSeasonName())
      Dibs.AceGUI.AddButton(shell, tabs, "Create", function()
        local name = makeUniqueSeasonName(trimText(getControlText(self.seasonNameInput)))
        local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name })
        if result.ok and result.value then self.selectedSeasonId = result.value.id end
        self:SetStatus(result.ok and ("Created season: " .. tostring(result.value.name)) or result.diagnostic)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.AddButton(shell, tabs, "Rename", function()
        local typed = trimText(getControlText(self.seasonNameInput))
        local duplicate = current and findSeasonByName(typed, current.id)
         local result = current and typed ~= "" and not duplicate and Dibs.ProtectedActions.Execute("season.rename", nil, { seasonId = current.id, name = typed })
         self:SetStatus(result and result.ok and result.value and ("Season renamed: " .. result.value.name) or (result and result.diagnostic) or "Unable to rename the selected season.")
        self:Refresh()
      end, 70)
      Dibs.AceGUI.AddButton(shell, tabs, "Delete", function()
         local result = current and #seasons > 1 and Dibs.ProtectedActions.Execute("season.archive", nil, { seasonId = current.id })
         if result and result.ok then self.selectedSeasonId = nil end
         self:SetStatus(result and result.ok and result.value and ("Season archived: " .. result.value.name) or (result and result.diagnostic) or "At least one season must remain.")
        self:Refresh()
      end, 70)
      self.summaryText = Dibs.AceGUI.AddLabel(shell, tabs, Dibs.OfficerUI.BuildStatusText(current), true)
      self.statusText = Dibs.AceGUI.AddLabel(shell, tabs, self.statusMessage or "Ready", true)
      Dibs.AceGUI.AddLabel(shell, tabs, "Rank allocations", true)
      local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason and Dibs.RankRules.GetRulesForSeason(currentId) or {}
      for index = 1, self.rankRowCount do
        local source = self.rankDrafts[index] or rules[index] or { rankIndex = index - 1, allocation = 1 }
        local row = { rankIndex = tonumber(source.rankIndex) or 0, allocation = tonumber(source.allocation) or 0 }
        self.rankDrafts[index] = row
        table.insert(self.rankRows, row)
        local ranks = {}
        for rank = 0, math.max(9, row.rankIndex) do ranks[rank] = buildRankLabel(rank) end
        row.rankDropdown = Dibs.AceGUI.AddDropdown(shell, tabs, "Rank", ranks, function(value) row.rankIndex = tonumber(value) or 0 end, 210)
        Dibs.AceGUI.SetValue(row.rankDropdown, row.rankIndex)
        row.valueText = Dibs.AceGUI.AddLabel(shell, tabs, "Dibs: " .. tostring(row.allocation))
        Dibs.AceGUI.AddButton(shell, tabs, "-", function() row.allocation = math.max(0, row.allocation - 1); self.rankDrafts[index] = row; self:Refresh() end, 28)
        Dibs.AceGUI.AddButton(shell, tabs, "+", function() row.allocation = row.allocation + 1; self.rankDrafts[index] = row; self:Refresh() end, 28)
        Dibs.AceGUI.AddButton(shell, tabs, "Set", function() applyRankRule(self, row) end, 50)
      end
      Dibs.AceGUI.AddButton(shell, tabs, "Add rank", function() self.rankRowCount = self.rankRowCount + 1; self:Refresh() end, 80)
      return
    end

    if self.activeTab == "dashboard" then
      self.ledgerTitle = Dibs.AceGUI.AddLabel(shell, tabs, "Dashboard", true)
      self.ledgerText = Dibs.AceGUI.AddLabel(shell, tabs, table.concat(Dibs.OfficerUI.BuildDashboardDetails(current), "\n"), true)
      return
    end
    if self.activeTab == "pendingAwards" then
      local proposals = Dibs.OfficerUI.GetPendingAwardProposals()
      Dibs.AceGUI.AddHeading(shell, tabs, (Dibs.L and Dibs.L.PENDING_AWARDS_TITLE) or "Pending awards", (Dibs.L and Dibs.L.PENDING_AWARDS_DESCRIPTION) or "Confirm awards received from another raid before they consume Dibs.")
      if #proposals == 0 then
        Dibs.AceGUI.AddLabel(shell, tabs, (Dibs.L and Dibs.L.PENDING_AWARDS_EMPTY) or "No awards are awaiting coordinator confirmation.", true)
      end
      for _, proposal in ipairs(proposals) do
        local detail = tostring(proposal.playerName) .. " | " .. tostring(proposal.itemLink or proposal.itemID or "item") .. " | " .. tostring(proposal.awardRef or "award")
        Dibs.AceGUI.AddLabel(shell, tabs, detail, true)
        Dibs.AceGUI.AddButton(shell, tabs, (Dibs.L and Dibs.L.PENDING_AWARDS_CONFIRM) or "Confirm", function()
          local result = Dibs.OfficerUI.ConfirmPendingAwardProposal(proposal.proposalId)
          self:SetStatus(result.accepted and ((Dibs.L and Dibs.L.PENDING_AWARDS_CONFIRMED) or "Award confirmed.") or tostring(result.reasonCode or "Unable to confirm award."))
          self:Refresh()
        end, 100)
      end
      return
    end
    if self.activeTab == "statistics" then
      local statistics = Dibs.OfficerUI.BuildSeasonStatistics(currentId)
      self.ledgerTitle = Dibs.AceGUI.AddLabel(shell, tabs, "Season statistics", true)
      self.ledgerText = Dibs.AceGUI.AddLabel(shell, tabs, "Active players: " .. statistics.players .. "\nTransactions: " .. statistics.transactions .. "\nDibs used: " .. statistics.used .. "\nActive pre-Dibs: " .. statistics.activePreDibs, true)
      return
    end
    self.searchBox = Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value)
      self.ledgerQuery, self.ledgerPage = value, 1
      self:Refresh()
    end, 220)
    setControlText(self.searchBox, self.ledgerQuery or "")
    Dibs.AceGUI.AddButton(shell, tabs, "Clear", function() self.ledgerQuery, self.ledgerPage = "", 1; self:Refresh() end, 60)
    local view = Dibs.OfficerUI.GetPagedView(self.activeTab == "history" and "actions" or self.activeTab, currentId, self.ledgerPage, 8, self.ledgerQuery, self.vaultStatusFilter)
    self.ledgerPage = view.page
    self.ledgerTitle = Dibs.AceGUI.AddLabel(shell, tabs, view.title .. " (" .. view.totalCount .. ")", true)
    local headerText, headerTooltip
    if self.activeTab == "history" or self.activeTab == "actions" then
      headerText = "Date | Player | Action | Amount | Reason"
      headerTooltip = "Date: when the ledger entry was recorded. Player: who it affected. Action: the ledger operation. Amount: Dibs gained or spent. Reason: audit context."
    elseif self.activeTab == "automaticDibs" then
      headerText = "Date | Player | Rank | Expected | Assigned | Action | Reason"
      headerTooltip = "Date: assignment time. Player: guild member. Rank: rank used for the rule. Expected: Dibs expected for the rank. Assigned: Dibs delta. Action: Auto, roster reconciliation, or GM/Officer adjustment. Reason: audit context."
    elseif self.activeTab == "predibs" then
      headerText = "Date | Player | Status | Item | Difficulty | Mode | Sync"
      headerTooltip = "Date: request time. Player: requester. Status: lifecycle state. Item: reserved loot. Difficulty: requested difficulty. Mode: Wild Open or Encounter. Sync: delivery acknowledgement."
    elseif self.activeTab == "vault" then
      headerText = "Date | Player | Status | Item | Source | Reset | Sync | Review"
      headerTooltip = "Date: acquisition time. Player: guild member. Status: verification state. Item: acquired item. Source: detection source. Reset: weekly context. Sync: guild state. Review: recorded Officer reason."
    else
      headerText = "Player | Balance | Actions"
      headerTooltip = "Player: guild member. Balance: current Dibs allocation after ledger activity. Actions: number of ledger entries."
    end
    local expectedColumns = (self.activeTab == "history" or self.activeTab == "actions") and 5 or (self.activeTab == "automaticDibs" and 7 or (self.activeTab == "predibs" and 7 or (self.activeTab == "vault" and 8 or 3)))
    local tableRows = {}
    if self.activeTab == "predibs" then
      local preDibRows = Dibs.OfficerUI.BuildRequestView("officer", { kind = "predibs", limit = 50 })
      for index, row in ipairs(preDibRows) do
        local line = view.lines[index] or ""
        local values = splitPipeLine(line, expectedColumns)
        values[3] = row.status.label
        values[4] = row.details.item ~= "" and row.details.item or values[4]
        values[5] = row.details.difficulty ~= "" and row.details.difficulty or values[5]
        values[6] = row.details.mode ~= "" and row.details.mode or values[6]
        values[7] = row.details.delivery ~= "" and row.details.delivery or row.explanation
        table.insert(tableRows, values)
      end
    elseif self.activeTab == "automaticDibs" then
      for _, row in ipairs(view.rows or {}) do
        table.insert(tableRows, {
          row.dateText or "",
          row.playerName or row.plainPlayerName or "",
          row.rankName or "Unknown",
          tostring(row.expected or 0),
          (tonumber(row.amount) or 0) >= 0 and ("+" .. tostring(row.amount or 0)) or tostring(row.amount or 0),
          row.action or "Auto",
          row.reason or "",
        })
      end
    else
      for _, line in ipairs(view.lines) do table.insert(tableRows, splitPipeLine(line, expectedColumns)) end
    end
    local columns = {}
    if expectedColumns == 7 and self.activeTab == "automaticDibs" then
      columns = {
        { title = "Date", width = 90, minWidth = 58, priority = 2, tooltip = "When the automatic assignment was recorded." },
        { title = "Player", width = 150, minWidth = 112, priority = 5, tooltip = "Guild member affected by the assignment." },
        { title = "Rank", width = 110, minWidth = 78, priority = 4, tooltip = "Guild rank used to calculate the assignment." },
        { title = "Expected", width = 72, minWidth = 62, priority = 1, tooltip = "Dibs expected for the current guild rank." },
        { title = "Assigned", width = 72, minWidth = 62, priority = 1, tooltip = "Dibs added or removed by this entry." },
        { title = "Action", width = 105, minWidth = 88, priority = 3, tooltip = "Automatic, roster reconciliation, or GM/Officer adjustment." },
        { title = "Reason", width = 190, minWidth = 120, priority = 6, tooltip = "Assignment or adjustment audit context." },
      }
    elseif expectedColumns == 5 then
      columns = {
        { title = "Date", width = 145, tooltip = "When the ledger entry was recorded." },
        { title = "Player", width = 135, tooltip = "Guild member affected by the entry." },
        { title = "Action", width = 135, tooltip = "Ledger operation." },
        { title = "Amount", width = 70, tooltip = "Dibs gained or spent." },
        { title = "Reason", width = 220, tooltip = "Audit context." },
      }
    elseif expectedColumns == 8 then
      columns = {
        { title = "Date", width = 135, tooltip = "Acquisition time." },
        { title = "Player", width = 130, tooltip = "Guild member." },
        { title = "Status", width = 150, tooltip = "Verification state." },
        { title = "Item", width = 170, tooltip = "Acquired item." },
        { title = "Source", width = 130, tooltip = "Detection source." },
        { title = "Reset", width = 110, tooltip = "Weekly reset context." },
        { title = "Sync", width = 90, tooltip = "Guild synchronization state." },
        { title = "Review", width = 220, tooltip = "Officer review reason." },
      }
    elseif expectedColumns == 7 then
      columns = {
        { title = "Date", width = 135, tooltip = "Request creation time." },
        { title = "Player", width = 130, tooltip = "Player who requested the item." },
        { title = "Status", width = 80, tooltip = "Current request lifecycle status." },
        { title = "Item", width = 180, tooltip = "Reserved item." },
        { title = "Difficulty", width = 80, tooltip = "Normal, Heroic, or Mythic." },
        { title = "Mode", width = 100, tooltip = "Wild Open or Encounter." },
        { title = "Sync", width = 100, tooltip = "Officer delivery acknowledgement." },
      }
    else
      columns = {
        { title = "Player", width = 220, tooltip = "Guild member." },
        { title = "Balance", width = 100, tooltip = "Current Dibs balance." },
        { title = "Actions", width = 100, tooltip = "Number of ledger entries." },
      }
    end
    if self.activeTab == "vault" then
      local vaultRows = Dibs.OfficerUI.BuildVaultAcquisitionReview({ seasonId = currentId, query = self.ledgerQuery, verificationState = self.vaultStatusFilter }).rows
      local acquisitionValues, decisionValues = {}, { CONFIRM = "Confirm", REJECT = "Reject", REFERENCE = "Keep as reference" }
      for _, row in ipairs(vaultRows) do acquisitionValues[row.acquisitionId] = row.playerName .. " | " .. tostring(row.projection.verificationState or "UNVERIFIED") .. " | " .. tostring(row.projection.itemID) end
      self.vaultAcquisition = Dibs.AceGUI.AddDropdown(shell, tabs, "Record", acquisitionValues, function(value) self.vaultAcquisitionId = value end, 360)
      self.vaultDecision = Dibs.AceGUI.AddDropdown(shell, tabs, "Decision", decisionValues, function(value) self.vaultDecisionValue = value end, 180)
      self.vaultReason = Dibs.AceGUI.AddEditBox(shell, tabs, "Reason", function(value) self.vaultReasonValue = value end, 360)
      Dibs.AceGUI.AddButton(shell, tabs, "Apply review", function()
        local result, reason = Dibs.OfficerUI.ReviewVaultAcquisition(self.vaultAcquisitionId, self.vaultDecisionValue or "CONFIRM", self.vaultReasonValue, nil)
        self:SetStatus(result and "Great Vault review recorded." or ("Unable to review Great Vault record: " .. tostring(reason or "unknown error")))
        if result then self:Refresh() end
      end, 120)
      local statusValues = { ALL = "All statuses", UNVERIFIED = "Unverified", MANUAL_RECORDED = "Manual", LEGACY_RECORDED = "Legacy", AUTOMATIC_CONFIRMED = "Automatic", OFFICER_CONFIRMED = "Officer confirmed", REJECTED = "Rejected", REFERENCE_ONLY = "Reference only" }
      self.vaultStatusControl = Dibs.AceGUI.AddDropdown(shell, tabs, "Status filter", statusValues, function(value) self.vaultStatusFilter = value == "ALL" and nil or value; self.ledgerPage = 1; self:Refresh() end, 220)
      Dibs.AceGUI.SetValue(self.vaultStatusControl, self.vaultStatusFilter or "ALL")
    end
    self.aceLedgerScroll = Dibs.AceGUI.AddTable(shell, tabs, columns, tableRows, 430, nil, {
      noScrolling = self.activeTab == "automaticDibs",
    })
    local pageControls = Dibs.AceGUI.AddInlineGroup(shell, tabs)
    local previous = Dibs.AceGUI.AddButton(shell, pageControls, "Previous", function() self.ledgerPage = math.max(1, self.ledgerPage - 1); self:Refresh() end, 80)
    self.pageText = Dibs.AceGUI.AddLabel(shell, pageControls, "Page " .. view.page .. "/" .. view.totalPages)
    local nextButton = Dibs.AceGUI.AddButton(shell, pageControls, "Next", function() self.ledgerPage = math.min(view.totalPages, self.ledgerPage + 1); self:Refresh() end, 60)
    Dibs.AceGUI.SetDisabled(previous, view.page <= 1)
    Dibs.AceGUI.SetDisabled(nextButton, view.page >= view.totalPages)
    Dibs.AceGUI.AddTooltip(self.pageText, "Page", "Current page and total number of pages.")
    if view.totalPages == 1 then
      setControlsVisible({ previous, self.pageText, nextButton }, false)
    end
  end
  activateRoute = function(route, syncTree)
    local normalized = normalizeOfficerTab(route or frame.activeTab or "overview")
    if not officerRouteVisible(normalized) then
      local routeModules = {
        disputes = "requests", preDibs = "preDibs", announcements = "announcements",
        integration = "rclootcouncil", eligibility = "lootEligibility",
      }
      if not routeModules[normalized] or moduleEnabled(routeModules[normalized]) then normalized = "overview" end
    end
    frame.activeTab, frame.selectedRoute, frame.ledgerPage = normalized, normalized, 1
    frame.routeDispatchCount = (frame.routeDispatchCount or 0) + 1
    if syncTree ~= false and navigation and frame._dibsTreeRoute ~= normalized then
      frame._dibsRouteSyncing = true
      Dibs.AceGUI.SelectTree(navigation, officerTreeSelectionValue(normalized))
      frame._dibsRouteSyncing = false
    end
    frame._dibsTreeRoute = normalized
    frame._dibsRenderingRoute = true
    local ok, reason = pcall(renderRoute, frame)
    frame._dibsRenderingRoute = false
    if not ok then error(reason, 0) end
    if navigation and navigation.DoLayout then navigation:DoLayout() end
  end
  frame.ActivateRoute = function(self, route)
    activateRoute(route, true)
  end
  frame.Refresh = function(self)
    if self._dibsRenderingRoute then return end
    activateRoute(self.activeTab, true)
  end

  shell.onRelease = function()
    closeRequestDetail()
    for _, key in ipairs({
      "aceTabs", "contentHost", "mountedPage", "mountedPageHost", "developerSandboxButton", "lootTypeControls",
      "enableLootTypes", "defaultLootTypes", "eligibilityAdvanced", "eligibilityFamily", "eligibilitySearchBox",
      "disputeStatusFilter", "disputeQuery", "disputeSearchBox", "disputeSelectedId", "disputeReason",
      "disputeStatusMessage", "disputeTechnicalExpanded", "disputeAdvancedExpanded", "disputeHistoryExpanded", "disputeDetailOpen", "requestDetailShell", "requestDetailRoot",
      "disputeAmount", "disputeConfirmed", "disputeTargetRequestId", "disputeCorrectPlayer", "disputeCorrectItem",
      "disputeCorrectPlayerQuery", "disputeCorrectItemQuery", "disputeCorrectItemKey", "disputeItemCatalogByKey",
      "rankRows", "rankDrafts", "rankRowCount", "selectedSeasonId", "inputBoundSeasonId", "ledgerPage", "ledgerQuery",
      "ledgerTitle", "ledgerText", "aceLedgerScroll", "pageText", "summaryText", "statusText", "activeTab",
      "selectedRoute", "Refresh", "SelectTab", "ActivateRoute", "routeDispatchCount", "_dibsRouteSyncing", "_dibsTreeRoute", "_dibsRenderingRoute", "SetStatus", "CloseHistoryTransfer", "dibsAceGUIShell", "_dibsUiShell",
    }) do
      frame[key] = nil
    end
  end
  if not frame._dibsOnShowHookInstalled then
    frame._dibsOnShowHookInstalled = true
    frame:HookScript("OnShow", function(self)
      local activeShell = self._dibsUiShell
      if activeShell and activeShell._dibsActive then self:Refresh() end
    end)
  end
  _G.DibsOfficerFrame = frame
  activateRoute(frame.activeTab, true)
  return frame
end

function Dibs.OfficerUI.CreateWindow(initialRoute)
  if _G.DibsOfficerFrame then
    local existingShell = _G.DibsOfficerFrame.dibsAceGUIShell
    if existingShell and existingShell.window then
      existingShell.window:SetWidth(980)
      existingShell.window:SetHeight(760)
    else
      _G.DibsOfficerFrame:SetSize(980, 760)
    end
    if initialRoute and _G.DibsOfficerFrame.ActivateRoute then
      _G.DibsOfficerFrame:ActivateRoute(initialRoute)
    end
    return _G.DibsOfficerFrame
  end

  if Dibs.AceGUI and Dibs.AceGUI.IsAvailable and Dibs.AceGUI.IsAvailable() then
    return createAceWindow(initialRoute)
  end

  local aceShell = nil
  local frame = CreateFrame("Frame", "DibsOfficerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(640, 650)
  frame:SetPoint("CENTER", 280, 0)
  frame:Hide()
  frame:SetClampedToScreen(true)
  frame:SetToplevel(true)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -12)
   title:SetText("RCLootCouncil - Dibs | Officer")

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  local seasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  seasonLabel:SetPoint("TOPLEFT", 16, -92)
  seasonLabel:SetWidth(610)
  seasonLabel:SetJustifyH("LEFT")

  local seasonDropdown = nil
  if HAS_DROPDOWN then
    seasonDropdown = CreateFrame("Frame", "DibsOfficerSeasonDropdown", frame, "UIDropDownMenuTemplate")
    seasonDropdown:SetPoint("TOPLEFT", 8, -20)
  end

  local previousSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  previousSeasonButton:SetSize(32, 22)
  previousSeasonButton:SetPoint("TOPLEFT", 242, -34)
  previousSeasonButton:SetText("<")

  local nextSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextSeasonButton:SetSize(32, 22)
  nextSeasonButton:SetPoint("LEFT", previousSeasonButton, "RIGHT", 4, 0)
  nextSeasonButton:SetText(">")

  local activateSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  activateSeasonButton:SetSize(84, 22)
  activateSeasonButton:SetPoint("LEFT", nextSeasonButton, "RIGHT", 6, 0)
  activateSeasonButton:SetText("Activate")

  local seasonNameInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  seasonNameInput:SetSize(260, 20)
  seasonNameInput:SetPoint("TOPLEFT", 16, -148)
  if seasonNameInput.SetAutoFocus then
    seasonNameInput:SetAutoFocus(false)
  end

  local newSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  newSeasonButton:SetSize(76, 22)
  newSeasonButton:SetPoint("LEFT", seasonNameInput, "RIGHT", 8, 0)
  newSeasonButton:SetText("Create")

  local renameSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  renameSeasonButton:SetSize(68, 22)
  renameSeasonButton:SetPoint("LEFT", newSeasonButton, "RIGHT", 4, 0)
  renameSeasonButton:SetText("Rename")

  local deleteSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  deleteSeasonButton:SetSize(62, 22)
  deleteSeasonButton:SetPoint("LEFT", renameSeasonButton, "RIGHT", 4, 0)
  deleteSeasonButton:SetText("Delete")

  local summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryText:SetPoint("TOPLEFT", 16, -178)
  summaryText:SetWidth(610)
  summaryText:SetJustifyH("LEFT")

  local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  statusText:SetPoint("TOPLEFT", 16, -256)
  statusText:SetWidth(610)
  statusText:SetJustifyH("LEFT")
  statusText:SetText("Ready")

  local sectionTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sectionTitle:SetPoint("TOPLEFT", 16, -282)
  sectionTitle:SetText("Rank allocations (choose rank + dibs, then Set)")

  local addRowButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  addRowButton:SetSize(28, 22)
  addRowButton:SetPoint("LEFT", sectionTitle, "RIGHT", 10, 0)
  addRowButton:SetText("+")

  local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(90, 24)
  refreshButton:SetPoint("BOTTOMLEFT", 16, 14)
  refreshButton:SetText("Refresh")

  local dashboardButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  dashboardButton:SetSize(90, 22)
  dashboardButton:SetPoint("TOPLEFT", 16, -116)
  dashboardButton:SetText("Dashboard")

  local playersButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  playersButton:SetSize(76, 22)
  playersButton:SetPoint("LEFT", dashboardButton, "RIGHT", 4, 0)
  playersButton:SetText("Players")

  local preDibsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  preDibsButton:SetSize(76, 22)
  preDibsButton:SetPoint("LEFT", playersButton, "RIGHT", 4, 0)
  preDibsButton:SetText("Pre-Dibs")

  local historyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  historyButton:SetSize(76, 22)
  historyButton:SetPoint("LEFT", preDibsButton, "RIGHT", 4, 0)
  historyButton:SetText("History")

  local statisticsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  statisticsButton:SetSize(72, 22)
  statisticsButton:SetPoint("LEFT", historyButton, "RIGHT", 4, 0)
  statisticsButton:SetText("Stats")

  local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  settingsButton:SetSize(76, 22)
  settingsButton:SetPoint("LEFT", statisticsButton, "RIGHT", 4, 0)
  settingsButton:SetText("Settings")

  local ledgerTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ledgerTitle:SetPoint("TOPLEFT", 16, -150)
  ledgerTitle:SetText("Dashboard")

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  searchLabel:SetPoint("TOPLEFT", 310, -150)
  searchLabel:SetText("Search:")

  local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  searchBox:SetSize(150, 20)
  searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
  if searchBox.SetAutoFocus then
    searchBox:SetAutoFocus(false)
  end
  setControlText(searchBox, "")

  local clearSearchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearSearchButton:SetSize(52, 22)
  clearSearchButton:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
  clearSearchButton:SetText("Clear")

  local ledgerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ledgerText:SetPoint("TOPLEFT", 16, -174)
  ledgerText:SetWidth(610)
  ledgerText:SetJustifyH("LEFT")

  local previousPageButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  previousPageButton:SetSize(28, 22)
  previousPageButton:SetPoint("BOTTOMLEFT", refreshButton, "RIGHT", 8, 0)
  previousPageButton:SetText("<")

  local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageText:SetPoint("LEFT", previousPageButton, "RIGHT", 6, 0)
  pageText:SetWidth(100)
  pageText:SetJustifyH("LEFT")

  local nextPageButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextPageButton:SetSize(28, 22)
  nextPageButton:SetPoint("LEFT", pageText, "RIGHT", 6, 0)
  nextPageButton:SetText(">")

  frame.summaryText = summaryText
  frame.statusText = statusText
  frame.seasonLabel = seasonLabel
  frame.seasonDropdown = seasonDropdown
  frame.seasonNameInput = seasonNameInput
  frame.ledgerText = ledgerText
  frame.ledgerTitle = ledgerTitle
  frame.pageText = pageText
  frame.searchBox = searchBox
  frame.activeTab = "dashboard"
  frame.ledgerPage = 1
  frame.inputBoundSeasonId = nil
  frame.rankRows = {}
  frame.dibsAceGUIShell = aceShell
  frame.settingsControls = {
    seasonNameInput, newSeasonButton, renameSeasonButton, deleteSeasonButton,
    summaryText, statusText, sectionTitle, addRowButton,
  }

  frame.SetStatus = function(self, msg)
    local text = tostring(msg or "")
    if self.statusText and self.statusText.SetText then
      self.statusText:SetText(text)
    end
    Dibs.Message(text)
  end

  local function ensureRows(count)
    while #frame.rankRows < count do
      table.insert(frame.rankRows, createRankRow(frame, #frame.rankRows + 1))
    end
  end

  ensureRows(3)

  local function refreshSeasonDropdown(self, seasons)
    if not self.seasonDropdown or not HAS_DROPDOWN then
      return
    end

    configureDropdown(self.seasonDropdown, 210, function(_, level)
      if level ~= 1 then
        return
      end
      for _, season in ipairs(seasons) do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = tostring(season.name)
        info.func = function()
          self.selectedSeasonId = season.id
          self.inputBoundSeasonId = nil
          setDropdownText(self.seasonDropdown, tostring(season.name))
          self:Refresh()
        end
        info.checked = season.id == self.selectedSeasonId
        _G.UIDropDownMenu_AddButton(info, level)
      end
    end)
  end

  frame.Refresh = function(self)
    local seasons = getSeasonList()
    local current = getSelectedSeason(self)
    if not current and #seasons > 0 then
      current = seasons[#seasons]
      self.selectedSeasonId = current.id
    end

    local activeSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
    local selectedName = current and current.name or "None"
    local activeName = (activeSeasonId and findSeasonById(activeSeasonId) and findSeasonById(activeSeasonId).name) or "None"

    self.seasonLabel:SetText("Season: " .. selectedName .. " (active: " .. activeName .. ")")

    if self.seasonNameInput and self.inputBoundSeasonId ~= (current and current.id or nil) then
      setControlText(self.seasonNameInput, selectedName ~= "None" and selectedName or getDefaultSeasonName())
      self.inputBoundSeasonId = current and current.id or nil
    end

    refreshSeasonDropdown(self, seasons)
    if self.seasonDropdown and current then
      setDropdownText(self.seasonDropdown, tostring(current.name))
    end

    self.summaryText:SetText(Dibs.OfficerUI.BuildStatusText(current))

    ensureRows(math.max(3, #seasons > 0 and 3 or 2))
    syncRowsToSeason(self, current)

    local isSettings = self.activeTab == "settings"
    local isSearchable = self.activeTab == "players" or self.activeTab == "predibs" or self.activeTab == "history"
    setControlsVisible(self.settingsControls, isSettings)
    setControlsVisible(self.rankRows, isSettings)
    setControlsVisible({ self.ledgerTitle, self.ledgerText }, not isSettings)
    setControlsVisible({ searchLabel, searchBox, clearSearchButton }, isSearchable)

    if isSettings then
      setControlsVisible({ previousPageButton, pageText, nextPageButton }, false)
      return
    end

    if self.activeTab == "dashboard" then
      self.ledgerTitle:SetText("Dashboard")
      self.ledgerText:SetText(table.concat(Dibs.OfficerUI.BuildDashboardDetails(current), "\n"))
      setControlsVisible({ previousPageButton, pageText, nextPageButton }, false)
      return
    end

    if self.activeTab == "statistics" then
      local statistics = Dibs.OfficerUI.BuildSeasonStatistics(current and current.id or nil)
      self.ledgerTitle:SetText("Season statistics")
      self.ledgerText:SetText("Active players: " .. tostring(statistics.players) .. "\n" ..
        "Transactions: " .. tostring(statistics.transactions) .. "\n" ..
        "Dibs used: " .. tostring(statistics.used) .. "\n" ..
        "Active pre-Dibs: " .. tostring(statistics.activePreDibs))
      setControlsVisible({ previousPageButton, pageText, nextPageButton }, false)
      return
    end

    local viewName = self.activeTab == "history" and "actions" or self.activeTab
    local view = Dibs.OfficerUI.GetPagedView(viewName, current and current.id or nil, self.ledgerPage, 8, getControlText(self.searchBox))
    self.ledgerPage = view.page
    self.ledgerTitle:SetText(view.title .. " (" .. tostring(view.totalCount) .. ")")
    self.pageText:SetText("Page " .. tostring(view.page) .. "/" .. tostring(view.totalPages))
    self.ledgerText:SetText(table.concat(view.lines, "\n"))
    setControlsVisible({ previousPageButton, pageText, nextPageButton }, true)
  end

  local function shiftSeason(offset)
    local seasons = getSeasonList()
    if #seasons == 0 then
      return
    end
    local selected = frame.selectedSeasonId
    local idx = 1
    for i, season in ipairs(seasons) do
      if season.id == selected then
        idx = i
        break
      end
    end
    idx = idx + offset
    if idx < 1 then
      idx = #seasons
    elseif idx > #seasons then
      idx = 1
    end
    frame.selectedSeasonId = seasons[idx].id
    frame.inputBoundSeasonId = nil
    frame:Refresh()
  end

  previousSeasonButton:SetScript("OnClick", function()
    shiftSeason(-1)
  end)

  nextSeasonButton:SetScript("OnClick", function()
    shiftSeason(1)
  end)

  activateSeasonButton:SetScript("OnClick", function()
    local selected = getSelectedSeason(frame)
    if not selected then
      frame:SetStatus("No season selected.")
      return
    end
    local result = Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = selected.id })
    frame:SetStatus(result.ok and ("Active season: " .. tostring(selected.name)) or result.diagnostic)
    frame:Refresh()
  end)

  newSeasonButton:SetScript("OnClick", function()
    local typed = trimText(getControlText(frame.seasonNameInput))
    local name = makeUniqueSeasonName(typed ~= "" and typed or getDefaultSeasonName())
    local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name })
    if result.ok and result.value then
      frame.selectedSeasonId = result.value.id
      frame.inputBoundSeasonId = nil
      frame:SetStatus("Created season: " .. tostring(result.value.name))
      setControlText(frame.seasonNameInput, getDefaultSeasonName())
    else
      frame:SetStatus(result.diagnostic or "Failed to create season.")
    end
    frame:Refresh()
  end)

  renameSeasonButton:SetScript("OnClick", function()
    local selected = getSelectedSeason(frame)
    if not selected then
      frame:SetStatus("No season selected.")
      return
    end

    local typed = trimText(getControlText(frame.seasonNameInput))
    if typed == "" then
      frame:SetStatus("Enter a season name first.")
      return
    end

    local duplicate = findSeasonByName(typed, selected.id)
    if duplicate then
      frame:SetStatus("A season with this name already exists.")
      return
    end

    local result = Dibs.ProtectedActions.Execute("season.rename", nil, { seasonId = selected.id, name = typed })
    if result.ok and result.value then
      frame.inputBoundSeasonId = nil
      frame:SetStatus("Season renamed: " .. tostring(result.value.name))
    else
      frame:SetStatus(result.diagnostic or "Unable to rename the selected season.")
    end
    frame:Refresh()
  end)

  deleteSeasonButton:SetScript("OnClick", function()
    local selected = getSelectedSeason(frame)
    if not selected then
      frame:SetStatus("No season selected.")
      return
    end

    local seasons = getSeasonList()
    if #seasons <= 1 then
      frame:SetStatus("At least one season must remain.")
      return
    end

    local result = Dibs.ProtectedActions.Execute("season.archive", nil, { seasonId = selected.id })
    if result.ok and result.value then
      frame.selectedSeasonId = nil
      frame.inputBoundSeasonId = nil
      frame:SetStatus("Season archived: " .. tostring(result.value.name))
    else
      frame:SetStatus(result.diagnostic or "Unable to delete the selected season.")
    end
    frame:Refresh()
  end)

  addRowButton:SetScript("OnClick", function()
    ensureRows(#frame.rankRows + 1)
    frame:Refresh()
  end)

  refreshButton:SetScript("OnClick", function()
    frame:Refresh()
  end)

  local function selectTab(tab)
    frame.activeTab = tab
    frame.ledgerPage = 1
    frame:Refresh()
  end

  frame.SelectTab = selectTab
  if aceShell then
    frame.aceTabs = Dibs.AceGUI.AddTabs(aceShell, {
      { text = "Dashboard", value = "dashboard" },
      { text = "Players", value = "players" },
      { text = "Pre-Dibs", value = "predibs" },
      { text = "History", value = "history" },
      { text = "Statistics", value = "statistics" },
      { text = "Settings", value = "settings" },
    }, selectTab)
    frame.aceLedgerScroll = Dibs.AceGUI.AddScrollableList(aceShell)
    frame.aceLedgerSearch = Dibs.AceGUI.AddSearch(aceShell, function(value)
      setControlText(frame.searchBox, value)
      frame.ledgerPage = 1
      frame:Refresh()
    end)
    frame.aceLedgerPagination = Dibs.AceGUI.AddPagination(aceShell, function()
      frame.ledgerPage = math.max(1, (frame.ledgerPage or 1) - 1)
      frame:Refresh()
    end, function()
      frame.ledgerPage = (frame.ledgerPage or 1) + 1
      frame:Refresh()
    end)
  end

  dashboardButton:SetScript("OnClick", function() selectTab("dashboard") end)
  playersButton:SetScript("OnClick", function() selectTab("players") end)
  preDibsButton:SetScript("OnClick", function() selectTab("predibs") end)
  historyButton:SetScript("OnClick", function() selectTab("history") end)
  statisticsButton:SetScript("OnClick", function() selectTab("statistics") end)
  settingsButton:SetScript("OnClick", function() selectTab("settings") end)
  searchBox:SetScript("OnTextChanged", function()
    frame.ledgerPage = 1
    frame:Refresh()
  end)
  clearSearchButton:SetScript("OnClick", function()
    setControlText(searchBox, "")
    frame.ledgerPage = 1
    frame:Refresh()
  end)
  previousPageButton:SetScript("OnClick", function()
    frame.ledgerPage = math.max(1, (frame.ledgerPage or 1) - 1)
    frame:Refresh()
  end)
  nextPageButton:SetScript("OnClick", function()
    frame.ledgerPage = (frame.ledgerPage or 1) + 1
    frame:Refresh()
  end)

  frame:HookScript("OnShow", function(self)
    self:Refresh()
  end)

  _G.DibsOfficerFrame = frame
  return frame
end

function Dibs.OfficerUI.ManageStandaloneAdmin(target, appoint)
  return Dibs.ProtectedActions.Execute(appoint and "admin.appoint" or "admin.revoke", nil, { target = target, reason = "Officer UI" })
end

function Dibs.OfficerUI.GetCandidateFallback(playerName, itemID)
  if not Dibs.RCLootCouncil or not Dibs.RCLootCouncil.GetStatusForCandidate then
    return nil, (Dibs.L and Dibs.L.RC_STATUS_UNAVAILABLE) or "RCLootCouncil status is unavailable."
  end
  local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  local availability = Dibs.RCLootCouncil.GetAvailability and Dibs.RCLootCouncil.GetAvailability() or "absent"
  if availability ~= "operational" then
    status.diagnostic = (Dibs.L and Dibs.L.RC_COMPATIBILITY_FALLBACK) or "RCLootCouncil candidate integration is unavailable; using the local Dibs display."
  end
  return status, status.diagnostic
end

---@return table|nil frame Officer window when UI is available.
-- Side effects: Creates/shows the permission-filtered officer control center.
function Dibs.OfficerUI.Show()
  if not canViewOfficerData() then
    Dibs.Message("Only the guild master or an officer may open the officer view.")
    return nil
  end
  local frame = Dibs.OfficerUI.CreateWindow()
  local shell = frame.dibsAceGUIShell
  if shell and shell.window then
    shell.window:SetWidth(800)
    shell.window:SetHeight(720)
  else
    frame:SetSize(800, 720)
  end
  local wasShown = frame:IsShown()
  frame:Show()
  frame:Raise()
  if wasShown and frame.Refresh then
    frame:Refresh()
  end

  local overview = Dibs.OfficerUI.GetLedgerOverview()
  Dibs.Message("Dibs officer ledger: " .. tostring(overview.count) .. " transactions")
  return overview
end

---@param forceShow boolean|nil Force visible state when true.
---@return boolean visible Whether the officer window is visible after the toggle.
function Dibs.OfficerUI.Toggle(forceShow)
  if not canViewOfficerData() then
    Dibs.Message("Only the guild master or an officer may open the officer view.")
    return false
  end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    Dibs.OfficerUI.pendingToggle = forceShow ~= false
    Dibs.Message((Dibs.L and Dibs.L.UI_DEFERRED_COMBAT) or "Officer UI will open after combat.")
    return false
  end

  local frame = Dibs.OfficerUI.CreateWindow()
  local wasShown = frame:IsShown()
  if forceShow then
    frame:Show()
    frame:Raise()
  elseif frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    frame:Raise()
  end

  if frame:IsShown() and wasShown and frame.Refresh then
    frame:Refresh()
  end

  return frame:IsShown()
end

function Dibs.OfficerUI.CreateSeason(name)
  if not Dibs.ProtectedActions then
    return nil
  end
  local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name })
  return result.ok and result.value or nil, result
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
  if Dibs.OfficerUI.pendingToggle then
    Dibs.OfficerUI.pendingToggle = nil
    Dibs.OfficerUI.Toggle(true)
  end
end)
