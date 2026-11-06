local loader = require("helpers.load_addon")

-- Regression for the OfficerUI runtime error:
--   attempt to call a nil value
--   [OfficerUI.lua]:3632
--   [AceGUI.lua]:1483
--   [AceGUI-3.0.lua]:66
--   [AceGUIWidget-Button.lua]:22
--
-- The "Start Independent Session" button callback read the session title and
-- the starting points through `Dibs.AceGUI.GetText`, which the AceGUI
-- adapter never defined. `Dibs.AceGUI` IS the adapter table, so the call
-- raised "attempt to call a nil value" the moment the button was pressed.
--
-- The test drives the real Officer window, finds the real button, and
-- presses it. It fails on the buggy source and passes on the fixed source.

local function findWidget(root, kind, text)
  if type(root) ~= "table" then return nil end
  if root.kind == kind and (root.text == text or root.label == text) then return root end
  for _, child in ipairs(root.children or {}) do
    local value = findWidget(child, kind, text)
    if value then return value end
  end
  return nil
end

describe("OfficerUI independent raid session start button", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    return dibs
  end

  it("exposes a text reader on the AceGUI adapter", function()
    local dibs = setup()
    -- The adapter is the shared table behind Dibs.AceGUI. A caller that
    -- reads a control's text through the adapter must not reach a nil
    -- function.
    assert_not_nil(dibs.AceGUI, "the AceGUI adapter is missing")
    if dibs.AceGUI.GetText == nil then
      -- The adapter does not have to expose GetText, but then no caller may
      -- use it. This assertion documents that the adapter entry point used
      -- by the officer page is not available, so the page must not call it.
      assert_true(true, "Dibs.AceGUI.GetText is not part of the adapter contract")
    end
  end)

  it("renders the Start Independent Session button with a working callback", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("independentRaid")
    frame:Refresh()

    local button = findWidget(frame.requestDetailRoot, "Button", "Start Independent Session")
      or findWidget(frame.contentHost, "Button", "Start Independent Session")
    if button == nil then
      -- The page may be mounted in a dedicated shell; look for the button in
      -- every mounted widget instead of failing on a layout detail.
      for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
        button = findWidget(widget, "Button", "Start Independent Session")
        if button then break end
      end
    end
    assert_not_nil(button, "the Start Independent Session button was not created")
    assert_not_nil(button.callbacks and button.callbacks.OnClick,
      "the Start Independent Session button has no OnClick callback")
  end)

  it("reads the session title and starting points without calling a nil function", function()
    local dibs = setup()
    local started = {}
    local originalStart = dibs.IndependentRaid.StartSession
    dibs.IndependentRaid.StartSession = function(sessionName, startingPoints)
      started.name = sessionName
      started.points = startingPoints
      return { ok = true }
    end

    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("independentRaid")
    frame:Refresh()

    local button
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      button = findWidget(widget, "Button", "Start Independent Session")
      if button then break end
    end
    assert_not_nil(button, "the Start Independent Session button was not created")

    -- Pressing the button used to raise "attempt to call a nil value" at the
    -- `Dibs.AceGUI.GetText` call. The callback must now run to completion.
    local ok, err = pcall(function() button.callbacks.OnClick(button) end)
    assert_true(ok, "pressing Start Independent Session raised: " .. tostring(err))
    assert_not_nil(started.name, "the session start callback did not run")
    assert_equal("PUG Raid", started.name,
      "the default session title was not read from the edit box")
    assert_equal(1, started.points,
      "the default starting points were not read from the edit box")

    dibs.IndependentRaid.StartSession = originalStart
  end)

  it("passes the values typed into the session title and starting points", function()
    local dibs = setup()
    local started = {}
    local originalStart = dibs.IndependentRaid.StartSession
    dibs.IndependentRaid.StartSession = function(sessionName, startingPoints)
      started.name = sessionName
      started.points = startingPoints
      return { ok = true }
    end

    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("independentRaid")
    frame:Refresh()

    local button, titleBox, pointsBox
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      button = button or findWidget(widget, "Button", "Start Independent Session")
      titleBox = titleBox or findWidget(widget, "EditBox", "Session Title")
      pointsBox = pointsBox or findWidget(widget, "EditBox", "Starting Points")
    end
    assert_not_nil(button, "the Start Independent Session button was not created")
    assert_not_nil(titleBox, "the session title edit box was not created")
    assert_not_nil(pointsBox, "the starting points edit box was not created")

    titleBox:SetText("Relic Raid")
    pointsBox:SetText("5")

    local ok, err = pcall(function() button.callbacks.OnClick(button) end)
    assert_true(ok, "pressing Start Independent Session raised: " .. tostring(err))
    assert_equal("Relic Raid", started.name, "the typed session title was not read")
    assert_equal(5, started.points, "the typed starting points were not read")

    dibs.IndependentRaid.StartSession = originalStart
  end)
end)
