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
    assert_true(dibs.Sync.GetAddonVersionCompatibility("0.6.2"))
    assert_true(dibs.Sync.GetAddonVersionCompatibility("0.6.4-dev"))
    local message = assert(dibs.Sync.BuildEnvelope({ type = "HELLO" }))
    message.addonVersion = "0.6.2"
    local accepted, reason = dibs.Sync.Receive(message, "Tester-Realm")
    assert_true(accepted, tostring(reason))
  end)

  it("requires an update for a different major.minor addon family", function()
    local dibs = load()
    assert_false(dibs.Sync.GetAddonVersionCompatibility("0.7.0"))
    local message = assert(dibs.Sync.BuildEnvelope({ type = "HELLO" }))
    message.addonVersion = "0.7.0"
    local accepted, reason = dibs.Sync.Receive(message, "Tester-Realm")
    assert_false(accepted)
    assert_equal("ADDON_UPDATE_REQUIRED", reason)
    local status = dibs.Sync.GetSynchronizationStatus()
    assert_equal("0.7.0", status.lastAddonVersionMismatch.remoteVersion)
    assert_equal("Tester-Realm", status.lastAddonVersionMismatch.sender)
    assert_true(dibs.BuildDebugReport():find("Addon version mismatch: sender=Tester-Realm local=0.6.5 remote=0.7.0 reason=ADDON_UPDATE_REQUIRED", 1, true) ~= nil)
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
end)
