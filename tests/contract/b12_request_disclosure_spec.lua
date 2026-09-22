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

describe("B12 request disclosure", function()
  it("keeps the Player request projection free of Officer and evidence internals", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Player-1" } }, withAce3 = true })
    dibs.GetPlayerName = function() return "Player-1" end
    dibs.Disputes.ListForPlayer = function()
      return {
        {
          requestId = "b12-player-disclosure",
          status = "Open",
          category = "history_problem",
          categoryLabel = "History problem",
          player = { name = "Player-1" },
          evidence = {
            { item = "Visible item", source = "Dibs ledger", transactionRef = "secret-transaction", awardRef = "secret-award" },
          },
          timeline = { { action = "created", actorId = "secret-officer" } },
        },
      }
    end
    local projection = dibs.PlayerUI.BuildRequestView({ limit = 10 })[1]
    assert_equal("b12-player-disclosure", projection.requestId)
    assert_equal("History problem", projection.details.category)
    assert_equal("Visible item", projection.details.item)
    assert_nil(projection.player)
    assert_nil(projection.evidence)
    assert_nil(projection.timeline)
    assert_nil(projection.details.transactionRef)
    assert_nil(projection.details.awardRef)
  end)

  it("does not expose advanced tools for an unavailable Officer request", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Officer-Realm", "Player-1" } }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow()
    local request = {
      requestId = "b12-unavailable-request",
      status = "Unavailable",
      unavailable = true,
      category = "history_problem",
      player = { name = "Player-1" },
      evidence = { { item = "Unavailable item" } },
    }
    assert_true(frame.OpenRequestDetail(request))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Advanced Officer Tools"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Correct player / item"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Correct balance"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Refund Dib"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Revoke Dib"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Import historical"))
  end)
end)
