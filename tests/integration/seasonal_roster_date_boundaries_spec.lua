local loader = require("helpers.load_addon")
local GM = "GameMaster-Realm"

local function load(locale, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    locale = locale or "enUS", playerName = GM, guildLeader = true,
    guildMembers = { GM, "Player-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 },
  } }))
end

local function setup()
  local dibs = load()
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "season date test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "season date test"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil, "season date test"))
  assert_not_nil(dibs.SeasonalRoster.ListSeasons())
  return dibs
end

local function input(dibs, patch, now)
  now = now or dibs.GetTimestamp()
  local value = { name = "Date boundary season", startAt = now + 1000,
    registrationStartAt = now - 100, raidRules = "Published guild raid rules" }
  for key, item in pairs(patch or {}) do value[key] = item end
  return value
end

local function digest(dibs)
  return dibs.Sync.CalculateContentHash(_G.RCLootCouncil_dibsDB)
end

local function realCalendar()
  local oldDate, oldTime = _G.date, _G.time
  register_reset(function() _G.date, _G.time = oldDate, oldTime end)
  _G.date = os.date
  _G.time = function(value)
    if type(value) == "table" then return os.time(value) end
    return oldTime()
  end
end

describe("Season registration date boundaries", function()
  it("rejects equal or later opening timestamps and excessive closing dates before any write", function()
    local dibs = setup()
    local now = dibs.GetTimestamp()
    local cases = {
      { { registrationStartAt = now + 1000 }, "REGISTRATION_MUST_PRECEDE_SEASON" },
      { { registrationStartAt = now + 1001 }, "REGISTRATION_MUST_PRECEDE_SEASON" },
      { { endAt = now + 2000, registrationEndAt = now + 2001 }, "REGISTRATION_EXCEEDS_SEASON_END" },
      { { endAt = now + 999 }, "INVALID_INPUT" },
      { { registrationEndAt = now - 101 }, "INVALID_INPUT" },
    }
    for index, case in ipairs(cases) do
      local before = digest(dibs)
      local result = dibs.SeasonalRoster.CreateSeason(input(dibs, case[1], now), "invalid-dates-" .. index, GM)
      assert_false(result.ok)
      assert_equal(case[2], result.code)
      assert_equal(before, digest(dibs), "refused creation must preserve all saved state")
    end
  end)

  it("accepts optional ends, registration ending earlier, and equal season and registration ends", function()
    local dibs = setup()
    local now = dibs.GetTimestamp()
    for index, patch in ipairs({ {}, { endAt = now + 2000 },
      { registrationEndAt = now + 500 },
      { endAt = now + 2000, registrationEndAt = now + 1999 },
      { endAt = now + 2000, registrationEndAt = now + 2000 },
      { registrationStartAt = now + 999 } }) do
      local result = dibs.SeasonalRoster.CreateSeason(input(dibs, patch, now), "valid-dates-" .. index, GM)
      assert_true(result.ok, tostring(result.code))
      local record = dibs.SeasonalRoster.GetSyncRevision(result.value, 1)
      assert_equal(patch.endAt, record.endAt)
      assert_equal(patch.registrationEndAt, record.registrationEndAt)
    end
  end)

  it("refuses invalid draft edits atomically and allows fixing them using the same unconsumed operation ID", function()
    local dibs = setup()
    local now = dibs.GetTimestamp()
    local created = dibs.SeasonalRoster.CreateSeason(input(dibs,
      { endAt = now + 3000, registrationEndAt = now + 2000 }, now), "editable-dates", GM)
    assert_true(created.ok, tostring(created.code))
    local before = digest(dibs)
    for index, case in ipairs({
      { { registrationStartAt = now + 1000 }, "REGISTRATION_MUST_PRECEDE_SEASON" },
      { { startAt = now - 101 }, "REGISTRATION_MUST_PRECEDE_SEASON" },
      { { registrationEndAt = now + 3001 }, "REGISTRATION_EXCEEDS_SEASON_END" },
      { { endAt = now + 1999 }, "REGISTRATION_EXCEEDS_SEASON_END" },
    }) do
      local result = dibs.SeasonalRoster.UpdateDraft(created.value, case[1], 1,
        "edit-dates-" .. index, "Correct date configuration", GM)
      assert_false(result.ok)
      assert_equal(case[2], result.code)
      assert_equal(before, digest(dibs))
    end
    local saved = dibs.SeasonalRoster.UpdateDraft(created.value, { registrationEndAt = now + 3000 }, 1,
      "edit-dates-3", "Correct date configuration", GM)
    assert_true(saved.ok, tostring(saved.code))
    local replay = dibs.SeasonalRoster.UpdateDraft(created.value, { registrationEndAt = now + 3000 }, 1,
      "edit-dates-3", "Correct date configuration", GM)
    assert_true(replay.ok)
    assert_true(replay.idempotent)
    assert_equal(now + 2000, dibs.SeasonalRoster.GetSyncRevision(created.value, 1).registrationEndAt)
    assert_equal(now + 3000, dibs.SeasonalRoster.GetSyncRevision(created.value, 2).registrationEndAt)
  end)

  it("rejects invalid Guided Setup dates before foundation initialization", function()
    local dibs = load()
    local now = dibs.GetTimestamp()
    for index, case in ipairs({
      { { registrationStartAt = now + 1000 }, "REGISTRATION_MUST_PRECEDE_SEASON" },
      { { endAt = now + 2000, registrationEndAt = now + 2001 }, "REGISTRATION_EXCEEDS_SEASON_END" },
    }) do
      local options = { seasonDraft = input(dibs, case[1], now), seasonOperationId = "setup-dates-" .. index }
      local before = digest(dibs)
      local preview = dibs.Wizard.PreviewProfile("progression", nil, options)
      assert_false(preview.canApply)
      assert_equal(case[2], preview.reasonCode)
      local result = dibs.Wizard.ApplyProfile("progression", nil, options)
      assert_false(result.ok)
      assert_equal(case[2], result.reasonCode)
      assert_equal(before, digest(dibs))
    end
  end)

  it("keeps a historical creation receipt idempotent without rewriting its old dates", function()
    local dibs = setup()
    local oldInput = input(dibs)
    local created = dibs.SeasonalRoster.CreateSeason(oldInput, "historical-date-receipt", GM)
    assert_true(created.ok, tostring(created.code))
    -- Reconstruct the saved record and local receipt emitted before FR-058.
    oldInput.registrationStartAt = oldInput.startAt
    local receiptInput = dibs.DeepCopy(oldInput)
    receiptInput.registrationState, receiptInput.lifecycleState = "DRAFT", "DRAFT"
    local valid, config = dibs.SeasonalRoster.ValidateSeasonInput(receiptInput)
    assert_true(valid)
    local store = dibs.GetDB().seasonalRoster
    local record = store.seasons[created.value].revisions["1"]
    record.registrationStartAt, record.contentHash = oldInput.registrationStartAt, nil
    record.contentHash = dibs.Sync.CalculateContentHash(record)
    store.operations["historical-date-receipt"].fingerprint = dibs.Sync.CalculateContentHash({
      config = config, actorKey = GM:lower(),
    })
    local before = digest(dibs)
    local replay = dibs.SeasonalRoster.CreateSeason(oldInput, "historical-date-receipt", GM)
    assert_true(replay.ok, tostring(replay.code))
    assert_true(replay.idempotent)
    assert_equal(created.value, replay.value)
    assert_equal(before, digest(dibs))
  end)

  it("closes registration by a configured season end when the registration end is omitted", function()
    local dibs = setup()
    local dates = input(dibs)
    dates.endAt = dates.startAt + 1000
    local created = dibs.SeasonalRoster.CreateSeason(dates, "season-end-boundary", GM)
    assert_true(created.ok, tostring(created.code))
    local opened = dibs.SeasonalRoster.SetRegistrationState(created.value, "OPEN", 1,
      "season-end-open", "Open registration", GM)
    assert_true(opened.ok, tostring(opened.code))
    local before = digest(dibs)
    assert_equal("OPEN", dibs.SeasonalRoster.GetSeasonLifecycle(created.value, dates.startAt - 1).registrationStatus)
    assert_equal("CLOSED", dibs.SeasonalRoster.GetSeasonLifecycle(created.value, dates.endAt).registrationStatus)
    assert_equal("CLOSED", dibs.SeasonalRoster.GetSeasonLifecycle(created.value, dates.endAt + 1).registrationStatus)
    assert_nil(dibs.SeasonalRoster.GetSyncRevision(created.value, opened.revision).registrationEndAt)
    assert_equal(before, digest(dibs))
  end)

  it("shows localized date errors in the shared form and permits different hours on the same day", function()
    for _, locale in ipairs({ "enUS", "frFR" }) do
      local dibs = load(locale)
      realCalendar()
      local state = { name = "Calendar season", raidDifficulties = { "NORMAL" },
        seasonalRosterNewStartDate = "2026-12-01", seasonalRosterNewStartHour = "20",
        seasonalRosterNewRegistrationStartDate = "2026-12-01", seasonalRosterNewRegistrationStartHour = "20" }
      local before = digest(dibs)
      local value, reason = dibs.OfficerUI.BuildSeasonFormInput(state)
      assert_nil(value)
      assert_equal(dibs.L.SEASONAL_ROSTER_CODE_REGISTRATION_MUST_PRECEDE_SEASON, reason)
      state.seasonalRosterNewRegistrationStartHour = "19"
      value = dibs.OfficerUI.BuildSeasonFormInput(state)
      assert_not_nil(value)
      assert_equal(3600, value.startAt - value.registrationStartAt)
      state.seasonalRosterNewEndDate = "2026-12-31"
      state.seasonalRosterNewRegistrationEndDate = "2027-01-01"
      value, reason = dibs.OfficerUI.BuildSeasonFormInput(state)
      assert_nil(value)
      assert_equal(dibs.L.SEASONAL_ROSTER_CODE_REGISTRATION_EXCEEDS_SEASON_END, reason)
      assert_true(state.sections.optionalDates)
      assert_equal(before, digest(dibs))
    end
  end)

  it("preserves legacy dates through authenticated revision adoption and refuses publishing the invalid draft", function()
    local source = setup()
    local initial = source.DeepCopy(_G.RCLootCouncil_dibsDB)
    local created = source.SeasonalRoster.CreateSeason(input(source), "legacy-date-season", GM)
    assert_true(created.ok, tostring(created.code))
    -- Represent an immutable revision created before FR-058, with its original hash.
    local legacy = source.SeasonalRoster.GetSyncRevision(created.value, 1)
    legacy.registrationStartAt = legacy.startAt
    legacy.endAt, legacy.registrationEndAt = legacy.startAt + 1000, legacy.startAt + 1001
    legacy.contentHash = nil
    legacy.contentHash = source.Sync.CalculateContentHash(legacy)
    local receiver = load("enUS", initial)
    local accepted, reason = receiver.SeasonalRoster.ApplySyncRevision(legacy, GM, {
      entityType = receiver.SeasonalRoster.SYNC_ENTITY, entityId = legacy.seasonId,
      revision = legacy.revision, contentHash = legacy.contentHash,
    })
    assert_true(accepted, tostring(reason))
    local adopted = receiver.SeasonalRoster.GetSyncRevision(legacy.seasonId, 1)
    assert_equal(legacy.contentHash, adopted.contentHash)
    assert_equal(legacy.registrationStartAt, adopted.registrationStartAt)
    assert_equal(legacy.registrationEndAt, adopted.registrationEndAt)
    local before = digest(receiver)
    local published = receiver.SeasonalRoster.SetRegistrationState(legacy.seasonId, "OPEN", 1,
      "invalid-legacy-date-publication", "Open registration", GM)
    assert_false(published.ok)
    assert_equal("REGISTRATION_MUST_PRECEDE_SEASON", published.code)
    assert_equal(before, digest(receiver))
  end)
end)
