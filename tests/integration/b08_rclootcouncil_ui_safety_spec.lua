local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function rcWithLoot(opts)
  opts = opts or {}
  local rc = loader.makeRCLootCouncil({ enabled = true })
  local native = {
    _scripts = {}, _text = "Need",
    SetText = function(self, value) self._text = value end,
    GetText = function(self) return self._text end,
    Enable = function(self) self.enabled = true end,
    Disable = function(self) self.enabled = false end,
    IsEnabled = function(self) return self.enabled ~= false end,
    SetAlpha = function() end,
  }
  local original = function() native.clicked = (native.clicked or 0) + 1 end
  native._scripts.OnClick = original
  local entry = { frame = {}, buttons = { native }, icon = {}, item = { link = "|Hitem:21001|h[Test]|h", sessions = { 1 } } }
  local loot = { EntryManager = { entries = { entry } }, Update = function() end }
  local voting = opts.voting
  rc.GetModule = function(_, name)
    if name == "RCLootFrame" then return loot end
    if name == "RCVotingFrame" then return voting end
  end
  return rc, loot, entry, native
end

describe("B08 RCLootCouncil UI ownership and combat safety", function()
  it("keeps the RC OnClick intact and gives only the Dibs-owned button a Dibs handler", function()
    local rc, loot, entry, native = rcWithLoot()
    local original = native._scripts.OnClick
    local _, dibs = loader.load({ rclootcouncil = rc })
    local before = #dibs.Ledger.GetAllTransactions()
    assert_equal(original, native._scripts.OnClick)
    assert_not_nil(entry.dibsButton)
    assert_true(entry.dibsButton.dibsInjected)
    assert_not_nil(entry.dibsButton._scripts.OnClick)
    assert_equal(2, #entry.buttons)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("coalesces loot and voting projection work during combat and flushes once after combat", function()
    local voting = { scrollCols = { { colName = "name" }, { colName = "response" } }, frame = { st = { cols = {}, SetDisplayCols = function(self, cols) self.cols = cols end, Refresh = function(self) self.refreshed = (self.refreshed or 0) + 1 end } } }
    local rc, loot, entry = rcWithLoot({ voting = voting })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { inCombat = true } })
    assert_nil(entry.dibsButton)
    dibs.RCLootCouncil.QueueUIRefresh("loot")
    dibs.RCLootCouncil.QueueUIRefresh("loot")
    dibs.RCLootCouncil.QueueUIRefresh("voting")
    local pending = dibs.RCLootCouncil.GetUIProjectionStatus().pending
    assert_equal(2, #pending)
    assert_equal(2, #voting.scrollCols)
    wow.setCombat(false); assert_true(dibs.RCLootCouncil.OnCombatEnded())
    assert_not_nil(entry.dibsButton)
    assert_true(#voting.scrollCols >= 3)
    assert_equal(0, #dibs.RCLootCouncil.GetUIProjectionStatus().pending)
    local button = entry.dibsButton
    assert_true(dibs.RCLootCouncil.OnCombatEnded())
    assert_equal(button, entry.dibsButton)
  end)

  it("leaves deferred work pending if combat resumes and never changes canonical ledger state", function()
    local rc, loot, entry = rcWithLoot()
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { inCombat = true } })
    local before = #dibs.Ledger.GetAllTransactions()
    dibs.RCLootCouncil.QueueUIRefresh("loot")
    assert_false(dibs.RCLootCouncil.FlushUIProjection())
    assert_nil(entry.dibsButton)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
    wow.setCombat(false)
    assert_true(dibs.RCLootCouncil.FlushUIProjection())
    assert_not_nil(entry.dibsButton)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
