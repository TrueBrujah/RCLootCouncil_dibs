local uiFixtures = require("helpers.b12_ui_fixtures")
local workflowFixtures = require("helpers.b12_workflow_fixtures")

describe("B12 UI projection records", function()
  it("keeps request and historical projections bounded and privacy-aware", function()
    local requests = workflowFixtures.requestVariants()
    for _, request in pairs(requests) do
      assert_not_nil(request.requestId)
      assert_true(#tostring(request.note or "") <= 240)
      if request.privacyFiltered then assert_nil(request.evidence) end
    end

    local candidates = workflowFixtures.historicalVariants()
    for _, candidate in pairs(candidates) do
      assert_not_nil(candidate.candidateId)
      assert_not_nil(candidate.classification)
      assert_true(candidate.privacy ~= nil)
      if candidate.privacyFiltered then assert_nil(candidate.evidence) end
    end
  end)

  it("models context-menu and page lifecycle state without authority fields", function()
    local shell = uiFixtures.officerShell({ selectedRoute = "requests", mountedPage = "requests" })
    local page = uiFixtures.pageRoot("requests")
    local menu = uiFixtures.contextMenu({ { label = "Open", enabled = true, dangerous = false } })
    local combat = uiFixtures.combatState(true)

    assert_equal("officer", shell.role)
    assert_equal("requests", shell.selectedRoute)
    assert_true(shell.footer.stable)
    assert_equal("requests", page.route)
    assert_true(menu.open)
    assert_true(menu.closedOnRouteChange)
    assert_true(combat.refreshQueued)
    assert_false(combat.dangerousActionAllowed)
    assert_nil(shell.ledger)
    assert_nil(shell.authority)
  end)

  it("keeps release-candidate and sandbox-limitation records as evidence only", function()
    local candidate = {
      version = "0.6.3-dev",
      automatedEvidence = { focused = "19 passed", full = "505 passed" },
      diagnostics = { errors = 0, diffCheck = "clean" },
      retailEvidence = { status = "required" },
      twoClientEvidence = { required = false, status = "not-required" },
      knownLimitations = { "Retail validation pending" },
      changelogEntry = "CHANGELOG.md",
      ready = false,
    }
    local limitation = {
      id = "SANDBOX_STORE_TOO_LARGE",
      scope = "developer-only",
      productionIsolated = true,
      normalUsersAffected = false,
      developerModeDefaultOff = true,
      validated = false,
    }

    assert_equal("0.6.3-dev", candidate.version)
    assert_equal("required", candidate.retailEvidence.status)
    assert_false(candidate.ready)
    assert_true(limitation.productionIsolated)
    assert_false(limitation.normalUsersAffected)
    assert_true(limitation.developerModeDefaultOff)
    assert_false(limitation.validated)
  end)
end)
