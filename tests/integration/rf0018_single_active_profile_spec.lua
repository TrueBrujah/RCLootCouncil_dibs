local loader = require("helpers.load_addon")

-- RF-0018 regression suite.
--
-- RF-0018 - "Profiles : plusieurs profils restent marques actifs et
-- GetActive renvoie un profil arbitraire"
-- (docs/code-audit/INDEX.md#rf-0018, anciennement RF-0008).
--
-- `Profiles.Activate` marked the activated profile active without clearing
-- the flag of the previously active one, so several profiles of a scope
-- stayed active. `Profiles.GetActive` then returned the first entry found by
-- a `pairs()` iteration, so the profile the officer had just activated could
-- be ignored.

describe("RF-0018 exactly one profile is active per scope", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    return dibs
  end

  it("keeps a single active profile after several activations", function()
    local dibs = setup()
    assert(dibs.Profiles.Create("A", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Create("B", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Activate("A", "guild", "Tester-Realm", true))
    assert(dibs.Profiles.Activate("B", "guild", "Tester-Realm", true))

    local active = 0
    for _, profile in ipairs(dibs.Profiles.List("guild", "Tester-Realm")) do
      if profile.active then active = active + 1 end
    end
    assert_equal(1, active, "several profiles stayed marked active")
  end)

  it("returns the profile that was activated last", function()
    local dibs = setup()
    assert(dibs.Profiles.Create("A", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Create("B", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Activate("A", "guild", "Tester-Realm", true))
    assert(dibs.Profiles.Activate("B", "guild", "Tester-Realm", true))

    local active = dibs.Profiles.GetActive("guild")
    assert_not_nil(active, "no active profile was reported")
    assert_equal("B", active.name, "the last activated profile is not the active one")
  end)

  it("keeps the guild and local scopes independent", function()
    local dibs = setup()
    assert(dibs.Profiles.Create("G1", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Create("G2", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Activate("G1", "guild", "Tester-Realm", true))
    assert(dibs.Profiles.Activate("G2", "guild", "Tester-Realm", true))
    assert(dibs.Profiles.Create("L1", "local", {}, "Tester-Realm"))
    assert(dibs.Profiles.Activate("L1", "local", "Tester-Realm", true))

    assert_equal("G2", dibs.Profiles.GetActive("guild").name,
      "the local activation changed the guild active profile")
    assert_equal("L1", dibs.Profiles.GetActive("local").name,
      "the local scope has no active profile")
  end)

  it("clears the active profile when it is deleted", function()
    local dibs = setup()
    assert(dibs.Profiles.Create("A", "guild", {}, "Tester-Realm"))
    assert(dibs.Profiles.Activate("A", "guild", "Tester-Realm", true))
    assert(dibs.Profiles.Delete("A", "guild", "Tester-Realm"))
    assert_nil(dibs.Profiles.GetActive("guild"),
      "a deleted profile is still reported as active")
  end)

  it("preserves the active profile when policy confirmation is missing", function()
    local dibs = setup()
    assert(dibs.Profiles.Create("Current", "guild", { authoritativePolicy = {} }, "Tester-Realm"))
    assert(dibs.Profiles.Create("Next", "guild", { authoritativePolicy = { defaultAllocation = 17 } }, "Tester-Realm"))
    assert(dibs.Profiles.Activate("Current", "guild", "Tester-Realm", true))

    local activated, reason = dibs.Profiles.Activate("Next", "guild", "Tester-Realm", false)
    assert_nil(activated)
    assert_equal("POLICY_CONFIRM_REQUIRED", reason)
    assert_equal("Current", dibs.Profiles.GetActive("guild").name)
    assert_true(dibs.Profiles.Get("Current", "guild").active)
    assert_false(dibs.Profiles.Get("Next", "guild").active)
  end)

  it("preserves the active profile when adopted policy rejects activation", function()
    local dibs = setup()
    assert(dibs.Profiles.Create("Current", "guild", { authoritativePolicy = {} }, "Tester-Realm"))
    assert(dibs.Profiles.Create("Next", "guild", { authoritativePolicy = { defaultAllocation = 17 } }, "Tester-Realm"))
    assert(dibs.Profiles.Activate("Current", "guild", "Tester-Realm", true))
    dibs.OperationalPolicy.IsAdopted = function() return true end

    local activated, reason = dibs.Profiles.Activate("Next", "guild", "Tester-Realm", true)
    assert_nil(activated)
    assert_equal("PROFILE_SHARED_POLICY_UNSUPPORTED", reason)
    assert_equal("Current", dibs.Profiles.GetActive("guild").name)
    assert_true(dibs.Profiles.Get("Current", "guild").active)
    assert_false(dibs.Profiles.Get("Next", "guild").active)
  end)

  it("keeps local active selection isolated between character owners", function()
    local dibs = setup()
    local owner = "First"
    dibs.GetPlayerName = function() return owner end
    assert(dibs.Profiles.Create("Shared name", "local"))
    assert(dibs.Profiles.Create("First choice", "local"))
    assert(dibs.Profiles.Activate("First choice", "local"))

    owner = "Second"
    assert(dibs.Profiles.Create("Shared name", "local"))
    assert_nil(dibs.Profiles.GetActive("local"))
    assert(dibs.Profiles.Activate("Shared name", "local"))
    assert_equal("Shared name", dibs.Profiles.GetActive("local").name)

    owner = "First"
    assert_equal("First choice", dibs.Profiles.GetActive("local").name)
    assert_false(dibs.Profiles.Get("Shared name", "local").active)
    assert_true(dibs.Profiles.Delete("Shared name", "local"))
    owner = "Second"
    assert_equal("Shared name", dibs.Profiles.GetActive("local").name)
  end)

  it("reads legacy local selection without an explicit profile active flag", function()
    local dibs = setup()
    local profile = assert(dibs.Profiles.Create("Legacy", "local"))
    local profiles = dibs.GetDB().profiles
    profiles["local"][profile.ownerScope].Legacy.active = nil
    profiles.active["local:Legacy"] = true
    assert_equal("Legacy", dibs.Profiles.GetActive("local").name)
  end)
end)
