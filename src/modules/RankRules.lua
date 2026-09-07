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

local function finiteNumber(value)
  local number = tonumber(value)
  return number and number == number and number ~= math.huge and number ~= -math.huge and number or nil
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
    local count = GetNumGuildMembers()
    local targetKey = string.lower(tostring(targetName or ""))
    local targetShort = targetKey:match("^([^-]+)")
    local shortMatch
    for index = 1, count do
      if type(GetGuildRosterInfo) == "function" then
        local name, rankName, rankIndex = GetGuildRosterInfo(index)
        local rosterKey = string.lower(tostring(name or ""))
        if name and rosterKey == targetKey then
          return {
            playerName = name,
            rankName = rankName or "Guild Member",
            rankIndex = tonumber(rankIndex) or 0,
          }
        end
        if name and not targetKey:find("-", 1, true) and rosterKey:match("^([^-]+)") == targetShort then
          if shortMatch then
            shortMatch = false
          elseif shortMatch == nil then
            shortMatch = { playerName = name, rankName = rankName, rankIndex = rankIndex }
          end
        end
      end
    end
    if type(shortMatch) == "table" then
      return {
        playerName = shortMatch.playerName,
        rankName = shortMatch.rankName or "Guild Member",
        rankIndex = tonumber(shortMatch.rankIndex) or 0,
      }
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
  local rules = Dibs.RankRules.GetRulesForSeason(targetSeason)
  if rules[tostring(normalizeRankIndex(info.rankIndex))] ~= nil then
    return tonumber(allocation) or 0
  end

  if Dibs.db.settings and Dibs.db.settings.defaultAllocation then
    return tonumber(Dibs.db.settings.defaultAllocation) or Dibs.DEFAULT_DIBS_PER_RANK
  end

  return Dibs.DEFAULT_DIBS_PER_RANK
end

function Dibs.RankRules.SetRankAllocation(seasonId, rankIndex, allocation, rankName)
  ensureState()
  if not seasonId or not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(seasonId) then
    return nil, "SEASON_NOT_FOUND"
  end
  local numericRank = finiteNumber(rankIndex)
  local numericAllocation = finiteNumber(allocation)
  if numericRank == nil or math.floor(numericRank) ~= numericRank or numericRank < 0 or numericRank > 9 then
    return nil, "INVALID_RANK_INDEX"
  end
  if numericAllocation == nil or numericAllocation < 0 or numericAllocation > 100000 then
    return nil, "INVALID_ALLOCATION"
  end

  return Dibs.RankRules.SetAllocation(seasonId, rankIndex, rankName, numericAllocation), nil
end

function Dibs.RankRules.GetRankAllocation(seasonId, rankIndex)
  ensureState()
  if not seasonId or not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(seasonId) then
    return nil
  end

  local rules = Dibs.RankRules.GetRulesForSeason(seasonId)
  return rules[tostring(normalizeRankIndex(rankIndex))]
end
