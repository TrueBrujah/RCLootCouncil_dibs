local loader = require("helpers.load_addon")
local codecs = require("helpers.backup_transport_codec")

describe("Compressed backup controls", function()
  local dibs, start, oldNative
  local function widget(property, value)
    local list = _G.__dibsAceWidgets or {}
    for i = #list, start + 1, -1 do if list[i][property] == value then return list[i] end end
  end
  local function action(callback)
    start = #(_G.__dibsAceWidgets or {})
    callback()
  end
  local function click(text)
    local button = assert_not_nil(widget("text", text))
    action(function() button.callbacks.OnClick(button) end)
  end
  before_each(function()
    oldNative, _G.C_EncodingUtil = _G.C_EncodingUtil, nil
    _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true, locale = "frFR" } })
    codecs.Install()
    start = #(_G.__dibsAceWidgets or {})
  end)
  after_each(function() _G.C_EncodingUtil = oldNative end)

  it("exports and imports compressed configuration using actual transfer controls", function()
    dibs.GetDB().settings.theme = "historical compressed theme"
    action(function() dibs.DataUI.Open("transfer") end)
    assert_not_nil(widget("text", dibs.L.DATA_TRANSPORT_COMPRESSED))
    click("Export package")
    local output = assert_not_nil(widget("label", "Package (copy this text)"))
    local encoded = output.text
    assert_equal("DIBS-COMP-1|", encoded:sub(1, 12))
    assert_not_nil(dibs.ImportExport.Decode(encoded))
    dibs.GetDB().settings.theme = "live"
    local box = assert_not_nil(widget("label", "Paste package to import"))
    box.callbacks.OnTextChanged(box, "OnTextChanged", encoded)
    click("Validate and preview")
    assert_equal("live", dibs.GetDB().settings.theme)
    click("Confirm import")
    assert_equal("historical compressed theme", dibs.GetDB().settings.theme)
  end)

  it("compresses selected historical output and clears it when codec access disappears", function()
    action(function() dibs.DataUI.Open("backups") end)
    dibs.GetDB().settings.theme = "old"
    click("Create backup")
    dibs.GetDB().settings.theme = "new"
    click(dibs.L.DATA_SNAPSHOT_EXPORT_ACTION)
    local output = assert_not_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_PACKAGE))
    assert_equal("DIBS-COMP-1|", output.text:sub(1, 12))
    assert_equal("old", assert(dibs.ImportExport.Decode(output.text)).payload.presentation.theme)
    _G.LibStub, _G.C_EncodingUtil = nil, nil
    action(function() dibs.DataUI.Refresh() end)
    assert_nil(widget("label", dibs.L.DATA_SNAPSHOT_EXPORT_PACKAGE))
  end)

  it("explains codec absence and offers the working legacy export", function()
    _G.LibStub, _G.C_EncodingUtil = nil, nil
    action(function() dibs.DataUI.Open("transfer") end)
    assert_not_nil(widget("text", dibs.L.DATA_TRANSPORT_UNAVAILABLE))
    click("Export package")
    local output = assert_not_nil(widget("label", "Package (copy this text)"))
    assert_equal("DIBS-PKG-1|", output.text:sub(1, 11))
  end)

  it("discards current full output when authority changes", function()
    action(function() dibs.DataUI.Open("transfer") end)
    local scope = assert_not_nil(widget("label", "Export scope"))
    scope.callbacks.OnValueChanged(scope, "OnValueChanged", "full")
    action(function() dibs.DataUI.Refresh() end)
    click("Export package")
    click("Export package")
    assert_not_nil(widget("label", "Package (copy this text)"))
    dibs.Permissions.Can = function() return false end
    action(function() dibs.DataUI.Refresh() end)
    assert_nil(widget("label", "Package (copy this text)"))
  end)
end)
