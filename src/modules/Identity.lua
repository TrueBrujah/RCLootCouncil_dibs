--[[
Module: Dibs.Identity
Layer: Identity / roster boundary
Purpose: Resolve canonical Name-Realm member keys from the current guild roster.
Responsibilities: Deterministic comparison normalization, roster freshness, and
immutable identity snapshots for future authoritative records.
Non-responsibilities: Alias inference, GUID-based remapping, and historical-data rewrites.
Dependencies: Guild roster WoW APIs.
Blizzard events: GUILD_ROSTER_UPDATE is forwarded by Core.
SavedVariables: None directly; reviewed aliases belong to Governance.
]]

local Dibs = _G.Dibs
Dibs.Identity = Dibs.Identity or {}
local Identity = Dibs.Identity

local state = Identity._rosterState or {
  generation = 0,
  fresh = false,
  members = {},
  shortNames = {},
  displayNames = {},
  reason = "ROSTER_NOT_REFRESHED",
}
Identity._rosterState = state
state.displayNames = state.displayNames or {}
state.invalidationGeneration = tonumber(state.invalidationGeneration) or 0

local function copy(value)
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function actorName(value)
  if type(value) == "table" then
    return value.nameRealm or value.displayName or value.name or value.playerName
  end
  if value == nil and Dibs.GetPlayerName then return Dibs.GetPlayerName() end
  return value
end

local function actorGuid(value)
  if type(value) == "table" then return value.guidWitness or value.guid end
  if value == nil and type(UnitGUID) == "function" then return UnitGUID("player") end
  return nil
end

local function normalizeDisplayName(value)
  local display = trim(actorName(value))
  if not display then return nil end
  local name, realm = display:match("^([^%-]+)%-(.+)$")
  if not name or not realm then return display end

  local realmParts = {}
  for part in realm:gmatch("[^%-]+") do realmParts[#realmParts + 1] = part end
  for period = 1, math.floor(#realmParts / 2) do
    local repeated = true
    for index = period + 1, #realmParts do
      if string.lower(realmParts[index]) ~= string.lower(realmParts[((index - 1) % period) + 1]) then
        repeated = false
        break
      end
    end
    if repeated then
      local canonicalRealm = {}
      for index = 1, period do canonicalRealm[index] = realmParts[index] end
      realm = table.concat(canonicalRealm, "-")
      break
    end
  end
  return name .. "-" .. realm
end

local function parseNameRealm(value)
  local sourceDisplay = trim(actorName(value))
  if not sourceDisplay then return nil, nil, "INVALID_IDENTITY" end
  -- A Player GUID is witness data, never a Name-Realm wire identity.
  if sourceDisplay:match("^Player%-%d+%-") then return nil, sourceDisplay, "GUID_IS_NOT_MEMBER_KEY" end
  local name, realm = sourceDisplay:match("^([^%-]+)%-(.+)$")
  name, realm = trim(name), trim(realm)
  if not name or not realm then return nil, sourceDisplay, "SHORT_NAME" end
  local normalizedRealm = realm:gsub("%s+", "")
  if normalizedRealm == "" then return nil, sourceDisplay, "INVALID_IDENTITY" end
  return string.lower(name .. "-" .. normalizedRealm), normalizeDisplayName(sourceDisplay), nil
end

local function shortName(value)
  local display = trim(actorName(value))
  if not display or display:find("-", 1, true) then return nil end
  return string.lower(display)
end

local function rosterMember(name, rankIndex)
  local key, display = parseNameRealm(name)
  if not key then
    -- WoW may return an unqualified name for a same-realm roster member.
    local short = trim(name)
    local realm = type(GetRealmName) == "function" and trim(GetRealmName()) or nil
    if short and realm then key, display = parseNameRealm(short .. "-" .. realm) end
  end
  if not key then return nil end
  rankIndex = tonumber(rankIndex)
  return {
    memberKey = key,
    displayName = display,
    rankIndex = rankIndex,
    -- This is a current-roster observation only. Governance remains GM-only in
    -- B02a; no local SavedVariables rank setting can alter this result.
    role = rankIndex == 0 and "gm" or (rankIndex and rankIndex <= 1 and "officer" or "player"),
  }
end

function Identity.InvalidateRoster(reason)
  state.generation = state.generation + 1
  state.invalidationGeneration = state.invalidationGeneration + 1
  state.fresh = false
  state.members = {}
  state.shortNames = {}
  state.displayNames = {}
  state.reason = reason or "ROSTER_INVALIDATED"
  return state.generation
end

function Identity.GetInvalidationGeneration()
  return state.invalidationGeneration
end

function Identity.OnRosterChanged()
  return Identity.InvalidateRoster("GUILD_ROSTER_UPDATE")
end

function Identity.RefreshRoster()
  if type(IsInGuild) ~= "function" or not IsInGuild() then
    Identity.InvalidateRoster("NOT_IN_GUILD")
    return false, state.reason
  end
  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    Identity.InvalidateRoster("ROSTER_API_UNAVAILABLE")
    return false, state.reason
  end
  local ok, count = pcall(GetNumGuildMembers, true)
  if not ok then
    Identity.InvalidateRoster("ROSTER_COUNT_FAILED")
    return false, state.reason
  end

  local members, shortNames, displayNames = {}, {}, {}
  for index = 1, tonumber(count) or 0 do
    local success, name, _, rankIndex = pcall(GetGuildRosterInfo, index)
    if success and name then
      local member = rosterMember(name, rankIndex)
      if member then
        members[member.memberKey] = member
        local short = string.lower(member.displayName:match("^([^%-]+)"))
        shortNames[short] = shortNames[short] or {}
        table.insert(shortNames[short], member.memberKey)
        local displayKey = string.lower(member.displayName)
        displayNames[displayKey] = displayNames[displayKey] or {}
        table.insert(displayNames[displayKey], member.memberKey)
      end
    end
  end
  for _, candidates in pairs(shortNames) do
    if #candidates > 1 then table.sort(candidates) end
  end
  state.generation = state.generation + 1
  state.fresh = true
  state.members = members
  state.shortNames = shortNames
  state.displayNames = displayNames
  state.reason = nil
  return true, state.generation
end

function Identity.GetRosterState()
  return copy({ generation = state.generation, fresh = state.fresh, reason = state.reason })
end

function Identity.CanonicalMemberKey(value)
  local key = parseNameRealm(value)
  return key
end

function Identity.NormalizeDisplayName(value)
  return normalizeDisplayName(value)
end

function Identity.ResolveRosterMember(value)
  local rosterApisAvailable = type(IsInGuild) == "function"
    and type(GetNumGuildMembers) == "function"
    and type(GetGuildRosterInfo) == "function"
  if not state.fresh or not rosterApisAvailable or not IsInGuild() then
    local refreshed, reason = Identity.RefreshRoster()
    if not refreshed then return { status = "ROSTER_UNAVAILABLE", reason = reason } end
  end

  local key, display, parseReason = parseNameRealm(value)
  if key then
    local member = state.members[key]
    if not member then
      local candidates = state.displayNames[string.lower(display or "")] or {}
      if #candidates > 1 then
        return { status = "AMBIGUOUS_IDENTITY", candidates = copy(candidates), rosterGeneration = state.generation }
      end
      if #candidates == 1 then member = state.members[candidates[1]] end
    end
    if not member then return { status = "UNKNOWN_ROSTER_MEMBER", memberKey = key, displayName = display } end
    return {
      status = "RESOLVED",
      memberKey = member.memberKey,
      displayName = member.displayName,
      rankIndex = member.rankIndex,
      role = member.role,
      rosterGeneration = state.generation,
    }
  end

  if parseReason ~= "SHORT_NAME" then return { status = "UNKNOWN_ROSTER_MEMBER", reason = parseReason } end
  local short = shortName(value)
  local candidates = short and state.shortNames[short] or nil
  if not candidates or #candidates == 0 then return { status = "UNKNOWN_ROSTER_MEMBER" } end
  if #candidates ~= 1 then return { status = "AMBIGUOUS_IDENTITY", candidates = copy(candidates), rosterGeneration = state.generation } end
  local member = state.members[candidates[1]]
  return {
    status = "RESOLVED",
    memberKey = member.memberKey,
    displayName = member.displayName,
    rankIndex = member.rankIndex,
    role = member.role,
    rosterGeneration = state.generation,
  }
end

function Identity.CreateSnapshot(value)
  local resolved = Identity.ResolveRosterMember(value)
  if resolved.status ~= "RESOLVED" then return nil, resolved.status, resolved end
  return {
    memberKey = resolved.memberKey,
    displayName = resolved.displayName,
    guidWitness = actorGuid(value),
    rosterGeneration = resolved.rosterGeneration,
  }
end

function Identity.IsCurrentGuildMaster(value)
  local resolved = Identity.ResolveRosterMember(value)
  if resolved.status ~= "RESOLVED" then return false, resolved.status, resolved end
  if resolved.rankIndex ~= 0 then return false, "CURRENT_GUILD_MASTER_REQUIRED", resolved end
  return true, "CURRENT_GUILD_MASTER", resolved
end

return Identity
