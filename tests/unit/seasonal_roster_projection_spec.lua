local loader = require("helpers.load_addon")
local Fixtures = require("helpers.seasonal_roster_fixtures")

describe("seasonal roster public projection", function()
  it("returns deterministic bounded pages, matching totals, and no officer-private fields", function()
    local guild = { "GameMaster-Realm", "Officer-Realm" }
    local _, dibs = loader.load({ withAce3 = true, wow = { playerName = guild[1], guildLeader = true,
      guildMembers = guild, guildRankIndices = { [1] = 0, [2] = 1 } } })
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "projection test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
      { allowPublicPreDibs = true, preDibModes = {} }, "projection test"))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
      "enable seasonal roster for this test"))
    local now = dibs.GetTimestamp()
    local created = dibs.SeasonalRoster.CreateSeason({ name = "Season 2", startAt = now + 10000,
      registrationStartAt = now + 5000 }, "create-projection-season", guild[1])
    assert_true(created.ok, tostring(created.code))
    local season = dibs.GetDB().seasonalRoster.seasons[created.value]
    for index = 1, 1000 do
      local character = string.format("Player%04d-Realm", index)
      local enrollment = Fixtures.enrollment({ enrollmentId = "enrollment-" .. index,
        character = character, characterKey = string.lower(character), status = "ACTIVE",
        ownerCharacterKey = "owner-" .. index, officerNote = "private" })
      season.enrollments[enrollment.enrollmentId] = enrollment
    end
    local link = dibs.CharacterEligibility.DeclareRelationship({ seasonId = created.value,
      mainCharacter = "Player0001-Realm", altCharacter = "Player0002-Realm" }, "Player0001-Realm")
    assert_equal("approved", dibs.CharacterEligibility.ApproveRelationship(link.relationshipId,
      "GameMaster-Realm").status)

    local first = dibs.SeasonalRoster.GetPublicRosterPage(created.value, { page = 1, pageSize = 50 })
    local last = dibs.SeasonalRoster.GetPublicRosterPage(created.value, { page = 20, pageSize = 50 })
    assert_equal(1000, first.total)
    assert_equal(20, first.pages)
    assert_equal(50, #first.rows)
    assert_equal(50, #last.rows)
    assert_equal("Player0001-Realm", first.rows[1].character)
    assert_equal("Player0951-Realm", last.rows[1].character)
    assert_equal(999, first.uniquePlayers,
      "linked Main and Alt enrollments remain visible but count once in player composition")
    assert_equal(1000, first.categories.RAIDER)
    for _, row in ipairs(first.rows) do
      assert_equal("CORE_PROGRESSION", row.requestedPath)
      assert_nil(row.ownerCharacterKey)
      assert_nil(row.officerNote)
    end

    local filtered = dibs.SeasonalRoster.GetPublicRosterPage(created.value,
      { page = 1, pageSize = 10, search = "player0009", categoryId = "RAIDER" })
    assert_equal(1, filtered.total)
    assert_equal(1, #filtered.rows)
    season.enrollments["enrollment-1"].status = "WITHDRAWN"
    season.rosterRevision = season.rosterRevision + 1
    local refreshed = dibs.SeasonalRoster.GetPublicRosterPage(created.value, { page = 1, pageSize = 50 })
    assert_equal(999, refreshed.total, "roster revision changes must invalidate the cached public projection")
  end)
end)
