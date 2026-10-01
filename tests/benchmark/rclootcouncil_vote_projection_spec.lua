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

    local transactionLists = {}
    for _, state in pairs(ledger.playerStates[seasonId]) do
      transactionLists[state.transactions] = true
    end

    local column = voting.publicColumns[voting:GetColumnIndex("dibsRemaining")]
    local columnIndex = voting:GetColumnIndex("dibsRemaining")
    assert_not_nil(column)
    return dibs, ledger, candidates, column, columnIndex, transactionLists
  end

  local function measureRefresh(dibs, ledger, candidates, column, columnIndex, transactionLists)
    dibs.Identity.InvalidateRoster("BENCH_COLD_ROSTER")
    local counters = {
      playerTransactionIterations = 0, sortOperations = 0, transactionSortOperations = 0,
      rosterCountCalls = 0, rosterMemberReads = 0,
    }
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

    local originalIpairs = ipairs
    local originalSort = table.sort
    local originalGetNumGuildMembers = GetNumGuildMembers
    local originalGetGuildRosterInfo = GetGuildRosterInfo
    GetNumGuildMembers = function(...)
      counters.rosterCountCalls = counters.rosterCountCalls + 1
      return originalGetNumGuildMembers(...)
    end
    GetGuildRosterInfo = function(...)
      counters.rosterMemberReads = counters.rosterMemberReads + 1
      return originalGetGuildRosterInfo(...)
    end
    ipairs = function(target)
      local iterator, state, control = originalIpairs(target)
      if not transactionLists[target] then return iterator, state, control end
      return function(currentState, currentControl)
        local index, value = iterator(currentState, currentControl)
        if value ~= nil then counters.playerTransactionIterations = counters.playerTransactionIterations + 1 end
        return index, value
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
      counters.playerTransactionIterations, counters.sortOperations, counters.transactionSortOperations = 0, 0, 0
      counters.rosterCountCalls, counters.rosterMemberReads = 0, 0
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
    ipairs = originalIpairs
    GetNumGuildMembers = originalGetNumGuildMembers
    GetGuildRosterInfo = originalGetGuildRosterInfo
    for _, methodName in ipairs(countedMethods) do dibs.Ledger[methodName] = originalMethods[methodName] end
    if not ok then error(err) end
    return cold, coldMilliseconds, warmMilliseconds, snapshotCounters()
  end

  local function makeLootRefreshScenario(entryCount, ledgerSize)
    local lootFrame = { EntryManager = { entries = {} } }
    function lootFrame:Update() self.updateCount = (self.updateCount or 0) + 1 end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = { RCLootFrame = lootFrame }
    local playerName = "Tester-Realm"
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { playerName = playerName, guildMembers = { playerName } } })
    assert_true(lootFrame.__dibsButtonHooked)
    for index = 1, entryCount do
      local itemID = 275658 + index
      lootFrame.EntryManager.entries[index] = {
        frame = _G.CreateFrame("Frame"),
        item = { link = string.format("|Hitem:%d::::::::::::|h[Bench Item %d]|h", itemID, index), typeCode = "INVTYPE_HEAD" },
        buttons = {},
      }
    end
    local seasonId = dibs.GetCurrentSeasonId()
    local ledger = dibs.GetDB().ledger
    local memberKey = dibs.Identity.CanonicalMemberKey(playerName)
    local transactions = {}
    ledger.transactions = {}
    ledger.playerStates[seasonId] = {
      [memberKey] = { allocation = 0, balance = 0, transactions = transactions },
    }
    for index = 1, ledgerSize do
      local transactionId = string.format("loot-bench:%05d", index)
      ledger.transactions[transactionId] = {
        transactionId = transactionId, memberKey = memberKey, playerName = playerName,
        seasonId = seasonId, type = "DIB_GRANTED", amount = 1, createdAt = index,
      }
      transactions[#transactions + 1] = transactionId
    end
    return dibs, lootFrame, { [transactions] = true }
  end

  local function measureLootRefresh(dibs, lootFrame, transactionLists)
    local counters = {
      typePolicyCalls = 0, canonicalProjectionCalls = 0, getBalanceCalls = 0, pendingReservationCalls = 0,
      confirmedRequestCalls = 0, requestItemLookups = 0, playerTransactionIterations = 0,
    }
    local function wrapMethod(owner, name, counter)
      local original = owner[name]
      owner[name] = function(...)
        counters[counter] = counters[counter] + 1
        return original(...)
      end
      return function() owner[name] = original end
    end
    local restore = {
      wrapMethod(dibs.RCLootCouncil, "IsItemDibTypeAllowed", "typePolicyCalls"),
      wrapMethod(dibs.Ledger, "GetCanonicalPlayerDibsState", "canonicalProjectionCalls"),
      wrapMethod(dibs.Ledger, "GetBalance", "getBalanceCalls"),
      wrapMethod(dibs.Ledger, "GetPendingDibReservations", "pendingReservationCalls"),
      wrapMethod(dibs.PreDibs, "GetConfirmedRequestForPlayer", "confirmedRequestCalls"),
      wrapMethod(dibs.PreDibs, "GetRequestsForItem", "requestItemLookups"),
    }
    local originalIpairs = ipairs
    ipairs = function(target)
      local iterator, state, control = originalIpairs(target)
      if not transactionLists[target] then return iterator, state, control end
      return function(currentState, currentControl)
        local index, value = iterator(currentState, currentControl)
        if value ~= nil then counters.playerTransactionIterations = counters.playerTransactionIterations + 1 end
        return index, value
      end, state, control
    end

    local function refreshThroughRegisteredSecureHook()
      lootFrame:Update()
      local hooks = lootFrame.__secureHooks and lootFrame.__secureHooks.Update or {}
      for _, callback in ipairs(hooks) do callback(lootFrame) end
    end

    local function snapshotCounters()
      local snapshot = {}
      for key, value in pairs(counters) do snapshot[key] = value end
      return snapshot
    end

    local function resetCounters()
      for key in pairs(counters) do counters[key] = 0 end
    end

    local coldStartedAt = os.clock()
    local coldOk, coldError = pcall(refreshThroughRegisteredSecureHook)
    local coldMilliseconds = (os.clock() - coldStartedAt) * 1000
    local cold = snapshotCounters()

    resetCounters()
    local warmStartedAt = os.clock()
    local warmOk, warmError = pcall(refreshThroughRegisteredSecureHook)
    local warmMilliseconds = (os.clock() - warmStartedAt) * 1000
    local warm = snapshotCounters()

    ipairs = originalIpairs
    for index = #restore, 1, -1 do restore[index]() end
    if not coldOk then error(coldError) end
    if not warmOk then error(warmError) end
    return cold, coldMilliseconds, warm, warmMilliseconds
  end

  describe("RCLootCouncil Vote Frame Dibs projection benchmark", function()
    it("records cold and warm callback cost across the requested matrix", function()
      for _, candidateCount in ipairs(candidateCounts) do
        for _, ledgerSize in ipairs(ledgerSizes) do
          local dibs, ledger, candidates, column, columnIndex, transactionLists = makeScenario(candidateCount, ledgerSize)
          local cold, coldMilliseconds, warmMilliseconds, warm = measureRefresh(
            dibs, ledger, candidates, column, columnIndex, transactionLists)

          assert_equal(0, cold.GetCanonicalPlayerDibsState)
          assert_equal(candidateCount, cold.GetPlayerDibsProjection)
          assert_equal(candidateCount, cold.GetPendingDibReservations)
          assert_equal(0, cold.GetPlayerSeasonState)
          assert_equal(0, cold.GetTransactions)
          assert_equal(0, cold.GetPlayerState)
          assert_equal(0, cold.GetBalance)
          assert_equal(ledgerSize, cold.playerTransactionIterations)
          assert_equal(0, cold.transactionSortOperations)
          assert_equal(1, cold.rosterCountCalls)
          assert_equal(candidateCount, cold.rosterMemberReads)
          assert_equal(candidateCount, warm.GetPlayerDibsProjection)
          assert_equal(0, warm.GetPendingDibReservations)
          assert_equal(candidateCount, warm.GetPlayerDibsProjection - warm.GetPendingDibReservations)
          assert_equal(0, warm.playerTransactionIterations)
          assert_equal(0, warm.transactionSortOperations)
          assert_equal(0, warm.rosterCountCalls)
          assert_equal(0, warm.rosterMemberReads)

          io.write(string.format(
            "BENCH path=vote-column candidates=%d ledger=%d cold_calls=projection:%d pending:%d player_tx_iterations:%d roster_reads:%d sorts_all:%d sorts_transactions:%d cold_ms=%.2f warm_calls=projection:%d pending:%d cache_hits:%d player_tx_iterations:%d roster_reads:%d sorts_all:%d sorts_transactions:%d warm_ms=%.2f\n",
            candidateCount, ledgerSize,
            cold.GetPlayerDibsProjection, cold.GetPendingDibReservations,
            cold.playerTransactionIterations, cold.rosterMemberReads, cold.sortOperations, cold.transactionSortOperations,
            coldMilliseconds,
            warm.GetPlayerDibsProjection, warm.GetPendingDibReservations,
            warm.GetPlayerDibsProjection - warm.GetPendingDibReservations,
            warm.playerTransactionIterations, warm.rosterMemberReads, warm.sortOperations, warm.transactionSortOperations,
            warmMilliseconds))
        end
      end
    end)

    it("measures the real post-Update loot-frame status path", function()
      for _, candidateCount in ipairs(candidateCounts) do
        for _, ledgerSize in ipairs(ledgerSizes) do
          local dibs, lootFrame, transactionLists = makeLootRefreshScenario(candidateCount, ledgerSize)
          local cold, coldMilliseconds, warm, warmMilliseconds = measureLootRefresh(dibs, lootFrame, transactionLists)
          for _, counters in ipairs({ cold, warm }) do
            assert_equal(candidateCount, counters.typePolicyCalls)
            assert_equal(1, counters.canonicalProjectionCalls, string.format(
              "typePolicy=%d projection=%d balance=%d pending=%d iterations=%d",
              counters.typePolicyCalls, counters.canonicalProjectionCalls, counters.getBalanceCalls,
              counters.pendingReservationCalls, counters.playerTransactionIterations))
            assert_equal(0, counters.getBalanceCalls)
            assert_equal(1, counters.pendingReservationCalls)
            assert_equal(candidateCount, counters.confirmedRequestCalls)
            assert_equal(candidateCount * 2, counters.requestItemLookups)
            assert_equal(ledgerSize, counters.playerTransactionIterations)
          end
          io.write(string.format(
            "BENCH path=applyDibsButtonState loot_entries=%d player_ledger_transactions=%d cold_ms=%.2f cold_calls=policy:%d projection:%d balance:%d pending:%d confirmed:%d item_lookups:%d player_tx_iterations:%d warm_ms=%.2f warm_calls=policy:%d projection:%d balance:%d pending:%d confirmed:%d item_lookups:%d player_tx_iterations:%d\n",
            candidateCount, ledgerSize,
            coldMilliseconds, cold.typePolicyCalls, cold.canonicalProjectionCalls, cold.getBalanceCalls,
            cold.pendingReservationCalls, cold.confirmedRequestCalls, cold.requestItemLookups, cold.playerTransactionIterations,
            warmMilliseconds, warm.typePolicyCalls, warm.canonicalProjectionCalls, warm.getBalanceCalls,
            warm.pendingReservationCalls, warm.confirmedRequestCalls, warm.requestItemLookups, warm.playerTransactionIterations))
        end
      end
    end)
  end)
end
