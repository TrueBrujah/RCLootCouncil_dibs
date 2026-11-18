local clients = require("helpers.canonical_operation_clients")

local function setup()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  local saved = world:Snapshot(coordinator)
  local player = world:Load("Player-Realm", saved)
  local officer = world:Load("Officer-Realm", saved)
  world:TakePackets()
  return world, coordinator, player, officer
end

local function proposal(client, id)
  return assert(client.dibs.Governance.RecordAwardProposal(client.name, {
    playerName = "Player-Realm", itemID = 275658, amount = 1,
    type = "DIB_USED", awardRef = id, sessionIdentity = id, response = "PASS",
  }))
end

local function send(sender, target, records, releases, patch)
  local message = { type = "AWARD_RESERVATION_DIGEST", records = records,
    contentHash = sender.dibs.Sync.CalculateContentHash(records) }
  if releases then
    message.releases, message.releaseHash = releases, sender.dibs.Sync.CalculateContentHash(releases)
  end
  for key, value in pairs(patch or {}) do message[key] = value end
  local envelope = assert(sender.dibs.Sync.BuildEnvelope(message))
  return target.dibs.Sync.OnAddonMessage("DIBS", sender.dibs.Ace3.Serialize(envelope), "GUILD", sender.name)
end

local function hold(client)
  return client.dibs.Ledger.GetPendingDibReservations("Player-Realm", client.dibs.GetCurrentSeasonId())
end

local function stateHash(client)
  local db = client.dibs.GetDB()
  local sync = assert(db.sync.v2)
  return client.dibs.Sync.CalculateContentHash({ ledgers = db.ledgers,
    reservations = assert(sync.awardReservations), releases = assert(sync.awardReservationTombstones) })
end

local function pendingAndRelease(coordinator, id)
  local created = proposal(coordinator, id)
  local records = coordinator.dibs.Sync.BuildAwardReservationDigest().records
  assert_true(coordinator.dibs.Governance.ResolveAwardProposal(created.proposalId, "REJECTED", "TEST_REJECTION"))
  return records, coordinator.dibs.Sync.BuildAwardReservationDigest().releases
end

describe("Award reservation release integrity", function()
  it("rejects an unrelated officer's release without changing holds or accounting", function()
    local _, coordinator, player, officer = setup()
    local records, releases = pendingAndRelease(coordinator, "release-authority")
    assert_true(send(coordinator, player, records))
    local before = stateHash(player)
    local ok, reason = send(officer, player, {}, releases)
    assert_false(ok)
    assert_equal("RESERVATION_RELEASE_AUTHORITY_REQUIRED", reason)
    assert_equal(before, stateHash(player))
    assert_equal(1, hold(player))
  end)

  for field, changed in pairs({ ledgerId = "other-ledger", seasonId = "other-season", amount = 2,
    playerMemberKey = "officer-realm", actorMemberKey = "officer-realm",
    awardRef = "other-award", evidenceId = "other-evidence" }) do
    it("rejects a release changing " .. field .. " without changing the original reservation", function()
      local _, coordinator, player = setup()
      local records, releases = pendingAndRelease(coordinator, "release-scope")
      assert_true(send(coordinator, player, records))
      local before = stateHash(player)
      releases[1][field] = changed
      local ok, reason = send(coordinator, player, {}, releases)
      assert_false(ok)
      assert_equal("RESERVATION_RELEASE_SCOPE_MISMATCH", reason)
      assert_equal(before, stateHash(player))
    end)
  end

  it("accepts the original officer actor's release without a balance effect", function()
    local _, _, player, officer = setup()
    local records, releases = pendingAndRelease(officer, "release-by-actor")
    local accounting = player.dibs.Sync.CalculateContentHash(player.dibs.GetDB().ledgers)
    assert_true(send(officer, player, records))
    assert_equal(1, hold(player))
    assert_true(send(officer, player, {}, releases))
    assert_equal(0, hold(player))
    assert_equal(accounting, player.dibs.Sync.CalculateContentHash(player.dibs.GetDB().ledgers))
  end)

  it("does not rebroadcast a received release even when an incoming flag claims local origin", function()
    local _, coordinator, _, officer = setup()
    local records, releases = pendingAndRelease(coordinator, "release-no-relay")
    assert_true(send(coordinator, officer, records))
    releases[1].localRelease = true
    assert_true(send(coordinator, officer, {}, releases))
    assert_equal(0, hold(officer))
    assert_nil(officer.dibs.GetDB().sync.v2.awardReservationTombstones[releases[1].proposalId].localRelease)
    assert_equal(0, #officer.dibs.Sync.BuildAwardReservationDigest().releases)
  end)

  it("rejects a mixed page atomically when its release hash is corrupt", function()
    local _, coordinator, player = setup()
    local records, releases = pendingAndRelease(coordinator, "release-corruption")
    assert_true(send(coordinator, player, records))
    proposal(coordinator, "pending-on-invalid-page")
    local pending = coordinator.dibs.Sync.BuildAwardReservationDigest().records
    local before = stateHash(player)
    assert_false(send(coordinator, player, pending, releases, { releaseHash = "corrupt" }))
    assert_equal(before, stateHash(player))
    assert_equal(1, hold(player))
  end)

  for _, shape in ipairs({ "boolean", "dictionary", "sparse" }) do
    it("rejects a " .. shape .. " release array without changing state", function()
      local _, coordinator, player = setup()
      local records, releases = pendingAndRelease(coordinator, "release-array-shape")
      assert_true(send(coordinator, player, records))
      local malformed
      if shape == "boolean" then malformed = false
      elseif shape == "dictionary" then malformed = { other = releases[1] }
      elseif shape == "sparse" then malformed = { [1] = releases[1], [3] = releases[1] } end
      local before = stateHash(player)
      local ok, reason = send(coordinator, player, {}, nil, { releases = malformed,
        releaseHash = coordinator.dibs.Sync.CalculateContentHash(shape == "boolean" and {} or malformed) })
      assert_false(ok)
      assert_equal("INVALID_AWARD_RESERVATION_DIGEST", reason)
      assert_equal(before, stateHash(player))
    end)
  end

  it("retains release-before-pending tombstones across reload despite a later pending timestamp", function()
    local world, coordinator, player = setup()
    local records, releases = pendingAndRelease(coordinator, "release-reordering")
    local accounting = player.dibs.Sync.CalculateContentHash(player.dibs.GetDB().ledgers)
    assert_true(send(coordinator, player, {}, releases))
    local saved = world:Snapshot(player)
    world.clients[player.name] = nil
    player = world:Load("Player-Realm", saved)
    records[1].updatedAt = releases[1].updatedAt + 500
    assert_true(send(coordinator, player, records))
    assert_equal(0, hold(player))
    assert_equal(accounting, player.dibs.Sync.CalculateContentHash(player.dibs.GetDB().ledgers))
    assert_equal(0, #player.dibs.Sync.BuildAwardReservationDigest().releases)
  end)

  it("catches up a disconnected client after the original release packet was lost", function()
    local world, coordinator, player = setup()
    local created = proposal(coordinator, "release-offline")
    assert_true(send(coordinator, player, coordinator.dibs.Sync.BuildAwardReservationDigest().records))
    world:SetOnline(player.name, false)
    assert_true(coordinator.dibs.Governance.ResolveAwardProposal(created.proposalId, "STALE", "TEST_STALE"))
    world:TakePackets() -- The release was lost, rather than retained by the test transport.
    local saved = world:Snapshot(coordinator)
    world.clients[coordinator.name] = nil
    coordinator = world:Load("Coordinator-Realm", saved)
    proposal(coordinator, "new-pending-after-release")
    world:TakePackets()
    world:SetOnline(player.name, true)
    assert_true(coordinator.dibs.Sync.AnnounceAwardReservationDigest())
    world:Deliver()
    assert_equal(1, hold(player))
    assert_equal(1, hold(coordinator))
  end)

  it("shares the existing page budget between pending entries and releases", function()
    local world, coordinator, player = setup()
    for index = 1, 18 do
      local created = proposal(coordinator, "pagination-" .. tostring(index))
      if index <= 10 then
        assert_true(coordinator.dibs.Governance.ResolveAwardProposal(created.proposalId, "REJECTED", "PAGE_TEST"))
      end
    end
    world:TakePackets()
    assert_true(coordinator.dibs.Sync.AnnounceAwardReservationDigest())
    local packets = world:TakePackets()
    assert_equal(2, #packets)
    local total, released = 0, 0
    for _, packet in ipairs(packets) do
      local message = coordinator.dibs.Ace3.Deserialize(packet.payload)
      assert_true(#message.records + #message.releases <= 16)
      assert_equal(message.contentHash, coordinator.dibs.Sync.CalculateContentHash(message.records))
      assert_equal(message.releaseHash, coordinator.dibs.Sync.CalculateContentHash(message.releases))
      for _, release in ipairs(message.releases) do
        assert_nil(release.localRelease)
        assert_nil(release.itemID)
        assert_nil(release.itemLink)
      end
      total, released = total + #message.records, released + #message.releases
      assert_true(player.dibs.Sync.OnAddonMessage("DIBS", packet.payload, "GUILD", coordinator.name))
    end
    assert_equal(8, total)
    assert_equal(10, released)
    assert_equal(8, hold(player))
  end)
end)
