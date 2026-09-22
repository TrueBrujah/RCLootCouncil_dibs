local loader = require("helpers.load_addon")

describe("Notifications wiring", function()
  it("notifies local Pre-Dib lifecycle and Vault acquisition events without ledger mutation", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local messages = {}
    dibs.Message = function(text) messages[#messages + 1] = text end
    local season = dibs.Seasons.GetCurrent()
    local transactionsBefore = #dibs.Ledger.GetTransactions(season.id)
    local request = dibs.PreDibs.Create(dibs.GetPlayerName(), 19019, "Midnight Blade", season.id)
    dibs.PreDibs.Confirm(request.requestId)
    dibs.PreDibs.Cancel(request.requestId)
    dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 19020, "Normal", { itemName = "Vault Item" })
    assert_true(#messages >= 3)
    assert_equal(transactionsBefore, #dibs.Ledger.GetTransactions(season.id))
  end)
end)
