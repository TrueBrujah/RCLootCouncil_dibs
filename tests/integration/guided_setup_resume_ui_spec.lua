local loader = require("helpers.load_addon")

local function load(saved, localSaved)
  local _, dibs = loader.load({ withAce3 = true, savedVariables = saved, localVariables = localSaved,
    wow = { guildLeader = true } })
  local capture = { buttons = {}, badges = {}, labels = {}, messages = {} }
  local button, badge, label = dibs.AceGUI.AddButton, dibs.Midnight.AddStatusBadge, dibs.AceGUI.AddLabel
  dibs.AceGUI.AddButton = function(shell, parent, text, callback, ...)
    capture.buttons[text] = callback
    return button(shell, parent, text, callback, ...)
  end
  dibs.Midnight.AddStatusBadge = function(shell, parent, tone, text, ...)
    capture.badges[#capture.badges + 1] = { tone = tone, text = text }
    return badge(shell, parent, tone, text, ...)
  end
  dibs.AceGUI.AddLabel = function(shell, parent, text, ...)
    capture.labels[#capture.labels + 1] = text
    return label(shell, parent, text, ...)
  end
  dibs.Message = function(message) capture.messages[#capture.messages + 1] = message end
  function capture.clear()
    capture.buttons, capture.badges, capture.labels, capture.messages = {}, {}, {}, {}
  end
  function capture.click(text)
    assert_not_nil(capture.buttons[text], "missing button: " .. tostring(text))()
  end
  function capture.hasBadge(tone, text)
    for _, item in ipairs(capture.badges) do
      if item.tone == tone and (text == nil or item.text == text) then return true end
    end
    return false
  end
  return dibs, capture
end

local function openVerify(dibs)
  dibs.Wizard.SetCurrentStage("verify")
  return dibs.OfficerUI.CreateWindow("wizard")
end

local function applyFoundation(dibs)
  assert_true(dibs.Wizard.ApplyProfile("progression").ok)
end

describe("Resumable one-action Guided Setup UI", function()
  it("shows a pending next action instead of the full red blocker wall on a fresh installation", function()
    local dibs, ui = load()
    local window = openVerify(dibs)
    assert_false(window.turnkeyShowDetails)
    assert_false(window.turnkeyNextStep.done)
    assert_equal("configure", window.turnkeyNextStep.stage)
    assert_true(ui.hasBadge("warning", dibs.L.WIZARD_PROGRESS_PENDING))
    assert_false(ui.hasBadge("danger"))
    assert_nil(ui.buttons[dibs.L.WIZARD_FIX_FIRST_BLOCKER])
    ui.click(dibs.L.WIZARD_CONTINUE_STEP)
    assert_equal("wizard", window.activeTab)
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    assert_false(dibs.Wizard.GetNavigationAccess().foundationReady)
  end)

  it("retains the authoritative blocker report behind an explicit details action", function()
    local dibs, ui = load()
    local window = openVerify(dibs)
    local original = dibs.Wizard.GetTurnkeyStatus()
    assert_equal("BLOCKED", original.overallState)
    ui.clear()
    -- Render the details button again after resetting captured callbacks.
    window:Refresh()
    ui.click(dibs.L.WIZARD_SHOW_DETAILS)
    assert_true(window.turnkeyShowDetails)
    assert_true(ui.hasBadge("danger"))
    assert_not_nil(ui.buttons[dibs.L.WIZARD_FIX_FIRST_BLOCKER])
    assert_equal(original.overallState, dibs.Wizard.GetTurnkeyStatus().overallState)
    ui.clear(); window:Refresh()
    ui.click(dibs.L.WIZARD_HIDE_DETAILS)
    assert_false(window.turnkeyShowDetails)
  end)

  it("guides a foundation-only guild to its raid-season form before rank rules", function()
    local dibs, ui = load()
    applyFoundation(dibs)
    ui.clear()
    local window = openVerify(dibs)
    assert_equal("seasonDraft", window.turnkeyNextStep.id)
    ui.click(dibs.L.WIZARD_CONTINUE_STEP)
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    assert_true(window.turnkeySeasonDraft.enabled)
    assert_not_nil(window.turnkeySeasonDraft.nameControl)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
    assert_equal("seasonDraft", dibs.Wizard.GetSetupProgress().issueId)
  end)

  it("saves typed fields across closing and recreating the actual Officer window", function()
    local dibs = load()
    dibs.Wizard.SetCurrentStage("configure")
    local window = dibs.OfficerUI.CreateWindow("wizard")
    local control = window.turnkeySeasonDraft.enabledControl
    control.callbacks.OnValueChanged(control, "OnValueChanged", true)
    local draft = window.turnkeySeasonDraft
    draft.nameControl.callbacks.OnTextChanged(draft.nameControl, "OnTextChanged", "Unfinished guild season")
    assert_nil(draft.categoryControl)
    local heroic = draft.difficultyControls[2].checkbox
    heroic.callbacks.OnValueChanged(heroic, "OnValueChanged", false)
    local scheduleToggle = draft.sectionControls.schedule
    scheduleToggle.callbacks.OnClick(scheduleToggle, "OnClick")
    draft.addScheduleNight.callbacks.OnClick(draft.addScheduleNight, "OnClick")
    local clock = window.turnkeySeasonDraft.scheduleControls[1].time
    clock.callbacks.OnTextChanged(clock, "OnTextChanged", "20:")
    local shell = window.dibsAceGUIShell
    shell.onRelease()
    local resumed = dibs.OfficerUI.CreateWindow("wizard")
    assert_equal("configure", dibs.Wizard.GetCurrentStage())
    assert_equal("Unfinished guild season", resumed.turnkeySeasonDraft.nameControl.text)
    assert_equal("MYTHIC", resumed.turnkeySeasonDraft.categories)
    assert_equal(1, #resumed.turnkeySeasonDraft.raidDifficulties)
    assert_equal("MYTHIC", resumed.turnkeySeasonDraft.raidDifficulties[1])
    assert_equal("20:", resumed.turnkeySeasonDraft.scheduleRows[1].startTime)
    assert_nil(resumed.turnkeySeasonDraft.scheduleRows[1].widget)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
  end)

  it("rehydrates form values and the chosen profile from local SavedVariables after reload", function()
    local dibs = load()
    dibs.Wizard.SetCurrentStage("configure")
    dibs.Wizard.SetSelectedProfileId("broad")
    local window = dibs.OfficerUI.CreateWindow("wizard")
    local control = window.turnkeySeasonDraft.enabledControl
    control.callbacks.OnValueChanged(control, "OnValueChanged", true)
    local draft = window.turnkeySeasonDraft
    draft.nameControl.callbacks.OnTextChanged(draft.nameControl, "OnTextChanged", "Resume after reload")
    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    local localSaved = dibs.DeepCopy(dibs.GetLocalDB())
    local restored = load(saved, localSaved)
    local resumed = restored.OfficerUI.CreateWindow("wizard")
    assert_equal("broad", restored.Wizard.GetSelectedProfileId())
    assert_equal("configure", restored.Wizard.GetCurrentStage())
    assert_equal("Resume after reload", resumed.turnkeySeasonDraft.nameControl.text)
    assert_true(resumed.turnkeySeasonDraft.enabled)
    assert_equal(0, #restored.SeasonalRoster.GetPreservedHistory())
  end)

  it("does not save the previous guild's form when the guild changes before window closure", function()
    local dibs = load()
    dibs.Wizard.SetCurrentStage("configure")
    local window = dibs.OfficerUI.CreateWindow("wizard")
    local control = window.turnkeySeasonDraft.enabledControl
    control.callbacks.OnValueChanged(control, "OnValueChanged", true)
    local name = window.turnkeySeasonDraft.nameControl
    name.callbacks.OnTextChanged(name, "OnTextChanged", "Private old guild draft")
    local originalGuild = dibs.GetGuildKey
    dibs.GetGuildKey = function() return "OTHER_REALM:OTHER_GUILD" end
    window.dibsAceGUIShell.onRelease()
    assert_nil(dibs.Wizard.GetSetupProgress().seasonDraft)
    dibs.GetGuildKey = originalGuild
    assert_equal("Private old guild draft", dibs.Wizard.GetSetupProgress().seasonDraft.name)
  end)

  it("keeps correction context across reload and returns to freshly evaluated guidance", function()
    local dibs = load()
    applyFoundation(dibs)
    local window = openVerify(dibs)
    dibs.OfficerUI.OpenWizardCorrection(window, { id = "rankRules", route = "ranks" })
    assert_equal("ranks", window.activeTab)
    local saved, localSaved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB), dibs.DeepCopy(dibs.GetLocalDB())
    local restored, ui = load(saved, localSaved)
    local resumed = restored.OfficerUI.CreateWindow("ranks")
    assert_not_nil(ui.buttons[restored.L.WIZARD_RETURN_SETUP])
    ui.click(restored.L.WIZARD_RETURN_SETUP)
    assert_equal("wizard", resumed.activeTab)
    assert_equal("verify", restored.Wizard.GetCurrentStage())
    assert_nil(restored.Wizard.GetSetupProgress().correctionRoute)
    assert_equal("seasonDraft", resumed.turnkeyNextStep.id)
  end)

  it("offers the same return path for a correction chosen from technical details", function()
    local dibs, ui = load()
    applyFoundation(dibs)
    local window = openVerify(dibs)
    ui.click(dibs.L.WIZARD_SHOW_DETAILS)
    local rankFinding
    for _, finding in ipairs(dibs.Wizard.GetTurnkeyStatus().verification) do
      if finding.id == "rankRules" then rankFinding = finding end
    end
    assert_not_nil(rankFinding)
    ui.click((dibs.L.WIZARD_OPEN or "Open") .. " " .. rankFinding.title)
    assert_equal("ranks", window.activeTab)
    assert_equal("ranks", dibs.Wizard.GetSetupProgress().correctionRoute)
    assert_not_nil(ui.buttons[dibs.L.WIZARD_RETURN_SETUP])
    ui.click(dibs.L.WIZARD_RETURN_SETUP)
    assert_equal("wizard", window.activeTab)
    assert_equal("verify", dibs.Wizard.GetCurrentStage())
  end)

  it("renders successful profile feedback inside the addon without preset chat spam", function()
    local dibs, ui = load()
    dibs.Wizard.SetCurrentStage("configure")
    local window = dibs.OfficerUI.CreateWindow("wizard")
    ui.clear(); window:Refresh()
    ui.click(dibs.L.WIZARD_APPLY)
    assert_true(window.turnkeySetupResult.ok)
    assert_equal("success", window.setupFeedback.tone)
    assert_true(ui.hasBadge("success", dibs.L.WIZARD_APPLIED_STATUS))
    assert_equal(0, #ui.messages)
    for _, action in ipairs(window.turnkeySetupResult.actions) do
      if action.outcome == "APPLIED" then assert_nil(action.reasonCode) end
    end
  end)

  it("retains a red textual error for an actual invalid season submission", function()
    local dibs, ui = load()
    dibs.Wizard.SetCurrentStage("configure")
    local window = dibs.OfficerUI.CreateWindow("wizard")
    local control = window.turnkeySeasonDraft.enabledControl
    control.callbacks.OnValueChanged(control, "OnValueChanged", true)
    ui.clear(); window:Refresh()
    ui.click(dibs.L.WIZARD_APPLY)
    assert_equal("danger", window.setupFeedback.tone)
    assert_true(type(window.setupFeedback.text) == "string" and #window.setupFeedback.text > 0)
    assert_true(ui.hasBadge("danger", window.setupFeedback.text))
    assert_equal(0, #ui.messages)
    assert_false(dibs.Wizard.GetNavigationAccess().foundationReady)
    assert_nil(window.turnkeySetupResult)
  end)

  it("shows yellow feedback within a correction route and preserves direct non-setup notices", function()
    local dibs, ui = load()
    applyFoundation(dibs)
    local window = openVerify(dibs)
    dibs.OfficerUI.OpenWizardCorrection(window, { id = "rankRules", route = "ranks" })
    ui.clear()
    window:SetStatus("Review guild allocations before publishing.", "warning")
    window:Refresh()
    assert_true(ui.hasBadge("warning", "Review guild allocations before publishing."))
    assert_equal(0, #ui.messages)
    dibs.Wizard.SaveSetupProgress({ correctionRoute = false, issueId = false })
    window:SetStatus("Direct configuration notice")
    assert_equal(1, #ui.messages)
    assert_equal("Direct configuration notice", ui.messages[1])
  end)

  it("shows a domain-rejected Loot Rules correction in red without printing it to chat", function()
    local dibs, ui = load()
    applyFoundation(dibs)
    local window = openVerify(dibs)
    dibs.LootRules.Adopt = function() return false, "SYNC_BEHIND" end
    dibs.OfficerUI.OpenWizardCorrection(window, { id = "dibsRules", route = "lootTypes" })
    ui.clear(); window:Refresh()
    ui.click(dibs.L.LOOT_RULES_ADOPT)
    assert_equal("danger", window.setupFeedback.tone)
    assert_true(ui.hasBadge("danger", window.setupFeedback.text))
    assert_equal(0, #ui.messages)
  end)

  it("shows successful real Loot Rules adoption in green within its correction page", function()
    local dibs, ui = load()
    applyFoundation(dibs)
    local window = openVerify(dibs)
    dibs.OfficerUI.OpenWizardCorrection(window, { id = "dibsRules", route = "lootTypes" })
    ui.clear(); window:Refresh()
    ui.click(dibs.L.LOOT_RULES_ADOPT)
    assert_equal("success", window.setupFeedback.tone)
    assert_true(ui.hasBadge("success", window.setupFeedback.text))
    assert_equal(0, #ui.messages)
  end)
end)
