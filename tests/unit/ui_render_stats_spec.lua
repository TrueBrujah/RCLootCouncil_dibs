local loader = require("helpers.load_addon")

describe("opt-in UI render timing", function()
  it("does no timing work while disabled and keeps bounded per-page counters when enabled", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer = _G.debugprofilestop
    register_reset(function() _G.debugprofilestop = timer end)
    local clock = 0
    _G.debugprofilestop = function()
      clock = clock + 2
      return clock
    end

    assert_false(dibs.UIRenderStats.IsEnabled())
    assert_nil(dibs.UIRenderStats.Begin())
    assert_false(dibs.UIRenderStats.Record("Officer", "overview", 0))
    assert_equal(0, #dibs.UIRenderStats.GetReport().pages)

    dibs.UIRenderStats.SetEnabled(true)
    local startedAt = dibs.UIRenderStats.Begin()
    assert_true(dibs.UIRenderStats.Record("Officer", "overview", startedAt))
    startedAt = dibs.UIRenderStats.Begin()
    assert_true(dibs.UIRenderStats.Record("Officer", "overview", startedAt))
    local report = dibs.UIRenderStats.GetReport()
    assert_equal(1, #report.pages)
    assert_equal("Officer", report.pages[1].kind)
    assert_equal("overview", report.pages[1].page)
    assert_equal(2, report.pages[1].count)
    assert_equal(2, report.pages[1].lastMs)
    assert_equal(2, report.pages[1].averageMs)
    assert_equal(2, report.pages[1].maxMs)

    dibs.UIRenderStats.Reset()
    assert_equal(0, #dibs.UIRenderStats.GetReport().pages)
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = timer
  end)

  it("keeps collecting later Player page timings and reports when the session counter limit is reached", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer = _G.debugprofilestop
    register_reset(function() _G.debugprofilestop = timer end)
    local clock = 0
    _G.debugprofilestop = function() clock = clock + 1; return clock end
    dibs.UIRenderStats.SetEnabled(true)

    for index = 1, 128 do
      local startedAt = dibs.UIRenderStats.Begin()
      assert_true(dibs.UIRenderStats.Record("Nested", "counter-" .. tostring(index), startedAt))
    end
    local startedAt = dibs.UIRenderStats.Begin()
    assert_true(dibs.UIRenderStats.Record("Player", "requests", startedAt))
    local report = dibs.UIRenderStats.GetReport()
    assert_equal(129, #report.pages)
    assert_equal(512, report.maxPages)

    for index = 130, 512 do
      startedAt = dibs.UIRenderStats.Begin()
      assert_true(dibs.UIRenderStats.Record("Nested", "counter-" .. tostring(index), startedAt))
    end
    startedAt = dibs.UIRenderStats.Begin()
    assert_false(dibs.UIRenderStats.Record("Overflow", "counter", startedAt),
      "the counter collection must stay bounded")
    report = dibs.UIRenderStats.GetReport()
    assert_equal(512, #report.pages)
    assert_equal(1, report.droppedPageCount)
    local requestsRecorded = false
    for _, row in ipairs(report.pages) do
      if row.kind == "Player" and row.page == "requests" then requestsRecorded = true end
    end
    assert_true(requestsRecorded)
    assert_true(dibs.UIRenderStats.FormatReport():find("1 new timing counters were omitted", 1, true) ~= nil,
      "the report should disclose counters rejected by the session limit")
    dibs.UIRenderStats.SetEnabled(false)
  end)

  it("reports sampled global Lua heap deltas for each timing counter", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer, collect = _G.debugprofilestop, _G.collectgarbage
    register_reset(function()
      _G.debugprofilestop = timer
      _G.collectgarbage = collect
    end)
    local clock, heap = 0, 128
    _G.debugprofilestop = function() clock = clock + 5; return clock end
    _G.collectgarbage = function(option)
      assert_equal("count", option)
      return heap
    end

    dibs.UIRenderStats.SetEnabled(true)
    local startedAt = dibs.UIRenderStats.Begin()
    heap = 160
    assert_true(dibs.UIRenderStats.Record("Officer", "overview", startedAt))
    local row = dibs.UIRenderStats.GetReport().pages[1]
    assert_equal(1, row.heapSampleCount)
    assert_equal(32, row.heapDeltaLastKB)
    assert_equal(32, row.heapDeltaAverageKB)
    assert_equal(32, row.heapDeltaMaxKB)
    assert_equal(32, row.heapDeltaTotalKB)
    assert_true(dibs.UIRenderStats.FormatReport():find("Lua heap ΔKB", 1, true) ~= nil)
    assert_true(dibs.UIRenderStats.FormatReport():find("last=32.00", 1, true) ~= nil)
    dibs.UIRenderStats.SetEnabled(false)
  end)

  it("supports CPU-only timing for high-frequency counters without sampling the global heap", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer, collect = _G.debugprofilestop, _G.collectgarbage
    register_reset(function()
      _G.debugprofilestop = timer
      _G.collectgarbage = collect
    end)
    local clock, heapReads = 0, 0
    _G.debugprofilestop = function() clock = clock + 3; return clock end
    _G.collectgarbage = function(option)
      assert_equal("count", option)
      heapReads = heapReads + 1
      return 128
    end

    dibs.UIRenderStats.SetEnabled(true)
    local startedAt = dibs.UIRenderStats.Begin(false)
    assert_equal(0, heapReads)
    assert_true(dibs.UIRenderStats.Record("UI widget", "create", startedAt))
    assert_equal(0, heapReads)
    local row = dibs.UIRenderStats.GetReport().pages[1]
    assert_equal(3, row.lastMs)
    assert_equal(0, row.heapSampleCount)

    local begin = dibs.UIRenderStats.Begin
    local requestedHeapSampling
    dibs.UIRenderStats.Begin = function(trackHeap)
      requestedHeapSampling = trackHeap
      return begin(trackHeap)
    end
    local shell = dibs.AceGUI.CreateWindow("CPU-only widget timing", 400, 300)
    dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    dibs.UIRenderStats.Begin = begin
    assert_equal(false, requestedHeapSampling,
      "per-widget timing should not trigger a global heap query")
    dibs.UIRenderStats.SetEnabled(false)
  end)

  it("skips the per-widget Record call entirely when render timing is disabled", function()
    local _, dibs = loader.load({ withAce3 = true })
    local shell = dibs.AceGUI.CreateWindow("Disabled widget timing", 400, 300)
    dibs.UIRenderStats.SetEnabled(false)
    local record = dibs.UIRenderStats.Record
    dibs.UIRenderStats.Record = function()
      error("disabled widget timing must not call Record")
    end

    local ok, widget = pcall(dibs.AceGUI.Create, shell, "Label", shell.window)
    dibs.UIRenderStats.Record = record

    assert_true(ok, tostring(widget))
    assert_not_nil(widget)
  end)

  it("records dynamic AceConfig callback cost separately by option phase", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer = _G.debugprofilestop
    register_reset(function() _G.debugprofilestop = timer end)
    local clock = 0
    _G.debugprofilestop = function()
      clock = clock + 1
      return clock
    end
    local shell = dibs.AceGUI.CreateWindow("AceConfig callback timing", 500, 350)
    dibs.UIRenderStats.SetEnabled(true)
    local options = {
      name = "Callback probe",
      args = {
        enabled = {
          type = "toggle",
          name = function() return "Enabled" end,
          desc = function() return "A measured description." end,
          hidden = function() return false end,
          disabled = function() return false end,
          get = function() return true end,
          set = function() end,
        },
      },
    }
    assert_true(dibs.AceGUI.RenderOptionsGroup(shell, shell.window, options, {
      scroll = false, renderGroupTitle = false,
    }))

    local measured = {}
    for _, row in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if row.kind == "AceConfig callback" then measured[row.page] = row end
    end
    dibs.UIRenderStats.SetEnabled(false)
    assert_true(measured["Callback probe/hidden"] ~= nil)
    assert_true(measured["Callback probe/name"] ~= nil)
    assert_true(measured["Callback probe/description"] ~= nil)
    assert_true(measured["Callback probe/disabled"] ~= nil)
    assert_true(measured["Callback probe/getter"] ~= nil)
  end)

  it("builds a complete copyable report for a selected category and opens from the slash command", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer = _G.debugprofilestop
    register_reset(function() _G.debugprofilestop = timer end)
    local clock = 0
    _G.debugprofilestop = function()
      clock = clock + 1
      return clock
    end
    dibs.UIRenderStats.SetEnabled(true)
    for index = 1, 25 do
      local startedAt = dibs.UIRenderStats.Begin()
      dibs.UIRenderStats.Record("Officer data", "page-" .. index, startedAt)
    end

    local selected = dibs.PerfUI.BuildReportText("Officer data")
    assert_true(selected:find("Officer data / page-25", 1, true) ~= nil)
    assert_equal(28, select(2, selected:gsub("\n", "")) + 1)

    local shell = dibs.PerfUI.Open()
    assert_not_nil(shell)
    assert_not_nil(shell.window)
    assert_equal(shell, dibs.PerfUI.Open())
    dibs.HandleSlashCommand("perf window")
    assert_true(dibs.UIRenderStats.IsEnabled())
    dibs.UIRenderStats.SetEnabled(false)
  end)

  it("counts actual Officer and Player page renders separately", function()
    local _, dibs = loader.load({ withAce3 = true })
    local timer = _G.debugprofilestop
    register_reset(function() _G.debugprofilestop = timer end)
    local previousChat = _G.DEFAULT_CHAT_FRAME
    register_reset(function() _G.DEFAULT_CHAT_FRAME = previousChat end)
    local clock = 0
    _G.debugprofilestop = function()
      clock = clock + 1
      return clock
    end
    local messages = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, value) messages[#messages + 1] = value end }
    dibs.HandleSlashCommand("perf reset")
    dibs.HandleSlashCommand("perf on")

    local originalPagedView = dibs.OfficerUI.GetPagedView
    local originalResolveTokens = dibs.EnvironmentAdapters.ResolveTokens
    local originalBeginPresentationContext = dibs.AceGUI.BeginPresentationContext
    local rankRouteUsedLedgerView = false
    local tokenResolutions, presentationContextCalls = 0, 0
    dibs.OfficerUI.GetPagedView = function(view, ...)
      if view == "ranks" then rankRouteUsedLedgerView = true end
      return originalPagedView(view, ...)
    end
    local officer = dibs.OfficerUI.CreateWindow("overview")
    dibs.EnvironmentAdapters.ResolveTokens = function(...)
      tokenResolutions = tokenResolutions + 1
      return originalResolveTokens(...)
    end
    dibs.AceGUI.BeginPresentationContext = function(...)
      presentationContextCalls = presentationContextCalls + 1
      return originalBeginPresentationContext(...)
    end
    officer:ActivateRoute("ranks")
    dibs.EnvironmentAdapters.ResolveTokens = originalResolveTokens
    dibs.AceGUI.BeginPresentationContext = originalBeginPresentationContext
    officer:ActivateRoute("integration")
    dibs.OfficerUI.GetPagedView = originalPagedView
    assert_false(rankRouteUsedLedgerView,
      "Rank Rules route should render rank configuration instead of the generic player ledger")
    assert_equal(1, presentationContextCalls, "the Officer route should create one presentation context")
    assert_equal(1, tokenResolutions,
      "an Officer page render should build the theme token snapshot once and share it across its widgets")
    local player = dibs.PlayerUI.Show()
    assert_not_nil(player)
    dibs.PlayerUI.GetSummary(nil, nil, {
      includeAcquisitions = false, includeEligibility = false, includeModePolicy = false,
    })
    dibs.PlayerUI.GetViewModel(nil, nil, nil, { includeHistory = false })
    dibs.PlayerUI.GetViewModel(nil, nil, nil, {
      includeHistory = false, pagePreDibHistory = 1,
    })
    dibs.PlayerUI.GetViewModel(nil, nil, nil, {
      includeHistory = false, pagePreDibHistory = 1,
    })
    dibs.PlayerUI.GetHistoryViewModel(nil, nil, nil, 1, 20)
    player.playerTab = "requests"
    player:Refresh()

    local byKey = {}
    for _, row in ipairs(dibs.UIRenderStats.GetReport().pages) do
      byKey[row.kind .. ":" .. row.page] = row
    end
    assert_equal(1, byKey["Officer:overview"].count)
    assert_equal(1, byKey["Officer:ranks"].count)
    assert_true(byKey["AceConfig:RCLootCouncil"] ~= nil,
      "AceConfig page rendering should be measured separately from the Officer route")
    assert_true(byKey["Player:my-dibs"] ~= nil,
      "PlayerUI.Show should record the active Player page render")
    assert_equal(1, byKey["Player:my-dibs"].count)
    assert_true(byKey["Player data:summary"] ~= nil,
      "Player summary computation should be timed separately")
    assert_true(byKey["Player data:view-model"] ~= nil,
      "Player view-model computation should be timed separately")
    assert_true(byKey["Player data:history-view-model"] ~= nil,
      "Player history computation should be timed separately")
    assert_true(byKey["Player data:predib-history"] ~= nil,
      "Pre-Dibs history projection should be timed separately")
    assert_true(byKey["Player data:predib-page-hit"] ~= nil,
      "repeated Player page renders should report a bounded page-cache hit")
    assert_true(byKey["Player data:predib-ui-summary-hit"] ~= nil,
      "repeated Player page renders should report a UI request-summary cache hit")
    assert_true(byKey["Pre-Dibs data:history-index-hit"] ~= nil,
      "Pre-Dibs lookup should report whether its revisioned history index was reused")
    assert_true(byKey["Player data:report-transactions"] ~= nil,
      "Report transaction choices should be timed separately")
    assert_true(byKey["Player data:report-history-choices"] ~= nil,
      "Report history choices should be timed separately")
    assert_true(byKey["Player data:report-transaction-labels"] ~= nil,
      "Report transaction labels should be timed separately")
    assert_true(byKey["Player data:request-list"] ~= nil,
      "Request projection should be timed separately")
    assert_true(byKey["Player UI:clear"] ~= nil,
      "Player page widget release should be timed separately")
    assert_true(byKey["Player UI:layout-flush"] ~= nil,
      "Player page layout flush should be timed separately")
    local tableRoute
    for _, row in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if row.kind == "UI table" and row.page:match("/add%-table$") then
        tableRoute = row.page:match("^(.-)/add%-table$")
        break
      end
    end
    assert_not_nil(tableRoute, "table construction should be attributed to its active UI route")
    assert_true(byKey["UI table:" .. tableRoute .. "-table-header-cells"] ~= nil,
      "table header construction should be attributed to the route that built it")
    assert_true(byKey["UI widget:Officer/overview"] ~= nil,
      "Officer widget construction should be attributed to its active page")
    assert_true(byKey["UI theme:render-token-context"] ~= nil,
      "Officer page rendering should measure its single theme-token snapshot")
    assert_true(byKey["UI widget:Player/my-dibs"] ~= nil,
      "Player widget construction should be attributed to its active page")
    assert_true(byKey["Officer data:dashboard"] ~= nil,
      "Officer dashboard projection should be timed separately")
    assert_true(byKey["Officer data:season-statistics"] ~= nil,
      "Officer season statistics should be timed separately")

    dibs.HandleSlashCommand("perf report")
    local printed = table.concat(messages, "\n")
    assert_true(printed:find("Officer / overview: count=1", 1, true) ~= nil)
    assert_true(printed:find("total=", 1, true) ~= nil)
    assert_true(printed:find("Player / my-dibs: count=1", 1, true) ~= nil)
    messages = {}
    dibs.HandleSlashCommand("perf report rank")
    printed = table.concat(messages, "\n")
    assert_true(printed:find("Officer / ranks: count=1", 1, true) ~= nil)
    assert_true(printed:find("Player / my-dibs", 1, true) == nil)
    dibs.HandleSlashCommand("perf off")
    assert_false(dibs.UIRenderStats.IsEnabled())
  end)
end)
