local loader = require("helpers.load_addon")

local roster = { "Tester-Realm", "Officer-Realm", "Member-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, guildLeader, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = guildLeader, guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function stepById(status, id)
  for _, step in ipairs(status.steps) do
    if step.id == id then return step end
  end
end

local function publishRule(dibs, seasonId, rankIndex, allocation, enabled)
  local result = dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = seasonId, rankIndex = rankIndex, rankName = "Rank " .. rankIndex, allocation = allocation,
    enabled = enabled,
  })
  assert_true(result.ok, tostring(result.diagnostic))
end

local function configuredGuild()
  local dibs = load("Tester-Realm", true)
  assert_true(dibs.Installation.Initialize(nil).ok)
  assert_true(dibs.Wizard.AdoptOperationalPolicy(nil))
  local season = dibs.Seasons.GetCurrent()
  for _, rankIndex in ipairs({ 0, 1, 3 }) do
    publishRule(dibs, season.id, rankIndex, rankIndex == 0 and 1 or 0)
  end
  return dibs, season
end

local function rankByIndex(rows, rankIndex)
  for _, row in ipairs(rows) do
    if row.rankIndex == rankIndex then return row end
  end
end

describe("Dibs.Wizard status derivation", function()
  it("adds an explicit GM policy adoption step and preserves the local policy inputs", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Installation.Initialize(nil).ok)
    local season = dibs.Seasons.GetCurrent()
    local settings = dibs.GetDB().settings
    settings.allowPublicPreDibs = false
    settings.preDibAnnouncementChannel = "RAID"
    settings.preDibOfficerAnnouncementChannel = "OFFICER"
    dibs.GetDB().preDibs.modePolicies[season.id] = { seasonId = season.id, mode = "ENCOUNTER" }

    local step = stepById(dibs.Wizard.GetStatus(), "operationalPolicy")
    assert_equal("ACTION_REQUIRED", step.status)
    assert_equal(false, step.detail.allowPublicPreDibs)
    assert_equal("ENCOUNTER", step.detail.preDibModes[tostring(season.id)])
    assert_equal("RAID", step.detail.announcementChannels.publicChannel)
    assert_true(dibs.Wizard.AdoptOperationalPolicy(nil))

    local adopted = dibs.OperationalPolicy.GetValues()
    assert_equal(false, adopted.allowPublicPreDibs)
    assert_equal("ENCOUNTER", adopted.preDibModes[tostring(season.id)])
    assert_equal("RAID", adopted.announcementChannels.publicChannel)
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "operationalPolicy").status)
  end)

  it("reports NEW_INSTALLATION/FIRST_TIME_SETUP before any configuration exists", function()
    local dibs = load("Tester-Realm", true)
    local status = dibs.Wizard.GetStatus()
    assert_equal("NEW_INSTALLATION", status.overallState)
    assert_equal("FIRST_TIME_SETUP", status.mode)
    assert_equal("ACTION_REQUIRED", stepById(status, "installation").status)
  end)

  it("does not claim raid readiness when a configured guild's check is unavailable", function()
    local dibs = load("Tester-Realm", true)
    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    local season = dibs.Seasons.GetCurrent()
    assert_not_nil(season)
    for rankIndex = 0, 3 do
      publishRule(dibs, season.id, rankIndex, rankIndex == 0 and 1 or 0)
    end

    local status = dibs.Wizard.GetStatus()
    assert_equal("installation", status.steps[1].id)
    assert_equal("READY", stepById(status, "installation").status)
    assert_equal("READY", stepById(status, "ledger").status)
    assert_equal("READY", stepById(status, "seasons").status)
    assert_equal("READY", stepById(status, "rankRules").status)
    assert_equal("BLOCKED", status.overallState)
    assert_equal("WARNING", stepById(status, "readiness").status)
  end)

  it("flags a missing rank rule even when raid readiness is unavailable", function()
    -- Dibs.Initialize()'s automatic default rules cover ranks 0-5; a rank
    -- beyond that range is genuinely unconfigured, not merely pending
    -- reconciliation (which is a separate, expected, ongoing officer task).
    local unusualRanks = { [1] = 0, [2] = 1, [3] = 7 }
    local _, seeded = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true, guildMembers = roster, guildRankIndices = unusualRanks,
    } })
    assert_true(seeded.Installation.Initialize(nil).ok)
    local status = seeded.Wizard.GetStatus()
    assert_equal("BLOCKED", status.overallState)
    assert_equal("ACTION_REQUIRED", stepById(status, "rankRules").status)
  end)

  it("reuses Dibs.Installation.GetStatus for the ledger step without a second detector", function()
    local dibs = load("Tester-Realm", true)
    local season = dibs.Seasons.Create("Legacy Season")
    assert_not_nil(dibs.Ledger.Grant("Member-Realm", 1, "legacy grant", "test", season.id))
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "test" }))
    local status = dibs.Wizard.GetStatus()
    assert_equal("WARNING", stepById(status, "ledger").status)
    assert_equal("MIGRATION_REQUIRED", status.overallState)
  end)

  it("never uses CharacterEligibility for the Rank Rules step", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Installation.Initialize(nil).ok)
    local calls = 0
    local original = dibs.CharacterEligibility
    dibs.CharacterEligibility = setmetatable({}, { __index = function(_, key)
      calls = calls + 1
      return original[key]
    end })
    dibs.Wizard.GetStatus()
    dibs.CharacterEligibility = original
    assert_equal(0, calls)
  end)

  it("persists the current step index in local per-character UI state, not guild data", function()
    local dibs = load("Tester-Realm", true)
    assert_equal(1, dibs.Wizard.GetCurrentStepIndex())
    assert_equal(4, dibs.Wizard.SetCurrentStepIndex(4))
    assert_equal(4, dibs.Wizard.GetCurrentStepIndex())
    assert_equal(4, _G.RCLootCouncil_dibsLocalDB.settings.wizardStepIndex)
    local guildDb = _G.RCLootCouncil_dibsDB.guilds and _G.RCLootCouncil_dibsDB.guilds["realm:testguild"]
    assert_true(guildDb == nil or guildDb.settings == nil or guildDb.settings.wizardStepIndex == nil)
  end)

  it("clamps the step index into range", function()
    local dibs = load("Tester-Realm", true)
    assert_equal(dibs.Wizard.GetStepCount(), dibs.Wizard.SetCurrentStepIndex(999))
    assert_equal(1, dibs.Wizard.SetCurrentStepIndex(-5))
  end)

  it("reuses Dibs.SetupAssistant.Evaluate and does not override its verdict", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Installation.Initialize(nil).ok)
    local status = dibs.Wizard.GetStatus()
    local report = dibs.SetupAssistant.Evaluate()
    local readiness = stepById(status, "readiness")
    assert_not_nil(readiness.detail)
    assert_equal(report.status, readiness.detail.status)
    assert_true(report.status ~= "READY_FOR_RAID")
    assert_equal("BLOCKED", status.overallState)
  end)

  it("blocks an otherwise complete review when SetupAssistant is unavailable or needs attention", function()
    local dibs = configuredGuild()
    for _, reportStatus in ipairs({ "UNAVAILABLE", "NEEDS_ATTENTION", "UNRECOGNIZED" }) do
      dibs.SetupAssistant.Evaluate = function()
        return { status = reportStatus, checks = {
          { id = "local_services", state = "blocked", impact = "Transport unavailable", remediation = "Repair transport" },
        } }
      end
      local status = dibs.Wizard.GetStatus()
      assert_equal("READY", stepById(status, "review").status)
      assert_equal("BLOCKED", status.overallState)
      assert_true(stepById(status, "readiness").status ~= "READY")
    end
  end)

  it("keeps a warning in Review when SetupAssistant is ready", function()
    local dibs, season = configuredGuild()
    dibs.SetupAssistant.Evaluate = function() return { status = "READY_FOR_RAID", checks = {} } end
    publishRule(dibs, season.id, 1, 1)
    local status = dibs.Wizard.GetStatus()
    assert_equal("READY", stepById(status, "rankRules").status)
    assert_equal("ACTION_REQUIRED", stepById(status, "allocationReconciliation").status)
    assert_true(stepById(status, "allocationReconciliation").summary:find("players need starting-allocation reconciliation", 1, true) ~= nil)
    assert_equal("WARNING", stepById(status, "review").status)
    assert_equal("READY", stepById(status, "readiness").status)
    assert_equal("PARTIALLY_CONFIGURED", status.overallState)
  end)

  it("recomputes raid readiness after a refresh when SetupAssistant changes", function()
    local dibs = configuredGuild()
    local reportStatus = "UNAVAILABLE"
    dibs.SetupAssistant.Evaluate = function() return { status = reportStatus, checks = {} } end
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_equal("BLOCKED", dibs.Wizard.GetStatus().overallState)
    reportStatus = "READY_FOR_RAID"
    frame:Refresh()
    assert_equal("READY_FOR_RAID", dibs.Wizard.GetStatus().overallState)
  end)

  it("applies Dibs loot presets from the turnkey Configure stage", function()
    local dibs = load("Tester-Realm", true)
    dibs.Wizard.SetSelectedProfileId("progression")
    dibs.Wizard.SetCurrentStage("configure")
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    local applyButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == "Apply this setup" then applyButton = widget end
    end
    assert_not_nil(applyButton)
    applyButton.callbacks.OnClick(applyButton, "OnClick")

    local types = dibs.RCOptions.GetLootTypeOptions().types
    assert_true(types.get(nil, "TOKEN"))
    assert_true(types.get(nil, "TOKEN_SET"))
    assert_false(types.get(nil, "MOUNTS"))
    assert_false(types.get(nil, "default"))
    assert_equal("wizard", frame.mountedPage)
  end)

  it("keeps the readiness check and safe report on Raid Readiness", function()
    local dibs = load("Tester-Realm", true)
    local runCount, reportMode = 0, nil
    dibs.Readiness.Run = function()
      runCount = runCount + 1
      return { status = "READY_FOR_RAID" }
    end
    dibs.Readiness.OpenReport = function(mode)
      reportMode = mode
      return {}, {}, nil
    end
    dibs.OfficerUI.CreateWindow("setup")
    local function findButton(text)
      for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
        if candidate.kind == "Button" and candidate.text == text then return candidate end
      end
    end
    local checkButton = findButton(dibs.L.READINESS_RUN_CHECK)
    local reportButton = findButton(dibs.L.READINESS_OPEN_SAFE_REPORT)
    assert_not_nil(checkButton)
    assert_not_nil(reportButton)
    checkButton.callbacks.OnClick(checkButton, "OnClick")
    assert_equal(1, runCount)
    reportButton = findButton(dibs.L.READINESS_OPEN_SAFE_REPORT)
    reportButton.callbacks.OnClick(reportButton, "OnClick")
    assert_equal("safe", reportMode)
  end)

  it("preserves missing and surplus allocations from RankRules reconciliation", function()
    local dibs, season = configuredGuild()
    local rules = dibs.RankRules.GetRulesForSeason(season.id)
    assert_equal("READY", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 0).status)
    assert_equal("OPTIONAL", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 1).status)

    publishRule(dibs, season.id, 1, 1)
    local officer = rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 1)
    assert_equal("READY", officer.status)
    assert_true(officer.pendingReconciliation > 0)
    local status = dibs.Wizard.GetStatus()
    assert_equal("READY", stepById(status, "rankRules").status)
    assert_equal("ACTION_REQUIRED", stepById(status, "allocationReconciliation").status)

    rules = dibs.RankRules.GetRulesForSeason(season.id)
    rules["1"] = { rankIndex = 1, rankName = "Officer" }
    assert_equal("ACTION_REQUIRED", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 1).status)
    rules["1"] = nil
    assert_equal("ACTION_REQUIRED", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 1).status)

    publishRule(dibs, season.id, 0, 0)
    assert_equal("OPTIONAL", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 0).status)
  end)

  it("does not mark a missing rank reconciliation projection or empty roster READY", function()
    local dibs, season = configuredGuild()
    dibs.RankRules.GetAllocationReconciliation = function() error("reconciliation unavailable") end
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "rankRules").status)
    dibs.RankRules.GetAllocationReconciliation = function() return {} end
    assert_equal("READY", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 0).status)
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "rankRules").status)
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "allocationReconciliation").status)
    dibs.RankRules.GetAllocationReconciliation = function()
      return { { rankIndex = 0, status = "UNKNOWN" } }
    end
    assert_equal("READY", rankByIndex(dibs.RankRules.GetRankConfigurationSummary(season.id), 0).status)
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "allocationReconciliation").status)
    _G.GetNumGuildMembers = function() return 0 end
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "rankRules").status)
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "allocationReconciliation").status)
  end)

  it("does not warn when Dibs allocation is disabled for every current rank", function()
    local dibs, season = configuredGuild()
    for _, rankIndex in ipairs({ 0, 1, 3 }) do
      publishRule(dibs, season.id, rankIndex, 0, false)
    end
    local step = stepById(dibs.Wizard.GetStatus(), "allocationReconciliation")
    assert_equal("OPTIONAL", step.status)
    assert_true(step.summary:find("disabled", 1, true) ~= nil)
  end)

  it("distinguishes healthy, unavailable, behind, and unknown Sync states", function()
    local dibs = configuredGuild()
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "sync").status)

    dibs.Sync.transportRegistered = false
    local unavailable = stepById(dibs.Wizard.GetStatus(), "sync")
    assert_equal("WARNING", unavailable.status)
    assert_true(unavailable.summary:find("transport is unavailable", 1, true) ~= nil)

    dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    local both = stepById(dibs.Wizard.GetStatus(), "sync")
    assert_equal("WARNING", both.status)
    assert_true(both.summary:find("transport is unavailable", 1, true) ~= nil)
    assert_true(both.summary:find("behind", 1, true) ~= nil)

    dibs.Sync.transportRegistered = true
    assert_true(stepById(dibs.Wizard.GetStatus(), "sync").summary:find("behind", 1, true) ~= nil)
    dibs.Sync.ClearSyncBehind()
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "sync").status)

    dibs.Sync.GetStatus = function() return { state = "UNRECOGNIZED" } end
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "sync").status)
    dibs.Sync.GetStatus = function() return nil end
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "sync").status)
  end)

  it("recomputes Sync readiness on a live Wizard refresh after transport recovery", function()
    local dibs = configuredGuild()
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    dibs.Wizard.SetCurrentStepIndex(10)
    frame:ActivateRoute("wizard")
    dibs.Sync.transportRegistered = false
    frame:Refresh()
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "sync").status)
    dibs.Sync.transportRegistered = true
    dibs.Sync.ClearSyncBehind()
    frame:Refresh()
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "sync").status)
  end)

  it("reflects a failed then successful transport send without retaining stale unavailability", function()
    local dibs = configuredGuild()
    local sendComm = dibs.Ace3.SendComm
    dibs.Ace3.SendComm = function() return false end
    assert_false(dibs.Sync.Send({ type = "HELLO" }, "GUILD"))
    assert_equal("SYNC_UNAVAILABLE", dibs.Sync.GetStatus().state)
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "sync").status)

    dibs.Ace3.SendComm = sendComm
    assert_true(dibs.Sync.Send({ type = "HELLO" }, "GUILD"))
    assert_equal("SYNC_READY", dibs.Sync.GetStatus().state)
    assert_equal("READY", stepById(dibs.Wizard.GetStatus(), "sync").status)

    dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    dibs.Ace3.SendComm = function() return false end
    assert_false(dibs.Sync.Send({ type = "HELLO" }, "GUILD"))
    dibs.Ace3.SendComm = sendComm
    assert_true(dibs.Sync.Send({ type = "HELLO" }, "GUILD"))
    assert_equal("SYNC_BEHIND", dibs.Sync.GetStatus().state)
    assert_equal("WARNING", stepById(dibs.Wizard.GetStatus(), "sync").status)
  end)

  it("does not mark warning-only turnkey verification as blocked", function()
    local dibs = configuredGuild()
    local status = dibs.Wizard.GetTurnkeyStatus()
    assert_equal("PARTIALLY_CONFIGURED", status.overallState)
    for _, result in ipairs(status.verification) do
      assert_true(result.severity ~= "BLOCKING")
    end
  end)
end)

describe("Guided Setup Wizard UI", function()
  local function findLatestWidget(predicate)
    for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
      local widget = _G.__dibsAceWidgets[index]
      if predicate(widget) then return widget end
    end
  end

  local function clickLatestButton(pattern)
    local widget = findLatestWidget(function(candidate)
      return candidate.kind == "Button" and type(candidate.text) == "string" and candidate.text:find(pattern, 1, true)
    end)
    assert_not_nil(widget, "Button not found matching: " .. pattern)
    widget.callbacks.OnClick(widget, "OnClick")
    return widget
  end

  it("opens with Choose selected and moves through the three primary stages", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_equal("choose", dibs.Wizard.GetCurrentStage())
    clickLatestButton("Selected: Progression raid")
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    clickLatestButton("Back to profiles")
    assert_equal("choose", dibs.Wizard.GetCurrentStage())
    clickLatestButton("3 Verify")
    assert_equal("verify", dibs.Wizard.GetCurrentStage())
  end)

  it("points directly to the first outstanding issue", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    clickLatestButton("3 Verify")
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text == "[X] BLOCKING"
        and widget.dibsMidnightStatus == "danger" and widget.dibsMidnightColor
        and widget.dibsMidnightColor[1] > widget.dibsMidnightColor[2]
    end))
    clickLatestButton("Fix first blocking issue")
    assert_equal("installation", frame.activeTab)
    assert_equal("verify", dibs.Wizard.GetCurrentStage())
  end)

  it("keeps detailed verification results inside a bounded responsive scroll frame", function()
    local dibs = load("Tester-Realm", true)
    dibs.Wizard.SetCurrentStage("verify")
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    local scroll = findLatestWidget(function(widget)
      return widget.kind == "ScrollFrame" and widget._dibsResizeOffset == 300
    end)
    assert_not_nil(scroll)
    assert_true(tonumber(scroll.height) >= 120)
    assert_true(tonumber(scroll.height) <= 520)
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Button" and widget.text == "Review setup profile"
        and widget.parent ~= scroll
    end))
  end)

  it("shows the exact failed setup action and routes SYNC_BEHIND to Synchronization", function()
    local dibs = load("Tester-Realm", true)
    dibs.Wizard.SetSelectedProfileId("progression")
    dibs.Wizard.SetCurrentStage("configure")
    dibs.Wizard.ApplyProfile = function()
      return {
        ok = false,
        reasonCode = "SETUP_PROFILE_PARTIAL_FAILURE",
        actions = {
          {
            id = "initialize", title = "Guild foundation", outcome = "FAILED",
            reasonCode = "SYNC_BEHIND", stage = "cutover", route = "sync",
          },
        },
      }
    end
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    clickLatestButton("Apply this setup")
    assert_true(frame.statusMessage:find("Guild foundation - SYNC_BEHIND", 1, true) ~= nil)
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text == "Reason: SYNC_BEHIND"
    end))
    clickLatestButton("Open Synchronization")
    assert_equal("sync", frame.activeTab)
  end)

  it("opens Automatic Dibs from the Allocation Reconciliation verification result", function()
    local dibs, season = configuredGuild()
    publishRule(dibs, season.id, 1, 1)
    dibs.Wizard.SetCurrentStage("verify")
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    clickLatestButton("Open Allocation Reconciliation")
    assert_equal("automaticDibs", frame.activeTab)
  end)

  it("keeps custom setup mutation-free and opens advanced settings", function()
    local dibs = load("Tester-Realm", true)
    dibs.Wizard.SetSelectedProfileId("custom")
    dibs.Wizard.SetCurrentStage("configure")
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    local before = loader.snapshotProductionState(dibs)
    clickLatestButton("Open advanced settings")
    assert_equal("settings", frame.activeTab)
    assert_true(loader.productionStateEquals(dibs, before))
  end)

  it("defers policy adoption for an Officer and applies it for the GM", function()
    local gm = load("Tester-Realm", true)
    assert_true(gm.Installation.Initialize(nil).ok)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)

    local officer = load("Officer-Realm", false, saved)
    officer.Wizard.SetCurrentStage("configure")
    local officerFrame = officer.OfficerUI.CreateWindow("wizard")
    officerFrame:ActivateRoute("wizard")
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text == "[!] DEFERRED"
    end))

    gm = load("Tester-Realm", true, saved)
    gm.Wizard.SetCurrentStage("configure")
    local gmFrame = gm.OfficerUI.CreateWindow("wizard")
    gmFrame:ActivateRoute("wizard")
    clickLatestButton("Apply this setup")
    assert_true(gm.OperationalPolicy.IsAdopted())
  end)

  it("shows authoritative readiness findings and refreshes verification", function()
    local dibs, season = configuredGuild()
    dibs.SetupAssistant.Evaluate = function() return { status = "UNAVAILABLE", checks = {
      { id = "local_services", state = "unavailable", impact = "Transport unavailable", remediation = "Repair transport" },
    } } end
    dibs.Wizard.SetCurrentStage("verify")
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text:find("Transport unavailable", 1, true) ~= nil
    end))

    publishRule(dibs, season.id, 1, 1)
    frame:Refresh()
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Button" and widget.text == "Open Allocation Reconciliation"
    end))

    dibs.SetupAssistant.Evaluate = function() return { status = "UNAVAILABLE", checks = {
      { id = "raid_context", state = "unavailable", impact = "No raid group is active, so live-session checks cannot run yet.",
        remediation = "This is expected outside a raid; run the check again after entering the intended raid." },
    } } end
    frame:Refresh()
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text:find("No raid group is active", 1, true) ~= nil
    end))
  end)

  it("denies configuration access to a non-officer", function()
    local dibs = load("Member-Realm", false)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_nil(findLatestWidget(function(widget) return widget.kind == "Button" and widget.text == "1 Choose" end))
  end)

  it("permits verified officers to initialize setup proposal, create seasons, and set rank rules", function()
    local officer = load("Officer-Realm", false)
    assert_true(officer.Permissions.IsOfficer())
    assert_false(officer.Permissions.IsGM())

    -- Installation status should not have GUILD_MASTER_REQUIRED blocker for officer
    local status = officer.Installation.GetStatus(nil)
    local hasGMBAN = false
    for _, b in ipairs(status.blockers or {}) do
      if b == "GUILD_MASTER_REQUIRED" then hasGMBAN = true end
    end
    assert_false(hasGMBAN)

    -- Officer can initialize setup proposal
    local initResult = officer.Installation.Initialize(nil)
    assert_true(initResult.ok)
    assert_equal("PROPOSAL_CREATED", initResult.reasonCode)

    -- Officer can create season and set rank rules
    local createSeason = officer.ProtectedActions.Execute("season.create", nil, { name = "Officer Season" })
    assert_true(createSeason.ok)
    local seasonId = createSeason.value.id

    local setRule = officer.ProtectedActions.Execute("rank.set", nil, {
      seasonId = seasonId, rankIndex = 1, rankName = "Officer", allocation = 2,
    })
    assert_true(setRule.ok)

    -- Officer can navigate the turnkey stages.
    local frame = officer.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Button" and widget.text:find("1 Choose", 1, true) ~= nil
    end))
  end)
end)
