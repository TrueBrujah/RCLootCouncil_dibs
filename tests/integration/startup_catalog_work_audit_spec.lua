local loader = require("helpers.load_addon")

describe("Startup catalog work audit", function()
  it("defers the Adventure Guide catalog scan until an officer window is requested", function()
    local _, dibs = loader.load({ withAce3 = true, savedVariables = {}, skipInitialize = true })
    assert_nil(_G.DibsOfficerFrame)
    -- The dashboard's privileged projection (which reads the EJ catalog) is
    -- available only to an Officer. Keep the scenario meaningful for this route.
    dibs.Permissions.GetGuildRole = function() return "officer" end
    local originalCatalog = dibs.EncounterJournal.GetLootCatalog
    local originalHistory = dibs.PreDibs.GetHistory
    local originalInstance = _G.EJ_GetInstanceByIndex
    local catalogCalls, instanceReads = 0, 0
    local requestHistory = {}
    dibs.PreDibs.GetHistory = function() return requestHistory end
    dibs.EncounterJournal.GetLootCatalog = function(...)
      catalogCalls = catalogCalls + 1
      return originalCatalog(...)
    end
    -- Empty journal data is sufficient to observe an unwanted native-API scan.
    -- This double does not model thousands of real items or their allocation.
    _G.EJ_GetInstanceByIndex = function()
      instanceReads = instanceReads + 1
      return nil
    end
    local ok, err = pcall(dibs.Initialize)
    assert_true(ok, tostring(err))
    assert_true(dibs.initialized)
    local officer = assert(_G.DibsOfficerFrame)
    assert_false(officer:IsShown())
    print("AUDIT_STARTUP officer-window-shown=false catalog-calls=" .. catalogCalls
      .. " journal-instance-reads=" .. instanceReads)
    assert_equal(0, catalogCalls, "startup built the item catalog for a hidden officer dashboard")
    officer:Show()
    local onShow = officer:GetScript("OnShow")
    if onShow then onShow(officer) end -- The WoW frame double does not dispatch OnShow.
    assert_equal(0, catalogCalls, "an empty dashboard should not scan a catalog it does not use")
    requestHistory = { {
      requestId = "active-test-request",
      seasonId = dibs.GetCurrentSeasonId(),
      playerName = "Tester-Realm",
      itemID = 12345,
      status = "pending",
    } }
    officer:Refresh()
    assert_equal(1, catalogCalls, "active Pre-Dibs should load the catalog for boss mapping")
    local readsAfterFirstShow = instanceReads
    officer:Hide()
    officer:Show()
    if onShow then onShow(officer) end
    assert_equal(2, catalogCalls, "reopening the dashboard should refresh its active-request projection")
    assert_equal(readsAfterFirstShow, instanceReads, "a cached catalog should not rescan the Journal")
    dibs.EncounterJournal.GetLootCatalog = originalCatalog
    dibs.PreDibs.GetHistory = originalHistory
    _G.EJ_GetInstanceByIndex = originalInstance
  end)
end)
