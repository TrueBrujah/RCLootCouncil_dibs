local loader = require("helpers.load_addon")

local function setup()
  local profile = {
    buttons = { default = { numButtons = 1, { text = "Need", whisperKey = "need" } } },
    responses = { default = { { text = "Need", sort = 1, color = { 1, 1, 1, 1 } } } },
    enabledButtons = { TOKEN = true, OTHER = true },
  }
  local rc = loader.makeRCLootCouncil({ enabled = true })
  rc.Getdb = function() return profile end
  rc.configChangeCount = 0
  rc.ConfigTableChanged = function(self) self.configChangeCount = self.configChangeCount + 1 end
  local _, dibs = loader.load({ rclootcouncil = rc, withAce3 = true,
    skipInitialize = true, savedVariables = {} })
  local scheduled = {}
  _G.C_Timer.After = function(delay, callback)
    scheduled[#scheduled + 1] = { delay = delay, callback = callback }
  end
  dibs.Initialize()

  -- Synthetic history, not the user's SavedVariables or a WoW heap sample.
  local rules = assert(dibs.LootRules.GetDraftSnapshot())
  local catalog = dibs.GetDB().seasonCatalog
  catalog.catalogRevision, catalog.records = 50, {}
  for revision = 1, 50 do
    catalog.records[tostring(revision)] = {
      catalogRevision = revision,
      guildConfiguration = { guildLootRules = dibs.DeepCopy(rules) },
    }
  end
  return dibs, scheduled, catalog, rc
end

local function observeCopies(dibs, catalog, body)
  local original, count = dibs.DeepCopy, 0
  dibs.DeepCopy = function(value, ...)
    if value == catalog then count = count + 1 end
    return original(value, ...)
  end
  local ok, result = pcall(body)
  dibs.DeepCopy = original
  assert_true(ok, tostring(result))
  return count, result
end

describe("RC startup work audit", function()
  it("reads a current loot decision without copying historical catalog records", function()
    local dibs, _, catalog = setup()
    local count, value = observeCopies(dibs, catalog, function()
      local decision, reason = dibs.LootRules.GetEffectiveValue("default", "rclootcouncil")
      assert_equal("GUILD", reason)
      return decision
    end)
    assert_true(value)
    print("AUDIT_RC single-decision full-catalog-copies=" .. count .. " historical-records=50")
    assert_equal(0, count, "a current policy lookup cloned the whole historical catalog")
  end)

  it("keeps the bounded watcher from copying historical catalogs on unchanged passes", function()
    local dibs, scheduled, catalog, rc = setup()
    local notificationsBefore = rc.configChangeCount
    local nextTick
    for _, timer in ipairs(scheduled) do
      if timer.delay == 0.75 then
        assert_nil(nextTick, "more than one initial config watcher")
        nextTick = timer.callback
      end
    end
    assert_not_nil(nextTick)
    local ticks, pending = 0, {}
    _G.C_Timer.After = function(delay, callback)
      if delay == 0.75 then pending[#pending + 1] = callback end
    end
    local count = observeCopies(dibs, catalog, function()
      while nextTick do
        ticks = ticks + 1
        assert_true(ticks <= 40, "watcher exceeded its declared bound")
        nextTick()
        nextTick = table.remove(pending, 1)
      end
    end)
    assert_equal(40, ticks)
    assert_equal(0, #pending)
    assert_false(dibs.RCLootCouncil.configWatcherActive)
    assert_true(dibs.RCLootCouncil.configWatcherStopped)
    assert_equal(notificationsBefore, rc.configChangeCount,
      "fixture unexpectedly changed the projection during the watcher")
    print("AUDIT_RC watcher-ticks=" .. ticks .. " full-catalog-copies=" .. count
      .. " historical-records=50")
    assert_equal(0, count, "unchanged config watcher passes cloned all historical catalog records")
  end)
end)
