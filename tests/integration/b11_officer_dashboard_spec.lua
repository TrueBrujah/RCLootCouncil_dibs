local loader = require("helpers.load_addon")

local function setup()
  local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1", "Player-2", "Player-3", "Player-4", "Player-5", "Player-6", "Player-7", "Player-8" } }, withAce3 = true })
  dibs.Seasons.GetCurrent = function() return { id = 7, name = "Midnight Season" } end
  dibs.Ledger.GetTransactions = function()
    local rows = {}
    for index = 1, 8 do
      rows[index] = { createdAt = 100 + index, playerName = "Player-" .. tostring(index), type = "DIB_USED", amount = -index, reason = "Award" }
    end
    return rows
  end
  dibs.PreDibs.GetHistory = function()
    return {
      { requestId = "r1", seasonId = 7, status = "pending", playerName = "Player-1", itemName = "Item 1", createdAt = 108 },
      { requestId = "r2", seasonId = 7, status = "confirmed", playerName = "Player-2", itemName = "Item 2", createdAt = 107 },
      { requestId = "r3", seasonId = 7, status = "pending", playerName = "Player-3", itemName = "Item 3", createdAt = 106 },
      { requestId = "r4", seasonId = 7, status = "fulfilled", playerName = "Player-4", itemName = "Item 4", createdAt = 105 },
    }
  end
  dibs.Sync.GetStatus = function() return { state = "SYNC_BEHIND", protocolState = "V2_ENFORCED", reason = "SYNC_BEHIND" } end
  dibs.Governance.GetAuthorityState = function() return {
    state = "ACTIVE", protocolState = "V2_ENFORCED", ledgerEpoch = 4,
    coordinator = { displayName = "Coordinator-Realm" },
  } end
  dibs.RCLootCouncil.GetLocalStatus = function() return {
    availability = "degraded", status = "degraded", reasonCode = "RC_MASTER_LOOTER_UNVERIFIABLE",
    diagnostic = "Master Looter could not be verified.", observedVersion = "3.0",
  } end
  return dibs
end

describe("B11d Officer dashboard", function()
  it("projects bounded operational summaries from normalized services", function()
    local dibs = setup()
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("gm", dashboard.role)
    assert_equal("Midnight Season", dashboard.season.name)
    assert_equal("Healthy", dashboard.status.ledger.label)
    assert_equal("Behind / Synchronizing", dashboard.status.sync.label)
    assert_equal("Active", dashboard.status.coordinator.label)
    assert_equal("Degraded", dashboard.status.rclootcouncil.label)
    assert_equal(2, dashboard.metrics.pendingRequests)
    assert_equal(3, dashboard.metrics.activePreDibs)
    assert_equal(5, #dashboard.recentActivity)
    assert_equal("SYNC_BEHIND", dashboard.technical.sync.state)
    assert_equal("RC_MASTER_LOOTER_UNVERIFIABLE", dashboard.technical.rclootcouncil.reasonCode)
    assert_true(dashboard.status.sync.label:find("SYNC", 1, true) == nil)
    assert_true(dashboard.status.rclootcouncil.label:find("RC_", 1, true) == nil)
  end)

  it("keeps no-season and degraded states readable", function()
    local dibs = setup()
    dibs.Seasons.GetCurrent = function() return nil end
    dibs.Ledger.GetTransactions = function() return {} end
    dibs.PreDibs.GetHistory = function() return {} end
    dibs.Sync.GetStatus = function() return { state = "SYNC_UNAVAILABLE" } end
    dibs.Governance.GetAuthorityState = function() return { state = "COORDINATOR_UNAVAILABLE" } end
    dibs.RCLootCouncil.GetLocalStatus = function() return { availability = "absent", status = "absent", reasonCode = "RC_ABSENT" } end
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("No active season", dashboard.season.name)
    assert_equal("Unavailable", dashboard.status.ledger.label)
    assert_equal("Unavailable", dashboard.status.sync.label)
    assert_equal("Unavailable", dashboard.status.coordinator.label)
    assert_equal("Unavailable", dashboard.status.rclootcouncil.label)
    assert_equal("No pending requests.", dashboard.empty.pendingRequests)
    assert_equal("No active Pre-Dibs.", dashboard.empty.activePreDibs)
    assert_equal("No recent activity.", dashboard.empty.recentActivity)
  end)

  it("presents recovery as a human-readable coordinator state with technical disclosure", function()
    local dibs = setup()
    dibs.Governance.GetAuthorityState = function() return { state = "RECOVERY_PENDING", ledgerEpoch = 9 } end
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("Recovery in progress", dashboard.status.coordinator.label)
    assert_equal("RECOVERY_PENDING", dashboard.technical.coordinator.state)
    assert_true(dashboard.status.coordinator.explanation:find("recovery", 1, true) ~= nil)
  end)
end)