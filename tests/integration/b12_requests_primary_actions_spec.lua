local loader = require("helpers.load_addon")

local function findWidget(widget, kind, text)
  if type(widget) ~= "table" then return nil end
  if widget.kind == kind and (widget.text == text or widget.label == text or widget.title == text) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findWidget(child, kind, text)
    if found then return found end
  end
  return nil
end

local function findLatestWidget(kind, text)
  local widgets = _G.__dibsAceWidgets or {}
  for index = #widgets, 1, -1 do
    local found = findWidget(widgets[index], kind, text)
    if found then return found end
  end
  return nil
end

local function findLatestKind(kind)
  local widgets = _G.__dibsAceWidgets or {}
  for index = #widgets, 1, -1 do
    local found = findWidget(widgets[index], kind, nil)
    if found and found.kind == kind then return found end
  end
  return nil
end

describe("B12 request primary actions", function()
  local function exercise(action, fieldLabel, confirmLabel, value)
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1" } },
      withAce3 = true,
    })
    local request = {
      requestId = "b12-primary-" .. action,
      status = "Open",
      category = "other",
      categoryLabel = "Other",
      player = { name = "Player-1" },
      evidence = { { item = "Midnight Blade", source = "Dibs ledger" } },
    }
    local captured
    dibs.Disputes.Resolve = function(requestId, resolvedAction, options)
      captured = { requestId = requestId, action = resolvedAction, options = options }
      return { ok = true, request = request }
    end
    dibs.Disputes.GetRequest = function() return request end

    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(request))
    local primary = findWidget(frame.requestDetailRoot, "Button", action == "ask_information" and "Ask for information" or action == "no_correction" and "Resolve" or "Reject")
    assert_not_nil(primary)
    primary.callbacks.OnClick(primary, "OnClick")

    local editor = findLatestKind("MultiLineEditBox") or findLatestKind("EditBox")
    assert_not_nil(editor)
    editor.callbacks.OnTextChanged(editor, "OnTextChanged", value)
    local review = findLatestWidget("Button", "Review")
    assert_not_nil(review)
    review.callbacks.OnClick(review, "OnClick")
    local confirm = findLatestWidget("Button", confirmLabel)
    assert_not_nil(confirm)
    confirm.callbacks.OnClick(confirm, "OnClick")

    assert_not_nil(captured)
    assert_equal(request.requestId, captured.requestId)
    assert_equal(action, captured.action)
    if action == "ask_information" then
      assert_equal(value, captured.options.question)
    else
      assert_equal(value, captured.options.reason)
    end
  end

  it("routes Ask for information through the existing dispute transition", function()
    exercise("ask_information", "Message / question", "Confirm question", "Which raid was this?")
  end)

  it("routes Resolve through the existing dispute transition", function()
    exercise("no_correction", "Resolution note", "Confirm resolve", "Evidence reviewed")
  end)

  it("routes Reject through the existing dispute transition", function()
    exercise("reject", "Reason", "Confirm reject", "Evidence does not support the report")
  end)
end)
