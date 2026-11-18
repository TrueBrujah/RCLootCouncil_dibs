-- Authorized dashboard presentation only. No authority, ledger reads or business writes.
local Dibs = _G.Dibs
local Dashboard = {}
Dibs.OfficerDashboard = Dashboard
local function text(key, fallback) return (Dibs.L and Dibs.L[key]) or fallback end

local function addLedgerViewControl(shell, container, frame, dashboard)
  local strings = Dibs.L or {}
  local ledgerValues = Dibs.AceGUI.GetLedgerDropdownValues(
    dashboard and dashboard.ledgerChoices,
    dashboard and dashboard.activeLedgerId,
    dashboard and dashboard.viewLedger and dashboard.viewLedger.id)
  local dropdown = Dibs.AceGUI.AddDropdown(shell, container, strings.LEDGER_VIEW_LABEL or "View ledger", ledgerValues, function(value)
    Dibs.AceGUI.SelectViewLedger(value)
    frame:Refresh()
  end, 200)
  local viewLedgerId = dashboard and dashboard.viewLedger and dashboard.viewLedger.id
    or Dibs.MultiLedger.GetViewLedgerId()
  Dibs.AceGUI.SetValue(dropdown, viewLedgerId)
  Dibs.AceGUI.AddTooltip(dropdown, strings.LEDGER_VIEW_LABEL or "View ledger", strings.LEDGER_VIEW_TOOLTIP)
  return dropdown
end

function Dashboard.Render(shell, parent, frame, dashboard, renderStartedAt)
  local dashboardRenderStartedAt = renderStartedAt or Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  if dashboard.hidden then
    Dibs.AceGUI.AddHeading(shell, parent, text("DASHBOARD_TITLE", "Officer dashboard"))
    Dibs.AceGUI.AddLabel(shell, parent, text("DASHBOARD_ACCESS_REQUIRED", "Officer access required."), true)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-total", dashboardRenderStartedAt)
    end
    return
  end
  local statusSection
  local function addStatus(key, value)
    local label = value and value.label or text("DASHBOARD_UNAVAILABLE", "Unavailable")
    local stateKey = "DASHBOARD_STATE_" .. tostring(label):upper():gsub("[^A-Z0-9]+", "_")
    local explanation = (Dibs.L or {})[stateKey .. "_HELP"] or (value and value.explanation)
    label = (Dibs.L or {})[stateKey] or label
    local tone = value and value.tone
    if not tone then
      if label == "Ready" or label == "Operational" or label == "Healthy" then tone = "success"
      elseif label == text("DASHBOARD_UNAVAILABLE", "Unavailable") then tone = "danger"
      elseif label == "Degraded" or label == "Recovery in progress" or label == "Behind / Synchronizing" or label == "Offline" then tone = "warning"
      else tone = "info" end
    end
    local statusText = value and value.memberName
      and (key .. ": " .. value.memberName .. " (" .. label .. ")") or (key .. ": " .. label)
    local badge = Dibs.Midnight.AddStatusBadge(shell, statusSection, tone, statusText)
    local colorNames = { success = "SUCCESS", ready = "SUCCESS", warning = "WARNING", danger = "DANGER", info = "INFO" }
    local tokens = Dibs.Midnight.GetTokens and Dibs.Midnight.GetTokens() or {}
    local color = tokens.colors and tokens.colors[colorNames[tone]]
    if badge and badge.label and color and type(badge.label.SetTextColor) == "function" then
      badge.label:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    Dibs.AceGUI.AddLabel(shell, statusSection, tostring(explanation or text("DASHBOARD_UNAVAILABLE_DETAIL", "Unavailable.")), true)
  end
  local controlsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  local controlHeaderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  Dibs.AceGUI.AddHeading(shell, parent, text("DASHBOARD_TITLE", "Officer dashboard"), text("DASHBOARD_INTRO", "Guild-wide operational summary for authorized Officers and GM."))
  local controlRow = Dibs.AceGUI.AddInlineGroup(shell, parent)
  local seasonLabel = Dibs.AceGUI.AddLabel(shell, controlRow, text("DASHBOARD_SEASON_PREFIX", "Season: ") .. tostring(dashboard.season and dashboard.season.name or text("DASHBOARD_NO_SEASON", "No active season")), false)
  if seasonLabel and seasonLabel.SetWidth then seasonLabel:SetWidth(180) end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-control-header", controlHeaderStartedAt)
  end
  if Dibs.MultiLedger and type(Dibs.MultiLedger.GetLedgers) == "function" then
    local selectorStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
      and Dibs.UIRenderStats.Begin(false)
    addLedgerViewControl(shell, controlRow, frame, dashboard)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-ledger-selector", selectorStartedAt)
    end
    Dibs.AceGUI.AddButton(shell, controlRow, (Dibs.L or {}).LEDGERS_MANAGE or "Manage ledgers", function()
      frame:ActivateRoute("installation")
    end, 160)
  end
  if Dibs.IndependentRaid and Dibs.IndependentRaid.IsSessionActive and Dibs.IndependentRaid.IsSessionActive() then
    Dibs.Midnight.AddStatusBadge(shell, controlRow, "warning", text("DASHBOARD_INDEPENDENT", "Independent Raid Active"))
  end
  if dashboard.viewLedger and dashboard.viewLedger.readOnly then
    local strings = Dibs.L or {}
    local ledgerValues = Dibs.AceGUI.GetLedgerDropdownValues()
    local viewLedgerId = dashboard.viewLedger.id
    Dibs.Midnight.AddStatusBadge(shell, parent, "warning", string.format(strings.LEDGER_VIEW_READONLY or "Read-only: %s",
      tostring(ledgerValues[viewLedgerId] or viewLedgerId)))
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-controls", controlsStartedAt)
  end
  local servicesStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  statusSection = Dibs.AceGUI.AddSection(shell, parent, text("DASHBOARD_SERVICES", "Service status"), text("DASHBOARD_SERVICES_HELP", "Current state of the services used by Dibs."))
  addStatus(text("DASHBOARD_LEDGER", "Ledger"), dashboard.status.ledger)
  addStatus(text("DASHBOARD_SYNC", "Sync"), dashboard.status.sync)
  addStatus(text("DASHBOARD_COORDINATOR", "Coordinator"), dashboard.status.coordinator)
  addStatus("RCLootCouncil", dashboard.status.rclootcouncil)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-services", servicesStartedAt)
  end
  if dashboard.nextAction then
    local action = dashboard.nextAction
    Dibs.AceGUI.AddHeader(shell, parent, text("DASHBOARD_NEXT_ACTION", "Next action"), action.explanation)
    Dibs.AceGUI.AddButton(shell, parent, action.label, function() frame:ActivateRoute(action.route) end, 230)
  end
  local activityStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  local recentLines = {}
  for index = 1, math.min(5, #dashboard.recentActivity) do
    recentLines[#recentLines + 1] = dashboard.recentActivity[index]
  end
  local recentText = #recentLines > 0 and table.concat(recentLines, "\n") or dashboard.empty.recentActivity
  local activitySection = Dibs.AceGUI.AddSection(shell, parent, text("DASHBOARD_ACTIVITY", "Recent activity"), text("DASHBOARD_ACTIVITY_HELP", "Latest bounded Officer-visible activity."))
  Dibs.AceGUI.AddLabel(shell, activitySection, recentText, true)
  Dibs.AceGUI.AddButton(shell, activitySection, text("DASHBOARD_SEARCH_ACTIVITY", "Search activity logs"), function()
    if Dibs.LogsUI and type(Dibs.LogsUI.OpenOfficer) == "function" then
      local opened, reason = Dibs.LogsUI.OpenOfficer("actions", dashboard.season and dashboard.season.id)
      if not opened then frame:SetStatus(text("DASHBOARD_LOGS_ERROR", "Unable to open activity logs: ") .. tostring(reason or "UI_UNAVAILABLE")) end
    else
      frame:SetStatus(text("DASHBOARD_LOGS_UNAVAILABLE", "Activity logs are unavailable."))
    end
  end, 190)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-activity", activityStartedAt)
  end
  local preDibsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  local bossGroups = dashboard.preDibBossGroups or {}
  local bossSection = Dibs.AceGUI.AddSection(shell, parent, text("DASHBOARD_PREDIBS", "Pre-Dibs by boss"),
    text("DASHBOARD_PREDIBS_HELP", "Up to five active requests per boss. Open Pre-Dibs to review the full list."))
  if #bossGroups == 0 then
    Dibs.AceGUI.AddLabel(shell, bossSection, dashboard.empty.activePreDibs or text("DASHBOARD_NO_PREDIBS", "No active Pre-Dibs."), true)
  end
  for _, group in ipairs(bossGroups) do
    local bossTitle = tostring(group.encounterName or text("DASHBOARD_NO_BOSS", "Boss unavailable"))
    if group.instanceName and group.instanceName ~= "" then
      bossTitle = bossTitle .. " | " .. group.instanceName
    end
    Dibs.AceGUI.AddHeader(shell, bossSection,
      bossTitle .. " (" .. tostring(group.activeRequestCount or #group.rows) .. ")")
    for _, request in ipairs(group.rows or {}) do
      Dibs.AceGUI.AddLabel(shell, bossSection,
        request.itemName .. " | " .. request.playerName .. " | " .. request.difficulty .. " | " .. request.status, true)
    end
    if (group.moreCount or 0) > 0 then
      Dibs.AceGUI.AddLabel(shell, bossSection, text("DASHBOARD_AND", "And ") .. tostring(group.moreCount) .. text("DASHBOARD_MORE", " more."), true)
    end
  end
  Dibs.AceGUI.AddButton(shell, bossSection, text("DASHBOARD_OPEN_PREDIBS", "Open Pre-Dibs"), function()
    frame:ActivateRoute("preDibRequests")
  end, 140)
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-predibs", preDibsStartedAt)
  end
  local metricsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  Dibs.AceGUI.AddHeader(shell, parent, text("DASHBOARD_STATISTICS", "Season statistics"), text("DASHBOARD_STATISTICS_HELP", "Current-season activity; award distribution values are per recipient."))
  local metricGrid = Dibs.AceGUI.AddInlineGroup(shell, parent)
  local metrics = {
    { label = text("DASHBOARD_ACTIVE_PLAYERS", "Active players"), value = dashboard.metrics.activePlayers },
    { label = text("DASHBOARD_PENDING_REQUESTS", "Pending requests"), value = dashboard.metrics.pendingRequests },
    { label = text("DASHBOARD_ACTIVE_PREDIBS", "Active Pre-Dibs"), value = dashboard.metrics.activePreDibs },
    { label = text("DASHBOARD_ACTIONS", "Actions"), value = dashboard.metrics.transactions },
    { label = text("DASHBOARD_AWARDS", "Awards"), value = dashboard.metrics.awards },
    { label = text("DASHBOARD_GRANTED", "Granted Dibs"), value = dashboard.metrics.grantedDibs },
    { label = text("DASHBOARD_USED", "Used Dibs"), value = dashboard.metrics.usedDibs },
    { label = text("DASHBOARD_CORRECTIONS", "Corrections"), value = dashboard.metrics.corrections },
    { label = text("DASHBOARD_RECIPIENTS", "Award recipients"), value = dashboard.metrics.awardRecipients },
    { label = text("DASHBOARD_MEAN", "Average awards"), value = string.format("%.1f", dashboard.metrics.averageAwardsPerRecipient or 0),
      tooltip = text("DASHBOARD_MEAN_HELP", "Average awards per recipient this season.") },
    { label = text("DASHBOARD_MEDIAN", "Median awards"), value = dashboard.metrics.medianAwardsPerRecipient,
      tooltip = "Median awards per recipient this season." },
    { label = text("DASHBOARD_MAX", "Max awards"), value = dashboard.metrics.maxAwardsPerRecipient,
      tooltip = "Most awards received by one recipient this season." },
  }
  for _, metric in ipairs(metrics) do
    local block = Dibs.AceGUI.Create(shell, "InlineGroup", metricGrid)
    if block then
      if block.SetLayout then block:SetLayout("List") end
      if block.SetWidth then block:SetWidth(132) end
      Dibs.AceGUI.AddHeading(shell, block, tostring(metric.value or 0))
      local label = Dibs.AceGUI.AddLabel(shell, block, metric.label, true)
      if metric.tooltip then Dibs.AceGUI.AddTooltip(label, metric.label, metric.tooltip) end
    end
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-metrics", metricsStartedAt)
  end
  local technicalStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin
    and Dibs.UIRenderStats.Begin(false)
  Dibs.AceGUI.AddButton(shell, parent, frame.showDashboardTechnical and text("DASHBOARD_HIDE_DETAILS", "Hide technical details") or text("DASHBOARD_SHOW_DETAILS", "Show technical details"), function()
    frame.showDashboardTechnical = not frame.showDashboardTechnical
    frame:Refresh()
  end, 190)
  if frame.showDashboardTechnical then
    Dibs.AceGUI.AddHeader(shell, parent, text("DASHBOARD_DETAILS", "Technical details"), text("DASHBOARD_DETAILS_HELP", "Normalized service state and diagnostic reason codes."))
    Dibs.AceGUI.AddLabel(shell, parent, text("DASHBOARD_SYNC_STATE", "Sync state: ") .. tostring(dashboard.technical.sync.state or "unknown"), true)
    Dibs.AceGUI.AddLabel(shell, parent, text("DASHBOARD_COORDINATOR_STATE", "Coordinator state: ") .. tostring(dashboard.technical.coordinator.state or "unknown"), true)
    Dibs.AceGUI.AddLabel(shell, parent, text("DASHBOARD_RC_REASON", "RCLootCouncil reason: ") .. tostring(dashboard.technical.rclootcouncil.reasonCode or "none"), true)
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-technical", technicalStartedAt)
    Dibs.UIRenderStats.Record("Officer data", "dashboard-ui-total", dashboardRenderStartedAt)
  end
end
