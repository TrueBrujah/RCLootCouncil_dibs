local loader = require("helpers.load_addon")

local function load()
  local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
  return dibs
end

describe("Progressive Officer setup navigation", function()
  it("shows only Guided Setup on a real fresh installation", function()
    local dibs = load()
    local tree = dibs.OfficerUI.GetNavigationTree()
    assert_equal(1, #tree)
    assert_equal("wizard", tree[1].value)
    local window = dibs.OfficerUI.CreateWindow("overview")
    assert_equal("wizard", window.activeTab)
    window:SelectTab("history")
    assert_equal("wizard", window.activeTab)
    window:SelectTab("lootRules")
    assert_equal("wizard", window.activeTab)
  end)

  it("refreshes visibility and redirects a previously open route when prerequisites change", function()
    local dibs = load()
    local access = { routes = { wizard = true, settings = true }, foundationReady = true }
    dibs.Wizard.GetNavigationAccess = function() return access end
    local window = dibs.OfficerUI.CreateWindow("settings")
    assert_equal("settings", window.activeTab)
    access = { routes = { wizard = true }, firstInstall = true }
    window:Refresh()
    assert_equal("wizard", window.activeTab)
    local tree = dibs.OfficerUI.GetNavigationTree()
    assert_equal(1, #tree)
    assert_equal("wizard", tree[1].value)
  end)

  it("does not unlock optional modules merely because a navigation dependency is ready", function()
    local dibs = load()
    dibs.Wizard.GetNavigationAccess = function()
      return { routes = { wizard = true, integration = true }, foundationReady = true }
    end
    dibs.OperationalPolicy.GetModuleStatus = function() return { enabled = false } end
    local tree = dibs.OfficerUI.GetNavigationTree()
    assert_equal(1, #tree)
    local window = dibs.OfficerUI.CreateWindow("rclootcouncil")
    assert_equal("wizard", window.activeTab)
  end)

  it("keeps custom setup's foundation workflow inside Guided Setup", function()
    local dibs = load()
    local initialize
    local addButton = dibs.AceGUI.AddButton
    dibs.AceGUI.AddButton = function(shell, parent, label, callback, ...)
      if label == "Initialize DIBS" then initialize = callback end
      return addButton(shell, parent, label, callback, ...)
    end
    dibs.Wizard.SetSelectedProfileId("custom")
    dibs.Wizard.SetCurrentStage("configure")
    local window = dibs.OfficerUI.CreateWindow("wizard")
    assert_equal("wizard", window.activeTab)
    assert_not_nil(initialize)
    assert_false(dibs.Wizard.GetNavigationAccess().foundationReady)
    initialize()
    assert_true(dibs.Wizard.GetNavigationAccess().foundationReady)
  end)
end)
