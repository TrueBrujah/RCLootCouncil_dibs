-- SA-002 Reproduction with proper guild roster setup

local loader = require("helpers.load_addon")

local function load(opts)
  local _, dibs = loader.load(opts or { wow = { guildLeader = true } })
  return dibs
end

describe("SA-002: Direct API bypass with proper roster", function()

  it("S002-R1: GM in roster - direct Ledger.Grant with nil audit", function()
    local dibs = load({ 
      wow = { 
        guildLeader = true, 
        playerName = "GM-Realm",
        guildMembers = { "GM-Realm", "Member1-Realm", "Member2-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1, [3] = 2 }  -- GM is rank 0
      } 
    })
    
    print("Current player: " .. tostring(dibs.GetPlayerName()))
    print("IsGuildLeader: " .. tostring(IsGuildLeader()))
    print("Dibs.Permissions.IsGM: " .. tostring(dibs.Permissions.IsGM()))
    
    local tx, reason = dibs.Ledger.Grant("Member1-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId(), nil)
    
    if tx then
      print("SUCCESS: GM direct grant worked: " .. tostring(tx.transactionId))
    else
      print("REJECTED: " .. tostring(reason))
    end
  end)

  it("S002-R2: Member in roster - direct Ledger.Grant with nil audit", function()
    local dibs = load({ 
      wow = { 
        guildLeader = false, 
        playerName = "Member1-Realm",
        guildMembers = { "GM-Realm", "Member1-Realm", "Member2-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1, [3] = 2 }
      } 
    })
    
    print("Current player: " .. tostring(dibs.GetPlayerName()))
    print("IsGuildLeader: " .. tostring(IsGuildLeader()))
    print("Dibs.Permissions.IsGM: " .. tostring(dibs.Permissions.IsGM()))
    
    local tx, reason = dibs.Ledger.Grant("Member2-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId(), nil)
    
    if tx then
      print("VULNERABILITY: Member direct grant worked: " .. tostring(tx.transactionId))
    else
      print("Correctly rejected: " .. tostring(reason))
    end
  end)

  it("S002-R3: GM in roster - ProtectedActions.Execute", function()
    local dibs = load({ 
      wow = { 
        guildLeader = true, 
        playerName = "GM-Realm",
        guildMembers = { "GM-Realm", "Member1-Realm", "Member2-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1, [3] = 2 }
      } 
    })
    
    local result = dibs.ProtectedActions.Execute("ledger.grant", "GM-Realm", {
      playerName = "Member1-Realm",
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

  it("S002-R4: Member in roster - ProtectedActions.Execute", function()
    local dibs = load({ 
      wow = { 
        guildLeader = false, 
        playerName = "Member1-Realm",
        guildMembers = { "GM-Realm", "Member1-Realm", "Member2-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1, [3] = 2 }
      } 
    })
    
    local result = dibs.ProtectedActions.Execute("ledger.grant", "Member1-Realm", {
      playerName = "Member2-Realm",
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

  it("S002-R5: Direct call with spoofed audit.actor (GM pretending to be member)", function()
    local dibs = load({ 
      wow = { 
        guildLeader = true, 
        playerName = "GM-Realm",
        guildMembers = { "GM-Realm", "Member1-Realm", "Member2-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1, [3] = 2 }
      } 
    })
    
    -- GM calls direct API but spoofs audit to say it's a member
    local tx, reason = dibs.Ledger.Grant("Member1-Realm", 5, "Test", "spoof-test", dibs.GetCurrentSeasonId(), {
      actor = "Member1-Realm",
      actorName = "Member1-Realm",
      transactionId = "spoof-test-1"
    })
    
    if tx then
      print("VULNERABILITY: Spoofed actor grant succeeded: " .. tostring(tx.transactionId))
      print("Transaction actorId: " .. tostring(tx.actorId))
    else
      print("Rejected: " .. tostring(reason))
    end
  end)

  it("S002-R6: Direct call with spoofed audit.actor (member pretending to be GM)", function()
    local dibs = load({ 
      wow = { 
        guildLeader = false, 
        playerName = "Member1-Realm",
        guildMembers = { "GM-Realm", "Member1-Realm", "Member2-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1, [3] = 2 }
      } 
    })
    
    -- Member calls direct API but spoofs audit to say it's GM
    local tx, reason = dibs.Ledger.Grant("Member2-Realm", 5, "Test", "spoof-test", dibs.GetCurrentSeasonId(), {
      actor = "GM-Realm",
      actorName = "GM-Realm",
      transactionId = "spoof-test-2"
    })
    
    if tx then
      print("VULNERABILITY: Member spoofed-as-GM grant succeeded: " .. tostring(tx.transactionId))
      print("Transaction actorId: " .. tostring(tx.actorId))
    else
      print("Rejected: " .. tostring(reason))
    end
  end)

end)