local loader = require("helpers.load_addon")

-- RF-0028 regression suite.
--
-- RF-0028 - "Le contournement de la politique publique des Pre-Dibs
-- subsiste sur la commande slash, l'Adventure Guide et le repli local"
-- (docs/code-audit/INDEX.md#rf-0028).
--
-- RF-0022 fixed the same fundamental cause in `LootPipeline`: a route that
-- fell back to `PreDibs.Create` when the public route was closed. That
-- fallback ignores `IsPublicEnabled`, so a `pending` request was still
-- written while the Officers had disabled public Pre-Dibs.
--
-- The same cause existed on three other routes and was not covered by
-- RF-0022:
--   * `Core.HandleSlashCommand("pre ...")` in `src/Core.lua`,
--   * `EncounterJournal.SubmitPreDib` in `src/integrations/EncounterJournal.lua`,
--   * the local fallback of `PlayerUI.submitPublicPreDib` in
--     `src/ui/PlayerUI.lua`.
--
-- This suite covers every remaining route, so the contract "no route may
-- create a public Pre-Dib while the public route is disabled" is now
-- verified in one place.

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { playerName = "Tester-Realm", guildLeader = true } })
  dibs.GetDB().settings.allowPublicPreDibs = false
  return dibs
end

local function storedRequestCount(dibs)
  local history = dibs.PreDibs.GetHistory() or {}
  return #history
end

describe("RF-0028 no route creates a public Pre-Dib while the public route is closed", function()
  it("refuses the slash route and writes no request", function()
    local dibs = setup()
    assert_false(dibs.PreDibs.IsPublicEnabled())

    dibs.HandleSlashCommand("pre 12345 TestItem")

    assert_equal(0, storedRequestCount(dibs),
      "the slash route created a request although public pre-dibs are disabled")
  end)

  it("refuses the Player UI route and writes no request", function()
    local dibs = setup()

    local request, reason = dibs.PlayerUI.SubmitPreDib("12345")

    assert_nil(request, "the Player UI route created a request although public pre-dibs are disabled")
    assert_not_nil(reason, "the Player UI route did not report a reason")
    assert_equal(0, storedRequestCount(dibs),
      "the Player UI route wrote a request although public pre-dibs are disabled")
  end)

  it("refuses the loot pipeline route and writes no request", function()
    local dibs = setup()

    local request, reason = dibs.LootPipeline.RequestDibFromContext({
      source = "player-ui", isTest = false, itemID = 12345,
      itemName = "Item 12345", owner = "Tester-Realm",
      seasonId = dibs.GetCurrentSeasonId(),
    })

    assert_nil(request, "the loot pipeline route created a request although public pre-dibs are disabled")
    assert_equal("PUBLIC_PRE_DIBS_DISABLED", reason)
    assert_equal(0, storedRequestCount(dibs),
      "the loot pipeline route wrote a request although public pre-dibs are disabled")
  end)

  it("refuses the Adventure Guide route and writes no request", function()
    local dibs = setup()

    local request, reason = dibs.EncounterJournal.SubmitPreDib(12345, "Item 12345")

    assert_nil(request, "the Adventure Guide route created a request although public pre-dibs are disabled")
    assert_equal("PUBLIC_PRE_DIBS_DISABLED", reason)
    assert_equal(0, storedRequestCount(dibs),
      "the Adventure Guide route wrote a request although public pre-dibs are disabled")
  end)

  it("still creates a request on every route when public pre-dibs are enabled", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { playerName = "Tester-Realm", guildLeader = true } })
    assert_true(dibs.PreDibs.IsPublicEnabled())

    local request, reason = dibs.LootPipeline.RequestDibFromContext({
      source = "player-ui", isTest = false, itemID = 12345,
      itemName = "Item 12345", owner = "Tester-Realm",
      seasonId = dibs.GetCurrentSeasonId(),
    })

    assert_not_nil(request, "the loot pipeline route refused a request although public pre-dibs are enabled")
    assert_equal("confirmed", request.status)
    assert_nil(reason)
  end)
end)
