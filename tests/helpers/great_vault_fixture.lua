local M = {}

function M.acquisition(overrides)
  local record = {
    acquisitionId = "vault-test-1",
    guildKey = "Realm:Test Guild",
    playerName = "Tester-Realm",
    characterId = "Player-1-TESTER",
    itemID = 21016,
    difficulty = "Heroic",
    seasonId = "season-test",
    resetId = "reset-test",
    claimedAt = 1700000000,
    createdAt = 1700000000,
    source = "GREAT_VAULT",
    verificationState = "AUTOMATIC_CONFIRMED",
    evidenceState = "COMPLETE",
    evidenceId = "claim-test-1",
    revision = 1,
    syncState = "LOCAL",
  }
  for key, value in pairs(overrides or {}) do record[key] = value end
  return record
end

function M.observation(overrides)
  local observation = {
    itemID = 21016,
    playerName = "Tester-Realm",
    resetId = "reset-test",
    claimedAt = 1700000000,
    claimId = "claim-test-1",
    claimComplete = true,
    capability = "test",
  }
  for key, value in pairs(overrides or {}) do observation[key] = value end
  return observation
end

return M
