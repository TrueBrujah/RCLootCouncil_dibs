local loader = require("helpers.load_addon")

describe("permission roster lookup work", function()
  it("reuses the invalidation-aware identity index across decisions and refreshes it on roster changes", function()
    local members, ranks = {}, {}
    for index = 1, 100 do
      members[index] = "Audit" .. index .. "-Realm"
      ranks[index] = 3
    end
    members[100] = "Officer-Realm"
    ranks[100] = 1
    local _, dibs = loader.load({ savedVariables = {}, wow = {
      guildLeader = false,
      playerName = members[100],
      guildMembers = members,
      guildRankIndices = ranks,
    } })

    local reads, getRosterInfo = 0, _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(...)
      reads = reads + 1
      return getRosterInfo(...)
    end
    for _ = 1, 10 do
      local decision = dibs.Permissions.Evaluate("settings.modify", nil)
      assert_true(decision.allowed)
      assert_equal("GUILD_OFFICER", decision.reasonCode)
    end
    assert_true(reads <= #members,
      "ten authority checks should use at most one full roster refresh, got " .. reads .. " roster reads")

    local readsBeforeInvalidation = reads
    ranks[100] = 3
    dibs.Identity.OnRosterChanged()
    local decision = dibs.Permissions.Evaluate("settings.modify", nil)
    assert_false(decision.allowed, "a changed guild rank must revoke the cached officer decision")
    assert_equal("GUILD_ADMIN_REQUIRED", decision.reasonCode)
    assert_true(reads > readsBeforeInvalidation, "the invalidated roster should be refreshed")
    assert_true(reads - readsBeforeInvalidation <= #members,
      "the refresh should traverse the roster once, got " .. (reads - readsBeforeInvalidation) .. " reads")
    _G.GetGuildRosterInfo = getRosterInfo
  end)
end)
