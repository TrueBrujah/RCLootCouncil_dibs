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
  if not Dibs.PreDibs or type(Dibs.PreDibs.RecordVaultAcquisition) ~= "function" then
    evaluated.status, evaluated.reasonCode = "UNAVAILABLE", "ACQUISITIONS_UNAVAILABLE"
    return evaluated
  end
  local acquisition, reason = Dibs.PreDibs.RecordVaultAcquisition(
    input.playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName()),
    input.itemID,
    input.difficulty,
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
  if Dibs.Message then Dibs.Message("[GreatVault] " .. tostring(reason)) end
end

local function isReadable(value)
  return type(_G.issecretvalue) ~= "function" or not issecretvalue(value)
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
            choice = { itemLink = link, itemID = tonumber(link:match("item:(%d+)")) }
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
  pendingClaim = {
    itemID = choice.itemID, itemLink = choice.itemLink,
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