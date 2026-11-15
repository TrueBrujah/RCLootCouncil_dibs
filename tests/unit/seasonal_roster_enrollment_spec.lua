local loader = require("helpers.load_addon")
local Fixtures = require("helpers.seasonal_roster_fixtures")

local guild = { "GameMaster-Realm", "Officer-Realm", "Player-Realm", "Other-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 }

local function adoptPolicy(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "seasonal roster enrollment test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "seasonal roster enrollment test"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
    "enable seasonal roster for this test"))
end

describe("seasonal raid enrollment", function()
  it("keeps signup pending until an Officer approves it and snapshots the requested path", function()
    local _, gm = loader.load({ withAce3 = true, wow = { playerName = guild[1], guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    adoptPolicy(gm)
    local now = gm.GetTimestamp()
    local created = gm.SeasonalRoster.CreateSeason({ name = "Season 2", startAt = now + 10000,
      registrationStartAt = now - 10 }, "create-season-enrollment", guild[1])
    assert_true(created.ok, tostring(created.code))
    local opened = gm.SeasonalRoster.SetRegistrationState(created.value, "OPEN", created.revision,
      "open-season-enrollment", "Open signup", guild[1])
    assert_true(opened.ok, tostring(opened.code))
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)

    local _, player = loader.load({ withAce3 = true, savedVariables = saved, wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local input = Fixtures.enrollment({ enrollmentId = nil, categoryId = "RAIDER", requestedPath = "CORE_PROGRESSION" })
    local result = player.SeasonalRoster.UpsertOwnEnrollment(created.value, input, 0, "enroll-core-path")
    assert_true(result.ok, tostring(result.code))
    local selfPromotion = player.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ enrollmentId = result.value, character = guild[3],
        categoryId = "CORE_RAIDER", requestedPath = "CORE_PROGRESSION" }), result.revision,
      "enroll-self-promote-core")
    assert_false(selfPromotion.ok, "players may request Core progression but cannot award themselves Core Raider status")
    assert_equal("CORE_PROMOTION_NOT_ELIGIBLE", selfPromotion.code)
    local own = player.SeasonalRoster.GetOwnEnrollment(created.value)
    assert_equal("PENDING_REVIEW", own.status)
    assert_equal("CORE_PROGRESSION", own.requestedPath)
    local public = player.SeasonalRoster.GetPublicRosterPage(created.value, { page = 1, pageSize = 20 })
    assert_equal(0, public.total)

    local _, officer = loader.load({ withAce3 = true, savedVariables = _G.RCLootCouncil_dibsDB, wow = {
      playerName = guild[1], guildLeader = true, guildMembers = guild, guildRankIndices = ranks,
    } })
    local rows = officer.SeasonalRoster.GetOfficerEnrollments(created.value)
    assert_equal("PENDING_REVIEW", rows[1].status)
    local approved = officer.SeasonalRoster.AdminUpdateEnrollment(created.value, result.value,
      { status = "ACTIVE", categoryId = "RAIDER", requestedPath = "CORE_PROGRESSION" }, result.revision,
      "Approved for Raider candidate roster", "approve-core-path", guild[1])
    assert_true(approved.ok, tostring(approved.code))
    assert_equal(1, officer.SeasonalRoster.GetPublicRosterPage(created.value, { page = 1, pageSize = 20 }).total)
    local auditIndex = officer.GetDB().seasonalRoster.auditOperationIndex["approve-core-path"]
    local audit = auditIndex and officer.GetDB().seasonalRoster.auditLog[auditIndex]
    assert_equal("ENROLLMENT_ADMIN_CORRECTED", audit.action)
    assert_equal("Approved for Raider candidate roster", audit.reason)

    local promoted = officer.SeasonalRoster.AdminUpdateEnrollment(created.value, result.value,
      { status = "ACTIVE", categoryId = "CORE_RAIDER", requestedPath = "CORE_PROGRESSION" },
      approved.revision, "Promoted after review", "approve-core-status", guild[1])
    assert_true(promoted.ok, tostring(promoted.code))
    local _, corePlayer = loader.load({ withAce3 = true, savedVariables = officer.DeepCopy(_G.RCLootCouncil_dibsDB), wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local selfDowngradePath = corePlayer.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ enrollmentId = result.value, character = guild[3],
        categoryId = "CORE_RAIDER", requestedPath = "STANDARD" }), promoted.revision,
      "player-change-core-path")
    assert_false(selfDowngradePath.ok)
    assert_equal("CORE_PROMOTION_NOT_ELIGIBLE", selfDowngradePath.code)
    local preservedCore = corePlayer.SeasonalRoster.GetOwnEnrollment(created.value)
    assert_equal("CORE_RAIDER", preservedCore.categoryId)
    assert_equal("CORE_PROGRESSION", preservedCore.requestedPath)
  end)

  it("requires a current authorized Officer revision to review an enrollment", function()
    local _, gm = loader.load({ withAce3 = true, wow = { playerName = guild[1], guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    adoptPolicy(gm)
    local now = gm.GetTimestamp()
    local created = gm.SeasonalRoster.CreateSeason({ name = "Review season", startAt = now + 10000,
      registrationStartAt = now - 10 }, "review-season-create", guild[1])
    assert_true(created.ok, tostring(created.code))
    local opened = gm.SeasonalRoster.SetRegistrationState(created.value, "OPEN", created.revision,
      "review-season-open", "Open review test", guild[1])
    assert_true(opened.ok, tostring(opened.code))
    local _, player = loader.load({ withAce3 = true, savedVariables = _G.RCLootCouncil_dibsDB, wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local signup = player.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ character = guild[3] }), 0, "review-season-signup")
    assert_true(signup.ok, tostring(signup.code))
    local saved = player.DeepCopy(_G.RCLootCouncil_dibsDB)

    local _, member = loader.load({ withAce3 = true, savedVariables = saved, wow = {
      playerName = guild[4], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local rows, listReason = member.SeasonalRoster.GetOfficerEnrollments(created.value)
    assert_nil(rows)
    assert_equal("GUILD_ADMIN_REQUIRED", listReason)
    local denied = member.SeasonalRoster.AdminUpdateEnrollment(created.value, signup.value,
      { status = "ACTIVE" }, signup.revision, "Unauthorized approval", "review-unauthorized", guild[4])
    assert_false(denied.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", denied.code)

    local _, officer = loader.load({ withAce3 = true, savedVariables = saved, wow = {
      playerName = guild[2], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local reviewed = officer.SeasonalRoster.AdminUpdateEnrollment(created.value, signup.value,
      { status = "ACTIVE" }, signup.revision, "Approved by officer", "review-approved", guild[2])
    assert_true(reviewed.ok, tostring(reviewed.code))
    local stale = officer.SeasonalRoster.AdminUpdateEnrollment(created.value, signup.value,
      { status = "REJECTED" }, signup.revision, "Stale attempt", "review-stale", guild[2])
    assert_false(stale.ok)
    assert_equal("STALE_REVISION", stale.code)
    local enrollment = officer.GetDB().seasonalRoster.seasons[created.value].enrollments[signup.value]
    assert_equal("ACTIVE", enrollment.status)
    assert_equal(guild[2]:lower(), enrollment.updatedBy)
  end)

  it("replays a signup idempotently, permits an out-of-guild character, and rejects writes after close", function()
    local _, gm = loader.load({ withAce3 = true, wow = { playerName = guild[1], guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    adoptPolicy(gm)
    local now = gm.GetTimestamp()
    local created = gm.SeasonalRoster.CreateSeason({ name = "Season 2", startAt = now + 10000,
      registrationStartAt = now - 10 }, "create-season-replay", guild[1])
    assert_true(created.ok, tostring(created.code))
    local opened = gm.SeasonalRoster.SetRegistrationState(created.value, "OPEN", created.revision,
      "open-season-replay", "Open signup", guild[1])
    assert_true(opened.ok, tostring(opened.code))
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)

    local _, player = loader.load({ withAce3 = true, savedVariables = saved, wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local signup = Fixtures.enrollment({ character = "Guest-Realm", characterKey = "guest-realm" })
    local beforeTransactions = player.DeepCopy(player.GetDB().ledger.transactions)
    local first = player.SeasonalRoster.UpsertOwnEnrollment(created.value, signup, 0, "signup-replay")
    assert_true(first.ok, tostring(first.code))
    local replay = player.SeasonalRoster.UpsertOwnEnrollment(created.value, signup, 0, "signup-replay")
    assert_true(replay.ok, tostring(replay.code))
    assert_true(replay.idempotent)
    assert_equal(first.value, replay.value)
    assert_equal("Guest-Realm", player.SeasonalRoster.GetOwnEnrollment(created.value).character)
    assert_equal(player.Sync.CalculateContentHash(beforeTransactions),
      player.Sync.CalculateContentHash(player.GetDB().ledger.transactions),
      "self-service signup must not mutate ledger transaction content")

    local _, officer = loader.load({ withAce3 = true, savedVariables = _G.RCLootCouncil_dibsDB, wow = {
      playerName = guild[1], guildLeader = true, guildMembers = guild, guildRankIndices = ranks,
    } })
    local closed = officer.SeasonalRoster.SetRegistrationState(created.value, "CLOSED", opened.revision,
      "close-season-replay", "Review signups", guild[1])
    assert_true(closed.ok, tostring(closed.code))
    local closedLifecycle = officer.SeasonalRoster.GetSeasonLifecycle(created.value, now + 30 * 24 * 60 * 60)
    assert_equal("REVIEW", closedLifecycle.seasonStatus)
    assert_equal("CLOSED", closedLifecycle.registrationStatus)
    local _, closedPlayer = loader.load({ withAce3 = true, savedVariables = _G.RCLootCouncil_dibsDB, wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local rejected = closedPlayer.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ character = "Guest2-Realm", characterKey = "guest2-realm" }), 0, "signup-after-close")
    assert_false(rejected.ok)
    assert_equal("REGISTRATION_CLOSED", rejected.code)
    assert_equal(1, #closedPlayer.SeasonalRoster.GetOwnEnrollments(created.value))
  end)

  it("keeps edit and withdrawal history without touching the Dibs ledger", function()
    local _, gm = loader.load({ withAce3 = true, wow = { playerName = guild[1], guildLeader = true,
      guildMembers = guild, guildRankIndices = ranks } })
    adoptPolicy(gm)
    local now = gm.GetTimestamp()
    local created = gm.SeasonalRoster.CreateSeason({ name = "Season 2", startAt = now + 10000,
      registrationStartAt = now - 10 }, "create-season-edit", guild[1])
    assert_true(created.ok, tostring(created.code))
    local opened = gm.SeasonalRoster.SetRegistrationState(created.value, "OPEN", created.revision,
      "open-season-edit", "Open signup", guild[1])
    assert_true(opened.ok, tostring(opened.code))
    local _, player = loader.load({ withAce3 = true, savedVariables = _G.RCLootCouncil_dibsDB, wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local beforeTransactions = player.DeepCopy(player.GetDB().ledger.transactions)
    local createdEnrollment = player.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ character = guild[3] }), 0, "signup-edit")
    assert_true(createdEnrollment.ok, tostring(createdEnrollment.code))
    local savedAfterSignup = player.DeepCopy(player.GetDB())
    local _, otherPlayer = loader.load({ withAce3 = true, savedVariables = savedAfterSignup, wow = {
      playerName = guild[4], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    local attemptedTakeover = otherPlayer.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ enrollmentId = createdEnrollment.value, character = guild[3] }), 1,
      "other-player-edit")
    assert_false(attemptedTakeover.ok)
    assert_equal("OWNER_MISMATCH", attemptedTakeover.code)
    local _, playerAgain = loader.load({ withAce3 = true, savedVariables = savedAfterSignup, wow = {
      playerName = guild[3], guildLeader = false, guildMembers = guild, guildRankIndices = ranks,
    } })
    player = playerAgain
    local updated = player.SeasonalRoster.UpsertOwnEnrollment(created.value,
      Fixtures.enrollment({ character = guild[3], requestedPath = "CASUAL" }), 1, "signup-update")
    assert_true(updated.ok, tostring(updated.code))
    assert_equal(2, updated.revision)
    local withdrawn = player.SeasonalRoster.WithdrawOwnEnrollment(created.value, updated.value,
      updated.revision, "signup-withdraw")
    assert_true(withdrawn.ok, tostring(withdrawn.code))
    local history = player.GetDB().seasonalRoster.seasons[created.value].enrollmentRevisions[updated.value]
    assert_not_nil(history["1"])
    assert_equal("CASUAL", history["2"].requestedPath)
    assert_equal("WITHDRAWN", history["3"].status)
    assert_equal(player.Sync.CalculateContentHash(beforeTransactions),
      player.Sync.CalculateContentHash(player.GetDB().ledger.transactions),
      "editing or withdrawing signup must not mutate ledger transaction content")
  end)
end)
