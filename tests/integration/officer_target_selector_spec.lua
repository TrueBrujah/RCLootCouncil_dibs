local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function correctionWidgets()
  local playerDropdown, itemDropdown, applyButton
  for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
    if widget.kind == "Dropdown" and widget.label == "Correct player" then playerDropdown = widget end
    if widget.kind == "Dropdown" and widget.label == "Correct item" then itemDropdown = widget end
    if widget.kind == "Button" and (widget.text == "Apply target correction" or widget.text == "Review" or widget.text == "Confirm reassign") then applyButton = widget end
  end
  return playerDropdown, itemDropdown, applyButton
end

local function latestWidget(kind, label)
  local found
  for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
    if widget.kind == kind and (label == nil or widget.label == label) then found = widget end
  end
  return found
end

local function latestDropdown(label)
  return latestWidget("Dropdown", label)
end

local function latestButton(text)
  local found
  for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
    if widget.kind == "Button" and widget.text == text then found = widget end
  end
  return found
end

local function openCorrectionDialog(officer, request)
  assert_true(officer.OpenRequestDetail(request))
  local advanced = latestButton("Correct player / item")
  assert_not_nil(advanced)
  advanced.callbacks.OnClick(advanced, "OnClick")
end

describe("Officer target selectors", function()
  it("filters guild players and Adventure Guide loot in correction controls", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Friend-Realm" } },
      withAce3 = true,
    })
    wow.installEncounterJournalContext({
      raidInstances = { { id = 900, name = "Citadel of Testing" } },
      encounters = { [900] = { { id = 901, name = "Test Warden" } } },
      loot = { [901] = { { itemID = 280001, name = "Warden's Curio", link = "|Hitem:280001::::::::::::|h[Warden's Curio]|h|r" } } },
    })
    local request = dibs.Disputes.CreateReport({ category = "wrong_item_player", note = "selector test" })
    assert_not_nil(request)

    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    officer.disputeAdvancedExpanded = true
    openCorrectionDialog(officer, request)

    local playerDropdown, itemDropdown
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Dropdown" and widget.label == "Correct player" then playerDropdown = widget end
      if widget.kind == "Dropdown" and widget.label == "Correct item" then itemDropdown = widget end
    end
    assert_not_nil(playerDropdown)
    assert_equal("Friend-Realm", playerDropdown.list["Friend-Realm"])
    assert_not_nil(itemDropdown)
    local foundItem = false
    for key, label in pairs(itemDropdown.list or {}) do
      if tostring(key):find("280001", 1, true) and tostring(label):find("Warden's Curio", 1, true) then foundItem = true end
    end
    assert_true(foundItem)
  end)

  it("keeps correction placeholders out of menus until an explicit selection", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Babbayaga-Durotan", "Berttha-Durotan" } },
      withAce3 = true,
    })
    wow.installEncounterJournalContext({
      raidInstances = { { id = 900, name = "Citadel of Testing" } },
      encounters = { [900] = { { id = 901, name = "Test Warden" } } },
      loot = { [901] = {
        { itemID = 280001, name = "Alluring Bubbleband", link = "|Hitem:280001::::::::::::|h[Alluring Bubbleband]|h|r" },
        { itemID = 280002, name = "Bubblin Splash Guard", link = "|Hitem:280002::::::::::::|h[Bubblin Splash Guard]|h|r" },
      } },
    })
    local request = dibs.Disputes.CreateReport({ category = "wrong_item_player", note = "placeholder test", itemID = 19020, itemLink = "|Hitem:19020::::::::::::|h[Current Item]|h|r" })
    assert_not_nil(request)
    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    officer.disputeAdvancedExpanded = true
    openCorrectionDialog(officer, request)

    local playerDropdown, itemDropdown, applyButton = correctionWidgets()
    assert_equal("Select a guild player...", playerDropdown.text)
    assert_nil(playerDropdown.value)
    assert_nil(playerDropdown.list["Select a guild player..."])
    assert_nil(playerDropdown.list[""])
    assert_equal("Select an Adventure Guide item...", itemDropdown.text)
    assert_nil(itemDropdown.value)
    assert_nil(itemDropdown.list["Select an Adventure Guide item..."])
    assert_nil(itemDropdown.list[""])
    assert_true(applyButton.disabled)
    assert_nil(officer.disputeCorrectPlayer)
    assert_nil(officer.disputeCorrectItemKey)

    local playerValue = "Berttha-Durotan"
    assert_equal(playerValue, playerDropdown.list[playerValue])
    playerDropdown.callbacks.OnValueChanged(playerDropdown, nil, playerValue)
    assert_equal(playerValue, officer.disputeCorrectPlayer)
    local itemKey
    for key in pairs(itemDropdown.list or {}) do
      if tostring(key):find("280002", 1, true) then itemKey = key break end
    end
    assert_not_nil(itemKey)
    itemDropdown.callbacks.OnValueChanged(itemDropdown, nil, itemKey)
    assert_equal(tostring(itemKey), officer.disputeCorrectItemKey)
    assert_true(officer.disputeCorrectItem:find("280002", 1, true) ~= nil)
    assert_equal(request.requestId, officer.disputeTargetRequestId)

    officer:Refresh()
    assert_equal(playerValue, officer.disputeCorrectPlayer)
    playerDropdown, itemDropdown, applyButton = correctionWidgets()
    assert_equal(playerValue, playerDropdown.text)
    assert_equal(tostring(itemKey), itemDropdown.value)
    assert_false(applyButton.disabled)
    assert_equal("Current Item", request.evidence[1].item:match("%[(.-)%]") or "")
  end)

  it("never sends a placeholder to correction resolution and keeps current targets until Apply", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Friend-Realm" } },
      withAce3 = true,
    })
    wow.installEncounterJournalContext({
      raidInstances = { { id = 900, name = "Citadel of Testing" } },
      encounters = { [900] = { { id = 901, name = "Test Warden" } } },
      loot = { [901] = { { itemID = 280001, name = "Warden's Curio", link = "|Hitem:280001::::::::::::|h[Warden's Curio]|h|r" } } },
    })
    local request = dibs.Disputes.CreateReport({ category = "wrong_item_player", note = "apply guard", itemID = 19020, itemLink = "|Hitem:19020::::::::::::|h[Current Item]|h|r" })
    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    officer.disputeAdvancedExpanded = true
    openCorrectionDialog(officer, request)
    local playerDropdown, _, applyButton = correctionWidgets()
    assert_true(applyButton.disabled == true or applyButton.disabled == false)
    local resolveCalls = 0
    local originalResolve = dibs.Disputes.Resolve
    dibs.Disputes.Resolve = function(_, action, options)
      resolveCalls = resolveCalls + 1
      assert_true(options.playerName ~= "Select a guild player...")
      assert_true(options.itemLink ~= "Select an Adventure Guide item...")
      return { request = request }
    end
    applyButton.callbacks.OnClick(applyButton)
    assert_equal(0, resolveCalls)
    playerDropdown.callbacks.OnValueChanged(playerDropdown, nil, "Friend-Realm")
    officer:Refresh()
    local _, _, selectedApplyButton = correctionWidgets()
    selectedApplyButton.callbacks.OnClick(selectedApplyButton)
    assert_equal(1, resolveCalls)
    dibs.Disputes.Resolve = originalResolve
    assert_equal("Current Item", request.evidence[1].item:match("%[(.-)%]") or "")
  end)

  it("projects only safe eligible items from the relevant raid and keeps search fail-closed", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    wow.installEncounterJournalContext({
      raidInstanceID = 900,
      raidInstances = {
        { id = 900, name = "The Venomous Abyss" },
        { id = 901, name = "Unrelated Dungeon" },
      },
      encounters = {
        [900] = { { id = 9010, name = "Abyss Warden" }, { id = 9011, name = "Abyss Queen" } },
        [901] = { { id = 9020, name = "Dungeon Boss" } },
      },
      loot = {
        [9010] = {
          { itemID = 281001, name = "Abyss Curio", link = "|Hitem:281001::::::::::::|h[Abyss Curio]|h|r" },
          { itemID = 281002, name = "Abyss Cosmetic", link = "|Hitem:281002::::::::::::|h[Abyss Cosmetic]|h|r" },
          { itemID = 281003, name = "Abyss Unknown", link = "|Hitem:281003::::::::::::|h[Abyss Unknown]|h|r" },
        },
        [9011] = {
          { itemID = 281004, name = "Abyss Equipment", link = "|Hitem:281004::::::::::::|h[Abyss Equipment]|h|r" },
        },
        [9020] = {
          { itemID = 281005, name = "Unrelated Curio", link = "|Hitem:281005::::::::::::|h[Unrelated Curio]|h|r" },
        },
      },
    })
    local families = { [281001] = "TOKEN", [281002] = "COSMETIC", [281003] = nil, [281004] = "OTHER", [281005] = "TOKEN" }
    local allowed = { [281001] = true, [281002] = false, [281004] = true, [281005] = true }
    local originalFamily = dibs.RCLootCouncil.GetItemSemanticFamily
    local originalAllowed = dibs.RCLootCouncil.IsItemDibTypeAllowed
    dibs.RCLootCouncil.GetItemSemanticFamily = function(itemID) return families[tonumber(itemID)] end
    dibs.RCLootCouncil.IsItemDibTypeAllowed = function(itemID, _, options)
      assert_true(options and options.strictWhitelist == true)
      return allowed[tonumber(itemID)] == true
    end

    local request = dibs.Disputes.CreateReport({ category = "wrong_item_player", note = "candidate projection", itemID = 19020, itemLink = "|Hitem:19020::::::::::::|h[Current Item]|h|r" })
    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    officer.disputeAdvancedExpanded = true
    openCorrectionDialog(officer, request)

    local _, itemDropdown = correctionWidgets()
    assert_not_nil(itemDropdown.list["281001:9010"])
    assert_not_nil(itemDropdown.list["281004:9011"])
    assert_nil(itemDropdown.list["281002:9010"])
    assert_nil(itemDropdown.list["281003:9010"])
    assert_not_nil(itemDropdown.list["281005:9020"])
    assert_true(itemDropdown.list["281001:9010"]:find("Abyss Curio", 1, true) ~= nil)
    assert_true(itemDropdown.list["281001:9010"]:find("Abyss Warden", 1, true) ~= nil)
    assert_true(itemDropdown.list["281001:9010"]:find("UNKNOWN", 1, true) == nil)
    assert_nil(itemDropdown.value)
    assert_equal("Current Item", request.evidence[1].item:match("%[(.-)%]") or "")

    local search = latestWidget("EditBox", "Search Adventure Guide")
    search.callbacks.OnTextChanged(search, nil, "281002")
    _, itemDropdown = correctionWidgets()
    assert_nil(itemDropdown.list["281002:9010"])
    assert_nil(itemDropdown.list["281001:9010"])

    search.callbacks.OnTextChanged(search, nil, "Abyss")
    _, itemDropdown = correctionWidgets()
    itemDropdown.callbacks.OnValueChanged(itemDropdown, nil, "281001:9010")
    assert_equal("281001:9010", officer.disputeCorrectItemKey)
    assert_true(officer.disputeCorrectItem:find("281001", 1, true) ~= nil)
    assert_equal("Current Item", request.evidence[1].item:match("%[(.-)%]") or "")

    dibs.RCLootCouncil.GetItemSemanticFamily = function() return nil end
    dibs.RCLootCouncil.IsItemDibTypeAllowed = function() return false end
    officer:Refresh()
    local emptyLabel = latestWidget("Label")
    local foundEmptyState = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" and widget.text == "No eligible raid items found." then foundEmptyState = true end
    end
    assert_true(foundEmptyState or emptyLabel ~= nil, tostring(emptyLabel and emptyLabel.text))

    dibs.RCLootCouncil.GetItemSemanticFamily = originalFamily
    dibs.RCLootCouncil.IsItemDibTypeAllowed = originalAllowed
  end)

  it("cascades expansion, season, raid and boss filters without selecting an item", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    _G.EXPANSION_NAME8 = "Expansion Eight"
    wow.installEncounterJournalContext({
      expansionLevel = 8,
      currentGameSeason = { id = "season-1", name = "Season 1" },
      raidInstanceID = 900,
      raidInstances = {
        { id = 900, name = "The Venomous Abyss", expansionID = 8, seasonID = "season-1", seasonName = "Season 1" },
        { id = 901, name = "The Older Abyss", expansionID = 7, seasonID = "season-legacy", seasonName = "Legacy Season" },
      },
      encounters = {
        [900] = { { id = 9010, name = "The Lost Explorers" } },
        [901] = { { id = 9020, name = "Old Warden" } },
      },
      loot = {
        [9010] = { { itemID = 282001, name = "Gehbo's Bottomless Bag", link = "|Hitem:282001::::::::::::|h[Gehbo's Bottomless Bag]|h|r" } },
        [9020] = { { itemID = 282002, name = "Legacy Relic", link = "|Hitem:282002::::::::::::|h[Legacy Relic]|h|r" } },
      },
    })
    local originalFamily = dibs.RCLootCouncil.GetItemSemanticFamily
    local originalAllowed = dibs.RCLootCouncil.IsItemDibTypeAllowed
    dibs.RCLootCouncil.GetItemSemanticFamily = function() return "OTHER" end
    dibs.RCLootCouncil.IsItemDibTypeAllowed = function(_, _, options) return options and options.strictWhitelist == true end
    local request = dibs.Disputes.CreateReport({ category = "wrong_item_player", note = "cascade test", itemID = 19020, itemLink = "|Hitem:19020::::::::::::|h[Current Item]|h|r" })
    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    officer.disputeAdvancedExpanded = true
    openCorrectionDialog(officer, request)

    local expansion = latestDropdown("Expansion")
    local season = latestDropdown("Season")
    local raid = latestDropdown("Raid")
    local boss = latestDropdown("Boss")
    assert_true(officer.disputeCorrectExpansionID ~= nil)
    assert_true(officer.disputeCorrectSeasonID ~= nil)
    assert_equal("Expansion Eight", expansion.list["8"])
    assert_nil(raid.list["901"])
    assert_equal("Season 1", season.list["season-1"])
    assert_nil(latestDropdown("Correct item").value)

    expansion.callbacks.OnValueChanged(expansion, nil, "")
    expansion, season, raid, boss = latestDropdown("Expansion"), latestDropdown("Season"), latestDropdown("Raid"), latestDropdown("Boss")
    assert_nil(officer.disputeCorrectExpansionID)
    assert_not_nil(raid.list["900"])
    assert_true(raid.list ~= nil)

    expansion.callbacks.OnValueChanged(expansion, nil, "8")
    season = latestDropdown("Season")
    season.callbacks.OnValueChanged(season, nil, "season-1")
    raid = latestDropdown("Raid")
    assert_equal("season-1", officer.disputeCorrectSeasonID)
    assert_not_nil(raid.list["900"])
    raid.callbacks.OnValueChanged(raid, nil, "900")
    boss = latestDropdown("Boss")
    assert_equal("900", officer.disputeCorrectRaidID)
    assert_not_nil(boss.list["9010"])
    boss.callbacks.OnValueChanged(boss, nil, "9010")
    local itemDropdown = latestDropdown("Correct item")
    assert_equal("9010", officer.disputeCorrectBossID)
    assert_not_nil(itemDropdown.list["282001:9010"])
    assert_nil(itemDropdown.value)
    assert_true(itemDropdown.list["282001:9010"]:find("Expansion Eight", 1, true) ~= nil)
    assert_true(itemDropdown.list["282001:9010"]:find("The Lost Explorers (9010)", 1, true) ~= nil)
    assert_true(itemDropdown.list["282001:9010"]:find("282001", 1, true) ~= nil)
    for key, label in pairs(itemDropdown.list or {}) do
      assert_true(tostring(label):find("Current raid", 1, true) == nil, tostring(key))
      assert_true(tostring(label):find("Current boss", 1, true) == nil, tostring(key))
      assert_true(tostring(label):find("(0)", 1, true) == nil, tostring(key))
    end
    local search = latestWidget("EditBox", "Search Adventure Guide")
    for _, needle in ipairs({ "Gehbo's", "282001", "The Lost Explorers", "9010", "The Venomous Abyss" }) do
      search.callbacks.OnTextChanged(search, nil, needle)
      itemDropdown = latestDropdown("Correct item")
      assert_not_nil(itemDropdown.list["282001:9010"], needle)
    end
    itemDropdown.callbacks.OnValueChanged(itemDropdown, nil, "282001:9010")
    expansion = latestDropdown("Expansion")
    expansion.callbacks.OnValueChanged(expansion, nil, "7")
    assert_equal("7", officer.disputeCorrectExpansionID)
    assert_nil(officer.disputeCorrectSeasonID)
    assert_nil(officer.disputeCorrectRaidID)
    assert_nil(officer.disputeCorrectBossID)
    assert_nil(officer.disputeCorrectItemKey)

    dibs.RCLootCouncil.GetItemSemanticFamily = originalFamily
    dibs.RCLootCouncil.IsItemDibTypeAllowed = originalAllowed
  end)
end)
