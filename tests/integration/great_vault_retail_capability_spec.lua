local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function installRetail(dibs)
  local available = true
  local link = "|cffa335ee|Hitem:21016::::::::::::|h[Vault Ring]|h|r"
  _G.C_WeeklyRewards = {
    CanClaimRewards = function() return available end,
    ClaimReward = function() end,
    GetActivities = function()
      return { { claimID = 77, type = 3, level = 15, rewards = { { itemDBID = 9001 } } } }
    end,
    GetItemHyperlink = function() return link end,
  }
  _G.C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 86400 end }
  _G.C_TooltipInfo = { GetHyperlink = function()
    return { lines = { { leftText = "Vault Ring" }, { leftText = "Heroic" }, { leftText = "Upgrade Level: Hero 1/6" } } }
  end }
  dibs.GreatVault.Initialize()
  local function claim()
    for _, hook in ipairs(C_WeeklyRewards.__secureHooks.ClaimReward) do hook(77) end
  end
  local function loot(itemLink, guid)
    wow.dispatch("CHAT_MSG_LOOT", "You receive loot: " .. (itemLink or link),
      nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid or UnitGUID("player"))
  end
  return claim, loot, function() available = false end
end

describe("Great Vault Retail capability", function()
  local previousTooltip
  before_each(function()
    previousTooltip = _G.C_TooltipInfo
    _G.C_TooltipInfo = nil
  end)
  after_each(function() _G.C_TooltipInfo = previousTooltip end)

  it("initializes safely when no Retail Great Vault API is present", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })

    assert_not_nil(dibs.GreatVault)
    assert_equal("UNAVAILABLE", dibs.GreatVault.GetCapability().status)
    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21016, "Heroic")
    assert_equal("MANUAL_RECORDED", record.verificationState)
  end)

  it("records only a selected reward received by the local player after claim completion", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    assert_equal("OPERATIONAL", dibs.GreatVault.GetCapability().status)
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    claim()
    loot(nil, "Player-OTHER")
    loot("item:99999")
    loot("|cffa335ee|Hitem:21016:999:::::::::::|h[Another variant]|h|r")
    complete()
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    local before = #dibs.Ledger.GetAllTransactions()
    loot()
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal(21016, records[1].itemID)
    assert_equal("Heroic", records[1].difficulty)
    assert_equal("AUTOMATIC_CONFIRMED", records[1].verificationState)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
    loot()
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
  end)

  it("handles loot arriving before the rewards update and installs the hook only once", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    dibs.GreatVault.Initialize()
    assert_equal(1, #C_WeeklyRewards.__secureHooks.ClaimReward)
    claim()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    complete()
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
  end)

  it("does not record an abandoned selection or merely viewing available rewards", function()
    local _, dibs = loader.load()
    local claim = installRetail(dibs)
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    wow.dispatch("WEEKLY_REWARDS_ITEM_CHANGED")
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("expires incomplete observations instead of attributing a later drop to the Vault", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    claim()
    local originalTime = _G.time
    local expiredAt = time() + 121
    _G.time = function() return expiredAt end
    complete()
    loot()
    _G.time = originalTime
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("refuses confirmation when the guild context changes during a claim", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    claim()
    local original = dibs.GetGuildKey
    dibs.GetGuildKey = function() return "another-guild" end
    complete()
    loot()
    dibs.GetGuildKey = original
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("does not capture live claims in Developer Mode", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    dibs.DeveloperMode.SetEnabled(true)
    claim()
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("does not infer the selected reward from an unknown claim ID", function()
    local _, dibs = loader.load()
    local _, loot, complete = installRetail(dibs)
    for _, hook in ipairs(C_WeeklyRewards.__secureHooks.ClaimReward) do hook(999) end
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("refuses an ambiguous multi-item choice instead of selecting its last reward", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_WeeklyRewards.GetActivities = function()
      return { { claimID = 77, rewards = { { itemDBID = 9001 }, { itemDBID = 9002 } } } }
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("classifies a Mythic+ reward by its Hero upgrade track", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_WeeklyRewards.GetActivities = function()
      return { { claimID = 77, type = 1, level = 10, rewards = { { itemDBID = 9001 } } } }
    end
    C_Item.GetItemUpgradeInfo = function() return { trackString = "Hero", currentLevel = 2, maxLevel = 6 } end
    C_TooltipInfo.GetHyperlink = function()
      return { lines = {
        { leftText = "Vault Ring" }, { leftText = "Mythic+" }, { leftText = "Upgrade Level: Hero 2/6" },
      } }
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    complete()
    loot()
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal("Heroic", records[1].difficulty)
    assert_nil(records[1].upgradeTrack)
  end)

  it("preserves each raid origin instead of promoting it to the reward's upgrade track", function()
    for _, case in ipairs({
      { "Raid Finder", "Veteran", "LFR" },
      { "Normal", "Hero", "Normal" }, { "Heroic", "Myth", "Heroic" }, { "Mythic", "Myth", "Mythic" },
    }) do
      local _, dibs = loader.load()
      local claim, loot, complete = installRetail(dibs)
      C_Item.GetItemUpgradeInfo = function() return { trackString = case[2], currentLevel = 2, maxLevel = 6 } end
      C_TooltipInfo.GetHyperlink = function()
        return { lines = {
          { leftText = "Vault Ring" }, { leftText = case[1] }, { leftText = "Upgrade Level: " .. case[2] .. " 2/6" },
        } }
      end
      wow.dispatch("WEEKLY_REWARDS_UPDATE")
      local balance = dibs.Ledger.GetBalance(dibs.GetPlayerName())
      claim()
      complete()
      loot()
      local records = dibs.PreDibs.GetAcquisitions()
      assert_equal(1, #records)
      assert_equal(case[3], records[1].difficulty)
      assert_nil(records[1].upgradeTrack)
      assert_equal("AUTOMATIC_CONFIRMED", records[1].verificationState)
      assert_equal(balance, dibs.Ledger.GetBalance(dibs.GetPlayerName()))
    end
  end)

  it("records a completed Heroic dungeon reward on Veteran as Heroic without spending Dibs", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_Item.GetItemUpgradeInfo = function() return { trackString = "Veteran", currentLevel = 3, maxLevel = 6 } end
    C_TooltipInfo.GetHyperlink = function()
      return { lines = {
        { leftText = "Vault Ring" }, { leftText = "Heroic" }, { leftText = "Upgrade Level: Veteran 3/6" },
      } }
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    local before = #dibs.Ledger.GetAllTransactions()
    claim()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    complete()
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    loot()
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal("Heroic", records[1].difficulty)
    assert_equal("AUTOMATIC_CONFIRMED", records[1].verificationState)
    assert_nil(records[1].upgradeTrack)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("retries unavailable item data when the selected reward is finally received", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_TooltipInfo.GetHyperlink = function() return nil end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    complete()
    C_TooltipInfo.GetHyperlink = function()
      return { lines = { { leftText = "Vault Ring" }, { leftText = "Normal" }, { leftText = "Upgrade Level: Champion 3/6" } } }
    end
    loot()
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal("Normal", records[1].difficulty)
    assert_nil(records[1].upgradeTrack)
  end)

  it("records nothing when only the upgrade track is known, not the original difficulty", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_WeeklyRewards.GetActivities = function()
      return { { claimID = 77, type = 1, level = 10, rewards = { { itemDBID = 9001 } } } }
    end
    C_Item.GetItemUpgradeInfo = function() return { trackString = "Myth" } end
    C_TooltipInfo.GetHyperlink = function()
      return { lines = { { leftText = "Vault Ring" }, { leftText = "Upgrade Level: Myth 2/6" } } }
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    _G.__dibsMessages = {}
    claim()
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    local reported = false
    for _, message in ipairs(_G.__dibsMessages) do
      if message:find(dibs.L.VAULT_REASON_DIFFICULTY_UNAVAILABLE, 1, true) then reported = true end
    end
    assert_true(reported)
  end)

  it("lets the manual command retain the original difficulty from the item tooltip", function()
    local _, dibs = loader.load()
    installRetail(dibs)
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    dibs.HandleSlashCommand("vault |cffa335ee|Hitem:21016::::::::::::|h[Vault Ring]|h|r")
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal("Heroic", records[1].difficulty)
    assert_equal("MANUAL_RECORDED", records[1].verificationState)
  end)

  it("captures the selected equipment when its reward bundle also includes a keystone", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_Item.IsItemKeystoneByID = function(id) return id == 180653 end
    C_WeeklyRewards.GetActivities = function()
      return { { claimID = 77, rewards = {
        { id = 21016, itemDBID = 9001 }, { id = 180653, itemDBID = 9002 },
      } } }
    end
    C_WeeklyRewards.GetItemHyperlink = function(id)
      if id == 9002 then return "|Hitem:180653::::::::::::|h[Keystone]|h" end
      return "|cffa335ee|Hitem:21016::::::::::::|h[Vault Ring]|h|r"
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    local before = #dibs.Ledger.GetAllTransactions()
    claim()
    complete()
    loot()
    local records = dibs.PreDibs.GetAcquisitions()
    assert_equal(1, #records)
    assert_equal(21016, records[1].itemID)
    assert_equal("AUTOMATIC_CONFIRMED", records[1].verificationState)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("excludes non-equippable supplemental items but never guesses a missing reward link", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_Item.IsEquippableItem = function(id) return id == 21016 end
    C_WeeklyRewards.GetActivities = function()
      return { { claimID = 77, rewards = {
        { id = 21016, itemDBID = 9001 }, { id = 12345, itemDBID = 9002 },
      } } }
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    complete()
    loot()
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())

    _, dibs = loader.load()
    claim, loot, complete = installRetail(dibs)
    C_WeeklyRewards.GetActivities = function()
      return { { claimID = 77, rewards = { { itemDBID = 9001 }, { itemDBID = 9002 } } } }
    end
    C_WeeklyRewards.GetItemHyperlink = function(id)
      if id == 9001 then return "|cffa335ee|Hitem:21016::::::::::::|h[Vault Ring]|h|r" end
    end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
  end)

  it("recognizes localized self loot with an empty GUID without accepting another player's loot", function()
    local previous = _G.LOOT_ITEM_SELF
    for _, format in ipairs({ "You receive loot: %s.", "Vous recevez le butin : %s." }) do
      local _, dibs = loader.load()
      local claim, _, complete = installRetail(dibs)
      _G.LOOT_ITEM_SELF = format
      local link = "|cffa335ee|Hitem:21016::::::::::::|h[Vault Ring]|h|r"
      claim()
      complete()
      wow.dispatch("CHAT_MSG_LOOT", "Other receives loot: " .. link, "Other-Realm")
      assert_equal(0, #dibs.PreDibs.GetAcquisitions())
      wow.dispatch("CHAT_MSG_LOOT", string.format(format, link), "", "", "", "", "", 0, 0, "", 0, 1, "")
      assert_equal(1, #dibs.PreDibs.GetAcquisitions())
    end
    _G.LOOT_ITEM_SELF = previous
  end)

  it("recovers a proven receipt when its difficulty loads after the loot event", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    C_TooltipInfo.GetHyperlink = function() return nil end
    wow.dispatch("WEEKLY_REWARDS_UPDATE")
    claim()
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    assert_equal("DIFFICULTY_UNAVAILABLE", dibs.GreatVault.GetCaptureStatus().lastReasonCode)
    C_TooltipInfo.GetHyperlink = function()
      return { lines = { { leftText = "Vault Ring" }, { leftText = "Heroic" },
        { leftText = "Upgrade Level: Hero 1/6" } } }
    end
    wow.dispatch("GET_ITEM_INFO_RECEIVED", 21016, true)
    wow.dispatch("GET_ITEM_INFO_RECEIVED", 21016, true)
    assert_equal(1, #dibs.PreDibs.GetAcquisitions())
    assert_equal("CLAIM_CONFIRMED", dibs.GreatVault.GetCaptureStatus().lastReasonCode)
    assert_equal(21016, dibs.GreatVault.GetCaptureStatus().lastItemID)
  end)

  it("isolates runtime capture diagnostics and cached reward choices by guild", function()
    local _, dibs = loader.load()
    local claim, loot, complete = installRetail(dibs)
    assert_equal(1, dibs.GreatVault.GetCaptureStatus().choiceCount)
    claim()
    assert_equal("CLAIM_PENDING", dibs.GreatVault.GetCaptureStatus().lastReasonCode)
    local original = dibs.GetGuildKey
    dibs.GetGuildKey = function() return "another-guild" end
    local status = dibs.GreatVault.GetCaptureStatus()
    assert_equal(0, status.choiceCount)
    assert_nil(status.lastReasonCode)
    claim()
    complete()
    loot()
    assert_equal(0, #dibs.PreDibs.GetAcquisitions())
    dibs.GetGuildKey = original
  end)

  it("refreshes pending and failed diagnostics and displays the claimed item in the open Player Vault page", function()
    local _, dibs = loader.load({ withAce3 = true })
    require("helpers.configured_addon").configure(dibs)
    local claim, loot, complete = installRetail(dibs)
    local rows, labels = nil, {}
    local addTable, addLabel = dibs.AceGUI.AddTable, dibs.AceGUI.AddLabel
    dibs.AceGUI.AddTable = function(shell, parent, columns, values, ...)
      if columns[4] and columns[4].title == dibs.L.PLAYER_VAULT_STATUS then rows = values end
      return addTable(shell, parent, columns, values, ...)
    end
    dibs.AceGUI.AddLabel = function(shell, parent, text, ...)
      labels[text] = true
      return addLabel(shell, parent, text, ...)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("vault")
    frame:Show()
    assert_equal(0, #rows)
    claim()
    assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_LAST, dibs.L.VAULT_REASON_CLAIM_PENDING)])
    for _, hook in ipairs(C_WeeklyRewards.__secureHooks.ClaimReward) do hook(999) end
    assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_LAST, dibs.L.VAULT_REASON_CLAIM_ITEM_UNAVAILABLE)])
    claim()
    local before = #dibs.Ledger.GetAllTransactions()
    complete()
    loot()
    assert_equal(1, #rows)
    assert_true(rows[1][2]:find("Vault Ring", 1, true) ~= nil)
    assert_true(rows[1][4]:find(dibs.L.VAULT_STATUS_AUTOMATIC_CONFIRMED, 1, true) ~= nil)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
