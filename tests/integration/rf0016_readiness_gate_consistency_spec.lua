local loader = require("helpers.load_addon")

-- RF-0016 regression suite.
--
-- RF-0016 - "Readiness : la porte d'attribution live contredit le drapeau
-- liveConsumptionAllowed du meme resultat"
-- (docs/code-audit/INDEX.md#rf-0016).
--
-- `Readiness.Evaluate` computes `liveConsumptionAllowed`, which is true only
-- when the integration and the standalone status are both "Ready".
-- `Readiness.CanProcessLiveAward` ignored that flag and returned true for
-- every non-blocked state, so a degraded integration produced a result whose
-- flag said "not allowed" while the gate function said "allowed".

describe("RF-0016 the live award gate agrees with the result it returns", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    return dibs
  end

  it("refuses a degraded integration that the result marks as not allowed", function()
    local dibs = setup()
    dibs.Readiness.Evaluate = function()
      return { integrationStatus = "Degraded", standaloneStatus = "Ready", status = "Degraded",
        liveConsumptionAllowed = false, reasonCodes = {} }
    end
    local allowed, result = dibs.Readiness.CanProcessLiveAward()
    assert_false(allowed, "the gate allowed a degraded integration")
    assert_false(result.liveConsumptionAllowed,
      "the result no longer reports the same decision")
  end)

  it("keeps the gate and the flag in agreement for every non-blocked state", function()
    local dibs = setup()
    local states = {
      { integrationStatus = "Ready", standaloneStatus = "Ready", liveConsumptionAllowed = true },
      { integrationStatus = "Degraded", standaloneStatus = "Ready", liveConsumptionAllowed = false },
      { integrationStatus = "Ready", standaloneStatus = "Degraded", liveConsumptionAllowed = false },
    }
    for _, state in ipairs(states) do
      dibs.Readiness.Evaluate = function()
        return { integrationStatus = state.integrationStatus, standaloneStatus = state.standaloneStatus,
          status = state.integrationStatus, liveConsumptionAllowed = state.liveConsumptionAllowed, reasonCodes = {} }
      end
      local allowed, result = dibs.Readiness.CanProcessLiveAward()
      assert_equal(state.liveConsumptionAllowed, allowed,
        "the gate and liveConsumptionAllowed disagree for " .. state.integrationStatus)
      assert_equal(state.liveConsumptionAllowed, result.liveConsumptionAllowed,
        "the returned result disagrees with the gate for " .. state.integrationStatus)
    end
  end)

  it("still allows an unavailable integration outside a live session", function()
    local dibs = setup()
    -- A missing RCLootCouncil integration is expected outside a raid and must
    -- not break the local RC callback path.
    dibs.Readiness.Evaluate = function()
      return { integrationStatus = "Unavailable", standaloneStatus = "Ready", status = "Unavailable",
        liveConsumptionAllowed = false, reasonCodes = {} }
    end
    local allowed = dibs.Readiness.CanProcessLiveAward()
    assert_true(allowed, "an unavailable integration outside a live session was refused")
  end)

  it("still refuses a blocked integration", function()
    local dibs = setup()
    dibs.Readiness.Evaluate = function()
      return { integrationStatus = "Blocked", standaloneStatus = "Ready", status = "Blocked",
        liveConsumptionAllowed = false, reasonCodes = { RC_MASTER_LOOTER_UNVERIFIABLE = true } }
    end
    local allowed = dibs.Readiness.CanProcessLiveAward()
    assert_false(allowed, "a blocked integration was allowed")
  end)
end)
