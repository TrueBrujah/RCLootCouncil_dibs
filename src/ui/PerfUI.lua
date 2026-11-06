--[[
Module: Dibs.PerfUI
Layer: UI / diagnostics
Purpose: Toggle, reset, inspect, and copy bounded in-session UI performance timings.
Responsibilities: Present UIRenderStats without collecting extra addon data.
Non-responsibilities: It does not persist, export, or synchronize measurements.
Dependencies: Dibs.UIRenderStats, AceGUI.
SavedVariables: None.
]]

local Dibs = _G.Dibs
Dibs.PerfUI = Dibs.PerfUI or {}

local currentShell
local selectedKind = "all"
local statusLabel
local reportWidget

local KNOWN_KINDS = {
  "Officer", "Officer data", "Officer UI", "Wizard data", "Wizard step",
  "Rank data", "Player", "Player data", "Player UI", "Pre-Dibs data",
  "UI widget", "UI table", "AceConfig",
}

local function getKinds()
  local kinds = { all = "All report types" }
  for _, kind in ipairs(KNOWN_KINDS) do kinds[kind] = kind end
  local report = Dibs.UIRenderStats and Dibs.UIRenderStats.GetReport and Dibs.UIRenderStats.GetReport()
  for _, row in ipairs(report and report.pages or {}) do
    if row.kind and kinds[row.kind] == nil then kinds[row.kind] = row.kind end
  end
  return kinds
end

function Dibs.PerfUI.BuildReportText(kind)
  local stats = Dibs.UIRenderStats
  local report = stats and stats.GetReport and stats.GetReport()
  if not report or type(report.pages) ~= "table" then return "Performance timing is unavailable." end
  local rows = {}
  local selected = kind or "all"
  for _, row in ipairs(report.pages) do
    if selected == "all" or row.kind == selected then rows[#rows + 1] = row end
  end
  if #rows == 0 then
    return selected == "all" and "No UI render timings recorded. Enable timing, then open or refresh pages."
      or ("No measurements recorded for " .. tostring(selected) .. ".")
  end
  local lines = {
    "Dibs UI render time (ms; current session):",
    "Lua heap ΔKB is global net change during each sample; GC noise applies, not addon attribution or allocation volume.",
  }
  for _, row in ipairs(rows) do
    local line = string.format("%s / %s: count=%d last=%.2f avg=%.2f max=%.2f total=%.2f",
      row.kind, row.page, row.count, row.lastMs, row.averageMs, row.maxMs, row.totalMs)
    if row.heapSampleCount and row.heapSampleCount > 0 then
      line = line .. string.format(" | Lua heap ΔKB last=%.2f avg=%.2f max=%.2f net=%.2f",
        row.heapDeltaLastKB, row.heapDeltaAverageKB, row.heapDeltaMaxKB, row.heapDeltaTotalKB)
    end
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "Timing uses debugprofilestop; it excludes later asynchronous work."
  return table.concat(lines, "\n")
end

local function updateReport()
  if statusLabel and statusLabel.SetText then
    local enabled = Dibs.UIRenderStats and Dibs.UIRenderStats.IsEnabled
      and Dibs.UIRenderStats.IsEnabled()
    statusLabel:SetText("Timing: " .. (enabled and "Enabled for this session" or "Disabled")
      .. " | Report type: " .. tostring(selectedKind == "all" and "All" or selectedKind))
  end
  if reportWidget and reportWidget.SetText then
    reportWidget:SetText(Dibs.PerfUI.BuildReportText(selectedKind))
  end
end

function Dibs.PerfUI.Open()
  local gui = Dibs.AceGUI
  if not gui or not gui.CreateWindow then return nil end
  if currentShell and currentShell.window then
    updateReport()
    currentShell.window:Show()
    return currentShell
  end

  local shell = gui.CreateWindow("Dibs | Performance Reports", 820, 620,
    { "CENTER", 0, 0 }, "DibsPerfReports")
  if not shell then return nil end
  currentShell = shell
  local content = gui.AddScrollableList(shell, shell.window, 540) or shell.window
  gui.AddHeading(shell, content, "Performance reports",
    "Session-only UI timings. Enable collection, open or refresh pages, then refresh this report.")
  statusLabel = gui.AddLabel(shell, content, "", true)

  local controls = gui.AddInlineGroup(shell, content)
  gui.AddButton(shell, controls, "Enable", function()
    Dibs.UIRenderStats.SetEnabled(true)
    updateReport()
  end, 90)
  gui.AddButton(shell, controls, "Disable", function()
    Dibs.UIRenderStats.SetEnabled(false)
    updateReport()
  end, 90)
  gui.AddButton(shell, controls, "Reset", function()
    Dibs.UIRenderStats.Reset()
    updateReport()
  end, 90)
  gui.AddButton(shell, controls, "Refresh report", updateReport, 130)
  gui.AddButton(shell, controls, "Select report for copy", function()
    if gui.SelectText then gui.SelectText(reportWidget) end
  end, 170)

  local typeControl = gui.AddDropdown(shell, content, "Report type", getKinds(), function(value)
    selectedKind = value or "all"
    updateReport()
  end, 260)
  gui.SetValue(typeControl, selectedKind)
  reportWidget = gui.AddSelectableText(shell, content, "Copy with Ctrl+C",
    Dibs.PerfUI.BuildReportText(selectedKind), 760, 360)
  updateReport()
  if shell.window and shell.window.Show then shell.window:Show() end
  return shell
end

function Dibs.PerfUI.Toggle()
  if currentShell and currentShell.window and currentShell.window.frame
    and currentShell.window.frame.IsShown and currentShell.window.frame:IsShown() then
    currentShell.window:Hide()
    return nil
  end
  return Dibs.PerfUI.Open()
end
