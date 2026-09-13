local loader = require("helpers.load_addon")

describe("B11 sandbox provider", function()
  it("rejects entry while developer mode is disabled and exposes production by default", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    assert_equal("production", dibs.DeveloperSandbox.GetActiveProvider())
    local ok, reason = dibs.DeveloperSandbox.EnterSandbox({ clone = true })
    assert_false(ok)
    assert_equal("DEVELOPER_MODE_REQUIRED", reason)
  end)

  it("rejects malformed, future, and oversized retained stores", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true },
      sandboxVariables = { schema = 999, payload = {} },
    })
    dibs.DeveloperMode.SetEnabled(true)
    local ok, reason = dibs.DeveloperSandbox.EnterSandbox()
    assert_false(ok)
    assert_equal("FUTURE_SANDBOX_SCHEMA", reason)

    local _, malformed = loader.load({
      wow = { guildLeader = true },
      sandboxVariables = { schema = 1, payload = "not-a-table" },
    })
    malformed.DeveloperMode.SetEnabled(true)
    ok, reason = malformed.DeveloperSandbox.EnterSandbox()
    assert_false(ok)
    assert_equal("INVALID_SANDBOX_PAYLOAD", reason)

    local oversized = {}
    for index = 1, 20001 do oversized[index] = index end
    local _, tooLarge = loader.load({
      wow = { guildLeader = true },
      sandboxVariables = { schema = 1, payload = oversized },
    })
    tooLarge.DeveloperMode.SetEnabled(true)
    ok, reason = tooLarge.DeveloperSandbox.EnterSandbox()
    assert_false(ok)
    assert_equal("SANDBOX_STORE_TOO_LARGE", reason)
  end)

  it("fails closed when a sandbox provider is mixed with protected production authority", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.DeveloperMode.SetEnabled(true)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true }))
    local result = dibs.ProtectedActions.Execute("ledger.grant", nil, {
      playerName = "Tester-Realm", amount = 1, reason = "sandbox probe",
    })
    assert_false(result.ok)
    assert_equal("MIXED_PROVIDER_REJECTED", result.reasonCode)
    local _, _, relayReason = dibs.RaidRelay.Broadcast("GUILD")
    assert_equal("MIXED_PROVIDER_REJECTED", relayReason)
  end)
end)