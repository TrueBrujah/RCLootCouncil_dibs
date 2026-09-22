--[[
Module: Dibs.RankRules
Layer: Domain policy
Purpose: Map guild rank snapshots to seasonal starting allocations.
Responsibilities: Store and read rank allocations and transaction-time rank information.
Non-responsibilities: It never rewrites existing ledger history.
Dependencies: Dibs.GetDB, Dibs.Permissions, Dibs.Seasons.
Blizzard events: None directly.  Internal events/messages: None emitted.
SavedVariables: db.rankRules and transaction rank fields through Ledger.
RCLootCouncil: None.
Combat safety: Pure data operations.
Invariants: DIBS-RULE-006 and DIBS-RULE-007.
Related docs: docs/developer/data-model.md, docs/officer/configuration.md.
]]

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

local function getGuildRosterMembers()
  local members = {}
  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    return members
  end
  for index = 1, GetNumGuildMembers() do
    local name, rankName, rankIndex = GetGuildRosterInfo(index)
    if type(name) == "string" and name ~= "" then
      table.insert(members, { playerName = name, rankName = rankName, rankIndex = tonumber(rankIndex) or 0 })
    end
  end
  return members
end

function Dibs.RankRules.GetAllocationReconciliation(seasonId, members)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local roster = type(members) == "table" and members or getGuildRosterMembers()
  local rows = {}
  for _, member in ipairs(roster) do
    local name = member.playerName or member.name
    if name and name ~= "" then
      local rankInfo = member.rankIndex ~= nil and member or Dibs.RankRules.GetPlayerRankInfo(name)
      local expected = Dibs.RankRules.GetAllocationForPlayer(name, targetSeason)
      local state = Dibs.Ledger and Dibs.Ledger.GetPlayerState and Dibs.Ledger.GetPlayerState(name, targetSeason) or {}
      local assigned = tonumber(state.allocation) or 0
      local delta = math.max(0, (tonumber(expected) or 0) - assigned)
      table.insert(rows, {
        playerName = name,
        rankName = rankInfo.rankName or "Guild Member",
        rankIndex = tonumber(rankInfo.rankIndex) or 0,
        expectedAllocation = tonumber(expected) or 0,
        assignedAllocation = assigned,
        missingAllocation = delta,
        surplusAllocation = math.max(0, assigned - (tonumber(expected) or 0)),
        balance = Dibs.Ledger and Dibs.Ledger.GetBalance and Dibs.Ledger.GetBalance(name, targetSeason) or 0,
        status = delta > 0 and "MISSING" or (assigned > (tonumber(expected) or 0) and "SURPLUS" or "ALIGNED"),
      })
    end
  end
  table.sort(rows, function(left, right)
    return string.lower(tostring(left.playerName)) < string.lower(tostring(right.playerName))
  end)
  return rows
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
