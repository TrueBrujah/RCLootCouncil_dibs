local loader = require("helpers.load_addon")
local uiMocks = require("helpers.b11_ui_mocks")

describe("Great Vault UI acceptance", function()
  it("shows LFR in the Player Vault history without changing the recorded classification", function()
    local _, dibs = loader.load({ withAce3 = true })
    local record = dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 21016, "LFR")
    local captured
    local original = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = rows
      return original(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    assert_equal(1, #captured)
    assert_equal("LFR", captured[1][3])
    assert_equal("LFR", record.difficulty)
  end)

  it("links ID-only item references without presenting them as the acquired variant", function()
    local _, dibs = loader.load({ withAce3 = true })
    local record = dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 275658)
    local captured
    local original = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = rows
      return original(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    assert_true(captured[1][2]:find("|Hitem:275658|h", 1, true) ~= nil)
    assert_true(captured[1][2]:find("Primeval Skyfriend", 1, true) ~= nil)
    assert_true(captured[1][4]:find(dibs.L.PLAYER_VAULT_REFERENCE_LABEL, 1, true) ~= nil)
    assert_true(captured[1].tooltip:find(dibs.L.PLAYER_VAULT_VARIANT_UNKNOWN, 1, true) ~= nil)
    assert_nil(record.itemLink)
    assert_nil(record.itemName)
    assert_equal("MANUAL_RECORDED", record.verificationState)
  end)

  it("previews an unambiguous owned variant without rewriting saved evidence", function()
    local _, dibs = loader.load({ withAce3 = true })
    local record = dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 159459)
    local link = "|cffa335ee|Hitem:159459::::::::90:577::35:3:123:456:789::::::|h[Ritual Binder's Ring]|h|r"
    local previous = _G.GetInventoryItemLink
    _G.GetInventoryItemLink = function(_, slot) if slot == 11 then return link end end
    local captured
    local original = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = rows
      return original(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    assert_true(captured[1][2]:find(link, 1, true) ~= nil)
    assert_true(captured[1][4]:find(dibs.L.PLAYER_VAULT_PREVIEW_LABEL, 1, true) ~= nil)
    assert_nil(record.itemLink)
    assert_equal("MANUAL_RECORDED", record.verificationState)
    _G.GetInventoryItemLink = function(_, slot)
      if slot == 11 then return link end
      if slot == 12 then return link:gsub(":123:", ":987:") end
    end
    frame:Refresh()
    assert_true(captured[1][2]:find("|Hitem:159459|h", 1, true) ~= nil)
    assert_true(captured[1][4]:find(dibs.L.PLAYER_VAULT_REFERENCE_LABEL, 1, true) ~= nil)
    assert_nil(captured[1][2]:find(":123:", 1, true))
    _G.GetInventoryItemLink = previous
  end)

  it("previews carried variants and never replaces a recorded exact link", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 159459)
    local link = "|cffa335ee|Hitem:159459::::::::90:577::35:3:123:456:789::::::|h[Ritual Binder's Ring]|h|r"
    local exactLink = "|cffa335ee|Hitem:275658::::::::90:577::35:1:987::::::|h[Recorded variant]|h|r"
    dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 275658, nil, { itemLink = exactLink })
    local previous = _G.C_Container
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemLink = function(_, slot)
        return slot == 1 and link or exactLink:gsub(":987:", ":654:")
      end,
    }
    local captured
    local original = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = rows
      return original(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    local foundPreview, foundExact = false, false
    for _, row in ipairs(captured) do
      if row[2] == link then foundPreview = true end
      if row[2] == exactLink then
        foundExact = true
        assert_nil(row[4]:find(dibs.L.PLAYER_VAULT_PREVIEW_LABEL, 1, true))
      end
    end
    assert_true(foundPreview and foundExact)
    _G.C_Container = previous
  end)

  it("refreshes asynchronously loaded item details and retains an exact recorded variant", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 159459)
    local exactLink = "|cffa335ee|Hitem:12345:999:::::::::::|h[Exact variant]|h|r"
    dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 12345, nil, { itemLink = exactLink })
    local finish, calls = nil, 0
    dibs.LootPipeline.ResolveItem = function(_, callback)
      calls = calls + 1
      finish = callback
      return true
    end
    local captured
    local original = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = rows
      return original(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    frame:Show()
    frame:Refresh()
    assert_equal(1, calls)
    finish({ itemName = "Loaded Ring", itemLink = "|Hitem:159459|h[Loaded Ring]|h" })
    local foundLoaded, foundExact = false, false
    for _, row in ipairs(captured) do
      if row[2]:find("Loaded Ring", 1, true) then foundLoaded = true end
      if row[2] == exactLink then foundExact = true end
    end
    assert_true(foundLoaded and foundExact)
    assert_equal(1, calls)
  end)

  it("shows a private newest-first paginated Player Vault history without spending Dibs", function()
    local _, dibs = loader.load({ withAce3 = true })
    local records = dibs.PreDibs.GetAcquisitions()
    for index = 1, 12 do
      records[#records + 1] = {
        acquisitionId = "vault-" .. index, playerName = dibs.GetPlayerName(),
        itemID = 1000 + index, itemName = "Vault Item " .. index,
        acquiredAt = 1700000000 + index, difficulty = "Heroic",
        seasonId = index <= 6 and "previous-season" or dibs.GetCurrentSeasonId(),
        verificationState = "MANUAL_RECORDED", source = "MANUAL", resetId = "week-42",
        syncState = "LOCAL", evidence = { secret = "private evidence" },
        review = { reason = "private review" },
      }
    end
    records[#records + 1] = {
      acquisitionId = "other-player", playerName = "Other-Realm", itemID = 9999,
      itemName = "Other player item", acquiredAt = 1800000000,
    }
    local balance = dibs.Ledger.GetBalance(dibs.GetPlayerName())
    local captured
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = { columns = columns, rows = rows, options = options, parent = parent }
      return originalAddTable(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    assert_equal(4, #captured.columns)
    assert_equal(10, #captured.rows)
    assert_equal("|Hitem:1012|h[Vault Item 12]|h", captured.rows[1][2])
    assert_equal("Heroic", captured.rows[1][3])
    assert_true(captured.rows[1][4]:find(dibs.L.VAULT_STATUS_MANUAL_RECORDED, 1, true) ~= nil)
    assert_true(captured.rows[1][4]:find(dibs.L.PLAYER_VAULT_REFERENCE_LABEL, 1, true) ~= nil)
    local tooltip = captured.options.cellTooltip(captured.rows[1], 2)
    assert_true(tooltip:find("week-42", 1, true) ~= nil)
    assert_true(tooltip:find("MANUAL", 1, true) ~= nil)
    assert_nil(tooltip:find("private", 1, true))
    assert_nil(captured.rows[1].evidence)
    assert_equal(frame.vaultTablePage.scroll, captured.parent)
    assert_true(captured.options.fluidColumns)
    assert_equal(frame.vaultTablePage.columnHeader, captured.options.headerParent)
    local nextButton = frame.vaultTablePage.pagination.next
    nextButton.callbacks.OnClick(nextButton, "OnClick")
    assert_equal(2, frame.vaultPage)
    assert_equal(2, #captured.rows)
    assert_equal("|Hitem:1002|h[Vault Item 2]|h", captured.rows[1][2])
    assert_equal("|Hitem:1001|h[Vault Item 1]|h", captured.rows[2][2])
    assert_equal(13, #records)
    assert_equal(1001, records[1].itemID)
    assert_equal(balance, dibs.Ledger.GetBalance(dibs.GetPlayerName()))
    frame.aceTabs.content = frame.aceTabs.frame
    frame.aceTabs.content.GetWidth = function() return 420 end
    frame:Refresh()
    assert_equal(420, captured.options.widthHint)
    frame.aceTabs.content.GetWidth = function() return 1240 end
    frame:Refresh()
    assert_equal(1240, captured.options.widthHint)
  end)

  it("localizes Player Vault navigation and distinguishes empty from unavailable history", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { locale = "frFR" } })
    local vaultEntry
    for _, entry in ipairs(dibs.PlayerUI.GetNavigation()) do
      if entry.value == "vault" then vaultEntry = entry end
    end
    assert_equal("Grand coffre", vaultEntry.text)
    local emptyText, labels = nil, {}
    local originalAddTable, originalAddLabel = dibs.AceGUI.AddTable, dibs.AceGUI.AddLabel
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      if columns[4] and columns[4].title == dibs.L.PLAYER_VAULT_STATUS then
        emptyText = options.emptyText
        assert_equal(0, #rows)
      end
      return originalAddTable(shell, parent, columns, rows, height, actions, options)
    end
    dibs.AceGUI.AddLabel = function(shell, parent, text, fullWidth)
      labels[text] = true
      return originalAddLabel(shell, parent, text, fullWidth)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    assert_equal(dibs.L.PLAYER_VAULT_EMPTY, emptyText)
    assert_equal(1, frame.vaultPage)
    dibs.PreDibs.GetAcquisitionsForPlayer = nil
    frame:Refresh()
    assert_true(labels[dibs.L.PLAYER_VAULT_UNAVAILABLE])
  end)

  it("keeps full Vault names and statuses readable and opens exact or reference links", function()
    local _, dibs = loader.load({ withAce3 = true })
    local link = "|cffa335ee|Hitem:268263::::::::90:577::6:1:123|h[Frostscale's Mystic Frond]|h|r"
    local saved = dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 268263, "Mythic", {
      itemLink = link, itemName = "Frostscale's Mystic Frond",
    })
    local previousDate, previousItemRef, previousTooltip = _G.date, _G.SetItemRef, _G.GameTooltip
    _G.date = function(pattern)
      return pattern == "%Y-%m-%d" and "2026-10-15" or "2026-10-15 15:48:00"
    end
    local opened, hovered
    _G.SetItemRef = function(itemString, text, button)
      opened = { itemString, text, button }
    end
    _G.GameTooltip = {
      SetOwner = function() end,
      SetText = function() end,
      SetHyperlink = function(_, value) hovered = value end,
      Show = function() end,
    }
    local captured
    local original = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, actions, options)
      captured = { columns = columns, rows = rows, options = options }
      return original(shell, parent, columns, rows, height, actions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    frame.aceTabs.content = frame.aceTabs.frame
    for _, width in ipairs({ 420, 600, 1240 }) do
      frame.aceTabs.content.GetWidth = function() return width end
      frame:Refresh()
      local widths, overflow, total = dibs.AceGUI.AllocateFluidColumnWidths(
        captured.columns, width, captured.options)
      assert_false(overflow)
      assert_true(total <= width + 0.01)
      assert_equal(84, widths[1])
      assert_equal(76, widths[3])
      assert_true(widths[2] > widths[4])
      for _, column in ipairs(captured.columns) do assert_true(column.wrap) end
      local row = captured.rows[1]
      assert_equal("2026-10-15", row[1])
      assert_true(row.tooltip:find("2026-10-15 15:48:00", 1, true) ~= nil)
      local rendered
      for _, child in ipairs(frame.vaultHistoryTable.children) do
        if child._dibsDataGridRow then rendered = child end
      end
      assert_not_nil(rendered)
      assert_equal(link, rendered.children[2].text)
      assert_equal(dibs.L.VAULT_STATUS_MANUAL_RECORDED, rendered.children[4].text)
      rendered.children[2].frame:GetScript("OnEnter")(rendered.children[2].frame)
      assert_equal(link, hovered)
      rendered.children[2].frame:GetScript("OnMouseUp")(rendered.children[2].frame, "LeftButton")
      assert_equal("item:268263::::::::90:577::6:1:123", opened[1])
      assert_equal(link, opened[2])
      assert_equal("LeftButton", opened[3])
    end
    dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 275658, "Heroic")
    frame:Refresh()
    local reference
    for _, row in ipairs(captured.rows) do
      if row.itemLink:find("|Hitem:275658|h", 1, true) then reference = row end
    end
    assert_not_nil(reference)
    assert_true(reference[4]:find(dibs.L.PLAYER_VAULT_REFERENCE_LABEL, 1, true) ~= nil)
    local previousInfo = _G.C_Item.GetItemInfo
    local referenceLink = "|cnIQ4:|Hitem:275658::::::::90:257:::::::::|h[Primeval Skyfriend]|h|r"
    _G.C_Item.GetItemInfo = function() return nil, nil end
    opened = nil
    _G.__dibsMessages = {}
    captured.options.onRowClick(reference, 2)
    assert_nil(opened)
    assert_true(_G.__dibsMessages[1]:find(dibs.L.PLAYER_VAULT_LINK_UNAVAILABLE, 1, true) ~= nil)
    _G.C_Item.GetItemInfo = function(input)
      assert_equal("item:275658", input)
      return "Primeval Skyfriend", referenceLink
    end
    captured.options.onRowClick(reference, 2)
    assert_equal("item:275658::::::::90:257:::::::::", opened[1])
    assert_equal(referenceLink, opened[2])
    assert_equal("|Hitem:275658|h[Primeval Skyfriend]|h", reference.itemLink)
    assert_equal(link, saved.itemLink)
    assert_nil(dibs.PreDibs.GetAcquisitions()[2].itemLink)
    _G.SetItemRef = nil
    _G.__dibsMessages = {}
    captured.options.onRowClick(reference, 2)
    assert_true(_G.__dibsMessages[1]:find(dibs.L.PLAYER_VAULT_LINK_UNAVAILABLE, 1, true) ~= nil)
    _G.C_Item.GetItemInfo = previousInfo
    _G.date, _G.SetItemRef, _G.GameTooltip = previousDate, previousItemRef, previousTooltip
  end)

  it("documents the manual Vault fallback in slash command help", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.HandleSlashCommand("help")
    local found = false
    local prefixExplained = false
    for _, message in ipairs(_G.__dibsMessages or {}) do
      if message:find("vault <item link | [Item Name] | itemID> <LFR | Normal | Heroic | Mythic>", 1, true) then found = true end
      if message:find("prefix each command with /dibs", 1, true) then prefixExplained = true end
    end
    assert_true(found and prefixExplained)
  end)

  it("keeps player projections private while exposing status and reset context", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.PreDibs.GetAcquisitionsForPlayer = function()
      return {
        {
          itemID = 275658,
          itemName = "Primeval Skyfriend",
          verificationState = "AUTOMATIC_CONFIRMED",
          resetId = "week-42",
          acquiredAt = 1700000100,
          source = "RETAIL_CLAIM",
          syncState = "SYNCED",
          evidence = { privateToken = "hidden" },
        },
      }
    end
    local summary = dibs.PlayerUI.GetSummary()
    assert_equal(1, #summary.acquisitions)
    assert_equal("AUTOMATIC_CONFIRMED", summary.acquisitions[1].verificationState)
    assert_equal("week-42", summary.acquisitions[1].resetId)
    assert_nil(summary.acquisitions[1].evidence)
    assert_nil(summary.acquisitions[1].privateToken)
  end)

  it("sorts bounded Officer history and keeps date and search values visible", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    dibs.PreDibs.GetAcquisitions = function()
      return {
        { acquisitionId = "old", playerName = "Tester-Realm", itemID = 100, itemName = "Old Item", acquiredAt = 1700000000, verificationState = "LEGACY_RECORDED", resetId = "week-41", source = "MIGRATED" },
        { acquisitionId = "new", playerName = "Officer-Realm", itemID = 200, itemName = "New Item", acquiredAt = 1700000200, verificationState = "MANUAL_RECORDED", resetId = "week-42", source = "MANUAL" },
      }
    end
    local page = dibs.OfficerUI.GetPagedView("vault", nil, 1, 1)
    assert_equal(2, page.totalCount)
    assert_equal(2, page.totalPages)
    assert_true(page.lines[1]:find("New Item", 1, true) ~= nil)
    assert_true(page.lines[1]:find("2026", 1, true) ~= nil)

    local filtered = dibs.OfficerUI.GetPagedView("vault", nil, 1, 8, "Old Item")
    assert_equal(1, filtered.totalCount)
    assert_true(filtered.lines[1]:find("Old Item", 1, true) ~= nil)

    local empty = dibs.OfficerUI.GetPagedView("vault", nil, 1, 8, "missing")
    assert_equal(0, empty.totalCount)
    assert_equal(dibs.L.HISTORY_FILTER_NO_RESULTS, empty.lines[1])
  end)

  it("preserves responsive minimums for the Vault table window", function()
    local _, dibs = loader.load({ withAce3 = true })
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    local shell = dibs.AceGUI.CreateWindow("Vault Review", 240, 180)
    assert_equal(metrics.minWidth, shell.layout.width)
    assert_equal(metrics.minHeight, shell.layout.height)
    assert_true(metrics.maxWidth >= metrics.minWidth)
    assert_true(metrics.maxHeight >= metrics.minHeight)
  end)

  it("keeps Vault Review headers on one row when the Officer content area is narrow", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    dibs.PreDibs.GetAcquisitions = function()
      return {
        {
          acquisitionId = "compact-vault", playerName = "Tester-Realm", itemID = 275658,
          itemName = "Primeval Skyfriend", acquiredAt = 1700000100,
          verificationState = "MANUAL_RECORDED", resetId = "week-42",
          source = "MANUAL", syncState = "SYNCED", review = { reason = "Verified in game" },
        },
      }
    end
    local captured
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      captured = { columns = columns, rows = rows, options = options }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.OfficerUI.CreateWindow("vault")
    assert_equal(4, #captured.columns)
    assert_equal("Date", captured.columns[1].title)
    assert_equal("Player", captured.columns[2].title)
    assert_equal("Status", captured.columns[3].title)
    assert_equal("Item", captured.columns[4].title)
    assert_true(captured.options.fluidColumns)
    assert_equal("Tester-Realm", captured.rows[1][2])
    assert_equal("Primeval Skyfriend", captured.rows[1][4])
    assert_true(captured.options.cellTooltip(captured.rows[1], 4):find("week-42", 1, true) ~= nil)
    frame.contentHost.frame.GetWidth = function() return 1240 end
    frame:Refresh()
    assert_equal(8, #captured.columns)
    assert_equal("CENTER", captured.columns[1].align)
    assert_equal("CENTER", captured.columns[3].align)
    assert_not_nil(frame.ledgerTablePage)
  end)

  it("uses the shared AceGUI dropdown style for Vault review controls", function()
    local msaNames = {
      "MSA_DropDownMenu_Create", "MSA_DropDownMenu_Initialize", "MSA_DropDownMenu_CreateInfo",
      "MSA_DropDownMenu_AddButton", "MSA_ToggleDropDownMenu", "MSA_DropDownMenu_SetText",
      "MSA_DropDownMenu_SetWidth", "MSA_DropDownMenu_JustifyText", "MSA_DropDownMenu_SetSelectedValue",
    }
    local previous = {}
    for _, name in ipairs(msaNames) do previous[name] = _G[name] end
    local msaState = uiMocks.installMSA()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("vault")

    assert_equal("Dropdown", frame.vaultAcquisition.kind)
    assert_equal("Dropdown", frame.vaultDecision.kind)
    assert_equal("Dropdown", frame.vaultStatusControl.kind)
    assert_equal(0, msaState.created)

    for _, name in ipairs(msaNames) do _G[name] = previous[name] end
  end)
end)
