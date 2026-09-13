local loader = require("helpers.load_addon")

describe("Sync privacy", function()
  it("uses AceComm and AceSerializer when supplied through LibStub", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    assert_true(dibs.Ace3.Has("comm"))
    assert_true(dibs.Sync.Send({ type = "HELLO" }, "GUILD"))
    local sent = dibs.Ace3.libs.comm.sent[1]
    assert_equal("DIBS", sent.prefix)
    assert_true(dibs.Sync.OnAddonMessage(sent.prefix, sent.payload, sent.channel, "Tester-Realm"))
  end)

  it("reports SYNC_UNAVAILABLE without a compact fallback when Ace3 is unavailable", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withLibStub = false })
    local sent, reason = dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    assert_false(sent)
    assert_equal("SYNC_UNAVAILABLE", reason)
    assert_equal("SYNC_UNAVAILABLE", dibs.Sync.GetStatus().state)
    assert_equal(0, #_G.__sentAddonMessages)
  end)

  it("rejects live loot session fields in snapshots", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local ok = dibs.Sync.ApplySnapshot({
      transactions = {},
      candidates = { "A" },
    })
    assert_false(ok)
  end)

  it("does not let an ordinary player export or apply the authoritative snapshot", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = false,
      guildMembers = { "Tester-Realm" },
      guildRankIndices = { [1] = 3 },
    } })
    local exported = dibs.Sync.SyncSnapshot()
    assert_equal(0, #exported.transactions)
    assert_equal("OFFICER_SCOPE_REQUIRED", exported.reasonCode)
    local digest = dibs.Sync.GetDigest()
    assert_equal(0, digest.txCount)
    assert_equal("OFFICER_SCOPE_REQUIRED", digest.reasonCode)
    local peer, peerReason = dibs.Sync.GetPeerState("peer")
    assert_nil(peer)
    assert_equal("OFFICER_SCOPE_REQUIRED", peerReason)

    local applied, reason = dibs.Sync.ApplySnapshot({ transactions = {}, preDibs = {} })
    assert_false(applied)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)
end)
