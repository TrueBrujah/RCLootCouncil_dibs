local loader = require("helpers.load_addon")

local function load(opts)
  opts = opts or {}; opts.withAce3 = true; opts.skipInitialize = true
  return select(2, loader.load(opts))
end

local function assertCore(dibs)
  assert_true(dibs.initialized)
  assert_not_nil(dibs.GetDB())
  assert_not_nil(dibs.Governance.GetState())
  assert_not_nil(dibs.Ledger.GetAllTransactions())
  assert_not_nil(_G.SlashCmdList.DIBS)
end

describe("B07 optional startup capability isolation", function()
  it("keeps core and unrelated optional capabilities available when Player UI initialization throws", function()
    local dibs = load()
    dibs.PlayerUI.CreateWindow = function() error("injected player UI failure") end
    dibs.EncounterJournal.AddActionIfAvailable = function() return true end
    assert_true(dibs.Initialize())
    assertCore(dibs)
    assert_equal("DEGRADED", dibs.Capabilities.Get("player_ui").status)
    assert_equal("AVAILABLE", dibs.Capabilities.Get("encounter_journal").status)
    assert_true(dibs.Capabilities.Get("officer_ui").status == "AVAILABLE")
    assert_true(dibs.BuildDebugReport():find("player_ui: DEGRADED", 1, true) ~= nil)
  end)

  it("keeps core available without RCLootCouncil and retries only that capability after late load", function()
    local dibs = load()
    assert_true(dibs.Initialize()); assertCore(dibs)
    assert_equal("RETRY_PENDING", dibs.Capabilities.Get("rclootcouncil").status)
    local calls, original = 0, dibs.RCLootCouncil.Initialize
    dibs.RCLootCouncil.Initialize = function(...)
      calls = calls + 1
      return original(...)
    end
    _G.RCLootCouncil = loader.makeRCLootCouncil()
    assert_true(dibs.Capabilities.Retry("rclootcouncil", "RCLootCouncil_LOADED"))
    assert_equal("AVAILABLE", dibs.Capabilities.Get("rclootcouncil").status)
    assert_true(dibs.Capabilities.Retry("rclootcouncil", "RCLootCouncil_LOADED"))
    assert_equal(1, calls)
    assertCore(dibs)
  end)

  it("records independent RCLootCouncil and Encounter Journal failures without changing core state", function()
    local dibs = load({ rclootcouncil = loader.makeRCLootCouncil() })
    dibs.RCLootCouncil.Initialize = function() error("injected RC failure") end
    dibs.EncounterJournal.AddActionIfAvailable = function() error("injected EJ failure") end
    assert_true(dibs.Initialize()); assertCore(dibs)
    assert_equal("DEGRADED", dibs.Capabilities.Get("rclootcouncil").status)
    assert_equal("DEGRADED", dibs.Capabilities.Get("encounter_journal").status)
    local retried = dibs.Capabilities.Retry("rclootcouncil", "RCLootCouncil_LOADED")
    assert_false(retried)
    assert_equal("DEGRADED", dibs.Capabilities.Get("rclootcouncil").status)
  end)

  it("does not convert a required persistence safety state into an optional capability", function()
    local dibs = load({ savedVariables = { schemaVersion = 999 } })
    assert_true(dibs.Initialize())
    assert_true(dibs.GetPersistenceStatus().readOnly)
    assert_nil(dibs.Capabilities.Get("persistence"))
  end)
end)
