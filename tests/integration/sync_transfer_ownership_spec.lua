local loader = require("helpers.load_addon")
local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function receive(dibs, message, sender, mutate)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  if mutate then mutate(envelope) end
  return dibs.Sync.OnAddonMessage("DIBS", assert(dibs.Ace3.Serialize(envelope)), "GUILD", sender)
end

local function prepare()
  local gm = load("GameMaster-Realm")
  assert_true(gm.Governance.AdoptInitial(nil, { reason = "transfer ownership",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
  assert_true(gm.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }, "transfer ownership"))
  local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
  local season = assert(gm.Seasons.Create("Ownership Season"))
  local published, reason, catalog = gm.Seasons.PublishCatalog(nil, "SEASON_CREATE")
  assert_true(published, tostring(reason))
  local target = load("Player-Realm", saved)
  local raw = assert(target.Ace3.Serialize(catalog))
  local transferId = "ownership-transfer"
  assert_true(receive(target, { type = "TRANSFER_BEGIN", transferId = transferId,
    entityType = "SEASON_CATALOG", entityId = tostring(catalog.catalogRevision),
    revision = catalog.catalogRevision, contentHash = catalog.contentHash,
    payloadHash = target.Sync.CalculateContentHash(raw), chunkCount = 2 }, "GameMaster-Realm"))
  local middle = math.floor(#raw / 2)
  assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = transferId,
    chunkIndex = 1, chunk = raw:sub(1, middle) }, "GameMaster-Realm"))
  return target, transferId, raw:sub(middle + 1), season
end

describe("Production SyncV2 transfer ownership", function()
  it("rejects a foreign END without deleting the owner's partial transfer", function()
    local dibs, transferId, lastChunk, season = prepare()
    local accepted, reason = receive(dibs, { type = "TRANSFER_END", transferId = transferId,
      entityType = "SEASON_CATALOG" }, "Officer-Realm")
    assert_false(accepted)
    assert_equal("INVALID_TRANSFER_END", reason)
    assert_not_nil(dibs.runtime.v2Transfers[transferId])
    assert_true(receive(dibs, { type = "TRANSFER_CHUNK", transferId = transferId,
      chunkIndex = 2, chunk = lastChunk }, "GameMaster-Realm"))
    assert_true(receive(dibs, { type = "TRANSFER_END", transferId = transferId,
      entityType = "SEASON_CATALOG" }, "GameMaster-Realm"))
    assert_equal("Ownership Season", dibs.Seasons.GetById(season.id).name)
  end)

  it("retains a transfer after an early END or mismatched scope", function()
    local dibs, transferId, lastChunk = prepare()
    local accepted, reason = receive(dibs, { type = "TRANSFER_END", transferId = transferId,
      entityType = "SEASON_CATALOG" }, "GameMaster-Realm")
    assert_false(accepted)
    assert_equal("MISSING_TRANSFER_CHUNK", reason)
    assert_not_nil(dibs.runtime.v2Transfers[transferId])
    accepted, reason = receive(dibs, { type = "TRANSFER_END", transferId = transferId,
      entityType = "SEASON_CATALOG", entityId = "different" }, "GameMaster-Realm")
    assert_false(accepted)
    assert_equal("TRANSFER_METADATA_MISMATCH", reason)
    assert_not_nil(dibs.runtime.v2Transfers[transferId])
    accepted, reason = receive(dibs, { type = "TRANSFER_END", transferId = transferId,
      entityType = "SEASON_CATALOG", ledgerId = "different" }, "GameMaster-Realm")
    assert_false(accepted)
    assert_equal("LEDGER_SCOPE_MISMATCH", reason)
    assert_not_nil(dibs.runtime.v2Transfers[transferId])
    assert_true(receive(dibs, { type = "TRANSFER_CHUNK", transferId = transferId,
      chunkIndex = 2, chunk = lastChunk }, "GameMaster-Realm"))
    assert_true(receive(dibs, { type = "TRANSFER_END", transferId = transferId,
      entityType = "SEASON_CATALOG" }, "GameMaster-Realm"))
  end)
end)
