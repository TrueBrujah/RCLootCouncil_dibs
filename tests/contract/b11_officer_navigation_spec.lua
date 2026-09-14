local loader = require("helpers.load_addon")

local function hasEntry(tree, value)
  for _, entry in ipairs(tree or {}) do
    if entry.value == value then return entry end
  end
  return nil
end

local function hasSection(tree, section)
  for _, entry in ipairs(tree or {}) do
    if entry.section == section then return true end
  end
  return false
end

describe("B11d Officer navigation", function()
  it("keeps the Officer navigation hidden from a normal Player", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildRankIndices = { 3 } }, withAce3 = true })
    local navigation = dibs.OfficerUI.GetNavigationTree()
    assert_equal(0, #navigation)
  end)

  it("groups the Officer navigation and hides Developer and Debug by default", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildRankIndices = { 1 } }, withAce3 = true })
    local navigation = dibs.OfficerUI.GetNavigationTree()
    assert_not_nil(hasEntry(navigation, "overview"))
    assert_not_nil(hasEntry(navigation, "disputes"))
    assert_not_nil(hasEntry(navigation, "preDibs"))
    assert_not_nil(hasEntry(navigation, "history"))
    assert_not_nil(hasEntry(navigation, "seasons"))
    assert_not_nil(hasEntry(navigation, "ranks"))
    assert_not_nil(hasEntry(navigation, "lootTypes"))
    assert_not_nil(hasEntry(navigation, "announcements"))
    assert_not_nil(hasEntry(navigation, "integration"))
    assert_not_nil(hasEntry(navigation, "settings"))
    assert_not_nil(hasEntry(navigation, "diagnostics"))
    assert_nil(hasEntry(navigation, "developer"))
    assert_nil(hasEntry(navigation, "debug"))
    assert_true(hasSection(navigation, "OVERVIEW"))
    assert_true(hasSection(navigation, "DIBS"))
    assert_true(hasSection(navigation, "GUILD RULES"))
    assert_true(hasSection(navigation, "INTEGRATIONS"))
    assert_true(hasSection(navigation, "SYSTEM"))

    dibs.DeveloperMode.SetEnabled(true)
    navigation = dibs.OfficerUI.GetNavigationTree()
    assert_not_nil(hasEntry(navigation, "developer"))
    assert_not_nil(hasEntry(navigation, "debug"))
  end)

  it("supports simulated Officer and GM presentation without granting production authority", function()
    local _, dibs = loader.load({ wow = { guildLeader = false, guildRankIndices = { 3 } }, withAce3 = true })
    dibs.DeveloperMode.SetEnabled(true)
    local before = loader.snapshotProductionState(dibs)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true, role = "officer" }))
    local officer = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("officer", officer.role)
    assert_equal("sandbox", officer.provider)
    assert_equal("simulated_sandbox", officer.authorityOrigin)
    assert_true(#dibs.OfficerUI.GetNavigationTree() > 0)
    assert_equal("player", dibs.Permissions.GetGuildRole())
    local denied = dibs.ProtectedActions.Execute("season.create", nil, { name = "Sandbox season" })
    assert_false(denied.ok)
    assert_equal("MIXED_PROVIDER_REJECTED", denied.reasonCode)
    assert_true(loader.productionStateEquals(dibs, before))

    assert_true(dibs.DeveloperSandbox.SetRole("gm"))
    local gm = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("gm", gm.role)
    assert_true(gm.capabilities.governance == true)
    assert_equal("player", dibs.Permissions.GetGuildRole())
    assert_true(loader.productionStateEquals(dibs, before))
    assert_true(dibs.DeveloperSandbox.ExitSandbox())
  end)
end)