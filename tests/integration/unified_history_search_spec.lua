local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

describe("Unified history search", function()
  it("filters only the current player's Dibs history by recorded item and source fields", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } },
    })
    local playerName = dibs.GetPlayerName()
    local seasonId = dibs.GetCurrentSeasonId()
    local added = dibs.Ledger.AddTransaction(fixtures.transaction(playerName, seasonId, {
      transactionId = "history-search-player-match",
      itemID = 19019,
      itemName = "Midnight Blade",
      type = "DIB_GRANTED",
      amount = 1,
      source = "rclootcouncil",
      instanceName = "The Midnight Citadel",
      createdAt = 1700000100,
    }))
    assert_not_nil(added)
    assert_not_nil(dibs.Ledger.AddTransaction(fixtures.transaction("Other-Realm", seasonId, {
      transactionId = "history-search-other-player",
      itemName = "Other Boss Item",
      type = "DIB_GRANTED",
      amount = 1,
      source = "rclootcouncil",
      itemID = 19019,
      createdAt = 1700000200,
    })))
    assert_not_nil(dibs.Ledger.AddTransaction(fixtures.transaction(playerName, seasonId, {
      transactionId = "history-search-player-nonmatch",
      itemName = "Unrelated Item",
      itemID = 999,
      type = "DIB_GRANTED",
      amount = 1,
      source = "manual",
      createdAt = 1700000300,
    })))

    local view = dibs.PlayerUI.GetViewModel(nil, {
      query = "19019",
      source = "rclootcouncil",
    })

    assert_equal(1, #view.history)
    assert_equal(19019, view.history[1].itemID)
    assert_nil(view.history[1].evidence)
    assert_nil(view.history[1].historyRef)

    local missingMetadata = dibs.PlayerUI.GetViewModel(nil, { query = "Unknown" })
    local cleared = dibs.PlayerUI.GetViewModel(nil, {})
    assert_equal(0, #missingMetadata.history)
    assert_equal(3, #cleared.history)
    for _, entry in ipairs(cleared.history) do
      assert_true(entry.transactionId ~= "history-search-other-player")
    end
  end)

  it("filters the Player Great Vault page through its search control without leaking private evidence", function()
    local _, dibs = loader.load({ withAce3 = true })
    local records = dibs.PreDibs.GetAcquisitions()
    records[#records + 1] = {
      acquisitionId = "history-search-vault-match",
      playerName = dibs.GetPlayerName(),
      itemID = 275658,
      itemName = "Wanted Vault Item",
      acquiredAt = 1700000300,
      source = "MANUAL",
      verificationState = "MANUAL_RECORDED",
      evidence = { privateToken = "must-not-display" },
    }
    records[#records + 1] = {
      acquisitionId = "history-search-vault-other",
      playerName = dibs.GetPlayerName(),
      itemID = 275659,
      itemName = "Unrelated Vault Item",
      acquiredAt = 1700000200,
      source = "MANUAL",
      verificationState = "MANUAL_RECORDED",
    }
    records[#records + 1] = {
      acquisitionId = "history-search-vault-other-player",
      playerName = "Other-Realm",
      itemName = "Wanted Vault Item",
      acquiredAt = 1700000400,
    }

    local vaultRows
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      if columns[4] and columns[4].title == dibs.L.PLAYER_VAULT_STATUS then vaultRows = rows end
      return originalAddTable(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    assert_not_nil(frame.vaultFilterSearch)
    frame.vaultFilters = { query = "Wanted", source = "NO_MATCH" }
    frame:Refresh()
    assert_not_nil(frame.vaultFilterClearFields.source)
    frame.vaultFilterClearFields.source.callbacks.OnClick(frame.vaultFilterClearFields.source, "OnClick")
    assert_equal("", frame.vaultFilters.source or "")
    assert_equal("Wanted", frame.vaultFilters.query)
    assert_equal(1, #vaultRows)
    frame.vaultFilterSearch:SetText("Wanted")
    frame.vaultFilterApply.callbacks.OnClick(frame.vaultFilterApply, "OnClick")

    assert_equal(1, #vaultRows)
    assert_true(vaultRows[1][2]:find("Wanted Vault Item", 1, true) ~= nil)
    assert_nil(vaultRows[1].evidence)
    assert_true(not tostring(vaultRows[1].tooltip):find("must-not-display", 1, true))
    frame.vaultFilterClear.callbacks.OnClick(frame.vaultFilterClear, "OnClick")
    assert_equal(2, #vaultRows)
  end)

  it("filters authorized Officer ledger, Pre-Dib, and Vault records by their recorded fields", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    assert_not_nil(dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
      transactionId = "officer-filter-ledger-match",
      type = "DIB_GRANTED",
      amount = 1,
      itemID = 111,
      source = "loot",
    })))
    assert_not_nil(dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", seasonId, {
      transactionId = "officer-filter-ledger-other",
      type = "DIB_GRANTED",
      amount = 1,
      itemID = 222,
      source = "loot",
    })))
    local ledger = dibs.OfficerUI.BuildLedgerDetails(seasonId, { item = "111", source = "loot" })
    assert_equal(1, ledger.transactionCount)
    local pagedLedger = dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 10, {
      item = "111", status = "DIB_GRANTED", source = "loot",
    })
    assert_equal(1, pagedLedger.totalCount)
    assert_true(pagedLedger.lines[1]:find("Tester-Realm", 1, true) ~= nil)

    local originalTime = _G.time
    _G.time = function(value) return os.time(value) end
    local matchingTimestamp = time({ year = 2023, month = 11, day = 14, hour = 12 })
    local outsideTimestamp = time({ year = 2023, month = 11, day = 15, hour = 12 })
    dibs.PreDibs.GetHistory = function()
      return {
        { requestId = "predib-match", seasonId = seasonId, playerName = "Tester-Realm", status = "pending", itemID = 111, itemName = "Wanted", source = "pre-dib", raidName = "Some Raid", bossName = "Some Boss", createdAt = matchingTimestamp },
        { requestId = "predib-other", seasonId = seasonId, playerName = "Other-Realm", status = "confirmed", itemID = 222, itemName = "Other", source = "pre-dib", raidName = "Some Raid", bossName = "Other Boss", createdAt = outsideTimestamp },
      }
    end
    dibs.PreDibs.GetAcquisitions = function() return {} end
    local officerCriteria = {
      item = "111", playerName = "Tester", status = "pending", source = "pre-dib",
      raid = "Some Raid", boss = "Some Boss",
      fromDate = "2023-11-14", toDate = "2023-11-14",
    }
    local preDibs = dibs.OfficerUI.BuildPreDibDetails(seasonId, officerCriteria)
    assert_equal(1, #preDibs.requests)
    assert_true(preDibs.requests[1]:find("Wanted", 1, true) ~= nil)
    local requestRows, requestFilterError = dibs.OfficerUI.BuildRequestView("officer", {
      kind = "predibs", limit = 50, item = "111", status = "pending",
    })
    assert_nil(requestFilterError)
    assert_equal(1, #requestRows)
    assert_equal("predib-match", requestRows[1].requestId)

    dibs.PreDibs.GetAcquisitions = function()
      return {
        { acquisitionId = "vault-match", seasonId = seasonId, playerName = "Tester-Realm", itemID = 111, itemName = "Wanted Vault Item", acquiredAt = matchingTimestamp + 300, source = "MANUAL", verificationState = "MANUAL_RECORDED", raidName = "Some Raid", bossName = "Some Boss" },
        { acquisitionId = "vault-other", seasonId = seasonId, playerName = "Tester-Realm", itemID = 222, itemName = "Other Vault Item", acquiredAt = outsideTimestamp, source = "MANUAL", verificationState = "MANUAL_RECORDED", review = { reason = "private review note" } },
      }
    end
    local vault = dibs.OfficerUI.BuildVaultAcquisitionReview({
      seasonId = seasonId, playerName = "Tester", item = "111", status = "MANUAL_RECORDED",
      source = "MANUAL", raid = "Some Raid", boss = "Some Boss",
      fromDate = "2023-11-14", toDate = "2023-11-14",
    })
    assert_equal(1, #vault.rows)
    assert_equal("vault-match", vault.rows[1].acquisitionId)
    local privateNoteSearch = dibs.OfficerUI.BuildVaultAcquisitionReview({
      seasonId = seasonId, query = "private review note",
    })
    assert_equal(0, #privateNoteSearch.rows)
    _G.time = originalTime
  end)

  it("keeps guild-wide search behind the existing Officer authorization boundary", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = false, guildMembers = { "Tester-Realm", "Other-Realm" } },
    })

    assert_true(dibs.OfficerUI.BuildLedgerDetails(dibs.GetCurrentSeasonId()).hidden)
    assert_true(dibs.OfficerUI.BuildVaultAcquisitionReview({}).hidden)
  end)

  it("clears one Officer Vault filter while preserving the remaining search", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.PreDibs.GetAcquisitions = function()
      return {
        {
          acquisitionId = "officer-clear-filter-vault",
          seasonId = seasonId,
          playerName = "Tester-Realm",
          itemID = 111,
          itemName = "Wanted Vault Item",
          acquiredAt = 1700000300,
          source = "MANUAL",
          verificationState = "MANUAL_RECORDED",
        },
      }
    end

    local frame = dibs.OfficerUI.CreateWindow()
    frame:ActivateRoute("vault")
    frame.historyFilters = { query = "Wanted", source = "NO_MATCH" }
    frame:Refresh()
    assert_not_nil(frame.historyFilterClearFields.source)
    frame.historyFilterClearFields.source.callbacks.OnClick(frame.historyFilterClearFields.source, "OnClick")

    assert_equal("", frame.historyFilters.source or "")
    assert_equal("Wanted", frame.historyFilters.query)
    assert_equal(1, frame.ledgerPage)
    assert_equal(1, #dibs.OfficerUI.BuildVaultAcquisitionReview(frame.historyFilters).rows)
  end)
end)
