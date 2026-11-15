local loader = require("helpers.load_addon")

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
    guildMembers = { "Tester-Realm", "Player-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 } } })
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "season UI gate test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true, preDibModes = {} }))
  return dibs
end

describe("Seasonal roster feature gate", function()
  it("blocks reads and writes while preserving the exact history across re-enable", function()
    local dibs = setup()
    local result = dibs.SeasonalRoster.CreateSeason({ name = "Preserved season", startAt = dibs.GetTimestamp() + 100,
      registrationStartAt = dibs.GetTimestamp() }, "gate-create")
    assert_true(result.ok, tostring(result.code))
    local stored = dibs.GetDB().seasonalRoster
    local digest = dibs.Sync.CalculateContentHash(stored)
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = false }, nil, "disable test"))
    assert_false(dibs.FeatureRegistry.GetEffectiveState("seasonalRoster").enabled)
    local history = dibs.SeasonalRoster.GetPreservedHistory()
    assert_equal("Preserved season", history[1].name)
    assert_equal(1, #history[1].revisionHistory)
    local seasons, failure = dibs.SeasonalRoster.ListSeasons()
    assert_nil(seasons); assert_equal("MODULE_DISABLED", failure)
    local blocked = dibs.SeasonalRoster.UpdateDraft(result.value, { name = "Must not write" }, 1,
      "gate-blocked", "disabled")
    assert_false(blocked.ok); assert_equal("MODULE_DISABLED", blocked.code)
    assert_equal(digest, dibs.Sync.CalculateContentHash(dibs.GetDB().seasonalRoster))
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil, "enable test"))
    seasons = dibs.SeasonalRoster.ListSeasons()
    assert_equal("Preserved season", seasons[1].name)
    assert_equal(digest, dibs.Sync.CalculateContentHash(dibs.GetDB().seasonalRoster))
  end)

  it("keeps the disabled Officer route available for history but hides mutation controls", function()
    local dibs = setup()
    assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = false }, nil, "disable test"))
    local window = dibs.OfficerUI.CreateWindow("seasonalRoster")
    window:ActivateRoute("seasonalRoster")
    assert_equal("seasonalRoster", window.activeTab)
    assert_nil(window.seasonalRosterCreateButton)
    assert_nil(window.seasonActivateButton)
    assert_nil(window.seasonReconcileButton)
  end)
end)
