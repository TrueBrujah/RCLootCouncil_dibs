local loader = require("helpers.load_addon")

-- RF-0020 integration suite - the officer review surface.
--
-- The unit-level contract of the surface is covered by
-- `rf0020_officer_relationship_review_spec.lua`. This suite covers the
-- integration properties that a reviewer needs to trust the surface:
-- persistence across a reload, decision deduplication, the audit trail,
-- the protection of another player's history, and the synchronization of
-- a decision.
--
-- RF-0014 (a main change never merges two unrelated players) and RF-0017
-- (the player group is always derived) are preserved and are not
-- reintroduced here: a decision taken through the surface must go
-- through the same domain guards.

local function setup(options)
  options = options or {}
  options.withAce3 = true
  options.wow = options.wow or {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Alt-Realm", "Other-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 },
  }
  return select(2, loader.load(options))
end

local function declareAlt(dibs, mainName, altName)
  return assert(dibs.CharacterEligibility.DeclareRelationship({
    mainCharacterId = mainName, altCharacterId = altName,
    seasonId = dibs.Seasons.GetCurrent().id,
  }, mainName))
end

local function findRelationship(dibs, relationshipId)
  for _, entry in ipairs(dibs.CharacterEligibility.GetRelationshipStatus("Tester-Realm", dibs.Seasons.GetCurrent().id) or {}) do
    if entry.relationshipId == relationshipId then return entry end
  end
  return nil
end

describe("RF-0020 officer review surface integration", function()
  it("keeps an approved decision after a reload", function()
    local dibs = setup()
    local relationship = declareAlt(dibs, "Tester-Realm", "Alt-Realm")

    local result = dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "approved")
    assert_true(result.ok, tostring(result.diagnostic))

    -- Reload the same saved variables into a fresh addon instance.
    local savedVariables = dibs.GetDB()
    local _, reloaded = loader.load({ withAce3 = true, savedVariables = savedVariables, wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Alt-Realm", "Other-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 },
    } })

    local found
    for _, entry in ipairs(reloaded.CharacterEligibility.GetRelationshipStatus("Tester-Realm", reloaded.Seasons.GetCurrent().id) or {}) do
      if entry.relationshipId == relationship.relationshipId then found = entry end
    end
    assert_not_nil(found, "the approved relationship did not survive the reload")
    assert_equal("approved", found.status, "the reloaded relationship lost its approved status")
  end)

  it("deduplicates a repeated approval decision", function()
    local dibs = setup()
    local relationship = declareAlt(dibs, "Tester-Realm", "Alt-Realm")

    local first = dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "approved")
    local second = dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "approved")
    assert_true(first.ok, tostring(first.diagnostic))
    assert_true(second.ok, tostring(second.diagnostic))

    local found = findRelationship(dibs, relationship.relationshipId)
    assert_not_nil(found, "the relationship disappeared after a repeated approval")
    assert_equal("approved", found.status)

    -- A repeated decision must not append a second relationship record.
    local count = 0
    for _, entry in ipairs(dibs.CharacterEligibility.GetRelationshipStatus("Tester-Realm", dibs.Seasons.GetCurrent().id) or {}) do
      count = count + 1
    end
    assert_equal(1, count, "a repeated approval duplicated the relationship record")
  end)

  it("records an audit entry for the decision", function()
    local dibs = setup()
    local relationship = declareAlt(dibs, "Tester-Realm", "Alt-Realm")

    dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "approved")

    local audit = dibs.GetDB().auditLog or {}
    local found = false
    for _, entry in ipairs(audit) do
      if entry.relationshipId == relationship.relationshipId
        and entry.action == "eligibility.relationship.approved" then found = true end
    end
    assert_true(found, "no audit entry was recorded for the approval")
  end)

  it("keeps a rejection auditable with its reason", function()
    local dibs = setup()
    local relationship = declareAlt(dibs, "Tester-Realm", "Alt-Realm")

    local result = dibs.OfficerUI.ReviewEligibilityRelationship(
      relationship.relationshipId, "rejected", "Not this player's character")
    assert_true(result.ok, tostring(result.diagnostic))

    local audit = dibs.GetDB().auditLog or {}
    local found = false
    for _, entry in ipairs(audit) do
      if entry.relationshipId == relationship.relationshipId
        and entry.action == "eligibility.relationship.rejected"
        and entry.reason == "Not this player's character" then found = true end
    end
    assert_true(found, "the rejection was not audited with its reason")
  end)

  it("keeps an approved relationship inside its own group", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- Another player declares their own relationship.
    local other = declareAlt(dibs, "Other-Realm", "Other-Alt-Realm")
    assert_not_nil(other, "the other player's declaration failed")

    -- The alt starts unlinked.
    assert_equal("character:other-alt-realm",
      dibs.CharacterEligibility.GetPlayerGroup("Other-Alt-Realm", seasonId))

    -- Approving the other player's declaration links their alt to their own
    -- main, and to nobody else.
    local result = dibs.OfficerUI.ReviewEligibilityRelationship(other.relationshipId, "approved")
    assert_true(result.ok, tostring(result.diagnostic))

    assert_equal("group:other-realm",
      dibs.CharacterEligibility.GetPlayerGroup("Other-Alt-Realm", seasonId),
      "the approved alt was not linked to its own main")
    assert_equal("character:alt-realm",
      dibs.CharacterEligibility.GetPlayerGroup("Alt-Realm", seasonId),
      "an unrelated approval changed this player's group")
  end)

  it("never lets a non-officer approve through the surface", function()
    local plain = setup({ wow = {
      playerName = "Plain-Realm", guildLeader = false,
      guildMembers = { "Plain-Realm", "Tester-Realm", "Alt-Realm" },
      guildRankIndices = { [1] = 3, [2] = 3, [3] = 3 },
    } })
    local relationship = assert(plain.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Plain-Realm", altCharacterId = "Alt-Realm",
      seasonId = plain.Seasons.GetCurrent().id,
    }, "Plain-Realm"))

    local result = plain.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "approved")
    assert_false(result.ok, "a non-officer approved a relationship through the surface")

    local found
    for _, entry in ipairs(plain.CharacterEligibility.GetRelationshipStatus("Plain-Realm", plain.Seasons.GetCurrent().id) or {}) do
      if entry.relationshipId == relationship.relationshipId then found = entry end
    end
    assert_not_nil(found, "the relationship disappeared after a denied approval")
    assert_equal("pending", found.status, "a non-officer changed the relationship status")
  end)

  it("approves a main change through the surface and applies the probation", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id

    -- The player declares their alt, so the change stays inside one group.
    local relationship = declareAlt(dibs, "Tester-Realm", "Alt-Realm")
    assert(dibs.OfficerUI.ReviewEligibilityRelationship(relationship.relationshipId, "approved").ok)

    local change, reason = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Alt-Realm", reason = "role change", seasonId = seasonId,
    }, "Tester-Realm")
    assert_not_nil(change, "the main change request was refused: " .. tostring(reason))

    local result = dibs.OfficerUI.ReviewEligibilityMainChange(change.changeId, { reason = "Approved by the GM" })
    assert_true(result.ok, tostring(result.diagnostic))

    local probation = dibs.CharacterEligibility.GetProbation("Alt-Realm", seasonId)
    assert_not_nil(probation, "the approved main change did not apply a probation")
    assert_equal("approved", probation.status)
  end)

  it("refuses a main change that would merge two unrelated players", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id

    -- The stranger is linked to their own main.
    local stranger = declareAlt(dibs, "Other-Realm", "Other-Alt-Realm")
    assert(dibs.CharacterEligibility.ReviewRelationship(stranger.relationshipId, "approved", "Tester-Realm"))

    local change, reason = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Other-Realm", reason = "swap", seasonId = seasonId,
    }, "Tester-Realm")
    assert_nil(change, "a main change to another player's character was accepted")
    assert_equal("MAIN_CHANGE_GROUP_MISMATCH", reason)

    -- The two players keep their own groups: the refusal changed nothing.
    assert_equal("group:other-realm",
      dibs.CharacterEligibility.GetPlayerGroup("Other-Realm", seasonId),
      "the two players were merged")
    assert_equal("character:tester-realm",
      dibs.CharacterEligibility.GetPlayerGroup("Tester-Realm", seasonId),
      "the requester was moved into another player's group")
  end)
end)
