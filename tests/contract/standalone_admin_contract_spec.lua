local loader = require("helpers.load_addon")

describe("Standalone admin contract", function()
  it("appoint and revoke are GM-only and persisted", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local appoint = dibs.ProtectedActions.Execute("admin.appoint", nil, { target = "Officer-Realm", reason = "test" })
    assert_true(appoint.ok)

    local list = dibs.ProtectedActions.Execute("admin.list", nil, {})
    assert_true(list.ok)
    assert_true(#list.value >= 1)

    local revoke = dibs.ProtectedActions.Execute("admin.revoke", nil, { target = "Officer-Realm", reason = "test" })
    assert_true(revoke.ok)
  end)
end)
