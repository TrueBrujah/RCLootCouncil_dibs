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

describe("Dibs.Wizard status derivation", function()
  it("reports NEW_INSTALLATION/FIRST_TIME_SETUP before any configuration exists", function()
    local dibs = load("Tester-Realm", true)
    local status = dibs.Wizard.GetStatus()
    assert_equal("NEW_INSTALLATION", status.overallState)
    assert_equal("FIRST_TIME_SETUP", status.mode)
    assert_equal("ACTION_REQUIRED", stepById(status, "installation").status)
  end)

  it("reaches READY_FOR_RAID/REVIEW_CONFIGURATION on a fully initialized, configured guild", function()
    local dibs = load("Tester-Realm", true)
    local result = dibs.Installation.Initialize(nil)
    assert_true(result.ok, tostring(result.reasonCode))
    local season = dibs.Seasons.GetCurrent()
    assert_not_nil(season)
    for rankIndex = 0, 3 do
      dibs.RankRules.SetAllocation(season.id, rankIndex, "Rank " .. rankIndex, 1)
    end

    local status = dibs.Wizard.GetStatus()
    assert_equal("installation", status.steps[1].id)
    assert_equal("READY", stepById(status, "installation").status)
    assert_equal("READY", stepById(status, "ledger").status)
    assert_equal("READY", stepById(status, "seasons").status)
    assert_equal("READY", stepById(status, "rankRules").status)
    assert_equal("READY_FOR_RAID", status.overallState)
    assert_equal("REVIEW_CONFIGURATION", status.mode)
  end)

  it("flags PARTIALLY_CONFIGURED when a rank is missing an allocation rule", function()
    -- Dibs.Initialize()'s automatic default rules cover ranks 0-5; a rank
    -- beyond that range is genuinely unconfigured, not merely pending
    -- reconciliation (which is a separate, expected, ongoing officer task).
    local unusualRanks = { [1] = 0, [2] = 1, [3] = 7 }
    local _, seeded = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true, guildMembers = roster, guildRankIndices = unusualRanks,
    } })
    assert_true(seeded.Installation.Initialize(nil).ok)
    local status = seeded.Wizard.GetStatus()
    assert_equal("PARTIALLY_CONFIGURED", status.overallState)
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

  it("reuses Dibs.SetupAssistant.Evaluate verbatim for the readiness step and never overrides its verdict", function()
    local dibs = load("Tester-Realm", true)
    assert_true(dibs.Installation.Initialize(nil).ok)
    local status = dibs.Wizard.GetStatus()
    local report = dibs.SetupAssistant.Evaluate()
    local readiness = stepById(status, "readiness")
    assert_not_nil(readiness.detail)
    assert_equal(report.status, readiness.detail.status)
    -- Outside a live raid, SetupAssistant's own verdict is not READY_FOR_RAID
    -- (raid_context is unavailable) -- the Wizard's configuration-completeness
    -- state must not depend on that and reaches READY_FOR_RAID anyway.
    assert_true(report.status ~= "READY_FOR_RAID")
    assert_equal("READY_FOR_RAID", status.overallState)
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

  it("denies configuration access to a non-officer", function()
    local dibs = load("Member-Realm", false)
    local frame = dibs.OfficerUI.CreateWindow("wizard")
    frame:ActivateRoute("wizard")
    assert_nil(findLatestWidget(function(widget) return widget.kind == "Button" and widget.text == "Next" end))
  end)
end)
