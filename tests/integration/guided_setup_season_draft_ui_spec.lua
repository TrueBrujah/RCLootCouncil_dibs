local loader = require("helpers.load_addon")

local function equalTree(expected, actual, path)
  path = path or "db"
  assert_equal(type(expected), type(actual), path)
  if type(expected) ~= "table" then assert_equal(expected, actual, path); return end
  for key, value in pairs(expected) do equalTree(value, actual[key], path .. "." .. tostring(key)) end
  for key in pairs(actual) do assert_not_nil(expected[key], path .. "." .. tostring(key)) end
end

local function setup(profile)
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Member-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 },
  } })
  -- The shared WoW stub fixes date/time independently. Calendar input needs
  -- the real table-to-timestamp round trip, as in the season editor tests.
  local originalDate, originalTime = _G.date, _G.time
  register_reset(function() _G.date, _G.time = originalDate, originalTime end)
  _G.date = os.date
  _G.time = function(value)
    if type(value) == "table" then return os.time(value) end
    return originalTime()
  end
  local buttons = {}
  local addButton = dibs.AceGUI.AddButton
  dibs.AceGUI.AddButton = function(shell, parent, label, callback, ...)
    buttons[label] = callback
    return addButton(shell, parent, label, callback, ...)
  end
  dibs.Wizard.SetSelectedProfileId(profile or "progression")
  dibs.Wizard.SetCurrentStage("configure")
  local window = dibs.OfficerUI.CreateWindow("wizard")
  return dibs, window, function() buttons[dibs.L.WIZARD_APPLY or "Apply this setup"]() end
end

local function enabledDraft(window)
  local draft = assert_not_nil(window.turnkeySeasonDraft)
  local control = assert_not_nil(draft.enabledControl)
  control.callbacks.OnValueChanged(control, "OnValueChanged", true)
  return window.turnkeySeasonDraft
end

local function fillDraft(dibs, window)
  local draft = enabledDraft(window)
  draft.nameControl.callbacks.OnTextChanged(draft.nameControl, "OnTextChanged", "Guild progression 2026")
  assert_nil(draft.categoryControl)
  draft.seasonalRosterNewStartDate, draft.seasonalRosterNewStartHour, draft.seasonalRosterNewStartMinute = "2026-11-20", "20", "15"
  draft.seasonalRosterNewEndDate, draft.seasonalRosterNewEndHour, draft.seasonalRosterNewEndMinute = "2026-12-20", "23", "00"
  draft.seasonalRosterNewRegistrationStartDate = "2026-11-16"
  draft.seasonalRosterNewRegistrationEndDate = "2026-11-19"
  draft.raidRules, draft.timeZone = "Guild-specific progression rules", "America/Toronto"
  local scheduleToggle = draft.sectionControls.schedule
  scheduleToggle.callbacks.OnClick(scheduleToggle, "OnClick")
  draft.addScheduleNight.callbacks.OnClick(draft.addScheduleNight, "OnClick")
  draft = window.turnkeySeasonDraft
  local controls = draft.scheduleControls[1]
  controls.day.callbacks.OnValueChanged(controls.day, "OnValueChanged", 3)
  controls.time.callbacks.OnTextChanged(controls.time, "OnTextChanged", "20:15")
  controls.difficulty.callbacks.OnValueChanged(controls.difficulty, "OnValueChanged", "MYTHIC")
  draft.difficultyControls[1].checkbox.callbacks.OnValueChanged(
    draft.difficultyControls[1].checkbox, "OnValueChanged", true)
  return window.turnkeySeasonDraft
end

describe("Guided Setup inline season draft UI", function()
  it("keeps selection, opting in, editing and previewing out of SavedVariables", function()
    local dibs, window = setup()
    local before = dibs.DeepCopy(dibs.GetDB())
    assert_false(window.turnkeySeasonDraft.enabled == true)
    assert_nil(dibs.OfficerUI.BuildWizardSeasonOptions(window))
    local draft = fillDraft(dibs, window)
    window:Refresh()
    local options = assert_not_nil(dibs.OfficerUI.BuildWizardSeasonOptions(window))
    assert_equal("Guild progression 2026", options.seasonDraft.name)
    assert_equal(draft.operationId, options.seasonOperationId)
    assert_true(dibs.Wizard.PreviewProfile("progression", nil, options).canApply)
    equalTree(before, dibs.GetDB())
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
  end)

  it("applies the real foundation and one explicit DRAFT without activating or allocating it", function()
    local dibs, window, apply = setup()
    fillDraft(dibs, window)
    local originalActive = dibs.GetCurrentSeasonId()
    apply()
    assert_true(window.turnkeySetupResult.ok)
    assert_true(dibs.Wizard.GetNavigationAccess().foundationReady)
    assert_equal("verify", dibs.Wizard.GetCurrentStage())
    local seasons = dibs.SeasonalRoster.ListSeasons()
    assert_equal(1, #seasons)
    local season = seasons[1]
    assert_equal("Guild progression 2026", season.name)
    assert_equal("DRAFT", season.persistedLifecycleState)
    assert_equal("DRAFT", season.registrationState)
    assert_equal("NORMAL", season.categories[1])
    assert_equal("HEROIC", season.categories[2])
    assert_equal("MYTHIC", season.categories[3])
    equalTree(season.categories, season.raidDifficulties, "raid categories")
    assert_equal("Guild-specific progression rules", season.raidRules)
    assert_equal(3, season.raidSchedule[1].weekday)
    assert_equal("20:15", season.raidSchedule[1].startTime)
    assert_equal("America/Toronto", season.raidSchedule[1].timeZone)
    assert_equal("MYTHIC", season.raidSchedule[1].difficulty)
    assert_equal("NORMAL", season.raidDifficulties[1])
    assert_equal(dibs.OfficerUI.ParseSeasonDateTime("2026-11-20", "20", "15", true), season.startAt)
    assert_equal(originalActive, dibs.GetCurrentSeasonId())
    local native = dibs.Seasons.GetById(season.seasonId)
    assert_true(native.isDraft)
    assert_false(native.isActive)
    local db = dibs.GetDB()
    assert_nil(db.rankRules and db.rankRules[season.seasonId])
    assert_nil(db.seasonalRoster.seasons[season.seasonId].activationManifest)
    for _, ledger in pairs(db.ledgers or {}) do
      for _, tx in pairs(ledger.transactions or {}) do
        assert_true(tx.seasonId ~= season.seasonId, "wizard must not allocate a draft season")
      end
    end
    dibs.Wizard.SetCurrentStage("configure")
    window:Refresh()
    assert_false(window.turnkeySeasonDraft.enabled)
    apply()
    assert_equal(1, #dibs.SeasonalRoster.ListSeasons())
  end)

  it("requires a raid category before applying the foundation", function()
    local dibs, window, apply = setup()
    local draft = fillDraft(dibs, window)
    for _, entry in ipairs(draft.difficultyControls) do
      entry.checkbox.callbacks.OnValueChanged(entry.checkbox, "OnValueChanged", false)
    end
    local before = dibs.DeepCopy(dibs.GetDB())
    apply()
    assert_equal(dibs.L.SEASONAL_ROSTER_CATEGORY_REQUIRED, window.turnkeySeasonDraft.message)
    assert_nil(window.turnkeySetupResult)
    equalTree(before, dibs.GetDB())
  end)

  it("rejects an invalid calendar date before any foundation changes", function()
    local dibs, window, apply = setup()
    local draft = fillDraft(dibs, window)
    draft.seasonalRosterNewStartDate = "2026-02-30"
    local before = dibs.DeepCopy(dibs.GetDB())
    apply()
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    assert_not_nil(window.turnkeySeasonDraft.message)
    assert_nil(window.turnkeySetupResult)
    equalTree(before, dibs.GetDB())
  end)

  it("rejects an incomplete raid night before any foundation changes", function()
    local dibs, window, apply = setup()
    local draft = fillDraft(dibs, window)
    draft.scheduleRows[1].startTime = "24:00"
    local before = dibs.DeepCopy(dibs.GetDB())
    apply()
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    assert_not_nil(window.turnkeySeasonDraft.message)
    assert_nil(window.turnkeySetupResult)
    equalTree(before, dibs.GetDB())
  end)

  it("validates the season name through the domain before initializing", function()
    local dibs, window, apply = setup()
    local draft = fillDraft(dibs, window)
    draft.nameControl.callbacks.OnTextChanged(draft.nameControl, "OnTextChanged", "")
    local before = dibs.DeepCopy(dibs.GetDB())
    apply()
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    assert_not_nil(window.turnkeySeasonDraft.message)
    equalTree(before, dibs.GetDB())
  end)

  it("retains edited fields and the operation ID across Choose and Configure refreshes", function()
    local dibs, window = setup()
    fillDraft(dibs, window)
    local options = dibs.OfficerUI.BuildWizardSeasonOptions(window)
    dibs.Wizard.SetCurrentStage("choose")
    window:Refresh()
    dibs.Wizard.SetCurrentStage("configure")
    window:Refresh()
    local nextOptions = dibs.OfficerUI.BuildWizardSeasonOptions(window)
    equalTree(options, nextOptions, "options")
    assert_equal("Guild progression 2026", window.turnkeySeasonDraft.nameControl.text)
  end)

  it("keeps Custom independent of the automatic season draft form", function()
    local dibs, window = setup("custom")
    assert_nil(window.turnkeySeasonDraft)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
    assert_false(dibs.Wizard.GetNavigationAccess().foundationReady)
  end)

  it("leaves optional end dates and raid nights unset when the guild does not provide them", function()
    local dibs, window, apply = setup()
    local draft = fillDraft(dibs, window)
    draft.seasonalRosterNewEndDate, draft.seasonalRosterNewRegistrationEndDate = "", ""
    draft.scheduleRows = {}
    apply()
    assert_true(window.turnkeySetupResult.ok)
    local season = dibs.SeasonalRoster.ListSeasons()[1]
    assert_nil(season.endAt)
    assert_nil(season.registrationEndAt)
    assert_equal(0, #season.raidSchedule)
  end)

  it("does not enable a disabled seasonal module or create a season for it", function()
    local dibs, window, apply = setup()
    apply()
    assert_true(dibs.OperationalPolicy.SetModuleEnabled("seasonalRoster", false))
    dibs.Wizard.SetCurrentStage("configure")
    window:Refresh()
    local before = dibs.DeepCopy(dibs.GetDB().seasonalRoster)
    assert_false(window.turnkeySeasonDraft.enabled == true)
    assert_nil(dibs.OfficerUI.BuildWizardSeasonOptions(window))
    apply()
    equalTree(before, dibs.GetDB().seasonalRoster, "seasonalRoster")
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
    assert_false(dibs.OperationalPolicy.GetModuleStatus("seasonalRoster").enabled)
  end)

  it("preserves an existing season and hides creation while its module is disabled", function()
    local dibs, window, apply = setup()
    fillDraft(dibs, window)
    apply()
    local seasons = dibs.SeasonalRoster.GetPreservedHistory()
    local before = dibs.DeepCopy(dibs.GetDB().seasonalRoster)
    assert_true(dibs.OperationalPolicy.SetModuleEnabled("seasonalRoster", false))
    dibs.Wizard.SetCurrentStage("configure")
    window:Refresh()
    assert_false(window.turnkeySeasonDraft.enabled)
    assert_nil(dibs.OfficerUI.BuildWizardSeasonOptions(window))
    apply()
    equalTree(before, dibs.GetDB().seasonalRoster, "seasonalRoster")
    assert_equal(seasons[1].seasonId, dibs.SeasonalRoster.GetPreservedHistory()[1].seasonId)
    assert_false(dibs.OperationalPolicy.GetModuleStatus("seasonalRoster").enabled)
  end)
  it("retains typed values when optional sections fold and reopen", function()
    local dibs, view, apply = setup()
    local draft = view.turnkeySeasonDraft
    assert_nil(draft.addScheduleNight)
    fillDraft(dibs, view)
    local toggle = draft.sectionControls.rules
    toggle.callbacks.OnClick(toggle, "OnClick")
    draft.rulesControl.callbacks.OnTextChanged(draft.rulesControl, "OnTextChanged", "Règles locales conservées")
    toggle = draft.sectionControls.rules
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_nil(draft.rulesControl)
    toggle = draft.sectionControls.schedule
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_nil(draft.addScheduleNight)
    toggle = draft.sectionControls.rules
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_equal("Règles locales conservées", draft.raidRules)
    toggle = draft.sectionControls.schedule
    toggle.callbacks.OnClick(toggle, "OnClick")
    assert_equal("20:15", draft.scheduleRows[1].startTime)
    assert_equal("America/Toronto", dibs.OfficerUI.BuildSeasonFormInput(draft).raidSchedule[1].timeZone)
    assert_equal(0, #dibs.SeasonalRoster.ListSeasons())
  end)

  it("reveals an invalid optional date without losing the draft or creating a season", function()
    local dibs, view, apply = setup()
    local draft = fillDraft(dibs, view)
    draft.seasonalRosterNewEndDate = "2026-02-30"
    view:Refresh()
    assert_false(draft.sections.optionalDates == true)
    apply()
    assert_true(draft.sections.optionalDates)
    assert_equal("Guild progression 2026", draft.name)
    assert_equal("2026-02-30", draft.seasonalRosterNewEndDate)
    assert_equal(0, #dibs.SeasonalRoster.ListSeasons())
  end)

end)
