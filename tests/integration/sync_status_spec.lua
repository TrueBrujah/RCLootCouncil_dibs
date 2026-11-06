local loader = require("helpers.load_addon")

local function load()
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  } }))
end

describe("Synchronization status", function()
  it("reuses the resolved guild DB for sync-behind and writer compatibility checks", function()
    local dibs = load()
    local db = dibs.GetDB()
    db.sync.v2.syncBehind = true
    local originalGetDB = dibs.GetDB
    dibs.GetDB = function() error("resolved guild DB should be reused") end

    local behindOk, behind = pcall(dibs.Sync.IsSyncBehind, db)
    local compatibilityOk, compatible, reason = pcall(dibs.Sync.CanEnforceV2, { "Tester-Realm" }, db)

    dibs.GetDB = originalGetDB
    assert_true(behindOk, tostring(behind))
    assert_true(behind)
    assert_true(compatibilityOk, tostring(compatible))
    assert_true(compatible, tostring(reason))
    assert_equal("WRITER_COMPATIBLE", reason)
  end)

  it("reuses a supplied guild DB for season, baseline, and active-ledger reads", function()
    local dibs = load()
    local db = dibs.GetDB()
    db.currentSeasonId = db.currentSeasonId or "season-test"
    local expectedSeason = db.currentSeasonId
    local expectedLedger = db.activeLedgerId or "guild-primary"
    local expectedBaseline = dibs.HistoricalBaseline.GetBaselineHash(db)
    local originalGetDB = dibs.GetDB
    dibs.GetDB = function() error("resolved guild DB should be reused") end

    local ok, values = pcall(function()
      return {
        season = dibs.GetCurrentSeasonId(db),
        baseline = dibs.HistoricalBaseline.GetBaselineHash(db),
        ledger = dibs.MultiLedger.GetActiveLedgerId(db),
      }
    end)

    dibs.GetDB = originalGetDB
    assert_true(ok, tostring(values))
    assert_equal(expectedSeason, values.season)
    assert_equal(expectedBaseline, values.baseline)
    assert_equal(expectedLedger, values.ledger)
  end)

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

  it("reuses the route DB for the synchronization policy status", function()
    local dibs = load()
    local db = dibs.GetDB()
    local originalIsAdopted = dibs.OperationalPolicy.IsAdopted
    local receivedDB
    dibs.OperationalPolicy.IsAdopted = function(dbOverride)
      receivedDB = dbOverride
      return originalIsAdopted(dbOverride)
    end

    dibs.OfficerUI.BuildSynchronizationProjection("GUILD", { db = db, page = 1, pageSize = 20 })

    dibs.OperationalPolicy.IsAdopted = originalIsAdopted
    assert_equal(db, receivedDB, "the status projection should not resolve the guild DB again")
  end)

  it("uses a compact status in the Officer projection and loads reasons only when behind", function()
    local dibs = load()
    local getReasons = dibs.Sync.GetSyncBehindReasons
    dibs.Sync.GetSyncBehindReasons = function() error("ready status must not build behind reasons") end
    local ok, readyProjection = pcall(dibs.OfficerUI.BuildSynchronizationProjection, "GUILD", { page = 1, pageSize = 20 })
    dibs.Sync.GetSyncBehindReasons = getReasons
    assert_true(ok, tostring(readyProjection))
    assert_equal("SYNC_READY", readyProjection.state.state)
    assert_equal(0, #readyProjection.state.reasons)

    dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    local calls = 0
    dibs.Sync.GetSyncBehindReasons = function(...)
      calls = calls + 1
      return getReasons(...)
    end
    local behindProjection = dibs.OfficerUI.BuildSynchronizationProjection("GUILD", { page = 1, pageSize = 20 })
    dibs.Sync.GetSyncBehindReasons = getReasons
    assert_equal("SYNC_BEHIND", behindProjection.state.state)
    assert_equal(1, calls)
    assert_equal("LEDGER_GAP", behindProjection.state.reasons[1].code)
  end)

  it("reads warmed mismatch diagnostics without resolving SavedVariables again", function()
    local dibs = load()
    dibs.Sync.GetSynchronizationStatus()

    local originalGetDB = dibs.GetDB
    local originalGovernance = dibs.Governance.GetSynchronizationSummary
    local originalCatalog = dibs.Seasons.GetCatalogSummary
    local originalPolicyAdopted = dibs.OperationalPolicy.IsAdopted
    dibs.GetDB = function() error("warmed status reads must use the resolved Sync state") end
    dibs.Governance.GetSynchronizationSummary = function()
      return { status = "GOVERNANCE_UNINITIALIZED", pendingAwardProposals = 0 }
    end
    dibs.Seasons.GetCatalogSummary = function()
      return { catalogRevision = 0 }
    end
    dibs.OperationalPolicy.IsAdopted = function() return false end

    local ok, status = pcall(dibs.Sync.GetSynchronizationStatus)

    dibs.GetDB = originalGetDB
    dibs.Governance.GetSynchronizationSummary = originalGovernance
    dibs.Seasons.GetCatalogSummary = originalCatalog
    dibs.OperationalPolicy.IsAdopted = originalPolicyAdopted
    assert_true(ok, tostring(status))
    assert_false(status.governanceAdopted)
    assert_false(status.operationalPolicyAdopted)
  end)

  it("uses the resolved governance state for compact read summaries", function()
    local dibs = load()
    dibs.Governance.GetSynchronizationSummary()
    dibs.Governance.GetInstallationSummary()
    dibs.Governance.GetAuthorityDigestState()

    local originalGetDB = dibs.GetDB
    dibs.GetDB = function() error("compact reads must reuse the resolved governance state") end
    local ok, summaries = pcall(function()
      return {
        synchronization = dibs.Governance.GetSynchronizationSummary(),
        installation = dibs.Governance.GetInstallationSummary(),
        authority = dibs.Governance.GetAuthorityDigestState(),
      }
    end)
    dibs.GetDB = originalGetDB

    assert_true(ok, tostring(summaries))
    assert_equal("POLICY_UNINITIALIZED", summaries.synchronization.status)
    assert_equal("POLICY_UNINITIALIZED", summaries.installation.status)
    assert_equal("LEGACY_LOCAL", summaries.authority.state)
  end)

  it("reads catalog and policy digest summaries from the resolved guild DB", function()
    local dibs = load()
    local catalog = dibs.Seasons.GetCatalogSummary()
    local policy = dibs.OperationalPolicy.GetDigestSummary()
    local originalGetDB = dibs.GetDB
    dibs.GetDB = function() error("compact digests must reuse the resolved guild DB") end

    local ok, summaries = pcall(function()
      return {
        catalog = dibs.Seasons.GetCatalogSummary(),
        policy = dibs.OperationalPolicy.GetDigestSummary(),
      }
    end)
    dibs.GetDB = originalGetDB

    assert_true(ok, tostring(summaries))
    assert_equal(catalog.catalogRevision, summaries.catalog.catalogRevision)
    assert_equal(catalog.hash, summaries.catalog.hash)
    assert_equal(policy.policyRevision, summaries.policy.policyRevision)
    assert_equal(policy.hash, summaries.policy.hash)
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
