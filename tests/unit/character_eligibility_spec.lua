local loader = require("helpers.load_addon")

describe("Character loot eligibility", function()
  it("blocks Catalyst and keeps Curio progress separate from Tier Set progress", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local catalyst = dibs.CharacterEligibility.Evaluate({ family = "CATALYST", itemID = 280001 }, "Tester-Realm", seasonId)
    assert_equal("block", catalyst.outcome)
    assert_equal("CATALYST_PERSONAL", catalyst.reasonCode)

    local policy = dibs.ProtectedActions.Execute("eligibility.policy.set", nil, {
      seasonId = seasonId, family = "TOKEN", completionThreshold = 1,
    })
    assert_true(policy.ok)
    local record = dibs.ProtectedActions.Execute("eligibility.history.add", nil, {
      seasonId = seasonId, family = "TOKEN", itemID = 280001, itemName = "Curio",
      playerName = "Tester-Realm", confirmation = true, difficulty = "Normal", slot = "head",
      evidenceId = "reconciliation:curio-1", reason = "confirmed test history",
    })
    assert_true(record.ok)
    local curio = dibs.CharacterEligibility.Evaluate({ family = "TOKEN", itemID = 280002, slot = "chest", difficulty = "Heroic" }, "Tester-Realm", seasonId)
    assert_equal("block", curio.outcome)
    local tierPolicy = dibs.ProtectedActions.Execute("eligibility.policy.set", nil, {
      seasonId = seasonId, family = "TOKEN_SET", groups = { MAGE = { participants = { "Tester-Realm" } } },
    })
    assert_true(tierPolicy.ok)
    local tier = dibs.CharacterEligibility.Evaluate({ family = "TOKEN_SET", itemID = 280003, tokenGroup = "MAGE" }, "Tester-Realm", seasonId)
    assert_equal("allow", tier.outcome)
  end)

  it("makes finalized acquisitions idempotent and shares progress after an approved link", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local declaration = dibs.CharacterEligibility.DeclareRelationship({
      seasonId = seasonId, mainCharacter = "Tester-Realm", altCharacter = "Alt-Realm",
    })
    assert_equal("pending", declaration.status)
    local approved = dibs.ProtectedActions.Execute("eligibility.relationship.review", nil, {
      relationshipId = declaration.relationshipId, status = "approved",
    })
    assert_true(approved.ok)
    assert_equal(declaration.playerGroupId, dibs.CharacterEligibility.GetPlayerGroup("Alt-Realm", seasonId))

    local first = dibs.CharacterEligibility.RecordAcquisition({
      seasonId = seasonId, family = "TOKEN", itemID = 280010, playerName = "Alt-Realm",
      difficulty = "Normal", slot = "head", awardRef = "entry:280010", source = "test",
    }, nil, true)
    local replay = dibs.CharacterEligibility.RecordAcquisition({
      seasonId = seasonId, family = "TOKEN", itemID = 280010, playerName = "Alt-Realm",
      difficulty = "Normal", slot = "head", awardRef = "entry:280010", source = "test",
    }, nil, true)
    assert_not_nil(first)
    assert_equal(first.acquisitionId, replay.acquisitionId)
    assert_true(replay.idempotentReplay)
  end)

  it("enforces the lowest Tier Set progress round", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local setPolicy = dibs.ProtectedActions.Execute("eligibility.policy.set", nil, {
      seasonId = seasonId, family = "TOKEN_SET", groups = {
        MAGE = { participants = { "Tester-Realm", "Alt-Realm" } },
      }, enforcementOutcome = "downgrade",
    })
    assert_true(setPolicy.ok)
    local acquired = dibs.CharacterEligibility.RecordAcquisition({
      seasonId = seasonId, family = "TOKEN_SET", itemID = 280020, playerName = "Tester-Realm",
      difficulty = "Mythic", tokenGroup = "MAGE", awardRef = "entry:280020",
    }, nil, true)
    assert_not_nil(acquired)
    local decision = dibs.CharacterEligibility.Evaluate({
      seasonId = seasonId, family = "TOKEN_SET", itemID = 280021, difficulty = "Mythic", tokenGroup = "MAGE",
    }, "Tester-Realm", seasonId)
    assert_equal("downgrade", decision.outcome)
    assert_equal("TIER_SET_ROUND_PRIORITY", decision.reasonCode)
  end)

  it("blocks main-spec protected loot during the default probation", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local request = dibs.CharacterEligibility.RequestMainChange({
      seasonId = seasonId, oldMain = "Tester-Realm", newMain = "Newmain-Realm", reason = "role change",
    })
    assert_equal("pending", request.status)
    local approved = dibs.ProtectedActions.Execute("eligibility.main.review", nil, {
      changeId = request.changeId, reason = "approved role change",
    })
    assert_true(approved.ok)
    local decision = dibs.CharacterEligibility.Evaluate({
      seasonId = seasonId, family = "TOKEN", itemID = 280030, isMainSpec = true,
    }, "Newmain-Realm", seasonId)
    assert_equal("block", decision.outcome)
    assert_equal("MAIN_CHANGE_PROBATION", decision.reasonCode)
  end)

  it("allows one bounded probation exception and consumes it once", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local request = dibs.CharacterEligibility.RequestMainChange({
      seasonId = seasonId, oldMain = "Tester-Realm", newMain = "Newmain-Realm", reason = "role change",
    })
    local approved = dibs.ProtectedActions.Execute("eligibility.main.review", nil, {
      changeId = request.changeId, reason = "approved role change",
    })
    assert_true(approved.ok)
    local exception = dibs.ProtectedActions.Execute("eligibility.exception.create", nil, {
      changeId = request.changeId, awardLimit = 1, reason = "first raid exception",
    })
    assert_true(exception.ok)
    local decision = dibs.CharacterEligibility.Evaluate({
      seasonId = seasonId, family = "TOKEN", itemID = 280031, isMainSpec = true,
    }, "Newmain-Realm", seasonId)
    assert_equal("allow", decision.outcome)
    assert_not_nil(decision.probationException)
    assert_true(dibs.CharacterEligibility.ConsumeException(decision))
    local after = dibs.CharacterEligibility.Evaluate({
      seasonId = seasonId, family = "TOKEN", itemID = 280032, isMainSpec = true,
    }, "Newmain-Realm", seasonId)
    assert_equal("block", after.outcome)
    assert_equal("MAIN_CHANGE_PROBATION", after.reasonCode)
  end)

  it("projects protected-loot decisions into the RCLootCouncil candidate status", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local instant = _G.C_Item.GetItemInfoInstant
    _G.C_Item.GetItemInfoInstant = function(itemID)
      if tonumber(itemID) == 280040 then return nil, "Context Token", "Context Token", "", nil, 5, 2 end
      return instant(itemID)
    end
    local policy = dibs.ProtectedActions.Execute("eligibility.policy.set", nil, {
      seasonId = seasonId, family = "TOKEN", completionThreshold = 1,
    })
    assert_true(policy.ok)
    local history = dibs.CharacterEligibility.RecordAcquisition({
      seasonId = seasonId, family = "TOKEN", itemID = 280040, playerName = "Tester-Realm",
      difficulty = "Normal", slot = "head", awardRef = "entry:280040",
    }, nil, true)
    assert_not_nil(history)
    local status = dibs.RCLootCouncil.GetStatusForCandidate("Tester-Realm", 280040, "DIB")
    assert_equal("eligibility-block", status.status)
    assert_false(status.canUseDib)
    assert_equal("CURIO_COMPLETE", status.eligibility.reasonCode)
  end)
end)
