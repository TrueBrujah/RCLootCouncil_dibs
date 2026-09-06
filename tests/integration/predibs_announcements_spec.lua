local loader = require("helpers.load_addon")

describe("Pre-Dib announcements", function()
  it("sends one announcement when public and officer channels match", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.PreDibs.SetAnnouncementChannels("GUILD", "GUILD")

    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21041, "Item 21041", dibs.GetCurrentSeasonId(), "test")

    assert_not_nil(request)
    assert_equal(1, #_G.__sentChatMessages)
    assert_equal("GUILD", _G.__sentChatMessages[1].channel)
  end)

  it("sends announcements to the joined Raid Dibs channel", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, raidDibsChannel = true } })
    dibs.PreDibs.SetAnnouncementChannels("RAID_DIBS", "NONE")

    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21043, "Item 21043", dibs.GetCurrentSeasonId(), "test")

    assert_not_nil(request)
    assert_equal(1, #_G.__sentChatMessages)
    assert_equal("CLUB", _G.__sentChatMessages[1].channel)
    assert_equal(2044801, _G.__sentChatMessages[1].clubId)
    assert_equal(3, _G.__sentChatMessages[1].streamId)
  end)

  it("sends a test announcement without creating a request", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local before = #dibs.PreDibs.GetHistory()

    local ok = dibs.PreDibs.SendTestAnnouncement("GUILD", "Public")

    assert_true(ok)
    assert_equal(1, #_G.__sentChatMessages)
    assert_equal("GUILD", _G.__sentChatMessages[1].channel)
    assert_equal(before, #dibs.PreDibs.GetHistory())
  end)

  it("does not announce Developer Mode requests", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.CreateTest("Tester-Realm", 21042, "Item 21042", dibs.GetCurrentSeasonId(), "DEV", { isTest = true })

    assert_not_nil(request)
    assert_equal(0, #_G.__sentChatMessages)
  end)

  it("sends authorized in-raid reminders without creating a request", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, inRaid = true, raidLeader = true } })
    local before = #dibs.PreDibs.GetHistory()
    local ok = dibs.RaidRelay.SendReminder()
    assert_true(ok)
    assert_equal("RAID", _G.__sentChatMessages[1].channel)
    assert_equal(before, #dibs.PreDibs.GetHistory())
  end)
end)
