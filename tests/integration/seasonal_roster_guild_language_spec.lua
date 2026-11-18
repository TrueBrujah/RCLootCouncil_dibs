local loader = require("helpers.load_addon")

local function render(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, wow = {
    locale = options.locale or "enUS", guildLeader = true,
    guildMembers = { "Tester-Realm", "Player-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 },
  } })
  local captured = { labels = {}, dropdowns = {}, rows = {}, buttons = {} }
  dibs.Wizard.GetNavigationAccess = function()
    return options.access or { foundationReady = true, firstInstall = false,
      dependencies = { seasonConfigured = true, rosterConfigured = true, ranksPublished = true, ledgerReady = true },
      routes = { seasonalRoster = true, disputes = true, vault = true } }
  end
  for _, method in ipairs({ "AddLabel", "AddDropdown", "AddTable", "AddButton" }) do
    local original = dibs.AceGUI[method]
    dibs.AceGUI[method] = function(shell, parent, label, value, callback, ...)
      if method == "AddLabel" then captured.labels[#captured.labels + 1] = label
      elseif method == "AddDropdown" then captured.dropdowns[label] = { values = value, select = callback }
      elseif method == "AddTable" then
        if label[1].title == dibs.L.SEASONAL_ROSTER_CHARACTER then captured.rows = value end
      elseif method == "AddButton" then captured.buttons[label] = value end
      return original(shell, parent, label, value, callback, ...)
    end
  end
  local catalog = options.catalog or {
    { id = "RAIDER", name = "Raid Team", description = "Our guild raids on Tuesday.", active = true },
    { id = "CORE_RAIDER", name = "Vanguard", description = "Our guild progression group.", active = true },
  }
  dibs.SeasonalRoster.ListSeasons = function()
    return { { seasonId = "guild-season", name = "Guild season", revision = 2,
      categories = options.categories or { "RAIDER", "CORE_RAIDER" }, categoryCatalog = catalog,
      raidDifficulties = options.raidDifficulties or {},
      lifecycle = { registrationStatus = options.registrationStatus or "OPEN" } } }
  end
  dibs.SeasonalRoster.GetOwnEnrollments = function()
    return options.enrollment and { options.enrollment } or {}
  end
  dibs.SeasonalRoster.GetPublicRosterPage = function()
    return { rows = { { character = "Player-Realm", requestedPath = "CORE_PROGRESSION",
      categoryId = "CORE_RAIDER", categoryName = "Approved Vanguard", primarySpec = "balance", roles = {} } },
      page = 1, pages = 1, total = 1 }
  end
  dibs.PlayerUI.RenderSeasonIdentity = function() end
  local window = dibs.PlayerUI.CreateWindow()
  window.SelectTab("seasonal-roster")
  return dibs, captured, window
end

local function hasText(labels, expected)
  for _, text in ipairs(labels) do
    if type(text) == "string" and text:find(expected, 1, true) then return true end
  end
  return false
end

describe("Seasonal roster guild-specific language", function()
  it("uses published guild names and descriptions without changing path identifiers", function()
    local dibs, captured = render()
    assert_nil(captured.dropdowns[dibs.L.SEASONAL_ROSTER_CATEGORY])
    local paths = captured.dropdowns[dibs.L.SEASONAL_ROSTER_REQUESTED_PATH]
    assert_equal("Raid Team", paths.values.STANDARD)
    assert_equal("Vanguard", paths.values.CORE_PROGRESSION)
    assert_true(hasText(captured.labels, "Our guild raids on Tuesday."))
    assert_equal("Vanguard", captured.dropdowns[dibs.L.SEASONAL_ROSTER_CATEGORY_FILTER or "Category filter"].values.CORE_RAIDER)
    assert_equal("Vanguard", captured.rows[1][2])
    assert_equal("Approved Vanguard", captured.rows[1][3])
  end)

  it("does not impose an Officer/Core rule or a fixed raid weekday in either locale", function()
    for _, locale in ipairs({ "enUS", "frFR" }) do
      local dibs, captured = render({ locale = locale, catalog = {}, categories = {} })
      assert_false(hasText(captured.labels, dibs.L.SEASONAL_ROSTER_OFFICER_NOT_CORE))
      local core = captured.dropdowns[dibs.L.SEASONAL_ROSTER_REQUESTED_PATH].values.CORE_PROGRESSION
      assert_nil(core:lower():find("thursday", 1, true))
      assert_nil(core:lower():find("jeudi", 1, true))
      assert_true(hasText(captured.labels, dibs.L.SEASONAL_ROSTER_PATH_HELP))
    end
  end)

  it("shows an approved enrollment as approved instead of pending review", function()
    local dibs, captured = render({ enrollment = { enrollmentId = "approved", character = "Tester-Realm",
      revision = 4, status = "ACTIVE", categoryId = "CORE_RAIDER", requestedPath = "CORE_PROGRESSION",
      primarySpec = "balance", roles = { "DAMAGER" } } })
    assert_true(hasText(captured.labels, "Vanguard (" .. dibs.L.SEASONAL_ROSTER_APPROVED .. ")"))
    assert_false(hasText(captured.labels, dibs.L.SEASONAL_ROSTER_PENDING_REVIEW))
    assert_true(hasText(captured.labels, "Our guild progression group."))
  end)

  it("offers only unified raid categories and submits the player's explicit selection", function()
    for _, locale in ipairs({ "enUS", "frFR" }) do
      local dibs, captured, window = render({ locale = locale, categories = { "HEROIC", "MYTHIC" },
        raidDifficulties = { "HEROIC", "MYTHIC" }, catalog = {
          { id = "HEROIC", name = "Heroic", active = true },
          { id = "MYTHIC", name = "Mythic", active = true },
          { id = "RAIDER", name = "Retained historical team", active = false },
        } })
      local choices = captured.dropdowns[dibs.L.SEASONAL_ROSTER_CATEGORY]
      assert_equal("Heroic", choices.values.HEROIC)
      assert_equal("Mythic", choices.values.MYTHIC)
      assert_nil(choices.values.NORMAL)
      assert_nil(choices.values.RAIDER)
      local submitted
      dibs.SeasonalRoster.UpsertOwnEnrollment = function(seasonId, input, revision)
        submitted = input
        assert_equal("guild-season", seasonId); assert_equal(0, revision)
        return { ok = false, code = "STALE_REVISION" }
      end
      choices.select("MYTHIC")
      window.seasonalRosterPrimarySpec = "balance"
      captured.buttons[dibs.L.SEASONAL_ROSTER_SAVE_ENROLLMENT]()
      assert_equal("MYTHIC", submitted.categoryId)
      assert_equal("STANDARD", submitted.requestedPath)
      assert_nil(submitted.status)
      assert_nil(submitted.approvedBy)
    end
  end)

  it("does not expose a raid-category change for closed or incompatible published catalogs", function()
    for _, options in ipairs({
      { registrationStatus = "CLOSED", categories = { "NORMAL", "MYTHIC" },
        raidDifficulties = { "NORMAL", "MYTHIC" } },
      { categories = { "NORMAL", "MYTHIC" }, raidDifficulties = { "MYTHIC" } },
    }) do
      local dibs, captured = render(options)
      assert_nil(captured.dropdowns[dibs.L.SEASONAL_ROSTER_CATEGORY])
    end
  end)

  it("retains the reviewed submission contract when a guild uses custom names", function()
    local dibs, captured, window = render()
    local submitted
    dibs.SeasonalRoster.UpsertOwnEnrollment = function(seasonId, input, revision)
      submitted = { seasonId = seasonId, input = input, revision = revision }
      return { ok = false, code = "STALE_REVISION" }
    end
    captured.dropdowns[dibs.L.SEASONAL_ROSTER_REQUESTED_PATH].select("CORE_PROGRESSION")
    window.seasonalRosterPrimarySpec = "balance"
    captured.buttons[dibs.L.SEASONAL_ROSTER_SAVE_ENROLLMENT]()
    assert_equal("guild-season", submitted.seasonId)
    assert_equal("CORE_PROGRESSION", submitted.input.requestedPath)
    assert_equal("RAIDER", submitted.input.categoryId)
    assert_equal(0, submitted.revision)
    assert_nil(submitted.input.status)
    assert_nil(submitted.input.approvedBy)
  end)
end)

describe("Player progressive setup navigation", function()
  it("shows only safe setup status on fresh installation and refuses direct page access", function()
    local dibs, captured, window = render({ access = {
      firstInstall = true, foundationReady = false, dependencies = {}, routes = {}, preservedHistory = false } })
    local navigation = dibs.PlayerUI.GetNavigation()
    assert_equal(1, #navigation)
    assert_equal("setup-status", navigation[1].value)
    assert_equal("setup-status", window.playerTab)
    assert_true(hasText(captured.labels, dibs.L.PLAYER_SETUP_WAITING or "Your guild setup is not complete yet."))
    assert_nil(captured.buttons[dibs.L.SEASONAL_ROSTER_SAVE_ENROLLMENT])
    window.SelectTab("my-dibs")
    assert_equal("setup-status", window.playerTab)
    window.playerTab = "requests"
    window:Refresh()
    assert_equal("setup-status", window.playerTab)
  end)

  it("reveals only configured pages and updates an already open navigation tree", function()
    local access = { firstInstall = false, foundationReady = true, dependencies = {}, routes = {} }
    local dibs, _, window = render({ access = access })
    local function visible()
      local result = {}
      for _, entry in ipairs(dibs.PlayerUI.GetNavigation()) do result[entry.value] = true end
      return result
    end
    assert_nil(visible()["my-dibs"])
    assert_nil(visible()["requests"])
    assert_nil(visible()["seasonal-roster"])
    access.dependencies = { seasonConfigured = true, rosterConfigured = true, ranksPublished = true, ledgerReady = true }
    access.routes = { seasonalRoster = true, disputes = true }
    window:Refresh()
    assert_true(visible()["my-dibs"])
    assert_true(visible()["requests"])
    assert_true(visible()["seasonal-roster"])
    window.SelectTab("seasonal-roster")
    assert_equal("seasonal-roster", window.playerTab)
    access.routes.seasonalRoster = false
    window:Refresh()
    assert_equal("my-dibs", window.playerTab)
  end)

  it("preserves safe history and preferences while an existing guild setup needs repair", function()
    local dibs = render({ access = { firstInstall = false, foundationReady = false,
      preservedHistory = true, dependencies = {}, routes = { vault = true } } })
    local visible = {}
    for _, entry in ipairs(dibs.PlayerUI.GetNavigation()) do visible[entry.value] = true end
    assert_true(visible["setup-status"])
    assert_true(visible.history)
    assert_true(visible.vault)
    assert_true(visible.preferences)
    assert_nil(visible["my-dibs"])
    assert_nil(visible.requests)
  end)

  it("opens published roster registrations before any accounting season is activated", function()
    local dibs, captured, window = render({ access = { firstInstall = false, foundationReady = true,
      dependencies = { rosterConfigured = true, seasonConfigured = false, ranksPublished = false, ledgerReady = true },
      routes = { seasonalRoster = true } } })
    assert_equal("seasonal-roster", window.playerTab)
    assert_not_nil(captured.buttons[dibs.L.SEASONAL_ROSTER_SAVE_ENROLLMENT])
    for _, entry in ipairs(dibs.PlayerUI.GetNavigation()) do assert_true(entry.value ~= "my-dibs") end
  end)
end)
