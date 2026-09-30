local loader = require("helpers.load_addon")

if os.getenv("DIBS_PERF_BENCH") == "1" then
  local candidateCounts = { 1, 10, 25, 40 }
  local ledgerSizes = { 100, 1000, 5000, 10000 }
  local countedMethods = {
    "GetCanonicalPlayerDibsState",
    "GetPlayerDibsProjection",
    "GetPendingDibReservations",
    "GetPlayerSeasonState",
    "GetTransactions",
    "GetPlayerState",
    "GetBalance",
  }

  local function makeVotingFrame()
    local voting = { publicColumns = { { colName = "name" }, { colName = "response" } } }
    function voting:GetColumnIndex(name)
      for index, column in ipairs(self.publicColumns) do
        if column.colName == name then return index end
      end
    end
    function voting:AddColumn(spec, target, position)
      local targetIndex = self:GetColumnIndex(target)
      if not targetIndex then error("Column target was not found") end
      table.insert(self.publicColumns, targetIndex + (position == "after" and 1 or 0), spec)
      return spec
    end
    return voting
  end

  local function makeScenario(candidateCount, ledgerSize)
    local candidates = {}
    for index = 1, candidateCount do
      candidates[index] = string.format("Bench%02d-Realm", index)
    end

    local voting = makeVotingFrame()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.GetModule = function(_, name)
      if name == "RCVotingFrame" then return voting end
    end

    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildMembers = candidates } })
    local seasonId = dibs.GetCurrentSeasonId()
    local ledger = dibs.GetDB().ledger
    local memberKeys = {}
    ledger.transactions = {}
    ledger.playerStates[seasonId] = {}

    for index, candidateName in ipairs(candidates) do
      local memberKey = dibs.Identity.CanonicalMemberKey(candidateName)
      memberKeys[index] = memberKey
      ledger.playerStates[seasonId][memberKey] = { allocation = 0, balance = 0, transactions = {} }
    end

    for transactionIndex = 1, ledgerSize do
      local candidateIndex = ((transactionIndex - 1) % candidateCount) + 1
      local transactionId = string.format("bench:%05d", transactionIndex)
      local memberKey = memberKeys[candidateIndex]
      ledger.transactions[transactionId] = {
        transactionId = transactionId,
        memberKey = memberKey,
        playerName = candidates[candidateIndex],
        seasonId = seasonId,
        type = "DIB_GRANTED",
        amount = 1,
        createdAt = transactionIndex,
      }
      table.insert(ledger.playerStates[seasonId][memberKey].transactions, transactionId)
    end

    local column = voting.publicColumns[voting:GetColumnIndex("dibsRemaining")]
    local columnIndex = voting:GetColumnIndex("dibsRemaining")
    assert_not_nil(column)
    return dibs, ledger, candidates, column, columnIndex
  end

  local function measureRefresh(dibs, ledger, candidates, column, columnIndex)
    local counters = { transactionIterations = 0, sortOperations = 0, transactionSortOperations = 0 }
    for _, methodName in ipairs(countedMethods) do counters[methodName] = 0 end

    local originalMethods = {}
    for _, methodName in ipairs(countedMethods) do
      local original = dibs.Ledger[methodName]
      originalMethods[methodName] = original
      dibs.Ledger[methodName] = function(...)
        counters[methodName] = counters[methodName] + 1
        return original(...)
      end
    end

    local originalPairs = pairs
    local originalSort = table.sort
    pairs = function(target)
      local iterator, state, control = originalPairs(target)
      if target ~= ledger.transactions then return iterator, state, control end
      return function(currentState, currentControl)
        local key, value = iterator(currentState, currentControl)
        if key ~= nil then counters.transactionIterations = counters.transactionIterations + 1 end
        return key, value
      end, state, control
    end
    table.sort = function(target, ...)
      counters.sortOperations = counters.sortOperations + 1
      if type(target[1]) == "table" and target[1].transactionId ~= nil then
        counters.transactionSortOperations = counters.transactionSortOperations + 1
      end
      return originalSort(target, ...)
    end

    local function refresh()
      for index, candidateName in ipairs(candidates) do
        local data = { [index] = { name = candidateName, cols = { [columnIndex] = {} } } }
        local cell = { text = { SetText = function() end, SetTextColor = function() end } }
        column.DoCellUpdate({}, cell, data, {}, index, index, columnIndex, true, {})
      end
    end

    local function resetCounters()
      counters.transactionIterations, counters.sortOperations, counters.transactionSortOperations = 0, 0, 0
      for _, methodName in ipairs(countedMethods) do counters[methodName] = 0 end
    end

    local function snapshotCounters()
      local snapshot = {}
      for key, value in pairs(counters) do snapshot[key] = value end
      return snapshot
    end

    local coldStartedAt = os.clock()
    local ok, err = pcall(refresh)
    local coldMilliseconds = (os.clock() - coldStartedAt) * 1000
    if not ok then error(err) end
    local cold = snapshotCounters()

    resetCounters()
    local warmStartedAt = os.clock()
    ok, err = pcall(refresh)
    local warmMilliseconds = (os.clock() - warmStartedAt) * 1000

    table.sort = originalSort
    pairs = originalPairs
    for _, methodName in ipairs(countedMethods) do dibs.Ledger[methodName] = originalMethods[methodName] end
    if not ok then error(err) end
    return cold, coldMilliseconds, warmMilliseconds, snapshotCounters()
  end

  describe("RCLootCouncil Vote Frame Dibs projection benchmark", function()
    it("records cold and warm callback cost across the requested matrix", function()
      for _, candidateCount in ipairs(candidateCounts) do
        for _, ledgerSize in ipairs(ledgerSizes) do
          local dibs, ledger, candidates, column, columnIndex = makeScenario(candidateCount, ledgerSize)
          local cold, coldMilliseconds, warmMilliseconds, warm = measureRefresh(dibs, ledger, candidates, column, columnIndex)

          assert_equal(0, cold.GetCanonicalPlayerDibsState)
          assert_equal(candidateCount, cold.GetPlayerDibsProjection)
          assert_equal(candidateCount, cold.GetPendingDibReservations)
          assert_equal(0, cold.GetPlayerSeasonState)
          assert_equal(0, cold.GetTransactions)
          assert_equal(0, cold.GetPlayerState)
          assert_equal(0, cold.GetBalance)
          assert_equal(0, cold.transactionIterations)
          assert_equal(0, cold.transactionSortOperations)
          assert_equal(candidateCount, warm.GetPlayerDibsProjection)
          assert_equal(0, warm.GetPendingDibReservations)
          assert_equal(candidateCount, warm.GetPlayerDibsProjection - warm.GetPendingDibReservations)
          assert_equal(0, warm.transactionIterations)
          assert_equal(0, warm.transactionSortOperations)

          io.write(string.format(
            "BENCH candidates=%d ledger=%d cold_calls=projection:%d pending:%d iterations:%d sorts_all:%d sorts_transactions:%d cold_ms=%.2f warm_calls=projection:%d pending:%d cache_hits:%d iterations:%d sorts_all:%d sorts_transactions:%d warm_ms=%.2f\n",
            candidateCount, ledgerSize,
            cold.GetPlayerDibsProjection, cold.GetPendingDibReservations,
            cold.transactionIterations, cold.sortOperations, cold.transactionSortOperations,
            coldMilliseconds,
            warm.GetPlayerDibsProjection, warm.GetPendingDibReservations,
            warm.GetPlayerDibsProjection - warm.GetPendingDibReservations,
            warm.transactionIterations, warm.sortOperations, warm.transactionSortOperations,
            warmMilliseconds))
        end
      end
    end)
  end)
end
