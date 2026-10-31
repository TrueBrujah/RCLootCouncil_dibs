local loader = require("helpers.load_addon")

local function load()
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  } }))
end

describe("Synchronization status", function()
  it("accepts patch and dev changes within one major.minor addon family", function()
    local dibs = load()
    assert_true(dibs.Sync.GetAddonVersionCompatibility("0.8.2"))
    assert_true(dibs.Sync.GetAddonVersionCompatibility("0.8.8-dev"))
    local message = assert(dibs.Sync.BuildEnvelope({ type = "HELLO" }))
    message.addonVersion = "0.8.2"
    local accepted, reason = dibs.Sync.Receive(message, "Tester-Realm")
    assert_true(accepted, tostring(reason))
  end)

  it("LRA21 requires an update for a 0.7.x peer and reports Loot Rules incompatible", function()
    local dibs = load()
    assert_false(dibs.Sync.GetAddonVersionCompatibility("0.7.5"))
    local message = assert(dibs.Sync.BuildEnvelope({ type = "HELLO" }))
    message.addonVersion = "0.7.5"
    local accepted, reason = dibs.Sync.Receive(message, "Tester-Realm")
    assert_false(accepted)
    assert_equal("ADDON_UPDATE_REQUIRED", reason)
    local status = dibs.Sync.GetSynchronizationStatus()
    assert_equal("0.7.5", status.lastAddonVersionMismatch.remoteVersion)
    assert_equal("Tester-Realm", status.lastAddonVersionMismatch.sender)
    assert_equal("ADDON_UPDATE_REQUIRED", dibs.Sync.GetStatusSummary().lastAddonVersionMismatchReasonCode)
    dibs.db.settings.dibAllowedTypes = { TOKEN = false }
    assert_equal("GUILD_LOOT_RULES_INCOMPATIBLE", dibs.LootRules.GetStatus().status)
    local effective, effectiveReason = dibs.LootRules.GetEffectiveValue("TOKEN", "adventureGuide")
    assert_equal(nil, effective)
    assert_equal("GUILD_LOOT_RULES_INCOMPATIBLE", effectiveReason)
    assert_true(dibs.BuildDebugReport():find("Addon version mismatch: sender=Tester-Realm local=" .. dibs.VERSION .. " remote=0.7.5 reason=ADDON_UPDATE_REQUIRED", 1, true) ~= nil)
  end)

  it("keeps legacy peers observable when they do not send an addon version", function()
    local dibs = load()
    local message = assert(dibs.Sync.BuildEnvelope({ type = "HELLO" }))
    message.addonVersion = nil
    local accepted, reason = dibs.Sync.Receive(message, "Tester-Realm")
    assert_true(accepted, tostring(reason))
    local status = dibs.Sync.GetSynchronizationStatus()
    assert_equal("REMOTE_ADDON_VERSION_UNKNOWN", status.lastAddonVersionMismatch.reasonCode)
    assert_nil(status.lastAddonVersionMismatch.remoteVersion)
  end)

  it("reports policy adoption state and retains a protocol-major mismatch", function()
    local dibs = load()
    local initial = dibs.Sync.GetSynchronizationStatus()
    assert_false(initial.governanceAdopted)
    assert_false(initial.operationalPolicyAdopted)
    assert_nil(initial.lastProtocolMismatch)

    local message = assert(dibs.Sync.BuildEnvelope({ type = "HELLO" }))
    message.protocol.major = 99
    local accepted, reason = dibs.Sync.Receive(message, "Tester-Realm")
    assert_false(accepted)
    assert_equal("UNSUPPORTED_PROTOCOL_MAJOR", reason)

    local status = dibs.Sync.GetSynchronizationStatus()
    assert_equal(99, status.lastProtocolMismatch.remoteMajor)
    assert_equal("Tester-Realm", status.lastProtocolMismatch.sender)
    assert_true(dibs.BuildDebugReport():find("Synchronization: governance=false policy=false", 1, true) ~= nil)
    assert_true(dibs.BuildDebugReport():find("Protocol mismatch: sender=Tester-Realm local=2 remote=99", 1, true) ~= nil)
    local uiStatus = dibs.OfficerUI.BuildSynchronizationStatus()
    assert_true(uiStatus ~= "")
    assert_true(uiStatus:find("Tester-Realm", 1, true) ~= nil)
  end)

  it("builds synchronization status from compact summaries without copying full histories", function()
    local dibs = load()
    local originalGovernanceState = dibs.Governance.GetState
    local originalProposals = dibs.Governance.GetAwardProposals
    local originalCatalog = dibs.Seasons.GetCatalogState
    dibs.Governance.GetState = function() error("full governance copy should not be needed") end
    dibs.Governance.GetAwardProposals = function() error("full proposal copy should not be needed") end
    dibs.Seasons.GetCatalogState = function() error("full catalog copy should not be needed") end

    local status = dibs.Sync.GetSynchronizationStatus()

    assert_false(status.governanceAdopted)
    assert_equal(0, status.pendingAwardProposals)
    assert_equal(0, status.seasonCatalogRevision)
    dibs.Governance.GetState = originalGovernanceState
    dibs.Governance.GetAwardProposals = originalProposals
    dibs.Seasons.GetCatalogState = originalCatalog
  end)

  it("provides the scalar synchronization fields used by Loot Rules without building the full status", function()
    local dibs = load()
    dibs.Sync.MarkSyncBehind("SEASON_CATALOG_PARENT_MISSING")
    local summary = dibs.Sync.GetStatusSummary()
    assert_equal("SYNC_BEHIND", summary.state)
    assert_true(summary.syncBehind)
    assert_equal("SEASON_CATALOG_PARENT_MISSING", summary.reason)
    assert_nil(summary.lastAddonVersionMismatchReasonCode)
  end)

  it("builds scalar status without constructing detailed behind-reason rows", function()
    local dibs = load()
    dibs.Sync.MarkSyncBehind("SEASON_CATALOG_PARENT_MISSING")
    local getReasons = dibs.Sync.GetSyncBehindReasons
    dibs.Sync.GetSyncBehindReasons = function() error("scalar status must not build detailed reason rows") end
    local ok, summary = pcall(dibs.Sync.GetStatusSummary)
    dibs.Sync.GetSyncBehindReasons = getReasons
    assert_true(ok, tostring(summary))
    assert_equal("SYNC_BEHIND", summary.state)
    assert_true(summary.syncBehind)
    assert_equal("SEASON_CATALOG_PARENT_MISSING", summary.reason)
  end)

  it("reads the resolved active guild Sync store without re-running database resolution", function()
    local dibs = load()
    local getDB = dibs.GetDB
    dibs.GetDB = function() error("hot Sync summary should use the resolved guild store") end
    local ok, summary = pcall(dibs.Sync.GetStatusSummary)
    dibs.GetDB = getDB
    assert_true(ok, tostring(summary))
    assert_equal("SYNC_READY", summary.state)
  end)

  it("turns peer synchronization states into explicit next actions", function()
    local dibs = load()
    local offline = dibs.OfficerUI.GetSynchronizationPeerPresentation({
      online = false, addonDetected = true, compatibility = "Compatible", syncStatus = "Behind",
    })
    assert_equal("Waiting for login", offline.label)
    assert_true(offline.nextAction:find("Log in", 1, true) ~= nil)

    local behind = dibs.OfficerUI.GetSynchronizationPeerPresentation({
      online = true, addonDetected = true, compatibility = "Compatible", syncStatus = "Behind",
    })
    assert_equal("Remote client behind", behind.label)
    assert_true(behind.nextAction:find("both clients online", 1, true) ~= nil)
  end)

  it("reads guild roster online status from the correct API return value", function()
    local dibs = load()
    local peers = dibs.Sync.GetPeerStatuses("GUILD")
    local officer
    for _, peer in ipairs(peers) do
      if peer.playerName == "Officer-Realm" then officer = peer; break end
    end
    assert_not_nil(officer)
    assert_true(officer.rosterOnline)
    assert_true(officer.online)
    assert_equal("ROSTER", officer.presenceSource)
  end)

  it("uses a recent addon response when the guild roster still reports offline", function()
    local dibs = load()
    local originalGetGuildRosterInfo = _G.GetGuildRosterInfo
    _G.GetGuildRosterInfo = function(index)
      local name, rankName, rankIndex = originalGetGuildRosterInfo(index)
      return name, rankName, rankIndex, nil, nil, nil, nil, nil, false
    end
    dibs.Identity.OnRosterChanged()

    local member = dibs.Identity.ResolveRosterMember("Officer-Realm")
    dibs.GetDB().sync.v2.peers[member.memberKey] = {
      lastSeenAt = 1700000000,
      addonVersion = "0.8.3",
    }

    local officer
    for _, peer in ipairs(dibs.Sync.GetPeerStatuses("GUILD")) do
      if peer.playerName == "Officer-Realm" then officer = peer; break end
    end
    assert_not_nil(officer)
    assert_true(officer.online)
    assert_false(officer.rosterOnline)
    assert_equal("ADDON_HEARTBEAT", officer.presenceSource)
    assert_true(officer.addonDetected)
  end)
end)
