local loader = require("helpers.load_addon")

local function setup()
  return loader.load({
    wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1", "Player-2" } },
    withAce3 = true,
  })
end

local function findCategory(categories, key)
  for _, category in ipairs(categories or {}) do
    if category.key == key then return category end
  end
  return nil
end

describe("B11e request and eligibility UI", function()
  it("projects bounded officer request rows with readable status and next action", function()
    local _, dibs = setup()
    dibs.Disputes.ListForOfficer = function()
      return {
        {
          requestId = "review-1",
          player = { name = "Player-1" },
          category = "missing_debit",
          categoryLabel = "Missing debit",
          status = "Open",
          note = string.rep("x", 500),
          createdAt = 100,
          evidence = {
            { evidenceId = "evidence-1", item = "Midnight Blade", itemID = 123, source = "Dibs ledger", winner = "Player-1", response = "DIB" },
          },
          timeline = { { action = "created", actorName = "secret", reason = "private" } },
        },
      }
    end

    local rows = dibs.OfficerUI.BuildRequestView("officer", { limit = 10 })
    assert_equal(1, #rows)
    assert_equal("review-1", rows[1].requestId)
    assert_equal("Open", rows[1].status.label)
    assert_equal("Review request", rows[1].nextAction)
    assert_true(rows[1].explanation ~= "")
    assert_true(#rows[1].details.note <= 240)
    assert_nil(rows[1].details.timeline)
    assert_nil(rows[1].details.votes)
    assert_nil(rows[1].details.candidates)
  end)

  it("keeps player request projections private and explains unavailable states", function()
    local _, dibs = setup()
    dibs.Disputes.ListForPlayer = function()
      return {
        { requestId = "review-2", status = "Need information", categoryLabel = "Other", note = "Please reply", evidence = { { item = "Private item", winner = "Tester-Realm" } } },
      }
    end

    local rows = dibs.PlayerUI.BuildRequestView({ limit = 10 })
    assert_equal(1, #rows)
    assert_equal("review-2", rows[1].requestId)
    assert_equal("Need information", rows[1].status.label)
    assert_equal("Reply to Officer", rows[1].nextAction)
    assert_true(rows[1].explanation:find("information", 1, true) ~= nil)
    assert_nil(rows[1].details.winner)

    local unavailable = dibs.PlayerUI.BuildRequestView({ unavailable = "SYNC_BEHIND" })
    assert_equal(1, #unavailable)
    assert_equal("Syncing guild data", unavailable[1].status.label)
    assert_equal("Try again shortly", unavailable[1].nextAction)
  end)

  it("shows the Recommended eligibility preset before advanced details", function()
    local _, dibs = setup()
    local projection = dibs.OfficerUI.GetEligibilityProjection(dibs.GetCurrentSeasonId())
    assert_equal("recommended", projection.preset.key)
    assert_true(projection.customize.visible)
    assert_false(projection.advanced.expanded)
    assert_equal("allow", findCategory(projection.categories, "curio").state)
    assert_equal("allow", findCategory(projection.categories, "tier_set").state)
    assert_equal("allow", findCategory(projection.categories, "token").state)
    assert_equal("block", findCategory(projection.categories, "mount").state)
    assert_equal("block", findCategory(projection.categories, "pet").state)
    assert_equal("block", findCategory(projection.categories, "cosmetic").state)
    assert_equal("block", findCategory(projection.categories, "catalyst").state)
    assert_equal("CATALYST_PERSONAL", findCategory(projection.categories, "catalyst").reasonCode)
    assert_true(findCategory(projection.categories, "catalyst").customizable == false)
  end)

  it("exposes semantic reason and current state only when advanced details are expanded", function()
    local _, dibs = setup()
    local projection = dibs.OfficerUI.GetEligibilityProjection(dibs.GetCurrentSeasonId(), { expanded = true })
    local curio = findCategory(projection.categories, "curio")
    assert_true(projection.advanced.expanded)
    assert_equal("TOKEN", curio.semanticFamily)
    assert_true(curio.reason ~= "")
    assert_not_nil(curio.currentState)
    assert_true(curio.editable == true)
  end)
end)
