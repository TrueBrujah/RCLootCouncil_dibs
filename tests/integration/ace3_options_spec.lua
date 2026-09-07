local loader = require("helpers.load_addon")

describe("Ace3 options integration", function()
  it("registers Dibs-owned settings through AceConfig without changing SavedVariables", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    local options = dibs.Ace3.libs.config.tables.RCLootCouncil_dibs
    assert_not_nil(options)
    assert_not_nil(options.args.dibsSettings.args.preDibs)
    assert_not_nil(options.args.dibsSettings.args.preDibs.args.mode)
    assert_not_nil(options.args.dibsSettings.args.settings.args.raidEntryDibPromptsEnabled)
    assert_not_nil(options.args.dibsSettings.args.settings.args.raidReminderMessage)
    assert_not_nil(dibs.GetDB().settings)
    assert_equal(nil, dibs.GetDB().profiles)
  end)

  it("supports the official callable-table LibStub implementation", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({
      wow = { guildLeader = true },
      rclootcouncil = rc,
      withAce3 = true,
      libStubAsCallableTable = true,
    })

    assert_true(dibs.AceGUI.IsAvailable())
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    assert_not_nil(dibs.Ace3.libs.comm)
  end)

  it("leaves the legacy category list untouched on Retail Settings", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local categories = {
      { parent = "RCLootCouncil", name = "Master Looter" },
      { parent = "RCLootCouncil", name = "Dibs" },
    }
    _G.INTERFACEOPTIONS_ADDONCATEGORIES = categories
    -- Registration ran once during initialization; repeat it after installing
    -- the sentinel list so the guard is exercised directly.
    dibs.RCOptions.registered = nil
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    assert_equal("Master Looter", categories[1].name)
    assert_equal("Dibs", categories[2].name)
  end)

  it("does not leave Player or Officer dialog frames over Blizzard Settings", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.PlayerUI.CreateWindow() ~= nil)
    assert_true(dibs.OfficerUI.CreateWindow() ~= nil)
    assert_false(_G.DibsPlayerFrame:IsShown())
    assert_false(_G.DibsOfficerFrame:IsShown())
  end)

  it("adds the packaged Dibs logo to AceGUI windows", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local shell = dibs.AceGUI.CreateWindow("Logo test", 500, 400, { "CENTER", 0, 0 })
    assert_not_nil(shell)
    assert_not_nil(shell.frame.dibsLogoTexture)
    assert_equal(dibs.ICON_TEXTURE, shell.frame.dibsLogoTexture._texture)
    assert_false(shell.frame:IsShown())
  end)
end)

describe("Unified Dibs options", function()
  local function setup(wow)
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = wow or { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    return dibs, dibs.Ace3.libs.config.tables.RCLootCouncil_dibs.args.dibsSettings.args
  end

  it("keeps Raid Dibs visible and sends to the resolved community stream", function()
    local dibs, groups = setup({ guildLeader = true, raidDibsChannel = true })
    local channel = groups.preDibs.args.preDibAnnouncementChannel
    dibs.PreDibs.SetAnnouncementChannels("RAID_DIBS", "NONE")
    assert_equal("Raid Dibs", channel.values[channel.get()])
    local before = #dibs.PreDibs.GetHistory()
    groups.announcements.args.testpublicChannel.func()
    assert_equal(2044801, _G.__sentChatMessages[1].clubId)
    assert_equal(3, _G.__sentChatMessages[1].streamId)
    assert_equal(before, #dibs.PreDibs.GetHistory())
    assert_true(groups.announcements.args.raidDibsStatus.name():find("stream 3", 1, true) ~= nil)
  end)

  it("retains the channel selection when the community is unavailable", function()
    local dibs, groups = setup()
    local channel = groups.preDibs.args.preDibAnnouncementChannel
    channel.set(nil, "RAID_DIBS")
    assert_equal("RAID_DIBS", dibs.PreDibs.GetAnnouncementSettings().publicChannel)
    assert_equal("Raid Dibs", channel.values[channel.get()])
    groups.announcements.args.testpublicChannel.func()
    assert_equal(0, #_G.__sentChatMessages)
    assert_true(dibs.RCOptions.state.status:find("not joined", 1, true) ~= nil)
  end)

  it("reads changes from either UI through shared settings and shows all views", function()
    local dibs, groups = setup()
    groups.announcements.args.preDibTemplate.set(nil, "%player - %item")
    assert_equal("%player - %item", dibs.PreDibs.GetAnnouncementTemplates().preDib)
    dibs.PreDibs.SetAnnouncementTemplates("Changed in officer window", "Reminder changed")
    assert_equal("Changed in officer window", groups.announcements.args.preDibTemplate.get())
    assert_equal("Reminder changed", groups.settings.args.raidReminderMessage.get())
    groups.developer.args.enabled.set(nil, true)
    assert_true(dibs.DeveloperMode.IsEnabled())
    assert_not_nil(groups.player.args.summary.name())
    assert_not_nil(groups.player.args.history.name())
    assert_not_nil(groups.player.args.openAcquisitions)
    assert_not_nil(groups.officer.args.statistics.name())
    assert_not_nil(groups.announcements.args.preview.name())
  end)

  it("preserves the actual raid reminder rejection reason", function()
    local dibs, groups = setup()
    dibs.Permissions.CanSendReminder = function() return false, "NOT_IN_RAID" end
    groups.settings.args.sendRaidReminder.func()
    assert_equal("NOT_IN_RAID", dibs.RCOptions.state.status)
    assert_equal(0, #_G.__sentChatMessages)
  end)

  it("uses the Retail category ID and defers opening in combat", function()
    local dibs = setup()
    local opened
    local previousSettings = _G.Settings
    local previousCombat = _G.InCombatLockdown
    _G.Settings = { OpenToCategory = function(id) opened = id end }
    dibs.RCOptions.categoryId = 4242
    _G.InCombatLockdown = function() return true end
    assert_equal(false, dibs.RCOptions.Open())
    assert_equal(nil, opened)
    assert_true(dibs.RCOptions.pendingOpen)
    _G.InCombatLockdown = function() return false end
    assert_true(dibs.RCOptions.Open())
    assert_equal(4242, opened)
    _G.Settings, _G.InCombatLockdown = previousSettings, previousCombat
  end)

  it("routes public requests through the player action and cancellation ownership", function()
    local dibs, groups = setup()
    local input
    dibs.PlayerUI.SubmitPreDib = function(value) input = value; return nil, "INVALID_ITEM" end
    groups.player.args.item.set(nil, "invalid")
    groups.player.args.submit.func()
    assert_equal("invalid", input)
    assert_equal("INVALID_ITEM", dibs.RCOptions.state.status)
    local owner
    dibs.PreDibs.CancelForPlayer = function(id, player) owner = player; return nil, "NOT_REQUEST_OWNER" end
    groups.player.args.request.set(nil, "someone-elses-request")
    groups.player.args.cancel.func()
    assert_equal(dibs.GetPlayerName(), owner)
    assert_equal("NOT_REQUEST_OWNER", dibs.RCOptions.state.status)
  end)
end)


describe("Dibs options compatibility", function()
  it("opens the shared options without RCLootCouncil", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local opened
    dibs.Ace3.libs.dialog.Open = function(_, name) opened = name end
    dibs.HandleSlashCommand("options")
    assert_equal("RCLootCouncil_dibs", opened)
    assert_not_nil(dibs.Ace3.libs.config.tables[opened].args.dibsSettings.args.officer)
  end)

  it("uses the RC type policy setter without changing the ledger", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local policy = dibs.Ace3.libs.config.tables.RCLootCouncil_dibs.args.dibsSettings.args.integration.args.types
    local count = #dibs.Ledger.GetTransactions(dibs.GetCurrentSeasonId())
    local revision = dibs.RCLootCouncil.GetTypePolicyRevision()
    policy.set(nil, "MOUNTS", false)
    assert_equal(false, dibs.RCLootCouncil.IsDibEnabledForType("MOUNTS"))
    assert_equal(false, policy.get(nil, "MOUNTS"))
    assert_true(dibs.RCLootCouncil.GetTypePolicyRevision() > revision)
    assert_equal(count, #dibs.Ledger.GetTransactions(dibs.GetCurrentSeasonId()))
  end)
end)


describe("Officer loot type controls", function()
  it("shares dynamic types, changes and presets with RC options", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCLootCouncil.SetDibEnabledForType("INVTYPE_FINGER", false)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("lootTypes")
    local policy = dibs.RCOptions.GetLootTypeOptions().types
    assert_equal(false, frame.lootTypeControls.INVTYPE_FINGER.value)
    frame.lootTypeControls.INVTYPE_FINGER.callbacks.OnValueChanged(nil, nil, true)
    assert_equal(true, policy.get(nil, "INVTYPE_FINGER"))
    policy.set(nil, "MOUNTS", false)
    frame:Refresh()
    assert_equal(false, frame.lootTypeControls.MOUNTS.value)
    frame.enableLootTypes.callbacks.OnClick()
    assert_equal(true, policy.get(nil, "MOUNTS"))
    frame.defaultLootTypes.callbacks.OnClick()
    assert_equal(false, policy.get(nil, "MOUNTS"))
    assert_equal(false, policy.get(nil, "INVTYPE_FINGER"))
    assert_equal(true, policy.get(nil, "default"))
  end)
end)

describe("Player and officer option visibility", function()
  it("hides officer controls for a player", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {}, enabled = false })
    local _, dibs = loader.load({ wow = { guildLeader = false }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    dibs.Permissions.IsOfficer = function() return false end
    local groups = dibs.Ace3.libs.config.tables.RCLootCouncil_dibs.args.dibsSettings.args
    assert_true(groups.officer.hidden())
    assert_true(groups.settings.hidden())
    assert_true(groups.debug.hidden())
    assert_true(groups.player.hidden == nil or groups.player.hidden() == false)
    assert_nil(groups.overview.args.officer)
    assert_not_nil(groups.officer.args.openWindow)
    assert_nil(groups.player.args.preDibs)
  end)

  it("shows officer controls to a guild officer", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    dibs.RCOptions.EnsureRegistered(1)
    local groups = dibs.Ace3.libs.config.tables.RCLootCouncil_dibs.args.dibsSettings.args
    assert_equal(false, groups.officer.hidden())
    assert_nil(groups.overview.args.officer)
    assert_not_nil(groups.officer.args.preDibs)
    assert_true(groups.officer.args.openWindow.name():find("Open officer window", 1, true) ~= nil)
  end)
end)
