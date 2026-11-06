local loader = require("helpers.load_addon")

-- RF-0015 regression suite.
--
-- RF-0015 - "Wizard : une verification obligatoire est masquee par une
-- verification facultative" (docs/code-audit/INDEX.md#rf-0015).
--
-- `Wizard.GetTurnkeyStatus` selects the first non-ready finding of the
-- readiness report to explain the step. The SetupAssistant report distinguishes
-- required findings (which block) from optional ones. Selecting the first
-- non-ready finding let an optional finding hide a required blocking one, so
-- the officer was directed to fix an optional item while the real blocker went
-- unreported.
--
-- The suite drives the real turnkey projection.

describe("RF-0015 the readiness step reports the blocking finding first", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    return dibs
  end

  local function readinessStep(dibs)
    local turnkey = dibs.Wizard.GetTurnkeyStatus(nil)
    for _, result in ipairs(turnkey.verification or {}) do
      if result.id == "readiness" then return result end
    end
    return nil
  end

  it("reports a required blocking finding instead of an earlier optional one", function()
    local dibs = setup()
    dibs.SetupAssistant.Evaluate = function()
      return { status = "NEEDS_ATTENTION", checks = {
        { id = "optional_one", state = "degraded", required = false,
          impact = "Optional impact", remediation = "Optional fix" },
        { id = "required_one", state = "blocked", required = true,
          impact = "Required impact", reasonCode = "REQUIRED_CODE", remediation = "Required fix" },
      }, blockingCount = 1 }
    end
    local step = assert(readinessStep(dibs), "the readiness step is missing")
    assert_equal("Required impact", step.explanation,
      "an optional finding hid the required blocking finding")
    assert_equal("Required fix", step.nextAction,
      "the next action points at an optional finding instead of the blocker")
  end)

  it("still reports an optional finding when it is the only one", function()
    local dibs = setup()
    dibs.SetupAssistant.Evaluate = function()
      return { status = "NEEDS_ATTENTION", checks = {
        { id = "optional_one", state = "degraded", required = false,
          impact = "Optional impact", remediation = "Optional fix" },
      }, blockingCount = 0 }
    end
    local step = assert(readinessStep(dibs), "the readiness step is missing")
    assert_equal("Optional impact", step.explanation,
      "the only available finding is no longer reported")
    assert_equal("Optional fix", step.nextAction,
      "the next action is no longer reported for the only finding")
  end)

  it("keeps the overall state blocked while a required finding is open", function()
    local dibs = setup()
    dibs.SetupAssistant.Evaluate = function()
      return { status = "NEEDS_ATTENTION", checks = {
        { id = "optional_one", state = "degraded", required = false, impact = "Optional impact" },
        { id = "required_one", state = "blocked", required = true, impact = "Required impact" },
      }, blockingCount = 1 }
    end
    local turnkey = dibs.Wizard.GetTurnkeyStatus(nil)
    assert_equal("BLOCKED", turnkey.overallState,
      "a required blocking finding did not keep the turnkey state blocked")
  end)

  it("ignores findings that are already ready or skipped", function()
    local dibs = setup()
    dibs.SetupAssistant.Evaluate = function()
      return { status = "NEEDS_ATTENTION", checks = {
        { id = "already_ready", state = "ready", required = true, impact = "Ready impact" },
        { id = "skipped_one", state = "skipped", required = true, impact = "Skipped impact" },
        { id = "required_one", state = "blocked", required = true, impact = "Required impact" },
      }, blockingCount = 1 }
    end
    local step = assert(readinessStep(dibs), "the readiness step is missing")
    assert_equal("Required impact", step.explanation,
      "a ready or skipped finding was reported instead of the blocker")
  end)
end)
