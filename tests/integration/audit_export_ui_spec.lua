local loader = require("helpers.load_addon")

describe("Anonymous audit export UI", function()
  it("offers a copyable export on the authorized Officer Diagnostics page", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow("diagnostics")
    local exportButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == dibs.L.AUDIT_EXPORT_BUTTON then
        exportButton = widget
      end
    end

    assert_not_nil(exportButton)
    exportButton.callbacks.OnClick(exportButton, "OnClick")
    assert_true(frame.anonymousAuditExport:find(dibs.AuditExport.PREFIX, 1, true) == 1)

    local copySurface
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if (widget.kind == "MultiLineEditBox" or widget.kind == "EditBox")
        and widget.text == frame.anonymousAuditExport then
        copySurface = widget
      end
    end
    assert_not_nil(copySurface)

    dibs.AuditExport.EncodeReport = function() return nil, "ENCODER_UNAVAILABLE" end
    exportButton.callbacks.OnClick(exportButton, "OnClick")
    assert_nil(frame.anonymousAuditExport)
    assert_true(frame.statusMessage:find("ENCODER_UNAVAILABLE", 1, true) ~= nil)
  end)
end)
