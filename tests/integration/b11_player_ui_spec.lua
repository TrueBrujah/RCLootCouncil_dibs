local loader = require("helpers.load_addon")

local function setup(options)
  options = options or {}
  options.withAce3 = true
  return loader.load(options)
end

local function containsForbiddenValue(value, forbidden)
  if type(value) == "string" then
    for _, text in ipairs(forbidden) do
      if value:find(text, 1, true) then return true end
    end
    return false
  end
  if type(value) ~= "table" then return false end
  for key, item in pairs(value) do
    if containsForbiddenValue(key, forbidden) or containsForbiddenValue(item, forbidden) then return true end
  end
  return false
end

describe("B11c Player UI", function()
  it("exposes only the three player navigation views", function()
    local _, dibs = setup()
    local navigation = dibs.PlayerUI.GetNavigation()
    assert_equal(3, #navigation)
    assert_equal("My Dibs", navigation[1].text)
    assert_equal("Requests", navigation[2].text)
    assert_equal("History", navigation[3].text)
    assert_equal("my-dibs", navigation[1].value)
    assert_equal("requests", navigation[2].value)
    assert_equal("history", navigation[3].value)
  end)

  it("projects authoritative personal data without administrative or technical details", function()
    local _, dibs = setup()
    dibs.PlayerUI.GetSummary = function()
      return {
        player = "Tester-Realm",
        balance = 17,
        season = { id = 1, name = "Midnight" },
        activePreDibs = {
          { requestId = "request-1", itemID = 123, itemName = "Midnight Blade", status = "pending", createdAt = 100 },
        },
        acquisitions = {},
      }
    end
    dibs.Readiness.Evaluate = function() return {
      status = "Ready", reasonCodes = {}, integrationStatus = "Ready", liveConsumptionAllowed = true,
    } end
    dibs.Ledger.GetHistory = function()
      return {
        {
          createdAt = 100, itemName = "Midnight Blade", type = "AWARD", amount = -3,
          transactionId = "technical-id", epoch = 4, contentHash = "technical-hash",
          rootHash = "technical-root", evidenceId = "technical-evidence",
        },
      }
    end

    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("Tester-Realm", view.player)
    assert_equal(17, view.balance)
    assert_equal("Midnight", view.seasonName)
    assert_equal(1, #view.activePreDibs)
    assert_equal("Ready", view.status.label)
    assert_nil(view.empty.activePreDibs)
    assert_false(containsForbiddenValue(view, { "RCLootCouncil - Dibs options", "Officer", "GM", "Developer", "hash", "epoch", "root", "evidence" }))
  end)

  it("uses intentional empty states and player-safe readiness explanations", function()
    local _, dibs = setup()
    dibs.PlayerUI.GetSummary = function()
      return { player = "Tester-Realm", balance = 0, season = nil, activePreDibs = {}, acquisitions = {} }
    end
    dibs.Ledger.GetHistory = function() return {} end
    dibs.Readiness.Evaluate = function() return {
      status = "Blocked", reasonCodes = { COORDINATOR_UNAVAILABLE = true },
    } end
    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("No active Pre-Dibs.", view.empty.activePreDibs)
    assert_equal("No history yet.", view.empty.history)
    assert_equal("Dibs temporarily unavailable", view.status.label)
    assert_equal("Guild Dibs is unavailable right now. Try again later or contact an Officer.", view.status.explanation)

    local status = dibs.PlayerUI.GetStatusPresentation({ status = "Unavailable", reasonCodes = { SYNC_BEHIND = true } })
    assert_equal("Syncing guild data", status.label)
    assert_equal("Your guild Dibs data is catching up. You can try again shortly.", status.explanation)
    status = dibs.PlayerUI.GetStatusPresentation({ status = "Unavailable", reasonCodes = { RECOVERY_PENDING = true } })
    assert_equal("Guild Dibs recovery in progress", status.label)
  end)

  it("keeps sandbox role simulation out of the normal Player surface", function()
    local _, dibs = setup({ wow = { guildLeader = true } })
    dibs.DeveloperMode.SetEnabled(true)
    local before = loader.snapshotProductionState(dibs)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true, role = "guild_master" }))
    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("My Dibs", view.navigation[1].text)
    assert_false(containsForbiddenValue(view, { "Officer dashboard", "review administration", "reconciliation", "Developer Mode" }))
    assert_true(loader.productionStateEquals(dibs, before))
    assert_true(dibs.DeveloperSandbox.ExitSandbox())
  end)
end)