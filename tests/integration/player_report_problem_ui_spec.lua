local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

local function findWidget(widget, predicate)
  if type(widget) ~= "table" then return nil end
  if predicate(widget) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findWidget(child, predicate)
    if found then return found end
  end
  return nil
end

local function byKind(kind, field, value)
  return function(widget)
    return widget.kind == kind and tostring(widget[field] or "") == value
  end
end

describe("Player Requests problem report", function()
  local function setup()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local season = dibs.Seasons.GetCurrent()
    local tx = dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", season.id, { transactionId = "tx-report-ui" }))
    return dibs, season, tx
  end

  it("keeps Pre-Dibs on My Dibs and shows only the report form on Reports", function()
    local dibs, season, tx = setup()
    local active = assert(dibs.PreDibs.Create("Tester-Realm", 19019, "Still Wanted", season.id))
    local cancelled = assert(dibs.PreDibs.Create("Tester-Realm", 19020, "Changed Mind", season.id))
    dibs.PreDibs.Cancel(cancelled.requestId)
    assert_not_nil(active)
    local tables = {}
    local addTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, ...)
      tables[#tables + 1] = { columns = columns, rows = rows }
      return addTable(shell, parent, columns, rows, ...)
    end
    local function tableContaining(text)
      for index = #tables, 1, -1 do
        for _, row in ipairs(tables[index].rows or {}) do
          for _, cell in ipairs(row) do
            if tostring(cell):find(text, 1, true) then return tables[index] end
          end
        end
      end
      return nil
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame:Refresh()
    local function hasText(root, text)
      return findWidget(root, function(widget)
        return tostring(widget.title or widget.text or ""):find(text, 1, true) ~= nil
      end) ~= nil
    end
    assert_true(hasText(frame.aceTabs, "Active Pre-Dibs"))
    assert_true(hasText(frame.aceTabs, "Past Pre-Dibs"))
    local activeTable = tableContaining("Still Wanted")
    assert_equal("Action", activeTable.columns[5].title)
    for _, row in ipairs(activeTable.rows) do assert_true(tostring(row[2]):find("Changed Mind", 1, true) == nil) end
    local past = tableContaining("Changed Mind")
    assert_not_nil(past)
    assert_equal(3, #past.columns)
    assert_true(past.rows[1][1] ~= "Unknown" and past.rows[1][1] ~= "")
    tables = {}
    frame.SelectTab("requests")
    local root = frame.aceTabs
    assert_false(hasText(root, "Active Pre-Dibs"))
    assert_false(hasText(root, "Past Pre-Dibs"))
    assert_nil(tableContaining("Changed Mind"))
    assert_nil(tableContaining("Still Wanted"))
    assert_true(hasText(root, "No review requests yet."))
    local category = findWidget(root, byKind("Dropdown", "label", "Problem type"))
    local transaction = findWidget(root, byKind("Dropdown", "label", "Related ledger entry (optional)"))
    local note = findWidget(root, byKind("EditBox", "label", "What should an Officer review?"))
    local submit = findWidget(root, byKind("Button", "text", "Submit report"))
    assert_not_nil(category)
    assert_not_nil(transaction)
    assert_not_nil(note)
    assert_not_nil(submit)
    assert_not_nil(transaction.list[tx.transactionId])
    assert_not_nil(category.list.wrong_debit)
    assert_not_nil(category.list.wrong_item_player)

    local balanceBefore = dibs.Ledger.GetBalance("Tester-Realm", season.id)
    local historyBefore = #dibs.Ledger.GetHistory("Tester-Realm", season.id)
    category.callbacks.OnValueChanged(category, "OnValueChanged", "wrong_debit")
    transaction.callbacks.OnValueChanged(transaction, "OnValueChanged", tx.transactionId)
    note.callbacks.OnTextChanged(note, "OnTextChanged", "A Dib was removed but I received nothing.")
    submit.callbacks.OnClick(submit, "OnClick")

    local requests = dibs.Disputes.ListForPlayer("Tester-Realm")
    assert_equal(1, #requests)
    assert_equal("wrong_debit", requests[1].category)
    local stored = dibs.GetDB().disputes.requests[requests[1].requestId]
    assert_not_nil(stored)
    assert_equal(tx.transactionId, stored.evidence[1].transactionRef)
    assert_equal(balanceBefore, dibs.Ledger.GetBalance("Tester-Realm", season.id))
    assert_equal(historyBefore, #dibs.Ledger.GetHistory("Tester-Realm", season.id))
    assert_equal(requests[1].requestId, frame.selectedDisputeRequestId)
    assert_not_nil(frame.disputeDetailTitle)
    assert_not_nil(findWidget(frame.aceTabs, byKind("Button", "text", "View")))
  end)

  it("opens the report form preselected from a History entry", function()
    local dibs, _, tx = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("history")
    local entry
    for _, candidate in ipairs(dibs.PlayerUI.GetViewModel().history or {}) do
      if candidate.transactionId == tx.transactionId then entry = candidate end
    end
    assert_not_nil(entry)
    frame.historyDetail = entry
    frame:Refresh()
    assert_not_nil(frame.historyReportButton)
    frame.historyReportButton.callbacks.OnClick(frame.historyReportButton, "OnClick")
    assert_equal("requests", frame.playerTab)
    assert_nil(frame.historyDetail)
    local transaction = findWidget(frame.aceTabs, byKind("Dropdown", "label", "Related ledger entry (optional)"))
    assert_not_nil(transaction)
    assert_equal(tx.transactionId, transaction.value)
  end)
end)
