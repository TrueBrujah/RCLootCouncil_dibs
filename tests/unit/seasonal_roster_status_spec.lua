local loader = require("helpers.load_addon")
local Fixtures = require("helpers.seasonal_roster_fixtures")

local GM = "GameMaster-Realm"
local PLAYER = "Player-Realm"
local guild = { GM, "Officer-Realm", PLAYER }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function adoptPolicy(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "season status test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "season status test"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
    "enable seasonal roster for this test"))
end

local function createOpenSeason(dibs)
  local now = dibs.GetTimestamp()
  local created = dibs.SeasonalRoster.CreateSeason({ name = "Status season", startAt = now + 10000,
    registrationStartAt = now - 10, raidRules = "Current rules", promotionPolicy = "Manual review.",
    raidDifficulties = { "NORMAL", "MYTHIC" },
    raidSchedule = { { weekday = 3, startTime = "19:00", durationMinutes = 150,
      timeZone = "America/Toronto", difficulty = "HEROIC" } } },
    "status-season-create", GM)
  assert_true(created.ok, tostring(created.code))
  local opened = dibs.SeasonalRoster.SetRegistrationState(created.value, "OPEN", created.revision,
    "status-season-open", "Open registration", GM)
  assert_true(opened.ok, tostring(opened.code))
  return created.value, opened.revision
end

describe("seasonal roster statuses and policy", function()
  it("maps the legacy AotC signup label to the current Raider category", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { playerName = GM, guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    local valid, normalized = dibs.SeasonalRoster.ValidateSeasonInput({ name = "Alias season",
      startAt = 1800000000, registrationStartAt = 1799990000, categories = { "AOTC" } })
    assert_true(valid)
    assert_equal(1, #normalized.categories)
    assert_equal("RAIDER", normalized.categories[1])
    assert_equal("Raider", normalized.categoryCatalog[1].name)
  end)

  it("publishes versioned rules and promotion policy without changing prior revisions", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { playerName = GM, guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    adoptPolicy(dibs)
    local seasonId, revision = createOpenSeason(dibs)
    local edited = dibs.SeasonalRoster.PublishSeasonPolicy(seasonId, {
      raidRules = "Updated raid rules", promotionPolicy = "Three reviewed progression nights." },
      revision, "publish-policy-v2", "Clarify the Core promotion criteria", GM)
    assert_true(edited.ok, tostring(edited.code))
    local season = dibs.GetDB().seasonalRoster.seasons[seasonId]
    assert_equal(revision + 1, season.currentRevision)
    assert_equal("Current rules", season.revisions[tostring(revision)].raidRules)
    assert_equal("Manual review.", season.revisions[tostring(revision)].promotionPolicy)
    assert_equal("NORMAL", season.revisions[tostring(revision)].raidDifficulties[1])
    assert_equal("MYTHIC", season.revisions[tostring(revision)].raidDifficulties[2])
    assert_equal("HEROIC", season.revisions[tostring(revision)].raidSchedule[1].difficulty)
    assert_equal("Updated raid rules", season.revisions[tostring(edited.revision)].raidRules)
    assert_equal("NORMAL", season.revisions[tostring(edited.revision)].raidDifficulties[1])
    assert_equal("MYTHIC", season.revisions[tostring(edited.revision)].raidDifficulties[2])
    assert_equal("HEROIC", season.revisions[tostring(edited.revision)].raidSchedule[1].difficulty)
    assert_equal("Three reviewed progression nights.", season.revisions[tostring(edited.revision)].promotionPolicy)
    assert_equal(2, season.revisions[tostring(edited.revision)].rulesRevision)
    local publicSeason = dibs.SeasonalRoster.ListSeasons()[1]
    assert_equal(2, publicSeason.rulesRevision)
    assert_equal("Updated raid rules", publicSeason.raidRules)
    assert_equal("NORMAL", publicSeason.raidDifficulties[1])
    assert_equal("MYTHIC", publicSeason.raidDifficulties[2])
    assert_equal("HEROIC", publicSeason.raidSchedule[1].difficulty)

    local stale = dibs.SeasonalRoster.PublishSeasonPolicy(seasonId, { raidRules = "Stale" }, revision,
      "publish-policy-stale", "Stale edit", GM)
    assert_false(stale.ok)
    assert_equal("STALE_REVISION", stale.code)
  end)

  it("keeps the Core request separate and requires a manual eligible promotion decision", function()
    local _, gm = loader.load({ withAce3 = true, wow = { playerName = GM, guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    adoptPolicy(gm)
    local seasonId = createOpenSeason(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local _, player = loader.load({ withAce3 = true, savedVariables = saved, wow = {
      playerName = PLAYER, guildLeader = false, guildMembers = guild, guildRankIndices = ranks } })
    local signup = player.SeasonalRoster.UpsertOwnEnrollment(seasonId,
      Fixtures.enrollment({ character = PLAYER, requestedPath = "CORE_PROGRESSION", categoryId = "RAIDER" }),
      0, "core-status-signup")
    assert_true(signup.ok, tostring(signup.code))
    local before = player.SeasonalRoster.GetOwnEnrollment(seasonId)
    assert_equal("CORE_PROGRESSION", before.requestedPath)
    assert_equal("RAIDER", before.categoryId)
    assert_equal("PENDING_REVIEW", before.status)

    local gmSaved = player.DeepCopy(_G.RCLootCouncil_dibsDB)
    _, gm = loader.load({ withAce3 = true, savedVariables = gmSaved, wow = { playerName = GM,
      guildLeader = true, guildMembers = guild, guildRankIndices = ranks } })

    local notYetApproved = gm.SeasonalRoster.AdminUpdateEnrollment(seasonId, signup.value,
      { categoryId = "CORE_RAIDER" }, signup.revision, "Not approved yet", "core-status-too-early", GM)
    assert_false(notYetApproved.ok)
    assert_equal("CORE_PROMOTION_NOT_ELIGIBLE", notYetApproved.code)

    local approved = gm.SeasonalRoster.AdminUpdateEnrollment(seasonId, signup.value,
      { categoryId = "RAIDER", status = "ACTIVE" }, signup.revision,
      "Approve as Raider candidate", "core-status-approve", GM)
    assert_true(approved.ok, tostring(approved.code))
    local promoted = gm.SeasonalRoster.AdminUpdateEnrollment(seasonId, signup.value,
      { categoryId = "CORE_RAIDER" }, approved.revision,
      "Promote after officer review", "core-status-promote", GM)
    assert_true(promoted.ok, tostring(promoted.code))
    local record = gm.GetDB().seasonalRoster.seasons[seasonId].enrollments[signup.value]
    assert_equal("CORE_RAIDER", record.categoryId)
    assert_equal("CORE_PROGRESSION", record.requestedPath)
    assert_equal(1, record.corePromotionPolicyRevision)
    assert_equal("Promote after officer review", record.corePromotionReason)
    local auditIndex = gm.GetDB().seasonalRoster.auditOperationIndex["core-status-promote"]
    assert_equal("CORE_PROMOTION_APPROVED", gm.GetDB().seasonalRoster.auditLog[auditIndex].action)

    local casual = gm.SeasonalRoster.AdminUpdateEnrollment(seasonId, signup.value,
      { categoryId = "CORE_RAIDER", requestedPath = "CASUAL" }, promoted.revision,
      "Change request path", "core-status-path-mismatch", GM)
    assert_false(casual.ok)
    assert_equal("CORE_PROMOTION_NOT_ELIGIBLE", casual.code)
  end)
end)
