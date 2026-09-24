local loader = require("helpers.load_addon")

local function load()
  local _, dibs = loader.load({ withAce3 = true, wow = {
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Owner-Realm", "Officer-Realm" },
    guildRankIndices = { [1] = 0, [2] = 3, [3] = 1 },
  } })
  return dibs
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm = sender
  envelope.senderMemberKey = string.lower(sender)
  return envelope
end

local function request(dibs, revision, status)
  return {
    requestId = "b04-request", playerName = "Owner-Realm", itemID = 21101,
    itemName = "B04 Item", seasonId = dibs.GetCurrentSeasonId(), status = status or "confirmed",
    revision = revision or 1, createdAt = 100, updatedAt = 100 + (revision or 1),
  }
end

local function transfer(dibs, payload, opts)
  opts = opts or {}; local raw = assert(dibs.Ace3.Serialize(payload)); local contentHash = dibs.Sync.CalculateRequestHash(payload)
  local chunks = opts.chunks or { raw }; local transferId = opts.transferId or "b04-transfer"
  assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_BEGIN", transferId = transferId, entityType = "PREDIB_REQUEST", entityId = payload.requestId, revision = payload.revision, contentHash = contentHash, payloadHash = opts.payloadHash or dibs.Sync.CalculateContentHash(raw), chunkCount = #chunks }, "Owner-Realm"), "Owner-Realm"))
  for index, chunk in ipairs(chunks) do
    local ok, reason = dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = index, chunk = chunk }, opts.chunkSender or "Owner-Realm"), opts.chunkSender or "Owner-Realm")
    if opts.expectChunkFailure then return ok, reason end
    assert_true(ok, tostring(reason))
  end
  return dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = transferId }, "Owner-Realm"), "Owner-Realm")
end

describe("B04 V2 transport", function()
  it("sends bounded GUILD digests and fetches missing detail by WHISPER", function()
    local dibs = load(); local payload = request(dibs, 2, "cancelled")
    local digest = remote(dibs, { type = "DIGEST", entityType = "PREDIB_INDEX", entityId = "current", revision = 1, contentHash = "index", index = { { requestId = payload.requestId, revision = payload.revision, contentHash = dibs.Sync.CalculateRequestHash(payload), terminal = true } } }, "Officer-Realm")
    local ok, reason = dibs.Sync.Receive(digest, "Officer-Realm")
    assert_true(ok); assert_equal("DETAIL_REQUESTED", reason); assert_true(dibs.Sync.IsSyncBehind())
    local sent = dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent]
    assert_equal("WHISPER", sent.channel)
  end)

  it("reassembles verified detail and propagates a terminal tombstone", function()
    local dibs = load(); local payload = request(dibs, 2, "fulfilled")
    local ok, reason = transfer(dibs, payload)
    assert_true(ok, tostring(reason)); assert_equal("APPLIED", reason)
    assert_equal("fulfilled", dibs.PreDibs.GetHistory()[1].status)
    assert_not_nil(dibs.GetDB().sync.v2.tombstones[payload.requestId])
  end)

  it("handles idempotent, conflict, and stale request revisions deterministically", function()
    local dibs = load(); local first = request(dibs, 2, "cancelled")
    assert_true(transfer(dibs, first))
    assert_true(transfer(dibs, first, { transferId = "b04-replay" }))
    local changed = request(dibs, 2, "invalidated")
    local ok, reason = transfer(dibs, changed, { transferId = "b04-conflict" })
    assert_false(ok); assert_equal("REQUEST_CONFLICT", reason)
    local stale = request(dibs, 1, "confirmed")
    ok, reason = transfer(dibs, stale, { transferId = "b04-stale" })
    assert_false(ok); assert_equal("STALE_REVISION", reason)
  end)

  it("rejects malformed, wrong-guild, wrong-sender, and unsupported-major envelopes", function()
    local dibs = load()
    assert_false(dibs.Sync.Receive({}, "Owner-Realm"))
    local wrongGuild = remote(dibs, { type = "HELLO" }, "Owner-Realm"); wrongGuild.guildKey = "wrong"
    assert_false(dibs.Sync.Receive(wrongGuild, "Owner-Realm"))
    local wrongSender = remote(dibs, { type = "HELLO" }, "Owner-Realm"); wrongSender.senderMemberKey = "officer-realm"
    assert_false(dibs.Sync.Receive(wrongSender, "Owner-Realm"))
    local future = remote(dibs, { type = "HELLO" }, "Owner-Realm"); future.protocol.major = 99
    assert_false(dibs.Sync.Receive(future, "Owner-Realm"))
  end)

  it("accepts reordered chunks but rejects missing, conflicting, altered, and cross-sender transfers", function()
    local dibs = load(); local payload = request(dibs, 2, "cancelled"); local raw = assert(dibs.Ace3.Serialize(payload)); local first, second = raw:sub(1, 2), raw:sub(3)
    local contentHash = dibs.Sync.CalculateRequestHash(payload)
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_BEGIN", transferId = "reordered", entityType = "PREDIB_REQUEST", entityId = payload.requestId, revision = payload.revision, contentHash = contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 2 }, "Owner-Realm"), "Owner-Realm"))
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = "reordered", chunkIndex = 2, chunk = second }, "Owner-Realm"), "Owner-Realm"))
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = "reordered", chunkIndex = 1, chunk = first }, "Owner-Realm"), "Owner-Realm"))
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = "reordered" }, "Owner-Realm"), "Owner-Realm"))
    local missing = request(dibs, 3, "invalidated")
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_BEGIN", transferId = "missing", entityType = "PREDIB_REQUEST", entityId = missing.requestId, revision = 3, contentHash = dibs.Sync.CalculateRequestHash(missing), payloadHash = "bad", chunkCount = 2 }, "Owner-Realm"), "Owner-Realm"))
    assert_false(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = "missing" }, "Owner-Realm"), "Owner-Realm"))
    local bad, why = transfer(dibs, missing, { transferId = "sender", chunkSender = "Officer-Realm", expectChunkFailure = true })
    assert_false(bad); assert_equal("INVALID_TRANSFER_CHUNK", why)
  end)

  it("tracks received chunks so incomplete transfers expose actionable progress", function()
    local dibs = load(); local payload = request(dibs, 4, "cancelled")
    local raw = assert(dibs.Ace3.Serialize(payload)); local first, second = raw:sub(1, 2), raw:sub(3)
    local begin = remote(dibs, { type = "TRANSFER_BEGIN", transferId = "progress", entityType = "PREDIB_REQUEST",
      entityId = payload.requestId, revision = payload.revision, contentHash = dibs.Sync.CalculateRequestHash(payload),
      payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 2 }, "Owner-Realm")
    assert_true(dibs.Sync.Receive(begin, "Owner-Realm"))
    assert_equal(0, dibs.runtime.v2Transfers.progress.receivedChunks)
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = "progress", chunkIndex = 1, chunk = first }, "Owner-Realm"), "Owner-Realm"))
    assert_equal(1, dibs.runtime.v2Transfers.progress.receivedChunks)
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = "progress", chunkIndex = 1, chunk = first }, "Owner-Realm"), "Owner-Realm"))
    assert_equal(1, dibs.runtime.v2Transfers.progress.receivedChunks)
    local ok, reason = dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = "progress" }, "Owner-Realm"), "Owner-Realm")
    assert_false(ok); assert_equal("MISSING_TRANSFER_CHUNK", reason)
  end)

  it("locks a transfer ID to its first sender and rejects unsupported detail entities", function()
    local dibs = load(); local payload = request(dibs, 2, "cancelled")
    local begin = { type = "TRANSFER_BEGIN", transferId = "locked", entityType = "PREDIB_REQUEST", entityId = payload.requestId, revision = payload.revision, contentHash = dibs.Sync.CalculateRequestHash(payload), payloadHash = "hash", chunkCount = 1 }
    assert_true(dibs.Sync.Receive(remote(dibs, begin, "Owner-Realm"), "Owner-Realm"))
    assert_equal("IDEMPOTENT_TRANSFER_BEGIN", select(2, dibs.Sync.Receive(remote(dibs, begin, "Owner-Realm"), "Owner-Realm")))
    local blocked, reason = dibs.Sync.Receive(remote(dibs, begin, "Officer-Realm"), "Officer-Realm")
    assert_false(blocked); assert_equal("TRANSFER_ID_CONFLICT", reason)
    local unsupported = { type = "TRANSFER_BEGIN", transferId = "unsupported", entityType = "LEDGER_EVENT", entityId = "nope", revision = 1, contentHash = "x", payloadHash = "x", chunkCount = 1 }
    blocked, reason = dibs.Sync.Receive(remote(dibs, unsupported, "Owner-Realm"), "Owner-Realm")
    assert_false(blocked); assert_equal("UNSUPPORTED_ENTITY", reason)
  end)

  it("bounds replays, refuses ledger detail, and clears SYNC_BEHIND only after verified recovery", function()
    local dibs = load(); local hello = remote(dibs, { type = "HELLO" }, "Officer-Realm")
    assert_true(dibs.Sync.Receive(hello, "Officer-Realm")); assert_equal("IDEMPOTENT_MESSAGE_REPLAY", select(2, dibs.Sync.Receive(hello, "Officer-Realm")))
    local forbidden = remote(dibs, { type = "LEDGER_DIGEST", entityType = "LEDGER", entityId = "x", revision = 1, contentHash = "x", nextSeq = 2 }, "Officer-Realm")
    assert_false(dibs.Sync.Receive(forbidden, "Officer-Realm")); assert_true(dibs.Sync.IsSyncBehind())
    assert_true(transfer(dibs, request(dibs, 2, "cancelled"), { transferId = "recover" })); assert_false(dibs.Sync.IsSyncBehind())
  end)

  it("models cutover states without allowing B04 to enforce V2", function()
    local dibs = load(); assert_equal("LEGACY_LOCAL", dibs.Sync.GetProtocolState())
    assert_true(dibs.Sync.SetProtocolState("CUTOVER_PREPARED")); assert_equal("CUTOVER_PREPARED", dibs.Sync.GetProtocolState())
    local ok, reason = dibs.Sync.SetProtocolState("V2_ENFORCED")
    assert_false(ok); assert_equal("GOVERNANCE_CUTOVER_REQUIRED", reason)
  end)

  it("bounds transfer capacity and keeps all distributed ledger state local-only", function()
    local dibs = load(); local payload = request(dibs, 2, "cancelled")
    -- The WoW test clock advances once per API call; transfers use wall-clock TTL
    -- in-game, so keep this capacity test within one actual second.
    local originalTime = time; _G.time = function() return 1000 end
    for index = 1, 8 do
      local ok = dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_BEGIN", transferId = "capacity-" .. index, entityType = "PREDIB_REQUEST", entityId = payload.requestId, revision = 2, contentHash = dibs.Sync.CalculateRequestHash(payload), payloadHash = "hash", chunkCount = 1 }, "Owner-Realm"), "Owner-Realm")
      assert_true(ok)
    end
    local ok, reason = dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_BEGIN", transferId = "capacity-over", entityType = "PREDIB_REQUEST", entityId = payload.requestId, revision = 2, contentHash = dibs.Sync.CalculateRequestHash(payload), payloadHash = "hash", chunkCount = 1 }, "Owner-Realm"), "Owner-Realm")
    _G.time = originalTime
    assert_false(ok, "expected TRANSFER_CAPACITY, got " .. tostring(reason)); assert_equal("TRANSFER_CAPACITY", reason)
    local before = #dibs.Ledger.GetAllTransactions()
    assert_false(dibs.Sync.Receive(remote(dibs, { type = "LEDGER_DIGEST", entityType = "LEDGER", entityId = "none", revision = 1, contentHash = "LOCAL_ONLY", nextSeq = 1 }, "Officer-Realm"), "Officer-Realm"))
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("requires both AceComm and AceSerializer and rejects live loot payloads", function()
    local dibs = load(); dibs.Ace3.libs.serializer = nil; dibs.Sync.transportRegistered = false
    local sent, reason = dibs.Sync.Send({ type = "HELLO" }, "GUILD")
    assert_false(sent); assert_equal("SYNC_UNAVAILABLE", reason)
    local _, fresh = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local live, liveReason = fresh.Sync.Send({ type = "DIGEST", candidates = { "secret" } }, "GUILD")
    assert_false(live); assert_equal("FORBIDDEN_LIVE_LOOT_DATA", liveReason)
  end)
end)
