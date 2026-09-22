local M = {}

local function merge(base, overrides)
  for key, value in pairs(overrides or {}) do base[key] = value end
  return base
end

function M.request(overrides)
  return merge({
    requestId = "b12-request-1",
    playerName = "Player-1",
    itemName = "Midnight Blade",
    itemID = 21016,
    category = "missing_debit",
    categoryLabel = "Missing Dibs",
    status = "Open",
    note = "The expected Dibs entry is missing.",
    createdAt = 1700000000,
    evidence = {
      { item = "Midnight Blade", itemID = 21016, winner = "Player-1", source = "Dibs ledger" },
    },
  }, overrides)
end

function M.requestVariants()
  local unavailable = M.request({ requestId = "b12-request-unavailable", status = "Unavailable" })
  unavailable.evidence = nil
  local privacyFiltered = M.request({ requestId = "b12-request-private", playerName = "Private-Player", privacyFiltered = true })
  privacyFiltered.evidence = nil
  return {
    legacy = M.request({ requestId = "b12-request-legacy", category = nil, categoryLabel = nil }),
    unknown = M.request({ requestId = "b12-request-unknown", category = "new_category", categoryLabel = nil }),
    unavailable = unavailable,
    ambiguous = M.request({ requestId = "b12-request-ambiguous", evidence = { { item = "Unknown item" }, { item = "Another item" } } }),
    stale = M.request({ requestId = "b12-request-stale", stale = true, updatedAt = 1600000000 }),
    duplicate = M.request({ requestId = "b12-request-duplicate", duplicate = true, duplicateOf = "b12-request-1" }),
    privacyFiltered = privacyFiltered,
  }
end

function M.historicalCandidate(overrides)
  return merge({
    candidateId = "b12-candidate-1",
    itemID = 21016,
    itemName = "Midnight Blade",
    winner = "Player-1",
    difficulty = "Heroic",
    encounter = "The Midnight Vault",
    awardDate = 1700000000,
    classification = "UNACCOUNTED",
    duplicate = false,
    stale = false,
    ambiguous = false,
    unknownFields = {},
    evidence = {
      { source = "RCLootCouncil history", awardRef = "history:b12-1" },
    },
    privacy = { playerVisible = false, officerVisible = true },
  }, overrides)
end

function M.historicalVariants()
  local unavailable = M.historicalCandidate({ candidateId = "b12-candidate-unavailable", classification = "UNAVAILABLE" })
  unavailable.evidence = nil
  local privacyFiltered = M.historicalCandidate({ candidateId = "b12-candidate-private", winner = nil, privacy = { playerVisible = true, officerVisible = false } })
  privacyFiltered.winner = nil
  privacyFiltered.evidence = nil
  return {
    legacy = M.historicalCandidate({ candidateId = "b12-candidate-legacy", classification = "LEGACY" }),
    unknown = M.historicalCandidate({ candidateId = "b12-candidate-unknown", unknownFields = { encounter = true } }),
    unavailable = unavailable,
    ambiguous = M.historicalCandidate({ candidateId = "b12-candidate-ambiguous", ambiguous = true, classification = "AMBIGUOUS" }),
    stale = M.historicalCandidate({ candidateId = "b12-candidate-stale", stale = true }),
    duplicate = M.historicalCandidate({ candidateId = "b12-candidate-duplicate", duplicate = true, duplicateOf = "b12-candidate-1" }),
    privacyFiltered = privacyFiltered,
  }
end

return M
