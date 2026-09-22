local loader = require("helpers.load_addon")

local function setup()
  return loader.load({
    wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1", "Player-2" } },
    withAce3 = true,
  })
end

local function findWidget(widget, kind, text)
  if type(widget) ~= "table" then return nil end
  if widget.kind == kind and (widget.text == text or widget.label == text or widget.title == text) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findWidget(child, kind, text)
    if found then return found end
  end
  return nil
end

describe("B12 request action contracts", function()
  it("requires reasons for normal resolution actions and delegates existing transitions", function()
    local _, dibs = setup()
    local askRequest = dibs.Disputes.CreateReport({ category = "other", note = "Need a review" })
    local asked, askReason = dibs.Disputes.Resolve(askRequest.requestId, "ask_information", {}, nil)
    assert_nil(asked)
    assert_equal("QUESTION_REQUIRED", askReason)

    asked, askReason = dibs.Disputes.Resolve(askRequest.requestId, "ask_information", { question = "Which raid was this?" }, nil)
    assert_true(asked.ok)
    assert_equal("Need information", asked.request.status)

    local resolveRequest = dibs.Disputes.CreateReport({ category = "other", note = "Resolve this review" })
    local resolved, resolveReason = dibs.Disputes.Resolve(resolveRequest.requestId, "no_correction", {}, nil)
    assert_nil(resolved)
    assert_equal("REASON_REQUIRED", resolveReason)
    resolved, resolveReason = dibs.Disputes.Resolve(resolveRequest.requestId, "no_correction", { reason = "Evidence reviewed" }, nil)
    assert_true(resolved.ok)
    assert_equal("Resolved", resolved.request.status)

    local rejectRequest = dibs.Disputes.CreateReport({ category = "other", note = "Reject this review" })
    local rejected, rejectReason = dibs.Disputes.Resolve(rejectRequest.requestId, "reject", {}, nil)
    assert_nil(rejected)
    assert_equal("REASON_REQUIRED", rejectReason)
    rejected, rejectReason = dibs.Disputes.Resolve(rejectRequest.requestId, "reject", { reason = "Evidence does not support the report" }, nil)
    assert_true(rejected.ok)
    assert_equal("Rejected", rejected.request.status)
  end)

  it("keeps cancellation unsupported and protects request privacy", function()
    local _, dibs = setup()
    local request = dibs.Disputes.CreateReport({ category = "other", note = "Private request" })
    local hidden, hiddenReason = dibs.Disputes.GetRequest(request.requestId, "Player-2")
    assert_nil(hidden)
    assert_equal("REQUEST_NOT_FOUND", hiddenReason)

    local cancelled, cancelReason = dibs.Disputes.Resolve(request.requestId, "cancel", { reason = "Cancel request" }, nil)
    assert_nil(cancelled)
    assert_equal("UNKNOWN_RESOLUTION_ACTION", cancelReason)
    local unchanged = dibs.Disputes.GetRequest(request.requestId, nil)
    assert_equal("Open", unchanged.status)
  end)

  it("requires confirmation and reason for advanced actions and delegates ledger work", function()
    local _, dibs = setup()
    local request = dibs.Disputes.CreateReport({
      category = "missing_debit",
      itemID = 21016,
      itemName = "Midnight Blade",
      source = "dibs",
      note = "Missing debit review",
    })
    local missingConfirmation, confirmationReason = dibs.Disputes.Resolve(request.requestId, "correct_balance", { amount = 1, reason = "Reviewed" }, nil)
    assert_nil(missingConfirmation)
    assert_equal("CONFIRMATION_REQUIRED", confirmationReason)
    local missingReason, reasonCode = dibs.Disputes.Resolve(request.requestId, "correct_balance", { amount = 1, confirmed = true }, nil)
    assert_nil(missingReason)
    assert_equal("REASON_REQUIRED", reasonCode)

    local protectedCalls = {}
    local originalProtectedExecute = dibs.ProtectedActions.Execute
    local ledgerCalls = 0
    local originalUse = dibs.Ledger.Use
    local originalRefund = dibs.Ledger.Refund
    local originalAdjust = dibs.Ledger.AdminAdjust
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      protectedCalls[#protectedCalls + 1] = { actionId = actionId, actor = actor, payload = payload }
      return { ok = true, value = { transactionId = "protected-review-1" } }
    end
    dibs.Ledger.Use = function() ledgerCalls = ledgerCalls + 1; error("direct ledger use") end
    dibs.Ledger.Refund = function() ledgerCalls = ledgerCalls + 1; error("direct ledger refund") end
    dibs.Ledger.AdminAdjust = function() ledgerCalls = ledgerCalls + 1; error("direct ledger adjust") end

    local corrected, correctionReason = dibs.Disputes.Resolve(request.requestId, "correct_balance", {
      amount = 1,
      confirmed = true,
      reason = "Verified missing debit",
    }, nil)

    dibs.ProtectedActions.Execute = originalProtectedExecute
    dibs.Ledger.Use = originalUse
    dibs.Ledger.Refund = originalRefund
    dibs.Ledger.AdminAdjust = originalAdjust
    assert_true(corrected.ok, correctionReason)
    assert_equal(1, #protectedCalls)
    assert_equal("ledger.use", protectedCalls[1].actionId)
    assert_equal(true, protectedCalls[1].payload.confirmation)
    assert_equal("dispute-center", protectedCalls[1].payload.source)
    assert_equal(0, ledgerCalls)
  end)

  it("keeps primary actions visible while advanced tools stay collapsed until opened", function()
    local _, dibs = setup()
    local request = {
      requestId = "b12-action-visibility",
      status = "Open",
      category = "other",
      categoryLabel = "Other",
      player = { name = "Player-1" },
      evidence = { { item = "Midnight Blade", source = "Dibs ledger" } },
    }
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(request))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Ask for information"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Resolve"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Reject"))
    assert_nil(findWidget(frame.requestDetailRoot, "Button", "Correct player / item"))

    local advanced = findWidget(frame.requestDetailRoot, "Button", "Advanced Officer Tools")
    assert_not_nil(advanced)
    advanced.callbacks.OnClick(advanced, "OnClick")
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Correct player / item"))
    assert_not_nil(findWidget(frame.requestDetailRoot, "Button", "Import historical"))
  end)
end)
