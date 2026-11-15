local loader = require("helpers.load_addon")

local function capturePage(dibs)
  local labels, rows = {}, nil
  local addLabel, addTable = dibs.AceGUI.AddLabel, dibs.AceGUI.AddTable
  dibs.AceGUI.AddLabel = function(shell, parent, text, fullWidth)
    labels[text] = true
    return addLabel(shell, parent, text, fullWidth)
  end
  dibs.AceGUI.AddTable = function(shell, parent, columns, values, height, actions, options)
    if columns[4] and columns[4].title == dibs.L.PLAYER_VAULT_STATUS then rows = values end
    return addTable(shell, parent, columns, values, height, actions, options)
  end
  local frame = dibs.PlayerUI.CreateWindow()
  frame.SelectTab("vault")
  return labels, rows, frame
end

describe("Great Vault capture diagnostics in Player UI", function()
  it("explains unavailable capture when the runtime adapter has no diagnostic API", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.GreatVault.GetCaptureStatus = nil
    local labels, rows = capturePage(dibs)
    assert_true(labels[dibs.L.PLAYER_VAULT_CAPTURE_UNAVAILABLE])
    assert_true(labels[dibs.L.VAULT_REASON_CLAIM_SIGNAL_UNAVAILABLE])
    assert_true(labels[dibs.L.PLAYER_VAULT_CAPTURE_HELP])
    assert_equal(0, #rows)
    assert_nil(labels[dibs.L.PLAYER_VAULT_CAPTURE_ACTIVE])
  end)

  it("shows readable equipment choices only while capture is operational", function()
    local _, dibs = loader.load({ withAce3 = true })
    local capture = { status = "OPERATIONAL", choiceCount = 3 }
    dibs.GreatVault.GetCaptureStatus = function() return capture end
    local labels, _, frame = capturePage(dibs)
    assert_true(labels[dibs.L.PLAYER_VAULT_CAPTURE_ACTIVE])
    assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_CHOICES, 3)])
    assert_true(labels[dibs.L.PLAYER_VAULT_CAPTURE_HELP])
    capture = { status = "UNAVAILABLE", reasonCode = "CLAIM_SIGNAL_UNAVAILABLE", choiceCount = 8 }
    frame:Refresh()
    assert_true(labels[dibs.L.PLAYER_VAULT_CAPTURE_UNAVAILABLE])
    assert_nil(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_CHOICES, 8)])
  end)

  it("keeps capture disabled without calling the runtime adapter and preserves historical records", function()
    local _, dibs = loader.load({ withAce3 = true })
    local saved = dibs.PreDibs.RecordVaultAcquisition(dibs.GetPlayerName(), 21016, "LFR")
    local previousGate = dibs.OperationalPolicy.RequireModuleEnabled
    dibs.OperationalPolicy.RequireModuleEnabled = function(moduleKey, ...)
      if moduleKey == "preDibs" then return false, "MODULE_DISABLED" end
      return previousGate(moduleKey, ...)
    end
    dibs.GreatVault.GetCaptureStatus = function() error("disabled capture must not be consulted") end
    local labels, rows = capturePage(dibs)
    assert_true(labels[dibs.L.PLAYER_VAULT_CAPTURE_DISABLED])
    assert_nil(labels[dibs.L.PLAYER_VAULT_CAPTURE_ACTIVE])
    assert_nil(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_CHOICES, 0)])
    assert_equal(1, #rows)
    assert_equal("LFR", rows[1][3])
    assert_equal(saved, dibs.PreDibs.GetAcquisitionsForPlayer(dibs.GetPlayerName())[1])
  end)

  it("localizes pending, confirmed, and failed capture outcomes without adding acquisitions", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { locale = "frFR" } })
    local capture = { status = "OPERATIONAL", choiceCount = 1, lastReasonCode = "CLAIM_PENDING" }
    dibs.GreatVault.GetCaptureStatus = function() return capture end
    local labels, rows, frame = capturePage(dibs)
    assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_LAST, dibs.L.VAULT_REASON_CLAIM_PENDING)])
    for _, code in ipairs({ "CLAIM_CONFIRMED", "CLAIM_ITEM_UNAVAILABLE", "DIFFICULTY_UNAVAILABLE" }) do
      capture.lastReasonCode = code
      frame:Refresh()
      assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_LAST, dibs.L["VAULT_REASON_" .. code])])
    end
    assert_equal(0, #rows)
    assert_equal(0, #dibs.PreDibs.GetAcquisitionsForPlayer(dibs.GetPlayerName()))
  end)

  it("uses localized fallback text for an unknown runtime reason", function()
    local _, dibs = loader.load({ withAce3 = true })
    dibs.GreatVault.GetCaptureStatus = function()
      return { status = "OPERATIONAL", lastReasonCode = "FUTURE_REASON" }
    end
    local labels = capturePage(dibs)
    assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_LAST, dibs.L.PLAYER_VAULT_CAPTURE_LAST_UNKNOWN)])
    assert_true(labels[string.format(dibs.L.PLAYER_VAULT_CAPTURE_CHOICES, 0)])
  end)

  it("refreshes only an existing visible Vault page when capture changes", function()
    local _, dibs = loader.load({ withAce3 = true })
    _G.DibsPlayerFrame = nil
    assert_nil(_G.DibsPlayerFrame)
    assert_false(dibs.PlayerUI.RefreshVaultCapture())
    assert_nil(_G.DibsPlayerFrame)
    local count, shown = 0, true
    _G.DibsPlayerFrame = {
      playerTab = "summary", IsShown = function() return shown end,
      Refresh = function() count = count + 1 end,
    }
    assert_false(dibs.PlayerUI.RefreshVaultCapture())
    _G.DibsPlayerFrame.playerTab = "vault"
    shown = false
    assert_false(dibs.PlayerUI.RefreshVaultCapture())
    assert_equal(0, count)
    shown = true
    assert_true(dibs.PlayerUI.RefreshVaultCapture())
    assert_equal(1, count)
    _G.DibsPlayerFrame = nil
  end)
end)
