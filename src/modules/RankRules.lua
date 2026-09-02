local Dibs = _G.Dibs
Dibs.RankRules = Dibs.RankRules or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  if type(Dibs.db.rankRules) ~= "table" then
    Dibs.db.rankRules = {}
  end
end

local function normalizeRankIndex(rankIndex)
  local value = tonumber(rankIndex) or 0
  return math.floor(value)
end

function Dibs.RankRules.GetRulesForSeason(seasonId)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  if not Dibs.db.rankRules[targetSeason] then
    Dibs.db.rankRules[targetSeason] = {}
  end
  return Dibs.db.rankRules[targetSeason]
end

function Dibs.RankRules.SetAllocation(seasonId, rankIndex, rankName, allocation)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local rules = Dibs.RankRules.GetRulesForSeason(targetSeason)
  local normalizedIndex = normalizeRankIndex(rankIndex)
  rules[tostring(normalizedIndex)] = {
    rankIndex = normalizedIndex,
    rankName = rankName or ("Rank " .. tostring(normalizedIndex)),
    allocation = tonumber(allocation) or 0,
  }
  return rules[tostring(normalizedIndex)]
end

function Dibs.RankRules.GetAllocation(seasonId, rankIndex)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local rules = Dibs.RankRules.GetRulesForSeason(targetSeason)
  return (rules[tostring(normalizeRankIndex(rankIndex))] or {}).allocation or 0
end

function Dibs.RankRules.GetPlayerRankInfo(playerName)
  local targetName = playerName or Dibs.GetPlayerName()
  if type(GetNumGuildMembers) == "function" then
    local count = GetNumGuildMembers(true)
    for index = 1, count do
      if type(GetGuildRosterInfo) == "function" then
        local name, rankName, rankIndex = GetGuildRosterInfo(index)
        if name and string.lower(name) == string.lower(targetName) then
          return {
            playerName = name,
            rankName = rankName or "Guild Member",
            rankIndex = tonumber(rankIndex) or 0,
          }
        end
      end
    end
  end

  return {
    playerName = targetName,
    rankName = "Guild Member",
    rankIndex = 0,
  }
end

function Dibs.RankRules.GetAllocationForPlayer(playerName, seasonId)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local info = Dibs.RankRules.GetPlayerRankInfo(playerName)
  local allocation = Dibs.RankRules.GetAllocation(targetSeason, info.rankIndex)
  if allocation and allocation > 0 then
    return allocation
  end

  if Dibs.db.settings and Dibs.db.settings.defaultAllocation then
    return tonumber(Dibs.db.settings.defaultAllocation) or Dibs.DEFAULT_DIBS_PER_RANK
  end

  return Dibs.DEFAULT_DIBS_PER_RANK
end
