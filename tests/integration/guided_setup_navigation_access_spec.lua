local loader = require("helpers.load_addon")

local function load()
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Member-Realm" }, guildRankIndices = { 0, 3 },
  } }))
end

local function foundation(dibs)
  assert_true(dibs.Installation.Initialize(nil).ok)
end

local function configured(dibs)
  foundation(dibs)
  local season = dibs.Seasons.GetCurrent()
  local result = dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = season.id, rankIndex = 0, rankName = "Guild Master", allocation = 10, enabled = true,
  })
  assert_true(result.ok, tostring(result.code))
  return dibs.GetDB(), season
end

describe("Guided Setup progressive navigation projection", function()
  it("exposes only Guided Setup on a real new installation, ignoring bootstrap Season 1", function()
    local dibs = load()
    assert_not_nil(dibs.Seasons.GetCurrent())
    local access = dibs.Wizard.GetNavigationAccess()
    assert_true(access.firstInstall)
    assert_false(access.foundationReady)
    local count = 0
    for route in pairs(access.routes) do count = count + 1; assert_equal("wizard", route) end
    assert_equal(1, count)
    assert_equal("GUILD_FOUNDATION_REQUIRED", access.reasonCode)
  end)

  it("opens configuration after foundation while bootstrap seasons do not unlock operational pages", function()
    local dibs = load()
    foundation(dibs)
    local access = dibs.Wizard.GetNavigationAccess()
    assert_true(access.foundationReady)
    assert_true(access.routes.seasonalRoster)
    assert_true(access.routes.ranks)
    assert_true(access.routes.modules)
    assert_true(access.routes.diagnostics)
    assert_nil(access.routes.dibsAdmin)
    assert_false(access.dependencies.seasonConfigured)
  end)

  it("opens Dibs after explicit season publication without requiring optional RC or roster modules", function()
    local dibs = load()
    configured(dibs)
    assert_true(dibs.Wizard.AdoptOperationalPolicy(nil))
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ rclootcouncil = false,
      historicalReconciliation = false, seasonalRoster = false,
      preDibs = false, announcements = false }, nil, "navigation test")
    assert_true(changed, tostring(reason))
    local access = dibs.Wizard.GetNavigationAccess()
    assert_true(access.dependencies.seasonConfigured)
    assert_true(access.dependencies.ranksPublished)
    assert_true(access.dependencies.ledgerReady)
    assert_true(access.routes.dibsAdmin)
    assert_nil(access.routes.seasonalRoster)
    assert_nil(access.routes.preDibs)
    assert_nil(access.routes.preDibRequests)
    assert_nil(access.routes.integration)
  end)

  it("keeps operational pages hidden when published ranks drift without hiding their editor", function()
    local dibs = load()
    local db, season = configured(dibs)
    db.rankRules[season.id]["0"].allocation = 12
    local access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_false(access.dependencies.ranksPublished)
    assert_nil(access.routes.dibsAdmin)
    assert_true(access.routes.ranks)
    assert_equal("RANK_RULES_PUBLICATION_REQUIRED", access.reasonCode)
  end)

  it("requires an adopted activation manifest for a prepared roster and accepts its immutable REVIEW revision", function()
    local dibs = load()
    local db, season = configured(dibs)
    local rules = dibs.DeepCopy(db.rankRules[season.id])
    db.seasonalRoster = { schema = 1, seasons = { [season.id] = {
      currentRevision = 1, revisions = { ["1"] = {
        lifecycleState = "REVIEW", rankAllocationSnapshot = { schema = 1, rules = rules,
          contentHash = dibs.Sync.CalculateContentHash(rules) },
      } },
    } } }
    local access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_false(access.dependencies.seasonConfigured)
    assert_nil(access.routes.dibsAdmin)
    db.seasonalRoster.seasons[season.id].activationAdopted = true
    access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_true(access.dependencies.seasonConfigured)
    assert_true(access.routes.dibsAdmin)
    db.seasonalRoster.seasons[season.id].revisions["1"].endAt = 1
    assert_nil(dibs.Wizard.GetNavigationAccess(nil, db).routes.dibsAdmin)
  end)

  it("opens enrollment navigation before activation without unlocking Dibs", function()
    local dibs = load()
    foundation(dibs)
    local db = dibs.GetDB()
    db.seasonalRoster = { schema = 1, seasons = { prepared = {
      currentRevision = 2, revisions = { ["2"] = { registrationState = "OPEN", lifecycleState = "REGISTRATION_OPEN" } },
    } } }
    local access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_true(access.dependencies.rosterConfigured)
    assert_false(access.dependencies.seasonConfigured)
    assert_true(access.routes.seasonalRoster)
    assert_nil(access.routes.dibsAdmin)
  end)

  it("hides disabled operational features and keeps disabled roster history accessible", function()
    local dibs = load()
    local db = configured(dibs)
    assert_true(dibs.Wizard.AdoptOperationalPolicy(nil))
    local changed, reason = dibs.OperationalPolicy.ChangeModules({ requests = false,
      greatVault = false, independentRaid = false, seasonalRoster = false,
      readiness = false, lootRules = false }, nil, "navigation feature visibility")
    assert_true(changed, tostring(reason))
    local access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_nil(access.routes.disputes)
    assert_nil(access.routes.vault)
    assert_nil(access.routes.independentRaid)
    assert_nil(access.routes.setup)
    assert_nil(access.routes.lootTypes)
    assert_true(access.routes.dibsAdmin)
    db.seasonalRoster = { seasons = { historic = { currentRevision = 1, revisions = {} } } }
    access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_true(access.routes.seasonalRoster)
    assert_nil(access.routes.disputes)
  end)

  it("preserves migration history without declaring foundation ready or deleting data", function()
    local dibs = load()
    assert_not_nil(dibs.Ledger.Grant("Member-Realm", 7, "legacy history", "test"))
    local db = dibs.GetDB()
    local before = dibs.Sync.CalculateContentHash(db)
    local access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_false(access.firstInstall)
    assert_false(access.foundationReady)
    assert_true(access.routes.history)
    assert_true(access.routes.reconciliation)
    assert_nil(access.routes.dibsAdmin)
    assert_equal(before, dibs.Sync.CalculateContentHash(db))
  end)

  it("preserves existing vault acquisitions and seasonal history before foundation", function()
    local dibs = load()
    local db = dibs.GetDB()
    db.preDibs.acquisitions.one = { itemId = 123 }
    db.seasonalRoster = { seasons = { old = { currentRevision = 1, revisions = {} } } }
    local access = dibs.Wizard.GetNavigationAccess(nil, db)
    assert_false(access.firstInstall)
    assert_true(access.routes.vault)
    assert_true(access.routes.seasonalRoster)
    assert_nil(access.routes.dibsAdmin)
    assert_equal(123, db.preDibs.acquisitions.one.itemId)
  end)

  it("does not run full readiness or per-member rank reconciliation on navigation", function()
    local dibs = load()
    configured(dibs)
    dibs.SetupAssistant.Evaluate = function() error("full readiness must not run") end
    dibs.RankRules.GetRankConfigurationSummary = function() error("member reconciliation must not run") end
    dibs.Wizard.GetStatus = function() error("full wizard must not run") end
    assert_true(dibs.Wizard.GetNavigationAccess().routes.dibsAdmin)
  end)

  it("does not hide configured Dibs when the coordinator is temporarily unavailable", function()
    local dibs = load()
    configured(dibs)
    local original = dibs.Installation.GetStatus
    dibs.Installation.GetStatus = function(...)
      local status = original(...)
      status.state, status.coordinator.ready = "COORDINATOR_UNAVAILABLE", false
      status.technical.authorityState = "COORDINATOR_UNAVAILABLE"
      return status
    end
    assert_true(dibs.Wizard.GetNavigationAccess().routes.dibsAdmin)
  end)

  it("keeps configuration accessible while ledger recovery prevents operational pages", function()
    local dibs = load()
    configured(dibs)
    local original = dibs.Installation.GetStatus
    dibs.Installation.GetStatus = function(...)
      local status = original(...)
      status.state = "RECOVERY_REQUIRED"
      return status
    end
    local access = dibs.Wizard.GetNavigationAccess()
    assert_false(access.dependencies.ledgerReady)
    assert_nil(access.routes.dibsAdmin)
    assert_true(access.routes.installation)
    assert_true(access.routes.ranks)
  end)

  it("uses an actor-scoped installation snapshot without exposing private details", function()
    local dibs = load()
    local original = dibs.Installation.GetStatus
    local observedActor, calls = nil, 0
    dibs.Installation.GetStatus = function(actor, db)
      observedActor, calls = actor, calls + 1
      return original(actor, db)
    end
    local access = dibs.Wizard.GetNavigationAccess("Member-Realm", dibs.GetDB())
    assert_equal("Member-Realm", observedActor)
    assert_equal(1, calls)
    assert_true(access.firstInstall)
    assert_nil(access.technical)
    assert_nil(access.installation)
  end)
end)
