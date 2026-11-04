local loader = require("helpers.load_addon")

local function load(guildLeader)
  local _, dibs = loader.load({ wow = { guildLeader = guildLeader ~= false }, withAce3 = true })
  return dibs
end

local function codes(rows)
  local result = {}
  for _, row in ipairs(rows or {}) do result[row.code or row] = true end
  return result
end

local function checkIds(report)
  local ids = {}
  for _, item in ipairs(report.checks or {}) do ids[item.id] = item end
  return ids
end

describe("Synchronization repair", function()
  it("keeps every recorded behind reason until each one is resolved", function()
    local dibs = load()
    dibs.Sync.MarkSyncBehind("POLICY_CHAIN_MISSING")
    dibs.Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
    local reasons = codes(dibs.Sync.GetSyncBehindReasons())
    assert_true(reasons.POLICY_CHAIN_MISSING)
    assert_true(reasons.CANONICAL_ROOT_CONFLICT)

    local recheck = dibs.Sync.RecheckSyncBehind()
    assert_true(codes(recheck.cleared).POLICY_CHAIN_MISSING)
    assert_true(codes(recheck.remaining).CANONICAL_ROOT_CONFLICT)
    assert_true(dibs.Sync.IsSyncBehind())
    assert_equal(true, dibs.Sync.GetStatus().reasons ~= nil)
  end)

  it("describes reasons with localized text", function()
    local dibs = load()
    assert_equal(dibs.L.SYNC_BEHIND_REASON_LEDGER_GAP, dibs.Sync.DescribeSyncBehindReason("LEDGER_GAP"))
    assert_true(dibs.Sync.DescribeSyncBehindReason("UNKNOWN_CODE"):find("UNKNOWN_CODE", 1, true) ~= nil)
  end)

  it("verifies, then reports what is still missing without changing ledger data", function()
    local dibs = load()
    dibs.Sync.MarkSyncBehind("MISSING_DETAIL")
    local verify = dibs.OfficerUI.FixSynchronization("VERIFY")
    assert_true(verify.ok)
    assert_false(dibs.Sync.IsSyncBehind())

    dibs.Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
    local auto = dibs.OfficerUI.FixSynchronization("AUTO")
    assert_false(auto.ok)
    assert_true(codes(auto.remaining).CANONICAL_ROOT_CONFLICT)
    assert_true(dibs.Sync.IsSyncBehind())
  end)

  it("lets a Guild Master force-clear the local behind flag", function()
    local officer = load(true)
    officer.Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
    local forced = officer.OfficerUI.FixSynchronization("FORCE", "SYNC_STATE_STUCK")
    assert_true(forced.ok)
    assert_false(officer.Sync.IsSyncBehind())
    assert_true(codes(forced.cleared).CANONICAL_ROOT_CONFLICT)
  end)

  it("denies force-clear for a non-administrator", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildRankIndices = { ["Tester-Realm"] = 3 } }, withAce3 = true })
    dibs.Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
    local ok, reason = dibs.Sync.ForceClearSyncBehind(nil, "SYNC_STATE_STUCK")
    assert_false(ok)
    assert_equal("OFFICER_REQUIRED", reason)
    assert_true(dibs.Sync.IsSyncBehind())
  end)
end)

describe("Reconciliation block explanation", function()
  it("explains why reconciliation is unavailable", function()
    local dibs = load()
    local short, long = dibs.OfficerUI.DescribeReconciliationBlock("SYNC_BEHIND")
    assert_equal(dibs.L.RECONCILE_BLOCKED_SYNC_BEHIND_SHORT, short)
    assert_equal(dibs.L.RECONCILE_BLOCKED_SYNC_BEHIND, long)
    local _, generic = dibs.OfficerUI.DescribeReconciliationBlock("SOMETHING_NEW")
    assert_true(generic:find("SOMETHING_NEW", 1, true) ~= nil)
  end)
end)

describe("Announcement switches", function()
  it("disables and restores the previous public and officer channels", function()
    local dibs = load()
    assert_not_nil(dibs.PreDibs.SetAnnouncementChannels("RAID", "OFFICER"))
    assert_true(dibs.PreDibs.IsAnnouncementEnabled("public"))

    assert_not_nil(dibs.PreDibs.SetAnnouncementEnabled("public", false))
    assert_false(dibs.PreDibs.IsAnnouncementEnabled("public"))
    assert_equal("NONE", dibs.PreDibs.GetAnnouncementSettings().publicChannel)
    assert_equal("OFFICER", dibs.PreDibs.GetAnnouncementSettings().officerChannel)

    assert_not_nil(dibs.PreDibs.SetAnnouncementEnabled("officer", false))
    assert_false(dibs.PreDibs.IsAnnouncementEnabled("officer"))

    assert_not_nil(dibs.PreDibs.SetAnnouncementEnabled("public", true))
    assert_equal("RAID", dibs.PreDibs.GetAnnouncementSettings().publicChannel)
    assert_not_nil(dibs.PreDibs.SetAnnouncementEnabled("officer", true))
    assert_equal("OFFICER", dibs.PreDibs.GetAnnouncementSettings().officerChannel)

    local _, reason = dibs.PreDibs.SetAnnouncementEnabled("bogus", false)
    assert_equal("INVALID_ANNOUNCEMENT_KIND", reason)
  end)

  it("sends no public announcement while public announcements are disabled", function()
    local dibs = load()
    dibs.PreDibs.SetAnnouncementChannels("GUILD", "NONE")
    dibs.PreDibs.SetAnnouncementEnabled("public", false)
    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21041, "Item 21041", dibs.GetCurrentSeasonId(), "test")
    assert_not_nil(request)
    assert_equal(0, #_G.__sentChatMessages)
  end)
end)

describe("Guild setup and raid readiness split", function()
  it("keeps guild configuration checks out of the raid readiness report", function()
    local dibs = load()
    local guild = checkIds(dibs.SetupAssistant.Evaluate({ scope = "guild" }))
    assert_not_nil(guild.season)
    assert_not_nil(guild.loot_types)
    assert_not_nil(guild.sync_state)
    assert_true(guild.raid_context == nil)
    assert_true(guild.rclootcouncil == nil)
    assert_true(guild.raid_members == nil)

    local raid = checkIds(dibs.SetupAssistant.Evaluate({ scope = "raid" }))
    assert_not_nil(raid.guild_setup)
    assert_not_nil(raid.raid_context)
    assert_not_nil(raid.raid_members)
    assert_not_nil(raid.sync_state)
    assert_true(raid.season == nil)
    assert_true(raid.loot_types == nil)

    local legacy = checkIds(dibs.SetupAssistant.Evaluate())
    assert_not_nil(legacy.season)
    assert_not_nil(legacy.rclootcouncil)
    assert_true(legacy.raid_members == nil)
  end)

  it("rolls guild blockers into one raid readiness item", function()
    local dibs = load()
    local guild = dibs.SetupAssistant.Evaluate({ scope = "guild" })
    local raid = checkIds(dibs.SetupAssistant.Evaluate({ scope = "raid" }))
    if guild.blockingCount > 0 then
      assert_equal("blocked", raid.guild_setup.state)
      assert_true(raid.guild_setup.required)
    else
      assert_true(raid.guild_setup.state ~= "blocked")
    end
  end)

  it("warns, without blocking, when raid members lack or need to update DIBS", function()
    local dibs = load()
    local previousInRaid = _G.IsInRaid
    _G.IsInRaid = function() return true end
    dibs.Sync.GetPeerStatuses = function()
      return {
        { playerName = "Tester-Realm", isLocal = true, addonDetected = true, rosterOnline = true, compatibility = "Compatible" },
        { playerName = "Alpha-Realm", addonDetected = true, rosterOnline = true, compatibility = "Compatible" },
        { playerName = "Bravo-Realm", addonDetected = false, rosterOnline = true, compatibility = "Unknown" },
        { playerName = "Charlie-Realm", addonDetected = true, rosterOnline = true, compatibility = "Update required" },
        { playerName = "Delta-Realm", addonDetected = false, rosterOnline = false, compatibility = "Unknown" },
      }
    end
    local report = dibs.SetupAssistant.Evaluate({ scope = "raid" })
    _G.IsInRaid = previousInRaid
    local members = checkIds(report).raid_members
    assert_equal("degraded", members.state)
    assert_false(members.required)
    assert_equal("RAID_ADDON_OUTDATED", members.reasonCode)
    assert_true(members.impact:find("Bravo-Realm", 1, true) ~= nil)
    assert_true(members.impact:find("Charlie-Realm", 1, true) ~= nil)
    assert_true(members.impact:find("Delta-Realm", 1, true) == nil)
    assert_true(members.impact:find("Alpha-Realm", 1, true) == nil)
  end)

  it("reports a behind client in both setup scopes and routes to synchronization", function()
    local dibs = load()
    dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    local guild = checkIds(dibs.SetupAssistant.Evaluate({ scope = "guild" }))
    assert_equal("degraded", guild.sync_state.state)
    assert_equal("SYNC_BEHIND", guild.sync_state.reasonCode)
    local raid = checkIds(dibs.SetupAssistant.Evaluate({ scope = "raid" }))
    assert_equal("degraded", raid.sync_state.state)
  end)

  it("renders the guild checks and raid readiness on separate routes", function()
    local dibs = load()
    local frame = dibs.OfficerUI.CreateWindow("guildSetup")
    assert_equal("guildSetup", frame.activeTab)
    local function texts()
      local values = {}
      for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
        values[#values + 1] = tostring(widget.text or "") .. "|" .. tostring(widget.title or "") .. "|" .. tostring(widget.label or "")
      end
      return table.concat(values, "\n")
    end
    local guildText = texts()
    assert_true(guildText:find("Guild Setup Checks", 1, true) ~= nil)
    assert_true(guildText:find("Run readiness check", 1, true) == nil)

    _G.__dibsAceWidgets = {}
    frame:ActivateRoute("setup")
    local raidText = texts()
    assert_true(raidText:find("Run readiness check", 1, true) ~= nil)
    assert_true(raidText:find("Raid members with DIBS", 1, true) ~= nil or raidText:find("Guild setup", 1, true) ~= nil)
  end)

  it("sends the Guided Setup readiness step to the guild checks", function()
    local dibs = load()
    local turnkey = dibs.Wizard.GetTurnkeyStatus()
    for _, result in ipairs(turnkey.verification or {}) do
      if result.id == "readiness" then assert_equal("guildSetup", result.route) end
    end
  end)
end)
