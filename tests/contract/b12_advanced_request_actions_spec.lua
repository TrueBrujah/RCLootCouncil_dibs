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

describe("B12 advanced request actions", function()
  local function request()
    return {
      requestId = "b12-advanced-1",
      status = "Open",
      category = "missing_debit",
      categoryLabel = "Missing Dib",
      player = { name = "Player-1" },
      evidence = { { item = "Midnight Blade", itemID = 21016, source = "Dibs ledger" } },
    }
  end

  it("discloses each advanced action separately and keeps them behind the advanced toggle", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1" } },
      withAce3 = true,
    })
    local frame = dibs.OfficerUI.CreateWindow()
    local current = request()
    assert_true(frame.OpenRequestDetail(current))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Correct balance"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Refund Dib"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Revoke Dib"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Import historical"))

    local toggle = findWidget(frame.requestDetailRoot, "Button", "Advanced Officer Tools")
    assert_not_nil(toggle)
    toggle.callbacks.OnClick(toggle, "OnClick")
    for _, label in ipairs({ "Correct player / item", "Correct balance", "Refund Dib", "Revoke Dib", "Import historical" }) do
      assert_not_nil(findWidget(frame.requestDetailRoot, "Button", label))
    end
  end)

  it("evaluates the existing protected permission before opening advanced action dialogs", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1" } },
      withAce3 = true,
    })
    local evaluated = {}
    local originalEvaluate = dibs.Permissions.Evaluate
    dibs.Permissions.Evaluate = function(actionId, actor)
      evaluated[#evaluated + 1] = { actionId = actionId, actor = actor }
      return { allowed = false, reasonCode = "GUILD_ADMIN_REQUIRED", diagnostic = "blocked" }
    end
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(request()))
    local toggle = findWidget(frame.requestDetailRoot, "Button", "Advanced Officer Tools")
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Correct balance"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Refund Dib"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Revoke Dib"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Import historical"))
    dibs.Permissions.Evaluate = originalEvaluate
    assert_true(#evaluated > 0)
  end)
end)
