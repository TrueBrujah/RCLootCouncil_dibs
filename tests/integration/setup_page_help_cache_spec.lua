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

    -- Ordinary pages use no full setup scan. The first supported guidance
    -- route builds the report; later routes reuse it until explicit refresh.
    local frame = dibs.OfficerUI.CreateWindow("settings")
    local afterOpen = evaluations
    assert_equal(0, afterOpen)
    frame:ActivateRoute("installation")
    assert_true(evaluations > 0)
    local afterBuild = evaluations
    frame:ActivateRoute("ranks")
    assert_equal(afterBuild, evaluations)
    frame:ActivateRoute("installation")
    assert_equal(afterBuild, evaluations)
    frame:Refresh()
    assert_equal(afterBuild + 1, evaluations)
  end)
end)
