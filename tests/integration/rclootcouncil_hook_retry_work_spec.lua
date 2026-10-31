local loader = require("helpers.load_addon")

describe("RCLootCouncil hook retry work", function()
  it("uses RCLootCouncil lifecycle hooks instead of periodic config polling when available", function()
    local profile = {
      buttons = { default = { numButtons = 1, { text = "Need", whisperKey = "need" } } },
      responses = { default = { { text = "Need", sort = 1, color = { 1, 1, 1, 1 } } } },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    rc.OnInitialize = function() end
    rc.OnEnable = function() end
    rc.UpdateDB = function() end
    rc.OptionsTable = function() return { args = {} } end
    local _, dibs = loader.load({ rclootcouncil = rc, skipInitialize = true })
    local scheduled = {}
    _G.C_Timer.After = function(delay, callback)
      scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end

    assert_true(dibs.RCLootCouncil.Initialize())
    assert_true(rc.__dibsForcedDibHooked_OnEnable)
    assert_true(rc.__dibsForcedDibHooked_UpdateDB)
    assert_true(rc.__dibsForcedDibHooked_OptionsTable)
    for _, timer in ipairs(scheduled) do
      assert_true(timer.delay ~= 0.75,
        "a compatible RC lifecycle API should make the 40-pass config poll unnecessary")
    end
    assert_false(dibs.RCLootCouncil.configWatcherActive)
  end)

  it("keeps config polling when UpdateDB is unavailable", function()
    local profile = {
      buttons = { default = { numButtons = 1, { text = "Need", whisperKey = "need" } } },
      responses = { default = { { text = "Need", sort = 1, color = { 1, 1, 1, 1 } } } },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.OnInitialize = function() end
    local _, dibs = loader.load({ rclootcouncil = rc, skipInitialize = true })
    local scheduled = {}
    _G.C_Timer.After = function(delay, callback)
      scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end

    assert_true(dibs.RCLootCouncil.Initialize())
    assert_true(dibs.RCLootCouncil.configWatcherActive,
      "a ready config without an UpdateDB hook must keep its bounded fallback")
    local hasFallbackTick = false
    for _, timer in ipairs(scheduled) do
      if timer.delay == 0.75 then hasFallbackTick = true end
    end
    assert_true(hasFallbackTick, "the config fallback should be scheduled")
  end)

  it("does not reproject an already hooked loot frame on each readiness retry", function()
    local lootFrame = { EntryManager = { entries = {
      { item = { link = "item:275658", typeCode = "INVTYPE_HEAD" }, buttons = {} },
    } } }
    function lootFrame:Update() end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = {
      RCLootFrame = lootFrame,
      -- An unavailable voting API keeps the bounded readiness retry active.
      RCVotingFrame = {},
    }
    local _, dibs = loader.load({ rclootcouncil = rc, skipInitialize = true })
    local scheduled = {}
    _G.C_Timer.After = function(delay, callback)
      scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end

    local projectionCalls = 0
    dibs.Ledger.GetCanonicalPlayerDibsState = function()
      projectionCalls = projectionCalls + 1
      return { available = true, balance = 1, availableBalance = 1, pendingDibReservations = 0 }
    end

    assert_true(dibs.RCLootCouncil.Initialize())
    assert_true(lootFrame.__dibsButtonHooked)
    assert_equal(1, projectionCalls,
      "initialization should project the loot frame once")

    local retries = 0
    for index = 1, 2 do
      local retry
      for queueIndex, timer in ipairs(scheduled) do
        if timer.delay == 1 then
          retry = timer.callback
          table.remove(scheduled, queueIndex)
          break
        end
      end
      assert_not_nil(retry, "readiness retry was not scheduled")
      retry()
      retries = retries + 1
      assert_equal(1, projectionCalls,
        "an installed Update hook should not trigger another full projection during readiness polling")
    end
    assert_equal(2, retries)
  end)
end)
