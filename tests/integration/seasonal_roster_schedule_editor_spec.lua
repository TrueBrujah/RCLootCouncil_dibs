local loader = require("helpers.load_addon")

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
  local ui = dibs.AceGUI
  ui.AddLabel = function() end
  ui.AddInlineGroup = function() return {} end
  ui.AddDropdown = function(_, _, text, values, callback)
    return { text = text, values = values, choose = callback }
  end
  ui.AddCheckBox = function(_, _, text, value, callback)
    return { text = text, value = value, choose = callback }
  end
  ui.AddEditBox = function(_, _, text, callback)
    return { text = text, enter = callback, SetText = function() end }
  end
  ui.AddButton = function(_, _, text, callback)
    return { text = text, click = callback, SetDisabled = function(self, value) self.disabled = value end }
  end
  ui.SetValue = function(control, value) if control then control.value = value end end
  return dibs, { Refresh = function(self) self.refreshes = (self.refreshes or 0) + 1 end }
end

describe("Seasonal roster day and time editor", function()
  it("adds a night with a named weekday and clock input, without publishing", function()
    local dibs, frame = setup()
    local state = {}
    dibs.SeasonalRoster.CreateSeason = function() error("editor must not publish") end
    dibs.OfficerUI.RenderRaidScheduleEditor({}, {}, frame, state)
    assert_equal(0, #state.scheduleRows)
    state.addScheduleNight.click()
    dibs.OfficerUI.RenderRaidScheduleEditor({}, {}, frame, state)
    local controls = state.scheduleControls[1]
    assert_equal(dibs.L.SEASONAL_ROSTER_DAY_TUESDAY, controls.day.values[3])
    controls.day.choose(3)
    controls.time.enter(" 20:15 ")
    local rows = dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows, "Europe/Paris")
    assert_equal(3, rows[1].weekday)
    assert_equal("20:15", rows[1].startTime)
    assert_equal("Europe/Paris", rows[1].timeZone)
    assert_nil(rows[1].durationMinutes)
  end)

  it("keeps raid difficulties separate and assigns one expected difficulty per night", function()
    local dibs, frame = setup()
    local state = { raidDifficulties = { "NORMAL", "MYTHIC" }, scheduleRows = {
      { weekday = 3, startTime = "19:00" },
    } }
    dibs.OfficerUI.RenderRaidScheduleEditor({}, {}, frame, state)
    assert_equal("NORMAL", state.difficultyControls[1].difficulty)
    assert_true(state.difficultyControls[1].checkbox.value)
    assert_false(state.difficultyControls[2].checkbox.value)
    state.difficultyControls[2].checkbox.choose(true)
    assert_equal(3, #state.raidDifficulties)
    state.scheduleControls[1].difficulty.choose("HEROIC")
    local rows = dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows)
    assert_equal("HEROIC", rows[1].difficulty)
    assert_equal("NORMAL", state.raidDifficulties[1])
    assert_equal("MYTHIC", state.raidDifficulties[3])
  end)

  it("retains each historical duration and timezone while editing its time", function()
    local dibs, frame = setup()
    local state = { scheduleRows = {
      { weekday = 2, startTime = "19:00", durationMinutes = 120, timeZone = "America/Toronto" },
      { weekday = 6, startTime = "22:00", durationMinutes = 240, timeZone = "Europe/Paris" },
    } }
    dibs.OfficerUI.RenderRaidScheduleEditor({}, {}, frame, state)
    state.scheduleControls[1].time.enter("19:30")
    local rows = dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows, "ignored default")
    assert_equal(120, rows[1].durationMinutes)
    assert_equal("America/Toronto", rows[1].timeZone)
    assert_equal(240, rows[2].durationMinutes)
    assert_equal("Europe/Paris", rows[2].timeZone)
    rows = dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows, "UTC", true)
    assert_equal("UTC", rows[1].timeZone)
    assert_equal("UTC", rows[2].timeZone)
  end)

  it("removes the selected row and accepts no raid nights", function()
    local dibs, frame = setup()
    local state = { scheduleRows = { { weekday = 4, startTime = "18:00" } } }
    dibs.OfficerUI.RenderRaidScheduleEditor({}, {}, frame, state)
    state.scheduleControls[1].remove.click()
    assert_equal(0, #state.scheduleRows)
    assert_equal(0, #dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows))
  end)

  it("rejects incomplete clocks, invalid days and duplicate nights before service calls", function()
    local dibs = setup()
    for _, rows in ipairs({
      { { startTime = "20:00" } }, { { weekday = 8, startTime = "20:00" } },
      { { weekday = 3, startTime = "24:00" } }, { { weekday = 3, startTime = "20:60" } },
      { { weekday = 3, startTime = "8:00" } },
      { { weekday = 3, startTime = "20:00" }, { weekday = 3, startTime = "20:00" } },
    }) do
      local result = dibs.OfficerUI.ReadRaidScheduleRows(rows)
      assert_nil(result)
    end
  end)

  it("uses the service's seven-night limit without imposing a raid weekday", function()
    local dibs, frame = setup()
    local state = { scheduleRows = {} }
    for day = 1, 7 do state.scheduleRows[day] = { weekday = day, startTime = "20:00" } end
    dibs.OfficerUI.RenderRaidScheduleEditor({}, {}, frame, state)
    assert_true(state.addScheduleNight.disabled)
    state.addScheduleNight.click()
    assert_equal(7, #state.scheduleRows)
    assert_equal(7, #dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows))
    state.scheduleRows[8] = { weekday = 1, startTime = "21:00" }
    assert_nil(dibs.OfficerUI.ReadRaidScheduleRows(state.scheduleRows))
  end)
end)
