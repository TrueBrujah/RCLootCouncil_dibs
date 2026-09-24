--[[
Module: Dibs.PreDibs
Layer: Domain / request workflow
Purpose: Manage player item requests before an encounter and their lifecycle.
Responsibilities: Validation, confirmation, sync upserts, fulfillment, and display-only Vault records.
Non-responsibilities: A request does not select a winner or transfer an item.
Dependencies: Ledger, Seasons, Permissions, Sync, EncounterJournal.
Blizzard events: None directly; announcement transport uses WoW chat APIs.
Internal events/messages: Sends configured public/officer announcements through chat.
SavedVariables: db.preDibs requests, modePolicies, acquisitions; db.settings announcement templates.
RCLootCouncil: Request context may be projected into RC voting.
Combat safety: Chat/data operations are separated from protected UI actions.
Invariants: DIBS-RULE-002, DIBS-RULE-003, DIBS-RULE-005.
Related docs: docs/developer/data-model.md, docs/player/README.md.
]]

local Dibs = _G.Dibs
Dibs.PreDibs = Dibs.PreDibs or {}

local function requirePreDibsEnabled()
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.RequireModuleEnabled then
    return Dibs.OperationalPolicy.RequireModuleEnabled("preDibs")
  end
  return true
end

local VALID_ANNOUNCE_CHANNELS = {
  NONE = true,
  GUILD = true,
  OFFICER = true,
  RAID = true,
  RAID_WARNING = true,
  RAID_DIBS = true,
  PARTY = true,
  INSTANCE_CHAT = true,
  SAY = true,
  YELL = true,
}

local function normalizeChannel(value, fallback)
  local key = string.upper(tostring(value or ""))
  if VALID_ANNOUNCE_CHANNELS[key] then
    return key
  end
  return fallback or "NONE"
end

local function announcementDebug(message)
  if Dibs.PreDibs.announcementDebug and Dibs.DebugEnabled and Dibs.DebugEnabled("announce", 4) and Dibs.Message then
    Dibs.Message("[Announcement Debug] " .. tostring(message))
  end
end

local DEFAULT_PREDIB_TEMPLATE = "[Dibs] %player requested %item (%difficulty) - %date %time"
local DEFAULT_REMINDER_TEMPLATE = "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]"

local function isRaidDibsChannelAvailable()
  local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  return clubId ~= nil and streamId ~= nil
end

function Dibs.PreDibs.GetRaidDibsChannel()
  local clubs = _G.C_Club
  if type(clubs) ~= "table" or type(clubs.GetSubscribedClubs) ~= "function" or type(clubs.GetStreams) ~= "function" then
    announcementDebug("C_Club API incomplet: GetSubscribedClubs/GetStreams manquant")
    return nil
  end
  local ok, subscribed = pcall(clubs.GetSubscribedClubs)
  if not ok or type(subscribed) ~= "table" then
    announcementDebug("GetSubscribedClubs a echoue ou n'a pas renvoye une table")
    return nil
  end
  local clubCount = 0
  for clubKey, club in pairs(subscribed) do
    clubCount = clubCount + 1
    local clubId
    if type(club) == "table" then
      clubId = club.clubId or club.clubID or club.clubIdentifier
    else
      clubId = club
    end
    if not clubId and (type(clubKey) == "number" or type(clubKey) == "string") then
      clubId = clubKey
    end
    announcementDebug("club[" .. tostring(clubKey) .. "] id=" .. tostring(clubId))
    local streamClubId = tostring(clubId or "")
    local streamOk, streams = pcall(clubs.GetStreams, streamClubId)
    announcementDebug("GetStreams(" .. streamClubId .. ") ok=" .. tostring(streamOk) .. " type=" .. type(streams))
    if streamOk and type(streams) == "table" then
      for streamKey, stream in pairs(streams) do
        local streamId = type(stream) == "table" and (stream.streamId or stream.streamID) or streamKey
        local streamName = type(stream) == "table" and (stream.name or stream.streamName) or stream
        streamName = string.lower(tostring(streamName or "")):match("^%s*(.-)%s*$")
        announcementDebug(" stream[" .. tostring(streamKey) .. "] id=" .. tostring(streamId) .. " name=" .. tostring(streamName))
        if streamId and streamName == "raid dibs" then
          announcementDebug("MATCH clubId=" .. tostring(clubId) .. " streamId=" .. tostring(streamId))
          return clubId, streamId
        end
      end
    end
  end
  announcementDebug("aucun stream Raid Dibs trouve; clubs inspectes=" .. tostring(clubCount))
  return nil
end

function Dibs.PreDibs.SetAnnouncementDebug(enabled, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  Dibs.PreDibs.announcementDebug = enabled == true
  return Dibs.PreDibs.announcementDebug, nil
end

function Dibs.PreDibs.DebugRaidDibs()
  local previous = Dibs.PreDibs.announcementDebug
  Dibs.PreDibs.announcementDebug = true
  local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  Dibs.Message("[Announcement Debug] resultat clubId=" .. tostring(clubId) .. " streamId=" .. tostring(streamId))
  Dibs.PreDibs.announcementDebug = previous
  return clubId, streamId
end

local function ensureRaidDibsChannel()
  local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  if clubId and streamId then return clubId, streamId end
  return nil, "RAID_DIBS_UNAVAILABLE"
end

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.preDibs = Dibs.db.preDibs or { requests = {} }
  Dibs.db.preDibs.requests = Dibs.db.preDibs.requests or {}
  Dibs.db.preDibs.modePolicies = Dibs.db.preDibs.modePolicies or {}
  Dibs.db.preDibs.acquisitions = Dibs.db.preDibs.acquisitions or {}
  Dibs.db.preDibs.vaultConflicts = Dibs.db.preDibs.vaultConflicts or {}
  Dibs.db.settings = Dibs.db.settings or {}
  if Dibs.db.settings.allowPublicPreDibs == nil then
    Dibs.db.settings.allowPublicPreDibs = true
  end
  Dibs.db.settings.preDibAnnouncementChannel = normalizeChannel(Dibs.db.settings.preDibAnnouncementChannel, "GUILD")
  Dibs.db.settings.preDibOfficerAnnouncementChannel = normalizeChannel(Dibs.db.settings.preDibOfficerAnnouncementChannel, "OFFICER")
  if Dibs.db.settings.preDibAnnouncementTemplate == nil then
    Dibs.db.settings.preDibAnnouncementTemplate = DEFAULT_PREDIB_TEMPLATE
  end
  if Dibs.db.settings.raidReminderTemplate == nil then
    Dibs.db.settings.raidReminderTemplate = Dibs.db.settings.raidReminderMessage or DEFAULT_REMINDER_TEMPLATE
  end
end

local VALID_MODES = { WILD_OPEN = true, ENCOUNTER = true }
local DIFFICULTY_NAMES = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
local function formatDateTime(format, timestamp)
  if type(date) == "function" then
    return date(format, timestamp)
  end
  return tostring(timestamp or time())
end

local function templateValue(value)
  return tostring(value == nil and "" or value)
end

function Dibs.PreDibs.FormatAnnouncement(template, context)
  local value = tostring(template or "")
  local data = type(context) == "table" and context or {}
  local now = time()
  local values = {
    player = data.playerName or data.player or Dibs.GetPlayerName and Dibs.GetPlayerName() or "Unknown",
    item = data.itemName or (data.itemID and ("Item " .. tostring(data.itemID)) or "Unknown item"),
    itemID = data.itemID,
    difficulty = data.difficulty or "Unknown",
    mode = data.modeAtCreation or data.mode or "WILD_OPEN",
    status = data.status or "confirmed",
    season = data.seasonName or data.seasonId or "Unknown season",
    date = data.date or formatDateTime("%Y-%m-%d", now),
    time = data.time or formatDateTime("%H:%M:%S", now),
    requestID = data.requestId,
    source = data.source or "Pre-Dib",
    channel = data.channel or "",
  }
  return (value:gsub("%%([%w_]+)", function(key)
    if values[key] == nil then return "%" .. key end
    return templateValue(values[key])
  end))
end

function Dibs.PreDibs.NormalizeDifficulty(value)
  local numeric = tonumber(value)
  if numeric and DIFFICULTY_NAMES[numeric] then return DIFFICULTY_NAMES[numeric] end
  local label = string.lower(tostring(value or ""))
  if label == "normal" then return "Normal" end
  if label == "heroic" then return "Heroic" end
  if label == "mythic" then return "Mythic" end
  return "UNKNOWN"
end

local function samePlayer(first, second)
  if Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId then
    local firstId = Dibs.Permissions.CanonicalPlayerId(first)
    local secondId = Dibs.Permissions.CanonicalPlayerId(second)
    if firstId and secondId then
      return firstId == secondId
    end
  end
  return string.lower(tostring(first or "")) == string.lower(tostring(second or ""))
end

local function copy(value)
  if Dibs.DeepCopy then return Dibs.DeepCopy(value) end
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

---@param value DibsVaultAcquisition
---@return DibsVaultAcquisition
local function copyVaultAcquisition(value)
  local result = Dibs.DeepCopy and Dibs.DeepCopy(value) or copy(value)
  ---@cast result DibsVaultAcquisition
  return result
end

local function requestContext(context)
  local value = type(context) == "table" and context or {}
  return {
    inRaid = value.inRaid == true,
    raidId = value.raidId or value.instanceId,
    itemRaidId = value.itemRaidId or value.raidId,
    isSupportedRaidLoot = value.isSupportedRaidLoot ~= false,
    source = value.source,
    difficulty = Dibs.PreDibs.NormalizeDifficulty(value.difficulty),
  }
end

local function ensureRuntimeState()
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.dev = Dibs.runtime.dev or {}
  Dibs.runtime.dev.requests = Dibs.runtime.dev.requests or {}
end

local function isChannelAvailable(channel)
  if channel == "NONE" then return false end
  if channel == "GUILD" or channel == "OFFICER" then
    return type(IsInGuild) == "function" and IsInGuild() == true
  end
  if channel == "RAID" then
    return type(IsInRaid) == "function" and IsInRaid() == true
  end
  if channel == "RAID_WARNING" then
    if type(IsInRaid) ~= "function" or IsInRaid() ~= true then return false end
    local isLeader = type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player") == true
    local isAssistant = type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player") == true
    return isLeader or isAssistant
  end
  if channel == "PARTY" then
    local inGroup = type(IsInGroup) == "function" and IsInGroup() == true
    local inRaid = type(IsInRaid) == "function" and IsInRaid() == true
    return inGroup and not inRaid
  end
  if channel == "INSTANCE_CHAT" then
    if type(IsInGroup) ~= "function" then return false end
    return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) == true
  end
  if channel == "RAID_DIBS" then
    return isRaidDibsChannelAvailable()
  end
  return true
end

local function sendAnnouncement(channel, message, raidDibsInfo)
  local normalized = normalizeChannel(channel, "NONE")
  announcementDebug("send channel=" .. tostring(channel) .. " normalized=" .. tostring(normalized))
  local ok
  if normalized == "RAID_DIBS" then
    local clubId = raidDibsInfo and raidDibsInfo.clubId
    local streamId = raidDibsInfo and raidDibsInfo.streamId
    if not clubId or not streamId then
      clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
    end
    if not clubId or not streamId then
      announcementDebug("aucun club/stream resolu")
      return false, "RAID_DIBS_NOT_JOINED"
    end
    local api = _G.C_Club
    if type(api) ~= "table" or type(api.SendMessage) ~= "function" then
      announcementDebug("C_Club.SendMessage manquant")
      return false, "CLUB_API_UNAVAILABLE"
    end
    local callOk, result = pcall(api.SendMessage, clubId, streamId, tostring(message))
    announcementDebug("C_Club.SendMessage(" .. tostring(clubId) .. ", " .. tostring(streamId) .. ") ok=" .. tostring(callOk) .. " retour=" .. tostring(result))
    ok = callOk
  else
    if not isChannelAvailable(normalized) then
      announcementDebug("canal indisponible avant envoi")
      return false, "CHANNEL_UNAVAILABLE"
    end
    if type(SendChatMessage) ~= "function" then return false, "CHAT_API_UNAVAILABLE" end
    announcementDebug("SendChatMessage canal=" .. tostring(normalized))
    ok = pcall(SendChatMessage, tostring(message), normalized)
  end
  return ok == true, ok == true and nil or "CHAT_SEND_FAILED"
end

function Dibs.PreDibs.SendTestAnnouncement(channel, audience, actor)
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsModuleEnabled
    and Dibs.OperationalPolicy.IsModuleEnabled("announcements") ~= true then
    return false, "MODULE_DISABLED_ANNOUNCEMENTS"
  end
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return false, "GUILD_ADMIN_REQUIRED"
  end
  ensureState()
  local normalized = normalizeChannel(channel, "NONE")
  announcementDebug("bouton test audience=" .. tostring(audience) .. " channel=" .. tostring(channel) .. " normalized=" .. tostring(normalized))
  local raidDibsInfo
  if normalized == "RAID_DIBS" then
    local clubId, streamIdOrReason = ensureRaidDibsChannel()
    if not clubId then return false, streamIdOrReason end
    raidDibsInfo = { clubId = clubId, streamId = streamIdOrReason }
  end
  local message = Dibs.PreDibs.FormatAnnouncement(
    Dibs.db.settings.preDibAnnouncementTemplate or DEFAULT_PREDIB_TEMPLATE,
    {
      playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or "Player-Realm",
      itemName = "Example item",
      itemID = 12345,
      difficulty = "Mythic",
      modeAtCreation = "WILD_OPEN",
      status = "confirmed",
      source = tostring(audience or "Announcement") .. " channel test",
    }
  )
  return sendAnnouncement(normalized, "[Dibs Test] " .. message, raidDibsInfo)
end

local function buildAnnouncementMessage(request)
  ensureState()
  local template = Dibs.db.settings.preDibAnnouncementTemplate or DEFAULT_PREDIB_TEMPLATE
  return Dibs.PreDibs.FormatAnnouncement(template, request)
end

local function announcePreDib(request)
  ensureState()
  if type(request) ~= "table" then return end
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsModuleEnabled
    and Dibs.OperationalPolicy.IsModuleEnabled("announcements") ~= true then return end
  local message = buildAnnouncementMessage(request)
  local settings = Dibs.PreDibs.GetAnnouncementSettings()
  local publicChannel, officerChannel = settings.publicChannel, settings.officerChannel
  local sent = {}
  if publicChannel ~= "NONE" and not sent[publicChannel] then
    sendAnnouncement(publicChannel, message)
    sent[publicChannel] = true
  end
  if officerChannel ~= "NONE" and not sent[officerChannel] then
    sendAnnouncement(officerChannel, message)
    sent[officerChannel] = true
  end
end

local function isRequestActive(request)
  return request.status ~= "fulfilled" and request.status ~= "cancelled" and request.status ~= "invalidated"
end

local VALID_STATUS_TRANSITIONS = {
  pending = { confirmed = true, cancelled = true, invalidated = true },
  confirmed = { cancelled = true, invalidated = true, fulfilled = true },
}

local function findActiveRequest(playerName, itemID, seasonId, difficulty)
  local targetPlayer = tostring(playerName or Dibs.GetPlayerName())
  local targetItem = tonumber(itemID) or 0
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local targetDifficulty = Dibs.PreDibs.NormalizeDifficulty(difficulty)
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if tonumber(request.itemID) == targetItem
      and tostring(request.playerName or "") == targetPlayer
      and request.seasonId == targetSeason
      and Dibs.PreDibs.NormalizeDifficulty(request.difficulty) == targetDifficulty
      and isRequestActive(request)
    then
      return request
    end
  end
  return nil
end

function Dibs.PreDibs.IsPublicEnabled()
  ensureState()
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted()
    and Dibs.OperationalPolicy.GetPublicPreDibsEnabled then
    local shared = Dibs.OperationalPolicy.GetPublicPreDibsEnabled()
    if shared ~= nil then return shared end
  end
  return Dibs.db.settings.allowPublicPreDibs ~= false
end

function Dibs.PreDibs.GetModePolicy(seasonId)
  ensureState()
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted()
    and Dibs.OperationalPolicy.GetPreDibMode then
    local sharedMode = Dibs.OperationalPolicy.GetPreDibMode(targetSeason)
    if sharedMode then return { seasonId = targetSeason, mode = sharedMode, source = "OPERATIONAL_POLICY" } end
  end
  local policy = targetSeason and Dibs.db.preDibs.modePolicies[targetSeason] or nil
  if type(policy) ~= "table" then
    return { seasonId = targetSeason, mode = "WILD_OPEN" }
  end
  return policy
end

function Dibs.PreDibs.SetModePolicy(seasonId, mode, actor)
  ensureState()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local normalized = string.upper(tostring(mode or ""))
  if not targetSeason then return nil, "NO_ACTIVE_SEASON" end
  if not VALID_MODES[normalized] then return nil, "INVALID_PREDIB_MODE" end
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted()
    and Dibs.OperationalPolicy.SetPreDibMode then
    local applied, reason, record = Dibs.OperationalPolicy.SetPreDibMode(targetSeason, normalized, actor)
    if not applied then return nil, reason end
    return { seasonId = targetSeason, mode = normalized, changedAt = record.timestamp, changedBy = record.authorNameRealm, policyRevision = record.policyRevision, source = "OPERATIONAL_POLICY" }
  end
  local policy = { seasonId = targetSeason, mode = normalized, changedAt = time(), changedBy = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "Unknown") }
  Dibs.db.preDibs.modePolicies[targetSeason] = policy
  return policy
end

---@param itemID integer Item identifier.
---@param seasonId string Season scope.
---@param context table|nil Encounter, difficulty, and eligibility context.
---@return boolean|nil accepted
---@return string|nil reasonCode
---@return table|nil policy
---@return table|nil validation Normalized request context when accepted.
function Dibs.PreDibs.ValidatePublicRequest(itemID, seasonId, context)
  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then return nil, "INVALID_ITEM" end
  local policy = Dibs.PreDibs.GetModePolicy(seasonId)
  local validation = requestContext(context)
  if validation.isSupportedRaidLoot ~= true then return nil, "UNSUPPORTED_RAID_LOOT", policy, validation end
  if policy.mode == "ENCOUNTER" then
    if validation.inRaid ~= true then return nil, "ENCOUNTER_REQUIRES_RAID", policy, validation end
    if not validation.raidId or validation.raidId ~= validation.itemRaidId then return nil, "ENCOUNTER_RAID_MISMATCH", policy, validation end
  end
  return true, nil, policy, validation
end

function Dibs.PreDibs.GetAnnouncementSettings()
  ensureState()
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted()
    and Dibs.OperationalPolicy.GetAnnouncementChannels then
    local shared = Dibs.OperationalPolicy.GetAnnouncementChannels()
    if shared then
      return {
        publicChannel = normalizeChannel(shared.publicChannel, "GUILD"),
        officerChannel = normalizeChannel(shared.officerChannel, "OFFICER"),
      }
    end
  end
  return {
    publicChannel = normalizeChannel(Dibs.db.settings.preDibAnnouncementChannel, "GUILD"),
    officerChannel = normalizeChannel(Dibs.db.settings.preDibOfficerAnnouncementChannel, "OFFICER"),
  }
end

function Dibs.PreDibs.SetAnnouncementChannels(publicChannel, officerChannel, actor)
  ensureState()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local publicValue, officerValue = normalizeChannel(publicChannel, "GUILD"), normalizeChannel(officerChannel, "OFFICER")
  if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted()
    and Dibs.OperationalPolicy.SetAnnouncementChannels then
    local applied, reason = Dibs.OperationalPolicy.SetAnnouncementChannels(publicValue, officerValue, actor)
    if not applied then return nil, reason end
    return Dibs.PreDibs.GetAnnouncementSettings()
  end
  Dibs.db.settings.preDibAnnouncementChannel = publicValue
  Dibs.db.settings.preDibOfficerAnnouncementChannel = officerValue
  return Dibs.PreDibs.GetAnnouncementSettings()
end

function Dibs.PreDibs.GetAnnouncementTemplates()
  ensureState()
  return {
    preDib = tostring(Dibs.db.settings.preDibAnnouncementTemplate or DEFAULT_PREDIB_TEMPLATE),
    reminder = tostring(Dibs.db.settings.raidReminderTemplate or DEFAULT_REMINDER_TEMPLATE),
  }
end

function Dibs.PreDibs.SetAnnouncementTemplates(preDibTemplate, reminderTemplate, actor)
  ensureState()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  if preDibTemplate ~= nil then
    Dibs.db.settings.preDibAnnouncementTemplate = tostring(preDibTemplate)
  end
  if reminderTemplate ~= nil then
    Dibs.db.settings.raidReminderTemplate = tostring(reminderTemplate)
    Dibs.db.settings.raidReminderMessage = tostring(reminderTemplate)
  end
  return Dibs.PreDibs.GetAnnouncementTemplates()
end

function Dibs.PreDibs.Create(playerName, itemID, itemName, seasonId)
  ensureState()
  local enabled, reason = requirePreDibsEnabled()
  if not enabled then return nil, reason end
  if not tonumber(itemID) or tonumber(itemID) <= 0 then return nil end

  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  if targetSeason == nil or targetSeason == "" then
    return nil, "NO_ACTIVE_SEASON"
  end

  local request = {
    requestId = Dibs.NewId("predib"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = tonumber(itemID) or 0,
    itemName = itemName or "Unknown item",
    seasonId = targetSeason,
    status = "pending",
    createdAt = time(),
    updatedAt = time(),
    difficulty = "UNKNOWN",
  }

  table.insert(Dibs.db.preDibs.requests, request)
  return request
end

---@param playerName string|nil Request owner; defaults to local player.
---@param itemID integer Item identifier.
---@param itemName string|nil Display name captured for the request.
---@param seasonId string|nil Season scope; defaults to active season.
---@param source string|nil Request source label.
---@param context table|nil Encounter/difficulty context.
---@return DibsPreDibRequest|nil request
---@return string|nil reasonCode
-- Side effects: Persists/updates a confirmed request and may send configured announcements.
function Dibs.PreDibs.CreatePublic(playerName, itemID, itemName, seasonId, source, context)
  ensureState()
  local enabled, reason = requirePreDibsEnabled()
  if not enabled then return nil, reason end
  if Dibs.PreDibs.IsPublicEnabled() ~= true then
    return nil, "PUBLIC_PRE_DIBS_DISABLED"
  end

  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then
    return nil, "INVALID_ITEM"
  end

  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  if targetSeason == nil or targetSeason == "" then
    return nil, "NO_ACTIVE_SEASON"
  end

  local accepted, validationReason, policy, validation = Dibs.PreDibs.ValidatePublicRequest(targetItem, targetSeason, context)
  if accepted ~= true then return nil, validationReason end

  local existing = findActiveRequest(playerName, targetItem, targetSeason, validation.difficulty)
  if existing then
    if existing.status ~= "confirmed" then
      existing.status = "confirmed"
      existing.confirmedAt = time()
      existing.updatedAt = existing.confirmedAt
      existing.revision = (tonumber(existing.revision) or 1) + 1
      existing.source = source or existing.source or "public"
      announcePreDib(existing)
    end
    return existing
  end

  local now = time()
  local request = {
    requestId = Dibs.NewId("predib"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = targetItem,
    itemName = itemName or ("Item " .. tostring(targetItem)),
    seasonId = targetSeason,
    status = "confirmed",
    source = source or "public",
    createdAt = now,
    updatedAt = now,
    confirmedAt = now,
    revision = 1,
    modeAtCreation = policy.mode,
    validationContext = validation,
    difficulty = validation.difficulty,
    delivery = { state = "PENDING" },
  }

  table.insert(Dibs.db.preDibs.requests, request)
  announcePreDib(request)
  return request
end

function Dibs.PreDibs.CreateTest(playerName, itemID, itemName, seasonId, source, context)
  ensureState()
  ensureRuntimeState()

  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then
    return nil, "INVALID_ITEM"
  end

  local now = time()
  local request = {
    requestId = Dibs.NewId("predibtest"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = targetItem,
    itemName = itemName or ("Item " .. tostring(targetItem)),
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
    status = "confirmed",
    source = source or "DEV",
    isTest = true,
    createdAt = now,
    updatedAt = now,
    confirmedAt = now,
    context = context,
  }

  table.insert(Dibs.runtime.dev.requests, request)
  return request
end

function Dibs.PreDibs.GetTestHistory()
  ensureRuntimeState()
  return Dibs.runtime.dev.requests
end

---@param requestId string Stable request ID.
---@param status DibsRequestStatus New lifecycle status.
---@return DibsPreDibRequest|nil request
---@return string|nil reasonCode
-- Side effects: Advances a request revision and records lifecycle timestamps.
function Dibs.PreDibs.UpdateStatus(requestId, status)
  local enabled, reason = requirePreDibsEnabled()
  if not enabled then return nil, reason end
  ensureState()

  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId then
      if VALID_STATUS_TRANSITIONS[request.status] == nil
        or VALID_STATUS_TRANSITIONS[request.status][status] ~= true
      then
        return nil, "INVALID_STATUS_TRANSITION"
      end
      request.status = status
      request.updatedAt = time()
      request.revision = (tonumber(request.revision) or 1) + 1
      if status == "confirmed" and request.confirmedAt == nil then
        request.confirmedAt = request.updatedAt
        announcePreDib(request)
      elseif status == "fulfilled" and request.fulfilledAt == nil then
        request.fulfilledAt = request.updatedAt
      elseif status == "cancelled" and request.cancelledAt == nil then
        request.cancelledAt = request.updatedAt
      end
      if Dibs.Notifications and Dibs.Notifications.Notify then
        local kind = status == "confirmed" and "PREDIB_CONFIRMED"
          or status == "cancelled" and "PREDIB_CANCELLED"
          or status == "fulfilled" and "REQUEST_RESOLVED"
        if kind then
          Dibs.Notifications.Notify("request:" .. tostring(request.requestId) .. ":" .. tostring(request.revision), kind, request)
        end
      end
      return request
    end
  end

  return nil
end

---@param incoming DibsPreDibRequest|table Validated synchronized request.
---@param senderName string|nil Sender identity used for owner checks.
---@return DibsPreDibRequest|nil request
---@return string|nil reasonCode
-- Side effects: Applies only newer, owner-matching request revisions.
function Dibs.PreDibs.UpsertFromSync(incoming, senderName)
  ensureState()
  local incomingItemId = type(incoming) == "table" and tonumber(incoming.itemID) or nil
  local incomingRevision = type(incoming) == "table" and (incoming.revision == nil and 1 or tonumber(incoming.revision)) or nil
  if type(incoming) ~= "table" or type(incoming.requestId) ~= "string" or #incoming.requestId < 1 or #incoming.requestId > 96
    or type(incoming.playerName) ~= "string" or #incoming.playerName < 1 or #incoming.playerName > 96
    or not incomingItemId or incomingItemId <= 0 or math.floor(incomingItemId) ~= incomingItemId
    or (type(incoming.seasonId) ~= "string" and type(incoming.seasonId) ~= "number")
    or not incomingRevision or incomingRevision < 1 or incomingRevision > 1000000 or math.floor(incomingRevision) ~= incomingRevision then
    return nil, "INVALID_REQUEST"
  end
  local validIncomingStatus = incoming.status == "pending" or incoming.status == "confirmed"
    or incoming.status == "cancelled" or incoming.status == "invalidated"
  if type(incoming.status) ~= "string" or not validIncomingStatus then
    return nil, "INVALID_STATUS"
  end
  if senderName and not samePlayer(senderName, incoming.playerName) then
    return nil, "OWNER_MISMATCH"
  end
  if incoming.status == "fulfilled" then return nil, "UNTRUSTED_FULFILLMENT" end
  for _, existing in ipairs(Dibs.db.preDibs.requests) do
    if existing.requestId == incoming.requestId then
      if incomingRevision <= (tonumber(existing.revision) or 1) then return nil, "STALE_REVISION" end
      if not samePlayer(existing.playerName, incoming.playerName) then
        return nil, "IMMUTABLE_FIELD_MISMATCH"
      end
      if existing.status ~= incoming.status and (not VALID_STATUS_TRANSITIONS[existing.status] or VALID_STATUS_TRANSITIONS[existing.status][incoming.status] ~= true) then
        return nil, "INVALID_STATUS_TRANSITION"
      end
       for key, value in pairs(incoming) do
         if key ~= "playerName" and key ~= "itemID" and key ~= "seasonId" and key ~= "modeAtCreation"
           and key ~= "createdAt" and key ~= "delivery" then existing[key] = value end
      end
      return existing
    end
  end
  if incoming.status ~= "pending" and incoming.status ~= "confirmed" then
    return nil, "MISSING_ORIGINAL_REQUEST"
  end
  incoming.revision = incomingRevision
  -- Delivery acknowledgement is local officer metadata; an owner-supplied
  -- sync record can never claim that an officer received it.
  incoming.delivery = { state = "PENDING" }
  table.insert(Dibs.db.preDibs.requests, incoming)
  return incoming
end

-- B04 calls this only after the V2 transport has authenticated the complete
-- transfer envelope, owner or officer relay, revision, and content hash. Unlike the legacy
-- helper above, it retains terminal lifecycle records as bounded sync
-- tombstone evidence so a stale client can learn cancellation/invalidation/
-- fulfillment even when it never saw the active revision.
function Dibs.PreDibs.ApplyVerifiedSyncRecord(incoming, senderName)
  ensureState()
  local revision = type(incoming) == "table" and tonumber(incoming.revision) or nil
  local itemID = type(incoming) == "table" and tonumber(incoming.itemID) or nil
  local allowed = incoming and (incoming.status == "pending" or incoming.status == "confirmed" or incoming.status == "cancelled" or incoming.status == "invalidated" or incoming.status == "fulfilled")
  if type(incoming) ~= "table" or type(incoming.requestId) ~= "string" or #incoming.requestId < 1 or #incoming.requestId > 96
    or type(incoming.playerName) ~= "string" or not itemID or itemID <= 0 or itemID ~= math.floor(itemID)
    or (type(incoming.seasonId) ~= "string" and type(incoming.seasonId) ~= "number")
    or not revision or revision < 1 or revision > 1000000 or revision ~= math.floor(revision) or not allowed
  then return nil, "INVALID_REQUEST" end
  if senderName and not samePlayer(senderName, incoming.playerName) then
    local senderRole = Dibs.Permissions and Dibs.Permissions.GetGuildRole and Dibs.Permissions.GetGuildRole(senderName)
    local recipientRole = Dibs.Permissions and Dibs.Permissions.GetGuildRole and Dibs.Permissions.GetGuildRole(nil)
    local senderIsOfficer = senderRole == "gm" or senderRole == "officer"
    local recipientIsOfficer = recipientRole == "gm" or recipientRole == "officer"
    if not senderIsOfficer or not recipientIsOfficer then return nil, "OWNER_MISMATCH" end
  end
  for _, existing in ipairs(Dibs.db.preDibs.requests) do
    if existing.requestId == incoming.requestId then
      local current = tonumber(existing.revision) or 1
      if revision <= current then return nil, "STALE_REVISION" end
      if not samePlayer(existing.playerName, incoming.playerName) or tonumber(existing.itemID) ~= itemID or existing.seasonId ~= incoming.seasonId then return nil, "IMMUTABLE_FIELD_MISMATCH" end
      if existing.status ~= incoming.status and (not VALID_STATUS_TRANSITIONS[existing.status] or VALID_STATUS_TRANSITIONS[existing.status][incoming.status] ~= true) then return nil, "INVALID_STATUS_TRANSITION" end
      for key, value in pairs(incoming) do
        if key ~= "playerName" and key ~= "itemID" and key ~= "seasonId" and key ~= "modeAtCreation" and key ~= "createdAt" and key ~= "delivery" then existing[key] = value end
      end
      return existing
    end
  end
  local record = Dibs.DeepCopy and Dibs.DeepCopy(incoming) or incoming
  record.revision = revision
  record.delivery = { state = "PENDING" }
  table.insert(Dibs.db.preDibs.requests, record)
  return record
end

function Dibs.PreDibs.AcknowledgeDelivery(requestId, revision, officerName)
  ensureState()
  local numericRevision = tonumber(revision)
  if type(requestId) ~= "string" or #requestId < 1 or #requestId > 96
    or not numericRevision or numericRevision < 1 or numericRevision > 1000000 or math.floor(numericRevision) ~= numericRevision then
    return nil, "INVALID_REVISION"
  end
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local role = Dibs.Permissions.GetGuildRole(officerName)
  if role ~= "gm" and role ~= "officer" then return nil, "GUILD_ADMIN_REQUIRED" end
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId and numericRevision <= (tonumber(request.revision) or 1) then
      request.delivery = { state = "ACKNOWLEDGED", lastAcknowledgedRevision = numericRevision, acknowledgedBy = officerName, acknowledgedAt = time() }
      return request
    end
  end
  return nil, "UNKNOWN_REQUEST"
end

---@param requestId string Stable request ID.
---@return DibsPreDibRequest|nil request
function Dibs.PreDibs.Confirm(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "confirmed")
end

function Dibs.PreDibs.Cancel(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "cancelled")
end

function Dibs.PreDibs.CancelForPlayer(requestId, playerName)
  ensureState()
  local enabled, reason = requirePreDibsEnabled()
  if not enabled then return nil, reason end
  local player = playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId then
      if not samePlayer(request.playerName, player) then
        return nil, "NOT_REQUEST_OWNER"
      end
      if not isRequestActive(request) then
        return nil, "INVALID_STATUS_TRANSITION"
      end
      return Dibs.PreDibs.Cancel(requestId)
    end
  end
  return nil, "UNKNOWN_REQUEST"
end

function Dibs.PreDibs.Invalidate(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "invalidated")
end

---@param requestId string Stable request ID.
---@return DibsPreDibRequest|nil request
function Dibs.PreDibs.Fulfill(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "fulfilled")
end

function Dibs.PreDibs.GetActiveRequests(playerName)
  ensureState()
  local active = {}
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.playerName == (playerName or Dibs.GetPlayerName()) and isRequestActive(request) then
      table.insert(active, request)
    end
  end
  return active
end

function Dibs.PreDibs.GetRequestsForItem(itemID)
  ensureState()
  local list = {}
  local targetItem = tonumber(itemID) or 0
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if tonumber(request.itemID) == targetItem then
      table.insert(list, request)
    end
  end
  return list
end

function Dibs.PreDibs.GetConfirmedRequestForPlayer(playerName, itemID, seasonId, difficulty)
  ensureState()
  local targetPlayer = playerName or Dibs.GetPlayerName()
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local requests = Dibs.PreDibs.GetRequestsForItem(itemID)
  for _, request in ipairs(requests) do
    if samePlayer(request.playerName, targetPlayer)
      and request.seasonId == targetSeason
      and request.status == "confirmed"
      and (difficulty == nil or Dibs.PreDibs.NormalizeDifficulty(request.difficulty) == Dibs.PreDibs.NormalizeDifficulty(difficulty))
    then
      return request
    end
  end
  return nil
end

---@param playerName string|nil Character/player identity.
---@param itemID integer Item identifier.
---@param difficulty DibsDifficulty|nil Difficulty context.
---@param options table|nil Evidence and reset metadata.
---@return DibsVaultAcquisition|nil acquisition
---@return string|nil reasonCode
-- Side effects: Persists a display-only acquisition; it never consumes a Dib.
function Dibs.PreDibs.RecordVaultAcquisition(playerName, itemID, difficulty, options)
  ensureState()
  local enabled, reason = requirePreDibsEnabled()
  if not enabled then return nil, reason end
  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then return nil, "INVALID_ITEM" end
  local player = playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  if not player or player == "" then return nil, "INVALID_PLAYER" end
  options = type(options) == "table" and options or {}
  local normalizedDifficulty = Dibs.PreDibs.NormalizeDifficulty(difficulty)
  local guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or nil
  local characterId = options.characterId
  local localPlayer = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
  if not characterId and localPlayer and tostring(player):lower() == tostring(localPlayer):lower() and type(UnitGUID) == "function" then
    characterId = UnitGUID("player")
  end
  if not characterId and Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId then
    characterId = Dibs.Permissions.CanonicalPlayerId(player)
  end
  local source = options.source or "VAULT_MANUAL"
  if source == "VAULT" then source = "VAULT_MANUAL" end
  local verificationState = options.verificationState
  if not verificationState then
    verificationState = source == "GREAT_VAULT" and "UNVERIFIED" or "MANUAL_RECORDED"
  end
  local evidenceState = options.evidenceState or (source == "GREAT_VAULT" and "PARTIAL" or "MISSING")
  local resetId = options.resetId and tostring(options.resetId) or nil
  local seasonId = options.seasonId
  if seasonId == nil and Dibs.GetCurrentSeasonId then seasonId = Dibs.GetCurrentSeasonId() end
  local claimedAt = tonumber(options.claimedAt) or time()
  local createdAt = tonumber(options.createdAt) or time()
  local acquisitionKey = table.concat({
    tostring(guildKey or ""), tostring(player), tostring(characterId or ""),
    tostring(seasonId or ""), tostring(resetId or "no-reset"), tostring(targetItem),
    tostring(normalizedDifficulty), tostring(options.claimId or options.evidenceId or source),
  }, "|")
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    local existingKey = record.acquisitionKey
    if not existingKey then
      existingKey = table.concat({
        tostring(record.guildKey or guildKey or ""), tostring(record.playerName or ""),
        tostring(record.characterId or characterId or ""), tostring(record.seasonId or ""),
        tostring(record.resetId or "no-reset"), tostring(record.itemID or ""),
        tostring(Dibs.PreDibs.NormalizeDifficulty(record.difficulty)),
        tostring(record.evidenceId or record.source or "VAULT_MANUAL"),
      }, "|")
      record.acquisitionKey = existingKey
    end
    if existingKey == acquisitionKey or (samePlayer(record.playerName, player)
      and tonumber(record.itemID) == targetItem and record.source ~= "RCLootCouncil"
      and Dibs.PreDibs.NormalizeDifficulty(record.difficulty) == normalizedDifficulty
      and tostring(record.resetId or "no-reset") == tostring(resetId or "no-reset")
      and tostring(record.seasonId or "") == tostring(seasonId or "")) then
      if source == "GREAT_VAULT" and record.verificationState == "MANUAL_RECORDED" then
        record.source = "GREAT_VAULT"
        record.verificationState = verificationState
        record.evidenceState = evidenceState
        record.evidenceId = options.evidenceId or record.evidenceId
        record.evidence = options.evidence or record.evidence
        record.evidenceSources = record.evidenceSources or { "VAULT_MANUAL" }
        table.insert(record.evidenceSources, "GREAT_VAULT")
        record.revision = (tonumber(record.revision) or 1) + 1
        record.outcome = "AUTOMATIC_CONFIRMED"
      else
        record.outcome = "ALREADY_RECORDED"
      end
      record.idempotentReplay = true
      return record
    end
  end
  local record = {
    acquisitionId = options.acquisitionId or Dibs.NewId("vault"), acquisitionKey = acquisitionKey,
    guildKey = guildKey, playerName = player, characterId = characterId, itemID = targetItem,
    itemLink = options.itemLink, itemName = options.itemName, itemLevel = tonumber(options.itemLevel),
    family = options.family, rewardCategory = options.rewardCategory, upgradeTrack = options.upgradeTrack,
    difficulty = normalizedDifficulty, source = source, verificationState = verificationState,
    evidenceState = evidenceState, evidenceId = options.evidenceId or options.claimId,
    evidence = Dibs.DeepCopy and Dibs.DeepCopy(options.evidence) or options.evidence,
    resetId = resetId, claimedAt = claimedAt, acquiredAt = claimedAt, createdAt = createdAt,
    seasonId = seasonId, revision = 1, syncState = "LOCAL",
    outcome = source == "VAULT_MANUAL" and "RECORDED_MANUAL" or verificationState,
  }
  table.insert(Dibs.db.preDibs.acquisitions, record)
  if Dibs.Notifications and Dibs.Notifications.Notify then
    Dibs.Notifications.Notify("vault:" .. tostring(record.acquisitionId), "VAULT_RECORDED", record)
  end
  return record
end

---@param acquisitionId string Acquisition identity.
---@param decision string CONFIRMED, REJECTED, or REFERENCE_ONLY.
---@param actor string|nil Officer reviewing the evidence.
---@param reason string|nil Review explanation; required for rejection/reference.
---@return DibsVaultAcquisition|nil acquisition
---@return string|nil reasonCode
-- Side effects: Stores an audited decision without changing the Dibs ledger.
function Dibs.PreDibs.ReviewVaultAcquisition(acquisitionId, decision, actor, reason)
  ensureState()
  local action = string.upper(tostring(decision or ""))
  local targetState = ({
    CONFIRM = "OFFICER_CONFIRMED", CONFIRMED = "OFFICER_CONFIRMED", OFFICER_CONFIRMED = "OFFICER_CONFIRMED",
    REJECT = "REJECTED", REJECTED = "REJECTED",
    REFERENCE = "REFERENCE_ONLY", REFERENCE_ONLY = "REFERENCE_ONLY",
  })[action]
  if not targetState then return nil, "INVALID_REVIEW_DECISION" end
  if tostring(reason or ""):match("^%s*$") then return nil, "REASON_REQUIRED" end
  local permission = targetState == "OFFICER_CONFIRMED" and "history.confirm" or "history.reject"
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function" or not Dibs.Permissions.Can(permission, actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  ---@type DibsVaultAcquisition|nil
  local target
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if record.acquisitionId == acquisitionId then target = record break end
  end
  if not target then return nil, "ACQUISITION_NOT_FOUND" end
  if target.verificationState == targetState then
    local replay = copyVaultAcquisition(target)
    replay.idempotentReplay = true
    return replay, "IDEMPOTENT_REPLAY"
  end
  local allowedTransitions = {
    MANUAL_RECORDED = { OFFICER_CONFIRMED = true, REJECTED = true, REFERENCE_ONLY = true },
    LEGACY_RECORDED = { OFFICER_CONFIRMED = true, REJECTED = true, REFERENCE_ONLY = true },
    UNVERIFIED = { OFFICER_CONFIRMED = true, REJECTED = true, REFERENCE_ONLY = true },
    AUTOMATIC_CONFIRMED = { REJECTED = true, REFERENCE_ONLY = true },
  }
  if not (allowedTransitions[target.verificationState] and allowedTransitions[target.verificationState][targetState]) then
    return nil, "INVALID_REVIEW_TRANSITION"
  end
  if not target.originalEvidence then target.originalEvidence = copy(target) end
  target.verificationState = targetState
  target.evidenceState = targetState == "OFFICER_CONFIRMED" and "COMPLETE" or target.evidenceState
  target.review = {
    decision = targetState, actorId = Dibs.Permissions.CanonicalPlayerId(actor),
    reason = reason, reviewedAt = time(),
  }
  target.reviewHistory = target.reviewHistory or {}
  table.insert(target.reviewHistory, copy(target.review))
  target.revision = (tonumber(target.revision) or 1) + 1
  target.syncState = "LOCAL"
  Dibs.db.auditLog = Dibs.db.auditLog or {}
  table.insert(Dibs.db.auditLog, {
    eventId = Dibs.NewId("vault-review"), action = "great_vault.review",
    acquisitionId = target.acquisitionId, decision = targetState,
    actorId = target.review.actorId, reason = reason, createdAt = time(),
  })
  return copyVaultAcquisition(target)
end

---@param record DibsVaultAcquisition Acquisition to project.
---@param visibility string "player" hides private evidence; "officer" preserves it.
---@return table projection
function Dibs.PreDibs.ProjectVaultAcquisition(record, visibility)
  local projection = copy(record or {})
  if tostring(visibility or "player") ~= "officer" then
    projection.evidence = nil
    projection.originalEvidence = nil
    projection.review = nil
  end
  return projection
end

function Dibs.PreDibs.GetVaultAcquisition(acquisitionId)
  ensureState()
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if record.acquisitionId == acquisitionId then return record end
  end
  return nil
end

---@param incoming table Bounded, guild-scoped acquisition projection.
---@return DibsVaultAcquisition|nil acquisition
---@return string|nil reasonCode
function Dibs.PreDibs.ApplyVaultSyncRecord(incoming)
  ensureState()
  if type(incoming) ~= "table" or type(incoming.acquisitionId) ~= "string" or incoming.acquisitionId == "" then
    return nil, "INVALID_ACQUISITION"
  end
  if tonumber(incoming.itemID) == nil or tonumber(incoming.itemID) <= 0 or type(incoming.playerName) ~= "string" then
    return nil, "INVALID_ACQUISITION"
  end
  if type(incoming.guildKey) ~= "string" or incoming.guildKey == "" or incoming.guildKey ~= Dibs.GetGuildKey() then
    return nil, "GUILD_SCOPE_MISMATCH"
  end
  local existing = Dibs.PreDibs.GetVaultAcquisition(incoming.acquisitionId)
  if existing then
    local identityFields = { "guildKey", "playerName", "characterId", "itemID", "resetId", "source" }
    for _, field in ipairs(identityFields) do
      if tostring(existing[field] or "") ~= tostring(incoming[field] or "") then
        table.insert(Dibs.db.preDibs.vaultConflicts, {
          conflictId = Dibs.NewId("vault-conflict"), acquisitionId = incoming.acquisitionId,
          current = copy(existing), incoming = copy(incoming), status = "REVIEW_REQUIRED", createdAt = time(),
        })
        return nil, "CONFLICT_REVIEW_REQUIRED"
      end
    end
    local currentRevision = tonumber(existing.revision) or 1

    local incomingRevision = tonumber(incoming.revision) or 1
    if incomingRevision < currentRevision then return nil, "STALE_REVISION" end
    if incomingRevision == currentRevision then
      return copyVaultAcquisition(existing), "IDEMPOTENT_REPLAY"
    end
  end
  ---@type DibsVaultAcquisition
  local record = copy(incoming)
  ---@cast record DibsVaultAcquisition
  record.syncState = "SYNCED"
  record.evidence = nil
  record.originalEvidence = nil
  record.review = nil
  if existing then
    for index, candidate in ipairs(Dibs.db.preDibs.acquisitions) do
      if candidate.acquisitionId == record.acquisitionId then Dibs.db.preDibs.acquisitions[index] = record break end
    end
  else
    table.insert(Dibs.db.preDibs.acquisitions, record)
  end
  return copyVaultAcquisition(record), "APPLIED"
end

function Dibs.PreDibs.GetVaultConflicts()
  ensureState()
  return Dibs.db.preDibs.vaultConflicts
end

function Dibs.PreDibs.GetVaultDiagnostics()
  ensureState()
  local diagnostics = { total = 0, legacy = 0, reviewRequired = 0, conflicts = 0, synced = 0 }
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    diagnostics.total = diagnostics.total + 1
    if record.verificationState == "LEGACY_RECORDED" then diagnostics.legacy = diagnostics.legacy + 1 end
    if record.verificationState == "UNVERIFIED" or record.verificationState == "MANUAL_RECORDED" then
      diagnostics.reviewRequired = diagnostics.reviewRequired + 1
    end
    if record.syncState == "SYNCED" then diagnostics.synced = diagnostics.synced + 1 end
  end
  for _, conflict in ipairs(Dibs.db.preDibs.vaultConflicts) do
    if conflict.status == "REVIEW_REQUIRED" then diagnostics.conflicts = diagnostics.conflicts + 1 end
  end
  return diagnostics
end

---@param conflictId string Conflict identity.
---@param decision string KEEP_CURRENT or ACCEPT_INCOMING.
---@param actor string|nil Officer resolving the conflict.
---@param reason string Explanation for the resolution.
---@return table|nil conflict Resolved conflict.
---@return string|nil reasonCode
function Dibs.PreDibs.ResolveVaultConflict(conflictId, decision, actor, reason)
  ensureState()
  if tostring(reason or ""):match("^%s*$") then return nil, "REASON_REQUIRED" end
  local action = string.upper(tostring(decision or ""))
  if action ~= "KEEP_CURRENT" and action ~= "ACCEPT_INCOMING" then return nil, "INVALID_CONFLICT_DECISION" end
  local permission = action == "ACCEPT_INCOMING" and "history.confirm" or "history.reject"
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function" or not Dibs.Permissions.Can(permission, actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local conflict
  for _, candidate in ipairs(Dibs.db.preDibs.vaultConflicts) do
    if candidate.conflictId == conflictId then conflict = candidate break end
  end
  if not conflict then return nil, "CONFLICT_NOT_FOUND" end
  if conflict.status == "RESOLVED" then return copy(conflict), "IDEMPOTENT_REPLAY" end

  if action == "ACCEPT_INCOMING" then
    local incoming = copy(conflict.incoming)
    incoming.syncState = "SYNCED"
    incoming.evidence = nil
    incoming.originalEvidence = nil
    incoming.review = nil
    for index, record in ipairs(Dibs.db.preDibs.acquisitions) do
      if record.acquisitionId == conflict.acquisitionId then Dibs.db.preDibs.acquisitions[index] = incoming break end
    end
  end
  conflict.status = "RESOLVED"
  conflict.resolution = {
    decision = action, actorId = Dibs.Permissions.CanonicalPlayerId(actor), reason = reason, resolvedAt = time(),
  }
  Dibs.db.auditLog = Dibs.db.auditLog or {}
  table.insert(Dibs.db.auditLog, {
    eventId = Dibs.NewId("vault-conflict-review"), action = "great_vault.conflict_review",
    conflictId = conflict.conflictId, acquisitionId = conflict.acquisitionId, decision = action,
    actorId = conflict.resolution.actorId, reason = reason, createdAt = conflict.resolution.resolvedAt,
  })
  return copy(conflict)
end

function Dibs.PreDibs.GetAcquisitionsForItem(itemID)
  ensureState()
  local records, targetItem = {}, tonumber(itemID) or 0
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if tonumber(record.itemID) == targetItem then table.insert(records, record) end
  end
  return records
end

function Dibs.PreDibs.GetAcquisitionsForPlayer(playerName)
  ensureState()
  local records, player = {}, playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if samePlayer(record.playerName, player) then table.insert(records, record) end
  end
  return records
end

function Dibs.PreDibs.GetAcquisitions()
  ensureState()
  return Dibs.db.preDibs.acquisitions
end

function Dibs.PreDibs.GetConfirmedRequestsForItem(itemID)
  ensureState()
  local list = {}
  for _, request in ipairs(Dibs.PreDibs.GetRequestsForItem(itemID)) do
    if request.status == "confirmed" then
      table.insert(list, request)
    end
  end
  return list
end

function Dibs.PreDibs.HasConfirmedRequestsForItem(itemID)
  return #Dibs.PreDibs.GetConfirmedRequestsForItem(itemID) > 0
end

function Dibs.PreDibs.GetHistory()
  ensureState()
  return Dibs.db.preDibs.requests
end
