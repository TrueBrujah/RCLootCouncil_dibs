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
end)
