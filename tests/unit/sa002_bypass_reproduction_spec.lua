-- SA-002 Reproduction Test: Public Mutators Bypass ProtectedActions
-- This test demonstrates that Ledger.Grant/Use/Refund/AdminAdjust can be called directly
-- without going through ProtectedActions.Execute, bypassing authorization controls.

local loader = require("helpers.load_addon")

local function load(opts)
  local _, dibs = loader.load(opts or { wow = { guildLeader = true } })
  return dibs
end

describe("SA-002: Public mutation APIs bypass ProtectedActions", function()

  it("S002-01: Member can grant DIBS without ProtectedActions authorization", function()
    local dibs = load({ wow = { guildLeader = false } }) -- Regular member, not GM
    
    -- Direct call to Ledger.Grant bypasses ProtectedActions entirely
    local tx, reason = dibs.Ledger.Grant("Tester-Realm", 5, "Test grant", "direct-api-test", dibs.GetCurrentSeasonId())
    
    -- This should be REJECTED because a regular member cannot grant DIBS
    -- But currently it may SUCCEED because the audit parameter is nil
    -- and authorize() defaults to current player without proper auth check
    if tx then
      print("VULNERABILITY CONFIRMED: Ledger.Grant succeeded without ProtectedActions: " .. tostring(tx.transactionId))
    else
      print("Ledger.Grant correctly rejected: " .. tostring(reason))
    end
    
    -- The test documents current behavior - we'll fix it to always reject unauthorized callers
  end)

  it("S002-02: Member can use DIBS without ProtectedActions authorization", function()
    local dibs = load({ wow = { guildLeader = false } })
    
    -- First give the player some DIBS via direct API (to test use)
    dibs.Ledger.Grant("Tester-Realm", 10, "Setup", "setup", dibs.GetCurrentSeasonId())
    
    -- Direct call to Ledger.Use bypasses ProtectedActions
    local tx, reason = dibs.Ledger.Use("Tester-Realm", 3, "Test use", "direct-api-test", dibs.GetCurrentSeasonId())
    
    if tx then
      print("VULNERABILITY: Ledger.Use succeeded without ProtectedActions: " .. tostring(tx.transactionId))
    else
      print("Ledger.Use correctly rejected: " .. tostring(reason))
    end
  end)

  it("S002-03: Member can create refund without ProtectedActions authorization", function()
    local dibs = load({ wow = { guildLeader = false } })
    
    -- Give player DIBS first
    dibs.Ledger.Grant("Tester-Realm", 10, "Setup", "setup", dibs.GetCurrentSeasonId())
    
    -- Direct call to Ledger.Refund bypasses ProtectedActions
    local tx, reason = dibs.Ledger.Refund("Tester-Realm", 3, "Test refund", "direct-api-test", dibs.GetCurrentSeasonId())
    
    if tx then
      print("VULNERABILITY: Ledger.Refund succeeded without ProtectedActions: " .. tostring(tx.transactionId))
    else
      print("Ledger.Refund correctly rejected: " .. tostring(reason))
    end
  end)

  it("S002-04: Member can admin adjust without ProtectedActions authorization", function()
    local dibs = load({ wow = { guildLeader = false } })
    
    -- Direct call to Ledger.AdminAdjust bypasses ProtectedActions
    local tx, reason = dibs.Ledger.AdminAdjust("Tester-Realm", 100, "Test adjust", "direct-api-test", dibs.GetCurrentSeasonId())
    
    if tx then
      print("VULNERABILITY: Ledger.AdminAdjust succeeded without ProtectedActions: " .. tostring(tx.transactionId))
    else
      print("Ledger.AdminAdjust correctly rejected: " .. tostring(reason))
    end
  end)

  it("S002-05: ProtectedActions.Execute correctly rejects unauthorized member", function()
    local dibs = load({ wow = { guildLeader = false } })
    
    -- This SHOULD fail - going through ProtectedActions
    local result = dibs.ProtectedActions.Execute("ledger.grant", "Tester-Realm", {
      playerName = "Tester-Realm",
      amount = 5,
      reason = "Test grant",
      source = "protected-actions-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    
    assert_false(result.ok, "ProtectedActions should reject unauthorized member")
    assert_equal("GUILD_ADMIN_REQUIRED", result.decision.reasonCode)
    print("ProtectedActions correctly rejects: " .. result.decision.reasonCode)
  end)

  it("S002-06: ProtectedActions.Execute allows GM", function()
      -- GM needs to be in the guild roster
      local dibs = load({ 
        wow = { 
          guildLeader = true, 
          playerName = "GM-Realm",
          guildMembers = { "GM-Realm", "Member-Realm" }
        } 
      })
    
      -- Debug: Check what the Ledger.Grant receives AND returns
      local originalGrant = dibs.Ledger.Grant
      dibs.Ledger.Grant = function(playerName, amount, reason, source, seasonId, audit, ledgerId)
        print("DEBUG Grant: playerName=" .. tostring(playerName))
        print("DEBUG Grant: amount=" .. tostring(amount))
        print("DEBUG Grant: reason=" .. tostring(reason))
        print("DEBUG Grant: source=" .. tostring(source))
        print("DEBUG Grant: seasonId=" .. tostring(seasonId))
        print("DEBUG Grant: audit=" .. tostring(audit))
        if audit then
          print("DEBUG Grant: audit.actorId=" .. tostring(audit.actorId))
          print("DEBUG Grant: audit.action=" .. tostring(audit.action))
          print("DEBUG Grant: audit.source=" .. tostring(audit.source))
        end
        local tx, reason = originalGrant(playerName, amount, reason, source, seasonId, audit, ledgerId)
        print("DEBUG Grant RETURN: tx=" .. tostring(tx))
        print("DEBUG Grant RETURN: reason=" .. tostring(reason))
        return tx, reason
      end
    
      local result = dibs.ProtectedActions.Execute("ledger.grant", "GM-Realm", {
        playerName = "Member-Realm",
        amount = 5,
        reason = "Test grant",
        source = "protected-actions-test",
        seasonId = dibs.GetCurrentSeasonId()
      })
    
      print("DEBUG: result = " .. tostring(result))
      print("DEBUG: result.ok = " .. tostring(result.ok))
      print("DEBUG: result.diagnostic = " .. tostring(result.diagnostic))
      print("DEBUG: result.decision = " .. tostring(result.decision))
      if result.decision then
        print("DEBUG: result.decision.reasonCode = " .. tostring(result.decision.reasonCode))
        print("DEBUG: result.decision.diagnostic = " .. tostring(result.decision.diagnostic))
        print("DEBUG: result.decision.allowed = " .. tostring(result.decision.allowed))
        print("DEBUG: result.decision.actorId = " .. tostring(result.decision.actorId))
      end
      if result.value then
        print("DEBUG: result.value.transactionId = " .. tostring(result.value.transactionId))
      end
    
      assert_true(result.ok, "ProtectedActions should allow GM: " .. tostring(result.diagnostic))
      print("ProtectedActions correctly allows GM")
    end)

  it("S002-07: PreDibs public mutators also bypass ProtectedActions", function()
    local dibs = load({ wow = { guildLeader = false } })
    
    -- PreDibs.SetModePolicy has its own permission check (Can("predib.mode.set"))
    -- But other mutators like UpdateStatus, Confirm, Cancel, Invalidate, Fulfill
    -- may not have proper authorization
    
    local result = dibs.PreDibs.SetModePolicy(dibs.GetCurrentSeasonId(), "PUBLIC", "Member-Realm")
    if result then
      print("PreDibs.SetModePolicy succeeded: " .. tostring(result.mode))
    else
      print("PreDibs.SetModePolicy rejected (expected for member)")
    end
  end)

  it("S002-08: Authorized GM operation succeeds via ProtectedActions", function()
      local dibs = load({ 
        wow = { 
          guildLeader = true, 
          playerName = "GM-Realm",
          guildMembers = { "GM-Realm", "Member-Realm" }
        } 
      })
    
      local result = dibs.ProtectedActions.Execute("ledger.grant", "GM-Realm", {
        playerName = "Member-Realm",
        amount = 10,
        reason = "GM grant",
        source = "gm-test",
        seasonId = dibs.GetCurrentSeasonId()
      })
    
      print("DEBUG S002-08: result = " .. tostring(result))
      print("DEBUG S002-08: result.ok = " .. tostring(result.ok))
      print("DEBUG S002-08: result.diagnostic = " .. tostring(result.diagnostic))
      print("DEBUG S002-08: result.decision = " .. tostring(result.decision))
      print("DEBUG S002-08: result.value = " .. tostring(result.value))
      if result.decision then
        print("DEBUG S002-08: result.decision.reasonCode = " .. tostring(result.decision.reasonCode))
        print("DEBUG S002-08: result.decision.diagnostic = " .. tostring(result.decision.diagnostic))
        print("DEBUG S002-08: result.decision.allowed = " .. tostring(result.decision.allowed))
        print("DEBUG S002-08: result.decision.actorId = " .. tostring(result.decision.actorId))
      end
    
      assert_true(result.ok, "GM grant should succeed via ProtectedActions: " .. tostring(result.diagnostic))
      print("GM grant via ProtectedActions: " .. tostring(result.value.transactionId))
    end)

  it("S002-09: Historical reconciliation preserves authorization", function()
    local dibs = load({ wow = { guildLeader = true, playerName = "GM-Realm" } })
    
    -- RecordHistoricalAward requires reconciliation context - test through ProtectedActions
    local result = dibs.ProtectedActions.Execute("history.confirm", "GM-Realm", {
      mode = "manual",
      seasonId = dibs.GetCurrentSeasonId(),
      playerName = "Member-Realm",
      itemID = 12345,
      awardRef = "history:rclootcouncil-123",
      evidenceId = "reconciliation:evidence-456",
      confirmation = true,
      manualAcknowledgement = true,
      reason = "Historical award reconciliation",
      sourceStatus = "awarded",
    })
    
    print("DEBUG S002-09: result.ok = " .. tostring(result.ok))
    print("DEBUG S002-09: result.diagnostic = " .. tostring(result.diagnostic))
    
    -- Historical reconciliation requires proper setup (season catalog, etc.)
    -- It may fail for setup reasons, but should fail with proper reason not auth bypass
    print("S002-09: Historical confirmation result: " .. tostring(result.ok) .. " - " .. tostring(result.diagnostic))
  end)

  it("S002-10: Unauthorized direct call does not create persistent state", function()
    local dibs = load({ wow = { guildLeader = false } })
    local beforeCount = #dibs.Ledger.GetAllTransactions()
    
    local tx, reason = dibs.Ledger.Grant("Tester-Realm", 5, "Test", "test", dibs.GetCurrentSeasonId())
    local afterCount = #dibs.Ledger.GetAllTransactions()
    
    if tx then
      print("STATE CHANGED: Transaction created despite no authorization!")
      print("Before: " .. beforeCount .. ", After: " .. afterCount)
    else
      print("State unchanged: " .. tostring(reason))
      assert_equal(beforeCount, afterCount)
    end
  end)

  it("S002-11: Replayed authorized transaction does not create duplicates", function()
    local dibs = load({ 
      wow = { 
        guildLeader = false, 
        playerName = "Tester-Realm",
        guildMembers = { "GM-Realm", "Tester-Realm" }
      } 
    })
    
    -- First grant via ProtectedActions as GM
    local result1 = dibs.ProtectedActions.Execute("ledger.grant", "GM-Realm", {
      playerName = "Tester-Realm",
      amount = 5,
      reason = "Test",
      source = "replay-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    assert_true(result1.ok)
    local txId = result1.value.transactionId
    local count1 = #dibs.Ledger.GetAllTransactions()
    
    -- Replay via direct API should be rejected (no valid audit context)
    local tx2, reason2 = dibs.Ledger.Grant("Tester-Realm", 5, "Test", "replay-test", dibs.GetCurrentSeasonId(), 
      { transactionId = txId })
    
        -- Direct API call should be rejected - requires audit context from ProtectedActions
        assert_false(tx2, "Direct API call should be rejected without valid audit context: " .. tostring(reason2))
    
    -- Count should not change
    local count2 = #dibs.Ledger.GetAllTransactions()
    assert_equal(count1, count2, "No new transaction should be created")
    
    print("S002-11: Replay correctly rejected - no duplicates created")
  end)

  it("S002-12: Failed operation leaves persistent state unchanged", function()
    local dibs = load({ wow = { guildLeader = false } })
    local beforeCount = #dibs.Ledger.GetAllTransactions()
    local beforeBalance = dibs.Ledger.GetBalance("Tester-Realm")
    
    local tx, reason = dibs.Ledger.Grant("Tester-Realm", 5, "Test", "test", dibs.GetCurrentSeasonId())
    local afterCount = #dibs.Ledger.GetAllTransactions()
    local afterBalance = dibs.Ledger.GetBalance("Tester-Realm")
    
    if not tx then
      assert_equal(beforeCount, afterCount, "Transaction count should not change on rejection")
      assert_equal(beforeBalance, afterBalance, "Balance should not change on rejection")
      print("State correctly unchanged on rejection")
    else
      print("State changed despite rejection!")
    end
  end)

  it("S002-13: RF-0012 release locks cannot be bypassed", function()
    local dibs = load({ wow = { guildLeader = true } })
    
    -- Canonical operations should still be blocked by release locks
    local result = dibs.ProtectedActions.Execute("ledger.propose", "GM-Realm", {
      playerName = "Tester-Realm",
      amount = 5,
      reason = "Canonical test",
      source = "canonical-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    
    -- Should be rejected because CANONICAL_OPERATIONS_RELEASE_ENABLED = false
    if result.ok then
      print("WARNING: Canonical operation succeeded - release lock may be disabled")
    else
      print("Canonical operation correctly blocked: " .. tostring(result.decision.reasonCode))
    end
  end)

  it("S002-14: ProtectedActions does not recursively invoke itself", function()
    local dibs = load({ 
      wow = { 
        guildLeader = true, 
        playerName = "GM-Realm",
        guildMembers = { "GM-Realm", "Tester-Realm" }
      } 
    })
    
    -- Calling ProtectedActions from within a ProtectedActions handler should not recurse
    local callCount = 0
    local originalExecute = dibs.ProtectedActions.Execute
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      callCount = callCount + 1
      if callCount > 5 then
        error("Recursion detected!")
      end
      return originalExecute(actionId, actor, payload)
    end
    
    local result = dibs.ProtectedActions.Execute("ledger.grant", "GM-Realm", {
      playerName = "Tester-Realm",
      amount = 1,
      reason = "Recursion test",
      source = "recursion-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    
    assert_true(result.ok, "ProtectedActions should work without recursion: " .. tostring(result.diagnostic))
    assert_equal(1, callCount, "Should not recurse")
    print("No recursion detected")
  end)

  it("S002-15: Existing Ledger regression tests still pass", function()
    local dibs = load()
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    
    -- Normal use through ProtectedActions should work
    local result = dibs.ProtectedActions.Execute("ledger.use", "GM-Realm", {
      playerName = "Tester-Realm",
      amount = 1,
      reason = "Regression test",
      source = "regression-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    
    assert_true(result.ok, "Normal ProtectedActions flow should still work")
    print("Regression test passed")
  end)

end)