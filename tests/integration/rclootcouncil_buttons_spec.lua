local loader = require("helpers.load_addon")

describe("RCLootCouncil DIB response projection", function()
  it("adds DIB to the real indexed profile and preserves configured responses", function()
    local profile = {
      maxButtons = 10,
      enabledButtons = { INVTYPE_HEAD = true },
      buttons = {
        default = {
          numButtons = 2,
          [1] = { text = "Minor Upgrade", whisperKey = "minor" },
          [2] = { text = "yan", whisperKey = "yan" },
        },
      },
      responses = {
        default = {
          [1] = { text = "Minor Upgrade", color = { 1, 1, 1, 1 }, sort = 1 },
          [2] = { text = "yan", color = { 1, 1, 1, 1 }, sort = 2 },
        },
      },
    }
    -- RCLootCouncil's defaults normally retain inactive entries up to
    -- maxButtons; the projection must count only the active prefix.
    for index = 3, 10 do
      profile.buttons.default[index] = { text = "Unused " .. tostring(index), whisperKey = tostring(index) }
      profile.responses.default[index] = { text = "Unused " .. tostring(index), color = { 1, 1, 1, 1 }, sort = index }
    end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function(self, changedKeys) self.lastConfigChange = changedKeys end

    local _, dibs = loader.load({ rclootcouncil = rc })
    local buttons = profile.buttons.default
    local responses = profile.responses.default

    assert_equal(3, buttons.numButtons)
    assert_equal("Dib", buttons[1].text)
    assert_equal("Minor Upgrade", buttons[2].text)
    assert_equal("yan", buttons[3].text)
    assert_equal("Dib", responses[1].text)
    assert_equal("Minor Upgrade", responses[2].text)
    assert_equal("yan", responses[3].text)
    assert_equal(1, responses[1].sort)
    assert_equal(2, responses[2].sort)
    assert_equal(3, responses[3].sort)
    assert_true(profile.enabledButtons.INVTYPE_HEAD)
    assert_equal(3, profile.buttons.INVTYPE_HEAD.numButtons)
    assert_equal("Dib", profile.buttons.INVTYPE_HEAD[1].text)
    assert_equal("Dib", profile.responses.INVTYPE_HEAD[1].text)
    assert_true(type(profile.buttons.INVTYPE_HEAD[2]) == "table")
    assert_true(type(profile.responses.INVTYPE_HEAD[3]) == "table")
    assert_true(type(rc.lastConfigChange) == "table")
    assert_true(rc.lastConfigChange.buttons == true)
    assert_true(rc.lastConfigChange.responses == true)

    -- Re-running the adapter must not duplicate DIB or consume another slot.
    dibs.RCLootCouncil.TryUseRCModule()
    assert_equal(3, buttons.numButtons)
    assert_equal("Dib", buttons[1].text)
    assert_equal("yan", buttons[3].text)
  end)

  it("does not overwrite an active response when the profile has no capacity", function()
    local profile = {
      maxButtons = 2,
      buttons = {
        default = {
          numButtons = 2,
          [1] = { text = "Need", whisperKey = "need" },
          [2] = { text = "Transmog", whisperKey = "transmog" },
        },
      },
      responses = {
        default = {
          [1] = { text = "Need", color = { 1, 1, 1, 1 }, sort = 1 },
          [2] = { text = "Transmog", color = { 1, 1, 1, 1 }, sort = 2 },
        },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    loader.load({ rclootcouncil = rc })

    assert_equal(2, profile.buttons.default.numButtons)
    assert_equal("Need", profile.buttons.default[1].text)
    assert_equal("Transmog", profile.buttons.default[2].text)
    assert_equal("Need", profile.responses.default[1].text)
    assert_equal("Transmog", profile.responses.default[2].text)
  end)

  it("bounds a corrupted button count before projecting the DIB response", function()
    local profile = {
      maxButtons = 10,
      buttons = { default = { numButtons = 999999999 } },
      responses = { default = { numButtons = 999999999 } },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    loader.load({ rclootcouncil = rc })

    assert_equal(10, profile.buttons.default.numButtons)
    assert_equal("Button 1", profile.buttons.default[1].text)
    assert_equal("Button 1", profile.responses.default[1].text)
  end)

  it("finds the AceDB profile when the addon exposes it through db.profile", function()
    local profile = {
      maxButtons = 10,
      enabledButtons = { INVTYPE_HEAD = true },
      buttons = {
        default = {
          numButtons = 2,
          [1] = { text = "Need" },
          [2] = { text = "Transmog" },
        },
        INVTYPE_HEAD = {
          numButtons = 2,
          [1] = { text = "Head Need" },
          [2] = { text = "Head Offspec" },
        },
      },
      responses = {
        default = {
          [1] = { text = "Need" },
          [2] = { text = "Transmog" },
        },
        INVTYPE_HEAD = {
          [1] = { text = "Head Need" },
          [2] = { text = "Head Offspec" },
        },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.db = { profile = profile }
    local _, dibs = loader.load({ rclootcouncil = rc })

    assert_equal("Dib", profile.buttons.default[1].text)
    assert_equal("Dib", profile.buttons.INVTYPE_HEAD[1].text)
    local status = dibs.RCLootCouncil.GetConfigProjectionStatus()
    assert_true(status.addonFound)
    assert_equal(1, status.profileCount)
    assert_equal(1, status.default.buttonDibIndex)
    assert_equal(1, status.additional.INVTYPE_HEAD.buttonDibIndex)
  end)

  it("renders the canonical balance from a normalized RCLootCouncil row identity", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.Ledger.RegisterSeasonAllocation("Tester-Realm", seasonId, 1, "Voting column test")

    local value, sortValue, identity = dibs.RCLootCouncil.GetDibsColumnValue({
      name = "|cff00ff00Tester-Realm|r",
    })
    assert_equal("1/1", value)
    assert_equal(1, sortValue)
    assert_equal("Tester-Realm", identity)
  end)

  it("passes the lib-st row and cell arguments to the voting Dibs renderer", function()
    local voting = {
      addColumnCalls = 0,
      scrollCols = {
        { colName = "name", name = "Name" },
        { colName = "response", name = "Response" },
      },
      frame = {
        st = {
          cols = {},
          SetDisplayCols = function(self, cols) self.cols = cols end,
          Refresh = function() end,
        },
      },
    }
    function voting:AddColumn(spec, target, position)
      self.addColumnCalls = self.addColumnCalls + 1
      local insertAt = #self.scrollCols + 1
      for index, column in ipairs(self.scrollCols) do
        if column.colName == target then
          insertAt = position == "before" and index or index + 1
          break
        end
      end
      table.insert(self.scrollCols, insertAt, spec)
      self.frame.st:SetDisplayCols(self.scrollCols)
      return spec
    end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.GetModule = function(_, name)
      if name == "RCVotingFrame" then return voting end
      return nil
    end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local dibsColumn
    for _, column in ipairs(voting.scrollCols) do
      if column.colName == "dibsRemaining" then dibsColumn = column break end
    end
    assert_not_nil(dibsColumn)
    assert_equal(2, voting.addColumnCalls)

    local cell = {
      text = {
        SetText = function(self, value) self.value = value end,
        SetTextColor = function() end,
      },
    }
    local row = { name = "Tester-Realm", cols = { [3] = {} } }
    dibsColumn.DoCellUpdate({}, cell, { row }, voting.scrollCols, 1, 1, 3, true, voting.frame.st)
    assert_equal("1/1", cell.text.value)
    assert_equal(1, row.cols[3].value)
    assert_true(dibs.RCLootCouncil.GetDibsColumnValue(row) ~= nil)
  end)

  it("restores both voting columns after late table initialization without duplicates", function()
    local voting = { addColumnCalls = 0, frame = { st = { cols = {}, SetDisplayCols = function(self, cols) self.cols = cols end, Refresh = function() end } } }
    function voting:AddColumn(spec, target, position)
      self.addColumnCalls = self.addColumnCalls + 1
      assert_true(type(self.scrollCols) == "table")
      table.insert(self.scrollCols, spec)
      self.frame.st:SetDisplayCols(self.scrollCols)
      return spec
    end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = { RCVotingFrame = voting }
    local _, dibs = loader.load({ rclootcouncil = rc })

    voting.scrollCols = {
      { colName = "name", name = "Name" },
      { colName = "response", name = "Response" },
    }
    dibs.RCLootCouncil.TryUseRCModule()
    dibs.RCLootCouncil.TryUseRCModule()

    local counts = { dibsRemaining = 0, dibsConvert = 0 }
    for _, column in ipairs(voting.scrollCols) do
      if counts[column.colName] ~= nil then counts[column.colName] = counts[column.colName] + 1 end
    end
    assert_equal(1, counts.dibsRemaining)
    assert_equal(1, counts.dibsConvert)
    assert_equal(2, voting.addColumnCalls)

    voting.frame.st.cols = {}
    voting.frame.st:SetDisplayCols(voting.scrollCols)
    dibs.RCLootCouncil.TryUseRCModule()
    assert_equal(4, #voting.scrollCols)
    assert_equal(4, #voting.frame.st.cols)
  end)

  it("keeps the read-only Dibs column when Master Looter capability is degraded", function()
    local voting = {
      scrollCols = {
        { colName = "name", name = "Name" },
        { colName = "response", name = "Response" },
      },
      frame = { st = { cols = {}, SetDisplayCols = function(self, cols) self.cols = cols end, Refresh = function() end } },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = {} })
    rc.modules = { RCVotingFrame = voting }
    local _, dibs = loader.load({ rclootcouncil = rc })
    local capabilities = dibs.RCLootCouncil.GetCapabilities()
    assert_equal("degraded", capabilities.state)
    assert_equal("RC_MASTER_LOOTER_UNVERIFIABLE", capabilities.reasonCode)
    assert_true(dibs.RCLootCouncil.GetUIProjectionStatus().runtimeHooksReady ~= false)

    local counts = { dibsRemaining = 0, dibsConvert = 0 }
    for _, column in ipairs(voting.scrollCols) do
      if counts[column.colName] ~= nil then counts[column.colName] = counts[column.colName] + 1 end
    end
    assert_equal(1, counts.dibsRemaining)
    assert_equal(1, counts.dibsConvert)
  end)

  it("does not use guild rank allocation when the canonical balance is zero", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({
      rclootcouncil = rc,
      wow = {
        guildMembers = { "Tester-Realm", "Other-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1 },
      },
    })

    local value, sortValue, identity = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Other-Realm" })
    assert_equal("0/1", value)
    assert_equal(0, sortValue)
    assert_equal("Other-Realm", identity)
  end)

  it("resolves a unique short RCLootCouncil name through the canonical identity service", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({
      rclootcouncil = rc,
      wow = { guildMembers = { "Tester-Realm", "Short-Realm" } },
    })
    local value, _, identity = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Short" })
    assert_equal("0/1", value)
    assert_equal("Short-Realm", identity)
  end)

  it("fails closed for ambiguous or missing candidate identity", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({
      rclootcouncil = rc,
      wow = { guildMembers = { "Tester-Realm", "Same-One", "Same-Two" } },
    })
    local ambiguous = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Same" })
    assert_equal("-", ambiguous)
    local missing = dibs.RCLootCouncil.GetDibsColumnValue({ name = "NoRealm" })
    assert_equal("-", missing)
    local absent = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Absent-Realm" })
    assert_equal("-", absent)
  end)

  it("fails closed when the canonical ledger projection is unavailable", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildMembers = { "Tester-Realm" } } })
    local original = dibs.Ledger.GetPlayerSeasonState
    dibs.Ledger.GetPlayerSeasonState = function() return nil end
    local value, sortValue = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" })
    assert_equal("-/1", value)
    assert_equal(0, sortValue)
    dibs.Ledger.GetPlayerSeasonState = original
  end)

  it("uses the same canonical balance service for PlayerUI and RCLootCouncil", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildMembers = { "Tester-Realm" } } })
    local calls = {}
    local original = dibs.Ledger.GetCanonicalPlayerDibsState
    dibs.Ledger.GetCanonicalPlayerDibsState = function(seasonId, identity)
      table.insert(calls, { seasonId = seasonId, identity = identity })
      return { available = true, balance = 2, rankMaximum = 3, canonicalName = "Tester-Realm", seasonId = seasonId }
    end
    local summary = dibs.PlayerUI.GetSummary("Tester-Realm")
    local value, sortValue = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" })
    assert_equal(2, summary.balance)
    assert_equal("2/3", value)
    assert_equal(2, sortValue)
    assert_equal(2, #calls)
    assert_equal(calls[1].seasonId, calls[2].seasonId)
    assert_equal(calls[1].identity, "Tester-Realm")
    assert_equal(calls[2].identity, "Tester-Realm")
    assert_true(dibs.RCLootCouncil.GetDibsColumnTooltip({ name = "Tester-Realm" }):find("Current balance: 2", 1, true) ~= nil)
    assert_true(dibs.RCLootCouncil.GetDibsColumnTooltip({ name = "Tester-Realm" }):find("Rank maximum: 3", 1, true) ~= nil)
    dibs.Ledger.GetCanonicalPlayerDibsState = original
  end)

  it("keeps balance and rank maximum independent in every display state", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildMembers = { "Tester-Realm" } } })
    local original = dibs.Ledger.GetCanonicalPlayerDibsState
    local state = { available = true, balance = 5, rankMaximum = 5, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    dibs.Ledger.GetCanonicalPlayerDibsState = function() return state end
    assert_equal("5/5", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    state = { available = false, balance = nil, rankMaximum = 3, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    assert_equal("-/3", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    state = { available = true, balance = 2, rankMaximum = nil, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    assert_equal("2/-", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    state = { available = false, balance = nil, rankMaximum = nil, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    assert_equal("-", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    dibs.Ledger.GetCanonicalPlayerDibsState = original
  end)

  it("does not repeatedly remove a wildcard legacy DIB value", function()
    local profile = {
      buttons = {
        default = {
          numButtons = 1,
          [1] = { text = "Need" },
        },
      },
      responses = {
        default = setmetatable({
          [1] = { text = "Need", color = { 1, 1, 1, 1 }, sort = 1 },
        }, { __index = { DIB = { text = "Dib" } } }),
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local ok, changed = dibs.RCLootCouncil.RefreshConfigProjection()
    assert_true(ok)
    assert_false(changed)
    assert_nil(rawget(profile.responses.default, "DIB"))
  end)
end)
