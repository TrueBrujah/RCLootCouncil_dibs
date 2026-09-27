local loader = require("helpers.load_addon")

local function load(player)
  player = player or "Tester-Realm"
  local _, dibs = loader.load({ withAce3 = true, wow = {
    playerName = player,
    guildLeader = player == "Tester-Realm",
    guildMembers = { "Tester-Realm", "Owner-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 3, [3] = 1, [4] = 3 },
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
  local sender = opts.sender or "Owner-Realm"
  assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_BEGIN", transferId = transferId, entityType = "PREDIB_REQUEST", entityId = payload.requestId, revision = payload.revision, contentHash = contentHash, payloadHash = opts.payloadHash or dibs.Sync.CalculateContentHash(raw), chunkCount = #chunks }, sender), sender))
  for index, chunk in ipairs(chunks) do
    local ok, reason = dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = index, chunk = chunk }, opts.chunkSender or sender), opts.chunkSender or sender)
    if opts.expectChunkFailure then return ok, reason end
    assert_true(ok, tostring(reason))
  end
  return dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = transferId }, sender), sender)
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

  it("routes shared ledger detail through GUILD while keeping personal detail targeted", function()
    local dibs = load()
    local sentBefore = #dibs.Ace3.libs.comm.sent
    assert_true(dibs.Sync.SendDetail("AWARD_COMMIT", "7:1", 1, "commit-hash", {
      commitHash = "commit-hash", ledgerEpoch = 7, sequence = 1,
    }, "Owner-Realm"))
    assert_equal("GUILD", dibs.Ace3.libs.comm.sent[sentBefore + 1].channel)
    assert_equal("GUILD", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].channel)

    assert_true(dibs.Sync.SendDetail("PREDIB_REQUEST", "b04-request", 1, "request-hash", {
      requestId = "b04-request", revision = 1,
    }, "Owner-Realm"))
    assert_equal("WHISPER", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].channel)
  end)

  it("keeps a targeted fallback for peers without the guild-detail capability", function()
    local dibs = load()
    local hello = remote(dibs, { type = "HELLO" }, "Owner-Realm")
    hello.protocol.capabilities.guildDetail = nil
    assert_true(dibs.Sync.Receive(hello, "Owner-Realm"))

    assert_true(dibs.Sync.SendDetail("AWARD_COMMIT", "7:1", 1, "commit-hash", {
      commitHash = "commit-hash", ledgerEpoch = 7, sequence = 1,
    }, "Owner-Realm"))
    assert_equal("WHISPER", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].channel)
  end)

  it("accepts shared ledger transfers only on the GUILD channel", function()
    local dibs = load()
    local function sendBegin(channel, transferId, legacy)
      local message = remote(dibs, {
        type = "TRANSFER_BEGIN", transferId = transferId, entityType = "AWARD_COMMIT",
        entityId = "7:1", revision = 1, contentHash = "commit-hash",
        payloadHash = "payload-hash", chunkCount = 1,
      }, "Officer-Realm")
      if legacy then message.protocol.capabilities.guildDetail = nil end
      return dibs.Sync.OnAddonMessage("DIBS", dibs.Ace3.Serialize(message), channel, "Officer-Realm")
    end
    local accepted, reason = sendBegin("GUILD", "guild-ledger-transfer")
    assert_true(accepted, tostring(reason))
    accepted, reason = sendBegin("WHISPER", "whisper-ledger-transfer")
    assert_false(accepted)
    assert_equal("INVALID_TRANSPORT_CHANNEL", reason)
    accepted, reason = sendBegin("WHISPER", "legacy-whisper-ledger-transfer", true)
    assert_true(accepted, tostring(reason))
  end)

  it("keeps personal request transfers off the GUILD channel", function()
    local dibs = load()
    local message = remote(dibs, {
      type = "TRANSFER_BEGIN", transferId = "guild-private-request", entityType = "PREDIB_REQUEST",
      entityId = "b04-request", revision = 1, contentHash = "request-hash",
      payloadHash = "payload-hash", chunkCount = 1,
    }, "Owner-Realm")
    local accepted, reason = dibs.Sync.OnAddonMessage("DIBS", dibs.Ace3.Serialize(message), "GUILD", "Owner-Realm")
    assert_false(accepted)
    assert_equal("INVALID_TRANSPORT_CHANNEL", reason)
  end)

  it("keeps direct Vault messages on targeted WHISPER", function()
    local dibs = load()
    local function vaultAck(channel)
      local message = remote(dibs, {
        type = "VAULT_ACK", acquisitionId = "b04-vault", revision = 1, result = "APPLIED",
      }, "Owner-Realm")
      return dibs.Sync.OnAddonMessage("DIBS", dibs.Ace3.Serialize(message), channel, "Owner-Realm")
    end
    local accepted, reason = vaultAck("WHISPER")
    assert_true(accepted, tostring(reason))
    accepted, reason = vaultAck("GUILD")
    assert_false(accepted)
    assert_equal("INVALID_TRANSPORT_CHANNEL", reason)
  end)

  it("accepts award reservation digests on GUILD and rejects WHISPER", function()
    local dibs = load()
    local records = { {
      proposalId = "b04-award-reservation", playerMemberKey = "player-realm", actorMemberKey = "officer-realm",
      seasonId = dibs.GetCurrentSeasonId(), amount = 1, state = "PENDING", updatedAt = time(),
    } }
    local function send(channel, id)
      local message = remote(dibs, {
        type = "AWARD_RESERVATION_DIGEST", entityType = "AWARD_RESERVATION", entityId = "pending",
        revision = 1, records = records, contentHash = dibs.Sync.CalculateContentHash(records), messageId = id,
      }, "Officer-Realm")
      return dibs.Sync.OnAddonMessage("DIBS", dibs.Ace3.Serialize(message), channel, "Officer-Realm")
    end
    local accepted, reason = send("GUILD", "guild-reservation")
    assert_true(accepted, tostring(reason))
    assert_equal(1, #dibs.Sync.GetPendingAwardReservations())
    accepted, reason = send("WHISPER", "whisper-reservation")
    assert_false(accepted)
    assert_equal("INVALID_TRANSPORT_CHANNEL", reason)
  end)

  it("reassembles verified detail and propagates a terminal tombstone", function()
    local dibs = load(); local payload = request(dibs, 2, "fulfilled")
    local ok, reason = transfer(dibs, payload)
    assert_true(ok, tostring(reason)); assert_equal("APPLIED", reason)
    assert_equal("fulfilled", dibs.PreDibs.GetHistory()[1].status)
    assert_not_nil(dibs.GetDB().sync.v2.tombstones[payload.requestId])
  end)

  it("allows officer-to-officer detail relay but rejects it for a player", function()
    local payload = request(load(), 2, "confirmed")
    local officer = load()
    local ok, reason = transfer(officer, payload, { sender = "Officer-Realm" })
    assert_true(ok, tostring(reason))

    local player = load("Player-Realm")
    ok, reason = transfer(player, payload, { sender = "Officer-Realm" })
    assert_false(ok)
    assert_equal("OWNER_MISMATCH", reason)
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

  it("reports channel-test receipt and returns confirmation on the tested channel", function()
    local dibs = load()
    dibs.DeveloperMode.SetEnabled(true)
    local sent, testId = dibs.Sync.StartChannelTest("GUILD")
    assert_true(sent)
    local outgoing = dibs.Ace3.Deserialize(dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].payload)
    assert_equal("CHANNEL_TEST", outgoing.type)
    assert_equal("GUILD", outgoing.testChannel)

    local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "remote-test", testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
    local accepted, reason = dibs.Sync.Receive(inbound, "Officer-Realm", "GUILD")
    assert_true(accepted, tostring(reason))
    local responseMessage = dibs.Ace3.Deserialize(dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].payload)
    assert_equal("CHANNEL_TEST_ACK", responseMessage.type)
    assert_equal("WHISPER", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].channel)
    assert_equal("Officer-Realm", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].target)
    assert_equal("WHISPER", responseMessage.ackTransport)
    assert_equal("CHANNEL_MESSAGE_VALIDATED", responseMessage.reasonCode)

    local acknowledgement = remote(dibs, { type = "CHANNEL_TEST_ACK", testId = testId,
      testChannel = "GUILD", result = "RECEIVED", reasonCode = "CHANNEL_MESSAGE_VALIDATED" }, "Officer-Realm")
    assert_true(dibs.Sync.Receive(acknowledgement, "Officer-Realm", "GUILD"))
    local results = dibs.Sync.GetChannelTestResults()
    local confirmed
    for _, result in ipairs(results) do if result.testId == testId then confirmed = result end end
    assert_not_nil(confirmed)
    assert_equal("ACKNOWLEDGED", confirmed.status)
    assert_equal("CHANNEL_MESSAGE_VALIDATED", confirmed.reasonCode)
  end)

  it("records a received channel probe when Developer Mode suppresses the reply", function()
    local dibs = load()
    local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "dev-mode-off-test",
      testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
    local accepted, reason = dibs.Sync.Receive(inbound, "Officer-Realm", "GUILD")
    assert_false(accepted)
    assert_equal("DEVELOPER_MODE_REQUIRED", reason)

    local received
    for _, result in ipairs(dibs.Sync.GetChannelTestResults()) do
      if result.testId == "dev-mode-off-test" then received = result; break end
    end
    assert_not_nil(received)
    assert_equal("RECEIVE", received.direction)
    assert_equal("IGNORED", received.status)
    assert_equal("DEVELOPER_MODE_REQUIRED", received.reasonCode)
  end)

  it("targets Whisper tests to a guild roster member and explains unavailable group channels", function()
    local dibs = load()
    dibs.DeveloperMode.SetEnabled(true)
    local sent, testId = dibs.Sync.StartChannelTest("WHISPER", "Officer-Realm")
    assert_true(sent)
    local outgoing = dibs.Ace3.Deserialize(dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].payload)
    assert_equal(testId, outgoing.testId)
    assert_equal("WHISPER", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].channel)
    assert_equal("Officer-Realm", dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].target)
    local available, reason = dibs.Sync.GetChannelTestAvailability("RAID")
    assert_false(available)
    assert_equal("NOT_IN_RAID", reason)
  end)

  it("requires guild membership before a player can start a channel test", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { inGuild = false, guildLeader = false } })
    dibs.DeveloperMode.SetEnabled(true)
    local sent, reason = dibs.Sync.StartChannelTest("GUILD")
    assert_false(sent)
    assert_equal("GUILD_MEMBER_REQUIRED", reason)
  end)

  it("rejects channel-test messages received over a different channel", function()
    local dibs = load()
    local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "wrong-channel-test",
      testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
    local accepted, reason = dibs.Sync.Receive(inbound, "Officer-Realm", "OFFICER")
    assert_false(accepted)
    assert_equal("CHANNEL_MISMATCH", reason)
    local results = dibs.Sync.GetChannelTestResults()
    assert_equal("CHANNEL_MISMATCH_EXPECTED_GUILD", results[1].reasonCode)
  end)

  it("accepts a channel test from a regular guild member and returns confirmation", function()
    local dibs = load()
    dibs.DeveloperMode.SetEnabled(true)
    local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "unauthorized-test",
      testChannel = "GUILD", startedAt = time() }, "Player-Realm")
    local accepted, reason = dibs.Sync.Receive(inbound, "Player-Realm", "GUILD")
    assert_true(accepted, tostring(reason))
    assert_equal("CHANNEL_TEST_ACK_QUEUED", reason)
    local acknowledgement = dibs.Ace3.Deserialize(dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].payload)
    assert_equal("CHANNEL_TEST_ACK", acknowledgement.type)
    assert_equal("RECEIVED", acknowledgement.result)
    assert_equal("CHANNEL_MESSAGE_VALIDATED", acknowledgement.reasonCode)
    local results = dibs.Sync.GetChannelTestResults()
    assert_equal("ACK_QUEUED", results[1].status)
    assert_equal("CHANNEL_MESSAGE_VALIDATED", results[1].reasonCode)
  end)

  it("lets an opted-in player answer an officer probe privately and only once", function()
    local dibs = load()
    dibs.Permissions.GetGuildRole = function() return "player" end
    dibs.DeveloperMode.SetEnabled(true)
    local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "player-test",
      testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
    local sentBefore = #dibs.Ace3.libs.comm.sent
    local accepted, reason = dibs.Sync.Receive(inbound, "Officer-Realm", "GUILD")
    assert_true(accepted, tostring(reason))
    assert_equal("CHANNEL_TEST_ACK_QUEUED", reason)
    assert_equal(sentBefore + 1, #dibs.Ace3.libs.comm.sent)
    local sent = dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent]
    assert_equal("WHISPER", sent.channel)
    assert_equal("Officer-Realm", sent.target)
    local response = dibs.Ace3.Deserialize(sent.payload)
    assert_equal("CHANNEL_TEST_ACK", response.type)
    assert_equal("WHISPER", response.ackTransport)
    local duplicate = remote(dibs, { type = "CHANNEL_TEST", testId = "player-test",
      testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
    local duplicateAccepted, duplicateReason = dibs.Sync.Receive(duplicate, "Officer-Realm", "GUILD")
    assert_true(duplicateAccepted)
    assert_equal("CHANNEL_TEST_DUPLICATE", duplicateReason)
    assert_equal(sentBefore + 1, #dibs.Ace3.libs.comm.sent)
  end)

  it("aggregates unique private ACKs from several players for one ping", function()
    local dibs = load()
    dibs.DeveloperMode.SetEnabled(true)
    local sent, testId = dibs.Sync.StartChannelTest("GUILD")
    assert_true(sent)
    local timeoutCallback = dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].callback
    for _, player in ipairs({ "Officer-Realm", "Player-Realm" }) do
      local acknowledgement = remote(dibs, { type = "CHANNEL_TEST_ACK", testId = testId,
        testChannel = "GUILD", ackTransport = "WHISPER", result = "RECEIVED",
        reasonCode = "CHANNEL_MESSAGE_VALIDATED" }, player)
      assert_true(dibs.Sync.Receive(acknowledgement, player, "WHISPER"))
    end
    local results = dibs.Sync.GetChannelTestResults()
    local combined
    for _, result in ipairs(results) do if result.testId == testId then combined = result end end
    assert_not_nil(combined)
    assert_equal("ACKNOWLEDGED", combined.status)
    assert_equal(2, #combined.responders)
    assert_equal("Officer-Realm", combined.responders[1].player)
    assert_equal("Player-Realm", combined.responders[2].player)
    local duplicate = remote(dibs, { type = "CHANNEL_TEST_ACK", testId = testId,
      testChannel = "GUILD", ackTransport = "WHISPER", result = "RECEIVED",
      reasonCode = "CHANNEL_MESSAGE_VALIDATED" }, "Player-Realm")
    local accepted, reason = dibs.Sync.Receive(duplicate, "Player-Realm", "WHISPER")
    assert_true(accepted)
    assert_equal("CHANNEL_TEST_ACK_DUPLICATE", reason)
    assert_equal(2, #dibs.Sync.GetChannelTestResults()[1].responders)
    timeoutCallback()
    local closed
    for _, result in ipairs(dibs.Sync.GetChannelTestResults()) do if result.testId == testId then closed = result end end
    assert_not_nil(closed)
    assert_false(closed.ackWindowOpen)
    assert_true(closed.ackWindowClosed)
  end)

  it("limits diagnostic pongs from one member to six per minute", function()
    local dibs = load()
    _G.time = function() return 1700000000 end
    dibs.Permissions.GetGuildRole = function() return "player" end
    dibs.DeveloperMode.SetEnabled(true)
    local sentBefore = #dibs.Ace3.libs.comm.sent
    for index = 1, 6 do
      local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "rate-test-" .. index,
        testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
      assert_true(dibs.Sync.Receive(inbound, "Officer-Realm", "GUILD"))
    end
    local blocked = remote(dibs, { type = "CHANNEL_TEST", testId = "rate-test-7",
      testChannel = "GUILD", startedAt = time() }, "Officer-Realm")
    local accepted, reason = dibs.Sync.Receive(blocked, "Officer-Realm", "GUILD")
    assert_false(accepted)
    assert_equal("CHANNEL_TEST_RATE_LIMITED", reason)
    assert_equal(sentBefore + 6, #dibs.Ace3.libs.comm.sent)
  end)

  it("bounds the number of local channel tests waiting for responses", function()
    local dibs = load()
    dibs.DeveloperMode.SetEnabled(true)
    for _ = 1, 16 do assert_true(dibs.Sync.StartChannelTest("GUILD")) end
    local sent, reason = dibs.Sync.StartChannelTest("GUILD")
    assert_false(sent)
    assert_equal("CHANNEL_TEST_PENDING_LIMIT", reason)
  end)

  it("sends custom-channel confirmations to the locally joined channel", function()
    local dibs = load()
    _G.GetChannelName = function(name) return name == "DibsTest" and 4 or 0 end
    dibs.DeveloperMode.SetEnabled(true)
    local sent, testId = dibs.Sync.StartChannelTest("CHANNEL", "DibsTest")
    assert_true(sent)
    local outgoing = dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent]
    assert_equal("CHANNEL", outgoing.channel)
    assert_equal(4, outgoing.target)
    local inbound = remote(dibs, { type = "CHANNEL_TEST", testId = "custom-test",
      testChannel = "CHANNEL", channelName = "DibsTest", startedAt = time() }, "Officer-Realm")
    assert_true(dibs.Sync.Receive(inbound, "Officer-Realm", "CHANNEL"))
    local acknowledgement = dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent]
    assert_equal("WHISPER", acknowledgement.channel)
    assert_equal("Officer-Realm", acknowledgement.target)
    local ackMessage = dibs.Ace3.Deserialize(acknowledgement.payload)
    assert_equal("CHANNEL_TEST_ACK", ackMessage.type)
    assert_equal("WHISPER", ackMessage.ackTransport)
    assert_true(dibs.Sync.Receive(remote(dibs, { type = "CHANNEL_TEST_ACK", testId = testId,
      testChannel = "CHANNEL", result = "RECEIVED", reasonCode = "CHANNEL_MESSAGE_VALIDATED" }, "Officer-Realm"),
      "Officer-Realm", "CHANNEL"))
  end)
end)
