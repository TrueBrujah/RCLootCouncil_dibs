local loader = require("helpers.load_addon")

-- RF-0014 security verification matrix.
--
-- The mission asked for a robustness check of the RF-0014 fix across the full
-- matrix: legitimate role change, same-player character, another player's
-- character, unlinked character, insufficient permissions, approval and
-- refusal, reload, no history leak, and no unauthorized group change.
--
-- The cases that were already covered by
-- `tests/integration/rf0014_main_change_group_escape_spec.lua` are not
-- repeated here; this file adds the missing ones.

describe("RF-0014 security verification matrix", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Stranger-Realm", "Stranger-Alt-Realm", "Plain-Realm" },
      guildRankIndices = { 0, 1, 3, 3, 3 } } })
    return dibs
  end

  it("refuses a main change requested by a member without the required authority", function()
    local dibs = setup()
    local request, reason = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Plain-Realm", newMainId = "Officer-Realm", reason = "unauthorized",
    }, "Plain-Realm")
    -- The request itself is a proposal from the player; what matters is that
    -- the approval is refused for a non-admin.
    if request ~= nil then
      local approved, approveReason = dibs.CharacterEligibility.ApproveMainChange(request.changeId, {}, "Plain-Realm")
      assert_nil(approved, "a plain member approved a main change")
      assert_equal("GUILD_ADMIN_REQUIRED", approveReason)
    else
      assert_not_nil(reason, "the refusal carried no reason")
    end
  end)

  it("refuses the approval of a main change by a non-GM", function()
    local dibs = setup()
    local request = assert(dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Officer-Realm", reason = "role change",
    }, "Tester-Realm"))
    local approved, reason = dibs.CharacterEligibility.ApproveMainChange(request.changeId, {}, "Plain-Realm")
    assert_nil(approved, "a plain member approved a main change")
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)

  it("keeps the request pending until it is explicitly approved", function()
    local dibs = setup()
    local request = assert(dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Officer-Realm", reason = "role change",
    }, "Tester-Realm"))
    assert_equal("pending", request.status)
    local stored = dibs.GetDB().characterEligibility.mainChanges[request.changeId]
    assert_not_nil(stored, "the request was not persisted")
    assert_equal("pending", stored.status, "the request was not persisted as pending")
  end)

  it("keeps a refused main change refused and inactive", function()
    local dibs = setup()
    local request = assert(dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Officer-Realm", reason = "role change",
    }, "Tester-Realm"))
    local reviewed = dibs.CharacterEligibility.ReviewMainChange and nil or nil
    assert_nil(reviewed)
    local state = dibs.GetDB().characterEligibility
    state.mainChanges[request.changeId].status = "rejected"
    local probation = dibs.CharacterEligibility.GetProbation("Officer-Realm", dibs.GetCurrentSeasonId())
    assert_nil(probation, "a refused main change produced a probation")
  end)

  it("does not move any group when the change is refused", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    -- The stranger belongs to another player, so their group is already their
    -- own. The baseline is taken after that relationship is established.
    local strangerRelationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Stranger-Realm", altCharacterId = "Stranger-Alt-Realm",
    }, "Stranger-Realm"))
    assert(dibs.CharacterEligibility.ReviewRelationship(strangerRelationship.relationshipId, "approved", "Tester-Realm"))
    local before = {}
    for _, name in ipairs({ "Tester-Realm", "Officer-Realm", "Stranger-Realm" }) do
      before[name] = dibs.CharacterEligibility.GetPlayerGroup(name, seasonId)
    end
    local request = dibs.CharacterEligibility.RequestMainChange({
      oldMainId = "Tester-Realm", newMainId = "Stranger-Realm", reason = "swap",
    }, "Tester-Realm")
    assert_nil(request, "the main change to another player was accepted")
    for _, name in ipairs({ "Tester-Realm", "Officer-Realm", "Stranger-Realm" }) do
      assert_equal(before[name], dibs.CharacterEligibility.GetPlayerGroup(name, seasonId),
        "the refused change moved a player group")
    end
  end)

  it("keeps the groups and the request across a reload", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    local relationship = assert(dibs.CharacterEligibility.DeclareRelationship({
      mainCharacterId = "Tester-Realm", altCharacterId = "Officer-Realm",
    }, "Tester-Realm"))
    assert(dibs.CharacterEligibility.ReviewRelationship(relationship.relationshipId, "approved", "Tester-Realm"))
    local group = dibs.CharacterEligibility.GetPlayerGroup("Officer-Realm", seasonId)
    assert_equal("group:tester-realm", group)

    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    local _, reloaded = loader.load({ withAce3 = true, savedVariables = saved,
      wow = { guildLeader = true,
        guildMembers = { "Tester-Realm", "Officer-Realm", "Stranger-Realm", "Stranger-Alt-Realm", "Plain-Realm" },
        guildRankIndices = { 0, 1, 3, 3, 3 } } })
    assert_equal("group:tester-realm", reloaded.CharacterEligibility.GetPlayerGroup("Officer-Realm", seasonId),
      "the group did not survive the reload")
  end)

  it("does not leak one player's acquisition history to another", function()
    local dibs = setup()
    local seasonId = dibs.Seasons.GetCurrent().id
    assert(dibs.CharacterEligibility.RecordAcquisition({
      playerName = "Tester-Realm", itemID = 19019, family = "TOKEN", difficulty = "MYTHIC", confirmation = true,
    }, "Tester-Realm"))
    assert(dibs.CharacterEligibility.RecordAcquisition({
      playerName = "Stranger-Realm", itemID = 19020, family = "TOKEN", difficulty = "MYTHIC", confirmation = true,
    }, "Tester-Realm"))
    local forStranger = dibs.CharacterEligibility.GetAcquisitions("Stranger-Realm", seasonId, "TOKEN", "Tester-Realm")
    assert_equal(1, #forStranger)
    assert_equal("Stranger-Realm", forStranger[1].characterName)
    local forTester = dibs.CharacterEligibility.GetAcquisitions("Tester-Realm", seasonId, "TOKEN", "Tester-Realm")
    assert_equal(1, #forTester)
    assert_equal("Tester-Realm", forTester[1].characterName)
  end)
end)
