local loader = require("helpers.load_addon")

local function load(localVariables)
  return select(2, loader.load({ withAce3 = true, localVariables = localVariables, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { 0, 1 },
  } }))
end

local function status(rows, primary)
  return { verification = rows, primaryIssueId = primary, overallState = "BLOCKED" }
end

local function finding(id, severity, route)
  return { id = id, severity = severity, title = id, explanation = "technical SEASON_CATALOG requirement",
    nextAction = "technical diagnostic", route = route }
end

local function foundation(dibs)
  assert_true(dibs.Wizard.ApplyProfile("progression").ok)
end

local function disableRoster(dibs)
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = false }, nil, "test projection"))
end

local function createDraft(dibs)
  local result = dibs.SeasonalRoster.CreateSeason({ name = "Test progression", startAt = dibs.GetTimestamp() + 86400,
    registrationStartAt = dibs.GetTimestamp(), categories = { "PROGRESSION" } }, "resume-season-draft")
  assert_true(result.ok, tostring(result.code))
  return result
end

describe("Guided Setup ordered resumable completion", function()
  it("guides a real fresh install to foundation before a season or rank rules", function()
    local dibs = load()
    local nextStep = dibs.Wizard.GetNextSetupStep(status({ finding("rankRules", "BLOCKING", "ranks") }, "rankRules"))
    assert_equal("wizard", nextStep.route)
    assert_equal("configure", nextStep.stage)
    assert_nil(nextStep.prepareSeason)
    assert_false(nextStep.done)
    assert_equal("error", nextStep.tone)
  end)

  it("guides a real foundation to first seasonal draft ahead of rank publication", function()
    local dibs = load()
    foundation(dibs)
    local report = dibs.Wizard.GetTurnkeyStatus()
    local before = dibs.Sync.CalculateContentHash(dibs.GetDB())
    local nextStep = dibs.Wizard.GetNextSetupStep(report)
    assert_equal("seasonDraft", nextStep.id)
    assert_true(nextStep.prepareSeason)
    assert_equal("configure", nextStep.stage)
    assert_equal("warning", nextStep.tone)
    assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetDB()))
    assert_equal("BLOCKED", report.overallState)
    assert_true(nextStep.index <= nextStep.total)
  end)

  it("keeps authoritative sync and account blockers before season guidance", function()
    local dibs = load()
    foundation(dibs)
    for _, id in ipairs({ "installation", "sync", "ledger" }) do
      local issue = dibs.Wizard.GetNextSetupStep(status({ finding(id, "BLOCKING", "sync") }, id))
      assert_equal(id, issue.id)
      assert_equal("error", issue.tone)
      assert_nil(issue.prepareSeason)
    end
  end)

  it("keeps a saved draft ahead of rank allocation without opening it automatically", function()
    local dibs = load()
    foundation(dibs)
    local draft = createDraft(dibs)
    local before = dibs.Sync.CalculateContentHash(dibs.GetDB())
    local issue = dibs.Wizard.GetNextSetupStep(status({ finding("rankRules", "BLOCKING", "ranks") }, "rankRules"))
    assert_equal("seasonPublication", issue.id)
    assert_equal("seasonalRoster", issue.route)
    assert_equal(draft.value, issue.seasonId)
    assert_equal("DRAFT", dibs.SeasonalRoster.ListSeasons()[1].registrationState)
    assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetDB()))
  end)

  it("advances past draft guidance once registration was explicitly opened", function()
    local dibs = load()
    foundation(dibs)
    local draft = createDraft(dibs)
    local opened = dibs.SeasonalRoster.SetRegistrationState(draft.value, "OPEN", draft.revision,
      "resume-open-registration", "Guild reviewed season")
    assert_true(opened.ok, tostring(opened.code))
    local issue = dibs.Wizard.GetNextSetupStep(status({ finding("rankRules", "BLOCKING", "ranks") }, "rankRules"))
    assert_equal("rankRules", issue.id)
    assert_equal("ranks", issue.route)
    assert_nil(issue.explanation:find("SEASON_CATALOG", 1, true))
  end)

  it("does not require a disabled optional seasonal module", function()
    local dibs = load()
    foundation(dibs)
    disableRoster(dibs)
    local issue = dibs.Wizard.GetNextSetupStep(status({ finding("rankRules", "BLOCKING", "ranks") }, "rankRules"))
    assert_equal("rankRules", issue.id)
    assert_equal("error", issue.tone)
  end)

  it("does not choose a leftover draft ahead of a published current season", function()
    local dibs = load()
    foundation(dibs)
    local draft = createDraft(dibs)
    assert_true(dibs.SeasonalRoster.SetRegistrationState(draft.value, "OPEN", draft.revision,
      "resume-published", "Guild reviewed season").ok)
    local leftover = dibs.SeasonalRoster.CreateSeason({ name = "Later draft", categories = { "PROGRESSION" },
      startAt = dibs.GetTimestamp() + 172800, registrationStartAt = dibs.GetTimestamp() }, "later-draft")
    assert_true(leftover.ok, tostring(leftover.code))
    assert_equal("rankRules", dibs.Wizard.GetNextSetupStep(status({ finding("rankRules", "BLOCKING", "ranks") }, "rankRules")).id)
  end)

  it("uses the authoritative primary blocker before warnings", function()
    local dibs = load()
    foundation(dibs)
    disableRoster(dibs)
    local issue = dibs.Wizard.GetNextSetupStep(status({ finding("dibsRules", "WARNING", "lootTypes"),
      finding("rankRules", "BLOCKING", "ranks") }, "rankRules"))
    assert_equal("rankRules", issue.id)
    local inconsistent = dibs.Wizard.GetNextSetupStep(status({ finding("dibsRules", "WARNING", "lootTypes"),
      finding("rankRules", "BLOCKING", "ranks") }, "dibsRules"))
    assert_equal("rankRules", inconsistent.id)
  end)

  it("uses warnings after blockers and computes done only from fresh results", function()
    local dibs = load()
    foundation(dibs)
    disableRoster(dibs)
    local report = status({ finding("rankRules", "READY"), finding("rclootcouncil", "OPTIONAL"),
      finding("dibsRules", "WARNING", "lootTypes") }, "dibsRules")
    local issue = dibs.Wizard.GetNextSetupStep(report)
    assert_equal("dibsRules", issue.id)
    assert_equal("warning", issue.tone)
    assert_equal(2, issue.completed)
    assert_equal(3, issue.total)
    assert_false(issue.done)
    report.verification[3].severity = "READY"
    local done = dibs.Wizard.GetNextSetupStep(report)
    assert_true(done.done)
    assert_equal("success", done.tone)
    assert_equal(3, done.completed)
    assert_equal("BLOCKED", report.overallState)
  end)

  it("persists draft values and stable operation ID across a real loader reload", function()
    local dibs = load()
    local dbBefore = dibs.Sync.CalculateContentHash(dibs.GetDB())
    assert_true(dibs.Wizard.SaveSetupProgress({ stage = "configure", profileId = "broad",
      correctionRoute = "ranks", issueId = "rankRules", seasonDraft = {
        enabled = true, name = "Guild's next season", categories = "Progression, Casual", raidRules = "Guild choices",
        raidDifficulties = { "NORMAL", "MYTHIC" },
        timeZone = "America/Toronto", operationId = "wizard-resume-stable",
        seasonalRosterNewStartDate = "2026-11-", seasonalRosterNewStartHour = "19", seasonalRosterNewStartMinute = "30",
        scheduleRows = { { weekday = 3, startTime = "19:", durationMinutes = 150, timeZone = "America/Toronto", difficulty = "MYTHIC" } },
      } }))
    assert_equal(dbBefore, dibs.Sync.CalculateContentHash(dibs.GetDB()))
    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsLocalDB)
    dibs = load(saved)
    local progress = dibs.Wizard.GetSetupProgress()
    assert_equal("configure", progress.stage)
    assert_equal("broad", progress.profileId)
    assert_equal("ranks", progress.correctionRoute)
    assert_equal("wizard-resume-stable", progress.seasonDraft.operationId)
    assert_equal("2026-11-", progress.seasonDraft.seasonalRosterNewStartDate)
    assert_equal("19:", progress.seasonDraft.scheduleRows[1].startTime)
    assert_equal(150, progress.seasonDraft.scheduleRows[1].durationMinutes)
    assert_equal("NORMAL", progress.seasonDraft.raidDifficulties[1])
    assert_equal("MYTHIC", progress.seasonDraft.raidDifficulties[2])
    assert_equal("MYTHIC", progress.seasonDraft.scheduleRows[1].difficulty)
  end)

  it("returns independent copies and never saves widgets or authoritative data", function()
    local dibs = load()
    assert_true(dibs.Wizard.SaveSetupProgress({ seasonDraft = { enabled = true, name = "Saved",
      scheduleRows = { { weekday = 3, startTime = "19:00" } } } }))
    local first = dibs.Wizard.GetSetupProgress()
    first.seasonDraft.name, first.seasonDraft.scheduleRows[1].weekday = "Changed", 6
    assert_equal("Saved", dibs.Wizard.GetSetupProgress().seasonDraft.name)
    assert_equal(3, dibs.Wizard.GetSetupProgress().seasonDraft.scheduleRows[1].weekday)
    local before = dibs.Sync.CalculateContentHash(dibs.GetLocalSettings())
    for _, patch in ipairs({ { completed = true }, { stage = "invalid" }, { profileId = "invalid" },
      { correctionRoute = "unknown" }, { issueId = {} }, { seasonDraft = { control = {} } },
      { seasonDraft = { name = function() end } }, { seasonDraft = { scheduleRows = { { frame = {} } } } } }) do
      local ok, reason = dibs.Wizard.SaveSetupProgress(patch)
      assert_nil(ok)
      assert_equal("INVALID_SETUP_PROGRESS", reason)
      assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetLocalSettings()))
    end
  end)

  it("rejects oversized or sparse draft data before writing any fields", function()
    local dibs = load()
    dibs.Wizard.SetCurrentStage("choose")
    local before = dibs.Sync.CalculateContentHash(dibs.GetLocalSettings())
    for _, draft in ipairs({ { name = string.rep("x", 81) }, { raidRules = string.rep("x", 8001) },
      { timeZone = string.rep("x", 65) }, { operationId = "invalid op" },
      { scheduleRows = { [2] = { weekday = 3 } } }, { scheduleRows = { { durationMinutes = 601 } } },
      { scheduleRows = { { weekday = 8 } } }, { scheduleRows = { { startTime = "19:000" } } },
      { raidDifficulties = { "INVALID" } }, { raidDifficulties = { "NORMAL", "NORMAL" } },
      { raidDifficulties = { [2] = "HEROIC" } }, { scheduleRows = { { difficulty = "INVALID" } } } }) do
      assert_nil(dibs.Wizard.SaveSetupProgress({ stage = "verify", seasonDraft = draft }))
      assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetLocalSettings()))
    end
  end)

  it("supports incomplete empty form fields and existing maximum domain values", function()
    local dibs = load()
    assert_true(dibs.Wizard.SaveSetupProgress({ seasonDraft = { name = string.rep("x", 80),
      raidRules = string.rep("x", 8000), enabled = false, seasonalRosterNewStartDate = "",
      scheduleRows = { {}, { startTime = "", durationMinutes = 600, timeZone = string.rep("x", 64) } } } }))
    assert_equal(8000, #dibs.Wizard.GetSetupProgress().seasonDraft.raidRules)
  end)

  it("clears correction context and a pending season draft explicitly", function()
    local dibs = load()
    assert_true(dibs.Wizard.SaveSetupProgress({ correctionRoute = "ranks", issueId = "rankRules", seasonDraft = { name = "Keep" } }))
    assert_true(dibs.Wizard.SaveSetupProgress({ correctionRoute = false, issueId = false }))
    assert_nil(dibs.Wizard.GetSetupProgress().correctionRoute)
    assert_nil(dibs.Wizard.GetSetupProgress().issueId)
    assert_equal("Keep", dibs.Wizard.GetSetupProgress().seasonDraft.name)
    assert_true(dibs.Wizard.SaveSetupProgress({ seasonDraft = false }))
    assert_nil(dibs.Wizard.GetSetupProgress().seasonDraft)
  end)

  it("isolates guild stage, profile, form and correction context", function()
    local dibs = load()
    local originalKey, scope = dibs.GetGuildKey, "first:guild"
    dibs.GetGuildKey = function() return scope end
    assert_true(dibs.Wizard.SaveSetupProgress({ stage = "verify", profileId = "broad", correctionRoute = "ranks",
      issueId = "rankRules", seasonDraft = { name = "First guild" } }))
    scope = "second:guild"
    assert_equal("choose", dibs.Wizard.GetCurrentStage())
    assert_equal("progression", dibs.Wizard.GetSelectedProfileId())
    assert_nil(dibs.Wizard.GetSetupProgress().seasonDraft)
    assert_nil(dibs.Wizard.GetSetupProgress().correctionRoute)
    dibs.Wizard.SetSelectedProfileId("custom")
    scope = "first:guild"
    assert_equal("verify", dibs.Wizard.GetCurrentStage())
    assert_equal("broad", dibs.Wizard.GetSelectedProfileId())
    assert_equal("First guild", dibs.Wizard.GetSetupProgress().seasonDraft.name)
    dibs.GetGuildKey = originalKey
  end)

  it("migrates legacy UI preferences once without sharing them with another guild", function()
    local dibs = load({ settings = { turnkeyWizardStage = "verify", turnkeyWizardProfileId = "broad" } })
    assert_equal("verify", dibs.Wizard.GetCurrentStage())
    assert_equal("broad", dibs.Wizard.GetSelectedProfileId())
    assert_true(dibs.Wizard.SaveSetupProgress({}))
    dibs.GetGuildKey = function() return "new:guild" end
    assert_equal("choose", dibs.Wizard.GetCurrentStage())
    assert_equal("progression", dibs.Wizard.GetSelectedProfileId())
  end)

  it("never labels successful foundation, preset, policy or season actions with a failure reason", function()
    local dibs = load()
    local seenOptions
    local apply = dibs.RCOptions.ApplyInstallationPreset
    dibs.RCOptions.ApplyInstallationPreset = function(key, options) seenOptions = options; return apply(key, options) end
    local result = dibs.Wizard.ApplyProfile("progression", nil, {
      seasonDraft = { name = "Progression", startAt = dibs.GetTimestamp() + 86400,
        registrationStartAt = dibs.GetTimestamp(), categories = { "PROGRESSION" } }, seasonOperationId = "success-draft" })
    assert_true(result.ok, tostring(result.reasonCode))
    assert_true(seenOptions.silent)
    assert_nil(result.reasonCode)
    for _, action in ipairs(result.actions) do
      if action.outcome == "APPLIED" or action.outcome == "ALREADY_READY" then assert_nil(action.reasonCode, action.id) end
    end
  end)

  it("preserves a real preset failure reason and failure-shaped overall result", function()
    local dibs = load()
    dibs.RCOptions.ApplyInstallationPreset = function() return false, "PRESET_TEST_FAILURE" end
    local result = dibs.Wizard.ApplyProfile("progression")
    assert_false(result.ok)
    assert_equal("SETUP_PROFILE_PARTIAL_FAILURE", result.reasonCode)
    assert_equal("FAILED", result.actions[2].outcome)
    assert_equal("PRESET_TEST_FAILURE", result.actions[2].reasonCode)
  end)
end)
