local Dibs = _G.Dibs
Dibs.Seasons = Dibs.Seasons or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  if type(Dibs.db.seasons) ~= "table" then
    Dibs.db.seasons = {}
  end
end

function Dibs.Seasons.Create(name)
  ensureState()

  local count = 0
  for _ in pairs(Dibs.db.seasons) do
    count = count + 1
  end

  local seasonName = name and name ~= "" and name or ("Season " .. tostring(count + 1))
  local season = {
    id = "season-" .. tostring(time()) .. "-" .. tostring(math.random(100, 999)),
    name = seasonName,
    createdAt = time(),
    isActive = true,
    note = "Created by Dibs",
  }

  Dibs.db.seasons[season.id] = season
  Dibs.db.currentSeasonId = season.id
  return season
end

function Dibs.Seasons.GetById(seasonId)
  ensureState()
  if not seasonId then
    return nil
  end

  return Dibs.db.seasons[seasonId]
end

function Dibs.Seasons.GetCurrent()
  ensureState()
  if Dibs.db.currentSeasonId and Dibs.db.seasons[Dibs.db.currentSeasonId] then
    return Dibs.db.seasons[Dibs.db.currentSeasonId]
  end

  if not next(Dibs.db.seasons) then
    return Dibs.Seasons.Create("Season 1")
  end
  for _, season in pairs(Dibs.db.seasons) do
    Dibs.db.currentSeasonId = season.id
    return season
  end
  return nil
end

function Dibs.Seasons.GetOrCreateDefault()
  ensureState()

  if not next(Dibs.db.seasons) then
    return Dibs.Seasons.Create("Season 1")
  end

  return Dibs.Seasons.GetCurrent()
end

function Dibs.Seasons.SetCurrent(seasonId)
  ensureState()
  if Dibs.db.seasons[seasonId] then
    Dibs.db.currentSeasonId = seasonId
    return true
  end

  return false
end

function Dibs.Seasons.List()
  ensureState()
  local seasons = {}
  for _, season in pairs(Dibs.db.seasons) do
    table.insert(seasons, season)
  end

  table.sort(seasons, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)

  return seasons
end
