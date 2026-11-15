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

  it("binds Main/Alt declarations and Main-change requests to the declaring player", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, playerName = "Tester-Realm" } })
    local seasonId = dibs.GetCurrentSeasonId()
    local forgedLink, linkReason = dibs.CharacterEligibility.DeclareRelationship({
      seasonId = seasonId, mainCharacter = "OtherPlayer-Realm", altCharacter = "Alt-Realm",
    }, "Tester-Realm")
    assert_nil(forgedLink)
    assert_equal("OWNER_MISMATCH", linkReason)

    local forgedChange, changeReason = dibs.CharacterEligibility.RequestMainChange({
      seasonId = seasonId, oldMainId = "OtherPlayer-Realm", newMainId = "Newmain-Realm",
    }, "Tester-Realm")
    assert_nil(forgedChange)
    assert_equal("OWNER_MISMATCH", changeReason)

    local valid = dibs.CharacterEligibility.DeclareRelationship({
      seasonId = seasonId, mainCharacter = "Tester-Realm", altCharacter = "Alt-Realm",
    }, "Tester-Realm")
    assert_equal("pending", valid.status)
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
    local link = dibs.CharacterEligibility.DeclareRelationship({ seasonId = seasonId,
      mainCharacter = "Tester-Realm", altCharacter = "Newmain-Realm" })
    assert_equal("approved", dibs.CharacterEligibility.ApproveRelationship(link.relationshipId, "Tester-Realm").status)
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
    local link = dibs.CharacterEligibility.DeclareRelationship({ seasonId = seasonId,
      mainCharacter = "Tester-Realm", altCharacter = "Newmain-Realm" })
    assert_equal("approved", dibs.CharacterEligibility.ApproveRelationship(link.relationshipId, "Tester-Realm").status)
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

  it("allows another Main change after probation expires and advances the identity revision", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local link = dibs.CharacterEligibility.DeclareRelationship({ seasonId = seasonId,
      mainCharacter = "Tester-Realm", altCharacter = "Newmain-Realm" })
    dibs.CharacterEligibility.ApproveRelationship(link.relationshipId, "Tester-Realm")
    local beforeRevision = dibs.CharacterEligibility.GetRevision(seasonId)
    local first = assert(dibs.CharacterEligibility.RequestMainChange({ seasonId = seasonId,
      oldMain = "Tester-Realm", newMain = "Newmain-Realm", reason = "first change" }, "Tester-Realm"))
    assert(dibs.CharacterEligibility.ApproveMainChange(first.changeId, { reason = "approved" }, "Tester-Realm"))
    assert_equal("newmain-realm", dibs.CharacterEligibility.GetPersonProjection("Tester-Realm", seasonId).mainCharacterKey)
    local originalTime, offset = _G.time, 0
    _G.time = function() return originalTime() + offset end
    offset = 15 * 24 * 60 * 60
    local second, reason = dibs.CharacterEligibility.RequestMainChange({ seasonId = seasonId,
      oldMain = "Newmain-Realm", newMain = "Tester-Realm", reason = "second change" }, "Newmain-Realm")
    assert_not_nil(second, tostring(reason))
    assert_equal("pending", second.status)
    local approved = dibs.CharacterEligibility.ApproveMainChange(second.changeId, { reason = "approved again" }, "Tester-Realm")
    assert_not_nil(approved)
    assert_equal("tester-realm", dibs.CharacterEligibility.GetPersonProjection("Newmain-Realm", seasonId).mainCharacterKey)
    assert_true(dibs.CharacterEligibility.GetRevision(seasonId) > beforeRevision)
  end)

  it("enforces the full 14-day probation and permits another request at expiry", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local link = dibs.CharacterEligibility.DeclareRelationship({ seasonId = seasonId,
      mainCharacter = "Tester-Realm", altCharacter = "Newmain-Realm" }, "Tester-Realm")
    assert_not_nil(dibs.CharacterEligibility.ApproveRelationship(link.relationshipId, "Tester-Realm"))
    local first = assert(dibs.CharacterEligibility.RequestMainChange({ seasonId = seasonId,
      oldMain = "Tester-Realm", newMain = "Newmain-Realm" }, "Tester-Realm"))
    local approved = assert(dibs.CharacterEligibility.ApproveMainChange(first.changeId,
      { reason = "reviewed" }, "Tester-Realm"))
    assert_equal(14 * 24 * 60 * 60, approved.probationEndsAt - approved.effectiveAt)

    local originalTime = _G.time
    _G.time = function() return approved.probationEndsAt - 1 end
    assert_not_nil(dibs.CharacterEligibility.GetProbation("Newmain-Realm", seasonId))
    local tooEarly, earlyReason = dibs.CharacterEligibility.RequestMainChange({ seasonId = seasonId,
      oldMain = "Newmain-Realm", newMain = "Tester-Realm" }, "Newmain-Realm")
    assert_nil(tooEarly)
    assert_equal("MAIN_CHANGE_ALREADY_ACTIVE", earlyReason)

    _G.time = function() return approved.probationEndsAt end
    assert_nil(dibs.CharacterEligibility.GetProbation("Newmain-Realm", seasonId))
    local nextRequest, nextReason = dibs.CharacterEligibility.RequestMainChange({ seasonId = seasonId,
      oldMain = "Newmain-Realm", newMain = "Tester-Realm" }, "Newmain-Realm")
    _G.time = originalTime
    assert_not_nil(nextRequest, tostring(nextReason))
    assert_equal("pending", nextRequest.status)
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
