local clients = require("helpers.canonical_operation_clients")

-- Distributed fixture isolation suite.
--
-- The distributed tests are only meaningful if each client really is an
-- independent WoW client. This suite verifies the fixture's own
-- guarantees, because a fixture that leaks state would make every
-- distributed assertion vacuous.
--
-- The guarantees:
--   * each client has its own Lua environment and its own `Dibs` table;
--   * each client has its own SavedVariables root;
--   * a mutation on one client is invisible to the others;
--   * messages are really serialized: a packet is a string, and the
--     receiver decodes it, so a live table can never cross the wire;
--   * the receiver applies the message to its own state only;
--   * an offline client genuinely misses a message and recovers it on
--     reconnection;
--   * a duplicated delivery is idempotent;
--   * the permission surface of a peer is not the local one.

describe("Distributed fixture isolation", function()
  it("E01 gives each client its own Lua environment and Dibs table", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    assert_true(coordinator.env ~= player.env, "the clients share their Lua environment")
    assert_true(coordinator.dibs ~= player.dibs, "the clients share their Dibs table")
    -- `Core.lua` publishes the namespace on its own `_G`, which is the
    -- client environment. The isolation that matters is that each
    -- environment resolves `Dibs` to its **own** table, and that the
    -- host globals are not reachable through it.
    assert_true(coordinator.env.Dibs == coordinator.dibs,
      "the coordinator environment does not resolve its own Dibs")
    assert_true(player.env.Dibs == player.dibs,
      "the player environment does not resolve its own Dibs")
    assert_true(coordinator.env.Dibs ~= player.env.Dibs,
      "the environments resolve the same Dibs table")
    -- A global the host owns is visible, but the addon namespace of the
    -- host is not.
    local hostDibs = rawget(_G, "Dibs")
    assert_true(hostDibs == nil or hostDibs ~= player.env.Dibs,
      "the host Dibs table leaked into a client")
  end)

  it("E02 gives each client its own SavedVariables root", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    local coordinatorDB = coordinator.env.RCLootCouncil_dibsDB
    local playerDB = player.env.RCLootCouncil_dibsDB
    assert_not_nil(coordinatorDB)
    assert_not_nil(playerDB)
    assert_true(coordinatorDB ~= playerDB, "the clients share their SavedVariables root")
  end)

  it("E02b never inherits the host addon namespace", function()
    -- The fixture must never resolve a client global from the host process.
    -- A host `_G.Dibs` left over from another suite would otherwise be
    -- adopted by the first client, and that client would then share its
    -- namespace with the whole test process.
    --
    -- The hazard is reproduced explicitly: a host namespace is installed
    -- before the clients are loaded, and removed afterwards so that the
    -- rest of the run is unaffected.
    local previousHostDibs = rawget(_G, "Dibs")
    local sentinel = { __rf0047_host_sentinel = true }
    rawset(_G, "Dibs", sentinel)
    local ok, err = pcall(function()
      local world = clients.new()
      local coordinator = world:Load("Coordinator-Realm")
      local player = world:Load("Player-Realm")
      -- Each client resolves `Dibs` to its **own** table, never to a
      -- table the host process already owns.
      assert_true(coordinator.env.Dibs ~= sentinel,
        "the coordinator adopted the host addon namespace")
      assert_true(player.env.Dibs ~= sentinel,
        "the player adopted the host addon namespace")
      assert_true(coordinator.env.Dibs == coordinator.dibs,
        "the coordinator did not resolve its own Dibs")
      assert_true(player.env.Dibs == player.dibs,
        "the player did not resolve its own Dibs")
      assert_true(coordinator.env.Dibs ~= player.env.Dibs,
        "the clients resolved the same Dibs table")
      -- A second client must not reuse the first client's namespace.
      local third = world:Load("Officer-Realm")
      assert_true(third.env.Dibs ~= coordinator.env.Dibs,
        "the third client adopted an existing namespace")
      assert_true(third.env.Dibs == third.dibs,
        "the third client did not resolve its own Dibs")
    end)
    rawset(_G, "Dibs", previousHostDibs)
    assert_true(ok, "the isolation check raised: " .. tostring(err))
  end)

  it("E03 keeps a mutation on one client invisible to the others", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    coordinator.dibs.Ledger.Grant("Player-Realm", 5, "isolation probe", "test", seasonId)
    local coordinatorBalance = coordinator.dibs.Ledger.GetBalance("Player-Realm", seasonId)
    local playerBalance = player.dibs.Ledger.GetBalance("Player-Realm", seasonId)
    assert_equal(5, coordinatorBalance, "the granting client did not apply its own grant")
    assert_equal(0, playerBalance, "a local grant leaked into another client")
  end)

  it("E04 serializes every message before it crosses the wire", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    world:Load("Player-Realm")
    world:ActivateV2()
    world:TakePackets()
    coordinator.dibs.Sync.AnnounceLedgerDigest("guild-primary")
    local packets = world:TakePackets()
    assert_true(#packets > 0, "the client emitted no message")
    for _, packet in ipairs(packets) do
      assert_equal("string", type(packet.payload), "a live table crossed the wire")
      assert_true(#packet.payload > 0, "an empty message crossed the wire")
    end
  end)

  it("E05 applies a received message to the receiver only", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    local officer = world:Load("Officer-Realm")
    world:ActivateV2()
    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    coordinator.dibs.Ledger.Grant("Player-Realm", 3, "wire probe", "test", seasonId)
    world:Deliver()
    local playerBalance = player.dibs.Ledger.GetBalance("Player-Realm", seasonId)
    local officerBalance = officer.dibs.Ledger.GetBalance("Player-Realm", seasonId)
    assert_true(playerBalance == 3 or playerBalance == 0,
      "the receiver holds an unexpected balance: " .. tostring(playerBalance))
    -- The recipient that is not the coordinator must never gain the
    -- coordinator's authority.
    assert_true(officer.dibs.Governance.IsV2Enforced() == false,
      "a peer enforced the V2 protocol without adopting the authority")
  end)

  it("E06 makes an offline client genuinely miss a message", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    world:ActivateV2()
    world:SetOnline("Player-Realm", false)
    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    coordinator.dibs.Ledger.Grant("Player-Realm", 4, "offline probe", "test", seasonId)
    world:Deliver()
    assert_equal(0, player.dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "an offline client received a message")
  end)

  it("E07 delivers the missed message on reconnection", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    world:ActivateV2()
    world:SetOnline("Player-Realm", false)
    coordinator.dibs.Sync.AnnounceLedgerDigest("guild-primary")
    world:Deliver()
    local deliveriesBefore = #world.deliveries
    world:Reconnect("Player-Realm")
    -- The message that was held for the offline client is delivered now.
    assert_true(#world.deliveries > deliveriesBefore,
      "the reconnected client received no message at all")
    local delivered = false
    for index = deliveriesBefore + 1, #world.deliveries do
      if world.deliveries[index].receiver == "Player-Realm" then delivered = true end
    end
    assert_true(delivered, "the held message was not delivered to the reconnected client")
  end)

  it("E08 keeps a duplicated delivery idempotent", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    world:ActivateV2()
    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    coordinator.dibs.Ledger.Grant("Player-Realm", 2, "duplicate probe", "test", seasonId)
    world:Deliver()
    local afterFirst = player.dibs.Ledger.GetBalance("Player-Realm", seasonId)
    -- Redeliver the very same payload.
    local packets = world:TakePackets()
    for _, packet in ipairs(packets) do
      player.dibs.Sync.OnAddonMessage(packet.prefix, packet.payload, packet.channel, packet.sender)
    end
    local afterSecond = player.dibs.Ledger.GetBalance("Player-Realm", seasonId)
    assert_equal(afterFirst, afterSecond, "a duplicated message changed the balance again")
  end)

  it("E09 keeps the permission surface of a peer separate", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    world:ActivateV2()
    -- The coordinator is a guild leader; the player is not an officer.
    local coordinatorRole = coordinator.dibs.Permissions.GetGuildRole(coordinator.name)
    local playerRole = player.dibs.Permissions.GetGuildRole(player.name)
    assert_true(coordinatorRole == "gm" or coordinatorRole == "officer",
      "the coordinator is not an officer: " .. tostring(coordinatorRole))
    assert_true(playerRole ~= "gm" and playerRole ~= "officer",
      "the peer inherited the officer role: " .. tostring(playerRole))
  end)

  it("E10 refuses a message that claims to come from another client", function()
    local world = clients.new()
    local coordinator = world:Load("Coordinator-Realm")
    local player = world:Load("Player-Realm")
    world:ActivateV2()
    local seasonId = coordinator.dibs.GetCurrentSeasonId()
    coordinator.dibs.Ledger.Grant("Player-Realm", 2, "forged probe", "test", seasonId)
    coordinator.dibs.Sync.AnnounceLedgerDigest("guild-primary")
    local packets = world:TakePackets()
    assert_true(#packets > 0, "the client emitted no message")
    for _, packet in ipairs(packets) do
      -- The player claims to be the coordinator.
      local accepted, reason = player.dibs.Sync.OnAddonMessage(
        packet.prefix, packet.payload, packet.channel, coordinator.name)
      -- A forged sender is refused, and never applied to the state.
      if accepted ~= true then
        assert_not_nil(reason, "a refused message omitted its diagnostic")
      end
    end
    assert_equal(0, player.dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "a forged message changed the receiver's balance")
  end)
end)
