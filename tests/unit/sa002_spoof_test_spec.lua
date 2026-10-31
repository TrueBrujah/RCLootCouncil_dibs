-- Simplified SA-002 Reproduction: Test if audit.actor spoofing works

local loader = require("helpers.load_addon")

local function load(opts)
  local _, dibs = loader.load(opts or { wow = { guildLeader = true } })
  return dibs
end

describe("SA-002: Direct API actor spoofing", function()

  it("S002-A: Direct Ledger.Grant with spoofed actor in audit", function()
    local dibs = load({ wow = { guildLeader = true } }) -- Current player IS GM
    
    -- Call Ledger.Grant with audit pretending to be a different actor
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "spoof-test", dibs.GetCurrentSeasonId(), {
      actor = "FakeGM-Realm",  -- Spoofed actor
      actorName = "FakeGM-Realm",
      transactionId = "spoof-test-1"
    })
    
    if tx then
      print("VULNERABILITY: Ledger.Grant accepted with spoofed actor: " .. tostring(tx.transactionId))
      print("Actor in transaction: " .. tostring(tx.actorId))
    else
      print("Correctly rejected: " .. tostring(reason))
    end
  end)

  it("S002-B: Direct Ledger.Grant with nil audit (defaults to current player)", function()
    local dibs = load({ wow = { guildLeader = true } }) -- Current player IS GM
    
    -- Call without audit - should use current player (GM)
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId(), nil)
    
    if tx then
      print("SUCCESS: Ledger.Grant accepted with current GM player: " .. tostring(tx.transactionId))
    else
      print("Rejected: " .. tostring(reason))
    end
  end)

  it("S002-C: Direct Ledger.Grant by regular member (no guildLeader)", function()
    local dibs = load({ wow = { guildLeader = false } }) -- Current player is NOT GM
    
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId(), nil)
    
    if tx then
      print("VULNERABILITY: Regular member grant succeeded: " .. tostring(tx.transactionId))
    else
      print("Correctly rejected for regular member: " .. tostring(reason))
    end
  end)

  it("S002-D: ProtectedActions.Execute by GM", function()
    local dibs = load({ wow = { guildLeader = true } })
    
    local result = dibs.ProtectedActions.Execute("ledger.grant", "GM-Realm", {
      playerName = "Target-Realm",
      amount = 5,
      reason = "Test",
      source = "protected-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    
    if result.ok then
      print("ProtectedActions GM grant succeeded: " .. tostring(result.value.transactionId))
    else
      print("ProtectedActions rejected: " .. tostring(result.decision.reasonCode))
    end
  end)

  it("S002-E: ProtectedActions.Execute by regular member", function()
    local dibs = load({ wow = { guildLeader = false } })
    
    local result = dibs.ProtectedActions.Execute("ledger.grant", "Member-Realm", {
      playerName = "Target-Realm",
      amount = 5,
      reason = "Test",
      source = "protected-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    
    if result.ok then
      print("ProtectedActions member grant succeeded (unexpected!)")
    else
      print("ProtectedActions correctly rejected member: " .. tostring(result.decision.reasonCode))
    end
  end)

  it("S002-F: Check who is the current player", function()
    local dibs = load({ wow = { guildLeader = true, playerName = "ActualGM-Realm" } })
    print("Current player: " .. tostring(dibs.GetPlayerName()))
    print("IsGuildLeader(): " .. tostring(IsGuildLeader()))
    print("Dibs.Permissions.IsGM(): " .. tostring(dibs.Permissions.IsGM()))
  end)

  it("S002-G: Test isCurrentActor with spoofed actor", function()
    local dibs = load({ wow = { guildLeader = true, playerName = "ActualGM-Realm" } })
    
    -- The isCurrentActor function checks if the supplied actor matches the current player
    local actorId = dibs.Permissions.CanonicalPlayerId("FakeGM-Realm")
    print("FakeGM actorId: " .. tostring(actorId))
    
    local localId = dibs.Permissions.CanonicalPlayerId(nil)
    print("Local (current) actorId: " .. tostring(localId))
    
    -- Test isCurrentActor logic
    local same = actorId and localId and string.lower(tostring(actorId)) == string.lower(tostring(localId))
    print("Same identity: " .. tostring(same))
  end)

end)