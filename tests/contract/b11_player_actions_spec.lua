local loader = require("helpers.load_addon")

describe("B11c Player actions", function()
  it("rejects invalid item input before invoking a request service", function()
    local _, dibs = loader.load()
    local calls = 0
    dibs.LootPipeline.RequestDibFromContext = function() calls = calls + 1 end
    local request, reason = dibs.PlayerUI.SubmitPreDib("not-an-item")
    assert_nil(request)
    assert_equal("Invalid item: use item ID or item link.", reason)
    assert_equal(0, calls)
  end)

  it("delegates valid requests to the authoritative loot pipeline", function()
    local _, dibs = loader.load()
    local received
    dibs.LootPipeline.RequestDibFromContext = function(context)
      received = context
      return { requestId = "request-1", itemID = context.itemID, status = "pending" }
    end
    local request = dibs.PlayerUI.SubmitPreDib("123")
    assert_equal("request-1", request.requestId)
    assert_equal(123, received.itemID)
    assert_equal("player-ui", received.source)
    assert_false(received.isTest)
  end)

  it("delegates cancellation with the local player identity", function()
    local _, dibs = loader.load()
    local requestID, owner
    dibs.PreDibs.CancelForPlayer = function(id, player)
      requestID, owner = id, player
      return { requestId = id, status = "cancelled" }
    end
    local request = dibs.PlayerUI.CancelPreDib("request-1")
    assert_equal("request-1", request.requestId)
    assert_equal("request-1", requestID)
    assert_equal(dibs.GetPlayerName(), owner)
  end)
end)