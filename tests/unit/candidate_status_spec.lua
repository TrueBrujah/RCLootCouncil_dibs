local loader = require("helpers.load_addon")

describe("Candidate status", function()
  it("marks pre-dib candidate as eligible", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 12345, "Item", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)
    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 12345)
    assert_true(status.hasPreDib)
    assert_true(status.canUseDib)
    assert_equal("pre-dib", status.status)
  end)

  it("locks non-pre-dib candidates when item has a confirmed pre-dib", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Reserved-Realm", 12346, "Item", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)

    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 12346)
    assert_true(status.hasAnyConfirmedPreDib)
    assert_true(status.lockedOutByPreDib)
    assert_false(status.canUseDib)
    assert_equal("pre-dib-locked", status.status)
  end)

  it("keeps confirmed pre-dib candidate eligible even at zero balance", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 12347, "Item", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)

    local spend = dibs.ProtectedActions.Execute("ledger.use", nil, {
      playerName = "Tester-Realm",
      amount = 1,
      reason = "test spend",
      source = "test",
    })
    assert_true(spend.ok)

    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 12347)
    assert_true(status.hasPreDib)
    assert_true(status.canUseDib)
    assert_false(status.lockedOutByPreDib)
  end)

  it("does not change candidate status when AceGUI windows are opened", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 12348, "Item", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)

    dibs.PlayerUI.CreateWindow()
    dibs.OfficerUI.CreateWindow()
    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 12348)

    assert_true(status.hasPreDib)
    assert_true(status.canUseDib)
    assert_equal("pre-dib", status.status)
  end)
end)
