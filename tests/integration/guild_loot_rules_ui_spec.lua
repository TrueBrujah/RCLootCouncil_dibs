local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function adoptPolicy(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "Loot Rules UI test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }, "Loot Rules UI test"))
end

local function widget(kind, text)
  for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
    if candidate.kind == kind and candidate.text == text then return candidate end
  end
end

local function widgetContaining(kind, text)
  for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
    if candidate.kind == kind and (tostring(candidate.text or ""):find(text, 1, true)
      or tostring(candidate.label or ""):find(text, 1, true)) then return candidate end
  end
end

describe("Guild-authoritative Loot Rules UI", function()
  it("reuses authority, editability, and template values for one page render", function()
    local gm = load("GameMaster-Realm")
    local routeDB = gm.GetDB()
    local authorityCalls, fullAuthorityCalls, statusSnapshotCalls, editabilityCalls, templateValueCalls = 0, 0, 0, 0, 0
    local assignmentBatchCalls, perTypeAssignmentCalls = 0, 0
    local authorityDB, draftDB, statusDB, templateValuesDB, assignmentsDB
    local setShellStatus = gm.AceGUI.SetShellStatus
    gm.AceGUI.SetShellStatus = function(...)
      setShellStatus(...)
      return true, routeDB
    end
    local getAuthoritySnapshot = gm.LootRules.GetAuthoritySnapshot
    local getAuthorityRulesSnapshot = gm.LootRules.GetAuthorityRulesSnapshot
    local getDraftSnapshot = gm.LootRules.GetDraftSnapshot
    local getStatusWithAuthoritySnapshot = gm.LootRules.GetStatusWithAuthoritySnapshot
    local canEditDibsSettings = gm.RCOptions.CanEditDibsSettings
    local getButtonTemplateValues = gm.RCOptions.GetButtonTemplateValues
    local getButtonTemplateAssignments = gm.RCOptions.GetButtonTemplateAssignments
    local getButtonTemplateAssignment = gm.RCOptions.GetButtonTemplateAssignment
    gm.LootRules.GetAuthoritySnapshot = function(...)
      fullAuthorityCalls = fullAuthorityCalls + 1
      return getAuthoritySnapshot(...)
    end
    gm.LootRules.GetAuthorityRulesSnapshot = function(...)
      authorityCalls = authorityCalls + 1
      authorityDB = select(1, ...)
      return getAuthorityRulesSnapshot(...)
    end
    gm.LootRules.GetDraftSnapshot = function(...)
      draftDB = select(1, ...)
      return getDraftSnapshot(...)
    end
    gm.LootRules.GetStatusWithAuthoritySnapshot = function(...)
      statusSnapshotCalls = statusSnapshotCalls + 1
      statusDB = select(4, ...)
      local readsBeforeStatus = authorityCalls
      local result = getStatusWithAuthoritySnapshot(...)
      assert_equal(readsBeforeStatus, authorityCalls, "status re-read the authority snapshot")
      return result
    end
    gm.RCOptions.CanEditDibsSettings = function(...)
      editabilityCalls = editabilityCalls + 1
      return canEditDibsSettings(...)
    end
    gm.RCOptions.GetButtonTemplateValues = function(...)
      templateValueCalls = templateValueCalls + 1
      templateValuesDB = select(1, ...)
      return getButtonTemplateValues(...)
    end
    gm.RCOptions.GetButtonTemplateAssignments = function(...)
      assignmentBatchCalls = assignmentBatchCalls + 1
      assignmentsDB = select(2, ...)
      return getButtonTemplateAssignments(...)
    end
    gm.RCOptions.GetButtonTemplateAssignment = function(...)
      perTypeAssignmentCalls = perTypeAssignmentCalls + 1
      return getButtonTemplateAssignment(...)
    end

    gm.OfficerUI.CreateWindow("lootTypes")
    assert_equal(1, statusSnapshotCalls)
    assert_equal(1, editabilityCalls)
    assert_equal(1, templateValueCalls)
    assert_equal(1, assignmentBatchCalls)
    assert_equal(0, perTypeAssignmentCalls,
      "Loot Rules resolved the template store again for individual rows")
    assert_equal(1, authorityCalls, "the page did not resolve one compact authority snapshot")
    assert_equal(0, fullAuthorityCalls, "the page copied the full season catalog record")
    assert_equal(routeDB, authorityDB)
    assert_equal(routeDB, draftDB)
    assert_equal(routeDB, statusDB)
    assert_equal(routeDB, templateValuesDB)
    assert_equal(routeDB, assignmentsDB)
    gm.AceGUI.SetShellStatus = setShellStatus
  end)

  it("LRA09 shows semantic draft controls and an explicit adoption action to the GM", function()
    local gm = load("GameMaster-Realm")
    local supported = gm.RCOptions.GetSupportedLootRuleTypeValues()
    local expectedCount = 0
    for key in pairs(supported) do
      if key ~= "COSMETIC" then expectedCount = expectedCount + 1 end
    end
    local templateId = gm.RCOptions.CreateButtonTemplate("Raid response")
    assert_not_nil(templateId)
    gm.OfficerUI.CreateWindow("lootTypes")
    local frame = _G.DibsOfficerFrame
    assert_equal(0, gm.Seasons.GetCatalogState().catalogRevision)
    assert_not_nil(frame.rcLootTemplateControls.TOKEN)
    assert_not_nil(widget("Button", gm.L.LOOT_RULES_ENABLE_ALL))
    assert_not_nil(widget("Button", gm.L.LOOT_RULES_DEFAULT_ONLY))
    assert_not_nil(widget("Button", "Adopt reviewed Loot Rules"))
    local checkboxes = 0
    for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
      if candidate.kind == "CheckBox" then checkboxes = checkboxes + 1 end
    end
    assert_equal(expectedCount * 2, checkboxes)
    frame._scripts.OnSizeChanged(frame, 940, 760)
    assert_equal("WIDE", frame.lootRulesLayoutMode)
    assert_equal(3, frame.lootRulesColumnCount)
    local lootRulesColumnsWidth = 0
    for _, width in ipairs(frame.lootRulesColumnWidths) do lootRulesColumnsWidth = lootRulesColumnsWidth + width end
    assert_true(lootRulesColumnsWidth <= frame.lootRulesAvailableWidth - 56)
    assert_not_nil(frame.rcLootTemplateControls.TOKEN)
    assert_true(frame.rcLootTypeControls.TOKEN.width > 0)
    assert_true(frame.lootTypeControls.TOKEN.width > 0)
    assert_false(frame.rcLootTypeControls.TOKEN.fullWidth == true)
    assert_false(frame.lootTypeControls.TOKEN.fullWidth == true)
    assert_true(frame.rcLootTemplateControls.TOKEN.width > 0)
    assert_equal("", frame.rcLootTemplateControls.TOKEN.label,
      "wide rows should not repeat the template label for every loot type")
    assert_true(frame.rcLootTemplateControls.TOKEN.width < frame.lootRulesColumnWidths[2] - 12,
      "wide template dropdown should size to its choices instead of filling the whole column")
    local tokenCard = frame.lootRulesCards.TOKEN
    local tokenRuleRow = tokenCard.children[1]
    assert_equal("InlineGroup", tokenCard.kind, "the loot type should title a bordered section like Rank Rules")
    assert_equal(gm.RCOptions.GetLootTypeOptions().types.values().TOKEN, tokenCard.title)
    assert_equal("SimpleGroup", tokenRuleRow.kind)
    assert_equal(tokenRuleRow, frame.rcLootTypeControls.TOKEN.parent)
    assert_equal(tokenRuleRow, frame.rcLootTemplateControls.TOKEN.parent)
    assert_equal(tokenRuleRow, frame.lootTypeControls.TOKEN.parent)
    assert_equal(3, #tokenRuleRow.children)
    frame.rcLootTemplateControls.TOKEN.callbacks.OnValueChanged(nil, nil, templateId)
    assert_equal(templateId, gm.RCOptions.GetButtonTemplateAssignment("TOKEN"))
  end)

  it("LRA10 publishes GM draft edits only after the explicit action", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.Adopt())
    local revision = gm.Seasons.GetCatalogState().catalogRevision
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))
    gm.OfficerUI.CreateWindow("lootTypes")
    assert_not_nil(widget("Button", "Publish Loot Rules changes"))
    assert_equal(revision, gm.Seasons.GetCatalogState().catalogRevision)
    widget("Button", "Publish Loot Rules changes").callbacks.OnClick()
    assert_equal(revision + 1, gm.Seasons.GetCatalogState().catalogRevision)
  end)

  it("LRA11 lets an Officer edit a local draft without publishing guild authority", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local templateId = gm.RCOptions.CreateButtonTemplate("Shared assignment")
    assert_not_nil(templateId)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.LootRules.Adopt())
    local catalog = gm.Seasons.GetCatalogRecord(gm.Seasons.GetCatalogState().catalogRevision)
    local officer = load("Officer-Realm", saved)
    assert_true(officer.Seasons.ApplyCatalog(catalog, "GameMaster-Realm"))
    local revision = officer.Seasons.GetCatalogState().catalogRevision
    officer.OfficerUI.CreateWindow("lootTypes")
    local assignment = _G.DibsOfficerFrame.rcLootTemplateControls.TOKEN
    assert_not_nil(assignment)
    assert_false(assignment.disabled)
    assert_equal("default", officer.RCOptions.GetButtonTemplateAssignment("TOKEN"))
    assert_equal(revision, officer.Seasons.GetCatalogState().catalogRevision)
    assert_not_nil(widget("Label", officer.L.LOOT_RULES_MANAGED_READ_ONLY))
    assert_equal(nil, widget("Button", "Adopt reviewed Loot Rules"))
    assert_equal(nil, widget("Button", "Publish Loot Rules changes"))
    local checkboxes = 0
    for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
      if candidate.kind == "CheckBox" then checkboxes = checkboxes + 1 end
    end
    assert_true(checkboxes > 0)
  end)

  it("reflows Loot Rules across breakpoints without replacing navigation or footer", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "rclootcouncil", false))
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", true))
    assert_true(gm.LootRules.Adopt())
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "rclootcouncil", true))
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", false))

    gm.OfficerUI.CreateWindow("lootTypes")
    local frame = _G.DibsOfficerFrame
    local navigation = frame.aceTabs
    local scroll = frame.lootRulesScroll
    local footer = frame.lootRulesFooter
    local shell = frame.dibsAceGUIShell
    assert_equal(100, scroll._dibsResizeOffset)
    local scrollRegistered = false
    for _, registeredScroll in ipairs(shell._dibsResponsiveScrolls) do
      if registeredScroll == scroll then scrollRegistered = true end
    end
    assert_true(scrollRegistered)
    assert_equal("WIDE", frame.lootRulesLayoutMode)
    assert_equal(gm.AceGUI.GetLayoutMetrics().minWidth, frame.lootRulesMinimumWindowWidth)
    assert_equal(190, frame.officerNavigationWidth)
    assert_not_nil(widgetContaining("Label", gm.L.LOOT_RULES_COLUMN_GUILD_RC))
    assert_not_nil(widgetContaining("CheckBox", gm.L.LOOT_RULES_COLUMN_DRAFT_GUIDE))
    assert_equal(frame.mountedPageHost, footer.parent)
    assert_true(scroll.parent ~= footer)

    scroll.localstatus = { scrollvalue = 615 }
    local resize = frame._scripts.OnSizeChanged
    assert_not_nil(resize)
    resize(frame, 940, 760)
    assert_equal("WIDE", frame.lootRulesLayoutMode)
    assert_equal(5, frame.lootRulesColumnCount)
    assert_not_nil(frame.rcLootTemplateControls.TOKEN)
    local authoritativeTokenCard = frame.lootRulesCards.TOKEN
    local authoritativeTokenRow = authoritativeTokenCard.children[1]
    assert_equal("InlineGroup", authoritativeTokenCard.kind,
      "the loot type should title a bordered section like Rank Rules")
    assert_equal(gm.RCOptions.GetLootTypeOptions().types.values().TOKEN, authoritativeTokenCard.title)
    assert_equal(authoritativeTokenRow, frame.rcLootTypeControls.TOKEN.parent)
    assert_equal(authoritativeTokenRow, frame.rcLootTemplateControls.TOKEN.parent)
    assert_equal(authoritativeTokenRow, frame.lootTypeControls.TOKEN.parent)
    assert_equal(5, #authoritativeTokenRow.children)
    assert_true(frame.lootRulesColumnWidths[1] < 191)
    lootRulesColumnsWidth = 0
    for _, width in ipairs(frame.lootRulesColumnWidths) do lootRulesColumnsWidth = lootRulesColumnsWidth + width end
    assert_true(lootRulesColumnsWidth <= frame.lootRulesAvailableWidth - 56)
    resize(frame, 700, 760)
    assert_equal("MEDIUM", frame.lootRulesLayoutMode)
    assert_equal(615, scroll.localstatus.scrollvalue)
    resize(frame, 520, 360)
    assert_equal("NARROW", frame.lootRulesLayoutMode)
    assert_equal(360, shell.layout.height)
    assert_equal(260, scroll.height)
    assert_equal(615, scroll.localstatus.scrollvalue)
    assert_equal(navigation, frame.aceTabs)
    assert_equal(scroll, frame.lootRulesScroll)
    assert_equal(footer, frame.lootRulesFooter)

    local function contains(root, expected)
      if not root then return false end
      if root.text == expected or root.label == expected or root.title == expected then return true end
      for _, child in ipairs(root.children or {}) do
        if contains(child, expected) then return true end
      end
      return false
    end
    local tokenCard = frame.lootRulesCards.TOKEN
    assert_nil(frame.lootRulesCards.COSMETIC)
    assert_true(contains(tokenCard, gm.RCOptions.GetLootTypeOptions().types.values().TOKEN))
    assert_equal(gm.L.LOOT_TYPE_HELP_TOKEN, gm.RCOptions.GetLootTypeDescription("TOKEN"))
    assert_not_nil(tokenCard._dibsTooltipAttachment)
    assert_true(contains(tokenCard, gm.L.LOOT_RULES_GROUP_GUILD))
    assert_true(contains(tokenCard, "RC: " .. gm.L.LOOT_RULES_DISABLED))
    assert_true(contains(tokenCard, gm.L.LOOT_RULES_COLUMN_GUIDE .. ": " .. gm.L.LOOT_RULES_ENABLED))
    assert_true(contains(tokenCard, gm.L.LOOT_RULES_GROUP_DRAFT))
    assert_true(contains(tokenCard, frame.rcLootTypeControls.TOKEN.label or "RC"))
    assert_true(contains(tokenCard, frame.lootTypeControls.TOKEN.label or gm.L.LOOT_RULES_COLUMN_GUIDE))
    assert_equal(1, #shell._dibsResponsiveScrolls)
  end)

  it("keeps narrow guild authority visible and Officer drafts editable", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "rclootcouncil", false))
    assert_true(gm.LootRules.SetDraftValue("TOKEN", "adventureGuide", true))
    assert_true(gm.LootRules.Adopt())
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local catalog = gm.Seasons.GetCatalogRecord(gm.Seasons.GetCatalogState().catalogRevision)
    local officer = load("Officer-Realm", saved)
    assert_true(officer.Seasons.ApplyCatalog(catalog, "GameMaster-Realm"))
    officer.OfficerUI.CreateWindow("lootTypes")

    local frame = _G.DibsOfficerFrame
    local resize = frame._scripts.OnSizeChanged
    resize(frame, 520, 360)
    assert_equal("NARROW", frame.lootRulesLayoutMode)
    local checkboxes = 0
    for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
      if candidate.kind == "CheckBox" then checkboxes = checkboxes + 1 end
    end
    assert_true(checkboxes > 0)
    local tokenCard = frame.lootRulesCards.TOKEN
    assert_not_nil(tokenCard)
    assert_equal(true, tokenCard.children[1].title == officer.L.LOOT_RULES_GROUP_GUILD)
    assert_equal(true, tokenCard.children[2].title == officer.L.LOOT_RULES_GROUP_DRAFT)
  end)
end)
