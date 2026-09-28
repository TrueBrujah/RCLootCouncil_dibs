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

describe("Guild-authoritative Loot Rules UI", function()
  it("LRA09 shows dynamic draft controls and an explicit adoption action to the GM", function()
    local gm = load("GameMaster-Realm")
    local supported = gm.RCOptions.GetLootTypeOptions().types.values()
    local expectedCount = 0
    for _ in pairs(supported) do expectedCount = expectedCount + 1 end
    gm.OfficerUI.CreateWindow("lootTypes")
    assert_equal(0, gm.Seasons.GetCatalogState().catalogRevision)
    assert_not_nil(widget("Button", gm.L.LOOT_RULES_ENABLE_ALL))
    assert_not_nil(widget("Button", gm.L.LOOT_RULES_DEFAULT_ONLY))
    assert_not_nil(widget("Button", "Adopt reviewed Loot Rules"))
    local checkboxes = 0
    for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
      if candidate.kind == "CheckBox" then checkboxes = checkboxes + 1 end
    end
    assert_equal(expectedCount * 2, checkboxes)
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

  it("LRA11 renders adopted authority read-only for an Officer", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.LootRules.Adopt())
    local catalog = gm.Seasons.GetCatalogRecord(gm.Seasons.GetCatalogState().catalogRevision)
    local officer = load("Officer-Realm", saved)
    assert_true(officer.Seasons.ApplyCatalog(catalog, "GameMaster-Realm"))
    officer.OfficerUI.CreateWindow("lootTypes")
    assert_not_nil(widget("Label", officer.L.LOOT_RULES_MANAGED_READ_ONLY))
    assert_equal(nil, widget("Button", "Adopt reviewed Loot Rules"))
    assert_equal(nil, widget("Button", "Publish Loot Rules changes"))
    for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
      assert_true(candidate.kind ~= "CheckBox")
    end
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
    assert_equal(220, scroll._dibsResizeOffset)
    local scrollRegistered = false
    for _, registeredScroll in ipairs(shell._dibsResponsiveScrolls) do
      if registeredScroll == scroll then scrollRegistered = true end
    end
    assert_true(scrollRegistered)
    assert_equal("WIDE", frame.lootRulesLayoutMode)
    assert_equal(gm.AceGUI.GetLayoutMetrics().minWidth, frame.lootRulesMinimumWindowWidth)
    assert_equal(190, frame.officerNavigationWidth)
    assert_not_nil(widget("Label", gm.L.LOOT_RULES_COLUMN_GUILD_RC))
    assert_not_nil(widget("Label", gm.L.LOOT_RULES_COLUMN_DRAFT_GUIDE))
    assert_equal(frame.mountedPageHost, footer.parent)
    assert_true(scroll.parent ~= footer)

    scroll.localstatus = { scrollvalue = 615 }
    local resize = frame._scripts.OnSizeChanged
    assert_not_nil(resize)
    resize(frame, 940, 760)
    assert_equal("WIDE", frame.lootRulesLayoutMode)
    assert_true(frame.lootRulesColumnWidths[1] < 191)
    resize(frame, 700, 760)
    assert_equal("MEDIUM", frame.lootRulesLayoutMode)
    assert_equal(615, scroll.localstatus.scrollvalue)
    resize(frame, 520, 360)
    assert_equal("NARROW", frame.lootRulesLayoutMode)
    assert_equal(360, shell.layout.height)
    assert_equal(140, scroll.height)
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
    assert_true(contains(tokenCard, gm.RCOptions.GetLootTypeOptions().types.values().TOKEN))
    assert_true(contains(tokenCard, gm.L.LOOT_RULES_GROUP_GUILD))
    assert_true(contains(tokenCard, "RC: " .. gm.L.LOOT_RULES_DISABLED))
    assert_true(contains(tokenCard, gm.L.LOOT_RULES_COLUMN_GUIDE .. ": " .. gm.L.LOOT_RULES_ENABLED))
    assert_true(contains(tokenCard, gm.L.LOOT_RULES_GROUP_DRAFT))
    assert_true(contains(tokenCard, frame.rcLootTypeControls.TOKEN.label or "RC"))
    assert_true(contains(tokenCard, frame.lootTypeControls.TOKEN.label or gm.L.LOOT_RULES_COLUMN_GUIDE))
    assert_equal(1, #shell._dibsResponsiveScrolls)
  end)

  it("keeps narrow Officer cards authoritative and read-only", function()
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
    for _, candidate in ipairs(_G.__dibsAceWidgets or {}) do
      assert_true(candidate.kind ~= "CheckBox")
    end
    local tokenCard = frame.lootRulesCards.TOKEN
    assert_not_nil(tokenCard)
    assert_equal(true, tokenCard.children[1].title == officer.L.LOOT_RULES_GROUP_GUILD)
  end)
end)
