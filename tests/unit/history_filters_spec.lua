local loader = require("helpers.load_addon")

describe("Shared history filters", function()
  local filters

  before_each(function()
    local _, dibs = loader.load()
    filters = dibs.HistoryFilters
  end)

  it("matches literal text case-insensitively and combines criteria with AND", function()
    local records = {
      { transactionId = "a", itemName = "Primal Storm", playerName = "Tester-Realm", source = "loot", createdAt = 10 },
      { transactionId = "b", itemName = "Primal Storm", playerName = "Other-Realm", source = "manual", createdAt = 20 },
      { transactionId = "c", itemName = "Storm", playerName = "Tester-Realm", source = "loot", createdAt = 30 },
    }

    local result = filters.FilterRecords(records, {
      query = "primal",
      playerName = "tester",
      source = "loot",
    })

    assert_equal(1, #result)
    assert_equal("a", result[1].transactionId)
  end)

  it("does not match criteria through missing metadata or display fallbacks", function()
    local result = filters.FilterRecords({
      { transactionId = "missing", createdAt = 10 },
      { transactionId = "recorded", instanceName = "Unknown", createdAt = 20 },
    }, { raid = "Unknown" })

    assert_equal(1, #result)
    assert_equal("recorded", result[1].transactionId)
  end)

  it("includes both calendar-date boundaries and rejects invalid or reversed dates", function()
    local originalTime = _G.time
    _G.time = function(value) return os.time(value) end
    local first = time({ year = 2025, month = 2, day = 1, hour = 0 })
    local last = time({ year = 2025, month = 2, day = 3, hour = 23, min = 59, sec = 59 })
    local result = filters.FilterRecords({
      { transactionId = "before", createdAt = first - 1 },
      { transactionId = "start", createdAt = first },
      { transactionId = "end", createdAt = last },
      { transactionId = "after", createdAt = last + 1 },
    }, { fromDate = "2025-02-01", toDate = "2025-02-03" })

    assert_equal(2, #result)
    assert_equal("end", result[1].transactionId)
    assert_equal("start", result[2].transactionId)

    local invalid, invalidReason = filters.FilterRecords({}, { fromDate = "2025-02-30" })
    local reversed, reversedReason = filters.FilterRecords({}, { fromDate = "2025-02-04", toDate = "2025-02-03" })
    assert_nil(invalid)
    assert_equal("INVALID_FROM_DATE", invalidReason)
    assert_nil(reversed)
    assert_equal("INVALID_DATE_RANGE", reversedReason)
    _G.time = originalTime
  end)

  it("sorts equal timestamps deterministically by the existing record identity", function()
    local result = filters.FilterRecords({
      { transactionId = "b", createdAt = 10 },
      { transactionId = "a", createdAt = 10 },
      { transactionId = "new", createdAt = 20 },
    }, {})

    assert_equal("new", result[1].transactionId)
    assert_equal("a", result[2].transactionId)
    assert_equal("b", result[3].transactionId)
  end)

  it("filters 5,000 records within the search budget", function()
    local records = {}
    for index = 1, 5000 do
      records[index] = {
        transactionId = tostring(index),
        itemName = index == 4317 and "Target Item" or "Other Item",
        createdAt = index,
      }
    end

    local started = os.clock()
    local result = filters.FilterRecords(records, { item = "Target Item" })
    local elapsed = os.clock() - started

    assert_equal(1, #result)
    assert_equal("4317", result[1].transactionId)
    assert_true(elapsed < 2, "5,000-record filter took " .. tostring(elapsed) .. " seconds")
  end)
end)
