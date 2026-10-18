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

  describe("Contextual setup guidance", function()
    local checkRoutes = {
      season = "seasons", policy = "ranks", rank_rules = "ranks",
      authority = "installation", installation = "settings", local_state = "installation",
      rclootcouncil = "integration", dib_response_projection = "integration",
      channels = "announcements", sync_context = "announcements",
      local_services = "sync", guild_loot_rules = "lootTypes", loot_types = "lootTypes",
      guild_setup = "guildSetup", sync_state = "sync", raid_members = "sync",
    }

    local function latestWidget(predicate)
      for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
        local widget = _G.__dibsAceWidgets[index]
        if predicate(widget) then return widget end
      end
    end

    it("gives every setup check and wizard step specific English and French instructions", function()
      local ids = {
        "season", "policy", "rank_rules", "authority", "installation", "local_state",
        "rclootcouncil", "dib_response_projection", "raid_context", "channels", "sync_context",
        "local_services", "guild_loot_rules", "loot_types", "guild_setup", "sync_state", "raid_members",
        "guild", "administration", "seasons", "rankRules", "allocationReconciliation", "dibsRules",
        "preDibs", "ledger", "sync", "operationalPolicy", "readiness",
      }
      for _, locale in ipairs({ "enUS", "frFR" }) do
        local _, dibs = loader.load({ wow = { guildLeader = true, locale = locale }, withAce3 = true })
        for _, id in ipairs(ids) do
          local guidance = dibs.SetupAssistant.GetGuidance(id)
          assert_true(type(guidance) == "string" and #guidance > 30, id)
          assert_true(guidance ~= dibs.L.SETUP_HELP_UNKNOWN, id)
          assert_true(guidance ~= dibs.L.WIZARD_CORRECTION_ACTION, id)
          assert_nil(guidance:find("SETUP_HELP_", 1, true), id)
        end
        for id, route in pairs(checkRoutes) do
          local presentation = dibs.SetupAssistant.GetCheckPresentation(id)
          assert_equal(route, presentation.route, id)
          assert_not_nil(dibs.L[presentation.labelKey], id)
          assert_not_nil(dibs.L[presentation.actionKey], id)
        end
        assert_nil(dibs.SetupAssistant.GetCheckPresentation("raid_context").route)
        assert_equal("probe-specific instructions", dibs.SetupAssistant.GetGuidance("future_probe", nil, "probe-specific instructions"))
      end
    end)

    it("shows current issues on every correction page, including direct navigation, without mutations", function()
      local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
      local checks = {}
      for id in pairs(checkRoutes) do
        checks[#checks + 1] = { id = id, state = "blocked", required = true,
          reasonCode = "TEST_" .. id, impact = "A synthetic issue needs attention." }
      end
      dibs.SetupAssistant.Evaluate = function() return { checks = checks } end
      dibs.Wizard.GetTurnkeyStatus = function() return { verification = {} } end
      local frame = dibs.OfficerUI.CreateWindow("seasons")
      for _, route in pairs(checkRoutes) do
        if route ~= "guildSetup" then frame:ActivateRoute(route) end
      end
      local before = loader.snapshotProductionState(dibs)
      local visited = {}
      for _, route in pairs(checkRoutes) do
        if route ~= "guildSetup" and not visited[route] then
          visited[route] = true
          frame:ActivateRoute(route)
          assert_not_nil(frame.setupGuidanceIssues, route)
          assert_true(#frame.setupGuidanceIssues > 0, route)
          for _, issue in ipairs(frame.setupGuidanceIssues) do
            assert_equal(route, issue.route)
            assert_equal("BLOCKING", issue.severity)
            assert_true(#issue.nextAction > 30)
          end
          local section = latestWidget(function(widget) return widget.title == dibs.L.SETUP_HELP_TITLE end)
          assert_not_nil(section)
          if route == "integration" or route == "lootTypes" or route == "settings"
            or route == "ranks" or route == "preDibs" or route == "announcements" then
            assert_equal("ScrollFrame", section.parent.kind, route)
          end
        end
      end
      assert_true(loader.productionStateEquals(dibs, before))
      frame:ActivateRoute("overview")
      assert_nil(frame.setupGuidanceIssues)
    end)

    it("explains a Master Looter warning on hover and removes the issue after it is fixed", function()
      local _, dibs = loader.load({ wow = { guildLeader = true, inRaid = true }, withAce3 = true })
      local check = { id = "rclootcouncil", state = "degraded", required = false,
        reasonCode = "RC_MASTER_LOOTER_UNVERIFIABLE", impact = "The Master Looter could not be verified." }
      dibs.SetupAssistant.Evaluate = function() return { checks = { check } } end
      dibs.Wizard.GetTurnkeyStatus = function() return { verification = {} } end
      local frame = dibs.OfficerUI.CreateWindow("setup")
      local action = latestWidget(function(widget)
        return widget.kind == "Button" and widget.text == dibs.L.SETUP_ASSISTANT_ACTION_RC
      end)
      assert_not_nil(action._dibsTooltipAttachment)
      action.callbacks.OnClick(action, "OnClick")
      assert_equal("integration", frame.activeTab)
      assert_equal(1, #frame.setupGuidanceIssues)
      assert_equal("WARNING", frame.setupGuidanceIssues[1].severity)
      local badge = latestWidget(function(widget)
        return widget.dibsMidnightStatus == "warning"
          and tostring(widget.text):find(dibs.L.SETUP_ASSISTANT_CHECK_RC, 1, true) ~= nil
      end)
      assert_not_nil(badge)
      local tooltip, previousTooltip = { lines = {} }, _G.GameTooltip
      _G.GameTooltip = {
        SetOwner = function() end,
        SetText = function(_, title) tooltip.title = title end,
        AddLine = function(_, line) tooltip.lines[#tooltip.lines + 1] = line end,
        Show = function() tooltip.shown = true end,
        Hide = function() tooltip.shown = false end,
      }
      badge.frame:GetScript("OnEnter")(badge.frame)
      assert_true(tooltip.shown)
      assert_equal(dibs.L.SETUP_ASSISTANT_CHECK_RC, tooltip.title)
      assert_true(tooltip.lines[1]:find(check.impact, 1, true) ~= nil)
      assert_true(tooltip.lines[1]:find("RC_MASTER_LOOTER_UNVERIFIABLE", 1, true) ~= nil)
      assert_true(tooltip.lines[1]:find(frame.setupGuidanceIssues[1].nextAction, 1, true) ~= nil)
      badge.frame:GetScript("OnLeave")(badge.frame)
      assert_false(tooltip.shown)
      check.state = "ready"
      local refresh = latestWidget(function(widget)
        return widget.kind == "Button" and widget.text == dibs.L.SETUP_HELP_REFRESH
      end)
      refresh.callbacks.OnClick(refresh, "OnClick")
      assert_equal(0, #frame.setupGuidanceIssues)
      assert_nil(badge._dibsTooltipAttachment)
      _G.GameTooltip = previousTooltip
    end)

    it("places synchronization and allocation guidance inside the table header", function()
      local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
      dibs.SetupAssistant.Evaluate = function()
        return { checks = { { id = "sync_state", state = "degraded", reasonCode = "SYNC_BEHIND" } } }
      end
      dibs.Wizard.GetTurnkeyStatus = function()
        return { verification = {
          { id = "allocationReconciliation", severity = "WARNING", title = "Allocation reconciliation",
            route = "automaticDibs", explanation = "A member needs allocation.",
            nextAction = dibs.SetupAssistant.GetGuidance("allocationReconciliation") },
        } }
      end
      local frame = dibs.OfficerUI.CreateWindow("sync")
      local section = latestWidget(function(widget) return widget.title == dibs.L.SETUP_HELP_TITLE end)
      assert_equal(frame.syncTablePage.header, section.parent)
      frame:ActivateRoute("automaticDibs")
      section = latestWidget(function(widget) return widget.title == dibs.L.SETUP_HELP_TITLE end)
      assert_equal(frame.automaticDibsTablePage.header, section.parent)
      assert_equal("allocationReconciliation", frame.setupGuidanceIssues[1].id)
    end)

    it("enables hover on labels and restores pooled mouse and script state on release", function()
      local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
      local shell = dibs.AceGUI.CreateWindow("Help", 500, 400)
      local label = dibs.AceGUI.AddLabel(shell, shell.window, "Warning", true)
      local mouseEnabled, entered = false, 0
      label.frame.IsMouseEnabled = function() return mouseEnabled end
      label.frame.EnableMouse = function(_, value) mouseEnabled = value end
      local previousEnter = function() entered = entered + 1 end
      label.frame:SetScript("OnEnter", previousEnter)
      dibs.AceGUI.AddTooltip(label, "Warning", "Steps to correct the issue")
      assert_true(mouseEnabled)
      label.frame:GetScript("OnEnter")(label.frame)
      assert_equal(1, entered)
      dibs.AceGUI.AddTooltip(label, "Updated warning", "Updated steps")
      dibs.AceGUI.Clear(shell.window)
      assert_false(mouseEnabled)
      assert_equal(previousEnter, label.frame:GetScript("OnEnter"))
    end)
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
      { "Open Guild Ledgers", "installation" },
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

    local ledgerCountBeforeDryRun = #dibs.Ledger.GetAllTransactions()
    clickButton("Run local dry-run")
    local dryRun = dibs.SetupAssistant.GetLastDryRun()
    assert_not_nil(dryRun)
    assert_equal("finalized", dryRun.input.status)
    assert_true(dryRun.simulation)
    assert_false(dryRun.mutated)
    assert_equal(ledgerCountBeforeDryRun, #dibs.Ledger.GetAllTransactions())
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
    local frame = dibs.OfficerUI.CreateWindow("guildSetup")
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
    assert_equal("guildSetup", frame.activeTab)
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
