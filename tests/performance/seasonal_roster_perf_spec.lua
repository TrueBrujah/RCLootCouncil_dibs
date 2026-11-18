local loader = require("helpers.load_addon")
local Fixtures = require("helpers.seasonal_roster_fixtures")

local function sum(values)
  local total = 0
  for _, count in pairs(values) do total = total + count end
  return total
end

describe("seasonal roster projection work budgets", function()
  for _, size in ipairs({ 20, 60, 500, 1000 }) do
    it("bounds cold and cached pagination for " .. size .. " enrollments", function()
      local gm = "GameMaster-Realm"
      local _, dibs = loader.load({ withAce3 = true, wow = { playerName = gm,
        guildLeader = true, guildMembers = { gm }, guildRankIndices = { [1] = 0 } } })
      assert_true(dibs.Governance.AdoptInitial(nil, { reason = "projection work budget",
        officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
        policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
      assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
        { allowPublicPreDibs = true, preDibModes = {} }, "projection work budget"))
      assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
        "enable projection work budget"))
      local now = dibs.GetTimestamp()
      local created = dibs.SeasonalRoster.CreateSeason({ name = "Projection budget " .. size,
        startAt = now + 10000, registrationStartAt = now + 5000 }, "perf-create-" .. size, gm)
      assert_true(created.ok, tostring(created.code))
      local season = dibs.GetDB().seasonalRoster.seasons[created.value]
      for index = 1, size do
        local character = string.format("Player%04d-Realm", index)
        local id = "perf-enrollment-" .. index
        season.enrollments[id] = Fixtures.enrollment({ enrollmentId = id, seasonId = created.value,
          character = character, characterKey = string.lower(character), status = "ACTIVE",
          roles = { index % 3 == 0 and "HEALER" or (index % 3 == 1 and "TANK" or "DAMAGER") } })
      end
      -- These fixtures measure the projection directly; identity authorization and
      -- approved-link deduplication are covered by the service regression suites.
      local original = dibs.CharacterEligibility.GetPersonProjection
      local identityCalls = 0
      dibs.CharacterEligibility.GetPersonProjection = function(...)
        identityCalls = identityCalls + 1
        return original(...)
      end
      local started = os.clock()
      local first = assert(dibs.SeasonalRoster.GetPublicRosterPage(created.value,
        { page = 1, pageSize = 1000 }))
      local coldSeconds = os.clock() - started
      assert_equal(size, first.total)
      assert_equal(size, first.uniquePlayers)
      assert_equal(size, identityCalls, "cold projection must resolve each included row once")
      assert_equal(math.min(50, size), #first.rows, "page size is clamped independently of total size")
      assert_equal(size, sum(first.classes))
      assert_equal(size, sum(first.armor))
      assert_equal(size, sum(first.roles))
      assert_equal(size, sum(first.categories))

      local seen, count = {}, 0
      started = os.clock()
      for page = 1, first.pages do
        local result = assert(dibs.SeasonalRoster.GetPublicRosterPage(created.value,
          { page = page, pageSize = 50 }))
        assert_equal(size, result.total)
        for _, row in ipairs(result.rows) do
          assert_nil(seen[row.character], "pagination must not duplicate a character")
          seen[row.character] = true
          count = count + 1
        end
      end
      local warmSeconds = os.clock() - started
      assert_equal(size, count)
      assert_equal(size, identityCalls, "cached page traversal must not rebuild the projection")

      -- Returned data must not alias cached aggregates or rows.
      first.roles.TANK = -1
      first.rows[1].roles[1] = "PRIVATE_TEST_VALUE"
      local cached = assert(dibs.SeasonalRoster.GetPublicRosterPage(created.value, { pageSize = 50 }))
      assert_equal(size, sum(cached.roles))
      assert_true(cached.rows[1].roles[1] ~= "PRIVATE_TEST_VALUE")

      season.enrollments["perf-enrollment-1"].status = "WITHDRAWN"
      season.rosterRevision = season.rosterRevision + 1
      local refreshed = assert(dibs.SeasonalRoster.GetPublicRosterPage(created.value, { pageSize = 50 }))
      assert_equal(size - 1, refreshed.total)
      assert_equal(size * 2 - 1, identityCalls, "revision invalidates exactly one cold projection")
      io.write(string.format("METRIC seasonal_projection rows=%d cold_seconds=%.6f warm_all_pages_seconds=%.6f identity_calls=%d\n",
        size, coldSeconds, warmSeconds, identityCalls))
      dibs.CharacterEligibility.GetPersonProjection = original
    end)
  end
end)
