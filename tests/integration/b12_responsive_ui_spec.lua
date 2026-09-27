local loader = require("helpers.load_addon")

describe("B12b responsive page contract", function()
  it("allocates weighted fluid columns while reserving fixed UI space", function()
    local _, dibs = loader.load({ withAce3 = true })
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    local columns = {
      { title = "Player", width = 200, minWidth = 160, weight = 4 },
      { title = "Guild Rank", width = 130, minWidth = 110, weight = 2 },
      { title = "Expected", width = 54, minWidth = 54, fixed = true },
      { title = "Assigned", width = 54, minWidth = 54, fixed = true },
      { title = "Difference", width = 64, minWidth = 64, fixed = true },
      { title = "Status", width = 160, minWidth = 100, weight = 3 },
      { title = "Action", width = metrics.actionMinWidth, minWidth = metrics.actionMinWidth, fixed = true },
    }
    local options = { horizontalPadding = 20, scrollbarReserve = 18, columnGap = 4 }
    local wide, wideOverflow, wideUsed = dibs.AceGUI.AllocateFluidColumnWidths(columns, 1040, options)
    assert_false(wideOverflow)
    assert_equal(metrics.actionMinWidth, wide[7])
    assert_true(wide[1] > wide[2])
    assert_true(wide[6] > wide[2])
    assert_true(math.abs(wideUsed - 1040) < 0.01)

    local medium, mediumOverflow = dibs.AceGUI.AllocateFluidColumnWidths(columns, 720, options)
    assert_false(mediumOverflow)
    assert_true(medium[1] >= 160)
    assert_true(medium[2] >= 110)
    assert_true(medium[6] >= 100)
    assert_equal(metrics.actionMinWidth, medium[7])

    local noScrollbar = dibs.AceGUI.AllocateFluidColumnWidths(columns, 720, {
      horizontalPadding = 20, scrollbarReserve = 0, columnGap = 4,
    })
    assert_true(noScrollbar[1] > medium[1])
    local tooNarrow, overflow = dibs.AceGUI.AllocateFluidColumnWidths(columns, 420, options)
    assert_true(overflow)
    assert_true(tooNarrow[1] >= 160)
    assert_true(tooNarrow[7] >= metrics.actionMinWidth)
  end)

  it("keeps narrow windows inside supported bounds and protects action columns", function()
    local _, dibs = loader.load({ withAce3 = true })
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    local shell = dibs.AceGUI.CreateWindow("B12 responsive", 320, 200)
    assert_not_nil(shell)
    assert_equal(metrics.minWidth, shell.layout.width)
    assert_equal(metrics.minHeight, shell.layout.height)

    local widths, overflow = dibs.AceGUI.FitColumnWidths({
      { title = "Player", width = 240, minWidth = 120, priority = 5 },
      { title = "Details", width = 360, minWidth = 64, priority = 1 },
      { title = "Review", width = 96, minWidth = metrics.actionMinWidth, priority = 100, action = true },
    }, 300)
    assert_true(widths[3] >= metrics.actionMinWidth)
    assert_true(widths[1] >= 120)
    assert_true(overflow == true or widths[1] + widths[2] + widths[3] <= 300)
  end)

  it("keeps long labels inspectable and status meaning independent of color", function()
    local _, dibs = loader.load({ withAce3 = true })
    local visible, truncated, full = dibs.Midnight.Truncate("Historical award recipient mismatch", 18)
    assert_true(truncated)
    assert_equal("Historical awar...", visible)
    assert_equal("Historical award recipient mismatch", full)

    local status = dibs.Midnight.GetStatePresentation("SYNC_BEHIND")
    assert_true(status.label ~= "")
    assert_true(status.marker ~= "")
    assert_true(status.explanation ~= "")
    assert_equal("warning", status.tone)
  end)

  it("keeps tooltips and undersized modals available through the shared adapter", function()
    local _, dibs = loader.load({ withAce3 = true })
    _G.GameTooltip = {
      SetOwner = function() end,
      SetText = function() end,
      AddLine = function() end,
      Show = function() end,
      Hide = function() end,
    }
    local shell = dibs.AceGUI.CreateWindow("B12 tooltip", 640, 480)
    local label = dibs.AceGUI.AddHeader(shell, shell.window, "Long field", "Full value and context")
    assert_not_nil(label)
    assert_not_nil(label.frame._scripts.OnEnter)
    assert_not_nil(label.frame._scripts.OnLeave)

    local modal = dibs.Midnight.AddModal(shell, "B12 modal", 280, 180)
    assert_not_nil(modal)
    assert_true(modal.layout.width >= dibs.Midnight.GetLayoutMetrics().minWidth)
    assert_true(modal.layout.height >= dibs.Midnight.GetLayoutMetrics().minHeight)
  end)
end)
