local loader = require("helpers.load_addon")

describe("B12b responsive page contract", function()
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
