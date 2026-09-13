local loader = require("helpers.load_addon")

describe("Pre-Dib recovery sync", function()
  it("builds a bounded V2 request index including lifecycle state without ledger effects", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 }, inRaid = true, instanceType = "raid", instanceId = 100 } })
    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21101, "Item", dibs.GetCurrentSeasonId(), "test")
    local before = #dibs.Ledger.GetAllTransactions()
    local manifest = dibs.Sync.BuildManifest()

    assert_equal("DIGEST", manifest.type)
    assert_equal(1, #manifest.index)
    assert_equal(request.requestId, manifest.index[1].requestId)
    assert_not_nil(manifest.index[1].contentHash)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("rejects forbidden or forged transfer records", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    assert_false(dibs.Sync.Receive({ type = "MANIFEST", candidates = { "private" } }, "Tester-Realm"))
    assert_false(dibs.Sync.Receive({ type = "REQUEST", request = { requestId = "x", playerName = "Other-Realm", itemID = 1, seasonId = "s" } }, "Tester-Realm"))
    local ok, result = pcall(dibs.Sync.Receive, { type = "TRANSFER_BEGIN", transferId = "bad" }, "Tester-Realm")
    assert_true(ok)
    assert_false(result)
  end)

  it("requires a guild member for requests and an officer for acknowledgements", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 } } })
    local seasonId = dibs.GetCurrentSeasonId()
    local request = { requestId = "outside", playerName = "Outside-Realm", itemID = 21102, seasonId = seasonId, status = "confirmed", revision = 1 }
    assert_false(dibs.Sync.Receive({ type = "REQUEST", request = request }, "Outside-Realm"))
    assert_false(dibs.Sync.Receive({ type = "REQUEST_ACK", requestId = "missing", revision = 1 }, "Tester-Realm"))
  end)

  it("does not disclose stored requests to an ordinary guild member", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildMembers = { "Tester-Realm", "Player2-Realm" }, guildRankIndices = { [1] = 3, [2] = 3 } } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.PreDibs.CreatePublic("Tester-Realm", 21103, "Item", seasonId, "test")
    local manifest = { type = "MANIFEST", version = dibs.PROTOCOL_VERSION, guildKey = dibs.GetGuildKey(), requests = {} }
    assert_false(dibs.Sync.Receive(manifest, "Player2-Realm"))
    local fetch = { type = "FETCH", version = dibs.PROTOCOL_VERSION, guildKey = dibs.GetGuildKey(), requests = { { requestId = "unknown" } } }
    assert_false(dibs.Sync.Receive(fetch, "Player2-Realm"))
  end)

  it("uses AceComm registration and AceTimer for one bounded anti-entropy heartbeat", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, inRaid = true }, withAce3 = true })
    assert_not_nil(dibs.Ace3.libs.comm.handlers.DIBS)
    dibs.Ace3.libs.timer.scheduled = {}
    dibs.Sync.heartbeat = nil
    dibs.Sync.OnLifecycle("STARTUP")
    assert_equal(1, #dibs.Ace3.libs.timer.scheduled)
    dibs.Sync.OnLifecycle("STARTUP")
    assert_equal(1, #dibs.Ace3.libs.timer.scheduled)
  end)
end)
