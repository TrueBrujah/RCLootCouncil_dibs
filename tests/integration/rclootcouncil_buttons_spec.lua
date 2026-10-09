local loader = require("helpers.load_addon")

local function makeVotingApi(columns)
  local voting = { publicColumns = columns or {}, addColumnCalls = 0 }
  function voting:GetColumnIndex(name)
    for index, column in ipairs(self.publicColumns) do
      if column.colName == name then return index end
    end
  end
  function voting:GetColumn(name)
    local index = self:GetColumnIndex(name)
    return index and self.publicColumns[index] or nil
  end
  function voting:AddColumn(spec, target, position)
    self.addColumnCalls = self.addColumnCalls + 1
    local targetIndex = target and self:GetColumnIndex(target) or nil
    if target and not targetIndex then error("Column target was not found") end
    local inserted = {}
    for key, value in pairs(spec) do inserted[key] = value end
    local insertAt = targetIndex and targetIndex + (position == "after" and 1 or 0) or #self.publicColumns + 1
    table.insert(self.publicColumns, insertAt, inserted)
    return inserted
  end
  return voting
end

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

  it("applies a template with DIB first and caps ordinary choices at nine", function()
    local profile = { maxButtons = 10, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local template = { count = 10, buttons = {} }
    for index = 1, 10 do
      template.buttons[index] = {
        text = "Button " .. tostring(index),
        response = "Response " .. tostring(index),
        color = { 0.1, 0.2, 0.3, 1 },
        requireNotes = index == 2,
      }
    end

    local applied, result = dibs.RCLootCouncil.ApplyButtonTemplate("OTHER", template, "OTHER", true)
    assert_true(applied)
    assert_equal(9, result.buttonCount)
    assert_true(result.dibIncluded)
    assert_true(result.truncated)
    assert_equal(10, profile.buttons.OTHER.numButtons)
    assert_equal("Dib", profile.buttons.OTHER[1].text)
    assert_true(profile.buttons.OTHER[1].dibsLocked)
    assert_equal("Dib", profile.responses.OTHER[1].text)
    assert_equal("Button 1", profile.buttons.OTHER[2].text)
    assert_equal("Response 1", profile.responses.OTHER[2].text)
    assert_equal(true, profile.buttons.OTHER[3].requireNotes)
    assert_equal(0.3, profile.responses.OTHER[2].color[3])
    assert_equal("Button 9", profile.buttons.OTHER[10].text)
    assert_nil(profile.buttons.OTHER[11])
    assert_true(profile.enabledButtons.OTHER)
  end)

  it("applies all ten template choices without a DIB response", function()
    local profile = { maxButtons = 10, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local template = { count = 10, buttons = {} }
    for index = 1, 10 do
      template.buttons[index] = { text = "Choice " .. index, response = "Reply " .. index }
    end

    local applied, result = dibs.RCLootCouncil.ApplyButtonTemplate("COSMETIC", template, "COSMETIC", true)
    assert_true(applied)
    assert_equal(10, result.buttonCount)
    assert_false(result.dibIncluded)
    assert_false(result.truncated)
    assert_equal("Choice 1", profile.buttons.COSMETIC[1].text)
    assert_equal("Reply 1", profile.responses.COSMETIC[1].text)
    assert_equal(10, profile.buttons.COSMETIC.numButtons)
    assert_true(profile.enabledButtons.COSMETIC)
  end)

  it("reports unsupported button schemas before template writes", function()
    local profile = {
      maxButtons = 10,
      buttons = { OTHER = { numButtons = 1, [1] = { text = "Original" } } },
      responses = { OTHER = { numButtons = 1, [1] = { text = "Original" } } },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local buttonText = profile.buttons.OTHER[1].text
    local responseText = profile.responses.OTHER[1].text
    local supported, reason = dibs.RCOptions.GetButtonTemplateCapability()
    assert_false(supported)
    assert_equal("RC_BUTTON_CONFIG_UNSUPPORTED", reason)

    local applied, applyReason = dibs.RCLootCouncil.ApplyButtonTemplate("OTHER", {
      count = 1, buttons = { { text = "New", response = "New" } },
    }, "OTHER", false)
    assert_false(applied)
    assert_equal("RC_BUTTON_CONFIG_UNSUPPORTED", applyReason)
    assert_equal(buttonText, profile.buttons.OTHER[1].text)
    assert_equal(responseText, profile.responses.OTHER[1].text)
  end)

  it("rejects an incomplete template before changing the RC profile", function()
    local profile = {
      maxButtons = 10,
      buttons = { OTHER = { numButtons = 1, [1] = { text = "Original" } } },
      responses = { OTHER = { numButtons = 1, [1] = { text = "Original" } } },
      enabledButtons = { OTHER = false },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local beforeButton = profile.buttons.OTHER[1].text
    local beforeResponse = profile.responses.OTHER[1].text
    local beforeCount = profile.buttons.OTHER.numButtons
    local beforeEnabled = profile.enabledButtons.OTHER
    local applied, reason = dibs.RCLootCouncil.ApplyButtonTemplate("OTHER", {
      count = 2,
      buttons = { { text = "Valid", response = "Valid" }, { text = "", response = "Invalid" } },
    }, "OTHER", true)

    assert_false(applied)
    assert_equal("INVALID_BUTTON_TEMPLATE", reason)
    assert_equal(beforeButton, profile.buttons.OTHER[1].text)
    assert_equal(beforeResponse, profile.responses.OTHER[1].text)
    assert_equal(beforeCount, profile.buttons.OTHER.numButtons)
    assert_equal(beforeEnabled, profile.enabledButtons.OTHER)
  end)

  it("prevalidates every set before applying a multi-set template plan", function()
    local profile = { maxButtons = 10, buttons = {}, responses = {} }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    rc.ConfigTableChanged = function() end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local valid = { count = 1, buttons = { { text = "Need", response = "Need" } } }
    local invalid = { count = 2, buttons = {
      { text = "Pass", response = "Pass" }, { text = "", response = "Invalid" },
    } }

    local applied, reason = dibs.RCLootCouncil.ApplyButtonTemplatePlan({
      { buttonSetKey = "RARE", template = valid, responseType = "RARE", includeDib = true },
      { buttonSetKey = "SPECIAL", template = invalid, responseType = "SPECIAL", includeDib = false },
    })
    assert_false(applied)
    assert_equal("INVALID_BUTTON_TEMPLATE", reason)
    assert_nil(profile.buttons.RARE)
    assert_nil(profile.responses.RARE)
    assert_nil(profile.enabledButtons)

    local planned, result = dibs.RCLootCouncil.ApplyButtonTemplatePlan({
      { buttonSetKey = "RARE", template = valid, responseType = "RARE", includeDib = true },
      { buttonSetKey = "SPECIAL", template = valid, responseType = "SPECIAL", includeDib = false },
    })
    assert_true(planned)
    assert_equal(2, result.appliedSets)
    assert_equal("Dib", profile.buttons.RARE[1].text)
    assert_true(profile.buttons.RARE[1].dibsLocked)
    assert_equal("Need", profile.buttons.RARE[2].text)
    assert_equal("Need", profile.buttons.SPECIAL[1].text)
    assert_equal(2, profile.buttons.RARE.numButtons)
    assert_equal(1, profile.buttons.SPECIAL.numButtons)
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

  it("restores shared rules and projects DIB first in buttons and responses", function()
    local profile = {
      maxButtons = 10,
      enabledButtons = { INVTYPE_HEAD = true },
      buttons = {
        default = { numButtons = 2, [1] = { text = "Need" }, [2] = { text = "Greed" } },
        INVTYPE_HEAD = { numButtons = 2, [1] = { text = "Head Need" }, [2] = { text = "Head Offspec" } },
      },
      responses = {
        default = { numButtons = 2, [1] = { text = "Need", sort = 1 }, [2] = { text = "Greed", sort = 2 } },
        INVTYPE_HEAD = { numButtons = 2, [1] = { text = "Head Need", sort = 1 }, [2] = { text = "Head Offspec", sort = 2 } },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    local _, dibs = loader.load({
      withAce3 = true,
      rclootcouncil = rc,
      savedVariables = { settings = {
        dibAllowedTypes = { default = false, OTHER = false },
        dibRCEnabledTypes = { default = false, OTHER = false },
      } },
    })
    assert_equal("Need", profile.buttons.default[1].text)

    local legacyTypes = {}
    for key in pairs(dibs.RCOptions.GetSupportedLootRuleTypeValues()) do
      if key ~= "COSMETIC" then
        legacyTypes[key] = { adventureGuide = true, rclootcouncil = true }
      end
    end
    legacyTypes.INVTYPE_HEAD = { adventureGuide = false, rclootcouncil = false }
    local normalized, reason = dibs.LootRules.NormalizeSnapshot({ schemaVersion = 1, types = legacyTypes })
    assert_true(type(normalized) == "table", tostring(reason))
    assert_nil(normalized.types.INVTYPE_HEAD)
    assert_equal(false, normalized.types.COSMETIC.adventureGuide)
    dibs.LootRules.GetAuthoritySnapshot = function()
      return normalized, "GUILD_LOOT_RULES_READY"
    end

    local refreshed, changed = dibs.RCLootCouncil.RefreshConfigProjection()
    assert_true(refreshed)
    assert_true(changed)
    assert_equal("Dib", profile.buttons.default[1].text)
    assert_equal("Need", profile.buttons.default[2].text)
    assert_equal("Dib", profile.responses.default[1].text)
    assert_equal(1, profile.responses.default[1].sort)
    assert_equal("Dib", profile.buttons.INVTYPE_HEAD[1].text)
    assert_equal("Head Need", profile.buttons.INVTYPE_HEAD[2].text)
    assert_equal("Dib", profile.responses.INVTYPE_HEAD[1].text)
    assert_equal(1, profile.responses.INVTYPE_HEAD[1].sort)
  end)

  it("removes stale DIB responses when synchronized guild rules disable every type", function()
    local profile = {
      maxButtons = 10,
      enabledButtons = { TOKEN = true },
      buttons = {
        default = { numButtons = 2, [1] = { text = "Dib", dibsLocked = true }, [2] = { text = "Need" } },
        TOKEN = { numButtons = 2, [1] = { text = "Dib", dibsLocked = true }, [2] = { text = "Token Need" } },
      },
      responses = {
        default = { numButtons = 2, [1] = { text = "Dib", sort = 1 }, [2] = { text = "Need", sort = 2 } },
        TOKEN = { numButtons = 2, [1] = { text = "Dib", sort = 1 }, [2] = { text = "Token Need", sort = 2 } },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.Getdb = function() return profile end
    local _, dibs = loader.load({ rclootcouncil = rc })

    local types = {}
    for key in pairs(dibs.RCOptions.GetSupportedLootRuleTypeValues()) do
      types[key] = { adventureGuide = false, rclootcouncil = false }
    end
    local snapshot = assert(dibs.LootRules.NormalizeSnapshot({ schemaVersion = 1, types = types }))
    dibs.LootRules.GetAuthoritySnapshot = function()
      return snapshot, "GUILD_LOOT_RULES_READY", { catalogRevision = 2 }
    end

    local refreshed, changed = dibs.RCLootCouncil.RefreshConfigProjection()
    assert_true(refreshed)
    assert_true(changed)
    assert_equal("Need", profile.buttons.default[1].text)
    assert_equal("Need", profile.responses.default[1].text)
    assert_equal("Token Need", profile.buttons.TOKEN[1].text)
    assert_equal("Token Need", profile.responses.TOKEN[1].text)
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

  it("uses the public column API and preserves the voting cell callback contract", function()
    local voting = makeVotingApi({
      { colName = "name", name = "Name" },
      { colName = "response", name = "Response" },
    })
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.GetModule = function(_, name)
      if name == "RCVotingFrame" then return voting end
      return nil
    end
    local _, dibs = loader.load({ rclootcouncil = rc })
    local dibsColumn = voting:GetColumn("dibsRemaining")
    assert_not_nil(dibsColumn)
    assert_equal(2, voting.addColumnCalls)
    assert_equal(3, voting:GetColumnIndex("dibsRemaining"))
    assert_equal(4, voting:GetColumnIndex("dibsConvert"))
    local integration = dibs.RCLootCouncil.GetVotingIntegrationStatus()
    assert_equal("ready", integration.status)
    assert_true(integration.publicColumnApi)

    local cell = {
      text = {
        SetText = function(self, value) self.value = value end,
        SetTextColor = function() end,
      },
    }
    local row = { name = "Tester-Realm", cols = { [3] = {} } }
    dibsColumn.DoCellUpdate({}, cell, { row }, voting.publicColumns, 1, 1, 3, true, {})
    assert_equal("1/1", cell.text.value)
    assert_equal(1, row.cols[3].value)
    assert_true(dibs.RCLootCouncil.GetDibsColumnValue(row) ~= nil)
  end)

  it("registers public columns after the base layout becomes available without duplicates", function()
    local voting = makeVotingApi()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = { RCVotingFrame = voting }
    local _, dibs = loader.load({ rclootcouncil = rc })

    voting.publicColumns = {
      { colName = "name", name = "Name" },
      { colName = "response", name = "Response" },
    }
    dibs.RCLootCouncil.TryUseRCModule()
    local successfulCallCount = voting.addColumnCalls
    dibs.RCLootCouncil.TryUseRCModule()

    assert_equal(3, voting:GetColumnIndex("dibsRemaining"))
    assert_equal(4, voting:GetColumnIndex("dibsConvert"))
    assert_equal(successfulCallCount, voting.addColumnCalls)
    assert_equal("ready", dibs.RCLootCouncil.GetVotingIntegrationStatus().status)
  end)

  it("keeps the read-only Dibs column when Master Looter capability is degraded", function()
    local voting = makeVotingApi({
      { colName = "name", name = "Name" },
      { colName = "response", name = "Response" },
    })
    local rc = loader.makeRCLootCouncil({ enabled = true, masterLooter = {} })
    rc.modules = { RCVotingFrame = voting }
    local _, dibs = loader.load({ rclootcouncil = rc })
    local capabilities = dibs.RCLootCouncil.GetCapabilities()
    assert_equal("degraded", capabilities.state)
    assert_equal("RC_MASTER_LOOTER_UNVERIFIABLE", capabilities.reasonCode)
    assert_true(dibs.RCLootCouncil.GetUIProjectionStatus().runtimeHooksReady ~= false)

    assert_equal(3, voting:GetColumnIndex("dibsRemaining"))
    assert_equal(4, voting:GetColumnIndex("dibsConvert"))
  end)

  it("reports unsupported versions without falling back to undocumented columns", function()
    local voting = {}
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = { RCVotingFrame = voting }
    local _, dibs = loader.load({ rclootcouncil = rc })
    local status = dibs.RCLootCouncil.GetVotingIntegrationStatus()
    assert_true(status.moduleFound)
    assert_false(status.publicColumnApi)
    assert_equal("unsupported", status.status)
    assert_equal("RC_COLUMN_API_UNSUPPORTED", status.reasonCode)
    assert_equal("3.23.3", status.requiredVersion)
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
    local original = dibs.Ledger.GetPlayerDibsProjection
    dibs.Ledger.GetPlayerDibsProjection = function()
      return { available = false, rankMaximum = 1, canonicalName = "Tester-Realm" }
    end
    local value, sortValue = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" })
    assert_equal("-/1", value)
    assert_equal(0, sortValue)
    dibs.Ledger.GetPlayerDibsProjection = original
  end)

  it("shows available Dibs in RCLootCouncil while PlayerUI retains the canonical balance", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildMembers = { "Tester-Realm" } } })
    local canonicalCalls, projectionCalls = {}, {}
    local originalCanonical = dibs.Ledger.GetCanonicalPlayerDibsState
    local originalProjection = dibs.Ledger.GetPlayerDibsProjection
    dibs.Ledger.GetCanonicalPlayerDibsState = function(seasonId, identity)
      table.insert(canonicalCalls, { seasonId = seasonId, identity = identity })
      return { available = true, balance = 2, canonicalBalance = 2, availableBalance = 1,
        pendingDibReservations = 1, rankMaximum = 3, canonicalName = "Tester-Realm", seasonId = seasonId }
    end
    dibs.Ledger.GetPlayerDibsProjection = function(identity, seasonId)
      table.insert(projectionCalls, { seasonId = seasonId, identity = identity })
      return { available = true, balance = 2, canonicalBalance = 2, availableBalance = 1,
        pendingDibReservations = 1, rankMaximum = 3, canonicalName = "Tester-Realm", seasonId = seasonId }
    end
    local summary = dibs.PlayerUI.GetSummary("Tester-Realm")
    local value, sortValue = dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" })
    assert_equal(2, summary.balance)
    assert_equal("1/3", value)
    assert_equal(1, sortValue)
    assert_equal(1, #canonicalCalls)
    assert_equal(1, #projectionCalls)
    assert_equal(canonicalCalls[1].seasonId, projectionCalls[1].seasonId)
    assert_equal(canonicalCalls[1].identity, "Tester-Realm")
    assert_equal(projectionCalls[1].identity, "Tester-Realm")
    local tooltip = dibs.RCLootCouncil.GetDibsColumnTooltip({ name = "Tester-Realm" })
    assert_true(tooltip:find("Available balance: 1", 1, true) ~= nil)
    assert_true(tooltip:find("Committed balance: 2", 1, true) ~= nil)
    assert_true(tooltip:find("Awaiting coordinator commit: 1 Dibs", 1, true) ~= nil)
    assert_true(tooltip:find("Rank maximum: 3", 1, true) ~= nil)
    dibs.Ledger.GetCanonicalPlayerDibsState = originalCanonical
    dibs.Ledger.GetPlayerDibsProjection = originalProjection
  end)

  it("keeps balance and rank maximum independent in every display state", function()
    local rc = loader.makeRCLootCouncil({ enabled = true })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildMembers = { "Tester-Realm" } } })
    local original = dibs.Ledger.GetPlayerDibsProjection
    local state = { available = true, balance = 5, rankMaximum = 5, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    dibs.Ledger.GetPlayerDibsProjection = function() return state end
    assert_equal("5/5", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    state = { available = false, balance = nil, rankMaximum = 3, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    assert_equal("-/3", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    state = { available = true, balance = 2, rankMaximum = nil, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    assert_equal("2/-", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    state = { available = false, balance = nil, rankMaximum = nil, canonicalName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId() }
    assert_equal("-", dibs.RCLootCouncil.GetDibsColumnValue({ name = "Tester-Realm" }))
    dibs.Ledger.GetPlayerDibsProjection = original
  end)

  it("shares one balance snapshot per loot update and re-reads changed sources next update", function()
    local playerName, itemID = "Tester-Realm", 275658
    local lootFrame = { EntryManager = { entries = {} } }
    function lootFrame:Update() self.updateCount = (self.updateCount or 0) + 1 end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = { RCLootFrame = lootFrame }
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      playerName = playerName, guildLeader = true, guildMembers = { playerName }, guildRankIndices = { [1] = 0 },
    } })
    assert_true(lootFrame.__dibsButtonHooked)
    local nativeDibButton = _G.CreateFrame("Button")
    nativeDibButton:SetText("Dib")
    nativeDibButton:Enable()
    for index = 1, 4 do
      lootFrame.EntryManager.entries[index] = {
        frame = _G.CreateFrame("Frame"),
        item = { link = "|cffffffff|Hitem:275658::::::::::::|h[Bench item]|h|r", typeCode = "INVTYPE_HEAD" },
        buttons = { nativeDibButton },
      }
    end

    local seasonId = dibs.GetCurrentSeasonId()
    local granted = dibs.Ledger.Grant(playerName, 1, "RCLC cache test", "test", seasonId)
    assert_not_nil(granted)
    local startingBalance = dibs.Ledger.GetBalance(playerName, seasonId)
    assert_true(startingBalance > 0)
    local originalAvailability = dibs.RCLootCouncil.IsAvailable
    local originalTypePolicy = dibs.RCLootCouncil.IsItemDibTypeAllowed
    local originalPublicPreDibs = dibs.PreDibs.IsPublicEnabled
    local originalLootRule = true
    local publicPreDibsEnabled = false
    local originalProjection = dibs.Ledger.GetCanonicalPlayerDibsState
    local originalRemoteReservations = dibs.Sync.GetPendingAwardReservations
    dibs.RCLootCouncil.IsAvailable = function() return true end
    dibs.RCLootCouncil.IsItemDibTypeAllowed = function() return originalLootRule end
    dibs.PreDibs.IsPublicEnabled = function() return publicPreDibsEnabled end
    local projections = {}
    dibs.Ledger.GetCanonicalPlayerDibsState = function(currentSeason, identity)
      local projection = originalProjection(currentSeason, identity)
      projections[#projections + 1] = projection
      return projection
    end
    local remoteReservations = {}
    dibs.Sync.GetPendingAwardReservations = function() return remoteReservations end

    local updateHooks = lootFrame.__secureHooks.Update or {}
    assert_equal(1, #updateHooks)
    local function refresh(expectedBalance, expectedPending, expectedEnabled)
      local previousReads = #projections
      lootFrame:Update()
      for _, callback in ipairs(updateHooks) do callback(lootFrame) end
      assert_equal(previousReads + 1, #projections)
      local projection = projections[#projections]
      assert_equal(expectedBalance, projection.balance)
      assert_equal(expectedPending, projection.pendingDibReservations)
      assert_equal(math.max(0, expectedBalance - expectedPending), projection.availableBalance)
      for _, entry in ipairs(lootFrame.EntryManager.entries) do
        assert_nil(entry.dibsButton)
        assert_equal(1, #entry.buttons)
      end
      assert_equal(expectedEnabled, nativeDibButton:IsEnabled())
    end

    refresh(startingBalance, 0, true)
    publicPreDibsEnabled = true
    refresh(startingBalance, 0, false)
    publicPreDibsEnabled = false
    refresh(startingBalance, 0, true)

    local proposal = assert(dibs.Governance.RecordAwardProposal(nil, {
      playerName = playerName, type = "DIB_USED", amount = -startingBalance, seasonId = seasonId,
      itemID = itemID, awardRef = "rclc-refresh-proposal",
    }))
    refresh(startingBalance, startingBalance, false)
    assert_true(dibs.Governance.MarkAwardProposalCommitted(proposal.proposalId, {}))
    refresh(startingBalance, 0, true)

    local memberKey = dibs.Identity.CanonicalMemberKey(playerName)
    remoteReservations = {{
      proposalId = "rclc-refresh-remote", playerMemberKey = memberKey,
      seasonId = seasonId, amount = startingBalance, state = "PENDING",
    }}
    refresh(startingBalance, startingBalance, false)
    remoteReservations = {}
    refresh(startingBalance, 0, true)

    local used = dibs.Ledger.Use(playerName, startingBalance, "RCLC cache test", "test", seasonId)
    assert_not_nil(used)
    refresh(0, 0, false)

    local publicRequest = assert(dibs.PreDibs.Create(playerName, itemID, "Bench item", seasonId))
    assert_not_nil(dibs.PreDibs.Confirm(publicRequest.requestId))
    refresh(0, 0, true)

    originalLootRule = false
    refresh(0, 0, false)

    local request = assert(dibs.PreDibs.Create(playerName, itemID, "Bench item", seasonId))
    assert_not_nil(request)

    dibs.RCLootCouncil.IsAvailable = originalAvailability
    dibs.RCLootCouncil.IsItemDibTypeAllowed = originalTypePolicy
    dibs.PreDibs.IsPublicEnabled = originalPublicPreDibs
    dibs.Ledger.GetCanonicalPlayerDibsState = originalProjection
    dibs.Sync.GetPendingAwardReservations = originalRemoteReservations
  end)

  it("shows confirmed Pre-Dib names in wrapped loot rows from one cached scan", function()
    local playerName = "Tester-Realm"
    local lootFrame = { EntryManager = { entries = {} } }
    function lootFrame:Update() end
    local rc = loader.makeRCLootCouncil({ enabled = true })
    rc.modules = { RCLootFrame = lootFrame }
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      playerName = playerName, guildLeader = true, guildMembers = { playerName }, guildRankIndices = { [1] = 0 },
    } })
    lootFrame.frame = _G.CreateFrame("Frame")
    lootFrame.frame.content = _G.CreateFrame("Frame")
    lootFrame.frame:SetHeight(140)
    local originalResolveRosterMember = dibs.Identity.ResolveRosterMember
    local originalClassColors = _G.RAID_CLASS_COLORS
    local classByPlayer = {
      ["Mirael-Dalaran"] = "SHAMAN",
      ["Thandor-Durotan"] = "PRIEST",
      ["Elisif-Zuljin"] = "WARRIOR",
    }
    dibs.Identity.ResolveRosterMember = function(name)
      return { status = "RESOLVED", classFileName = classByPlayer[name] }
    end
    _G.RAID_CLASS_COLORS = {
      SHAMAN = { colorStr = "ff0070de" },
      PRIEST = { colorStr = "ffffffff" },
      WARRIOR = { colorStr = "ffc79c6e" },
    }
    local seasonId = dibs.GetCurrentSeasonId()
    local requests = {
      { playerName = "Mirael-Dalaran", itemID = 280001, seasonId = seasonId, status = "confirmed" },
      { playerName = "Thandor-Durotan", itemID = 280001, seasonId = seasonId, status = "confirmed" },
      { playerName = "Elisif-Zuljin", itemID = 280001, seasonId = seasonId, status = "confirmed" },
      { playerName = "Pending-Realm", itemID = 280001, seasonId = seasonId, status = "pending" },
      { playerName = "Old-Realm", itemID = 280001, seasonId = "old-season", status = "confirmed" },
    }
    dibs.GetDB().preDibs.requests = requests

    local entries = {}
    local nativeDibButton = _G.CreateFrame("Button")
    nativeDibButton:SetText("Dib")
    nativeDibButton:Enable()
    for index, itemID in ipairs({ 280001, 280002 }) do
      local row = _G.CreateFrame("Frame")
      row:SetWidth(240)
      row:SetHeight(70)
      local entry = {
        frame = row,
        width = 240,
        item = { link = string.format("|Hitem:%d|h[Test]|h", itemID), typeCode = "INVTYPE_HEAD" },
        buttons = index == 1 and { nativeDibButton } or {},
      }
      function row:CreateFontString()
        local label = {
          SetWidth = function(self, width) self.width = width end,
          SetWordWrap = function() end,
          SetText = function(self, value) self.text = value end,
          SetTextColor = function() end,
          SetHeight = function(self, height) self.height = height end,
          GetStringHeight = function(self)
            return math.max(14, math.ceil(#(self.text or "") * 7 / self.width) * 14)
          end,
          SetPoint = function() end,
          ClearAllPoints = function() end,
          Show = function(self) self.shown = true end,
          Hide = function(self) self.shown = false end,
        }
        return label
      end
      entries[index] = entry
    end
    lootFrame.EntryManager.entries = entries

    local requestScans = 0
    local originalIpairs = ipairs
    ipairs = function(target)
      if target == requests then requestScans = requestScans + 1 end
      return originalIpairs(target)
    end
    local ok, err = pcall(function()
      for _, callback in ipairs(lootFrame.__secureHooks.Update or {}) do callback(lootFrame) end
    end)
    ipairs = originalIpairs
    dibs.Identity.ResolveRosterMember = originalResolveRosterMember
    _G.RAID_CLASS_COLORS = originalClassColors

    assert_true(ok, tostring(err))
    assert_equal(1, requestScans)
    local label = entries[1].__dibsPreDibLabel
    assert_not_nil(label)
    assert_true(label.shown)
    assert_equal("|cffffd100|||||| |rPre-Dib: ", label.text:sub(1, 28))
    assert_true(label.text:find("|cff0070deMirael-Dalaran|r", 1, true) ~= nil)
    assert_true(label.text:find("|cffffffffThandor-Durotan|r", 1, true) ~= nil)
    assert_true(label.text:find("|cffc79c6eElisif-Zuljin|r", 1, true) ~= nil)
    assert_true(label.height > 14)
    assert_false(entries[2].__dibsPreDibLabel ~= nil)
    assert_equal(70 + label.height + 8, entries[1].frame:GetHeight())
    assert_equal(70, entries[2].frame:GetHeight())
    assert_equal(140 + label.height + 8, lootFrame.frame:GetHeight())
    assert_equal(entries[1].frame, entries[2].frame._point[2])
    assert_false(nativeDibButton:IsEnabled())
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
