local loader = require("helpers.load_addon")

describe("seasonal Main/Alt balance correction", function()
  it("retains the Main balance and makes an audited Alt correction replay-safe", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      playerName = "Tester-Realm", guildMembers = { "Tester-Realm", "Alt-Realm" },
      guildRankIndices = { [1] = 0, [2] = 3 } } })
    assert_true(dibs.Governance.AdoptInitial(nil, {
      reason = "seasonal balance correction test",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    }))
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
      { allowPublicPreDibs = true, preDibModes = {} }, "seasonal balance correction test"))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil,
      "enable seasonal roster for this test"))
    local now = dibs.GetTimestamp()
    local created = dibs.SeasonalRoster.CreateSeason({ name = "Balance unit season",
      startAt = now + 10000, registrationStartAt = now + 5000 }, "balance-unit-create", "Tester-Realm")
    assert_true(created.ok, tostring(created.code))
    local relationship = dibs.CharacterEligibility.DeclareRelationship({ seasonId = created.value,
      mainCharacter = "Tester-Realm", altCharacter = "Alt-Realm" }, "Tester-Realm")
    assert_not_nil(relationship)
    assert_equal("approved", dibs.CharacterEligibility.ApproveRelationship(
      relationship.relationshipId, "Tester-Realm").status)

    for _, entry in ipairs({ { "Tester-Realm", 3 }, { "Alt-Realm", 2 } }) do
      local granted = dibs.ProtectedActions.Execute("ledger.adjust", nil, {
        playerName = entry[1], amount = entry[2], reason = "Seed balance unit fixture",
        source = "MANUAL_ADMIN", seasonId = created.value, confirmation = true,
      })
      assert_true(granted.ok, tostring(granted.diagnostic))
    end

    local preview = assert(dibs.SeasonalRoster.GetBalanceReconciliationPreview(
      created.value, "Tester-Realm", "Tester-Realm"))
    assert_equal(3, preview.resultingPersonBalance)
    assert_equal(1, #preview.adjustments)
    assert_equal(-2, preview.adjustments[1].amount)
    local expected = { previewId = preview.previewId, sourceLedgerRevision = preview.sourceLedgerRevision,
      eligibilityRevision = preview.eligibilityRevision, mainCharacterKey = preview.mainCharacterKey,
      personGroupId = preview.personGroupId, ledgerId = preview.ledgerId }

    local unconfirmed = dibs.SeasonalRoster.ApplyLegacyBalanceCorrection(created.value, "Alt-Realm",
      expected, "Reviewed duplicate Alt balance", "balance-unit-unconfirmed", false, "Tester-Realm")
    assert_false(unconfirmed.ok)
    assert_equal("CONFIRMATION_REQUIRED", unconfirmed.code)
    assert_equal(3, dibs.Ledger.GetBalance("Tester-Realm", created.value))
    assert_equal(2, dibs.Ledger.GetBalance("Alt-Realm", created.value))

    local applied = dibs.SeasonalRoster.ApplyLegacyBalanceCorrection(created.value, "Alt-Realm",
      expected, "Reviewed duplicate Alt balance", "balance-unit-correction", true, "Tester-Realm")
    assert_true(applied.ok, tostring(applied.code))
    assert_equal(3, dibs.Ledger.GetBalance("Tester-Realm", created.value), "the selected Main balance is retained")
    assert_equal(0, dibs.Ledger.GetBalance("Alt-Realm", created.value))
    assert_equal("DIB_ADMIN_ADJUSTMENT", applied.transaction.type)
    assert_equal("tester-realm", applied.transaction.actorSnapshot.memberKey)
    assert_true(applied.transaction.reason:find("Reviewed duplicate Alt balance", 1, true) ~= nil)

    local transactionCount = #dibs.GetDB().ledgers["guild-primary"].transactions
    local replay, replayReason = dibs.SeasonalRoster.ApplyLegacyBalanceCorrection(created.value, "Alt-Realm",
      expected, "Reviewed duplicate Alt balance", "balance-unit-correction", true, "Tester-Realm")
    assert_false(replay.ok)
    assert_equal("STALE_PREVIEW", replay.code or replayReason)
    assert_equal(transactionCount, #dibs.GetDB().ledgers["guild-primary"].transactions,
      "a stale retry must not append a duplicate correction")
  end)
end)
