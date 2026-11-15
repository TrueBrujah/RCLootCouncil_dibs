local Fixtures = {}

function Fixtures.season(overrides)
  local season = {
    seasonId = "season-029-fixture",
    revision = 1,
    lifecycleState = "DRAFT",
    registrationState = "DRAFT",
    name = "Season 1",
    startAt = 1793491200,
    registrationStartAt = 1792886400,
    categories = { "RAIDER", "CORE_RAIDER", "MEMBER" },
    raidSchedule = { { weekday = 5, startTime = "20:00", durationMinutes = 180 } },
  }
  for key, value in pairs(overrides or {}) do season[key] = value end
  return season
end

function Fixtures.enrollment(overrides)
  local enrollment = {
    seasonId = "season-029-fixture",
    character = "Player-Realm",
    characterKey = "player-realm",
    categoryId = "RAIDER",
    requestedPath = "CORE_PROGRESSION",
    primarySpec = "balance",
    secondarySpec = "restoration",
    roles = { "DAMAGER", "HEALER" },
    status = "PENDING_REVIEW",
    revision = 1,
  }
  for key, value in pairs(overrides or {}) do enrollment[key] = value end
  return enrollment
end

function Fixtures.rank(index, amount)
  return { rankIndex = index or 0, startingDibs = amount or 1, enabled = true }
end

function Fixtures.ledger(seasonId)
  return { seasonId = seasonId or "season-029-fixture", transactions = {}, playerStates = {} }
end

return Fixtures
