local loader = require("helpers.load_addon")

local function widgetAfter(start, property, value)
  local widgets = _G.__dibsAceWidgets or {}
  for index = #widgets, start + 1, -1 do
    local candidate = widgets[index]
    if candidate[property] == value then return candidate end
  end
end

local function click(widget)
  assert_not_nil(widget)
  assert_not_nil(widget.callbacks and widget.callbacks.OnClick)
  widget.callbacks.OnClick(widget)
end

describe("Data backup and transfer recovery boundaries in UI", function()
  it("distinguishes retained historical backup export from current-state export", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true, locale = "frFR" } })
    local labels = {}
    local addLabel = dibs.AceGUI.AddLabel
    dibs.AceGUI.AddLabel = function(shell, parent, text, ...)
      labels[text] = true
      return addLabel(shell, parent, text, ...)
    end
    dibs.DataUI.Open("backups")
    assert_true(labels[dibs.L.DATA_BACKUP_LOCAL_STORAGE])
    dibs.DataUI.Open("transfer")
    assert_true(labels[dibs.L.DATA_EXPORT_CURRENT_STATE])
  end)

  it("shows the compatibility-only recovery boundary in the actual full import preview", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local text = assert(dibs.ImportExport.Export("full"))
    local captured = {}
    local addProperty = dibs.AceGUI.AddPropertyTable
    dibs.AceGUI.AddPropertyTable = function(shell, parent, rows, ...)
      for _, row in ipairs(rows) do captured[row[1]] = row[2] end
      return addProperty(shell, parent, rows, ...)
    end
    dibs.DataUI.Open("transfer")
    local box = widgetAfter(0, "label", "Paste package to import")
    assert_not_nil(box)
    box.callbacks.OnTextChanged(box, "OnTextChanged", text)
    local scope = widgetAfter(0, "label", "Import scope")
    scope.callbacks.OnValueChanged(scope, "OnValueChanged", "full")
    local strategy = widgetAfter(0, "label", "Import strategy")
    strategy.callbacks.OnValueChanged(strategy, "OnValueChanged", "append")
    local before = #dibs.Ledger.GetAllTransactions()
    click(widgetAfter(0, "text", "Validate and preview"))
    assert_equal(dibs.L.DATA_FULL_IMPORT_LIMIT, captured[dibs.L.DATA_IMPORT_RECOVERY_BEHAVIOR])
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("discards missing restore previews from the visible UI rather than offering confirmation", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    dibs.DataUI.Open("backups")
    click(widgetAfter(0, "text", "Create backup"))
    click(widgetAfter(0, "text", "Preview restore"))
    assert_not_nil(next(dibs.GetDB().pendingRestores))
    dibs.GetDB().pendingRestores = {}
    local start = #(_G.__dibsAceWidgets or {})
    dibs.DataUI.Refresh()
    assert_not_nil(widgetAfter(start, "text", dibs.L.DATA_PREVIEW_UNAVAILABLE))
    assert_nil(widgetAfter(start, "text", "Confirm restore"))
  end)
end)
