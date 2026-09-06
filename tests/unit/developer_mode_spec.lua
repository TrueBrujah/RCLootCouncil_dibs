local loader = require("helpers.load_addon")

describe("Developer mode", function()
  it("is disabled by default", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    assert_false(dibs.DeveloperMode.IsEnabled())
  end)

  it("rejects testitem when developer mode is disabled", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.HandleSlashCommand("testitem 275658")

    local found = false
    for _, line in ipairs(_G.__dibsMessages or {}) do
      if string.find(line, "Developer Mode is disabled", 1, true) then
        found = true
        break
      end
    end
    assert_true(found)

    local txCount = #(dibs.Ledger.GetAllTransactions())
    assert_equal(1, txCount, "only default allocation transaction is expected")
    local testRequests = dibs.PreDibs.GetTestHistory and dibs.PreDibs.GetTestHistory() or {}
    assert_equal(0, #testRequests)
  end)

  it("enables and injects a test item without polluting production ledger", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })

    dibs.HandleSlashCommand("dev on")
    assert_true(dibs.DeveloperMode.IsEnabled())

    dibs.HandleSlashCommand("testitem 275658")

    local pending = dibs.LootPipeline.GetPendingDevContext()
    assert_not_nil(pending)
    assert_equal(true, pending.isTest)
    assert_equal(275658, pending.itemID)

    local request, reason = dibs.LootPipeline.RequestDibFromContext(pending)
    assert_not_nil(request)
    assert_nil(reason)
    assert_equal(true, request.isTest)
    assert_equal("confirmed", request.status)

    local testRequests = dibs.PreDibs.GetTestHistory()
    assert_equal(1, #testRequests)

    local liveRequests = dibs.PreDibs.GetHistory()
    assert_equal(0, #liveRequests)

    local txCount = #(dibs.Ledger.GetAllTransactions())
    assert_equal(1, txCount, "developer requests must not append production ledger transactions")

    assert_equal(0, #(_G.__sentChatMessages or {}), "developer request should not emit production chat announcements")
  end)

  it("handles invalid testitem input without Lua error", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.HandleSlashCommand("dev on")

    dibs.HandleSlashCommand("testitem")
    dibs.HandleSlashCommand("testitem abc")
    dibs.HandleSlashCommand("testitem -1")
    dibs.HandleSlashCommand("testitem 0")
    dibs.HandleSlashCommand("testitem 999999999")

    local hasUsage = false
    local hasInvalid = false
    for _, line in ipairs(_G.__dibsMessages or {}) do
      if string.find(line, "Usage: /dibs testitem", 1, true) then
        hasUsage = true
      end
      if string.find(line, "Invalid item input", 1, true) then
        hasInvalid = true
      end
    end

    assert_true(hasUsage)
    assert_true(hasInvalid)
  end)
end)
