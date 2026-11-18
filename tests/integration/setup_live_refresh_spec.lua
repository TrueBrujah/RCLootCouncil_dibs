local loader = require("helpers.load_addon")

local function open()
  local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
  local frame = dibs.PlayerUI.CreateWindow()
  frame:Show()
  local refresh, count = frame.Refresh, 0
  frame.Refresh = function(self)
    count = count + 1
    return refresh(self)
  end
  return dibs, frame, function() return count end
end

describe("Visible Player setup access refresh", function()
  it("updates an already open fresh Player window after real foundation initialization", function()
    local dibs, frame, count = open()
    assert_equal("setup-status", frame.playerTab)
    local initialized = dibs.Installation.Initialize(nil, {})
    assert_true(initialized.ok)
    assert_true(dibs.PlayerUI.RefreshSetupAccess())
    assert_equal(1, count())
    assert_true(frame.playerTab ~= "setup-status")
    assert_true(frame._dibsNavigationKey:find("history", 1, true) ~= nil)
    assert_false(dibs.PlayerUI.RefreshSetupAccess())
    assert_equal(1, count())
  end)

  it("detects remotely changed access on the next throttled visible tick", function()
    local dibs, frame, count = open()
    local reads = 0
    local access = { firstInstall = true, foundationReady = false, routes = {}, dependencies = {} }
    dibs.Wizard.GetNavigationAccess = function() reads = reads + 1; return access end
    dibs.Wizard.GetTurnkeyStatus = function() error("must not run readiness from access monitoring") end
    dibs.SetupAssistant.Evaluate = function() error("must not run full setup checks from access monitoring") end
    local tick = frame:GetScript("OnUpdate")
    assert_not_nil(tick)
    tick(frame, 0.4)
    tick(frame, 0.4)
    assert_equal(0, reads)
    access = { firstInstall = false, foundationReady = true, routes = {}, dependencies = {} }
    tick(frame, 0.2)
    assert_equal(1, count())
    assert_true(frame._dibsNavigationKey:find("vault", 1, true) ~= nil)
    tick(frame, 1)
    assert_equal(1, count())
  end)

  it("preserves live input controls and selection when access does not change", function()
    local dibs, frame = open()
    dibs.Installation.Initialize(nil, {})
    dibs.PlayerUI.RefreshSetupAccess()
    frame.SelectTab("history")
    local beforePage = frame.playerPageHost
    frame.historyQuery = "unfinished typed search"
    frame.historyPage = 3
    assert_false(dibs.PlayerUI.RefreshSetupAccess())
    frame:GetScript("OnUpdate")(frame, 1)
    assert_equal(beforePage, frame.playerPageHost)
    assert_equal("history", frame.playerTab)
    assert_equal("unfinished typed search", frame.historyQuery)
    assert_equal(3, frame.historyPage)
  end)

  it("does no access work while hidden or after the shell is released", function()
    local dibs, frame, count = open()
    local reads = 0
    dibs.Wizard.GetNavigationAccess = function() reads = reads + 1; error("hidden window must not read access") end
    frame:Hide()
    assert_false(dibs.PlayerUI.RefreshSetupAccess())
    local tick = frame:GetScript("OnUpdate")
    tick(frame, 20)
    assert_equal(0, reads)
    assert_equal(0, count())
    frame:Show()
    local shell = frame.dibsAceGUIShell
    shell._dibsActive = false
    shell.onRelease()
    assert_false(dibs.PlayerUI.RefreshSetupAccess())
    tick(frame, 20)
    assert_equal(0, reads)
    assert_nil(frame.Refresh)
    assert_nil(frame._dibsNavigationKey)
  end)

  it("redirects a currently visible page if remote policy removes its access", function()
    local dibs, frame = open()
    local access = { firstInstall = false, foundationReady = true,
      routes = { seasonalRoster = true }, dependencies = { rosterConfigured = true } }
    dibs.Wizard.GetNavigationAccess = function() return access end
    assert_true(dibs.PlayerUI.RefreshSetupAccess())
    frame.SelectTab("seasonal-roster")
    assert_equal("seasonal-roster", frame.playerTab)
    access.routes.seasonalRoster = false
    frame:GetScript("OnUpdate")(frame, 1)
    assert_true(frame.playerTab ~= "seasonal-roster")
    assert_nil(frame._dibsNavigationKey:find("seasonal-roster", 1, true))
  end)
end)
