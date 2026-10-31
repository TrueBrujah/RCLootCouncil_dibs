local loader = require("helpers.load_addon")

describe("Officer setup page help cache", function()
  it("reuses setup evaluation while navigating and refreshes it on demand", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 },
    } })
    local originalEvaluate = dibs.SetupAssistant.Evaluate
    local evaluations = 0
    dibs.SetupAssistant.Evaluate = function(...)
      evaluations = evaluations + 1
      return originalEvaluate(...)
    end

    local frame = dibs.OfficerUI.CreateWindow("automaticDibs")
    local afterOpen = evaluations
    assert_true(afterOpen > 0)
    frame:ActivateRoute("settings")
    assert_equal(afterOpen, evaluations)

    frame:Refresh()
    assert_equal(afterOpen + 1, evaluations)
  end)
end)
