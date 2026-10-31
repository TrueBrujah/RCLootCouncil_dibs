local loader = require("helpers.load_addon")

-- RF-0022 regression suite.
--
-- RF-0022 - "LootPipeline : la voie de repli contourne l'interdiction
-- de Pre-Dibs publics"
-- (docs/code-audit/INDEX.md#rf-0022).
--
-- `LootPipeline.RequestDibFromContext` tentait `PreDibs.CreatePublic` et,
-- seulement si les Pre-Dibs publics etaient desactives, se repliait sur
-- `PreDibs.Create`. `PreDibs.Create` ne respecte pas la politique
-- publique : il cree une requete au statut `pending` sans controle
-- `IsPublicEnabled`.
--
-- Consequence : un joueur pouvait deposer une requete alors que les
-- Officiers avaient desactive les Pre-Dibs publics, et la requete etait
-- quand meme enregistree. Cela contredit le scenario 3 de l'User Story 1
-- de la spec 002 : "Given public Pre-Dibs are disabled, When a player
-- submits a public request, Then the request is rejected with a clear
-- reason and no state is added."
--
-- La regle de metier n'est pas modifiee : c'est le chemin de repli qui
-- est aligne sur la politique deja etablie et deja testee dans
-- `tests/unit/public_predibs_spec.lua`.

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
  return dibs
end

local function submitPublic(dibs, itemID)
  return dibs.LootPipeline.RequestDibFromContext({
    source = "player-ui",
    isTest = false,
    itemID = itemID,
    itemName = "Item " .. tostring(itemID),
    owner = "Tester-Realm",
    seasonId = dibs.GetCurrentSeasonId(),
  })
end

describe("RF-0022 public pre-dib policy is not bypassed", function()
  it("rejects the request and adds no state when public pre-dibs are disabled", function()
    local dibs = setup()
    dibs.GetDB().settings.allowPublicPreDibs = false
    assert_false(dibs.PreDibs.IsPublicEnabled())

    local request, reason = submitPublic(dibs, 31001)

    assert_nil(request, "a request was created although public pre-dibs are disabled")
    assert_equal("PUBLIC_PRE_DIBS_DISABLED", reason)
    assert_equal(0, #dibs.PreDibs.GetRequestsForItem(31001),
      "a request was stored although public pre-dibs are disabled")
  end)

  it("adds no pending request state when public pre-dibs are disabled", function()
    local dibs = setup()
    dibs.GetDB().settings.allowPublicPreDibs = false

    submitPublic(dibs, 31002)

    local stored = dibs.PreDibs.GetHistory() or {}
    assert_equal(0, #stored, "a request was added to the Pre-Dib history")
  end)

  it("still creates a confirmed request when public pre-dibs are enabled", function()
    local dibs = setup()
    assert_true(dibs.PreDibs.IsPublicEnabled())

    local request, reason = submitPublic(dibs, 31003)

    assert_not_nil(request, "the request was refused although public pre-dibs are enabled")
    assert_equal("confirmed", request.status)
    assert_equal(31003, request.itemID)
    assert_nil(reason)
  end)

  it("does not change the developer test path", function()
    local dibs = setup()
    dibs.GetDB().settings.allowPublicPreDibs = false
    dibs.DeveloperMode.SetEnabled(true)

    local request, reason = dibs.LootPipeline.RequestDibFromContext({
      source = "DEV", isTest = true, itemID = 31004,
      itemName = "Item 31004", owner = "Tester-Realm",
      seasonId = dibs.GetCurrentSeasonId(),
    })

    assert_not_nil(request, "the developer test request was refused")
    assert_true(request.isTest == true)
    assert_nil(reason)
  end)
end)
