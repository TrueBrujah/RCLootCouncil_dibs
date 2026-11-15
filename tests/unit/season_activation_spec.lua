local H = require("helpers.season_activation")

describe("atomic seasonal activation service", function()
  it("commits only the new season in the existing approved ledger and replays without duplication", function()
    local dibs, id, old = H.make()
    local ledgerId = dibs.Ledger.GetActiveLedgerId()
    local result, preview = H.activate(dibs, id)
    assert_equal(ledgerId, dibs.Ledger.GetActiveLedgerId())
    assert_equal(5, dibs.Ledger.GetBalance(H.members[1], old))
    assert_equal(3, dibs.Ledger.GetBalance(H.members[1], id))
    assert_equal(id, dibs.GetCurrentSeasonId())
    assert_equal("ACTIVE", dibs.SeasonalRoster.GetSeasonLifecycle(id).lifecycleState)
    local root = dibs.Ledger.GetCanonicalState().rootHash
    local replay = dibs.SeasonalRoster.ActivateSeason(id, preview.previewId, result.revision,
      "service-activate", "Activate reviewed roster", H.members[1], true)
    assert_true(replay.ok); assert_true(replay.idempotent)
    assert_equal(root, dibs.Ledger.GetCanonicalState().rootHash)
    assert_equal("OPERATION_CONFLICT", dibs.SeasonalRoster.ActivateSeason(id, preview.previewId, result.revision,
      "service-activate", "Changed request", H.members[1], true).code)
  end)

  it("leaves the complete guild bucket unchanged when batch staging or final validation fails", function()
    local dibs, id, old = H.make()
    local preview = assert(dibs.SeasonalRoster.PreviewActivation(id, H.members[1]))
    local before = dibs.Sync.CalculateContentHash(dibs.GetDB())
    local original = dibs.Ledger.ValidateSeasonAllocationBatch
    dibs.Ledger.ValidateSeasonAllocationBatch = function() return false, "INJECTED_PRECOMMIT_FAILURE" end
    local failed = dibs.SeasonalRoster.ActivateSeason(id, preview.previewId, preview.seasonRevision,
      "service-failure", "Injected failure", H.members[1], true)
    assert_false(failed.ok); assert_equal("INJECTED_PRECOMMIT_FAILURE", failed.code)
    assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetDB()))
    assert_equal(old, dibs.GetCurrentSeasonId())
    dibs.Ledger.ValidateSeasonAllocationBatch = original
    H.activate(dibs, id, "service-failure")
    assert_equal(3, dibs.Ledger.GetBalance(H.members[1], id))
  end)

  it("never persists the first row when a later detached row is invalid", function()
    local dibs, id = H.make()
    local before = dibs.Sync.CalculateContentHash(dibs.GetDB())
    local batch, reason = dibs.Ledger.PrepareSeasonAllocationBatch(id, {
      { character = H.members[1], characterKey = H.members[1]:lower(), allocation = 3 },
      { character = H.members[2], characterKey = H.members[2]:lower(), allocation = -1 },
    }, "invalid-second-row", H.members[1], "Failure injection", dibs.Ledger.GetDataRevision(), "INITIALIZE")
    assert_nil(batch); assert_equal("INVALID_ALLOCATION_ROW", reason)
    assert_equal(before, dibs.Sync.CalculateContentHash(dibs.GetDB()))
  end)

  it("keeps a commit when announcement delivery fails and requires explicit confirmation", function()
    local dibs, id = H.make()
    local preview = dibs.SeasonalRoster.PreviewActivation(id, H.members[1])
    assert_equal("CONFIRMATION_REQUIRED", dibs.SeasonalRoster.ActivateSeason(id, preview.previewId,
      preview.seasonRevision, "unconfirmed", "Needs confirmation", H.members[1]).code)
    dibs.SyncV2.BroadcastSeasonActivationDigest = function() error("network failed") end
    H.activate(dibs, id)
    assert_equal(id, dibs.GetCurrentSeasonId())
    assert_not_nil(dibs.SeasonalRoster.GetActivationManifest(id))
  end)

  it("rejects a forged public adoption purpose on a member client", function()
    local dibs, id = H.make()
    local player = H.load(H.members[3], dibs.DeepCopy(_G.RCLootCouncil_dibsDB))
    local preview = player.SeasonalRoster.PreviewActivation(id, H.members[1], "ADOPTION")
    assert_nil(preview)
  end)
end)
