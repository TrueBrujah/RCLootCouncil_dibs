local loader = require("helpers.load_addon")

local function containsText(widget, text)
  if type(widget) ~= "table" then return false end
  if tostring(widget.text or ""):find(text, 1, true) or tostring(widget._dibsText or ""):find(text, 1, true)
    or tostring(widget.label or ""):find(text, 1, true) or tostring(widget.title or ""):find(text, 1, true) then return true end
  for _, child in ipairs(widget.children or {}) do
    if containsText(child, text) then return true end
  end
  return false
end

local function findWidget(widget, kind, text)
  if type(widget) ~= "table" then return nil end
  if widget.kind == kind and (tostring(widget.text or ""):find(text, 1, true)
    or tostring(widget._dibsText or ""):find(text, 1, true) or tostring(widget.label or ""):find(text, 1, true)
    or tostring(widget.title or ""):find(text, 1, true)) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findWidget(child, kind, text)
    if found then return found end
  end
  return nil
end

local function findLabeledWidget(widget, kind, label)
  if type(widget) ~= "table" then return nil end
  if widget.kind == kind and widget.label == label then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findLabeledWidget(child, kind, label)
    if found then return found end
  end
  return nil
end

local function findFormControl(widget, label, kind)
  if type(widget) ~= "table" then return nil end
  if widget.kind == "SimpleGroup" and containsText(widget, label) then
    return findWidget(widget, kind, "") or findWidget(widget, kind, label)
  end
  for _, child in ipairs(widget.children or {}) do
    local found = findFormControl(child, label, kind)
    if found then return found end
  end
  return nil
end

local function findFormRow(widget, label)
  if type(widget) ~= "table" then return nil end
  for _, child in ipairs(widget.children or {}) do
    local found = findFormRow(child, label)
    if found then return found end
  end
  if widget.kind == "SimpleGroup" and containsText(widget, label) then return widget end
  return nil
end

local function countKind(widget, kind)
  if type(widget) ~= "table" then return 0 end
  local count = widget.kind == kind and 1 or 0
  for _, child in ipairs(widget.children or {}) do count = count + countKind(child, kind) end
  return count
end

local function countExactText(widget, text)
  if type(widget) ~= "table" then return 0 end
  local count = (widget.text == text or widget._dibsText == text or widget.label == text) and 1 or 0
  for _, child in ipairs(widget.children or {}) do count = count + countExactText(child, text) end
  return count
end

local function latestFrame(width)
  local found
  for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
    if widget.kind == "Frame" and widget.layout and widget.layout.width == width then found = widget end
  end
  return found
end

local function latestButton(text)
  local found
  for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
    if widget.kind == "Button" and widget.text == text then found = widget end
  end
  return found
end

local function installRequest(dibs)
  local request = {
    requestId = "ui003-request",
    status = "Under review",
    category = "wrong_item_player",
    categoryLabel = "Wrong item or player",
    note = "The awarded item does not match the request.",
    player = { name = "Huudada-Durotan" },
    evidence = { {
      item = "[Item 19019]",
      itemID = 19019,
      source = "rclootcouncil",
      integrationStatus = "available",
      integrationReason = "none",
      transactionRef = "tx-1",
      unavailableFields = { "award history" },
    } },
  }
  dibs.Disputes.ListForOfficer = function() return { request } end
  dibs.Disputes.GetRequest = function() return request end
  dibs.Disputes.GetTimeline = function() return {
    { timestamp = "2026-09-13", actorName = "Officer-Realm", action = "created", reason = "Player report" },
    { timestamp = "2026-09-13", actorName = "Officer-Realm", action = "under_review", reason = "Checking evidence" },
  } end
  return request
end

describe("B11 Retail UI-003", function()
  it("uses a compact independent request detail workflow", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame:Refresh()
    assert_false(containsText(frame.contentHost, "Show technical details"))
    assert_true(frame.OpenRequestDetail(request))
    local detail = frame.requestDetailShell
    assert_not_nil(detail)
    assert_equal(600, detail.layout.width)
    assert_equal(430, detail.layout.height)
    assert_true(detail.layout.width ~= frame.dibsAceGUIShell.layout.width)
    assert_true(containsText(frame.requestDetailRoot, "Player"))
    assert_true(containsText(frame.requestDetailRoot, "Huudada-Durotan"))
    assert_true(containsText(frame.requestDetailRoot, "Issue"))
    assert_true(containsText(frame.requestDetailRoot, "Wrong player/item"))
    assert_false(containsText(frame.requestDetailRoot, "Question or resolution note"))
    assert_false(containsText(frame.requestDetailRoot, "Request ID"))
    assert_false(containsText(frame.requestDetailRoot, "Correct player / item"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Ask for information"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Resolve"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Reject"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Advanced Officer Tools"))
    assert_false(containsText(frame.requestDetailRoot, "Evidence source"))

    local sameDetail = frame.requestDetailShell
    frame.OpenRequestDetail(request)
    assert_true(frame.requestDetailShell == sameDetail)
    frame.CloseRequestDetail()
    assert_false(frame.disputeDetailOpen)
    assert_true(containsText(frame.contentHost, "Huudada-Durotan"))
  end)

  it("presents a simple request summary and keeps advanced details collapsed", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame:Refresh()
    assert_true(containsText(frame.contentHost, "Huudada-Durotan"))
    assert_false(containsText(frame.contentHost, "Show technical details"))
    assert_false(containsText(frame.contentHost, "Correct item or player"))
    assert_false(containsText(frame.contentHost, "Refund Dib"))
  end)

  it("uses one accounting window with a fixed footer and action selector", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame.disputeAdvancedExpanded = true
    assert_true(frame.OpenRequestDetail(request))
    local adjust = findWidget(frame.requestDetailRoot, "Button", "Adjust Dibs")
    assert_not_nil(adjust)
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Refund Dib"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Revoke Dib"))
    adjust.callbacks.OnClick(adjust, "OnClick")
    local accountingWindow
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Frame" and widget.layout and widget.layout.width == 540 then accountingWindow = widget end
    end
    assert_not_nil(accountingWindow)
    assert_equal(460, accountingWindow.layout.height)
    assert_not_nil(findFormControl(accountingWindow, "Action", "Dropdown"))
    assert_not_nil(findWidget(accountingWindow, "Button", "Review"))
  end)

  it("reserves non-overlapping form rows and keeps Review edit-free", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame.disputeAdvancedExpanded = true
    frame.OpenRequestDetail(request)
    local adjust = findWidget(frame.requestDetailRoot, "Button", "Adjust Dibs")
    adjust.callbacks.OnClick(adjust, "OnClick")
    local accountingWindow = latestFrame(540)
    local playerRow = findFormRow(accountingWindow, "Player")
    local actionRow = findFormRow(accountingWindow, "Action")
    local balanceRow = findFormRow(accountingWindow, "Current balance")
    local amountRow = findFormRow(accountingWindow, "Amount")
    local changeRow = findFormRow(accountingWindow, "Change")
    local resultRow = findFormRow(accountingWindow, "Result")
    local reasonRow = findFormRow(accountingWindow, "Reason")
    assert_true(playerRow.height >= 28)
    assert_true(actionRow.height >= 50)
    assert_true(balanceRow.height >= 24)
    assert_true(amountRow.height >= 50)
    assert_true(changeRow.height >= 24)
    assert_true(resultRow.height >= 24)
    assert_true(reasonRow.height >= 100)
    assert_true(countKind(reasonRow, "MultiLineEditBox") + countKind(reasonRow, "EditBox") > 0)
    assert_true(countKind(accountingWindow, "CheckBox") > 0)
    assert_true(countKind(accountingWindow, "Button") > 0)

    local amount = findFormControl(accountingWindow, "Amount", "EditBox")
    local reason = findFormControl(accountingWindow, "Reason", "MultiLineEditBox")
    local acknowledgement = findLabeledWidget(accountingWindow, "CheckBox", "I understand this changes recorded Dibs data")
    amount.callbacks.OnTextChanged(amount, "OnTextChanged", "2")
    reason.callbacks.OnTextChanged(reason, "OnTextChanged", "layout regression")
    acknowledgement.callbacks.OnValueChanged(acknowledgement, "OnValueChanged", true)
    local review = findWidget(accountingWindow, "Button", "Review")
    review.callbacks.OnClick(review, "OnClick")
    local reviewWindow = latestFrame(540)
    assert_equal(0, countKind(reviewWindow, "EditBox") + countKind(reviewWindow, "MultiLineEditBox"))
    assert_not_nil(findWidget(reviewWindow, "Button", "Confirm action"))
    local back = findWidget(reviewWindow, "Button", "Back")
    back.callbacks.OnClick(back, "OnClick")
    local editWindow = latestFrame(540)
    assert_equal(false, frame.requestAccountingReview)
    assert_not_nil(findFormRow(editWindow, "Reason"))
    assert_equal(1, countKind(editWindow, "MultiLineEditBox"))
    back = nil
    local reviewAgain = findWidget(editWindow, "Button", "Review")
    reviewAgain.callbacks.OnClick(reviewAgain, "OnClick")
    local reviewAgainWindow = latestFrame(540)
    assert_equal(0, countKind(reviewAgainWindow, "EditBox") + countKind(reviewAgainWindow, "MultiLineEditBox"))
  end)

  it("removes legacy Accept controls and keeps summary labels separate from values", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame.disputeAdvancedExpanded = true
    frame.OpenRequestDetail(request)
    findWidget(frame.requestDetailRoot, "Button", "Adjust Dibs").callbacks.OnClick()
    local editWindow = latestFrame(540)
    assert_equal(1, countExactText(editWindow, "Reason"))
    assert_equal(1, countKind(findFormRow(editWindow, "Reason"), "MultiLineEditBox"))
    assert_equal(0, countExactText(editWindow, "Accept"))
    assert_nil(findWidget(editWindow, "Button", "Accept"))
    assert_equal(1, countExactText(editWindow, "Change"))
    assert_equal(1, countExactText(editWindow, "Result"))

    local amount = findFormControl(editWindow, "Amount", "EditBox")
    local reason = findFormControl(editWindow, "Reason", "MultiLineEditBox")
    local acknowledgement = findLabeledWidget(editWindow, "CheckBox", "I understand this changes recorded Dibs data")
    amount.callbacks.OnTextChanged(amount, "OnTextChanged", "2")
    reason.callbacks.OnTextChanged(reason, "OnTextChanged", "single owner")
    acknowledgement.callbacks.OnValueChanged(acknowledgement, "OnValueChanged", true)
    local changeRow = findFormRow(editWindow, "Change")
    local resultRow = findFormRow(editWindow, "Result")
    assert_not_nil(findWidget(changeRow, "Label", "+2"))
    assert_not_nil(findWidget(resultRow, "Label", "2"))
    assert_nil(findWidget(changeRow, "Label", "Change\n+2"))
    assert_nil(findWidget(resultRow, "Label", "Result\n2"))

    findWidget(editWindow, "Button", "Review").callbacks.OnClick()
    local reviewWindow = latestFrame(540)
    assert_equal(0, countExactText(reviewWindow, "Accept"))
    assert_nil(findWidget(reviewWindow, "Button", "Accept"))
    local back = findWidget(reviewWindow, "Button", "Back")
    back.callbacks.OnClick()
    local restored = latestFrame(540)
    assert_equal(0, countExactText(restored, "Accept"))
    assert_equal(1, countKind(findFormRow(restored, "Reason"), "MultiLineEditBox"))
  end)

  it("commits Confirm action once and keeps the original history append-only", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local season = dibs.Seasons.GetCurrent()
    local stored = dibs.Ledger.AddTransaction({
      transactionId = "ui003-accounting-source", playerName = "Tester-Realm", amount = -1,
      type = "DIB_USED", reason = "Original event", source = "test", seasonId = season.id,
    })
    local historyBefore = #dibs.Ledger.GetHistory("Tester-Realm", season.id)
    local request = dibs.Disputes.CreateReport({ category = "wrong_debit", transactionRef = stored.transactionId })
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame.disputeAdvancedExpanded = true
    assert_true(frame.OpenRequestDetail(request))
    local adjust = findWidget(frame.requestDetailRoot, "Button", "Adjust Dibs")
    adjust.callbacks.OnClick(adjust)
    local accountingWindow
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Frame" and widget.layout and widget.layout.width == 540 then accountingWindow = widget end
    end
    local amount = findFormControl(accountingWindow, "Amount", "EditBox")
    local reason = findFormControl(accountingWindow, "Reason", "MultiLineEditBox") or findFormControl(accountingWindow, "Reason", "EditBox")
    local acknowledgement = findFormControl(accountingWindow, "", "CheckBox") or findLabeledWidget(accountingWindow, "CheckBox", "I understand this changes recorded Dibs data")
    amount.callbacks.OnTextChanged(amount, "OnTextChanged", "2")
    reason.callbacks.OnTextChanged(reason, "OnTextChanged", "Verified correction")
    acknowledgement.callbacks.OnValueChanged(acknowledgement, "OnValueChanged", true)
    assert_equal("2", frame.requestAccountingDraft.amount)
    assert_equal("Verified correction", frame.requestAccountingDraft.reason)
    assert_true(frame.requestAccountingDraft.acknowledged)
    local review = findWidget(accountingWindow, "Button", "Review")
    review.callbacks.OnClick(review)
    assert_true(frame.requestAccountingReview == true)
    local confirm = latestButton("Confirm action")
    assert_not_nil(confirm)
    confirm.callbacks.OnClick(confirm)
    confirm.callbacks.OnClick(confirm)
    local history = dibs.Ledger.GetHistory("Tester-Realm", season.id)
    assert_equal(historyBefore + 1, #history)
    assert_equal(2, history[#history].amount)
  end)

  it("keeps right-click actions safe and separates dangerous actions behind confirmation", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local request = installRequest(dibs)
    local originalAddTable = dibs.AceGUI.AddTable
    local tableOptions
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if options and options.contextMenu then tableOptions = options end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame:Refresh()
    assert_not_nil(tableOptions)
    local menu = tableOptions.contextMenu({ request = request })
    local menuText = {}
    for _, entry in ipairs(menu or {}) do menuText[entry.text] = true end
    assert_true(menuText["Open request"])
    assert_true(menuText["View player Dibs"])
    assert_true(menuText["Copy Name-Realm"])
    assert_true(not menuText["Refund Dib"])
    assert_true(not menuText["Correct balance"])

    assert_false(containsText(frame.contentHost, "Correct balance"))
  end)

  it("does not expose GM-only administrative adjustment to an Officer", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildRankIndices = { [1] = 1 } }, withAce3 = true })
    local request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame:Refresh()
    assert_false(containsText(frame.contentHost, "Admin adjustment"))
  end)

  it("keeps Debug focused on debug controls across route transitions", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.DeveloperMode.SetEnabled(true)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("disputes")
    frame.SelectTab("debug")
    assert_not_nil(frame.debugControls.all)
    assert_not_nil(frame.debugControls.announce)
    assert_not_nil(frame.debugControls.sync)
    assert_not_nil(frame.debugControls.ui)
    assert_not_nil(frame.debugControls.encounter_journal)
    assert_not_nil(frame.debugLogsButton)
    assert_not_nil(frame.debugReportButton)
    local openedBy
    dibs.DebugLogs = { Open = function(actor) openedBy = actor; return true end }
    frame.debugLogsButton.callbacks.OnClick(frame.debugLogsButton, "OnClick")
    assert_equal(dibs.GetPlayerName(), openedBy)
    assert_false(containsText(frame.contentHost, "Officer review requests"))
    assert_false(containsText(frame.contentHost, "History reconciliation"))
    frame.SelectTab("eligibility")
    frame.SelectTab("debug")
    assert_not_nil(frame.debugControls.all)
    assert_false(containsText(frame.contentHost, "Protected loot eligibility"))
    assert_false(containsText(frame.contentHost, "Selected request"))
  end)
end)
