local loader = require("helpers.load_addon")

-- Model the documented AceGUI container contract missing from the basic GUI
-- double: AddChild performs a full layout, and PauseLayout suppresses it.
-- Count work only. These are not timings or a simulation of native frame sizes.
local function observeLayoutWork(dibs)
  local stats = { calls = 0, childVisits = 0 }
  local wrapped = {}
  local function wrap(widget)
    if wrapped[widget] then return widget end
    wrapped[widget] = true
    local addChild = widget.AddChild
    widget.PauseLayout = function(self) self.LayoutPaused = true end
    widget.ResumeLayout = function(self) self.LayoutPaused = nil end
    widget.DoLayout = function(self)
      if self.LayoutPaused or not self.layout then return end
      stats.calls = stats.calls + 1
      stats.childVisits = stats.childVisits + #(self.children or {})
    end
    widget.AddChild = function(self, child)
      addChild(self, child)
      self:DoLayout()
    end
    return widget
  end
  for _, widget in ipairs(_G.__dibsAceWidgets or {}) do wrap(widget) end
  local gui = dibs.Ace3.libs.gui
  local create = gui.Create
  gui.Create = function(self, kind) return wrap(create(self, kind)) end
  return stats
end

local function setup(memberCount)
  memberCount = memberCount or 1
  local members, ranks = {}, {}
  for index = 1, memberCount do
    members[index], ranks[index] = "Audit" .. index .. "-Realm", 3
  end
  ranks[memberCount] = 1
  local _, dibs = loader.load({ savedVariables = {}, withAce3 = true, wow = {
    guildLeader = false, playerName = members[memberCount],
    guildMembers = members, guildRankIndices = ranks,
  } })
  return dibs
end

describe("UI layout work audit", function()
  it("batches layout work while rendering a populated option group", function()
    local dibs = setup()
    local stats = observeLayoutWork(dibs)
    local shell = assert(dibs.AceGUI.CreateWindow("Audit layout", 900, 650))
    local args = {}
    for index = 1, 40 do
      args["row" .. index] = { type = "description", name = "Synthetic row " .. index, order = index }
    end
    stats.calls, stats.childVisits = 0, 0
    assert_true(dibs.AceGUI.RenderOptionsGroup(shell, shell.window,
      { type = "group", name = "", args = args }, { renderGroupTitle = false }))
    print("AUDIT_UI options=40 layouts=" .. stats.calls .. " child-visits=" .. stats.childVisits)
    assert_true(stats.childVisits <= 160,
      "unbatched construction visited " .. stats.childVisits .. " children for 40 controls")
  end)

  it("characterizes reported Officer routes with a 100-member roster", function()
    local memberCount = 100
    local dibs = setup(memberCount)
    local stats = observeLayoutWork(dibs)
    local frame = assert(dibs.OfficerUI.CreateWindow())
    local rosterCalls, roster = 0, _G.GetGuildRosterInfo
    local diagnosticsCalls, diagnostics = 0, dibs.ImportExport.GetSizeDiagnostics
    local wizardCalls, wizardStatus = 0, dibs.Wizard.GetTurnkeyStatus
    _G.GetGuildRosterInfo = function(...)
      rosterCalls = rosterCalls + 1
      return roster(...)
    end
    dibs.ImportExport.GetSizeDiagnostics = function(...)
      diagnosticsCalls = diagnosticsCalls + 1
      return diagnostics(...)
    end
    dibs.Wizard.GetTurnkeyStatus = function(...)
      wizardCalls = wizardCalls + 1
      return wizardStatus(...)
    end
    for _, route in ipairs({ "overview", "ranks", "lootTypes", "settings", "automaticDibs" }) do
      stats.calls, stats.childVisits, rosterCalls, diagnosticsCalls, wizardCalls = 0, 0, 0, 0, 0
      local before = #_G.__dibsAceWidgets
      frame:ActivateRoute(route)
      assert_equal(route, frame.mountedPage)
      print("AUDIT_UI route=" .. route .. " widgets=" .. (#_G.__dibsAceWidgets - before)
        .. " layouts=" .. stats.calls .. " child-visits=" .. stats.childVisits
        .. " roster-reads=" .. rosterCalls .. " turnkey-rebuilds=" .. wizardCalls
        .. " full-size-diagnostics=" .. diagnosticsCalls)
      assert_true(rosterCalls <= memberCount,
        route .. " should not rescan the full guild roster repeatedly during render")
      assert_equal(0, wizardCalls,
        route .. " should not rebuild the full turnkey report while rendering ordinary settings pages")
    end
    _G.GetGuildRosterInfo = roster
    dibs.ImportExport.GetSizeDiagnostics = diagnostics
    dibs.Wizard.GetTurnkeyStatus = wizardStatus
  end)

  it("uses one reconciliation projection for both Guided Setup rank checks", function()
    local dibs = setup(60)
    local original, calls = dibs.RankRules.GetAllocationReconciliation, 0
    dibs.RankRules.GetAllocationReconciliation = function(...)
      calls = calls + 1
      return original(...)
    end
    local status = dibs.Wizard.GetTurnkeyStatus()
    dibs.RankRules.GetAllocationReconciliation = original
    assert_not_nil(status)
    assert_equal(1, calls,
      "Guided Setup rebuilt the per-player allocation reconciliation projection")
  end)

  it("renders Dibs Administration without an io library or duplicate roster scan", function()
    local memberCount = 60
    local dibs = setup(memberCount)
    assert_equal(memberCount, #dibs.Identity.GetRosterSnapshot())
    local originalInfo, originalIo, rosterCalls = _G.GetGuildRosterInfo, _G.io, 0
    _G.GetGuildRosterInfo = function(...)
      rosterCalls = rosterCalls + 1
      return originalInfo(...)
    end
    _G.io = nil
    local ok, roster = pcall(dibs.OfficerUI.BuildDibsAdministrationRoster,
      dibs.GetCurrentSeasonId(), nil, "name", false)
    _G.io = originalIo
    _G.GetGuildRosterInfo = originalInfo
    assert_true(ok, tostring(roster))
    assert_equal("ready", roster.state)
    assert_equal(memberCount, #roster.rows)
    assert_equal(0, rosterCalls,
      "Dibs Administration should reuse the roster snapshot already loaded by Identity")
  end)

  it("shares one roster snapshot until the guild roster changes", function()
    local memberCount = 60
    local dibs = setup(memberCount)
    local first = dibs.Identity.GetRosterSnapshot()
    assert_equal(first, dibs.Identity.GetRosterSnapshot(),
      "unchanged roster access should return the same cached list")

    local originalInfo, rosterCalls = _G.GetGuildRosterInfo, 0
    _G.GetGuildRosterInfo = function(...)
      rosterCalls = rosterCalls + 1
      return originalInfo(...)
    end
    dibs.Identity.OnRosterChanged()
    local refreshed = dibs.Identity.GetRosterSnapshot()
    assert_true(refreshed ~= first, "roster invalidation should publish a new snapshot")
    assert_equal(memberCount, rosterCalls, "one invalidation should cause one roster refresh")
    assert_equal(refreshed, dibs.Identity.GetRosterSnapshot(),
      "pages should reuse the new snapshot until another roster event")
    assert_equal(memberCount, rosterCalls, "unchanged roster reuse should not read WoW APIs again")
    _G.GetGuildRosterInfo = originalInfo
  end)

  it("batches PlayerUI route layout work", function()
    local dibs = setup(10)
    local stats = observeLayoutWork(dibs)
    local frame = assert(dibs.PlayerUI.CreateWindow())
    for _, route in ipairs({ "my-dibs", "requests", "history", "diagnostics" }) do
      stats.calls, stats.childVisits = 0, 0
      frame.SelectTab(route)
      assert_equal(route, frame.playerTab)
      print("AUDIT_UI player-route=" .. route .. " layouts=" .. stats.calls
        .. " child-visits=" .. stats.childVisits)
      assert_true(stats.childVisits <= 100,
        route .. " should batch layout work while creating its page")
    end
  end)
end)
