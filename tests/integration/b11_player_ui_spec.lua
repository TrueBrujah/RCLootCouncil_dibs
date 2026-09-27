local loader = require("helpers.load_addon")

local function setup(options)
  options = options or {}
  options.withAce3 = true
  return loader.load(options)
end

local function containsForbiddenValue(value, forbidden)
  if type(value) == "string" then
    for _, text in ipairs(forbidden) do
      if value:find(text, 1, true) then return true end
    end
    return false
  end
  if type(value) ~= "table" then return false end
  for key, item in pairs(value) do
    if containsForbiddenValue(key, forbidden) or containsForbiddenValue(item, forbidden) then return true end
  end
  return false
end

describe("B11c Player UI", function()
  it("exposes the player views and a diagnostics entry", function()
    local _, dibs = setup()
    local navigation = dibs.PlayerUI.GetNavigation()
    assert_equal(4, #navigation)
    assert_equal("My Dibs", navigation[1].text)
    assert_equal("Requests", navigation[2].text)
    assert_equal("History", navigation[3].text)
    assert_equal("Diagnostics", navigation[4].text)
    assert_equal("my-dibs", navigation[1].value)
    assert_equal("requests", navigation[2].value)
    assert_equal("history", navigation[3].value)
    assert_equal("diagnostics", navigation[4].value)
  end)

  it("lets a player enable diagnostics and run a sync channel test", function()
    local _, dibs = setup({ wow = {
      playerName = "Player-Realm", guildLeader = false,
      guildMembers = { "GM-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    assert_not_nil(frame.developerModeToggle)
    assert_nil(frame.channelTestAutoPingToggle)
    assert_nil(frame.channelTestRunButton)
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)
    assert_true(dibs.DeveloperMode.IsEnabled())
    assert_not_nil(frame.channelTestRunButton)
    assert_not_nil(frame.channelTestScanButton)
    _G.time = function() return 1700000000 end
    local sentBefore = #dibs.Ace3.libs.comm.sent
    frame.channelTestRunButton.callbacks.OnClick(frame.channelTestRunButton, "OnClick")
    assert_equal(sentBefore + 1, #dibs.Ace3.libs.comm.sent)
    local outgoing = dibs.Ace3.Deserialize(dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].payload)
    assert_equal("CHANNEL_TEST", outgoing.type)
    assert_equal("GUILD", outgoing.testChannel)
    assert_true(frame.channelTestStatus:find(outgoing.testId, 1, true) ~= nil)
    local playerRow, officerRow
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do
      if row[1] == "Player-Realm" then playerRow = row end
      if row[1] == "Officer-Realm" then officerRow = row end
    end
    assert_not_nil(playerRow)
    assert_true(playerRow[2]:find("YOU", 1, true) ~= nil)
    assert_not_nil(officerRow)
    assert_true(officerRow[2]:find("WAIT", 1, true) ~= nil)
    local acknowledgement = assert(dibs.Sync.BuildEnvelope({ type = "CHANNEL_TEST_ACK", testId = outgoing.testId,
      testChannel = "GUILD", ackTransport = "WHISPER", result = "RECEIVED",
      reasonCode = "CHANNEL_MESSAGE_VALIDATED" }))
    acknowledgement.senderNameRealm = "Officer-Realm"
    acknowledgement.senderMemberKey = "officer-realm"
    assert_true(dibs.Sync.Receive(acknowledgement, "Officer-Realm", "WHISPER"))
    officerRow = nil
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do
      if row[1] == "Officer-Realm" then officerRow = row; break end
    end
    assert_not_nil(officerRow)
    assert_true(officerRow[2]:find("PONG", 1, true) ~= nil)
    assert_true(officerRow[2]:find(date("%H:%M", 1700000000), 1, true) ~= nil)
  end)

  it("shows a received probe's reason when local Developer Mode suppresses the reply", function()
    local _, dibs = setup({ wow = { playerName = "Firebutt-Realm", guildLeader = false,
      guildMembers = { "Officer-Realm", "Firebutt-Realm" }, guildRankIndices = { [1] = 1, [2] = 3 } } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    local probe = assert(dibs.Sync.BuildEnvelope({ type = "CHANNEL_TEST", testId = "firebutt-probe",
      testChannel = "GUILD", startedAt = time() }))
    probe.senderNameRealm = "Officer-Realm"
    probe.senderMemberKey = "officer-realm"

    local accepted, reason = dibs.Sync.Receive(probe, "Officer-Realm", "GUILD")
    assert_false(accepted)
    assert_equal("DEVELOPER_MODE_REQUIRED", reason)
    assert_not_nil(frame.channelTestReceivedStatus)
    assert_true(frame.channelTestReceivedStatus.text:find("Last received probe: GUILD from Officer-Realm", 1, true) ~= nil)
    assert_true(frame.channelTestReceivedStatus.text:find("DEVELOPER_MODE_REQUIRED", 1, true) ~= nil)
  end)

  it("shows a duplicated realm suffix only once in the channel matrix", function()
    local _, dibs = setup({ wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Manu-Zul'jin-Zul'jin-Zul'jin" } } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)

    local found
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do
      if row[1]:find("Manu", 1, true) then found = row[1]; break end
    end
    assert_equal("Manu-Zul'jin", found)
  end)

  it("does not report no-pong for members outside the probed channel audience", function()
    local _, dibs = setup({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)

    local sent, testId = dibs.Sync.StartChannelTest("OFFICER")
    assert_true(sent)
    frame:Refresh()
    local statuses = {}
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do statuses[row[1]] = row[3] end
    assert_true(statuses["Officer-Realm"]:find("--", 1, true) == nil)
    assert_true(statuses["Player-Realm"]:find("--", 1, true) ~= nil)

    sent = dibs.Sync.StartChannelTest("WHISPER", "Officer-Realm")
    assert_true(sent)
    frame:Refresh()
    local whisperStatuses = {}
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do whisperStatuses[row[1]] = row[7] end
    assert_true(whisperStatuses["Officer-Realm"]:find("--", 1, true) == nil)
    assert_true(whisperStatuses["Player-Realm"]:find("--", 1, true) ~= nil)

    _G.IsInRaid = function() return true end
    _G.IsInGroup = function() return true end
    _G.GetNumGroupMembers = function() return 2 end
    _G.GetRaidRosterInfo = function(index)
      if index == 1 then return "Tester-Realm" end
      if index == 2 then return "Officer-Realm" end
    end
    sent = dibs.Sync.StartChannelTest("RAID")
    assert_true(sent)
    frame:Refresh()
    local raidStatuses = {}
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do raidStatuses[row[1]] = row[4] end
    assert_true(raidStatuses["Officer-Realm"]:find("--", 1, true) == nil)
    assert_true(raidStatuses["Player-Realm"]:find("--", 1, true) ~= nil)
    assert_true(type(testId) == "string")
  end)

  it("limits automatic channel scans to opted-in GM or Officer diagnostics sessions", function()
    local _, dibs = setup({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)
    assert_not_nil(frame.channelTestAutoPingToggle)

    local timerCount = #dibs.Ace3.libs.timer.scheduled
    frame.channelTestAutoPingToggle.callbacks.OnValueChanged(frame.channelTestAutoPingToggle, "OnValueChanged", true)
    assert_true(frame.channelTestAutoPingScheduled)
    assert_equal(timerCount + 3, #dibs.Ace3.libs.timer.scheduled)
    assert_equal(300, dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].delay)
    local staleCallback = dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].callback

    frame.SelectTab("history")
    assert_false(frame.channelTestAutoPingScheduled)
    frame.SelectTab("diagnostics")
    assert_true(frame.channelTestAutoPingScheduled)
    staleCallback()
    assert_true(frame.channelTestAutoPingScheduled)

    local activeCallback = dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].callback
    local sentBefore = #dibs.Ace3.libs.comm.sent
    activeCallback()
    assert_equal(sentBefore + 2, #dibs.Ace3.libs.comm.sent)
    assert_true(frame.channelTestAutoPingScheduled)
    frame.SelectTab("history")
    assert_false(frame.channelTestAutoPingScheduled)
  end)

  it("projects authoritative personal data without administrative or technical details", function()
    local _, dibs = setup()
    dibs.PlayerUI.GetSummary = function()
      return {
        player = "Tester-Realm",
        balance = 17,
        season = { id = 1, name = "Midnight" },
        activePreDibs = {
          { requestId = "request-1", itemID = 123, itemName = "Midnight Blade", status = "pending", createdAt = 100 },
        },
        acquisitions = {},
      }
    end
    dibs.Readiness.Evaluate = function() return {
      status = "Ready", reasonCodes = {}, integrationStatus = "Ready", liveConsumptionAllowed = true,
    } end
    dibs.Ledger.GetHistory = function()
      return {
        {
          createdAt = 100, itemName = "Midnight Blade", type = "AWARD", amount = -3,
          transactionId = "technical-id", epoch = 4, contentHash = "technical-hash",
          rootHash = "technical-root", evidenceId = "technical-evidence",
        },
      }
    end

    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("Tester-Realm", view.player)
    assert_equal(17, view.balance)
    assert_equal("Midnight", view.seasonName)
    assert_equal(1, #view.activePreDibs)
    assert_equal("Ready", view.status.label)
    assert_nil(view.empty.activePreDibs)
    assert_false(containsForbiddenValue(view, { "RCLootCouncil - Dibs options", "Officer", "GM", "Developer", "hash", "epoch", "root", "evidence" }))
  end)

  it("uses intentional empty states and player-safe readiness explanations", function()
    local _, dibs = setup()
    dibs.PlayerUI.GetSummary = function()
      return { player = "Tester-Realm", balance = 0, season = nil, activePreDibs = {}, acquisitions = {} }
    end
    dibs.Ledger.GetHistory = function() return {} end
    dibs.Readiness.Evaluate = function() return {
      status = "Blocked", reasonCodes = { COORDINATOR_UNAVAILABLE = true },
    } end
    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("No active Pre-Dibs.", view.empty.activePreDibs)
    assert_equal("No history yet.", view.empty.history)
    assert_equal("Dibs temporarily unavailable", view.status.label)
    assert_equal("Guild Dibs is unavailable right now. Try again later or contact an Officer.", view.status.explanation)

    local status = dibs.PlayerUI.GetStatusPresentation({ status = "Unavailable", reasonCodes = { SYNC_BEHIND = true } })
    assert_equal("Syncing guild data", status.label)
    assert_equal("Your guild Dibs data is catching up. You can try again shortly.", status.explanation)
    status = dibs.PlayerUI.GetStatusPresentation({ status = "Unavailable", reasonCodes = { RECOVERY_PENDING = true } })
    assert_equal("Guild Dibs recovery in progress", status.label)
  end)

  it("keeps sandbox role simulation out of the normal Player surface", function()
    local _, dibs = setup({ wow = { guildLeader = true } })
    dibs.DeveloperMode.SetEnabled(true)
    local before = loader.snapshotProductionState(dibs)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true, role = "guild_master" }))
    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("My Dibs", view.navigation[1].text)
    assert_false(containsForbiddenValue(view, { "Officer dashboard", "review administration", "reconciliation", "Developer Mode" }))
    assert_true(loader.productionStateEquals(dibs, before))
    assert_true(dibs.DeveloperSandbox.ExitSandbox())
  end)
end)