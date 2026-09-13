local loader = require("helpers.load_addon")

describe("B11 sandbox scenarios", function()
  it("simulates named roles and faults without traffic or live evidence", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.DeveloperMode.SetEnabled(true)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true }))

    for _, role in ipairs({ "player", "officer", "guild_master", "coordinator", "recovery" }) do
      local result = dibs.DeveloperSandboxScenarios.Execute("role_" .. role)
      assert_true(result.ok, role)
      assert_equal(role, dibs.DeveloperSandbox.GetStatus().role)
    end
    for _, scenario in ipairs({ "missing_coordinator", "stale_peer", "duplicate_event", "malformed_payload" }) do
      local result = dibs.DeveloperSandboxScenarios.Execute(scenario)
      assert_true(result.ok, scenario)
    end

    assert_equal(0, #(_G.__sentAddonMessages or {}))
    assert_equal(0, #(_G.__sentChatMessages or {}))
    assert_nil(dibs.RCLootCouncil.GetLastEvidence and dibs.RCLootCouncil.GetLastEvidence())
  end)
end)