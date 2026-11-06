local loader = require("helpers.load_addon")

-- RF-0014 regression suite.
--
-- RF-0014 - "CharacterEligibility : un changement de main peut fusionner deux
-- joueurs sans lien" (docs/code-audit/INDEX.md#rf-0014).
--
-- `Eligibility.RequestMainChange` derives the player group from the OLD main
-- character, but it never checked that the NEW main character belongs to that
-- same group. Once the change was approved, `Eligibility.GetPlayerGroup`
-- returned the requester's group for the unrelated character, so the two
-- players shared one group, one player's acquisitions became visible to the
-- other, and both characters' eligibility was merged.
--
-- The test drives the real module and proves the group escape is refused.

describe("RF-0014 a main change cannot merge two unrelated players", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Stranger-Realm", "Stranger-Alt-Realm" },
      guildRankIndices = { 0, 1, 3, 3 } } })
    return dibs
  end

  it("refuses a main change to a character that already belongs to another player", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- The stranger is linked to their own main, so their character already
    -- belongs to another player's group.
    local strangerRelationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Stranger-Realm", altCharacterId = "Stranger-Alt-Realm",
    }, "Stranger-Realm"))
    assert(dibs.CharacterEligibility.ReviewRelationship(strangerRelationship.relationshipId, "approved", "Tester-Realm"))
    assert_equal("group:stranger-realm", dibs.CharacterEligibility.GetPlayerGroup("Stranger-Realm", seasonId))
    assert_equal("character:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Tester-Realm", seasonId))

    local request, reason = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Stranger-Realm", reason = "swap",
    }, "Tester-Realm")
    assert_nil(request, "a main change to another player's character was accepted")
    assert_equal("MAIN_CHANGE_GROUP_MISMATCH", reason)
  end)

  it("keeps the two players in separate groups after the refusal", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local strangerRelationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Stranger-Realm", altCharacterId = "Stranger-Alt-Realm",
    }, "Stranger-Realm"))
    assert(dibs.CharacterEligibility.ReviewRelationship(strangerRelationship.relationshipId, "approved", "Tester-Realm"))
    local request = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Stranger-Realm", reason = "swap",
    }, "Tester-Realm")
    assert_nil(request, "a main change to another player's character was accepted")
    assert_equal("character:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Tester-Realm", seasonId))
    assert_equal("group:stranger-realm", dibs.CharacterEligibility.GetPlayerGroup("Stranger-Realm", seasonId))
  end)

  it("accepts a main change between characters that already share a group", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- The two characters are linked by an approved relationship, so they
    -- already share one player group and the change is legitimate.
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Stranger-Realm",
    }, "Tester-Realm"))
    local reviewed = assert(dibs.CharacterEligibility.ReviewRelationship(relationship.relationshipId, "approved", "Tester-Realm"))
    assert_equal("approved", reviewed.status)
    assert_equal("group:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Tester-Realm", seasonId))
    assert_equal("group:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Stranger-Realm", seasonId))

    local request, reason = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Stranger-Realm", reason = "legitimate swap",
    }, "Tester-Realm")
    assert_not_nil(request, "a legitimate main change was refused: " .. tostring(reason))
    local approved = assert(dibs.CharacterEligibility.ApproveMainChange(request.changeId, {}, "Tester-Realm"))
    assert_equal("approved", approved.status)
  end)

  it("refuses to approve a stored change whose characters no longer share a group", function()
    local dibs = setup()
    -- The new main character is linked to a third player, so it belongs to
    -- that player's group.
    local strangerRelationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Stranger-Realm", altCharacterId = "Stranger-Alt-Realm",
    }, "Stranger-Realm"))
    assert(dibs.CharacterEligibility.ReviewRelationship(strangerRelationship.relationshipId, "approved", "Tester-Realm"))

    -- A change stored before the check existed, or one whose characters were
    -- separated since it was requested, must not be approvable either.
    local state = dibs.GetDB().characterEligibility
    state.mainChanges["rf0014-stored-change"] = {
      changeId = "rf0014-stored-change", seasonId = dibs.GetCurrentSeasonId(),
      playerGroupId = "character:tester-realm", oldMainId = "tester-realm", newMainId = "stranger-realm",
      status = "pending", requestedBy = "tester-realm", requestedAt = 1700000000, reason = "stored before the check",
    }
    table.insert(state.mainChangeOrder, "rf0014-stored-change")

    local approved, reason = dibs.CharacterEligibility.ApproveMainChange("rf0014-stored-change", {}, "Tester-Realm")
    assert_nil(approved, "a main change was approved although the groups do not match")
    assert_equal("MAIN_CHANGE_GROUP_MISMATCH", reason)
  end)

  it("does not expose one player's acquisitions to another player", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local acquisition = assert(dibs.CharacterEligibility.RecordAcquisition({
      playerName = "Tester-Realm", itemID = 19019, family = "TOKEN", difficulty = "MYTHIC", confirmation = true,
    }, "Tester-Realm"))
    assert_equal("character:tester-realm", acquisition.playerGroupId)

    -- The stranger records their own acquisition.
    assert(dibs.CharacterEligibility.RecordAcquisition({
      playerName = "Stranger-Realm", itemID = 19020, family = "TOKEN", difficulty = "MYTHIC", confirmation = true,
    }, "Tester-Realm"))

    -- Each player group holds only its own acquisition. The stranger must not
    -- see the requester's row, and the requester must not see the stranger's.
    local forStranger = dibs.CharacterEligibility.GetAcquisitions("Stranger-Realm", seasonId, "TOKEN", "Tester-Realm")
    assert_equal(1, #forStranger, "the stranger's own acquisition history is not complete")
    assert_equal("Stranger-Realm", forStranger[1].characterName,
      "a player can read another player's acquisition")
    local forTester = dibs.CharacterEligibility.GetAcquisitions("Tester-Realm", seasonId, "TOKEN", "Tester-Realm")
    assert_equal(1, #forTester, "the player's own acquisition history is not complete")
    assert_equal("Tester-Realm", forTester[1].characterName,
      "a player can read another player's acquisition")
  end)
end)
