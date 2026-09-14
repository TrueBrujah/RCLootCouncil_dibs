local loader = require("helpers.load_addon")
local mocks = require("helpers.b11_ui_mocks")
local wow = require("helpers.wow_api")

describe("B12a shared UI ownership", function()
  after_each(function() mocks.clear() end)

  it("reuses and replaces one context menu, then closes it", function()
    local _, dibs = loader.load({ withAce3 = true })
    local state = mocks.installMSA()
    assert_true(dibs.AceGUI.ShowContextMenu({ { text = "One", callback = function() end } }))
    assert_true(dibs.AceGUI.ShowContextMenu({ { text = "Two", callback = function() end } }))
    assert_equal(1, state.created)
    assert_equal(2, state.initialized)
    dibs.AceGUI.HideContextMenu()
    dibs.AceGUI.HideContextMenu()
  end)

  it("keeps tooltip ordering, rejects raw parents, and detaches a scrolling table", function()
    local _, dibs = loader.load({ withAce3 = true })
    local calls = {}
    _G.GameTooltip = {
      SetOwner = function() end,
      SetText = function(_, ...) calls.text = { ... } end,
      SetHyperlink = function(_, value) calls.link = value end,
      Show = function() calls.shown = true end,
    }
    assert_true(dibs.AceGUI.ShowTableCellTooltip({}, "Unavailable"))
    assert_equal("Unavailable", calls.text[1])
    assert_equal(true, calls.text[6])
    local link = "|cffa335ee|Hitem:280001::::::::::::|h[Warden's Curio]|h|r"
    assert_true(dibs.AceGUI.ShowTableCellTooltip({}, link))
    assert_equal(link, calls.link)

    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    assert_nil(dibs.AceGUI.Create(shell, "SimpleGroup", _G.CreateFrame("Frame")))
    local tableLibrary = {
      SORT_ASC = 1, SORT_DSC = 2,
      CreateST = function(_, columns, _, _, _, parent)
        local frame = _G.CreateFrame("Frame", nil, parent)
        frame.ClearAllPoints = function() end
        local tableObject = {
          frame = frame, cols = columns,
          RegisterEvents = function(self, events) self.events = events end,
          SetDefaultHighlight = function() end, EnableSelection = function() end,
          SetDisplayCols = function() end, SetData = function() end, SortData = function() end,
          Show = function() end, Hide = function() end,
        }
        return tableObject
      end,
    }
    dibs.Ace3.libs.scrollingTable = tableLibrary
    local host = dibs.AceGUI.AddTable(shell, shell.window, { { title = "Status", width = 120 } }, { { "Ready" } }, 100, nil, { disableContextMenu = true })
    assert_not_nil(host)
    assert_not_nil(host._dibsScrollingTable)
    dibs.AceGUI.Clear(shell.window)
    assert_nil(host._dibsScrollingTable)
  end)

  it("releases native MSA dropdown labels with their pooled host", function()
    mocks.installMSA()
    local _, dibs = loader.load({ withAce3 = true })
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local dropdown = dibs.AceGUI.AddDropdown(shell, shell.window, "Officer pre-dib announce channel", { OFFICER = "Officer" }, function() end)
    assert_not_nil(dropdown)
    assert_not_nil(dropdown.host._dibsMSALabel)
    dibs.AceGUI.Clear(shell.window)
    assert_nil(dropdown.host._dibsMSALabel)
  end)

  it("compacts a pooled container before adding the next widget", function()
    local _, dibs = loader.load({ withAce3 = true })
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local parent = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    dibs.AceGUI.AddLabel(shell, parent, "First", true)
    dibs.AceGUI.AddLabel(shell, parent, "Second", true)
    parent.children[1] = nil
    local ok, heading = pcall(dibs.AceGUI.AddHeading, shell, parent, "Next", "After a pooled release.")
    assert_true(ok)
    assert_not_nil(heading)
    for index = 1, #parent.children do assert_not_nil(parent.children[index]) end
  end)

  it("coalesces refreshes and flushes them after combat", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { inCombat = true } })
    local calls = 0
    assert_false(dibs.AceGUI.RequestRefresh("b12a", function() calls = calls + 1 end))
    assert_false(dibs.AceGUI.RequestRefresh("b12a", function() calls = calls + 1 end))
    assert_equal(0, calls)
    wow.setCombat(false)
    assert_true(dibs.AceGUI.FlushRefreshes())
    assert_equal(2, calls)
  end)
end)
