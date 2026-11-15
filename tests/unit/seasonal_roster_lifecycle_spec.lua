local loader = require("helpers.load_addon")

describe("seasonal raid lifecycle foundations", function()
  it("validates legal lifecycle transitions and their date gates", function()
    local _, dibs = loader.load({ withAce3 = true })
    local validate = dibs.SeasonalRoster.ValidateLifecycleTransition
    local now = 1800000000
    local future = { startAt = now + 1000, registrationStartAt = now - 1,
      registrationEndAt = now + 500, endAt = now + 2000 }

    assert_true(validate("DRAFT", "REGISTRATION_OPEN", future, now))
    local allowed, reason = validate("DRAFT", "ACTIVE", future, now)
    assert_false(allowed)
    assert_equal("ACTIVATION_NOT_IMPLEMENTED", reason)
    allowed, reason = validate("DRAFT", "REGISTRATION_OPEN", { startAt = future.startAt }, now)
    assert_false(allowed)
    assert_equal("SEASON_DATES_REQUIRED", reason)
    allowed, reason = validate("COMPLETED", "ARCHIVED", { endAt = now - 10 }, now)
    assert_false(allowed)
    assert_equal("ARCHIVE_GRACE_PERIOD", reason)
    assert_true(validate("COMPLETED", "ARCHIVED", { endAt = now - 7 * 24 * 60 * 60 }, now))
  end)

  it("closes registration at the exact configured end timestamp", function()
    local _, dibs = loader.load({ withAce3 = true })
    local now = 1800000000
    local opened, reason = dibs.SeasonalRoster.ValidateLifecycleTransition("DRAFT", "REGISTRATION_OPEN", {
      startAt = now + 1000, registrationStartAt = now - 100, registrationEndAt = now,
    }, now)
    assert_false(opened)
    assert_equal("REGISTRATION_CLOSED", reason)
  end)

  it("does not archive when signup closes and archives an ended active season after seven days", function()
    local H = require("helpers.season_activation")
    local dibs, id = H.make(false, true)
    local season = dibs.GetDB().seasonalRoster.seasons[id]
    local record = season.revisions[tostring(season.currentRevision)]
    local registrationEnded = dibs.SeasonalRoster.GetSeasonLifecycle(id, record.startAt)
    assert_equal("CLOSED", registrationEnded.registrationStatus)
    assert_equal("REVIEW", registrationEnded.seasonStatus)
    H.activate(dibs, id)
    local ended = dibs.SeasonalRoster.GetSeasonLifecycle(id, record.endAt)
    assert_equal("COMPLETED", ended.seasonStatus)
    local archived = dibs.SeasonalRoster.GetSeasonLifecycle(id, record.endAt + 7 * 24 * 60 * 60)
    assert_equal("ARCHIVED", archived.seasonStatus)
    assert_true(archived.readOnly)
  end)

  it("completes an active season through an audited idempotent revision without changing the active ledger season", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      playerName = "GameMaster-Realm", guildMembers = { "GameMaster-Realm" }, guildRankIndices = { [1] = 0 } } })
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "lifecycle completion test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
      { allowPublicPreDibs = true, preDibModes = {} }, "lifecycle completion test"))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
      "enable seasonal roster for this test"))
    local now = dibs.GetTimestamp()
    local created = dibs.SeasonalRoster.CreateSeason({ name = "Active season", startAt = now - 100,
      registrationStartAt = now - 200 }, "completion-season-create", "GameMaster-Realm")
    assert_true(created.ok, tostring(created.code))
    local season = dibs.GetDB().seasonalRoster.seasons[created.value]
    -- Activation is implemented by a later feature task. Seed the lifecycle
    -- precondition here to test the completion operation independently.
    season.revisions["1"].lifecycleState = "ACTIVE"
    season.revisions["1"].registrationState = "CLOSED"
    local currentSeasonId = dibs.GetCurrentSeasonId()
    local ledgerBefore = dibs.Sync.CalculateContentHash(dibs.GetDB().ledgers)

    local completed = dibs.SeasonalRoster.CompleteSeason(created.value, 1,
      "complete-active-season", "Season ended by the GM", "GameMaster-Realm")
    assert_true(completed.ok, tostring(completed.code))
    assert_equal(2, completed.revision)
    local completedRecord = dibs.GetDB().seasonalRoster.seasons[created.value].revisions["2"]
    assert_equal("COMPLETED", completedRecord.lifecycleState)
    assert_equal("SEASON_COMPLETED", completedRecord.action)
    assert_equal("gamemaster-realm", completedRecord.updatedBy)
    assert_equal(currentSeasonId, dibs.GetCurrentSeasonId())
    assert_equal(ledgerBefore, dibs.Sync.CalculateContentHash(dibs.GetDB().ledgers))

    local replay = dibs.SeasonalRoster.CompleteSeason(created.value, 1,
      "complete-active-season", "Season ended by the GM", "GameMaster-Realm")
    assert_true(replay.ok)
    assert_true(replay.idempotent)
    assert_equal(2, replay.revision)
  end)

  it("creates a canonical Dibs draft without activating it", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "Officer-Realm", guildLeader = false,
      guildMembers = { "GameMaster-Realm", "Officer-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    local current = dibs.Seasons.GetCurrent()
    assert_not_nil(current)
    local currentId = current.id

    local draft = dibs.Seasons.CreateDraft("Season 2", "season-029-test")
    assert_not_nil(draft)
    assert_equal("season-029-test", draft.id)
    assert_true(draft.isDraft)
    assert_false(draft.isActive)
    assert_equal(currentId, dibs.GetCurrentSeasonId())
    assert_equal(currentId, dibs.Seasons.GetCurrent().id)
  end)

  it("does not allow a draft ID to overwrite a saved Dibs season", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local existing = dibs.Seasons.GetCurrent()
    local duplicate = dibs.Seasons.CreateDraft("Collision", existing.id)
    assert_nil(duplicate)
    assert_equal(existing.name, dibs.Seasons.GetById(existing.id).name)
    assert_equal(existing.id, dibs.GetCurrentSeasonId())
  end)

  it("creates the roster draft under the same inactive Dibs season ID", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "GameMaster-Realm", guildLeader = true,
      guildMembers = { "GameMaster-Realm", "Officer-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    assert_true(dibs.Governance.AdoptInitial(nil, {
      reason = "seasonal roster test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
      { allowPublicPreDibs = true, preDibModes = {} }, "seasonal roster test"))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
      "enable seasonal roster for this test"))
    local currentId = dibs.Seasons.GetCurrent().id
    local missingDates = dibs.SeasonalRoster.CreateSeason({ name = "Season 2" }, "missing-dates", "GameMaster-Realm")
    assert_false(missingDates.ok)
    assert_equal("SEASON_DATES_REQUIRED", missingDates.code)
    local now = dibs.GetTimestamp()
    local result = dibs.SeasonalRoster.CreateSeason({ name = "Season 2", startAt = now + 10000,
      registrationStartAt = now + 5000 }, "create-season-029", "GameMaster-Realm")
    assert_true(result.ok, tostring(result.code))
    local replay = dibs.SeasonalRoster.CreateSeason({ name = "Season 2", startAt = now + 10000,
      registrationStartAt = now + 5000 }, "create-season-029", "GameMaster-Realm")
    assert_true(replay.ok, tostring(replay.code))
    assert_true(replay.idempotent)
    assert_equal(result.value, replay.value)
    local stale = dibs.SeasonalRoster.SetRegistrationState(result.value, "OPEN", 0,
      "stale-open-season", "Open signup", "GameMaster-Realm")
    assert_false(stale.ok)
    assert_equal("STALE_REVISION", stale.code)
    assert_equal(result.value, dibs.Seasons.GetById(result.value).id)
    assert_true(dibs.Seasons.GetById(result.value).isDraft)
    assert_equal(currentId, dibs.GetCurrentSeasonId())
    local atSeasonStart = dibs.SeasonalRoster.GetSeasonLifecycle(result.value, now + 10000)
    assert_equal("DRAFT", atSeasonStart.registrationStatus)
    assert_equal("DRAFT", atSeasonStart.seasonStatus)
    local season = dibs.SeasonalRoster.ListSeasons()[1]
    assert_equal(result.value, season.seasonId)
    assert_equal(result.value, season.identitySeasonId)
  end)

  it("edits only draft fields through an audited revision and preserves the active Dibs season", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      playerName = "GameMaster-Realm", guildMembers = { "GameMaster-Realm" }, guildRankIndices = { [1] = 0 } } })
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "draft edit test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
      { allowPublicPreDibs = true, preDibModes = {} }, "draft edit test"))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
      "enable seasonal roster for this test"))
    local now = dibs.GetTimestamp()
    local created = dibs.SeasonalRoster.CreateSeason({ name = "Draft A", startAt = now + 1000,
      registrationStartAt = now + 500 }, "create-draft-edit", "GameMaster-Realm")
    assert_true(created.ok, tostring(created.code))
    local currentBefore = dibs.Seasons.GetCurrent()
    local ledgerBefore = dibs.GetDB().ledgers
    local edited = dibs.SeasonalRoster.UpdateDraft(created.value,
      { name = "Draft B", registrationEndAt = now + 600,
        raidRules = "Need main-spec only; pass for alts until AotC." }, 1,
      "edit-draft-season", "Corrected the registration window", "GameMaster-Realm")
    assert_true(edited.ok, tostring(edited.code))
    assert_equal(2, edited.revision)
    local season = dibs.GetDB().seasonalRoster.seasons[created.value]
    assert_equal("Draft B", season.revisions["2"].name)
    assert_equal("Draft A", season.revisions["1"].name)
    assert_equal("", season.revisions["1"].raidRules)
    assert_equal("Need main-spec only; pass for alts until AotC.", season.revisions["2"].raidRules)
    assert_equal("Need main-spec only; pass for alts until AotC.",
      dibs.SeasonalRoster.ListSeasons()[1].raidRules)
    assert_equal("SEASON_DRAFT_UPDATED", season.revisions["2"].action)
    assert_equal(currentBefore and currentBefore.id, dibs.Seasons.GetCurrent() and dibs.Seasons.GetCurrent().id)
    assert_equal(ledgerBefore, dibs.GetDB().ledgers)
    local replay = dibs.SeasonalRoster.UpdateDraft(created.value,
      { name = "Draft B", registrationEndAt = now + 600,
        raidRules = "Need main-spec only; pass for alts until AotC." }, 1,
      "edit-draft-season", "Corrected the registration window", "GameMaster-Realm")
    assert_true(replay.ok)
    assert_true(replay.idempotent)
    assert_equal(2, replay.revision)
    local stale = dibs.SeasonalRoster.UpdateDraft(created.value, { name = "Stale" }, 1,
      "stale-draft-season", "Stale revision attempt", "GameMaster-Realm")
    assert_false(stale.ok)
    assert_equal("STALE_REVISION", stale.code)
    local forbidden = dibs.SeasonalRoster.UpdateDraft(created.value, { currentSeasonId = "other" }, 2,
      "forbidden-draft-field", "Invalid field attempt", "GameMaster-Realm")
    assert_false(forbidden.ok)
    assert_equal("PATCH_FIELD_FORBIDDEN", forbidden.code)
  end)

  it("copies season settings into a draft without copying people, dates, identity, or ledger", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      playerName = "GameMaster-Realm", guildMembers = { "GameMaster-Realm" }, guildRankIndices = { [1] = 0 } } })
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "copy settings test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
      { allowPublicPreDibs = true, preDibModes = {} }, "copy settings test"))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
      "enable seasonal roster for this test"))
    local now = dibs.GetTimestamp()
    local source = dibs.SeasonalRoster.CreateSeason({ name = "Prior", startAt = now + 10000,
      registrationStartAt = now + 9000, description = "Prior rules summary",
      raidRules = "One tier token until everyone has one.",
      categoryCatalog = { { id = "RAIDER", name = "Raider", description = "Raid", active = true } },
      raidSchedule = { { weekday = 5, startTime = "20:00", durationMinutes = 180 } },
    }, "copy-settings-source", "GameMaster-Realm")
    local target = dibs.SeasonalRoster.CreateSeason({ name = "Next", startAt = now + 20000,
      registrationStartAt = now + 19000, description = "Target description" },
      "copy-settings-target", "GameMaster-Realm")
    assert_true(source.ok, tostring(source.code))
    assert_true(target.ok, tostring(target.code))
    local sourceSeason = dibs.GetDB().seasonalRoster.seasons[source.value]
    sourceSeason.enrollments["prior-player"] = { enrollmentId = "prior-player", character = "Prior-Realm" }
    local ledgerBefore = dibs.GetDB().ledgers
    local copied = dibs.SeasonalRoster.CopySeasonSettings(source.value, target.value, 1,
      "copy-settings-operation", "Copy reviewed signup settings", "GameMaster-Realm")
    assert_true(copied.ok, tostring(copied.code))
    local targetSeason = dibs.GetDB().seasonalRoster.seasons[target.value]
    local targetConfig = targetSeason.revisions[tostring(targetSeason.currentRevision)]
    assert_equal("Target description", targetSeason.revisions["1"].description)
    assert_equal("Prior rules summary", targetConfig.description)
    assert_equal("One tier token until everyone has one.", targetConfig.raidRules)
    assert_equal("Next", targetConfig.name)
    assert_equal(now + 20000, targetConfig.startAt)
    assert_equal(target.value, targetConfig.identitySeasonId)
    assert_equal("20:00", targetConfig.raidSchedule[1].startTime)
    assert_equal(0, #targetSeason.enrollments)
    assert_equal(ledgerBefore, dibs.GetDB().ledgers)
  end)

  it("rejects season rule text that exceeds the bounded saved and sync payload", function()
    local _, dibs = loader.load({ withAce3 = true })
    local valid, reason = dibs.SeasonalRoster.ValidateSeasonInput({ name = "Oversized rules",
      raidRules = string.rep("x", 8001), startAt = 2000000000, registrationStartAt = 1999999000 })
    assert_false(valid)
    assert_equal("INVALID_INPUT", reason)
  end)
end)
