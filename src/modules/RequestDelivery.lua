-- Private request delivery and online-only follow-up; never writes accounting.
local Dibs = _G.Dibs
Dibs.RequestDelivery = Dibs.RequestDelivery or {}
local Delivery = Dibs.RequestDelivery
local MAX_PENDING, RETRY_SECONDS, REMINDER_SECONDS = 128, 60, 3600
local MAX_REMINDERS_PER_BATCH, REMINDER_BATCH_SECONDS = 3, 60
local cursor = 0

local function copy(value) return Dibs.DeepCopy(value) end
local function scope() return tostring(Dibs.GetGuildKey()) end
local function enabled()
  return not (Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled())
    and not (Dibs.IndependentRaid and Dibs.IndependentRaid.IsSessionActive and Dibs.IndependentRaid.IsSessionActive())
    and (not Dibs.OperationalPolicy or Dibs.OperationalPolicy.IsModuleEnabled("requests") == true)
end
local function member(name)
  local result = Dibs.Identity and Dibs.Identity.ResolveRosterMember(name)
  return result and result.status == "RESOLVED" and result or nil
end
local function admin(value) return value and (value.role == "gm" or value.role == "officer") end
local function localMember() return member(Dibs.GetPlayerName()) end
local function state()
  local root = Dibs.GetLocalDB()
  root.requestDelivery = root.requestDelivery or {}
  root.requestDelivery[scope()] = root.requestDelivery[scope()] or { pending = {}, statuses = {}, reminders = {} }
  return root.requestDelivery[scope()]
end
local function requests()
  local db = Dibs.GetDB()
  return db.disputes and db.disputes.requests or {}
end
local function authority()
  local current = Dibs.Governance and Dibs.Governance.GetAuthorityState()
  if not current or current.state ~= "ACTIVE" or not current.coordinator then return nil end
  if type(current.ledgerEpoch) ~= "number" or current.ledgerEpoch < 1
    or current.ledgerEpoch ~= math.floor(current.ledgerEpoch) or current.ledgerEpoch == math.huge then return nil end
  local coordinator = member(current.coordinator.displayName)
  if not admin(coordinator) or coordinator.memberKey ~= current.coordinator.memberKey then return nil end
  return { memberKey = coordinator.memberKey, epoch = current.ledgerEpoch, displayName = coordinator.displayName }
end
local function sameAuthority(first, second)
  return type(first) == "table" and type(second) == "table" and first.memberKey == second.memberKey and first.epoch == second.epoch
end
local function requestStatus(id)
  local store = state()
  store.statuses[id] = store.statuses[id] or { state = "queued", targets = {} }
  return store.statuses[id]
end
local function send(message, target)
  return Dibs.Sync.SendDetail("REQUEST_MESSAGE", message.operationId, message.revision or 1,
    Dibs.Sync.CalculateContentHash(message), message, target)
end
local function queue(message, target, key)
  local store = state()
  key = key or message.operationId
  if not store.pending[key] then
    local ok, reason = Delivery.CanQueue()
    if not ok then return nil, reason end
  end
  store.pending[key] = { message = copy(message), target = target, attempts = 0, nextAttemptAt = 0, lastState = "queued" }
  local status = requestStatus(message.requestId)
  status.state, status.reason = "queued", nil
  return copy(message)
end

function Delivery.CanQueue()
  local count = 0
  for _ in pairs(state().pending) do count = count + 1 end
  return count < MAX_PENDING, count >= MAX_PENDING and "REQUEST_OUTBOX_CAPACITY" or nil
end

function Delivery.CanMutate(request)
  if not enabled() then return false, "REQUEST_CONTEXT_ISOLATED" end
  local current, actor = authority(), localMember()
  if not current or not actor or current.memberKey ~= actor.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
  if request.deliveryAuthority and not sameAuthority(current, request.deliveryAuthority) then return false, "REQUEST_AUTHORITY_CHANGED" end
  return true
end

function Delivery.GetStatus(id)
  local result = state().statuses[id]
  if not result then return nil end
  local view = { state = result.state, reason = result.reason, attempts = result.attempts, receivedAt = result.receivedAt, pendingCount = 0 }
  local priority = { received = 0, sent = 1, queued = 2, error = 3 }
  local pendingState
  for _, pending in pairs(state().pending) do
    if pending.message.requestId == id then
      view.pendingCount = view.pendingCount + 1
      local value = pending.lastState or "queued"
      if not pendingState or (priority[value] or 0) > (priority[pendingState] or 0) then
        pendingState, view.reason = value, pending.lastReason
      end
    end
  end
  if pendingState then view.state = pendingState end
  return view
end

function Delivery.QueueSubmission(request)
  if not enabled() then return nil, "REQUEST_CONTEXT_ISOLATED" end
  local current, actor = authority(), localMember()
  if current then request.deliveryAuthority = copy(current) end
  if current and actor and current.memberKey == actor.memberKey then
    request.deliveryAuthority = copy(current)
    local status = requestStatus(request.requestId)
    status.state, status.receivedAt = "received", time()
    Delivery.OnChanged(request, "created")
    return true
  end
  return queue({
    operationId = Dibs.NewId("request-send"), kind = "submit", requestId = request.requestId,
    guildScope = scope(), revision = 1, authority = current,
    body = { requestId = request.requestId, playerName = request.player.name, category = request.category,
      note = request.note, evidence = copy(request.evidence) },
  }, current and current.displayName)
end

function Delivery.QueueReply(request, value)
  if not enabled() then return nil, "REQUEST_CONTEXT_ISOLATED" end
  local id = Dibs.NewId("request-reply")
  if Delivery.CanMutate(request) then
    return Dibs.Disputes.ReceiveReply(request.requestId, value, id, Dibs.GetPlayerName(), request.revision or 0)
  end
  local queued, reason = queue({
    operationId = id, kind = "reply", requestId = request.requestId, guildScope = scope(),
    revision = tonumber(request.revision) or 0, authority = copy(request.deliveryAuthority),
    body = { replyId = id, text = value },
  }, request.deliveryAuthority.displayName)
  if not queued then return nil, reason end
  return { replyId = id, boundedText = value, queued = true }
end

local function queueSnapshot(request, recipient)
  local actor = localMember()
  if not recipient or not actor or recipient.memberKey == actor.memberKey then return end
  local owner = member(request.player and request.player.name)
  if not owner then return end
  local isOwner = owner.memberKey == recipient.memberKey
  if not isOwner and not admin(recipient) then return end
  local progress = requestStatus(request.requestId)
  if (progress.targets[recipient.memberKey] or 0) >= (request.revision or 0) then return end
  local key = request.requestId .. "|" .. recipient.memberKey
  local pending = state().pending[key]
  if pending and pending.message.revision == request.revision then return end
  -- Owner projection always wins even when the owner is also an officer.
  local body = isOwner and Dibs.Disputes.BuildSafeView(request) or Dibs.Disputes.BuildOfficerView(request)
  body.delivery = nil
  local queued, reason = queue({ operationId = Dibs.NewId("request-state"), kind = "snapshot", guildScope = scope(),
    requestId = request.requestId, revision = request.revision or 1, authority = copy(request.deliveryAuthority),
    owner = owner.displayName, projection = isOwner and "owner" or "officer", body = body,
  }, recipient.displayName, key)
  if not queued then progress.state, progress.reason = "error", reason end
end

function Delivery.OnChanged(request, action)
  if not enabled() then return end
  local owner, actor = member(request.player and request.player.name), localMember()
  if owner and actor and owner.memberKey == actor.memberKey and Dibs.Notifications then
    local kind = (request.status == "Resolved" or request.status == "Rejected") and "REQUEST_RESOLVED"
      or (action == "officer_reply" or action == "ask_information") and "REQUEST_REPLY" or nil
    if kind then Dibs.Notifications.Notify("request:" .. request.requestId .. ":" .. tostring(request.revision), kind, { itemName = request.requestId }) end
  end
  if not request.deliveryAuthority or not Delivery.CanMutate(request) then return end
  queueSnapshot(request, member(request.player and request.player.name))
  for _, recipient in ipairs(Dibs.Sync.GetRequestPeers()) do queueSnapshot(request, recipient) end
end

local function validId(value)
  return type(value) == "string" and #value > 0 and #value <= 128
end
local function validTree(value, depth, budget)
  depth, budget = depth or 0, budget or { count = 0 }
  if depth > 9 then return false end
  local kind = type(value)
  if kind == "string" then return #value <= 512 end
  if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
  if kind == "boolean" or kind == "nil" then return true end
  if kind ~= "table" then return false end
  for key, item in pairs(value) do
    budget.count = budget.count + 1
    if budget.count > 2500 or (type(key) ~= "string" and type(key) ~= "number")
      or not validTree(item, depth + 1, budget) then return false end
  end
  return true
end
local function receipt(message, recipient, accepted, reason)
  return send({ operationId = Dibs.NewId("request-receipt"), kind = "receipt", requestId = message.requestId,
    guildScope = scope(), revision = message.revision, authority = copy(message.authority),
    acknowledgedId = message.operationId, accepted = accepted == true, reason = reason,
  }, recipient.displayName)
end
local function notify(request, previous)
  if not Dibs.Notifications then return end
  local resolution, prior = request.resolution, previous and previous.resolution
  if resolution and (not prior or resolution.createdAt ~= prior.createdAt or resolution.action ~= prior.action) then
    Dibs.Notifications.Notify("request:" .. request.requestId .. ":resolved:" .. tostring(resolution.createdAt) .. ":" .. tostring(resolution.action), "REQUEST_RESOLVED", {
      itemName = request.requestId,
    })
  elseif #(request.replies or {}) > #(previous and previous.replies or {})
    or request.status == "Need information" and (not previous or previous.status ~= "Need information" or previous.question ~= request.question) then
    Dibs.Notifications.Notify("request:" .. request.requestId .. ":reply:" .. tostring(request.revision), "REQUEST_REPLY", {
      itemName = request.requestId,
    })
  end
end

function Delivery.Receive(message, actualSender)
  if not enabled() then return false, "REQUEST_CONTEXT_ISOLATED" end
  local sender, actor, current = member(actualSender), localMember(), authority()
  if not sender or not actor then return false, "ROSTER_UNAVAILABLE" end
  if type(message) ~= "table" or not validTree(message) or not validId(message.operationId)
    or not validId(message.requestId) or message.guildScope ~= scope()
    or type(message.revision) ~= "number" or message.revision < 0 or message.revision ~= math.floor(message.revision) then
    return false, "INVALID_REQUEST_MESSAGE"
  end
  if not sameAuthority(current, message.authority) then return false, "REQUEST_AUTHORITY_CHANGED" end
  if message.kind == "receipt" then
    for key, pending in pairs(state().pending) do
      local expected = member(pending.target)
      if pending.message.operationId == message.acknowledgedId and pending.message.requestId == message.requestId
        and pending.message.revision == message.revision and sameAuthority(pending.message.authority, message.authority)
        and expected and expected.memberKey == sender.memberKey then
        if pending.message.kind ~= "snapshot" and (not admin(sender) or current.memberKey ~= sender.memberKey) then return false, "CURRENT_COORDINATOR_REQUIRED" end
        local status = requestStatus(message.requestId)
        if message.accepted == true then
          state().pending[key] = nil
          status.state, status.reason, status.receivedAt = "received", nil, time()
          status.targets[sender.memberKey] = math.max(status.targets[sender.memberKey] or 0, message.revision)
        else
          status.state, status.reason = "error", message.reason or "REQUEST_REJECTED"
          pending.lastState, pending.lastReason = status.state, status.reason
          pending.nextAttemptAt = time() + RETRY_SECONDS
        end
        return true, message.accepted and "REQUEST_RECEIVED" or "REQUEST_REJECTED"
      end
    end
    return true, "IDEMPOTENT_RECEIPT"
  end
  if message.kind == "snapshot" then
    if not admin(sender) or current.memberKey ~= sender.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
    local owner = member(message.owner)
    if not owner then return false, "PLAYER_SCOPE_REQUIRED" end
    local isOwner = owner.memberKey == actor.memberKey
    if (isOwner and message.projection ~= "owner") or (not isOwner and (not admin(actor) or message.projection ~= "officer")) then return false, "REQUEST_PRIVATE" end
    local body = message.body
    if type(body) ~= "table" or body.requestId ~= message.requestId or body.revision ~= message.revision
      or type(body.evidence) ~= "table" or type(body.replies) ~= "table"
      or (body.timeline ~= nil and type(body.timeline) ~= "table")
      or (body.attachedContext ~= nil and type(body.attachedContext) ~= "table")
      or (body.resolution ~= nil and type(body.resolution) ~= "table")
      or type(body.category) ~= "string" or not Dibs.Disputes.CATEGORIES[body.category]
      or type(body.note) ~= "string" or #body.note > 240
      or (body.categoryLabel ~= nil and type(body.categoryLabel) ~= "string")
      or #(body.timeline or {}) > 120 or #body.replies > 120 or #body.evidence > 8 then return false, "INVALID_REQUEST_SNAPSHOT" end
    if body.resolution and body.resolution.targetCorrection ~= nil and type(body.resolution.targetCorrection) ~= "table" then return false, "INVALID_REQUEST_SNAPSHOT" end
    local knownStatus = false
    for _, value in pairs(Dibs.Disputes.GetStatuses()) do if body.status == value then knownStatus = true break end end
    if not knownStatus then return false, "INVALID_REQUEST_SNAPSHOT" end
    for _, reply in ipairs(body.replies) do
      if type(reply) ~= "table" or not validId(reply.replyId) or type(reply.boundedText) ~= "string"
        or #reply.boundedText > 240 or (reply.author ~= "player" and reply.author ~= "officer") then return false, "INVALID_REQUEST_SNAPSHOT" end
    end
    for _, item in ipairs(body.evidence) do if type(item) ~= "table" then return false, "INVALID_REQUEST_SNAPSHOT" end end
    for _, event in ipairs(body.timeline or {}) do if type(event) ~= "table" then return false, "INVALID_REQUEST_SNAPSHOT" end end
    local store = Dibs.GetDB().disputes
    local previous = store.requests[message.requestId]
    if previous and previous.player and member(previous.player.name)
      and member(previous.player.name).memberKey ~= owner.memberKey then return false, "PLAYER_SCOPE_REQUIRED" end
    if not previous and #store.order >= 500 then receipt(message, sender, false, "REQUEST_CAPACITY"); return false, "REQUEST_CAPACITY" end
    if not previous or (tonumber(previous.revision) or 0) <= message.revision then
      -- Re-project received owner bodies instead of trusting private-field absence.
      local request = isOwner and Dibs.Disputes.BuildSafeView(body) or copy(body)
      request.delivery = nil
      request.player = { id = owner.memberKey, name = owner.displayName }
      if isOwner and previous then request.duplicateKey = previous.duplicateKey end
      request.guildScope, request.deliveryAuthority = scope(), copy(current)
      request.replies, request.timeline = request.replies or {}, request.timeline or {}
      store.requests[message.requestId] = request
      if not previous then table.insert(store.order, 1, message.requestId) end
      if isOwner and (not previous or (previous.revision or 0) < message.revision) then notify(request, previous) end
    end
    receipt(message, sender, true)
    return true, "REQUEST_SNAPSHOT_RECEIVED"
  end
  if not admin(actor) or current.memberKey ~= actor.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
  local accepted, reason
  if message.kind == "submit" then
    if type(message.body) ~= "table" or message.body.requestId ~= message.requestId then return false, "INVALID_REQUEST_MESSAGE" end
    accepted, reason = Dibs.Disputes.ReceiveSubmission(message.body, sender.displayName, current)
  elseif message.kind == "reply" then
    local request = requests()[message.requestId]
    if not request or not sameAuthority(request.deliveryAuthority, current) then return false, "REQUEST_AUTHORITY_CHANGED" end
    if type(message.body) ~= "table" or message.body.replyId ~= message.operationId then return false, "INVALID_REQUEST_REPLY" end
    accepted, reason = Dibs.Disputes.ReceiveReply(message.requestId, message.body.text, message.body.replyId, sender.displayName, message.revision)
  else return false, "INVALID_REQUEST_KIND" end
  receipt(message, sender, accepted ~= nil, reason)
  if accepted and message.kind == "reply" and reason ~= "IDEMPOTENT_REPLAY" and Dibs.Notifications then
    Dibs.Notifications.Notify("request-reply:" .. message.operationId, "REQUEST_REPLY", { itemName = message.requestId })
  end
  if accepted then Delivery.OnChanged(requests()[message.requestId]) end
  return accepted ~= nil, reason or "REQUEST_RECEIVED"
end

function Delivery.Snooze(requestId, untilAt)
  local request = Dibs.Disputes.GetRequest(requestId, nil)
  untilAt = tonumber(untilAt)
  if not request then return false, "REQUEST_NOT_FOUND" end
  if not untilAt or untilAt ~= math.floor(untilAt) or untilAt <= time() or untilAt > time() + 31536000 then return false, "INVALID_FOLLOWUP" end
  state().reminders[requestId] = { snoozedUntil = untilAt }
  return true
end

function Delivery.Retry(requestId)
  local request = Dibs.Disputes.GetRequest(requestId, Dibs.GetPlayerName())
  if not request then return false, "REQUEST_NOT_FOUND" end
  local changed = false
  for _, pending in pairs(state().pending) do
    if pending.message.requestId == requestId and pending.message.kind ~= "snapshot" then
      if pending.message.kind == "reply" then
        if request.status ~= "Need information" then return false, "REPLY_NOT_REQUESTED" end
        pending.message.revision = request.revision or 0
      end
      pending.nextAttemptAt = 0
      changed = true
    end
  end
  if not changed then return false, "REQUEST_NOT_PENDING" end
  Delivery.Pump()
  return true
end

function Delivery.CheckReminders()
  if not enabled() then return end
  local actor = localMember()
  if not actor then return end
  local order = Dibs.GetDB().disputes.order
  if #order == 0 then return end
  local localState = state()
  local now = time()
  if localState.lastReminderBatchAt and now - localState.lastReminderBatchAt < REMINDER_BATCH_SECONDS then return end
  local sentCount = 0
  for _ = 1, #order do
    localState.reminderCursor = (localState.reminderCursor or 0) % #order + 1
    local id = order[localState.reminderCursor]
    local request = requests()[id]
    if request then
        local owner, assigned = member(request.player and request.player.name), member(request.assignedTo)
        local relevant = owner and owner.memberKey == actor.memberKey or admin(actor) and assigned and assigned.memberKey == actor.memberKey
        if relevant and request.guildScope == scope() and request.followUpAt and request.followUpAt <= now
          and (request.status == "Open" or request.status == "Under review" or request.status == "Need information") then
          local reminder = localState.reminders[id] or {}
          if (reminder.snoozedUntil or 0) <= now and (reminder.lastAt or 0) + REMINDER_SECONDS <= now then
            local sent = Dibs.Notifications.Notify("request-due:" .. id .. ":" .. tostring(request.revision) .. ":" .. math.floor(now / REMINDER_SECONDS),
              "REQUEST_DUE", { itemName = id })
            if sent then
              reminder.lastAt = now
              localState.reminders[id] = reminder
              localState.lastReminderBatchAt = now
              sentCount = sentCount + 1
              if sentCount >= MAX_REMINDERS_PER_BATCH then break end
            end
          end
        end
    end
  end
end

function Delivery.Pump()
  if not enabled() then return false, "REQUEST_CONTEXT_ISOLATED" end
  Delivery.CheckReminders()
  local current, actor = authority(), localMember()
  if current and actor and current.memberKey == actor.memberKey then
    local order = Dibs.GetDB().disputes.order
    for _ = 1, math.min(8, #order) do
      cursor = cursor % #order + 1
      local request = requests()[order[cursor]]
      if request then Delivery.OnChanged(request) end
    end
  end
  local sentCount = 0
  for _, pending in pairs(state().pending) do
    if sentCount >= 4 then break end
    if (pending.nextAttemptAt or 0) <= time() then
      local message = pending.message
      local status = requestStatus(message.requestId)
      local localDossierChanged = false
      if not message.authority and current and message.kind == "submit" then
        local original = requests()[message.requestId]
        if not original or (original.revision or 0) ~= 1 or original.status ~= "Open" then
          localDossierChanged = true
        else
          message.authority, pending.target = copy(current), current.displayName
          original.deliveryAuthority = copy(current)
        end
      end
      local recipient, reason = Dibs.Sync.GetRequestPeer(pending.target)
      if not sameAuthority(current, message.authority) then recipient, reason = nil, "REQUEST_AUTHORITY_CHANGED" end
      if not current then recipient, reason = nil, "REQUEST_COORDINATOR_UNAVAILABLE" end
      if localDossierChanged then recipient, reason = nil, "REQUEST_LOCAL_DOSSIER_CHANGED" end
      if recipient and message.kind ~= "snapshot" and (not admin(recipient) or current.memberKey ~= recipient.memberKey) then recipient, reason = nil, "CURRENT_COORDINATOR_REQUIRED" end
      if recipient and message.kind == "snapshot" then
        local owner = member(message.owner)
        if not Delivery.CanMutate(requests()[message.requestId] or {}) or not owner
          or (message.projection == "officer" and not admin(recipient))
          or (message.projection == "owner" and owner.memberKey ~= recipient.memberKey) then recipient, reason = nil, "REQUEST_PRIVATE" end
      end
      if recipient then
        local sent
        sent, reason = send(message, recipient.displayName)
        pending.attempts = pending.attempts + 1
        status.state = sent and "sent" or "error"
        status.attempts = pending.attempts
        sentCount = sentCount + 1
      else status.state = "queued" end
      status.reason = reason
      pending.lastState, pending.lastReason = status.state, reason
      pending.nextAttemptAt = time() + RETRY_SECONDS
    end
  end
  return true
end

return Delivery
