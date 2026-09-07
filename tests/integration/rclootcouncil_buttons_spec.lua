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

  it("renders the voting Dibs value from a normalized RCLootCouncil row identity", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.Ledger.RegisterSeasonAllocation("Tester-Realm", seasonId, 1, "Voting column test")

    local value, sortValue, identity = dibs.RCLootCouncil.GetDibsColumnValue({
      name = "|cff00ff00Tester-Realm|r",
    })
    assert_equal("2/2", value)
    assert_equal(2, sortValue)
    assert_equal("Tester-Realm", identity)
  end)

  it("passes the lib-st row and cell arguments to the voting Dibs renderer", function()
    local voting = {
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

  it("uses the guild rank allocation for a candidate with no ledger history", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({
      rclootcouncil = rc,
      wow = {
        guildMembers = { "Tester-Realm", "Other-Realm" },
        guildRankIndices = { [1] = 0, [2] = 1 },
      },
    })

    local value, sortValue, identity = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Other-Realm" })
    assert_equal("1/1", value)
    assert_equal(1, sortValue)
    assert_equal("Other-Realm", identity)
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
