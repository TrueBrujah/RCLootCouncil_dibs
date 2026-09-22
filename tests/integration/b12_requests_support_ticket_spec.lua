local loader = require("helpers.load_addon")
local fixtures = require("helpers.b12_workflow_fixtures")

describe("B12 request support-ticket projections", function()
  local function setup(requests)
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1", "Player-2" } },
      withAce3 = true,
    })
    dibs.Disputes.ListForOfficer = function()
      return requests
    end
    return dibs
  end

  it("projects the submitter, item, category, existing status, next action, and bounded note", function()
    local dibs = setup({
      fixtures.request({
        requestId = "b12-open",
        player = { name = "Player-1" },
        category = "wrong_item_player",
        categoryLabel = "Wrong item or player",
        status = "Open",
        note = string.rep("n", 500),
      }),
      fixtures.request({ requestId = "b12-review", player = { name = "Player-2" }, status = "Under review" }),
      fixtures.request({ requestId = "b12-question", player = { name = "Player-1" }, status = "Need information" }),
      fixtures.request({ requestId = "b12-resolved", player = { name = "Player-2" }, status = "Resolved" }),
      fixtures.request({ requestId = "b12-rejected", player = { name = "Player-1" }, status = "Rejected" }),
    })

    local rows = dibs.OfficerUI.BuildRequestView("officer", { limit = 10 })
    assert_equal(5, #rows)
    assert_equal("Player-1", rows[1].details.player)
    assert_equal("Wrong player/item", rows[1].details.category)
    assert_equal("Midnight Blade", rows[1].details.item)
    assert_equal(240, #rows[1].details.note)
    assert_equal("Open", rows[1].status.label)
    assert_equal("Review request", rows[1].nextAction)
    assert_equal("Continue review", rows[2].nextAction)
    assert_equal("Reply to Officer", rows[3].nextAction)
    assert_equal("View resolution", rows[4].nextAction)
    assert_equal("Rejected", rows[5].status.label)
  end)

  it("keeps detail evidence bounded and marks incomplete evidence without leaking private fields", function()
    local complete = fixtures.request({
      requestId = "b12-detail-complete",
      player = { name = "Player-1" },
      category = "missing_debit",
      note = string.rep("detail ", 80),
    })
    local incomplete = fixtures.request({
      requestId = "b12-detail-incomplete",
      player = { name = "Player-2" },
      categoryLabel = "History problem",
      evidence = { { item = "Unknown item", unavailableFields = { "winner", "reference" } } },
      timeline = { { actorName = "Private officer", reason = "private audit reason" } },
      votes = { { player = "Private player" } },
    })
    local dibs = setup({ complete, incomplete })

    local detail = dibs.OfficerUI.BuildRequestDetailView(complete)
    assert_equal("b12-detail-complete", detail.requestId)
    assert_equal("Player-1", detail.summary.player)
    assert_equal("Missing Dib", detail.summary.issue)
    assert_equal("Evidence available", detail.summary.evidence)
    assert_equal(240, #detail.summary.note)
    assert_nil(detail.timeline)
    assert_nil(detail.votes)

    local unavailable = dibs.OfficerUI.BuildRequestDetailView(incomplete)
    assert_equal("Evidence incomplete", unavailable.summary.evidence)
    assert_equal("Unknown item", unavailable.summary.item)
    assert_nil(unavailable.timeline)
    assert_nil(unavailable.votes)
  end)

  it("represents unavailable and privacy-filtered requests without inventing evidence", function()
    local variants = fixtures.requestVariants()
    local dibs = setup({ variants.unavailable, variants.privacyFiltered })

    local rows = dibs.OfficerUI.BuildRequestView("officer", { limit = 10 })
    assert_equal(2, #rows)
    assert_equal("Unavailable", rows[1].status.label)
    assert_equal("Contact an Officer", rows[1].nextAction)
    assert_equal("", rows[2].details.player)
    assert_equal("", rows[2].details.item)
    assert_equal("Evidence incomplete", rows[2].details.evidence)
  end)

  it("maps supported category aliases to presentation labels without changing request semantics", function()
    local categories = {
      { key = "missing_debit", label = "Missing Dib" },
      { key = "wrong_debit", label = "Incorrect removal" },
      { key = "wrong_item_player", label = "Wrong player/item" },
      { key = "wrong_recipient", label = "Wrong recipient" },
      { key = "award_recipient_mismatch", label = "Award-recipient mismatch" },
      { key = "predib_problem", label = "Pre-Dib problem" },
      { key = "refund_request", label = "Refund request" },
      { key = "history_problem", label = "History problem" },
      { key = "general_dibs_question", label = "General Dibs question" },
      { key = "other", label = "Other" },
      { key = "new_category", label = "Other" },
    }
    local requests = {}
    for index, category in ipairs(categories) do
      requests[index] = fixtures.request({
        requestId = "b12-category-" .. tostring(index),
        category = category.key,
        categoryLabel = nil,
      })
    end
    local dibs = setup(requests)
    local rows = dibs.OfficerUI.BuildRequestView("officer", { limit = 20 })
    assert_equal(#categories, #rows)
    for index, category in ipairs(categories) do
      assert_equal(category.label, rows[index].details.category)
    end
  end)
end)
