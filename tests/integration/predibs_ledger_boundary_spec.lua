local loader = require("helpers.load_addon")

describe("Pre-Dib ledger boundary", function()
  it("does not consume a Dib when a request is created", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local before = #dibs.Ledger.GetAllTransactions()
    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21021, "Item 21021", dibs.GetCurrentSeasonId(), "test")

    assert_not_nil(request)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("does not consume a Dib or fulfill a request when a Vault acquisition is recorded", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21022, "Item 21022", dibs.GetCurrentSeasonId(), "test", { difficulty = "Heroic" })
    local before = #dibs.Ledger.GetAllTransactions()

    local record = dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21022, "Heroic")

    assert_not_nil(record)
    assert_equal("VAULT", record.source)
    assert_equal("confirmed", request.status)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
