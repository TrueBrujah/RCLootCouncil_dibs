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

local function publishRule(dibs, seasonId, rankIndex, allocation)
  local result = dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = seasonId, rankIndex = rankIndex, rankName = "Rank " .. rankIndex, allocation = allocation,
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

  it("opens with step 1 selected, supports Next/Back, and navigates to an existing page via Open", function()
    local dibs = load("Tester-Realm", true)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_equal(1, dibs.Wizard.GetCurrentStepIndex())

    clickLatestButton("Next")
    assert_equal(2, dibs.Wizard.GetCurrentStepIndex())
    clickLatestButton("Back")
    assert_equal(1, dibs.Wizard.GetCurrentStepIndex())

    clickLatestButton("Open Installation")
    assert_equal("installation", frame.activeTab)
  end)

  it("jumps directly to a step and to the first outstanding issue", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Installation.Initialize(nil).ok)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")

    clickLatestButton("4 Seasons")
    assert_equal(4, dibs.Wizard.GetCurrentStepIndex())

    dibs.Wizard.SetCurrentStepIndex(1)
    frame:Refresh()
    clickLatestButton("Jump to first issue")
    local status = dibs.Wizard.GetStatus()
    assert_true(status.steps[dibs.Wizard.GetCurrentStepIndex()].status ~= "READY")
  end)

  it("opens Automatic Dibs from the Allocation Reconciliation step", function()
    local dibs = load("Tester-Realm", true)
    local status = dibs.Wizard.GetStatus()
    local index
    for stepIndex, step in ipairs(status.steps) do
      if step.id == "allocationReconciliation" then index = stepIndex break end
    end
    assert_not_nil(index)
    dibs.Wizard.SetCurrentStepIndex(index)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    clickLatestButton("Open Allocation Reconciliation")
    assert_equal("automaticDibs", frame.activeTab)
  end)

  it("shows policy adoption only to the GM and removes the action after adoption", function()
    local gm = load("Tester-Realm", true)
    assert_true(gm.Installation.Initialize(nil).ok)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local function policyIndex(dibs)
      for index, step in ipairs(dibs.Wizard.GetStatus().steps) do
        if step.id == "operationalPolicy" then return index end
      end
    end

    local officer = load("Officer-Realm", false, saved)
    officer.Wizard.SetCurrentStepIndex(policyIndex(officer))
    local officerFrame = officer.OfficerUI.CreateWindow("wizard")
    officerFrame:ActivateRoute("wizard")
    assert_nil(findLatestWidget(function(widget)
      return widget.kind == "Button" and widget.text == "Adopt and publish Guild Policy"
    end))
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text == "Only the Guild Master can adopt Guild Policy."
    end))

    gm = load("Tester-Realm", true, saved)
    gm.Wizard.SetCurrentStepIndex(policyIndex(gm))
    local gmFrame = gm.OfficerUI.CreateWindow("wizard")
    gmFrame:ActivateRoute("wizard")
    local adoptButton = findLatestWidget(function(widget)
      return widget.kind == "Button" and widget.text == "Adopt and publish Guild Policy"
    end)
    assert_not_nil(adoptButton)
    local widgetsBeforeRefresh = #(_G.__dibsAceWidgets or {})
    adoptButton.callbacks.OnClick(adoptButton, "OnClick")
    assert_true(gm.OperationalPolicy.IsAdopted())
    for index = widgetsBeforeRefresh + 1, #(_G.__dibsAceWidgets or {}) do
      local widget = _G.__dibsAceWidgets[index]
      assert_false(widget.kind == "Button" and widget.text == "Adopt and publish Guild Policy")
    end
  end)

  it("shows authoritative readiness findings and refreshes the affected rank in Review", function()
    local dibs, season = configuredGuild()
    dibs.SetupAssistant.Evaluate = function() return { status = "UNAVAILABLE", checks = {
      { id = "local_services", state = "unavailable", impact = "Transport unavailable", remediation = "Repair transport" },
    } } end
    local reviewIndex
    for stepIndex, step in ipairs(dibs.Wizard.GetStatus().steps) do
      if step.id == "review" then reviewIndex = stepIndex break end
    end
    assert_not_nil(reviewIndex)
    dibs.Wizard.SetCurrentStepIndex(reviewIndex)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text == "Overall: Blocked"
    end))
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text:find("local_services: Transport unavailable", 1, true) ~= nil
    end))

    publishRule(dibs, season.id, 1, 1)
    frame:Refresh()
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text:find("Allocation Reconciliation", 1, true) ~= nil
    end))

    dibs.Wizard.SetCurrentStepIndex(13)
    frame:Refresh()
    assert_not_nil(findLatestWidget(function(widget)
      return widget.kind == "Label" and widget.text:find("local_services: Transport unavailable", 1, true) ~= nil
    end))
  end)

  it("denies configuration access to a non-officer", function()
    local dibs = load("Member-Realm", false)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_nil(findLatestWidget(function(widget) return widget.kind == "Button" and widget.text == "Next" end))
  end)
end)
