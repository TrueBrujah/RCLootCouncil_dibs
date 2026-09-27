local loader = require("helpers.load_addon")

describe("First installation assistant UI", function()
  it("mounts the setup route as one Officer-owned page", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow("setup")
    assert_equal("setup", frame.selectedRoute)
    assert_equal("setup", frame.mountedPage)
    assert_equal(1, frame.primaryPageCount)
    assert_true(frame.contentHost._dibsCurrentPageRoot ~= nil)
  end)

  it("routes channel setup to Guild Rules announcements", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow("setup")
    frame:ActivateRoute("announcements")
    assert_equal("announcements", frame.activeTab)
    assert_equal("announcements", frame.selectedRoute)
    assert_true(frame.activeTab ~= "overview")
  end)

  it("localizes readiness sections, actions, and technical disclosure in French", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, locale = "frFR" }, withAce3 = true })
    assert_equal("DIBS essentiel", dibs.L.SETUP_ASSISTANT_SECTION_CORE)
    assert_equal("Ouvrir les regles de butin", dibs.L.SETUP_ASSISTANT_ACTION_LOOT_RULES)
    assert_equal("A verifier", dibs.L.SETUP_ASSISTANT_NEEDS_ATTENTION_SECTION)
    assert_equal("Outils", dibs.L.SETUP_ASSISTANT_TOOLS)
    assert_equal("Inconnu", dibs.L.SETUP_ASSISTANT_STATE_UNKNOWN)
    assert_equal("Details techniques", dibs.L.SETUP_ASSISTANT_TECHNICAL_TITLE)
  end)

  it("keeps dashboard presentation strings available in both locales", function()
    local keys = {
      "SETUP_ASSISTANT_SUMMARY", "SETUP_ASSISTANT_ATTENTION_COUNT", "SETUP_ASSISTANT_READY_COUNT",
      "SETUP_ASSISTANT_GROUP_READY_COUNT", "SETUP_ASSISTANT_OUTSIDE_RAID",
      "SETUP_ASSISTANT_NEEDS_ATTENTION_SECTION", "SETUP_ASSISTANT_READY_SECTION",
      "SETUP_ASSISTANT_TOOLS", "SETUP_ASSISTANT_NO_READY_CHECKS", "SETUP_ASSISTANT_STATE_UNKNOWN",
      "SETUP_ASSISTANT_LOOT_LOCAL_LABEL", "SETUP_ASSISTANT_LOOT_SCOPE_GENERIC",
      "SETUP_ASSISTANT_LOOT_SCOPE_OFFICER", "SETUP_ASSISTANT_LOOT_SCOPE_GM",
      "SETUP_ASSISTANT_LOOT_AUTHORITY_STATUS",
      "SETUP_ASSISTANT_LOOT_UNAVAILABLE", "SETUP_ASSISTANT_LOOT_INVALID",
      "SETUP_ASSISTANT_LOOT_INVALID_ACTION",
    }
    local _, english = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    for _, key in ipairs(keys) do assert_true(type(english.L[key]) == "string" and english.L[key] ~= "") end
    local _, french = loader.load({ wow = { guildLeader = true, locale = "frFR" }, withAce3 = true })
    for _, key in ipairs(keys) do assert_true(type(french.L[key]) == "string" and french.L[key] ~= "") end
    assert_equal("At a glance", english.L.SETUP_ASSISTANT_SUMMARY)
    assert_equal("En bref", french.L.SETUP_ASSISTANT_SUMMARY)
  end)

  it("presents readiness checks clearly, discloses technical detail, and keeps configuration on its own routes", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local report = {
      status = "NEEDS_ATTENTION",
      blockingCount = 7,
      checks = {
        { id = "season", state = "blocked", required = true, reasonCode = "SEASON_UNAVAILABLE", source = "seasons", impact = "An active season is required.", remediation = "Create a season." },
        { id = "policy", state = "degraded", required = false, reasonCode = "POLICY_REVIEW", source = "policy", impact = "A rank policy needs review.", remediation = "Review rank rules." },
        { id = "rank_rules", state = "degraded", required = true, reasonCode = "RANK_RULES_REVIEW", source = "rank-rules", impact = "Rank rules need review.", remediation = "Review rank rules." },
        { id = "authority", state = "blocked", required = true, reasonCode = "AUTHORITY_UNAVAILABLE", source = "permissions", impact = "Guild authority could not be verified.", remediation = "Review guild configuration." },
        { id = "installation", state = "blocked", required = true, reasonCode = "INSTALLATION_INCOMPLETE", source = "installation", impact = "Guild installation needs attention.", remediation = "Review settings." },
        { id = "local_state", state = "blocked", required = true, reasonCode = "LOCAL_STATE_INVALID", source = "local-state", impact = "Local DIBS state is incomplete.", remediation = "Review guild configuration." },
        { id = "rclootcouncil", state = "blocked", required = true, reasonCode = "RC_UNAVAILABLE", source = "readiness", impact = "RCLootCouncil integration is unavailable.", remediation = "Review the integration." },
        { id = "dib_response_projection", state = "degraded", required = true, reasonCode = "DIB_RESPONSE_MISSING", source = "readiness", impact = "DIB response support needs review.", remediation = "Review the integration." },
        { id = "raid_context", state = "unavailable", required = false, reasonCode = "NO_RAID_CONTEXT", source = "readiness", impact = "No raid is active.", remediation = "Enter a raid and refresh." },
        { id = "channels", state = "unavailable", required = false, reasonCode = "CHANNEL_UNAVAILABLE", source = "readiness", impact = "The raid channel is unavailable.", remediation = "Join the raid channel." },
        { id = "sync_context", state = "degraded", required = false, reasonCode = "SYNC_REVIEW", source = "sync", impact = "Synchronization needs review.", remediation = "Review announcements." },
        { id = "local_services", state = "degraded", required = false, reasonCode = "SYNC_UNAVAILABLE", source = "sync", impact = "Guild synchronization is unavailable.", remediation = "Review synchronization." },
        { id = "loot_types", state = "unavailable", required = false, reasonCode = "LOOT_TYPES_UNAVAILABLE", source = "options", impact = "Loot controls are unavailable.", remediation = "Open loot rules." },
        { id = "optional_probe", state = "ready", required = true, reasonCode = nil, source = "test", impact = "Optional check is complete.", remediation = "No action required." },
        { id = "skipped_probe", state = "skipped", required = false, reasonCode = nil, source = "test", impact = "Skipped check.", remediation = "No action required." },
      },
    }
    dibs.SetupAssistant.Evaluate = function() return report end
    local originalChecks = report.checks
    local frame = dibs.OfficerUI.CreateWindow("setup")

    local function latestButton(text)
      for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
        local widget = _G.__dibsAceWidgets[index]
        if widget.kind == "Button" and widget.text == text then return widget end
      end
    end
    local function clickButton(text)
      local widget = latestButton(text)
      assert_not_nil(widget, "Button not found: " .. text)
      widget.callbacks.OnClick(widget, "OnClick")
    end
    local function renderedText()
      local values = {}
      for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
        values[#values + 1] = tostring(widget.text or "")
        values[#values + 1] = tostring(widget.label or "")
        values[#values + 1] = tostring(widget.title or "")
      end
      return table.concat(values, "\n")
    end
    local function hasStandaloneText(value)
      for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
        if widget.text == value or widget.label == value or widget.title == value then return true end
      end
      return false
    end

    local summaryText = renderedText()
    assert_true(summaryText:find("At a glance", 1, true) ~= nil)
    assert_true(summaryText:find("RCLootCouncil integration", 1, true) ~= nil)
    assert_true(summaryText:find("13 items need attention", 1, true) ~= nil)
    assert_true(summaryText:find("1 / 14 checks ready", 1, true) ~= nil)
    assert_true(summaryText:find("Outside a raid, some live checks are unavailable.", 1, true) ~= nil)
    assert_true(summaryText:find("[X] Blocked", 1, true) ~= nil)
    assert_true(summaryText:find("[!] Needs attention", 1, true) ~= nil)
    assert_true(summaryText:find("[ ] Unavailable", 1, true) ~= nil)
    assert_true(summaryText:find("Guild authority", 1, true) ~= nil)
    assert_true(summaryText:find("Active season", 1, true) < summaryText:find("Rank allocation policy", 1, true))
    assert_true(summaryText:find("Rank allocation policy", 1, true) < summaryText:find("Raid context", 1, true))
    assert_true(summaryText:find("Raid context", 1, true) < summaryText:find("Loot rules", 1, true))
    assert_true(summaryText:find("Core DIBS", 1, true) ~= nil)
    assert_true(summaryText:find("1 / 7 checks ready", 1, true) ~= nil)
    assert_true(summaryText:find("Tools", 1, true) ~= nil)
    assert_true(summaryText:find("Refresh readiness", 1, true) ~= nil)
    assert_true(summaryText:find("Run local dry-run", 1, true) ~= nil)
    assert_true(summaryText:find("Technical details", 1, true) ~= nil)
    assert_true(summaryText:find("Optional check is complete.", 1, true) == nil)
    assert_true(summaryText:find("Additional check", 1, true) == nil)
    for _, item in ipairs(report.checks) do
      assert_false(hasStandaloneText(item.id), "Raw check ID shown: " .. item.id)
    end
    assert_true(summaryText:find("No action required.", 1, true) == nil)
    assert_true(summaryText:find("New season name", 1, true) == nil)
    assert_true(summaryText:find("Create season", 1, true) == nil)
    assert_true(summaryText:find("Installation mode", 1, true) == nil)
    assert_true(summaryText:find("Apply mode", 1, true) == nil)

    local function widgetIndex(value)
      for index, widget in ipairs(_G.__dibsAceWidgets or {}) do
        if widget.text == value or widget.label == value or widget.title == value then return index end
      end
    end
    assert_true(widgetIndex("Needs attention") < widgetIndex("Ready"))

    clickButton("Show all checks")
    local expandedText = renderedText()
    assert_true(expandedText:find("Additional check", 1, true) ~= nil)
    assert_true(expandedText:find("Optional check is complete.", 1, true) == nil)
    clickButton("Hide completed checks")
    clickButton("Technical details")
    local technicalText = renderedText()
    assert_true(technicalText:find("season | State: blocked | Required: Yes | Reason: SEASON_UNAVAILABLE | Source: seasons", 1, true) ~= nil)
    assert_true(technicalText:find("Impact: An active season is required.", 1, true) ~= nil)
    assert_true(technicalText:find("Remediation: Create a season.", 1, true) ~= nil)

    local routes = {
      { "Open Seasons", "seasons" },
      { "Open Rank Rules", "ranks" },
      { "Open Guild Configuration", "installation" },
      { "Open Settings", "settings" },
      { "Open RCLootCouncil", "integration" },
      { "Open Announcements", "announcements" },
      { "Open Sync", "sync" },
      { "Open Loot Rules", "lootTypes" },
    }
    for _, route in ipairs(routes) do
      local action = latestButton(route[1])
      assert_not_nil(action, "Button not found: " .. route[1])
      assert_equal(0.28, action.relWidth)
      assert_equal("Flow", action.parent.layout)
      action.callbacks.OnClick(action, "OnClick")
      assert_equal(route[2], frame.activeTab)
      frame:ActivateRoute("setup")
    end
    clickButton("Refresh readiness")
    assert_equal("setup", frame.activeTab)
    assert_equal("NEEDS_ATTENTION", report.status)
    assert_equal(7, report.blockingCount)
    assert_true(report.checks == originalChecks)
    assert_equal(15, #report.checks)
    assert_equal("season", report.checks[1].id)
    assert_equal("blocked", report.checks[1].state)
  end)

  it("uses the projected overall status and presents unknown states explicitly", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local report = {
      status = "READY_FOR_RAID",
      blockingCount = 99,
      checks = { { id = "season", state = "ready", required = true } },
    }
    dibs.SetupAssistant.Evaluate = function() return report end
    local frame = dibs.OfficerUI.CreateWindow("setup")
    local function hasText(value)
      for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
        if widget.text == value or widget.label == value or widget.title == value then return true end
      end
      return false
    end
    assert_true(hasText("[OK] Ready"))
    assert_true(hasText("0 items need attention"))
    assert_true(hasText("1 / 1 checks ready"))

    report.status = "FUTURE_STATUS"
    for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
      local widget = _G.__dibsAceWidgets[index]
      if widget.kind == "Button" and widget.text == "Refresh readiness" then
        widget.callbacks.OnClick(widget, "OnClick")
        break
      end
    end
    assert_true(hasText("[?] Unknown"))
    assert_equal("ready", report.checks[1].state)
    assert_equal(99, report.blockingCount)
    assert_equal("FUTURE_STATUS", report.status)
    assert_equal("setup", frame.activeTab)
  end)

  it("shows the unadopted guild status separately from available Loot Rules controls", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.OperationalPolicy.IsAdopted = function() return false end
    local frame = dibs.OfficerUI.CreateWindow("setup")
    local values = {}
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      values[#values + 1] = tostring(widget.text or "")
      values[#values + 1] = tostring(widget.label or "")
      values[#values + 1] = tostring(widget.title or "")
    end
    local text = table.concat(values, "\n")
    assert_true(text:find("Loot rules", 1, true) ~= nil)
    assert_true(text:find("[!] Needs attention", 1, true) ~= nil)
    assert_true(text:find("Controls available", 1, true) ~= nil)
    assert_true(text:find("Guild Loot Rules: GUILD_LOOT_RULES_NOT_CONFIGURED", 1, true) ~= nil)
    assert_true(text:find("explicitly adopt", 1, true) ~= nil)
    assert_equal("setup", frame.activeTab)
  end)

  it("replaces the generic policy banner with role-specific local scope on Loot Rules", function()
    for _, role in ipairs({ "gm", "officer" }) do
      local _, dibs = loader.load({ wow = { guildLeader = role == "gm" }, withAce3 = true })
      dibs.Permissions.GetGuildRole = function() return role end
      dibs.Sync.GetSynchronizationStatus = function() return { operationalPolicyAdopted = false } end
      dibs.OfficerUI.CreateWindow("lootTypes")
      local values = {}
      for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
        values[#values + 1] = tostring(widget.text or "")
        values[#values + 1] = tostring(widget.label or "")
        values[#values + 1] = tostring(widget.title or "")
      end
      local text = table.concat(values, "\n")
      assert_true(text:find("Guild Loot Rules have not been adopted.", 1, true) ~= nil)
      assert_true(text:find("Guild-wide rules are not active. Changes remain local until the Guild Master adopts the policy.", 1, true) == nil)
      if role == "gm" then
        assert_true(text:find("Review the complete local draft.", 1, true) ~= nil)
      else
        assert_true(text:find("Only the Guild Master can adopt guild Loot Rules.", 1, true) ~= nil)
      end
    end
  end)

  it("retains the generic policy banner on other pages", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.Sync.GetSynchronizationStatus = function() return { operationalPolicyAdopted = false } end
    dibs.OfficerUI.CreateWindow("preDibs")
    local text = {}
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      text[#text + 1] = tostring(widget.text or "")
      text[#text + 1] = tostring(widget.label or "")
      text[#text + 1] = tostring(widget.title or "")
    end
    assert_true(table.concat(text, "\n"):find(
      "Guild-wide rules are not active. Changes remain local until the Guild Master adopts the policy.", 1, true) ~= nil)
  end)

  it("re-probes the Loot Rules source when Refresh readiness is clicked", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local source = dibs.RCOptions.GetLootTypeOptions()
    local probeCount = 0
    dibs.RCOptions.GetLootTypeOptions = function()
      probeCount = probeCount + 1
      return source
    end
    local frame = dibs.OfficerUI.CreateWindow("setup")
    local beforeRefresh = probeCount
    local refresh
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == "Refresh readiness" then refresh = widget end
    end
    assert_not_nil(refresh)
    refresh.callbacks.OnClick(refresh, "OnClick")
    assert_true(probeCount > beforeRefresh)
    assert_equal("setup", frame.activeTab)
  end)
end)
