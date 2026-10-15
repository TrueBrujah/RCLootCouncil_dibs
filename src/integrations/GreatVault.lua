--[[
Module: Dibs.GreatVault
Layer: Optional Retail capability adapter
Purpose: Translate reliable Great Vault claim observations into Pre-Dibs evidence.
Non-responsibilities: It does not infer claims from reward choices or change the Dibs ledger.
]]

local Dibs = _G.Dibs
Dibs.GreatVault = Dibs.GreatVault or {}

local GreatVault = Dibs.GreatVault
local CLAIM_TIMEOUT = 120
local rewardChoices = {}
local pendingClaim
local hookedAPI
local eventFrame

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function hasClaimSignal()
  local api = _G.C_WeeklyRewards
  return type(api) == "table" and hookedAPI == api
    and type(api.CanClaimRewards) == "function"
    and type(_G.C_DateAndTime) == "table"
    and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function"
end

function GreatVault.GetCapability()
  if hasClaimSignal() then
    return { status = "OPERATIONAL", reasonCode = "CLAIM_SIGNAL_AVAILABLE" }
  end
  return { status = "UNAVAILABLE", reasonCode = "CLAIM_SIGNAL_UNAVAILABLE" }
end

local function result(status, confidence, reasonCode, observation)
  local reasonKey = "VAULT_REASON_" .. tostring(reasonCode or "")
  return {
    status = status,
    source = "GREAT_VAULT",
    itemID = tonumber(observation and observation.itemID),
    resetId = observation and observation.resetId,
    claimedAt = tonumber(observation and observation.claimedAt),
    rewardCategory = observation and observation.rewardCategory,
    confidence = confidence,
    reasonCode = reasonCode,
    explanation = (Dibs.L and Dibs.L[reasonKey]) or reasonCode,
  }
end

function GreatVault.EvaluateObservation(observation)
  local input = type(observation) == "table" and observation or {}
  local itemID = tonumber(input.itemID)
  if not itemID or itemID <= 0 then
    return result("UNAVAILABLE", "MISSING", "ITEM_ID_UNAVAILABLE", input)
  end
  if input.claimComplete ~= true then
    if not input.event and not hasClaimSignal() then
      return result("UNAVAILABLE", "MISSING", "CLAIM_SIGNAL_UNAVAILABLE", input)
    end
    return result("AMBIGUOUS", "PARTIAL", "CLAIM_NOT_CONFIRMED", input)
  end
  if not trim(input.claimId or input.evidenceId):find("%S") then
    return result("AMBIGUOUS", "PARTIAL", "CLAIM_ID_UNAVAILABLE", input)
  end
  if not input.resetId or trim(input.resetId) == "" then
    return result("AMBIGUOUS", "PARTIAL", "RESET_ID_UNAVAILABLE", input)
  end
  return result("CONFIRMED", "COMPLETE", "CLAIM_CONFIRMED", input)
end

function GreatVault.RecordClaim(observation)
  local input = type(observation) == "table" and observation or {}
  local evaluated = GreatVault.EvaluateObservation(input)
  if evaluated.status ~= "CONFIRMED" then return evaluated end
  local normalize = Dibs.PreDibs and Dibs.PreDibs.NormalizeDifficulty
  local difficulty = input.difficulty
  if input.itemLink then
    local detected = GreatVault.ResolveItemDifficulty(input.itemLink)
    if detected then difficulty = detected end
  end
  if not normalize or normalize(difficulty) == "UNKNOWN" then
    return result("AMBIGUOUS", "PARTIAL", "DIFFICULTY_UNAVAILABLE", input)
  end
  if not Dibs.PreDibs or type(Dibs.PreDibs.RecordVaultAcquisition) ~= "function" then
    evaluated.status, evaluated.reasonCode = "UNAVAILABLE", "ACQUISITIONS_UNAVAILABLE"
    return evaluated
  end
  local acquisition, reason = Dibs.PreDibs.RecordVaultAcquisition(
    input.playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName()),
    input.itemID,
    difficulty,
    {
      source = "GREAT_VAULT",
      verificationState = "AUTOMATIC_CONFIRMED",
      evidenceState = "COMPLETE",
      evidenceId = input.claimId or input.evidenceId,
      resetId = input.resetId,
      claimedAt = input.claimedAt,
      itemLink = input.itemLink,
      itemName = input.itemName,
      itemLevel = input.itemLevel,
      family = input.family,
      rewardCategory = input.rewardCategory,
      upgradeTrack = input.upgradeTrack,
      evidence = input.evidence,
    }
  )
  if not acquisition then
    evaluated.status, evaluated.reasonCode = "UNAVAILABLE", reason or "ACQUISITION_REJECTED"
    return evaluated
  end
  evaluated.acquisition = acquisition
  evaluated.idempotent = acquisition.idempotentReplay == true
  return evaluated
end

local function reportFailure(reason)
  local text = Dibs.L and Dibs.L["VAULT_REASON_" .. tostring(reason)]
  if Dibs.Message then Dibs.Message("[GreatVault] " .. tostring(text or reason)) end
end

local function isReadable(value)
  return type(_G.issecretvalue) ~= "function" or not issecretvalue(value)
end

local function itemStringOf(link)
  if not isReadable(link) then return nil end
  if type(link) ~= "string" then return nil end
  return link:match("|H(item:[^|]+)|h") or link:match("^(item:[^|%s]+)$")
end

local DIFFICULTY_BY_TOOLTIP_LABEL = {
  ["Raid Finder"] = "LFR",
  ["Looking For Raid"] = "LFR",
  ["Looking for Raid"] = "LFR",
  ["Outil Raids"] = "LFR",
  ["Outil de raid"] = "LFR",
  Normal = "Normal",
  Heroic = "Heroic",
  ["Héroïque"] = "Heroic",
  Mythic = "Mythic",
  Mythique = "Mythic",
}

local KEYSTONE_LABELS = { ["Mythic+"] = true, ["Mythique+"] = true }

local TRACK_BY_LABEL = {
  Adventurer = "ADVENTURER", Aventurier = "ADVENTURER",
  Veteran = "VETERAN", ["Vétéran"] = "VETERAN",
  Champion = "CHAMPION",
  Hero = "HERO", ["Héros"] = "HERO",
  Myth = "MYTH", Mythe = "MYTH",
}

local DIFFICULTY_BY_TRACK = { VETERAN = "LFR", CHAMPION = "Normal", HERO = "Heroic", MYTH = "Mythic" }

-- Raid origin labels are kept only on tracks a raid of that difficulty can award.
local RAID_TRACKS = {
  LFR = { VETERAN = true },
  Normal = { CHAMPION = true, HERO = true },
  Heroic = { HERO = true, MYTH = true },
  Mythic = { MYTH = true },
}

local function cleanText(text)
  if not isReadable(text) or type(text) ~= "string" then return nil end
  return trim(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function trackOf(text)
  local label = type(text) == "string" and text:match("([^%s:]+)%s+%d+%s*/%s*%d+%s*$")
  return label and TRACK_BY_LABEL[label] or nil
end

local function tooltipDifficulty(text)
  local label = cleanText(text)
  if not label then return nil end
  local keystone = _G.PLAYER_DIFFICULTY_MYTHIC_PLUS
  if KEYSTONE_LABELS[label] or (isReadable(keystone) and label == keystone) then return "KEYSTONE" end
  for _, entry in ipairs({
    { "PLAYER_DIFFICULTY3", "LFR" },
    { "ITEM_RAID_FINDER", "LFR" },
    { "RAID_FINDER", "LFR" },
    { "PLAYER_DIFFICULTY1", "Normal" },
    { "PLAYER_DIFFICULTY2", "Heroic" },
    { "PLAYER_DIFFICULTY6", "Mythic" },
    { "ITEM_HEROIC", "Heroic" },
    { "ITEM_MYTHIC", "Mythic" },
  }) do
    local localized = _G[entry[1]]
    if isReadable(localized) and type(localized) == "string" and label == localized then return entry[2] end
  end
  return DIFFICULTY_BY_TOOLTIP_LABEL[label]
end

local function upgradeTrackOf(itemLink, lines)
  local api = _G.C_Item
  if type(api) == "table" and type(api.GetItemUpgradeInfo) == "function" then
    local ok, info = pcall(api.GetItemUpgradeInfo, itemLink)
    if ok and isReadable(info) and type(info) == "table" and isReadable(info.trackString)
      and type(info.trackString) == "string" then
      local track = TRACK_BY_LABEL[trim(info.trackString)]
      if track then return track end
    end
  end
  for index, line in ipairs(lines) do
    if index > 1 and isReadable(line) and type(line) == "table" then
      local track = trackOf(cleanText(line.leftText))
      if track then return track end
    end
  end
  return nil
end

-- Heroic/Veteran and Mythic/Champion identify dungeon rewards rather than raids.
function GreatVault.ResolveItemDifficulty(itemLink)
  if not itemStringOf(itemLink) then return nil end
  local api = _G.C_TooltipInfo
  if type(api) ~= "table" or type(api.GetHyperlink) ~= "function" then return nil end
  local ok, info = pcall(api.GetHyperlink, itemLink)
  if not ok then
    reportFailure("TOOLTIP_UNAVAILABLE")
    return nil
  end
  if not isReadable(info) or type(info) ~= "table" or not isReadable(info.lines)
    or type(info.lines) ~= "table" then return nil end
  local origin
  for index, line in ipairs(info.lines) do
    -- The first line is the item name, not its difficulty.
    if index > 1 and isReadable(line) and type(line) == "table" then
      local detected = tooltipDifficulty(line.leftText)
      if detected and origin and detected ~= origin then return nil end
      origin = detected or origin
    end
  end
  if not origin then return nil end
  local track = upgradeTrackOf(itemLink, info.lines)
  if not track then return nil end
  if origin == "Heroic" and track == "VETERAN" then return "Heroic", "DUNGEON_TRACK" end
  if origin == "KEYSTONE" or (origin == "Mythic" and track == "CHAMPION")
  then
    local difficulty = DIFFICULTY_BY_TRACK[track]
    if difficulty then return difficulty, "DUNGEON_TRACK" end
    return nil
  end
  if RAID_TRACKS[origin] and RAID_TRACKS[origin][track] then return origin, "RAID_ORIGIN" end
  return nil
end

local function cacheRewardChoices()
  local api = _G.C_WeeklyRewards
  if not hasClaimSignal() or not api.CanClaimRewards() then return end
  local choices = {}
  for _, activity in ipairs(api.GetActivities() or {}) do
    if isReadable(activity.claimID) and activity.claimID then
      local choice
      local itemCount = 0
      for _, reward in ipairs(activity.rewards or {}) do
        if isReadable(reward.itemDBID) and reward.itemDBID then
          local link = api.GetItemHyperlink(reward.itemDBID)
          if isReadable(link) and type(link) == "string" and link:match("item:(%d+)") then
            itemCount = itemCount + 1
            choice = {
              itemLink = link, itemID = tonumber(link:match("item:(%d+)")),
              difficulty = GreatVault.ResolveItemDifficulty(link),
            }
          end
        end
      end
      if itemCount == 1 then choices[activity.claimID] = choice end
    end
  end
  rewardChoices = choices
end

local function finishPendingClaim()
  local claim = pendingClaim
  if not claim then return end
  if time() - claim.claimedAt > CLAIM_TIMEOUT
    or claim.playerName ~= Dibs.GetPlayerName()
    or claim.guildKey ~= Dibs.GetGuildKey()
    or claim.seasonId ~= Dibs.GetCurrentSeasonId()
    or (Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled()) then
    pendingClaim = nil
    reportFailure("CLAIM_CONTEXT_EXPIRED")
    return
  end
  if not claim.received or C_WeeklyRewards.CanClaimRewards() ~= false then return end
  pendingClaim = nil
  claim.claimComplete = true
  local recorded = GreatVault.RecordClaim(claim)
  if recorded.status ~= "CONFIRMED" then reportFailure(recorded.reasonCode) end
end

local function onClaimRequested(claimID)
  pendingClaim = nil
  if not isReadable(claimID) then return reportFailure("CLAIM_ID_UNAVAILABLE") end
  if Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled() then return end
  local choice = rewardChoices[claimID]
  if not choice then return reportFailure("CLAIM_ITEM_UNAVAILABLE") end
  local seconds = C_DateAndTime.GetSecondsUntilWeeklyReset()
  if type(seconds) ~= "number" or seconds <= 0 then return reportFailure("RESET_ID_UNAVAILABLE") end
  local claimedAt = time()
  local resetId = "weekly:" .. tostring(math.floor((claimedAt + seconds) / 86400))
  local difficulty = choice.difficulty or GreatVault.ResolveItemDifficulty(choice.itemLink)
  pendingClaim = {
    itemID = choice.itemID, itemLink = choice.itemLink,
    difficulty = difficulty,
    claimId = resetId .. ":" .. tostring(claimID), resetId = resetId,
    claimedAt = claimedAt, playerName = Dibs.GetPlayerName(),
    guildKey = Dibs.GetGuildKey(), seasonId = Dibs.GetCurrentSeasonId(),
  }
end

local function onEvent(_, event, ...)
  if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
    GreatVault.Initialize()
  elseif event == "CHAT_MSG_LOOT" and pendingClaim then
    local message = ...
    local senderGUID = select(12, ...)
    if isReadable(message) and isReadable(senderGUID) and type(message) == "string"
      and senderGUID == UnitGUID("player") then
      -- Match the full reward variant, not an unrelated drop with the same item ID.
      local itemString = message:match("|H(item:[^|]+)|h")
      local selectedString = pendingClaim.itemLink:match("|H(item:[^|]+)|h")
      if itemString and itemString == selectedString then pendingClaim.received = true end
    end
    finishPendingClaim()
  elseif event == "WEEKLY_REWARDS_UPDATE" or event == "WEEKLY_REWARDS_ITEM_CHANGED" then
    finishPendingClaim()
    cacheRewardChoices()
  end
end

function GreatVault.Initialize()
  local api = _G.C_WeeklyRewards
  if type(api) == "table" and hookedAPI ~= api and type(hooksecurefunc) == "function"
    and type(api.ClaimReward) == "function" and type(api.GetActivities) == "function"
    and type(api.GetItemHyperlink) == "function" and type(api.CanClaimRewards) == "function"
    and type(_G.C_DateAndTime) == "table"
    and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function" then
    local ok, reason = pcall(hooksecurefunc, api, "ClaimReward", onClaimRequested)
    if ok then hookedAPI = api else reportFailure(reason) end
  end
  if not eventFrame and type(CreateFrame) == "function" then
    eventFrame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "CHAT_MSG_LOOT",
      "WEEKLY_REWARDS_UPDATE", "WEEKLY_REWARDS_ITEM_CHANGED" }) do
      eventFrame:RegisterEvent(event)
    end
    eventFrame:SetScript("OnEvent", onEvent)
  end
  cacheRewardChoices()
  GreatVault.capability = GreatVault.GetCapability()
  return GreatVault.capability
end

GreatVault.Initialize()