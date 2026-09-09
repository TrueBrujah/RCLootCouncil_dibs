local Dibs = _G.Dibs
Dibs.DryRun = Dibs.DryRun or {}

local DryRun = Dibs.DryRun
local MAX_TEXT = 160

local function trim(value, limit)
  local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  limit = tonumber(limit) or MAX_TEXT
  if #text > limit then text = text:sub(1, limit) end
  return text
end

local function now()
  if type(time) == "function" then return tonumber(time()) or 0 end
  return 0
end

local function addReason(result, code)
  if not code or code == "" then return end
  table.insert(result.reasonCodes, tostring(code))
end

local function parseItem(value)
  if type(value) == "table" then
    value = value.itemID or value.id or value.link
  end
  local id = tonumber(value)
  if not id and type(value) == "string" then id = tonumber(value:match("item:(%d+)")) end
  if not id or id < 1 or id > 999999999 then return nil end
  return math.floor(id)
end

local function stableFingerprint(input)
  return table.concat({
    tostring(input.itemID or "none"),
    string.lower(trim(input.winner, MAX_TEXT)),
    string.upper(trim(input.response, MAX_TEXT)),
    string.lower(trim(input.status, 32)),
    trim(input.sessionIdentity, MAX_TEXT),
    string.lower(trim(input.difficulty, 32)),
    string.lower(trim(input.mode, 32)),
  }, "|")
end

local function localAdmin(options)
  if options and options.allowPlayer == true then return true end
  return Dibs.Permissions and type(Dibs.Permissions.CanManageDibs) == "function"
    and Dibs.Permissions.CanManageDibs() == true
end

local function integrationState()
  if Dibs.Readiness and type(Dibs.Readiness.Evaluate) == "function" then
    local result = Dibs.Readiness.Evaluate({ allowPlayer = true, dryRun = true })
    return result and result.integrationStatus or "Unavailable", result
  end
  return "Unavailable", nil
end

local function makeResult(input)
  local result = {
    simulation = true,
    mutated = false,
    checkedAt = now(),
    input = {
      itemID = input.itemID,
      winner = input.winner,
      response = input.response,
      status = input.status,
      sessionIdentity = input.sessionIdentity,
      difficulty = input.difficulty,
      mode = input.mode,
    },
    reasonCodes = {},
    outcome = "would_require_review",
    wouldConsumeDib = false,
    integrationStatus = "Unavailable",
  }
  result.fingerprint = stableFingerprint(input)
  return result
end

function DryRun.Run(input, options)
  input = type(input) == "table" and input or {}
  options = type(options) == "table" and options or {}
  if not localAdmin(options) then return nil, "GUILD_ADMIN_REQUIRED" end

  local bounded = {
    itemID = parseItem(input.item or input.itemID or input.itemLink),
    winner = trim(input.winner or input.playerName),
    response = trim(input.response or input.responseText, MAX_TEXT),
    status = string.lower(trim(input.status or "finalized", 32)),
    sessionIdentity = trim(input.sessionIdentity or input.session or input.awardRef),
    difficulty = trim(input.difficulty, 32),
    mode = trim(input.mode, 32),
    responseType = trim(input.responseType, 64),
  }
  local result = makeResult(bounded)

  if not bounded.itemID then
    addReason(result, "AWARD_INVALID_ITEM")
    result.outcome = "would_ignore"
    result.explanation = "The simulated item identity is missing or malformed."
    return result
  end
  if bounded.winner == "" then
    addReason(result, "AWARD_INVALID_WINNER")
    result.outcome = "would_ignore"
    result.explanation = "A bounded winner identity is required."
    return result
  end
  if bounded.response == "" then
    addReason(result, "EMPTY_RESPONSE")
    result.outcome = "would_ignore"
    result.explanation = "An explicit RCLootCouncil response is required."
    return result
  end
  if not bounded.sessionIdentity then
    addReason(result, "AWARD_IDENTITY_UNAVAILABLE")
    result.outcome = "would_require_review"
    result.explanation = "A stable synthetic award identity is required for the simulation."
    return result
  end
  if bounded.status == "test" or bounded.status == "test_mode" then
    addReason(result, "AWARD_TEST_MODE")
    result.outcome = "would_ignore"
    result.explanation = "Test-status awards never consume production Dibs."
    return result
  end
  if bounded.status ~= "finalized" and bounded.status ~= "awarded" and bounded.status ~= "complete" then
    addReason(result, "AWARD_NOT_FINAL")
    result.outcome = "would_require_review"
    result.explanation = "Only a finalized award can be considered for Dibs accounting."
    return result
  end

  local integrationStatus, readiness = integrationState()
  result.integrationStatus = integrationStatus
  if readiness and readiness.lastDryRunOutcome then
    result.readinessOutcome = readiness.lastDryRunOutcome
  end

  local validation = Dibs.RCLootCouncil and Dibs.RCLootCouncil.ValidateAwardInput and Dibs.RCLootCouncil.ValidateAwardInput({
    itemID = bounded.itemID,
    winner = bounded.winner,
    response = bounded.response,
    responseType = bounded.responseType ~= "" and bounded.responseType or nil,
    status = bounded.status,
    sessionIdentity = bounded.sessionIdentity,
    requireIdentity = true,
  })
  if not validation or validation.ok ~= true then
    addReason(result, validation and validation.reasonCode or "DIB_VALIDATION_UNAVAILABLE")
    result.outcome = validation and validation.reasonCode == "AWARD_IDENTITY_UNAVAILABLE" and "would_require_review" or "would_ignore"
    result.explanation = "The simulated award failed the shared live-award validation rules."
    return result
  end
  result.normalizedResponse = validation.response

  local candidate
  if Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.GetStatusForCandidate) == "function" then
    candidate = Dibs.RCLootCouncil.GetStatusForCandidate(bounded.winner, bounded.itemID, bounded.responseType ~= "" and bounded.responseType or nil, {
      ignorePublicPreDibRequirement = true,
    })
  end
  result.candidate = {
    status = candidate and candidate.status or "unavailable",
    balance = candidate and tonumber(candidate.balance) or 0,
    typeEnabled = candidate and candidate.dibTypeEnabled == true or false,
    canUseDib = candidate and candidate.canUseDib == true or false,
  }
  if not candidate then
    addReason(result, "DIB_VALIDATION_UNAVAILABLE")
    result.outcome = "would_require_review"
    result.explanation = "The local Dibs eligibility service is unavailable."
    return result
  end
  if candidate.canUseDib ~= true then
    addReason(result, "DIB_INELIGIBLE")
    result.outcome = "would_reject"
    result.explanation = "The player would not be eligible to spend a Dib for this item under the current policy."
    return result
  end

  result.outcome = "would_allow"
  result.wouldConsumeDib = true
  result.explanation = "The protected live path would be allowed to consume one Dib after final revalidation."
  return result
end

function DryRun.RunFromSlash(raw, options)
  local tokens = {}
  for token in string.gmatch(tostring(raw or ""), "%S+") do table.insert(tokens, token) end
  if #tokens < 4 then return nil, "USAGE" end
  return DryRun.Run({
    item = tokens[1],
    winner = tokens[2],
    response = tokens[3],
    status = tokens[4],
    sessionIdentity = tokens[5] or "slash-dry-run",
  }, options)
end

function DryRun.Format(result)
  if type(result) ~= "table" then return tostring(result or "Dry-run unavailable.") end
  local lines = {
    "Dibs dry-run (no live changes)",
    "Outcome: " .. tostring(result.outcome),
    "Would consume Dib: " .. (result.wouldConsumeDib and "yes" or "no"),
    "Integration: " .. tostring(result.integrationStatus),
    "Reasons: " .. table.concat(result.reasonCodes or {}, ", "),
    "Fingerprint: " .. tostring(result.fingerprint),
    tostring(result.explanation or ""),
  }
  return table.concat(lines, "\n")
end
