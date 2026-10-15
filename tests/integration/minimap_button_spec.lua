local wow = require("helpers.wow_api")
local loader = require("helpers.load_addon")

describe("Minimap button", function()
  before_each(function()
    wow.install({ guildLeader = true })
    _G.Minimap = _G.CreateFrame("Frame")
    dofile("src/Core.lua")
    dofile("src/locales/enUS.lua")
    dofile("src/modules/Permissions.lua")
    dofile("src/ui/MinimapButton.lua")
  end)

  it("creates a local shortcut without changing authority state", function()
    local button = Dibs.MinimapButton.Create()
    assert_true(button ~= nil)
    assert_equal(button.parent, _G.Minimap)
    assert_equal(button.icon._texture, Dibs.ICON_TEXTURE)
  end)

  it("keeps creation safe when Minimap is unavailable", function()
    local previous = _G.Minimap
    _G.Minimap = nil
    Dibs.MinimapButton.button = nil
    assert_equal(Dibs.MinimapButton.Create(), nil)
    _G.Minimap = previous
  end)

  it("toggles the Officer view with left click and the Player view with right click", function()
    local officerShown, playerShown = false, false
    Dibs.PlayerUI, Dibs.OfficerUI = {}, {}
    Dibs.Permissions.IsOfficer = function() return true end
    Dibs.PlayerUI.Toggle = function(force)
      assert_nil(force)
      playerShown = not playerShown
    end
    Dibs.OfficerUI.Toggle = function(force)
      assert_nil(force)
      officerShown = not officerShown
    end
    local click = Dibs.MinimapButton.Create():GetScript("OnClick")
    click(nil, "LeftButton")
    assert_true(officerShown)
    click(nil, "LeftButton")
    assert_false(officerShown)
    click(nil, "RightButton")
    assert_true(playerShown)
    click(nil, "RightButton")
    assert_false(playerShown)
  end)

  it("toggles only the Player view for a non-officer", function()
    Dibs.PlayerUI, Dibs.OfficerUI = {}, {}
    Dibs.Permissions.IsOfficer = function() return false end
    Dibs.Permissions.IsGM = function() return false end
    local calls = 0
    Dibs.PlayerUI.Toggle = function() calls = calls + 1 end
    Dibs.OfficerUI.Toggle = function() error("Officer view must remain inaccessible") end
    local click = Dibs.MinimapButton.Create():GetScript("OnClick")
    click(nil, "LeftButton")
    click(nil, "RightButton")
    assert_equal(2, calls)
  end)

  it("persists visibility and reapplies it when the button is recreated", function()
    assert_true(Dibs.MinimapButton.GetVisible())
    assert_true(Dibs.MinimapButton.SetVisible(false))
    assert_false(Dibs.MinimapButton.GetVisible())
    assert_false(Dibs.MinimapButton.button:IsShown())

    Dibs.MinimapButton.button = nil
    local button = Dibs.MinimapButton.Initialize()
    assert_false(button:IsShown())
    assert_true(Dibs.MinimapButton.SetVisible(true))
    assert_true(button:IsShown())
  end)

  it("supports the show and hide slash commands", function()
    Dibs.HandleSlashCommand("minimap hide")
    assert_false(Dibs.MinimapButton.GetVisible())
    assert_false(Dibs.MinimapButton.button:IsShown())

    Dibs.HandleSlashCommand("minimap show")
    assert_true(Dibs.MinimapButton.GetVisible())
    assert_true(Dibs.MinimapButton.button:IsShown())
  end)

  it("exposes the persistent minimap preference in the Player UI", function()
    local _, dibs = loader.load({ withAce3 = true })
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("preferences")

    assert_equal("preferences", frame.playerTab)
    assert_not_nil(frame.minimapButtonToggle)
    assert_true(frame.minimapButtonToggle.value)
    frame.minimapButtonToggle.callbacks.OnValueChanged(frame.minimapButtonToggle, "OnValueChanged", false)
    assert_false(dibs.GetLocalSettings().minimapButtonShown)
    assert_false(dibs.MinimapButton.button:IsShown())
  end)
end)
