local loader = require("helpers.load_addon")

describe("B11 sandbox provider", function()
  it("rejects entry while developer mode is disabled and exposes production by default", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    assert_equal("production", dibs.DeveloperSandbox.GetActiveProvider())
    local ok, reason = dibs.DeveloperSandbox.EnterSandbox({ clone = true })
    assert_false(ok)
    assert_equal("DEVELOPER_MODE_REQUIRED", reason)
  end)

  it("migrates the legacy single sandbox payload into the current guild bucket", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true },
      sandboxVariables = { schema = 1, payload = { marker = "legacy", backups = { { id = 1 } } } },
    })
    local persisted = dibs.DeveloperSandboxStore.GetPersisted()
    assert_equal("legacy", persisted.payload.marker)
    assert_nil(persisted.payload.backups)
    assert_true(dibs.DeveloperSandboxStore.GetPayload() ~= nil)
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
    for index = 1, 100001 do oversized[index] = index end
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

  it("keeps sandbox payloads per guild and omits recovery workflow state", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local db = dibs.GetDB()
    db.backups = { { snapshotId = "large-recovery-state", payload = { value = string.rep("x", 1000) } } }
    db.pendingRestores = { restore = { snapshot = db.backups[1] } }
    dibs.DeveloperMode.SetEnabled(true)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true }))
    local sandboxPayload = dibs.DeveloperSandboxStore.GetPayload()
    assert_nil(sandboxPayload.backups)
    assert_nil(sandboxPayload.pendingRestores)
    dibs.DeveloperSandbox.ExitSandbox()

    dibs.currentGuildKey = "realm:guild-two"
    assert_true(dibs.DeveloperSandboxStore.SavePayload({ marker = "guild-two" }))
    assert_equal("guild-two", dibs.DeveloperSandboxStore.GetPayload().marker)
    dibs.currentGuildKey = "realm:testguild"
    assert_nil(dibs.DeveloperSandboxStore.GetPayload().marker)
  end)
end)