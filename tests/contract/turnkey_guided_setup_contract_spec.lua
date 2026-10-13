local loader = require("helpers.load_addon")

local function load(player, guildLeader)
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = player or "Tester-Realm",
    guildLeader = guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Member-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 7 },
  } }))
end

local function byId(rows, id)
  for _, row in ipairs(rows or {}) do if row.id == id then return row end end
end

describe("Turnkey Guided Setup contract", function()
  it("exposes three documented profiles as defensive copies", function()
    local dibs = load()
    local profiles = dibs.Wizard.GetProfiles()
    assert_equal(3, #profiles)
    assert_equal("progression", profiles[1].id)
    assert_true(profiles[1].summary:find("progression", 1, true) ~= nil)
    assert_true(#profiles[1].benefits > 0)
    assert_true(#profiles[1].preserves > 0)
    profiles[1].label = "mutated"
    assert_true(dibs.Wizard.GetProfiles()[1].label ~= "mutated")
  end)

  it("rejects unknown profiles and keeps custom mode mutation-free", function()
    local dibs = load()
    local preview, reason = dibs.Wizard.PreviewProfile("unknown")
    assert_nil(preview)
    assert_equal("UNKNOWN_SETUP_PROFILE", reason)
    local before = loader.snapshotProductionState(dibs)
    local result = dibs.Wizard.ApplyProfile("custom")
    assert_true(result.ok)
    assert_equal("ADVANCED_ONLY", result.actions[1].outcome)
    assert_true(loader.productionStateEquals(dibs, before))
  end)

  it("previews preserved state and applies a recommended profile idempotently", function()
    local dibs = load()
    local preview = dibs.Wizard.PreviewProfile("progression")
    assert_true(preview.canApply)
    assert_true(#preview.preserved >= 3)
    assert_equal("APPLY", byId(preview.actions, "initialize").disposition)
    local first = dibs.Wizard.ApplyProfile("progression")
    assert_true(first.ok, tostring(first.reasonCode))
    local governanceRevision = dibs.Governance.GetState().revision
    local second = dibs.Wizard.ApplyProfile("progression")
    assert_true(second.ok, tostring(second.reasonCode))
    assert_equal(governanceRevision, dibs.Governance.GetState().revision)
    assert_equal("ALREADY_READY", byId(second.actions, "initialize").outcome)
    assert_equal("ALREADY_READY", byId(second.actions, "lootRules").outcome)
  end)

  it("lets a verified guild officer apply the Dibs loot policy preset", function()
    local dibs = load("Officer-Realm", false)
    local result = dibs.Wizard.ApplyProfile("progression", "Officer-Realm")
    assert_equal("APPLIED", byId(result.actions, "lootRules").outcome)
    assert_true(dibs.GetDB().settings.dibAllowedTypes.TOKEN)
    assert_true(dibs.GetDB().settings.dibAllowedTypes.TOKEN_SET)
    assert_false(dibs.Permissions.IsGM())
    assert_true(dibs.Permissions.IsOfficer())
  end)

  it("returns explicit partial failure details", function()
    local dibs = load()
    dibs.RCOptions.ApplyInstallationPreset = function() return false end
    local result = dibs.Wizard.ApplyProfile("progression")
    assert_false(result.ok)
    assert_equal("SETUP_PROFILE_PARTIAL_FAILURE", result.reasonCode)
    assert_equal("FAILED", byId(result.actions, "lootRules").outcome)
    assert_equal("LOOT_RULE_PRESET_FAILED", byId(result.actions, "lootRules").reasonCode)
    assert_equal("lootTypes", byId(result.actions, "lootRules").route)
  end)

  it("makes behind synchronization the first blocker before ledger activation", function()
    local dibs = load()
    dibs.Installation.GetStatus = function()
      return {
        state = "READY_TO_INITIALIZE",
        governance = { ready = true },
        legacy = {}, baseline = { ready = true }, coordinator = { ready = false },
        compatibility = { ready = true }, sync = { ready = false, behind = true },
        protocol = { active = false }, actor = { isGM = true, isOfficer = true },
      }
    end
    dibs.Sync.GetStatus = function() return { state = "SYNC_BEHIND", syncBehind = true } end
    dibs.Sync.IsSyncBehind = function() return true end
    local status = dibs.Wizard.GetTurnkeyStatus()
    assert_equal("BLOCKING", byId(status.verification, "sync").severity)
    assert_equal("sync", status.primaryIssueId)
    assert_equal("sync", byId(status.verification, "sync").route)
    assert_equal("WARNING", byId(status.verification, "ledger").severity)
    assert_equal("sync", byId(status.verification, "ledger").route)
  end)

  it("classifies true blockers separately from warnings and provides routes", function()
    local dibs = load()
    assert_true(dibs.Installation.Initialize(nil).ok)
    local status = dibs.Wizard.GetTurnkeyStatus()
    assert_equal(3, #status.stages)
    local rankRules = byId(status.verification, "rankRules")
    assert_equal("BLOCKING", rankRules.severity)
    assert_equal("ranks", rankRules.route)
    assert_not_nil(rankRules.impact)
    assert_not_nil(rankRules.nextAction)
    assert_equal("OPTIONAL", byId(status.verification, "rclootcouncil").severity)
    assert_true(status.primaryIssueId ~= nil)
  end)

  it("persists only turnkey navigation preferences in local state", function()
    local dibs = load()
    assert_equal("choose", dibs.Wizard.GetCurrentStage())
    assert_equal("verify", dibs.Wizard.SetCurrentStage("verify"))
    assert_equal("broad", dibs.Wizard.SetSelectedProfileId("broad"))
    assert_equal("verify", _G.RCLootCouncil_dibsLocalDB.settings.turnkeyWizardStage)
    assert_equal("broad", _G.RCLootCouncil_dibsLocalDB.settings.turnkeyWizardProfileId)
    local guildDb = _G.RCLootCouncil_dibsDB.guilds and _G.RCLootCouncil_dibsDB.guilds["realm:testguild"]
    assert_true(guildDb == nil or guildDb.settings == nil or guildDb.settings.turnkeyWizardStage == nil)
  end)
end)
