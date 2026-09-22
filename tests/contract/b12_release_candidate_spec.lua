local loader = require("helpers.load_addon")

describe("B12 release candidate record", function()
  it("keeps version, evidence, limitations, and readiness gates aligned", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local candidate = {
      version = dibs.VERSION,
      automatedEvidence = { focused = "55 passed", full = "541 passed" },
      retailEvidence = { status = "PENDING_MANUAL_RETAIL_VALIDATION" },
      twoClientEvidence = { required = false, status = "not-required" },
      knownLimitations = { "Retail validation pending", "SANDBOX_STORE_TOO_LARGE" },
      changelogEntry = true,
      readinessGates = { diagnostics = true, diffCheck = true, retail = false },
    }

    assert_true(candidate.version ~= nil and candidate.version ~= "")
    assert_equal(candidate.version, dibs.VERSION)
    assert_equal("55 passed", candidate.automatedEvidence.focused)
    assert_equal("541 passed", candidate.automatedEvidence.full)
    assert_equal("PENDING_MANUAL_RETAIL_VALIDATION", candidate.retailEvidence.status)
    assert_false(candidate.twoClientEvidence.required)
    assert_equal("not-required", candidate.twoClientEvidence.status)
    assert_true(candidate.knownLimitations[1] ~= nil)
    assert_true(candidate.knownLimitations[2] ~= nil)
    assert_true(candidate.changelogEntry)
    assert_true(candidate.readinessGates.diagnostics)
    assert_true(candidate.readinessGates.diffCheck)
    assert_false(candidate.readinessGates.retail)
  end)
end)
