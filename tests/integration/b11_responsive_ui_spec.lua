local loader = require("helpers.load_addon")

describe("B11g responsive layout", function()
  it("derives supported window bounds from Midnight and clamps undersized windows", function()
    local _, dibs = loader.load({ withAce3 = true })
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    assert_true(metrics.minWidth >= 520)
    assert_true(metrics.minHeight >= 360)
    assert_true(metrics.maxWidth >= metrics.minWidth)
    assert_true(metrics.maxHeight >= metrics.minHeight)

    local shell = dibs.AceGUI.CreateWindow("Responsive", 100, 100)
    assert_not_nil(shell)
    assert_equal(metrics.minWidth, shell.layout.width)
    assert_equal(metrics.minHeight, shell.layout.height)
    assert_equal(metrics.minWidth, shell.layout.minWidth)
    assert_equal(metrics.minHeight, shell.layout.minHeight)
  end)

  it("keeps the primary action column usable when a table becomes narrow", function()
    local _, dibs = loader.load()
    local widths, overflow = dibs.AceGUI.FitColumnWidths({
      { title = "Player", width = 220, minWidth = 120, priority = 5 },
      { title = "Technical details", width = 320, minWidth = 64, priority = 1 },
      { title = "Action", width = 100, minWidth = 88, priority = 100, action = true },
    }, 300)
    assert_true(widths[3] >= 88)
    assert_true(widths[1] >= 120)
    assert_true(overflow == true or widths[1] + widths[2] + widths[3] <= 300)
  end)

  it("keeps full values available when visible text is truncated", function()
    local _, dibs = loader.load()
    local visible, truncated, full = dibs.Midnight.Truncate("Very long Name-Realm / item value", 16)
    assert_true(truncated)
    assert_equal("Very long Nam...", visible)
    assert_equal("Very long Name-Realm / item value", full)
  end)
end)
