local loader = require("helpers.load_addon")

describe("Identity roster snapshot", function()
  it("keeps every roster entry so callers can detect duplicate names", function()
    local _, dibs = loader.load({ wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Tester-Realm", "Twin", "Zed-Realm", "Twin" },
      guildRankIndices = { [1] = 0, [2] = 2, [3] = 4, [4] = 3 },
    } })

    local snapshot = dibs.Identity.GetRosterSnapshot()

    assert_equal(4, #snapshot, "duplicate roster names must not be merged into one entry")
    local twins = {}
    for _, member in ipairs(snapshot) do
      if member.displayName == "Twin-Realm" then twins[#twins + 1] = member end
    end
    assert_equal(2, #twins)
    assert_equal(twins[1].memberKey, twins[2].memberKey)
    assert_equal(2, twins[1].rankIndex, "duplicates keep roster order")
    assert_equal(3, twins[2].rankIndex, "duplicates keep roster order")
  end)

  it("orders entries by member key and then by roster position", function()
    local _, dibs = loader.load({ wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Zed-Realm", "Alice-Realm", "Tester-Realm" },
      guildRankIndices = { [1] = 4, [2] = 3, [3] = 0 },
    } })

    local keys = {}
    for _, member in ipairs(dibs.Identity.GetRosterSnapshot()) do keys[#keys + 1] = member.memberKey end

    assert_equal("alice-realm", keys[1])
    assert_equal("tester-realm", keys[2])
    assert_equal("zed-realm", keys[3])
  end)

  it("returns defensive copies from GetRosterMembers without changing the shared snapshot", function()
    local _, dibs = loader.load({ wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Tester-Realm", "Twin", "Twin" },
      guildRankIndices = { [1] = 0, [2] = 2, [3] = 3 },
    } })

    local snapshot = dibs.Identity.GetRosterSnapshot()
    local members = dibs.Identity.GetRosterMembers()
    members[1].displayName = "Changed"

    assert_equal(3, #members)
    assert_true(snapshot[1].displayName ~= "Changed")
  end)
end)
