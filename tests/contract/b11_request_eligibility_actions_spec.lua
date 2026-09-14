local loader = require("helpers.load_addon")

describe("B11e request and eligibility actions", function()
  it("routes eligibility saves through the protected action boundary", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local directCalls, actions = 0, {}
    local originalSetPolicy = dibs.CharacterEligibility.SetPolicy
    local originalExecute = dibs.ProtectedActions.Execute
    dibs.CharacterEligibility.SetPolicy = function()
      directCalls = directCalls + 1
      return nil, "DIRECT_POLICY_WRITE"
    end
    dibs.ProtectedActions.Execute = function(action, actor, payload)
      table.insert(actions, { action = action, actor = actor, payload = payload })
      return { ok = true, value = { family = payload.family } }
    end

    local result = dibs.OfficerUI.SaveEligibilityPolicy({
      seasonId = dibs.GetCurrentSeasonId(), family = "TOKEN", completionThreshold = 5,
    })

    dibs.CharacterEligibility.SetPolicy = originalSetPolicy
    dibs.ProtectedActions.Execute = originalExecute
    assert_true(result.ok)
    assert_equal(0, directCalls)
    assert_equal("eligibility.policy.set", actions[1].action)
    assert_equal(5, actions[1].payload.completionThreshold)
  end)

  it("routes Pre-Dib mode changes through the protected action boundary", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local directCalls, action
    local originalSetMode = dibs.PreDibs.SetModePolicy
    local originalExecute = dibs.ProtectedActions.Execute
    dibs.PreDibs.SetModePolicy = function()
      directCalls = (directCalls or 0) + 1
      return nil, "DIRECT_MODE_WRITE"
    end
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      action = { id = actionId, payload = payload }
      return { ok = true, value = payload }
    end

    local result = dibs.OfficerUI.SavePreDibMode(dibs.GetCurrentSeasonId(), "ENCOUNTER")

    dibs.PreDibs.SetModePolicy = originalSetMode
    dibs.ProtectedActions.Execute = originalExecute
    assert_true(result.ok)
    assert_equal(0, directCalls or 0)
    assert_equal("predib.mode.set", action.id)
    assert_equal("ENCOUNTER", action.payload.mode)
  end)

  it("keeps unsaved eligibility drafts in the projection until an explicit save", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local calls = 0
    local originalExecute = dibs.ProtectedActions.Execute
    dibs.ProtectedActions.Execute = function()
      calls = calls + 1
      return { ok = true }
    end

    local projection = dibs.OfficerUI.GetEligibilityProjection(dibs.GetCurrentSeasonId(), {
      expanded = true,
      draft = { TOKEN = { enforcementOutcome = "warn", completionThreshold = 6 } },
    })

    dibs.ProtectedActions.Execute = originalExecute
    assert_true(projection.unsaved)
    assert_equal("warn", projection.byFamily.TOKEN.currentState.enforcementOutcome)
    assert_equal(6, projection.byFamily.TOKEN.currentState.completionThreshold)
    assert_equal(0, calls)
  end)
end)
