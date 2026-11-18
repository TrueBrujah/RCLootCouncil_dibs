local loader = require("helpers.load_addon")

-- RF-0019 regression suite.
--
-- RF-0019 - "PlayerUI : la surface de declaration main/alt est
-- orpheline et le badge d'integration RCLootCouncil applique la
-- precedence des operateurs"
-- (docs/code-audit/INDEX.md#rf-0019).
--
-- Cause 1 - La fenetre live `createAceWindow` (seule fenetre atteignable
-- via `Dibs.PlayerUI.CreateWindow`) ne contient aucune des surfaces de
-- declaration main/alt. La seule implementation de `Declare alt` et
-- `Request main change` se trouve dans `createLegacyAceWindow`, une
-- fonction locale qui n'est plus appelee depuis le commit 845d478
-- ("Implement B11c player UI redesign"). Un joueur ne peut donc plus
-- declarer un alt ni demander un changement de main depuis l'interface.
-- FR-012 de la spec 005 exige "The system MUST allow a player to declare
-- a main and related alts".
--
-- Cause 2 - `integrationState` (PlayerUI.lua) est ecrit
--   `availability == "operational" or status == "Ready" and { status = "Ready" }`
-- L'operateur `and` lie plus fort que `or`, donc l'expression vaut
-- `true`, ou `false`, ou la table `{ status = "Ready" }`. Le premier
-- operande est un booleen : quand `availability` vaut "operational",
-- `integrationState` vaut `true` (booleen) au lieu d'une table
-- `{ status = "Ready" }`. `GetStatusPresentation(true)` retombe alors
-- sur l'etat "Unavailable", et le badge affiche
-- "RCLootCouncil: Dibs temporarily unavailable" alors que l'integration
-- est operationnelle.

local function setup(options)
  options = options or {}
  options.withAce3 = true
  local environment, dibs = loader.load(options)
  -- Page tests use a configured guild; first-install access has its own suites.
  dibs.Seasons.GetCatalogState()
  dibs.Wizard.GetNavigationAccess = function()
    return { firstInstall = false, foundationReady = true, preservedHistory = true,
      dependencies = { seasonConfigured = true, rosterConfigured = true, ranksPublished = true, ledgerReady = true },
      routes = { disputes = true, seasonalRoster = true, vault = true } }
  end
  return environment, dibs
end

local function captureLabels(dibs)
  local captured = {}
  local originalAddLabel = dibs.AceGUI.AddLabel
  dibs.AceGUI.AddLabel = function(shell, parent, text, fullWidth)
    local label = originalAddLabel(shell, parent, text, fullWidth)
    if label then captured[#captured + 1] = { text = tostring(text or ""), widget = label } end
    return label
  end
  return captured, function() dibs.AceGUI.AddLabel = originalAddLabel end
end

local function renderIntegrationBadge(dibs, availability)
  dibs.RCLootCouncil.GetLocalStatus = function()
    return { availability = availability, status = availability, reasonCode = "RC_TEST" }
  end
  local captured, restore = captureLabels(dibs)
  local frame = dibs.PlayerUI.CreateWindow()
  frame:Show()
  frame.SelectTab("my-dibs")
  frame:Refresh()
  restore()
  for _, entry in ipairs(captured) do
    if entry.text:find("RCLootCouncil:", 1, true) ~= nil then return entry.widget end
  end
  return nil
end
describe("RF-0019 Player eligibility surface and integration badge", function()
  it("exposes the main/alt declaration controls in the reachable Player window", function()
    local _, dibs = setup({ wow = {
      playerName = "Player-Realm",
      guildLeader = false,
      guildMembers = { "Player-Realm", "Alt-Realm" },
      guildRankIndices = { [1] = 3, [2] = 3 },
    } })

    local seen, summaryCalls = {}, 0
    local originalSummary = dibs.CharacterEligibility.GetSummary
    dibs.CharacterEligibility.GetSummary = function(...)
      summaryCalls = summaryCalls + 1
      return originalSummary(...)
    end
    local originalAddButton = dibs.AceGUI.AddButton
    dibs.AceGUI.AddButton = function(shell, parent, text, callback, width)
      seen[tostring(text or "")] = callback
      return originalAddButton(shell, parent, text, callback, width)
    end
    local originalAddSection = dibs.AceGUI.AddSection
    dibs.AceGUI.AddSection = function(shell, parent, title, description)
      seen[tostring(title or "")] = true
      return originalAddSection(shell, parent, title, description)
    end

    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("my-dibs")
    frame:Refresh()

    assert_equal(0, summaryCalls, "collapsed identity must not load the full eligibility summary")
    assert_nil(seen["Declare alt"], "declaration controls should be collapsed initially")
    assert_not_nil(seen["Manage Main / alts"], "identity controls need a visible entry point")
    seen["Manage Main / alts"]()
    assert_true(summaryCalls > 0)
    assert_true(seen["Main / alt declarations"] == true,
      "the reachable Player window has no Main / alt declarations section")
    assert_not_nil(seen["Declare alt"], "the expanded window has no Declare alt control")
    assert_not_nil(seen["Request main change"], "the expanded window has no Request main change control")
    frame.eligibilityCharacter = "Alt-Realm"
    local expandedSummaryCalls = summaryCalls
    seen["Hide Main / alts"]()
    frame:Refresh()
    assert_equal(expandedSummaryCalls, summaryCalls, "closing identity must stop full projections")
    assert_equal("Alt-Realm", frame.eligibilityCharacter, "collapsing must preserve the selected character")
    assert_equal(0, #dibs.CharacterEligibility.GetRelationshipStatus("Player-Realm"),
      "opening and closing identity must not declare a relationship")
  end)

  it("keeps active probation visible without expanding identity and hides inactive probation", function()
    local _, dibs = setup({ wow = { playerName = "Player-Realm", guildLeader = false } })
    local probation = { probationEndsAt = 1700604800 }
    dibs.CharacterEligibility.GetProbation = function() return probation end
    local captured = captureLabels(dibs)
    local frame = dibs.PlayerUI.Show()
    local probationText = "Main-change probation until " .. date("%Y-%m-%d %H:%M", probation.probationEndsAt)
    local function hasLabel(text)
      for _, entry in ipairs(captured) do
        if entry.text:find(text, 1, true) then return true end
      end
      return false
    end
    assert_true(hasLabel(probationText), "active probation must stay visible while identity is collapsed")
    assert_true(not hasLabel("Protected-loot group:"), "technical identity details should be collapsed")
    probation = nil
    for index = #captured, 1, -1 do captured[index] = nil end
    frame:Refresh()
    assert_true(not hasLabel("Main-change probation"), "inactive probation should not clutter the summary")
  end)
  it("puts the balance and active requests before identity controls", function()
    local _, dibs = setup()
    local events = {}
    local originalTable, originalButton, originalHeader = dibs.AceGUI.AddTable,
      dibs.AceGUI.AddButton, dibs.AceGUI.AddHeader
    dibs.AceGUI.AddTable = function(shell, parent, columns, ...)
      if columns[1].title == "Dibs remaining" then events[#events + 1] = "balance" end
      return originalTable(shell, parent, columns, ...)
    end
    dibs.AceGUI.AddHeader = function(shell, parent, title, ...)
      if title == "Active Pre-Dibs" then events[#events + 1] = "active" end
      return originalHeader(shell, parent, title, ...)
    end
    dibs.AceGUI.AddButton = function(shell, parent, title, ...)
      if title == "Manage Main / alts" then events[#events + 1] = "identity" end
      return originalButton(shell, parent, title, ...)
    end
    dibs.PlayerUI.Show()
    assert_equal("balance", events[1])
    assert_equal("active", events[2])
    assert_equal("identity", events[3])
  end)

  it("localizes the identity disclosure and submitted feedback in French", function()
    local _, dibs = setup({ wow = { locale = "frFR", playerName = "Player-Realm", guildLeader = false,
      guildMembers = { "Player-Realm", "Alt-Realm" }, guildRankIndices = { [1] = 3, [2] = 3 } } })
    local buttons = {}
    local originalButton = dibs.AceGUI.AddButton
    dibs.AceGUI.AddButton = function(shell, parent, title, callback, ...)
      buttons[title] = callback
      return originalButton(shell, parent, title, callback, ...)
    end
    local headings = {}
    local originalHeading = dibs.AceGUI.AddHeading
    dibs.AceGUI.AddHeading = function(shell, parent, title, ...)
      headings[title] = true
      return originalHeading(shell, parent, title, ...)
    end
    local captured = captureLabels(dibs)
    local frame = dibs.PlayerUI.Show()
    assert_true(headings["Mes Dibs"] == true)
    assert_equal("Mes Dibs", dibs.PlayerUI.GetNavigation()[1].text)
    assert_not_nil(buttons["Gérer mon Main et mes alts"])
    buttons["Gérer mon Main et mes alts"]()
    assert_not_nil(buttons["Masquer Main et alts"])
    assert_not_nil(buttons["Demander un changement de Main"])
    buttons["Déclarer un alt"]()
    local feedbackShown = false
    for _, entry in ipairs(captured) do
      if entry.text == "Déclaration envoyée pour approbation par un officier." then feedbackShown = true end
    end
    assert_true(feedbackShown, "submission feedback should use the player's locale")
    assert_equal("Alt-Realm", frame.eligibilityCharacter)
    assert_equal("pending", dibs.CharacterEligibility.GetRelationshipStatus("Player-Realm")[1].status)
    frame.SelectTab("history")
    assert_equal("history", frame.playerTab, "localization must preserve the route identifiers")
    assert_true(headings["Historique"] == true)
    frame.SelectTab("diagnostics")
    assert_equal("diagnostics", frame.playerTab)
    assert_true(headings["Diagnostics"] == true)
  end)

  it("renders an operational RCLootCouncil integration as Ready", function()
    local _, dibs = setup({ wow = { playerName = "Player-Realm", guildLeader = false } })
    local badge = renderIntegrationBadge(dibs, "operational")

    assert_not_nil(badge, "no RCLootCouncil integration badge was rendered")
    assert_true(badge.text:find("Ready", 1, true) ~= nil,
      "an operational RCLootCouncil integration is not reported as Ready: " .. tostring(badge.text))
  end)

  it("renders a degraded RCLootCouncil integration as Degraded", function()
    local _, dibs = setup({ wow = { playerName = "Player-Realm", guildLeader = false } })
    local badge = renderIntegrationBadge(dibs, "degraded")

    assert_not_nil(badge, "no RCLootCouncil integration badge was rendered")
    assert_true(badge.text:find("Limited availability", 1, true) ~= nil,
      "a degraded RCLootCouncil integration is not reported as degraded: " .. tostring(badge.text))
  end)

  it("renders an absent RCLootCouncil integration as Unavailable", function()
    local _, dibs = setup({ wow = { playerName = "Player-Realm", guildLeader = false } })
    assert_equal("Unavailable", dibs.PlayerUI.GetIntegrationState({ availability = "absent" }).status)
    local badge = renderIntegrationBadge(dibs, "absent")

    assert_not_nil(badge, "no RCLootCouncil integration badge was rendered")
    assert_true(badge.text:lower():find("unavailable", 1, true) ~= nil,
      "an absent RCLootCouncil integration is not reported as unavailable: " .. tostring(badge.text))
  end)

  it("submits a pending relationship when the player declares an alt", function()
    local _, dibs = setup({ wow = {
      playerName = "Player-Realm",
      guildLeader = false,
      guildMembers = { "Player-Realm", "Alt-Realm" },
      guildRankIndices = { [1] = 3, [2] = 3 },
    } })

    local buttons = {}
    local originalAddButton = dibs.AceGUI.AddButton
    dibs.AceGUI.AddButton = function(shell, parent, text, callback, width)
      buttons[tostring(text or "")] = callback
      return originalAddButton(shell, parent, text, callback, width)
    end

    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("my-dibs")
    frame:Refresh()

    assert_not_nil(buttons["Manage Main / alts"], "no identity entry point was rendered")
    buttons["Manage Main / alts"]()
    assert_not_nil(buttons["Declare alt"], "no Declare alt control was rendered")
    buttons["Declare alt"]()

    local relationships = dibs.CharacterEligibility.GetRelationshipStatus("Player-Realm")
    assert_equal(1, #relationships, "the declaration was not recorded")
    assert_equal("pending", relationships[1].status,
      "a player declaration must stay pending until an Officer approves it")
    assert_equal("Alt-Realm", relationships[1].altCharacterName)
    assert_equal("Player-Realm", relationships[1].mainCharacterName)
  end)

  it("lists online guild characters first, caps the offline choices, and searches the full roster", function()
    local members = { "Player-Realm", "OnlineAlt-Realm" }
    local online = { ["Player-Realm"] = true, ["OnlineAlt-Realm"] = true }
    for index = 1, 900 do members[#members + 1] = string.format("OfflineAlt%03d-Realm", index) end
    for index = 1, 900 do online[string.format("OfflineAlt%03d-Realm", index)] = false end
    local _, dibs = setup({ wow = {
      playerName = "Player-Realm", guildLeader = false, guildMembers = members,
      guildOnline = online,
    } })

    local dropdowns, buttons, edits, labels = {}, {}, {}, {}
    local originalDropdown, originalButton, originalEditBox, originalLabel = dibs.AceGUI.AddDropdown,
      dibs.AceGUI.AddButton, dibs.AceGUI.AddEditBox, dibs.AceGUI.AddLabel
    dibs.AceGUI.AddDropdown = function(shell, parent, label, values, callback, ...)
      dropdowns[tostring(label)] = { values = values, callback = callback }
      return originalDropdown(shell, parent, label, values, callback, ...)
    end
    dibs.AceGUI.AddButton = function(shell, parent, label, callback, ...)
      buttons[tostring(label)] = callback
      return originalButton(shell, parent, label, callback, ...)
    end
    dibs.AceGUI.AddEditBox = function(shell, parent, label, callback, ...)
      edits[tostring(label)] = callback
      return originalEditBox(shell, parent, label, callback, ...)
    end
    dibs.AceGUI.AddLabel = function(shell, parent, text, ...)
      labels[#labels + 1] = tostring(text)
      return originalLabel(shell, parent, text, ...)
    end

    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("my-dibs")
    frame:Refresh()
    assert_not_nil(buttons["Manage Main / alts"])
    buttons["Manage Main / alts"]()
    assert_true(dropdowns["Online characters"]
      and dropdowns["Online characters"].values["OnlineAlt-Realm"] ~= nil,
      "the online character should appear in the online section")
    assert_true(dropdowns["Offline / remaining characters"] ~= nil)
    local offlineValues = dropdowns["Offline / remaining characters"].values
    local offlineCount = 0
    for _ in pairs(offlineValues) do offlineCount = offlineCount + 1 end
    assert_equal(50, offlineCount, "the initial offline dropdown must remain bounded; got " .. tostring(offlineCount))
    local currentMainVisible = false
    for _, label in ipairs(labels) do
      if label == "Current character (selected Main): Player-Realm" then currentMainVisible = true end
    end
    assert_true(currentMainVisible, "the logged-in character should remain the selected Main")

    edits["Search guild characters"]("OfflineAlt899-Realm")
    buttons.Search()
    offlineValues = dropdowns["Offline / remaining characters"].values
    assert_equal("OfflineAlt899-Realm", offlineValues["OfflineAlt899-Realm"],
      "search must find a guild member beyond the first bounded page")
    local onlineCount = 0
    for _ in pairs(dropdowns["Online characters"].values) do onlineCount = onlineCount + 1 end
    assert_equal(0, onlineCount, "the search should filter the online section too")

    dibs.AceGUI.AddDropdown, dibs.AceGUI.AddButton = originalDropdown, originalButton
    dibs.AceGUI.AddEditBox, dibs.AceGUI.AddLabel = originalEditBox, originalLabel
  end)

  it("maps the RCLootCouncil integration state without operator-precedence surprises", function()
    local _, dibs = setup({ wow = { playerName = "Player-Realm", guildLeader = false } })
    -- The original expression evaluated to the boolean `true` for an
    -- operational integration because `and` binds tighter than `or`.
    assert_equal("Ready", dibs.PlayerUI.GetIntegrationState({ availability = "operational" }).status)
    assert_equal("Ready", dibs.PlayerUI.GetIntegrationState({ status = "Ready" }).status)
    assert_equal("Degraded", dibs.PlayerUI.GetIntegrationState({ availability = "degraded" }).status)
    assert_equal("Degraded", dibs.PlayerUI.GetIntegrationState({ status = "Degraded" }).status)
    assert_equal("Unavailable", dibs.PlayerUI.GetIntegrationState({}).status)
    assert_equal("Unavailable", dibs.PlayerUI.GetIntegrationState(nil).status)
    assert_equal("Ready", dibs.PlayerUI.GetStatusPresentation(
      dibs.PlayerUI.GetIntegrationState({ availability = "operational" })).label)
  end)
end)
