local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("audit runtime and shared UI regressions", function()
  it("receives PLAYER_LOGIN when AceEvent is unavailable", function()
    local _, dibs = loader.load({ savedVariables = {}, withLibStub = false, skipInitialize = true })
    assert_nil(dibs.initialized)
    wow.dispatch("PLAYER_LOGIN")
    assert_true(dibs.initialized == true)
  end)

  it("receives PLAYER_LOGIN when AceEvent embedding fails", function()
    local _, dibs = loader.load({ savedVariables = {}, skipInitialize = true,
      libStub = function(name)
        if name == "AceEvent-3.0" then return { Embed = function() error("embed failure") end } end
      end })
    assert_nil(dibs.initialized)
    wow.dispatch("PLAYER_LOGIN")
    assert_true(dibs.initialized == true)
  end)

  it("retains every distinct event consumer and isolates a failing listener", function()
    local _, dibs = loader.load({ withAce3 = true })
    local delivered = 0
    local listener = function() delivered = delivered + 1 end
    assert_true(dibs.Ace3.RegisterEvent("DIBS_AUDIT_SHARED", function() error("listener failed") end))
    assert_true(dibs.Ace3.RegisterEvent("DIBS_AUDIT_SHARED", listener))
    assert_true(dibs.Ace3.RegisterEvent("DIBS_AUDIT_SHARED", listener))
    assert_error(function() dibs.Ace3.libs.event.handlers.DIBS_AUDIT_SHARED("DIBS_AUDIT_SHARED") end)
    assert_equal(1, delivered, "duplicate registration must not duplicate delivery")
  end)

  it("sorts equivalent case and numeric keys with a stable strict order", function()
    local _, dibs = loader.load({ withAce3 = true })
    local shell = assert(dibs.AceGUI.CreateWindow("Audit sorting", 700, 400))
    local rows = {}
    for index = 1, 100 do rows[index] = { index % 2 == 0 and "ABC" or "abc", index } end
    local tableWidget = dibs.AceGUI.AddTable(shell, shell.window,
      { { title = "Name", width = 160 }, { title = "Index", width = 80 } }, rows, 180, nil,
      { noScrolling = true })
    local grid = assert(tableWidget._dibsDataGrid)
    assert_true(grid.Sort(1, "desc"))
    for index, row in ipairs(grid.rows) do assert_equal(index, row[2]) end
    for index, row in ipairs(rows) do row[1] = index % 2 == 0 and "02" or 2 end
    assert_true(grid.Sort(1, "asc"))
    for index, row in ipairs(grid.rows) do assert_equal(index, row[2]) end
    assert_true(grid.Sort(1, "desc"))
    for index, row in ipairs(grid.rows) do assert_equal(index, row[2]) end
    -- Mixed numeric and textual values must also form a total order.
    rows[1][1], rows[2][1], rows[3][1] = "2", "10", "10a"
    assert_true(grid.Sort(1, "asc"))
    assert_equal("10a", grid.rows[#grid.rows][1])
    assert_true(grid.Sort(1, "desc"))
    assert_equal("10a", grid.rows[1][1])
  end)

  it("fits unspecified fluid weights while retaining minima and fixed widths", function()
    local _, dibs = loader.load({ withAce3 = true })
    local columns = { { width = 400, minWidth = 100 }, { width = 400, minWidth = 100 },
      { width = 100, minWidth = 100, fixed = true } }
    local widths, overflow, used = dibs.AceGUI.AllocateFluidColumnWidths(columns, 502)
    assert_false(overflow)
    assert_true(math.abs(502 - used) < 0.01)
    assert_true(math.abs(502 - widths[1] - widths[2] - widths[3]) < 0.01)
    assert_equal(100, widths[3])
    local _, narrowOverflow, narrowUsed = dibs.AceGUI.AllocateFluidColumnWidths(columns, 250)
    assert_true(narrowOverflow)
    assert_equal(300, narrowUsed)
    local _, fixedOverflow, fixedUsed = dibs.AceGUI.AllocateFluidColumnWidths({
      { width = 100, fixed = true }, { width = 100, fixed = true } }, 500)
    assert_false(fixedOverflow)
    assert_equal(200, fixedUsed)
    assert_equal(300, dibs.AceGUI.GetFluidColumnMinimumWidth(columns))
  end)
end)
