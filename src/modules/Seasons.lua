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

  local function nextSeasonId()
    local candidate = nil
    if Dibs.NewId then
      candidate = Dibs.NewId("season")
    end
    if not candidate or candidate == "" then
      candidate = "season-" .. tostring(time()) .. "-" .. tostring(math.random(100000, 999999))
    end
    return tostring(candidate)
  end

  local seasonId = nextSeasonId()
  local guard = 0
  while Dibs.db.seasons[seasonId] and guard < 10 do
    seasonId = nextSeasonId()
    guard = guard + 1
  end

  if Dibs.db.seasons[seasonId] then
    seasonId = seasonId .. "-" .. tostring(time())
  end

  local season = {
    id = seasonId,
    name = seasonName,
    createdAt = time(),
    isActive = true,
    isArchived = false,
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
  if Dibs.db.currentSeasonId and Dibs.db.seasons[Dibs.db.currentSeasonId] and not Dibs.db.seasons[Dibs.db.currentSeasonId].isArchived then
    return Dibs.db.seasons[Dibs.db.currentSeasonId]
  end

  if not next(Dibs.db.seasons) then
    return Dibs.Seasons.Create("Season 1")
  end
  for _, season in pairs(Dibs.db.seasons) do
    if not season.isArchived then
      Dibs.db.currentSeasonId = season.id
      return season
    end
  end

  Dibs.db.currentSeasonId = nil
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
  if Dibs.db.seasons[seasonId] and not Dibs.db.seasons[seasonId].isArchived then
    Dibs.db.currentSeasonId = seasonId
    return true
  end

  return false
end

function Dibs.Seasons.List(includeArchived)
  ensureState()
  local seasons = {}
  for _, season in pairs(Dibs.db.seasons) do
    if includeArchived or not season.isArchived then
      table.insert(seasons, season)
    end
  end

  table.sort(seasons, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)

  return seasons
end

function Dibs.Seasons.CreateSeason(name)
  return Dibs.Seasons.Create(name)
end

function Dibs.Seasons.SetActiveSeason(seasonId)
  local ok = Dibs.Seasons.SetCurrent(seasonId)
  if not ok then
    return nil
  end
  return Dibs.Seasons.GetById(seasonId)
end

function Dibs.Seasons.ListSeasons()
  return Dibs.Seasons.List()
end

function Dibs.Seasons.ArchiveSeason(seasonId)
  ensureState()
  local season = seasonId and Dibs.db.seasons[seasonId] or nil
  if not season then
    return nil
  end

  season.isArchived = true
  season.archivedAt = time()
  season.isActive = false
  if Dibs.db.currentSeasonId == seasonId then
    Dibs.db.currentSeasonId = nil
  end

  Dibs.Seasons.GetCurrent()
  return season
end

function Dibs.Seasons.RenameSeason(seasonId, newName)
  ensureState()
  local season = seasonId and Dibs.db.seasons[seasonId] or nil
  local name = tostring(newName or ""):match("^%s*(.-)%s*$")
  if not season or name == "" then
    return nil
  end
  season.name = name
  season.updatedAt = time()
  return season
end
