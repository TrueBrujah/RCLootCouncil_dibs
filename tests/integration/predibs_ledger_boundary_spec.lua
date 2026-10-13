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
    assert_equal("VAULT_MANUAL", record.source)
    assert_equal("confirmed", request.status)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("migrates legacy Pre-Dibs into the primary ledger store", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local db = dibs.GetDB()
    db.preDibs = {
      requests = {
        {
          requestId = "legacy-primary-request",
          playerName = "Tester-Realm",
          itemID = 21023,
          seasonId = dibs.GetCurrentSeasonId(),
          status = "confirmed",
          revision = 1,
        },
      },
      modePolicies = { [dibs.GetCurrentSeasonId()] = { mode = "ENCOUNTER" } },
    }

    local history = dibs.PreDibs.GetHistory("guild-primary")

    assert_equal(1, #history)
    assert_equal("guild-primary", history[1].ledgerId)
    assert_equal("ENCOUNTER", dibs.PreDibs.GetModePolicy(dibs.GetCurrentSeasonId(), "guild-primary").mode)
  end)

  it("isolates requests and mode policies by approved ledger without switching the active ledger", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
    local proposal = dibs.MultiLedger.ProposeLedger("Tester-Realm", "Alt Raid")
    assert_true(proposal.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposal.ledgerId).ok)
    local seasonId = dibs.GetCurrentSeasonId()
    local primary = dibs.PreDibs.CreatePublic("Tester-Realm", 21024, "Primary item", seasonId, "test")
    local alternate = dibs.PreDibs.CreatePublic("Tester-Realm", 21024, "Alt item", seasonId, "test", {
      ledgerId = proposal.ledgerId,
    })
    assert_not_nil(primary)
    assert_not_nil(alternate)

    local alternateMode = dibs.PreDibs.SetModePolicy(seasonId, "ENCOUNTER", "Tester-Realm", proposal.ledgerId)
    assert_not_nil(alternateMode)
    assert_equal(proposal.ledgerId, alternate.ledgerId)
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    assert_equal(primary.requestId, dibs.PreDibs.GetHistory("guild-primary")[1].requestId)
    assert_equal(alternate.requestId, dibs.PreDibs.GetHistory(proposal.ledgerId)[1].requestId)
    assert_equal("WILD_OPEN", dibs.PreDibs.GetModePolicy(seasonId, "guild-primary").mode)
    assert_equal("ENCOUNTER", dibs.PreDibs.GetModePolicy(seasonId, proposal.ledgerId).mode)
    assert_equal(primary.requestId, dibs.GetDB().preDibs.requests[1].requestId)

    local primaryManifest = dibs.Sync.BuildManifest("guild-primary")
    local alternateManifest = dibs.Sync.BuildManifest(proposal.ledgerId)
    assert_nil(primaryManifest.ledgerId)
    assert_equal(proposal.ledgerId, alternateManifest.ledgerId)
    assert_equal(primary.requestId, primaryManifest.index[1].requestId)
    assert_equal(alternate.requestId, alternateManifest.index[1].requestId)
  end)

  it("applies a verified synchronized request only to its approved ledger", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    dibs.SyncV2.BroadcastCatalogDigest = function() return true, "TEST_SENT" end
    local proposal = dibs.MultiLedger.ProposeLedger("Tester-Realm", "Alt Raid")
    assert_true(proposal.ok)
    assert_true(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposal.ledgerId).ok)
    local seasonId = dibs.GetCurrentSeasonId()
    local incoming = {
      requestId = "remote-alt-request",
      playerName = "Tester-Realm",
      itemID = 21025,
      seasonId = seasonId,
      status = "confirmed",
      revision = 1,
      ledgerId = proposal.ledgerId,
    }

    local applied, reason = dibs.PreDibs.ApplyVerifiedSyncRecord(incoming, "Tester-Realm", proposal.ledgerId)

    assert_not_nil(applied, tostring(reason))
    assert_equal(0, #dibs.PreDibs.GetHistory("guild-primary"))
    assert_equal("remote-alt-request", dibs.PreDibs.GetHistory(proposal.ledgerId)[1].requestId)
    assert_equal("guild-primary", dibs.MultiLedger.GetActiveLedgerId())
    local missingScope = dibs.DeepCopy(incoming)
    missingScope.requestId = "missing-ledger-scope"
    missingScope.ledgerId = nil
    local unscoped, unscopedReason = dibs.PreDibs.ApplyVerifiedSyncRecord(missingScope, "Tester-Realm", proposal.ledgerId)
    assert_nil(unscoped)
    assert_equal("LEDGER_SCOPE_MISMATCH", unscopedReason)
    local unapproved = dibs.DeepCopy(incoming)
    unapproved.ledgerId = "not-approved"
    local rejected, rejectReason = dibs.PreDibs.ApplyVerifiedSyncRecord(unapproved, "Tester-Realm", "not-approved")
    assert_nil(rejected)
    assert_equal("LEDGER_NOT_APPROVED", rejectReason)
    local accepted, validationReason = dibs.PreDibs.ValidatePublicRequest(21025, seasonId, nil, "not-approved")
    assert_nil(accepted)
    assert_equal("LEDGER_NOT_APPROVED", validationReason)
  end)
end)
