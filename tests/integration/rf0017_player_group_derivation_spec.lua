local loader = require("helpers.load_addon")

-- RF-0017 regression suite.
--
-- RF-0017 - "CharacterEligibility : un identifiant de groupe de joueur fourni
-- par l'appelant permet de fusionner ou de divulguer des donnees entre
-- joueurs" (docs/code-audit/INDEX.md#rf-0017).
--
-- `Eligibility.DeclareRelationship` and `Eligibility.RecordAcquisition`
-- accepted a caller supplied `playerGroupId`. The player group is the
-- authority that binds a character to its acquisitions, so choosing it let a
-- declarer or an officer place two unrelated players in one group, read the
-- other player's acquisition history, and have their item count toward the
-- other player's eligibility.
--
-- The group is now always derived from the character.

describe("RF-0017 the player group is derived, never chosen by the caller", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Stranger-Realm" },
      guildRankIndices = { 0, 1, 3 } } })
    return dibs
  end

  it("ignores a caller supplied group when declaring a relationship", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Stranger-Realm",
      playerGroupId = "group:attacker-chosen",
    }, "Tester-Realm"))
    assert_equal("group:tester-realm", relationship.playerGroupId,
      "the caller chose the player group of a declared relationship")
    assert(dibs.CharacterEligibility.ReviewRelationship(relationship.relationshipId, "approved", "Tester-Realm"))
    assert_equal("group:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Stranger-Realm", seasonId),
      "the stranger joined a caller supplied group")
  end)

  it("ignores a caller supplied group when recording an acquisition", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local acquisition = assert(dibs.CharacterEligibility.RecordAcquisition({
      playerName = "Tester-Realm", itemID = 19019, family = "TOKEN", difficulty = "MYTHIC",
      playerGroupId = "character:stranger-realm", confirmation = true,
    }, "Tester-Realm"))
    assert_equal("character:tester-realm", acquisition.playerGroupId,
      "the caller chose the player group of an acquisition")
  end)

  it("does not expose one player's acquisition to another player", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- The officer records an acquisition for the attacker, stamped with the
    -- stranger's group.
    assert(dibs.CharacterEligibility.RecordAcquisition({
      playerName = "Tester-Realm", itemID = 19019, family = "TOKEN", difficulty = "MYTHIC",
      playerGroupId = "character:stranger-realm", confirmation = true,
    }, "Tester-Realm"))

    local forStranger = dibs.CharacterEligibility.GetAcquisitions("Stranger-Realm", seasonId, "TOKEN", "Tester-Realm")
    assert_equal(0, #forStranger, "a player could read another player's acquisition")
    local forTester = dibs.CharacterEligibility.GetAcquisitions("Tester-Realm", seasonId, "TOKEN", "Tester-Realm")
    assert_equal(1, #forTester, "the player's own acquisition history is not complete")
  end)

  it("keeps an unlinked character in its own group after a legitimate declaration", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- The legitimate flow: a player declares a relationship between their own
    -- characters. The group is still derived from the main character.
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Stranger-Realm",
    }, "Tester-Realm"))
    assert_equal("group:tester-realm", relationship.playerGroupId)
    assert(dibs.CharacterEligibility.ReviewRelationship(relationship.relationshipId, "approved", "Tester-Realm"))
    assert_equal("group:tester-realm", dibs.CharacterEligibility.GetPlayerGroup("Stranger-Realm", seasonId),
      "the declared relationship did not link the two characters")
  end)
end)
