local loader = require("helpers.load_addon")

local function officerSetup()
  return loader.load({
    wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1" } },
    withAce3 = true,
  })
end

describe("B12b targeted page cleanup", function()
  it("renders explicit empty states and denies officer data to players", function()
    local _, officer = officerSetup()
    local empty = officer.OfficerUI.GetPagedView("predibs", officer.GetCurrentSeasonId(), 1, 8)
    assert_equal("Pre-Dibs", empty.title)
    assert_equal(1, #empty.lines)
    assert_equal("No pre-Dibs for this season.", empty.lines[1])

    local _, player = loader.load({ wow = { guildLeader = false, guildRank = 0 } })
    local denied = player.OfficerUI.GetPagedView("players", player.GetCurrentSeasonId(), 1, 8)
    assert_equal("Players", denied.title)
    assert_equal("Officer access required.", denied.lines[1])
  end)

  it("keeps page results bounded and preserves readable status semantics", function()
    local _, dibs = officerSetup()
    local originalLedger = dibs.OfficerUI.BuildLedgerDetails
    local originalPreDibs = dibs.OfficerUI.BuildPreDibDetails
    local originalVault = dibs.OfficerUI.BuildVaultAcquisitionReview
    dibs.OfficerUI.BuildLedgerDetails = function()
      return { actions = { "Player-1 / Item 1", "Player-1 / Item 2", "Player-1 / Item 3" }, players = {}, hiddenTransactionCount = 0 }
    end
    dibs.OfficerUI.BuildPreDibDetails = function()
      return { requests = {}, hiddenRequestCount = 0 }
    end
    dibs.OfficerUI.BuildVaultAcquisitionReview = function()
      return { rows = {}, hiddenCount = 0 }
    end

    local page = dibs.OfficerUI.GetPagedView("actions", dibs.GetCurrentSeasonId(), 2, 1, "item")
    assert_equal("Actions", page.title)
    assert_equal(1, #page.lines)
    assert_equal("Player-1 / Item 2", page.lines[1])
    assert_equal(3, page.totalCount)
    assert_equal(3, page.totalPages)

    local ready = dibs.Midnight.GetStatusPresentation("ready")
    local warning = dibs.Midnight.GetStatePresentation("SYNC_BEHIND")
    assert_equal("Ready", ready.label)
    assert_equal("warning", warning.tone)
    assert_true(warning.explanation ~= "")

    dibs.OfficerUI.BuildLedgerDetails = originalLedger
    dibs.OfficerUI.BuildPreDibDetails = originalPreDibs
    dibs.OfficerUI.BuildVaultAcquisitionReview = originalVault
  end)

  it("keeps request rows information-first without a generic action column", function()
    local _, dibs = officerSetup()
    local original = dibs.Disputes.ListForOfficer
    dibs.Disputes.ListForOfficer = function()
      return {
        {
          requestId = "b12-request-1",
          playerName = "Player-1",
          itemName = "Midnight Blade",
          status = "Open",
          note = "Missing Dibs after the award.",
        },
      }
    end

    local rows = dibs.OfficerUI.BuildRequestView("officer", { limit = 10 })
    assert_equal(1, #rows)
    assert_equal("b12-request-1", rows[1].requestId)
    assert_equal("Open", rows[1].status.label)
    assert_equal("Review request", rows[1].nextAction)
    assert_nil(rows[1].action)
    assert_true(rows[1].explanation ~= "")

    dibs.Disputes.ListForOfficer = original
  end)
end)
