local loader = require("helpers.load_addon")

local function loadHelpCatalogs()
  loader.load({ skipInitialize = true })
  local dibs = _G.Dibs
  local addonTable = _G.RCLootCouncil_dibs or {}
  local englishChunk = assert(loadfile("src/locales/enUS.lua"))
  englishChunk("RCLootCouncil_dibs", addonTable)
  local english = {}
  for key, value in pairs(dibs.L or {}) do
    if key:match("^UI_HELP_") or key:match("^SETUP_ASSISTANT_.*_TOOLTIP$") then
      english[key] = value
    end
  end

  _G.GetLocale = function() return "frFR" end
  local frenchChunk = assert(loadfile("src/locales/frFR.lua"))
  frenchChunk("RCLootCouncil_dibs", addonTable)
  local french = {}
  for key in pairs(english) do french[key] = dibs.L[key] end
  return english, french
end

local function hasText(value, fragment)
  return type(value) == "string" and value:find(fragment, 1, true) ~= nil
end

describe("localized UI help content", function()
  it("defines important help keys in enUS", function()
    local english = loadHelpCatalogs()
    for key, value in pairs(english) do
      assert_true(type(value) == "string" and value ~= "", key .. " must have enUS help")
    end
  end)

  it("defines important help keys in frFR", function()
    local _, french = loadHelpCatalogs()
    for key, value in pairs(french) do
      assert_true(type(value) == "string" and value ~= "", key .. " must have frFR help")
    end
  end)

  it("keeps critical Rank Allocation help distinct from its label", function()
    local english, french = loadHelpCatalogs()
    assert_true(english.UI_HELP_RANK_ALLOCATION ~= "Rank Allocation")
    assert_true(french.UI_HELP_RANK_ALLOCATION ~= "Allocation de rang")
  end)

  it("provides Guild Setup help in both locales", function()
    local english, french = loadHelpCatalogs()
    assert_true(hasText(english.UI_HELP_GUILD_SETUP, "Guild Master"))
    assert_true(hasText(french.UI_HELP_GUILD_SETUP, "maitre de guilde"))
  end)

  it("provides Rank Rules help in both locales", function()
    local english, french = loadHelpCatalogs()
    assert_true(hasText(english.UI_HELP_RANK_ALLOCATION, "selected season"))
    assert_true(hasText(french.UI_HELP_RANK_ALLOCATION, "saison selectionnee"))
  end)

  it("provides reconciliation help in both locales", function()
    local english, french = loadHelpCatalogs()
    assert_true(hasText(english.UI_HELP_RECONCILIATION, "historical"))
    assert_true(hasText(french.UI_HELP_RECONCILIATION, "historiques"))
  end)

  it("provides audited Dibs Administration help in both locales", function()
    local english, french = loadHelpCatalogs()
    assert_true(hasText(english.UI_HELP_DIBS_ADMIN, "previous balance"))
    assert_true(hasText(french.UI_HELP_DIBS_ADMIN, "avant/apres"))
  end)

  it("explains the consequence of synchronization status", function()
    local english, french = loadHelpCatalogs()
    assert_true(hasText(english.UI_HELP_SYNC_STATUS, "canonical updates"))
    assert_true(hasText(french.UI_HELP_SYNC_STATUS, "mises a jour canoniques"))
  end)

  it("keeps protocol implementation jargon out of player help", function()
    local english, french = loadHelpCatalogs()
    local playerKeys = { "UI_HELP_PLAYER_OVERVIEW", "UI_HELP_DIB_BALANCE", "UI_HELP_PREDIB", "UI_HELP_HISTORY_SCOPE" }
    local jargon = { "V2_ENFORCED", "ledgerEpoch", "SyncV2", "legacyBaselineHash" }
    for _, key in ipairs(playerKeys) do
      for _, term in ipairs(jargon) do
        assert_true(not hasText(english[key], term), key .. " exposes " .. term .. " in enUS")
        assert_true(not hasText(french[key], term), key .. " exposes " .. term .. " in frFR")
      end
    end
  end)

  it("reserves protocol terminology for technical diagnostics", function()
    local english, french = loadHelpCatalogs()
    assert_true(hasText(english.UI_HELP_TECHNICAL_DETAILS, "V2_ENFORCED"))
    assert_true(hasText(english.UI_HELP_TECHNICAL_DETAILS, "ledgerEpoch"))
    assert_true(hasText(french.UI_HELP_TECHNICAL_DETAILS, "V2_ENFORCED"))
    assert_true(hasText(french.UI_HELP_TECHNICAL_DETAILS, "ledgerEpoch"))
  end)
end)