local loader = require("helpers.load_addon")
local mocks = require("helpers.b11_ui_mocks")

describe("B12a window state", function()
  after_each(function() mocks.clear() end)

  it("keeps Player and Officer records separate and restores each frame once", function()
    local _, dibs = loader.load({ withAce3 = true, skipInitialize = true })
    local previous = _G.LibStub
    local _, window = mocks.installLibraries(previous)
    local player = dibs.AceGUI.CreateWindow("Player", 640, 420, nil, "PlayerWindowPosition")
    local officer = dibs.AceGUI.CreateWindow("Officer", 640, 420, nil, "OfficerWindowPosition")
    assert_not_nil(player)
    assert_not_nil(officer)
    assert_equal(2, window.restoreCount)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.PlayerWindowPosition)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.OfficerWindowPosition)
    assert_true(player.frame ~= officer.frame)
    local restored = window.restoreCount
    dibs.WindowState.Register(player.frame, "PlayerWindowPosition")
    assert_equal(restored, window.restoreCount)
  end)

  it("saves a valid drag without a second restore and recovers an off-screen frame", function()
    local _, dibs = loader.load({ withAce3 = true, skipInitialize = true })
    local previous = _G.LibStub
    local _, window = mocks.installLibraries(previous)
    local parent = _G.UIParent
    parent.GetWidth = function() return 1920 end
    parent.GetHeight = function() return 1080 end
    local frame = _G.CreateFrame("Frame", nil, parent)
    frame._point = { "BOTTOMLEFT", parent, "BOTTOMLEFT", -2000, 2000 }
    frame.GetPoint = function(self) return self._point[1], self._point[2], self._point[3], self._point[4], self._point[5] end
    frame.ClearAllPoints = function(self) self._cleared = true end
    frame.SetPoint = function(self, ...) self._point = { ... } end
    frame.GetLeft = function() return -2000 end
    frame.GetTop = function() return 2000 end
    frame.GetWidth = function() return 640 end
    frame.GetHeight = function() return 420 end
    frame.GetParent = function() return parent end
    frame.GetEffectiveScale = function() return 1 end
    frame.SetMovable = function() end
    frame.RegisterForDrag = function() end
    frame.SetScript = function(self, name, callback) self._scripts = self._scripts or {}; self._scripts[name] = callback end
    frame.StartMoving = function() end
    frame.StopMovingOrSizing = function() end
    assert_true(dibs.WindowState.Register(frame, "RecoveryWindow"))
    assert_equal("CENTER", frame._point[1])
    assert_equal(0, frame._point[4])
    assert_equal(0, frame._point[5])
    local restores = window.restoreCount
    frame._scripts.OnDragStop(frame)
    assert_equal(restores, window.restoreCount)
    assert_equal(1, window.saveCount)
  end)
end)
