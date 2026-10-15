local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

describe("Request follow-up and retained lifecycle", function()
  local function setup()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" }, guildRankIndices = { 0, 1, 3 } } })
    local request = dibs.Disputes.CreateReport(fixtures.report("other", { note = "Original dossier" }))
    return dibs, request
  end

  it("assigns only a verified officer and filters due, assigned and waiting work", function()
    local dibs, request = setup()
    local denied, reason = dibs.Disputes.UpdateFollowUp(request.requestId, { assignedTo = "Player-Realm" })
    assert_nil(denied); assert_equal("VERIFIED_OFFICER_REQUIRED", reason)
    local updated = dibs.Disputes.UpdateFollowUp(request.requestId, { assignedTo = "Tester-Realm", followUpAt = time() - 1 })
    assert_true(updated.ok)
    assert_equal(1, #dibs.Disputes.ListForOfficer(nil, { filter = "due" }))
    assert_equal(1, #dibs.Disputes.ListForOfficer(nil, { filter = "assigned" }))
    assert_equal(0, #dibs.Disputes.ListForOfficer(nil, { filter = "waiting" }))
    dibs.Disputes.AskForInformation(request.requestId, "Which raid?")
    assert_equal(1, #dibs.Disputes.ListForOfficer(nil, { filter = "waiting" }))
    local safe = dibs.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_nil(safe.assignedTo); assert_nil(safe.timeline)
    assert_not_nil(safe.followUpAt)
  end)

  it("adds a public reply without putting internal audit in the owner projection", function()
    local dibs, request = setup()
    dibs.Disputes.UpdateFollowUp(request.requestId, { reason = "PRIVATE administrative rationale" })
    local reply = dibs.Disputes.AddOfficerReply(request.requestId, "We are checking your report.")
    assert_equal("officer", reply.author)
    local safe = dibs.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_equal(reply.boundedText, safe.replies[1].boundedText)
    assert_nil(safe.timeline); assert_nil(safe.guildScope); assert_nil(safe.officerOnly)
    assert_equal(3, #dibs.Disputes.GetTimeline(request.requestId, nil))
  end)

  it("retains the original complete dossier through conclusion, close and archive", function()
    local dibs, request = setup()
    dibs.Disputes.AddOfficerReply(request.requestId, "Searchable public reply")
    dibs.Disputes.NoCorrection(request.requestId, "Reviewed without correction")
    assert_nil(dibs.Disputes.Resolve(request.requestId, "archive", { reason = "Too early" }))
    assert_nil(dibs.Disputes.Resolve(request.requestId, "close", {}))
    assert_true(dibs.Disputes.Resolve(request.requestId, "close", { reason = "Owner informed" }).ok)
    assert_true(dibs.Disputes.Resolve(request.requestId, "archive", { reason = "Retain complete case" }).ok)
    local archived = dibs.Disputes.GetRequest(request.requestId, nil)
    assert_equal("Archived", archived.status)
    assert_equal(5, #archived.timeline)
    assert_equal("Original dossier", archived.note)
    assert_equal(1, #archived.replies)
    assert_equal(1, #dibs.Disputes.ListForOfficer(nil, { filter = "archived", query = "Searchable public" }))
    assert_equal(1, #dibs.Disputes.ListForPlayer("Tester-Realm", { status = "Archived" }))
    assert_true(dibs.Disputes.Reopen(request.requestId, "Additional evidence").ok)
    assert_equal(6, #dibs.Disputes.GetTimeline(request.requestId, nil))
  end)

  it("allows rejection to close and archive without changing the conclusion", function()
    local dibs, request = setup()
    dibs.Disputes.Resolve(request.requestId, "reject", { reason = "Insufficient evidence" })
    dibs.Disputes.Resolve(request.requestId, "close", { reason = "Reviewed" })
    dibs.Disputes.Resolve(request.requestId, "archive", { reason = "Retained" })
    assert_equal("reject", dibs.Disputes.GetRequest(request.requestId, nil).resolution.action)
  end)

  it("fails before correction when audit capacity is full and never truncates history", function()
    local dibs, request = setup()
    local raw = dibs.GetDB().disputes.requests[request.requestId]
    for index = 2, 120 do raw.timeline[index] = { eventId = "event-" .. index, reason = "retained" } end
    local before = #dibs.Ledger.GetAllTransactions()
    local denied, reason = dibs.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "No capacity" })
    assert_nil(denied); assert_equal("REQUEST_AUDIT_CAPACITY", reason)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
    assert_equal(120, #raw.timeline)
    assert_equal("created", raw.timeline[1].action)
    assert_nil(dibs.Disputes.AddOfficerReply(request.requestId, "Cannot append"))
  end)

  it("rejects new requests at capacity without deleting terminal dossiers", function()
    local dibs, request = setup()
    local store = dibs.GetDB().disputes
    for index = 2, 500 do
      store.order[index] = "archived-" .. index
      store.requests[store.order[index]] = { requestId = store.order[index], status = "Archived", timeline = { { reason = "Retained" } } }
    end
    local result, reason = dibs.Disputes.CreateReport({ category = "integration", note = "New unique issue" })
    assert_nil(result); assert_equal("REQUEST_CAPACITY", reason)
    assert_equal(500, #store.order)
    assert_not_nil(store.requests["archived-500"])
    assert_not_nil(store.requests[request.requestId])
  end)

  it("checks optimistic revisions and preserves compensation links after archival", function()
    local dibs, request = setup()
    local stale, reason = dibs.Disputes.UpdateFollowUp(request.requestId, { expectedRevision = 99 })
    assert_nil(stale); assert_equal("REQUEST_REVISION_CONFLICT", reason)
    local correction = dibs.Disputes.CorrectBalance(request.requestId, { amount = 1, confirmed = true, reason = "Verified correction" })
    assert_true(correction.ok)
    local before = #dibs.Ledger.GetAllTransactions()
    dibs.Disputes.Resolve(request.requestId, "close", { reason = "Complete" })
    dibs.Disputes.Resolve(request.requestId, "archive", { reason = "Retain" })
    assert_nil(dibs.Disputes.Reopen(request.requestId, "Do not double apply"))
    assert_equal(correction.transaction.transactionId, dibs.Disputes.GetRequest(request.requestId, nil).correctionTransactionId)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("persists and throttles local reminders with snooze and disabled notifications", function()
    local dibs, request = setup()
    local clock = 1792000000
    _G.time = function() return clock end
    dibs.Disputes.UpdateFollowUp(request.requestId, { assignedTo = "Tester-Realm", followUpAt = clock - 1 })
    local count = #_G.__dibsMessages
    dibs.RequestDelivery.CheckReminders()
    assert_equal(count + 1, #_G.__dibsMessages)
    dibs.RequestDelivery.CheckReminders()
    assert_equal(count + 1, #_G.__dibsMessages)
    assert_true(dibs.RequestDelivery.Snooze(request.requestId, clock + 7200))
    clock = clock + 3601
    dibs.RequestDelivery.CheckReminders()
    assert_equal(count + 1, #_G.__dibsMessages)
    local saved, personal = dibs.DeepCopy(_G.RCLootCouncil_dibsDB), dibs.DeepCopy(_G.RCLootCouncil_dibsLocalDB)
    _, dibs = loader.load({ withAce3 = true, savedVariables = saved, localVariables = personal })
    _G.time = function() return clock end
    dibs.RequestDelivery.CheckReminders()
    assert_not_nil(dibs.GetLocalDB().requestDelivery[dibs.GetGuildKey()].reminders[request.requestId].snoozedUntil)
    clock = clock + 4000
    dibs.Notifications.SetEnabled(false)
    local disabledCount = #_G.__dibsMessages
    dibs.RequestDelivery.CheckReminders()
    assert_equal(disabledCount, #_G.__dibsMessages)
  end)

  it("fails atomically when the durable outbox is full", function()
    local dibs, request = setup()
    local pending = dibs.GetLocalDB().requestDelivery[dibs.GetGuildKey()].pending
    for key in pairs(pending) do pending[key] = nil end
    for index = 1, 128 do pending["pending-" .. index] = { message = { operationId = "pending-" .. index } } end
    local result, reason = dibs.Disputes.CreateReport({ category = "integration", note = "Capacity boundary" })
    assert_nil(result); assert_equal("REQUEST_OUTBOX_CAPACITY", reason)
    assert_equal(1, #dibs.GetDB().disputes.order)
    assert_equal(request.requestId, dibs.GetDB().disputes.order[1])
  end)

  it("migrates legacy dossiers additively without changing serialized status or evidence", function()
    local dibs, request = setup()
    local saved = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    local guild = saved.guilds[dibs.GetGuildKey()]
    guild.disputes.version = 1
    guild.disputes.requests[request.requestId].revision = nil
    _, dibs = loader.load({ withAce3 = true, savedVariables = saved })
    local restored = dibs.Disputes.GetRequest(request.requestId, nil)
    assert_equal(2, dibs.GetDB().disputes.version)
    assert_equal("Open", restored.status)
    assert_equal(request.evidence[1].evidenceId, restored.evidence[1].evidenceId)
    assert_equal(1, #restored.timeline)
  end)

  it("exposes localized follow-up controls and queues without a new navigation route", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { locale = "frFR", guildLeader = true } })
    local request = dibs.Disputes.CreateReport({ category = "other", note = "Contrôle synthétique" })
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame.OpenRequestDetail(dibs.Disputes.GetRequest(request.requestId, nil)))
    local function find(widget, kind, text)
      if widget.kind == kind and (widget.text == text or widget.label == text) then return widget end
      for _, child in ipairs(widget.children or {}) do local value = find(child, kind, text); if value then return value end end
    end
    local assign = find(frame.requestDetailRoot, "Button", dibs.L.REQUEST_ASSIGN_ME)
    assert_not_nil(assign)
    assign.callbacks.OnClick(assign, "OnClick")
    assert_equal("Tester-Realm", dibs.Disputes.GetRequest(request.requestId, nil).assignedTo)
    assert_not_nil(find(frame.requestDetailRoot, "Button", dibs.L.REQUEST_SEND_REPLY))
    frame.SelectTab("disputes")
    assert_equal("disputes", frame.activeTab)
  end)

  it("bounds reminder bursts globally across reload and fairly reaches remaining requests", function()
    local dibs, request = setup()
    local clock = 1792000000
    _G.time = function() return clock end
    local cases = { request }
    for index = 2, 4 do cases[index] = dibs.Disputes.CreateReport({ note = "Independent due issue " .. index }) end
    for _, case in ipairs(cases) do dibs.Disputes.UpdateFollowUp(case.requestId, { followUpAt = clock - 1 }) end
    local before = #_G.__dibsMessages
    dibs.RequestDelivery.CheckReminders()
    assert_equal(before + 3, #_G.__dibsMessages)
    dibs.RequestDelivery.CheckReminders()
    assert_equal(before + 3, #_G.__dibsMessages)
    local saved, personal = dibs.DeepCopy(_G.RCLootCouncil_dibsDB), dibs.DeepCopy(_G.RCLootCouncil_dibsLocalDB)
    _, dibs = loader.load({ withAce3 = true, wow = { now = clock }, savedVariables = saved, localVariables = personal })
    _G.time = function() return clock end
    before = #_G.__dibsMessages
    dibs.RequestDelivery.CheckReminders()
    assert_equal(before, #_G.__dibsMessages)
    clock = clock + 61
    dibs.RequestDelivery.CheckReminders()
    assert_equal(before + 1, #_G.__dibsMessages)
    local reminders = dibs.GetLocalDB().requestDelivery[dibs.GetGuildKey()].reminders
    for _, case in ipairs(cases) do assert_not_nil(reminders[case.requestId].lastAt) end
  end)

  it("does not report complete receipt while another private delivery remains pending or failed", function()
    local dibs, request = setup()
    local delivery = dibs.GetLocalDB().requestDelivery[dibs.GetGuildKey()]
    delivery.statuses[request.requestId].state = "received"
    delivery.pending = {
      first = { message = { requestId = request.requestId }, lastState = "sent" },
      second = { message = { requestId = request.requestId }, lastState = "error", lastReason = "PAYLOAD_TOO_LARGE" },
    }
    local status = dibs.RequestDelivery.GetStatus(request.requestId)
    assert_equal("error", status.state)
    assert_equal("PAYLOAD_TOO_LARGE", status.reason)
    assert_equal(2, status.pendingCount)
    assert_equal("error", dibs.Disputes.GetRequest(request.requestId, nil).delivery.state)
    local safe = dibs.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_nil(safe.delivery.targets)
  end)
end)
