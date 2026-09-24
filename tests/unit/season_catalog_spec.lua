local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function adoptPolicy(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, {
    reason = "season catalog unit test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }, "season catalog unit test"))
end

describe("Season catalog invariants", function()
  it("publishes a revision linked to the previous catalog hash", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_not_nil(gm.Seasons.Create("Season One"))

    local published, reason, record = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(reason))
    assert_equal(1, record.catalogRevision)
    assert_equal(0, record.parentRevision)
    assert_equal("GENESIS", record.parentHash)
    assert_equal(gm.Seasons.CalculateCatalogHash(record), record.contentHash)
    assert_equal(record.contentHash, gm.Seasons.GetCatalogState().hash)
  end)

  it("merges incoming records without deleting local seasons", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    local shared = assert(gm.Seasons.Create("Shared Season"))
    local published, reason, record = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(reason))

    local target = load("Officer-Realm", gm.DeepCopy(_G.RCLootCouncil_dibsDB))
    local localOnly = assert(target.Seasons.Create("Local Season"))
    local applied, applyReason = target.Seasons.ApplyCatalog(record, "GameMaster-Realm")
    assert_true(applied, tostring(applyReason))
    assert_equal("Shared Season", target.Seasons.GetById(shared.id).name)
    assert_equal("Local Season", target.Seasons.GetById(localOnly.id).name)
  end)

  it("rejects tampered records and unauthorized senders", function()
    local gm = load("GameMaster-Realm")
    adoptPolicy(gm)
    assert_not_nil(gm.Seasons.Create("Protected Season"))
    local published, reason, record = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
    assert_true(published, tostring(reason))

    local target = load("Player-Realm", gm.DeepCopy(_G.RCLootCouncil_dibsDB))
    local tampered = target.DeepCopy(record)
    tampered.seasons[next(tampered.seasons)].name = "Tampered"
    local applied, applyReason = target.Seasons.ApplyCatalog(tampered, "GameMaster-Realm")
    assert_false(applied)
    assert_equal("SEASON_CATALOG_HASH_MISMATCH", applyReason)

    applied, applyReason = target.Seasons.ApplyCatalog(record, "Player-Realm")
    assert_false(applied)
    assert_equal("POLICY_WRITER_REQUIRED", applyReason)
  end)
end)
