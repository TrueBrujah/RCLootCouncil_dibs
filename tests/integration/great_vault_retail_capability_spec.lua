local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function installRetail(dibs)
  local available = true
  local link = "|cffa335ee|Hitem:21016::::::::::::|h[Vault Ring]|h|r"
  _G.C_WeeklyRewards = {
    CanClaimRewards = function() return available end,
    ClaimReward = function() end,
    GetActivities = function()
      return { { claimID = 77, rewards = { { itemDBID = 9001 } } } }
    end,
    GetItemHyperlink = function() return link end,
  }
  _G.C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 86400 end }
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
end)
