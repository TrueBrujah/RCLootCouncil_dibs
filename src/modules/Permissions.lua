local Dibs = _G.Dibs
Dibs.Permissions = Dibs.Permissions or {}

local function isGuildAvailable()
  return IsInGuild and IsInGuild()
end

function Dibs.Permissions.IsOfficer()
  if not isGuildAvailable() then
    return false
  end

  if IsGuildLeader and IsGuildLeader() then
    return true
  end

  if CanEditOfficerNote and CanEditOfficerNote() then
    return true
  end

  if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then
    return true
  end

  if UnitIsGroupLeader and UnitIsGroupLeader("player") then
    return true
  end

  return false
end

function Dibs.Permissions.IsGM()
  if not isGuildAvailable() then
    return false
  end

  return IsGuildLeader and IsGuildLeader() or false
end

function Dibs.Permissions.CanManageDibs()
  return Dibs.Permissions.IsOfficer() or Dibs.Permissions.IsGM()
end

function Dibs.Permissions.GetRole()
  if Dibs.Permissions.IsGM() then
    return "gm"
  end

  if Dibs.Permissions.IsOfficer() then
    return "officer"
  end

  return "player"
end
