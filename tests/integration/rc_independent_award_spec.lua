local loader = require("helpers.load_addon")

local function retailRC()
  local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = { guid = "Player-1-TESTER", name = "Tester-Realm" } })
  local ml = {
    lootTable = {
      [7] = {
        history = { id = "1700000000-1", lootWon = "item:19019", response = "DIB" },
        items = { [1] = { link = "item:19019" } },
      },
      [8] = {
        history = { id = "1700000000-2", lootWon = "item:19020", response = "Major Upgrade" },
        items = { [1] = { link = "item:19020" } },
      },
      [9] = {
        history = { id = "1700000000-3", lootWon = "item:19021", response = "DIB" },
        items = { [1] = { link = "item:19021" } },
      },
    },
  }
  rc.GetModule = function(_, name)
    if name == "RCLootCouncilML" then return ml end
  end
  return rc, ml
end

describe("RCLootCouncil Independent Raid Award Integration", function()
  it("intercepts DIB awards during active independent raid session with local deduction and zero guild sync", function()
    local rc, ml = retailRC()
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      playerName = "Tester-Realm", guildLeader = false,
      guildMembers = { "Tester-Realm", "RaiderA-Realm" },
      guildRankIndices = { [1] = 1, [2] = 3 },
      rclootcouncilVersion = "3.23.3",
    } })

    -- Start independent raid session with 1 starting point
    local start = dibs.IndependentRaid.StartSession("Pug Raid", 1)
    assert_true(start.ok)
    assert_true(dibs.IndependentRaid.IsSessionActive())

    -- First award to RaiderA with DIB response
    local result1 = dibs.RCLootCouncil.HandleAwardCallback(
      "RCMLAwardSuccess", 7, "RaiderA-Realm", "normal", "item:19019", "DIB", "1700000000-1")
    assert_true(result1.ok)
    assert_equal("independent_consumed", result1.outcome)
    assert_equal(0, dibs.IndependentRaid.GetPlayerBalance("RaiderA-Realm"))

    -- Verify guild sync is inhibited during independent session
    local sentToGuild = dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    assert_false(sentToGuild)

    -- Second award to RaiderA with non-DIB response succeeds as free award without spending points
    local result2 = dibs.RCLootCouncil.HandleAwardCallback(
      "RCMLAwardSuccess", 8, "RaiderA-Realm", "normal", "item:19020", "Major Upgrade", "1700000000-2")
    assert_true(result2.ok)
    assert_equal("independent_free_award", result2.outcome)
    assert_equal(0, dibs.IndependentRaid.GetPlayerBalance("RaiderA-Realm"))

    -- Third award with DIB response fails due to insufficient points (0 points left)
    local result3 = dibs.RCLootCouncil.HandleAwardCallback(
      "RCMLAwardSuccess", 9, "RaiderA-Realm", "normal", "item:19021", "DIB", "1700000000-3")
    assert_false(result3.ok)
    assert_equal("INDEPENDENT_NO_POINTS", result3.reasonCode)

    -- Conclude session
    dibs.IndependentRaid.ConcludeSession()
    assert_false(dibs.IndependentRaid.IsSessionActive())
  end)
end)
