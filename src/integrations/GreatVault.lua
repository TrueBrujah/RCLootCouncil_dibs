--[[
Module: Dibs.GreatVault
Layer: Optional Retail capability adapter
Purpose: Translate reliable Great Vault claim observations into Pre-Dibs evidence.
Non-responsibilities: It does not infer claims from reward choices or change the Dibs ledger.
]]

local Dibs = _G.Dibs
Dibs.GreatVault = Dibs.GreatVault or {}

local GreatVault = Dibs.GreatVault

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function hasClaimSignal()
  return GreatVault.claimSignalAvailable == true
    and type(_G.C_WeeklyRewards) == "table"
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

function GreatVault.Initialize()
  GreatVault.capability = GreatVault.GetCapability()
  return GreatVault.capability
end

GreatVault.Initialize()