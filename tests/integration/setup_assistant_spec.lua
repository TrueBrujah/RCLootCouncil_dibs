local loader = require("helpers.load_addon")

describe("First installation assistant integration", function()
  it("delegates local dry-run without creating ledger state", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local before = #((dibs.GetDB() or {}).ledger and dibs.GetDB().ledger.transactions or {})
    local result = dibs.SetupAssistant.RunDryRun({
      item = 275658,
      winner = "Tester-Realm",
      response = "DIB",
      status = "test",
      sessionIdentity = "setup-assistant-test",
    }, { allowPlayer = true })
    assert_not_nil(result)
    assert_equal("would_ignore", result.outcome)
    local after = #((dibs.GetDB() or {}).ledger and dibs.GetDB().ledger.transactions or {})
    assert_equal(before, after)
    assert_false(result.wouldConsumeDib)
  end)

  it("returns a bounded unavailable result when the dry-run service is absent", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local original = dibs.DryRun.Run
    dibs.DryRun.Run = nil
    local result, reason = dibs.SetupAssistant.RunDryRun({ item = 275658 }, { allowPlayer = true })
    dibs.DryRun.Run = original
    assert_equal(nil, result)
    assert_equal("DRY_RUN_UNAVAILABLE", reason)
  end)
end)
