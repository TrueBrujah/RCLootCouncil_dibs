local loader = require("helpers.load_addon")

local function load(player, leader)
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = player or "Tester-Realm", guildLeader = leader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Member-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  } }))
end

local function options(dibs, patch)
  local draft = { name = "Guild progression", startAt = dibs.GetTimestamp() + 86400,
    registrationStartAt = dibs.GetTimestamp(), raidSchedule = {
      { weekday = 3, startTime = "19:30", durationMinutes = 150, timeZone = "America/Toronto" },
    }, categoryCatalog = { { id = "PROGRESSION", name = "Our progression team", active = true } } }
  for key, value in pairs(patch or {}) do draft[key] = value end
  return { seasonDraft = draft, seasonOperationId = "guided-season-draft-1" }
end

local function action(result, id)
  for _, row in ipairs(result.actions or {}) do if row.id == id then return row end end
end

local function configure(dibs)
  assert_true(dibs.Wizard.ApplyProfile("progression").ok)
  assert_true(dibs.Wizard.GetNavigationAccess().foundationReady)
end

local function digest(dibs, value)
  return dibs.Sync.CalculateContentHash(value or dibs.GetDB())
end

describe("Guided Setup optional seasonal draft", function()
  it("leaves the existing two-argument preview and application unchanged", function()
    local dibs = load()
    assert_equal(3, #dibs.Wizard.PreviewProfile("progression").actions)
    assert_true(dibs.Wizard.ApplyProfile("progression").ok)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
  end)

  it("previews without mutation and creates a real draft after fresh GM foundation setup", function()
    local dibs = load()
    local input = options(dibs)
    local before = digest(dibs)
    local preview = dibs.Wizard.PreviewProfile("progression", nil, input)
    assert_true(preview.canApply)
    assert_equal("APPLY", action(preview, "seasonDraft").disposition)
    assert_equal(before, digest(dibs))
    local applied = dibs.Wizard.ApplyProfile("progression", nil, input)
    assert_true(applied.ok, tostring(applied.reasonCode))
    local created = action(applied, "seasonDraft")
    assert_equal("APPLIED", created.outcome)
    assert_equal(1, created.revision)
    local record = dibs.GetDB().seasonalRoster.seasons[created.value].revisions["1"]
    assert_equal("DRAFT", record.lifecycleState)
    assert_equal("DRAFT", record.registrationState)
    assert_equal("Our progression team", record.categoryCatalog[1].name)
    assert_equal(3, record.raidSchedule[1].weekday)
    assert_equal(150, record.raidSchedule[1].durationMinutes)
    assert_equal("America/Toronto", record.raidSchedule[1].timeZone)
    assert_true(dibs.GetCurrentSeasonId() ~= created.value)
    assert_nil(dibs.GetDB().seasonalRoster.seasons[created.value].activationAdopted)
    assert_nil(input.seasonDraft.lifecycleState)
  end)

  it("does not change any ledger or active season while creating a draft", function()
    local dibs = load()
    configure(dibs)
    local db = dibs.GetDB()
    local ledgerHash, current = digest(dibs, db.ledgers), db.currentSeasonId
    assert_true(dibs.Wizard.ApplyProfile("broad", nil, options(dibs)).ok)
    assert_equal(ledgerHash, digest(dibs, db.ledgers))
    assert_equal(current, db.currentSeasonId)
  end)

  it("rejects malformed options and operation identifiers before any mutation", function()
    local dibs = load()
    for _, input in ipairs({ false, { seasonDraft = false },
      { seasonDraft = options(dibs).seasonDraft, seasonOperationId = "unsafe id" },
      { seasonDraft = options(dibs).seasonDraft, seasonOperationId = string.rep("x", 129) } }) do
      local before = digest(dibs)
      local result = dibs.Wizard.ApplyProfile("progression", nil, input)
      assert_false(result.ok)
      assert_equal("INVALID_INPUT", result.reasonCode)
      assert_equal(before, digest(dibs))
    end
  end)

  it("rejects missing required dates before foundation initialization", function()
    local dibs = load()
    local input = options(dibs)
    input.seasonDraft.registrationStartAt = nil
    local before = digest(dibs)
    local result = dibs.Wizard.ApplyProfile("progression", nil, input)
    assert_false(result.ok)
    assert_equal("SEASON_DATES_REQUIRED", result.reasonCode)
    assert_equal(before, digest(dibs))
  end)

  it("rejects invalid schedules and non-draft states before foundation initialization", function()
    local dibs = load()
    for _, patch in ipairs({ { raidSchedule = { { weekday = 8, startTime = "19:00" } } },
      { registrationState = "OPEN" }, { lifecycleState = "ACTIVE" }, { name = "  " } }) do
      local before = digest(dibs)
      local preview = dibs.Wizard.PreviewProfile("progression", nil, options(dibs, patch))
      assert_false(preview.canApply)
      assert_false(dibs.Wizard.ApplyProfile("progression", nil, options(dibs, patch)).ok)
      assert_equal(before, digest(dibs))
    end
  end)

  it("keeps custom profiles completely manual even with invalid options", function()
    local dibs = load()
    local before = digest(dibs)
    assert_true(dibs.Wizard.ApplyProfile("custom", nil, false).ok)
    assert_equal(before, digest(dibs))
    assert_nil(action(dibs.Wizard.PreviewProfile("custom", nil, options(dibs)), "seasonDraft"))
  end)

  it("fails explicitly when the season service is absent without initializing", function()
    local dibs = load()
    local input = options(dibs)
    dibs.SeasonalRoster = nil
    local before = digest(dibs)
    local result = dibs.Wizard.ApplyProfile("progression", nil, input)
    assert_false(result.ok)
    assert_equal("SEASON_SERVICE_UNAVAILABLE", result.reasonCode)
    assert_equal(before, digest(dibs))
  end)

  it("defers a disabled module without enabling it or creating a season", function()
    local dibs = load()
    configure(dibs)
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = false }, nil, "test disabled"))
    local before = digest(dibs, dibs.GetDB().seasonalRoster)
    local result = dibs.Wizard.ApplyProfile("progression", nil, options(dibs))
    assert_true(result.ok)
    assert_equal("DEFERRED", action(result, "seasonDraft").outcome)
    assert_equal("MODULE_DISABLED", action(result, "seasonDraft").reasonCode)
    assert_false(dibs.FeatureRegistry.GetEffectiveState("seasonalRoster").enabled)
    assert_equal(before, digest(dibs, dibs.GetDB().seasonalRoster))
  end)

  it("preserves existing seasons unchanged even while their module is disabled", function()
    local dibs = load()
    configure(dibs)
    local first = action(dibs.Wizard.ApplyProfile("progression", nil, options(dibs)), "seasonDraft")
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = false }, nil, "preserve disabled"))
    local before = digest(dibs, dibs.GetDB().seasonalRoster)
    local result = dibs.Wizard.ApplyProfile("progression", nil, options(dibs, { name = "Do not replace" }))
    assert_true(result.ok)
    assert_equal("ALREADY_READY", action(result, "seasonDraft").outcome)
    assert_equal(first.value, action(result, "seasonDraft").value)
    assert_equal(before, digest(dibs, dibs.GetDB().seasonalRoster))
  end)

  it("is idempotent across retries and does not add revisions or audit events", function()
    local dibs = load()
    local input = options(dibs)
    local first = dibs.Wizard.ApplyProfile("progression", nil, input)
    assert_true(first.ok)
    local before = digest(dibs, dibs.GetDB().seasonalRoster)
    local retried = dibs.Wizard.ApplyProfile("progression", nil, input)
    assert_true(retried.ok)
    assert_equal("ALREADY_READY", action(retried, "seasonDraft").outcome)
    assert_equal(action(first, "seasonDraft").value, action(retried, "seasonDraft").value)
    assert_equal(before, digest(dibs, dibs.GetDB().seasonalRoster))
  end)

  it("does not treat a successful Officer proposal as adopted foundation", function()
    local dibs = load("Officer-Realm", false)
    local result = dibs.Wizard.ApplyProfile("progression", nil, options(dibs))
    assert_equal("APPLIED", action(result, "initialize").outcome)
    assert_equal("DEFERRED", action(result, "seasonDraft").outcome)
    assert_equal("GUILD_FOUNDATION_REQUIRED", action(result, "seasonDraft").reasonCode)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
    assert_false(dibs.Wizard.GetNavigationAccess().foundationReady)
  end)

  it("reports source creation failures and allows a later retry", function()
    local dibs = load()
    configure(dibs)
    local create = dibs.SeasonalRoster.CreateSeason
    dibs.SeasonalRoster.CreateSeason = function() return { ok = false, code = "PERSISTENCE_READ_ONLY" } end
    local result = dibs.Wizard.ApplyProfile("progression", nil, options(dibs))
    assert_false(result.ok)
    assert_equal("PERSISTENCE_READ_ONLY", action(result, "seasonDraft").reasonCode)
    assert_equal("seasonalRoster", action(result, "seasonDraft").route)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
    dibs.SeasonalRoster.CreateSeason = create
    assert_true(dibs.Wizard.ApplyProfile("progression", nil, options(dibs)).ok)
  end)

  it("rechecks seasons created concurrently by earlier setup actions", function()
    local dibs = load()
    configure(dibs)
    local apply = dibs.RCOptions.ApplyInstallationPreset
    dibs.RCOptions.ApplyInstallationPreset = function(...)
      assert_true(dibs.SeasonalRoster.CreateSeason(options(dibs, { name = "Concurrent season" }).seasonDraft,
        "concurrent-season").ok)
      return apply(...)
    end
    local result = dibs.Wizard.ApplyProfile("broad", nil, options(dibs))
    assert_true(result.ok)
    assert_equal("ALREADY_READY", action(result, "seasonDraft").outcome)
    local history = dibs.SeasonalRoster.GetPreservedHistory()
    assert_equal(1, #history)
    assert_equal("Concurrent season", history[1].name)
  end)

  it("propagates unavailable preserved history before applying other settings", function()
    local dibs = load()
    dibs.SeasonalRoster.GetPreservedHistory = function() return nil, "GUILD_UNAVAILABLE" end
    local before = digest(dibs)
    local result = dibs.Wizard.ApplyProfile("progression", nil, options(dibs))
    assert_false(result.ok)
    assert_equal("GUILD_UNAVAILABLE", result.reasonCode)
    assert_equal(before, digest(dibs))
  end)

  it("rechecks a module disabled during setup instead of bypassing its gate", function()
    local dibs = load()
    configure(dibs)
    local apply = dibs.RCOptions.ApplyInstallationPreset
    dibs.RCOptions.ApplyInstallationPreset = function(...)
      assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = false }, nil, "concurrent disable"))
      return apply(...)
    end
    local result = dibs.Wizard.ApplyProfile("broad", nil, options(dibs))
    assert_true(result.ok)
    assert_equal("DEFERRED", action(result, "seasonDraft").outcome)
    assert_equal("MODULE_DISABLED", action(result, "seasonDraft").reasonCode)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
  end)

  it("does not create a season after another applicable setup action fails", function()
    local dibs = load()
    configure(dibs)
    dibs.RCOptions.ApplyInstallationPreset = function() return false, "TEST_PRESET_FAILURE" end
    local result = dibs.Wizard.ApplyProfile("broad", nil, options(dibs))
    assert_false(result.ok)
    assert_equal("DEFERRED", action(result, "seasonDraft").outcome)
    assert_equal("SETUP_FOUNDATION_FAILED", action(result, "seasonDraft").reasonCode)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
  end)

  it("delegates member permissions to the real season service", function()
    local dibs = load()
    configure(dibs)
    local result = dibs.Wizard.ApplyProfile("progression", "Member-Realm", options(dibs))
    assert_false(result.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", action(result, "seasonDraft").reasonCode)
    assert_equal(0, #dibs.SeasonalRoster.GetPreservedHistory())
  end)
end)
