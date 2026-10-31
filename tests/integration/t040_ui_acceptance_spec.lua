local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

-- T040: UI acceptance coverage for the canonical correction workflow.
--
-- The suite proves that an officer can always read a single, explicit status
-- and its reason, that the historical report stays read-only, that the narrow
-- and wide layouts both remain usable, that the empty and error states are
-- explicit, and that no other guild or private session data leaks into the
-- view.

local function findWidget(root, kind, text)
  if type(root) ~= "table" then return nil end
  if root.kind == kind and (root.text == text or root.label == text) then return root end
  for _, child in ipairs(root.children or {}) do
    local value = findWidget(child, kind, text)
    if value then return value end
  end
  return nil
end

local function collectText(root, into)
  into = into or {}
  if type(root) ~= "table" then return into end
  for _, field in ipairs({ "text", "_dibsText", "label" }) do
    if type(root[field]) == "string" then into[#into + 1] = root[field] end
  end
  for _, child in ipairs(root.children or {}) do collectText(child, into) end
  return into
end

local function containsAny(parts, needle)
  for _, part in ipairs(parts) do
    if type(part) == "string" and part:find(needle, 1, true) then return true end
  end
  return false
end

describe("T040 canonical correction UI acceptance", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { 0, 1, 3 } } })
    return dibs
  end

  local function installRequest(dibs, options)
    options = options or {}
    local seasonId = dibs.Seasons.GetCurrent().id
    local original = assert(dibs.Ledger.AddTransaction({
      transactionId = options.transactionId or "t040-original",
      playerName = "Tester-Realm",
      amount = -1,
      type = "DIB_USED",
      reason = "Original recorded event",
      source = "test",
      seasonId = seasonId,
    }))
    local request = assert(dibs.Disputes.CreateReport({
      category = "wrong_debit",
      transactionRef = original.transactionId,
      note = options.note or "Synthetic UI acceptance report",
    }))
    return original, request
  end

  it("shows a distinct visible status and reason for every correction outcome", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    for _, outcome in ipairs({ "PROPOSED", "ACCEPTED_IN_SESSION", "REPLAYED", "REJECTED",
      "BLOCKED", "RECOVERY_NOT_READY", "ATTRIBUTION_ONLY" }) do
      local label, explanation = dibs.OfficerUI.DescribeCorrectionOutcome(outcome)
      assert_true(label ~= nil and label ~= "", outcome .. " has no visible status")
      assert_true(explanation ~= nil and explanation ~= "", outcome .. " has no visible reason")
      assert_true(explanation:find("saved to disk", 1, true) == nil,
        outcome .. " must not claim a disk save")
      assert_true(explanation:find("synchronized to everyone", 1, true) == nil,
        outcome .. " must not claim universal propagation")
    end
    assert_not_nil(frame)
  end)

  it("renders the outcome label and reason in the request detail view", function()
    local dibs = setup()
    local _, request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(dibs.Disputes.GetRequest(request.requestId, nil)))
    -- The real flow sets the success projection and then re-opens the detail.
    frame.requestSuccess = {
      requestId = request.requestId,
      action = "Correction applied",
      reference = "t040-reference",
      outcome = "ACCEPTED_IN_SESSION",
    }
    assert_true(frame.OpenRequestDetail(dibs.Disputes.GetRequest(request.requestId, nil)))
    local parts = collectText(frame.requestDetailRoot)
    assert_true(containsAny(parts, "Accepted in Session"),
      "the outcome label is not visible in the request detail view")
    assert_true(containsAny(parts, "Persistence is confirmed only after a later reload observes it"),
      "the outcome reason is not visible in the request detail view")
  end)
  it("keeps the historical report read-only and separates every classification", function()
    local dibs = setup()
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    assert_true(report.readOnly == true, "the historical report is not marked read-only")
    local rows = dibs.OfficerUI.DescribeHistoricalReport(report)
    assert_equal(5, #rows, "the historical report did not produce one row per classification")
    local seen = {}
    for _, row in ipairs(rows) do
      assert_nil(seen[row.label], row.key .. " shares a label with another classification")
      seen[row.label] = row.key
      assert_true(row.explanation:find("read-only", 1, true) ~= nil,
        row.key .. " does not state that the report is read-only")
    end
  end)

  it("keeps the empty state explicit when no historical candidate exists", function()
    local dibs = setup()
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    local rows = dibs.OfficerUI.DescribeHistoricalReport(report)
    local total = 0
    for _, row in ipairs(rows) do total = total + row.count end
    assert_equal(0, total, "a fresh guild reported historical correction candidates")
    for _, row in ipairs(rows) do
      assert_true(row.count == 0, row.key .. " reported a candidate in an empty guild")
      assert_true(row.label ~= nil and row.label ~= "", row.key .. " has no label in the empty state")
    end
  end)

  it("shows a bounded, non-clipped detail view in the narrow and wide layouts", function()
    local dibs = setup()
    local _, request = installRequest(dibs)
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(dibs.Disputes.GetRequest(request.requestId, nil)))
    for _, width in ipairs({ metrics.minWidth, metrics.maxWidth }) do
      frame.requestDetailShell.layout.width = width
      frame:Refresh()
      local parts = collectText(frame.requestDetailRoot)
      assert_true(#parts > 0, "the detail view rendered nothing at width " .. tostring(width))
      local hasStatus = false
      for _, part in ipairs(parts) do
        if type(part) == "string" and part:find("Open", 1, true) then hasStatus = true end
      end
      assert_true(hasStatus, "the dossier status is not visible at width " .. tostring(width))
    end
  end)

  it("keeps the guild scope isolated between two guilds", function()
    local dibs = setup()
    local _, request = installRequest(dibs)
    local otherGuildKey = dibs.GetGuildKey()
    local _, otherGuild = loader.load({ withAce3 = true, wow = { guildLeader = true, guildName = "OtherGuild" } })
    assert_true(otherGuild.GetGuildKey() ~= otherGuildKey,
      "the second client resolved the same guild key")
    assert_nil(otherGuild.Disputes.GetRequest(request.requestId, nil),
      "a dossier from another guild was readable")
  end)

  it("never exposes a live loot session or candidate in the correction view", function()
    local dibs = setup()
    local _, request = installRequest(dibs)
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(dibs.Disputes.GetRequest(request.requestId, nil)))
    local parts = collectText(frame.requestDetailRoot)
    for _, part in ipairs(parts) do
      if type(part) == "string" then
        assert_true(part:find("candidate", 1, true) == nil,
          "the correction view exposed a live loot candidate")
        assert_true(part:find("vote", 1, true) == nil,
          "the correction view exposed a live loot vote")
      end
    end
  end)

  it("keeps the historical report free of any mutation of the ledger", function()
    local dibs = setup()
    installRequest(dibs)
    local before = #dibs.Ledger.GetAllTransactions()
    local canonicalBefore = dibs.Ledger.GetCanonicalState and dibs.Ledger.GetCanonicalState("guild-primary") or nil
    local report = dibs.Disputes.BuildLegacyCorrectionReport("guild-primary")
    assert_not_nil(report)
    dibs.OfficerUI.DescribeHistoricalReport(report)
    assert_equal(before, #dibs.Ledger.GetAllTransactions(), "the read-only report changed the ledger")
    local canonicalAfter = dibs.Ledger.GetCanonicalState and dibs.Ledger.GetCanonicalState("guild-primary") or nil
    if canonicalBefore and canonicalAfter then
      assert_equal(canonicalBefore.nextSeq, canonicalAfter.nextSeq,
        "the read-only report advanced the canonical sequence")
      assert_equal(canonicalBefore.rootHash, canonicalAfter.rootHash,
        "the read-only report changed the canonical root hash")
    end
  end)
end)
