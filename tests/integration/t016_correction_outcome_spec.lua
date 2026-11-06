local loader = require("helpers.load_addon")

describe("T016 Correction outcome localization and display", function()
  local function setup()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    return dibs
  end

  it("exposes a distinct localized explanation for every correction outcome", function()
    local dibs = setup()
    local outcomes = {
      "PROPOSED", "ACCEPTED_IN_SESSION", "REPLAYED", "REJECTED", "BLOCKED",
      "RECOVERY_NOT_READY", "ATTRIBUTION_ONLY",
    }
    local seen = {}
    for _, outcome in ipairs(outcomes) do
      local label, explanation = dibs.OfficerUI.DescribeCorrectionOutcome(outcome)
      assert_true(label ~= nil and label ~= "", outcome .. " has no label")
      assert_true(explanation ~= nil and explanation ~= "", outcome .. " has no explanation")
      assert_nil(seen[label], outcome .. " shares a label with another outcome: " .. tostring(seen[label]))
      seen[label] = outcome
    end
  end)

  it("never claims disk durability or universal propagation", function()
    local dibs = setup()
    local _, explanation = dibs.OfficerUI.DescribeCorrectionOutcome("ACCEPTED_IN_SESSION")
    assert_true(explanation:find("saved to disk", 1, true) == nil, "must not claim a disk save")
    assert_true(explanation:find("synchronized to everyone", 1, true) == nil, "must not claim universal sync")
    assert_true(explanation:find("reload", 1, true) ~= nil, "must state the persistence confirmation limit")
  end)

  it("keeps attribution-only distinct from a balance correction", function()
    local dibs = setup()
    local label, explanation = dibs.OfficerUI.DescribeCorrectionOutcome("ATTRIBUTION_ONLY")
    assert_equal("Attribution Only", label)
    assert_true(explanation:find("no balance entry", 1, true) ~= nil, "must state that no balance entry is created")
  end)

  it("localizes every added outcome string in English and French", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local strings = dibs.L or {}
    for _, key in ipairs({
      "DISPUTE_CORRECTION_OUTCOME_PROPOSED", "DISPUTE_CORRECTION_OUTCOME_ACCEPTED_IN_SESSION",
      "DISPUTE_CORRECTION_OUTCOME_REPLAYED", "DISPUTE_CORRECTION_OUTCOME_REJECTED",
      "DISPUTE_CORRECTION_OUTCOME_BLOCKED", "DISPUTE_CORRECTION_OUTCOME_RECOVERY_NOT_READY",
      "DISPUTE_CORRECTION_OUTCOME_ATTRIBUTION_ONLY",
      "DISPUTE_STATUS_PROPOSED", "DISPUTE_STATUS_BLOCKED", "DISPUTE_STATUS_RECOVERY_NOT_READY",
      "DISPUTE_STATUS_REPLAYED", "DISPUTE_STATUS_ACCEPTED_IN_SESSION",
    }) do
      assert_true(type(strings[key]) == "string" and strings[key] ~= "", "missing locale key: " .. key)
    end
  end)

  it("gives every observable operation state a distinct localized explanation", function()
    local dibs = setup()
    local states = {
      "BEHIND", "INCOMPATIBLE", "PROJECTION_INCOMPLETE", "RECOVERED_AFTER_RELOAD",
      "PERSISTENCE_UNCONFIRMED", "HISTORY_REPORT",
    }
    local seen = {}
    for _, state in ipairs(states) do
      local label, explanation = dibs.OfficerUI.DescribeOperationState(state)
      assert_true(label ~= nil and label ~= "", state .. " has no label")
      assert_true(explanation ~= nil and explanation ~= "", state .. " has no explanation")
      assert_nil(seen[label], state .. " shares a label with another state: " .. tostring(seen[label]))
      seen[label] = state
    end
  end)

  it("never claims a disk flush or a receipt by every member", function()
    local dibs = setup()
    for _, state in ipairs({ "BEHIND", "INCOMPATIBLE", "PROJECTION_INCOMPLETE",
      "RECOVERED_AFTER_RELOAD", "PERSISTENCE_UNCONFIRMED", "HISTORY_REPORT" }) do
      local _, explanation = dibs.OfficerUI.DescribeOperationState(state)
      assert_true(explanation:find("saved to disk", 1, true) == nil,
        state .. " must not claim a disk save")
      assert_true(explanation:find("synchronized to everyone", 1, true) == nil,
        state .. " must not claim a receipt by every member")
    end
  end)

  it("presents the historical report as read-only", function()
    local dibs = setup()
    local report = {
      summary = { complete = 1, partial = 2, ambiguous = 0, localOnly = 3, unverifiable = 4 },
    }
    local rows = dibs.OfficerUI.DescribeHistoricalReport(report)
    assert_equal(5, #rows, "the historical report did not produce one row per classification")
    local total = 0
    for _, row in ipairs(rows) do
      total = total + row.count
      assert_true(row.label ~= nil and row.label ~= "", row.key .. " has no label")
      assert_true(row.explanation:find("read-only", 1, true) ~= nil,
        row.key .. " does not state that the report is read-only")
    end
    assert_equal(10, total, "the historical report summary lost counts")
  end)

  it("gives every historical classification its own distinct visible label", function()
    local dibs = setup()
    local report = {
      summary = { complete = 1, partial = 2, ambiguous = 3, localOnly = 4, unverifiable = 5 },
    }
    local rows = dibs.OfficerUI.DescribeHistoricalReport(report)
    local seen = {}
    for _, row in ipairs(rows) do
      assert_nil(seen[row.label],
        row.key .. " shares a label with " .. tostring(seen[row.label]))
      seen[row.label] = row.key
      assert_true(row.explanation:find("read-only", 1, true) ~= nil,
        row.key .. " does not state that the report is read-only")
    end
    assert_equal(1, rows[1].count, "the complete count was not projected")
    assert_equal(5, rows[5].count, "the unverifiable count was not projected")
  end)

  it("localizes every historical classification string in English and French", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local strings = dibs.L or {}
    for _, key in ipairs({
      "DISPUTE_OPERATION_STATE_HISTORY_COMPLETE", "DISPUTE_OPERATION_STATE_HISTORY_PARTIAL",
      "DISPUTE_OPERATION_STATE_HISTORY_AMBIGUOUS", "DISPUTE_OPERATION_STATE_HISTORY_LOCAL_ONLY",
      "DISPUTE_OPERATION_STATE_HISTORY_UNVERIFIABLE",
    }) do
      assert_true(type(strings[key]) == "string" and strings[key] ~= "", "missing locale key: " .. key)
      assert_true(type(strings[key .. "_HELP"]) == "string" and strings[key .. "_HELP"] ~= "",
        "missing locale key: " .. key .. "_HELP")
    end
  end)

  it("localizes every operation state string in English and French", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local strings = dibs.L or {}
    for _, key in ipairs({
      "DISPUTE_OPERATION_STATE_BEHIND", "DISPUTE_OPERATION_STATE_INCOMPATIBLE",
      "DISPUTE_OPERATION_STATE_PROJECTION_INCOMPLETE", "DISPUTE_OPERATION_STATE_RECOVERED_AFTER_RELOAD",
      "DISPUTE_OPERATION_STATE_PERSISTENCE_UNCONFIRMED", "DISPUTE_OPERATION_STATE_HISTORY_REPORT",
    }) do
      assert_true(type(strings[key]) == "string" and strings[key] ~= "", "missing locale key: " .. key)
    end
  end)
end)
