local loader = require("helpers.load_addon")

local roster = { "GameMaster-Realm", "Officer-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "GameMaster-Realm",
    guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  return envelope
end

local function messages(dibs, messageType)
  local result = {}
  for _, sent in ipairs(dibs.Ace3.libs.comm.sent) do
    local message = dibs.Ace3.Deserialize(sent.payload)
    if message.type == messageType then result[#result + 1] = message end
  end
  return result
end

local function transfer(dibs, entityType, record, revision, sender)
  sender = sender or "GameMaster-Realm"
  local raw = assert(dibs.Ace3.Serialize(record))
  local id = entityType .. "-" .. tostring(revision)
  local contentHash = entityType == "PREDIB_REQUEST" and dibs.Sync.CalculateRequestHash(record) or record.contentHash
  local entityId = entityType == "PREDIB_REQUEST" and record.requestId or tostring(revision)
  for _, message in ipairs({
    { type = "TRANSFER_BEGIN", transferId = id, entityType = entityType, entityId = entityId,
      revision = revision, contentHash = contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1 },
    { type = "TRANSFER_CHUNK", transferId = id, chunkIndex = 1, chunk = raw },
    { type = "TRANSFER_END", transferId = id, entityType = entityType },
  }) do
    local ok, reason = dibs.Sync.Receive(remote(dibs, message, sender), sender)
    assert_true(ok, tostring(reason))
  end
end

local function adopt(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "repair test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  }))
end

describe("GM and Officer guild recovery", function()
  it("lets an Officer request peer and guild recovery without a historical baseline", function()
    local dibs = load("Officer-Realm")
    assert_nil(dibs.HistoricalBaseline.GetBaseline())
    assert_true(dibs.Sync.RepairPeer("Player"))
    assert_true(dibs.Sync.RepairGuild())
    local requests = messages(dibs, "SYNC_REPAIR_REQUEST")
    assert_equal(2, #requests)
    assert_equal("PEER", requests[1].scope)
    assert_equal("GUILD", requests[2].scope)
    assert_true(requests[1].protocol.capabilities.guildRepair)
    local ok, reason = dibs.Sync.RepairGuild()
    assert_false(ok)
    assert_equal("REPAIR_COOLDOWN", reason)
    assert_true(#messages(dibs, "HELLO") > 0, "Source must also advertise its data")
  end)

  it("rejects ordinary senders, forged identities, wrong guilds and wrong channels", function()
    local dibs = load("Player-Realm")
    dibs.Ace3.libs.comm.sent = {}
    local request = { type = "SYNC_REPAIR_REQUEST", requestId = "repair", scope = "GUILD" }
    local ok, reason = dibs.Sync.Receive(remote(dibs, request, "Player-Realm"), "Player-Realm", "GUILD")
    assert_false(ok)
    assert_equal("OFFICER_REQUIRED", reason)
    ok, reason = dibs.Sync.Receive(remote(dibs, request, "Officer-Realm"), "Player-Realm", "GUILD")
    assert_false(ok)
    assert_equal("SENDER_MISMATCH", reason)
    local wrongGuild = remote(dibs, request, "Officer-Realm")
    wrongGuild.guildKey = "another-guild"
    ok, reason = dibs.Sync.Receive(wrongGuild, "Officer-Realm", "GUILD")
    assert_false(ok)
    assert_equal("GUILD_SCOPE_MISMATCH", reason)
    ok, reason = dibs.Sync.Receive(remote(dibs, request, "Officer-Realm"), "Officer-Realm", "WHISPER")
    assert_false(ok)
    assert_equal("INVALID_SYNC_CHANNEL", reason)
    assert_equal(0, #messages(dibs, "SYNC_REPAIR_ACK"))
    assert_equal(0, #messages(dibs, "HELLO"))
    ok, reason = dibs.Sync.RepairGuild()
    assert_false(ok)
    assert_equal("OFFICER_REQUIRED", reason)
  end)

  it("starts bounded recovery on a member without erasing conflicts or ledger data", function()
    local dibs = load("Player-Realm")
    dibs.Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
    local before = dibs.DeepCopy(dibs.Ledger.GetAllTransactions())
    local request = remote(dibs, { type = "SYNC_REPAIR_REQUEST", requestId = "repair-guild", scope = "GUILD" }, "Officer-Realm")
    assert_true(dibs.Sync.Receive(request, "Officer-Realm", "GUILD"))
    local replies = messages(dibs, "SYNC_REPAIR_ACK")
    assert_equal(1, #replies)
    assert_equal("STARTED", replies[1].result)
    assert_true(replies[1].report.syncBehind)
    assert_equal("CANONICAL_ROOT_CONFLICT", replies[1].report.syncReason)
    assert_equal(#before, #dibs.Ledger.GetAllTransactions())
    local announcements = #messages(dibs, "HELLO")
    assert_true(announcements > 0)
    assert_true(dibs.Sync.Receive(request, "Officer-Realm", "GUILD"))
    assert_equal(announcements, #messages(dibs, "HELLO"), "Replay must not restart recovery")
    request = remote(dibs, { type = "SYNC_REPAIR_REQUEST", requestId = "another-repair", scope = "GUILD" }, "GameMaster-Realm")
    assert_true(dibs.Sync.Receive(request, "GameMaster-Realm", "GUILD"))
    replies = messages(dibs, "SYNC_REPAIR_ACK")
    assert_equal("BLOCKED", replies[#replies].result)
    assert_equal("REPAIR_COOLDOWN", replies[#replies].reasonCode)
  end)

  it("blocks combat, sandbox and Independent Raid without emitting production requests", function()
    local dibs = load("Officer-Realm")
    local previousCombat = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    local ok, reason = dibs.Sync.RepairGuild()
    _G.InCombatLockdown = previousCombat
    assert_false(ok)
    assert_equal("IN_COMBAT", reason)
    local sandboxActive = dibs.DeveloperSandbox.IsActive
    dibs.DeveloperSandbox.IsActive = function() return true end
    ok, reason = dibs.Sync.RepairGuild()
    dibs.DeveloperSandbox.IsActive = sandboxActive
    assert_false(ok)
    assert_equal("SANDBOX_ACTIVE", reason)
    local independentActive = dibs.IndependentRaid.IsSessionActive
    dibs.IndependentRaid.IsSessionActive = function() return true end
    ok, reason = dibs.Sync.RepairPeer("Player")
    dibs.IndependentRaid.IsSessionActive = independentActive
    assert_false(ok)
    assert_equal("INDEPENDENT_RAID_ACTIVE", reason)
    assert_equal(0, #messages(dibs, "SYNC_REPAIR_REQUEST"))
  end)

  it("accepts only matching recovery replies and labels them as startup, not completion", function()
    local dibs = load("Officer-Realm")
    local sent, id = dibs.Sync.RepairPeer("Player")
    assert_true(sent)
    local reply = { type = "SYNC_REPAIR_ACK", requestId = id, result = "STARTED",
      report = { displayName = "Player-Realm", syncBehind = true, syncReason = "SEASON_CATALOG_PARENT_MISSING" } }
    local ok, reason = dibs.Sync.Receive(remote(dibs, reply, "GameMaster-Realm"), "GameMaster-Realm", "WHISPER")
    assert_false(ok)
    assert_equal("UNSOLICITED_REPAIR_ACK", reason)
    assert_true(dibs.Sync.Receive(remote(dibs, reply, "Player-Realm"), "Player-Realm", "WHISPER"))
    local probe = dibs.Sync.GetPeerSyncProbe("Player")
    assert_equal("STARTED", probe.repair.result)
    assert_true(probe.report.syncBehind)
    assert_not_nil(dibs.Sync.FormatSyncProbeReport(probe):find("repair=STARTED", 1, true))
  end)

  it("reports receiver combat and startup failures as blocked", function()
    local dibs = load("Player-Realm")
    local previousCombat = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    local accepted, reason = dibs.Sync.Receive(remote(dibs, {
      type = "SYNC_REPAIR_REQUEST", requestId = "combat", scope = "PEER",
    }, "Officer-Realm"), "Officer-Realm", "WHISPER")
    _G.InCombatLockdown = previousCombat
    assert_true(accepted, tostring(reason))
    local replies = messages(dibs, "SYNC_REPAIR_ACK")
    assert_equal("BLOCKED", replies[#replies].result)
    assert_equal("IN_COMBAT", replies[#replies].reasonCode)
    local resync = dibs.Sync.RequestResync
    dibs.Sync.RequestResync = function() return 0, false, "TEST_STARTUP_FAILURE" end
    accepted, reason = dibs.Sync.Receive(remote(dibs, {
      type = "SYNC_REPAIR_REQUEST", requestId = "failure", scope = "PEER",
    }, "Officer-Realm"), "Officer-Realm", "WHISPER")
    dibs.Sync.RequestResync = resync
    assert_true(accepted, tostring(reason))
    replies = messages(dibs, "SYNC_REPAIR_ACK")
    assert_equal("BLOCKED", replies[#replies].result)
    assert_equal("TEST_STARTUP_FAILURE", replies[#replies].reasonCode)
  end)

  it("reports missing peer support and transport failures instead of claiming recovery", function()
    local dibs = load("Officer-Realm")
    local hello = remote(dibs, { type = "HELLO" }, "Player-Realm")
    hello.protocol.capabilities.guildRepair = nil
    assert_true(dibs.Sync.Receive(hello, "Player-Realm"))
    local ok, reason = dibs.Sync.RepairPeer("Player")
    assert_false(ok)
    assert_equal("PEER_UPDATE_REQUIRED", reason)
    local send = dibs.Ace3.SendComm
    dibs.Ace3.SendComm = function() return false, "TEST_TRANSPORT_FAILURE" end
    ok, reason = dibs.Sync.RepairGuild()
    dibs.Ace3.SendComm = send
    assert_false(ok)
    assert_equal("TEST_TRANSPORT_FAILURE", reason)
    assert_true(dibs.Sync.RepairGuild(), "Failed send must not consume cooldown")
  end)
end)

-- Only one addon instance can be live at a time, so each hop reloads a client from
-- its persisted SavedVariables and delivers the other client's real outgoing messages.
local function outbox(dibs)
  local result = {}
  for _, sent in ipairs(dibs.Ace3.libs.comm.sent) do
    local message = dibs.DeepCopy(dibs.Ace3.Deserialize(sent.payload))
    if message.type == "TRANSFER_CHUNK" then
      message.decodedChunk = dibs.DeepCopy(dibs.Ace3.Deserialize(message.chunk))
    end
    result[#result + 1] = { message = message, channel = sent.channel, target = sent.target }
  end
  return result
end

-- The test serializer encodes by per-instance handle, so chunks are re-encoded for
-- the receiver and the begin hash is updated to match, as a real wire would carry.
local function deliver(dibs, queue, sender, recipient)
  local raws = {}
  for _, entry in ipairs(queue) do
    if entry.message.type == "TRANSFER_CHUNK" then
      raws[entry.message.transferId] = assert(dibs.Ace3.Serialize(entry.message.decodedChunk))
    end
  end
  for _, entry in ipairs(queue) do
    if entry.channel == "GUILD" or entry.target == recipient or entry.target == recipient:match("^[^-]+") then
      local message = dibs.DeepCopy(entry.message)
      local raw = raws[message.transferId]
      if raw and message.type == "TRANSFER_BEGIN" then message.payloadHash = dibs.Sync.CalculateContentHash(raw) end
      if raw and message.type == "TRANSFER_CHUNK" then message.chunk, message.decodedChunk = raw, nil end
      dibs.Sync.Receive(message, sender, entry.channel)
    end
  end
end

describe("End-to-end guild repair between two clients", function()
  it("restores a stale member from an Officer request and reports the result back", function()
    local gm = load("GameMaster-Realm")
    adopt(gm)
    local memberSaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    for index = 1, 3 do
      assert_not_nil(gm.Seasons.Create("Repair Season " .. index))
      assert_true(gm.Seasons.PublishCatalog(nil, "SEASON_CREATE"))
    end
    assert_true(gm.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true }, "repair"))
    assert_true(gm.OperationalPolicy.Change(nil, { allowPublicPreDibs = false }, "repair"))
    local predib = {
      requestId = "e2e-player-request", playerName = "Player-Realm", itemID = 21102,
      itemName = "Restored Item", seasonId = gm.GetCurrentSeasonId(), status = "confirmed",
      revision = 2, createdAt = 100, updatedAt = 200, modeAtCreation = "WILD_OPEN",
      internalNote = "Officer-only synthetic note",
    }
    assert_not_nil(gm.PreDibs.ApplyVerifiedSyncRecord(predib, "Player-Realm"))
    local expectedCatalogHash = gm.Seasons.GetCatalogState().hash
    local expectedPolicyHash = gm.OperationalPolicy.GetState().hash
    gm.Ace3.libs.comm.sent = {}
    local started, requestId = gm.Sync.RepairGuild()
    assert_true(started)
    local gmQueue, gmRuntime = outbox(gm), gm.DeepCopy(gm.runtime.syncRepair)
    local gmSaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)

    local member = load("Player-Realm", memberSaved)
    local before, beforeIds = member.DeepCopy(member.Ledger.GetAllTransactions()), {}
    for _, tx in ipairs(before) do beforeIds[tx.transactionId] = true end
    local ackSeen, hops = false, 0
    repeat
      hops = hops + 1
      member.Ace3.libs.comm.sent = {}
      deliver(member, gmQueue, "GameMaster-Realm", "Player-Realm")
      local memberQueue = outbox(member)
      for _, entry in ipairs(memberQueue) do
        if entry.message.type == "SYNC_REPAIR_ACK" then
          ackSeen = true
          assert_equal(requestId, entry.message.requestId)
          assert_equal("STARTED", entry.message.result)
          assert_equal("WHISPER", entry.channel)
        end
      end
      memberSaved = member.DeepCopy(_G.RCLootCouncil_dibsDB)

      gm = load("GameMaster-Realm", gmSaved)
      gm.runtime.syncRepair = gm.DeepCopy(gmRuntime) -- same live Officer session
      gm.Ace3.libs.comm.sent = {}
      deliver(gm, memberQueue, "Player-Realm", "GameMaster-Realm")
      gmQueue, gmRuntime = outbox(gm), gm.DeepCopy(gm.runtime.syncRepair)
      local probe = gm.Sync.GetPeerSyncProbe("Player")
      gmSaved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)

      member = load("Player-Realm", memberSaved)
      local caughtUp = member.Seasons.GetCatalogState().hash == expectedCatalogHash
        and member.OperationalPolicy.GetState().hash == expectedPolicyHash
        and member.PreDibs.GetHistory()[1] ~= nil
      if hops == 1 then
        assert_true(ackSeen, "Member must acknowledge the Officer request")
        assert_not_nil(probe, "Officer must record the member's acknowledgement")
        assert_equal("STARTED", probe.repair.result)
        assert_not_nil(gm.Sync.FormatSyncProbeReport(probe):find("repair=STARTED", 1, true))
      end
    until caughtUp or hops >= 12

    assert_true(hops < 12, "Repair must converge")
    assert_equal(3, member.Seasons.GetCatalogState().catalogRevision)
    assert_equal(expectedCatalogHash, member.Seasons.GetCatalogState().hash)
    assert_equal(expectedPolicyHash, member.OperationalPolicy.GetState().hash)
    local restored = member.PreDibs.GetHistory()[1]
    assert_equal(predib.requestId, restored.requestId)
    assert_equal("confirmed", restored.status)
    assert_nil(restored.internalNote)
    local afterIds = {}
    for _, tx in ipairs(member.Ledger.GetAllTransactions()) do afterIds[tx.transactionId] = tx end
    for _, tx in ipairs(before) do assert_not_nil(afterIds[tx.transactionId], "Repair must not erase ledger history") end
    for id, tx in pairs(afterIds) do
      if not beforeIds[id] then assert_equal("SEASON_ALLOCATION", tx.type) end
    end
    assert_equal(#before + 3, #member.Ledger.GetAllTransactions())
    member.Sync.RecheckSyncBehind()
    assert_false(member.Sync.IsSyncBehind())
  end)
end)

describe("Recovery of missing revision chains", function()
  it("restores a returning player's own Pre-Dib from an Officer copy without exposing private metadata", function()
    local officer = load("Officer-Realm")
    local saved = officer.DeepCopy(_G.RCLootCouncil_dibsDB)
    local request = {
      requestId = "missing-player-request", playerName = "Player-Realm", itemID = 21101,
      itemName = "Recovered Item", seasonId = officer.GetCurrentSeasonId(), status = "confirmed",
      revision = 2, createdAt = 100, updatedAt = 200, modeAtCreation = "WILD_OPEN",
      internalNote = "Officer-only synthetic note",
    }
    assert_not_nil(officer.PreDibs.ApplyVerifiedSyncRecord(request, "Player-Realm"))
    local manifest = officer.Sync.BuildManifest()
    officer.Ace3.libs.comm.sent = {}
    assert_true(officer.Sync.Receive(remote(officer, { type = "DETAIL_FETCH", requests = {
      { entityType = "PREDIB_REQUEST", entityId = request.requestId, revision = 2 },
    } }, "Player-Realm"), "Player-Realm", "WHISPER"))
    local chunks = messages(officer, "TRANSFER_CHUNK")
    assert_equal(1, #chunks)
    local projection = officer.DeepCopy(officer.Ace3.Deserialize(chunks[1].chunk))
    assert_equal(request.requestId, projection.requestId)
    assert_nil(projection.internalNote)
    assert_nil(projection.delivery)

    local dibs = load("Player-Realm", saved)
    local transactions = #dibs.Ledger.GetAllTransactions()
    assert_true(dibs.Sync.Receive(remote(dibs, manifest, "Officer-Realm"), "Officer-Realm", "GUILD"))
    local fetches = messages(dibs, "DETAIL_FETCH")
    assert_equal(request.requestId, fetches[#fetches].requests[1].entityId)
    projection.internalNote = "Must also be stripped on receipt"
    transfer(dibs, "PREDIB_REQUEST", projection, 2, "Officer-Realm")
    local restored = dibs.PreDibs.GetHistory()[1]
    assert_equal(request.requestId, restored.requestId)
    assert_equal("confirmed", restored.status)
    assert_equal("WILD_OPEN", restored.modeAtCreation)
    assert_nil(restored.internalNote)
    assert_equal(transactions, #dibs.Ledger.GetAllTransactions())
    assert_false(dibs.Sync.IsSyncBehind())
  end)

  it("catches up multiple season catalog revisions in order and retains the final target", function()
    local gm = load("GameMaster-Realm")
    adopt(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local records = {}
    for index = 1, 4 do
      assert_not_nil(gm.Seasons.Create("Recovered Season " .. index))
      assert_true(gm.Seasons.PublishCatalog(nil, "SEASON_CREATE"))
      records[index] = gm.Seasons.GetCatalogRecord(index)
    end
    local digest = gm.Sync.BuildSeasonCatalogDigest()
    local dibs = load("Player-Realm", saved)
    assert_true(dibs.Sync.Receive(remote(dibs, digest, "GameMaster-Realm"), "GameMaster-Realm"))
    for revision = 1, 4 do
      local fetches = messages(dibs, "DETAIL_FETCH")
      local request = fetches[#fetches].requests[1]
      assert_equal("SEASON_CATALOG", request.entityType)
      assert_equal(revision, request.revision)
      transfer(dibs, "SEASON_CATALOG", records[revision], revision)
      assert_equal(revision, dibs.Seasons.GetCatalogState().catalogRevision)
      assert_equal(revision < 4, dibs.Sync.IsSyncBehind())
      if revision == 1 then
        local beforeVerify = #dibs.Ace3.libs.comm.sent
        dibs.Sync.RecheckSyncBehind()
        assert_equal(beforeVerify, #dibs.Ace3.libs.comm.sent, "Verification must not send requests")
        dibs.Sync.RequestResync()
        local retries = messages(dibs, "DETAIL_FETCH")
        assert_equal(2, retries[#retries].requests[1].revision, "Retry must resume at the missing revision")
      end
    end
    assert_equal("Recovered Season 4", dibs.Seasons.GetCurrent().name)
    assert_equal(digest.contentHash, dibs.Seasons.GetCatalogState().hash)
  end)

  it("recovers every missing policy revision without skipping the parent chain", function()
    local gm = load("GameMaster-Realm")
    adopt(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    assert_true(gm.OperationalPolicy.AdoptInitial(nil, { allowPublicPreDibs = true }, "recovery"))
    assert_true(gm.OperationalPolicy.Change(nil, { allowPublicPreDibs = false }, "recovery"))
    assert_true(gm.OperationalPolicy.Change(nil, { allowPublicPreDibs = true }, "recovery"))
    local records = {}
    for index = 1, 3 do records[index] = gm.OperationalPolicy.GetRecord(index) end
    local digest = gm.Sync.BuildOperationalPolicyDigest()
    local dibs = load("Player-Realm", saved)
    assert_true(dibs.Sync.Receive(remote(dibs, digest, "GameMaster-Realm"), "GameMaster-Realm"))
    for revision = 1, 3 do
      local fetches = messages(dibs, "DETAIL_FETCH")
      assert_equal(revision, fetches[#fetches].requests[1].revision)
      transfer(dibs, "OPERATIONAL_POLICY", records[revision], revision)
      assert_equal(revision < 3, dibs.Sync.IsSyncBehind())
    end
    assert_equal(digest.contentHash, dibs.OperationalPolicy.GetState().hash)
  end)

  it("keeps season catalog conflicts visible and preserves the adopted catalog", function()
    local gm = load("GameMaster-Realm")
    adopt(gm)
    assert_not_nil(gm.Seasons.Create("Keep This Season"))
    assert_true(gm.Seasons.PublishCatalog(nil, "SEASON_CREATE"))
    local digest = gm.Sync.BuildSeasonCatalogDigest()
    local originalHash = digest.contentHash
    digest.contentHash = "conflicting-catalog"
    local ok, reason = gm.Sync.Receive(remote(gm, digest, "GameMaster-Realm"), "GameMaster-Realm")
    assert_false(ok)
    assert_equal("SEASON_CATALOG_CONFLICT", reason)
    gm.Sync.RecheckSyncBehind()
    assert_true(gm.Sync.IsSyncBehind())
    assert_equal(originalHash, gm.Seasons.GetCatalogState().hash)
    assert_equal("SEASON_CATALOG_CONFLICT", gm.Sync.GetSyncBehindReasons()[1].code)
  end)

  it("keeps the highest announced target when a slower member advertises an older catalog", function()
    local gm = load("GameMaster-Realm")
    adopt(gm)
    local saved = gm.DeepCopy(_G.RCLootCouncil_dibsDB)
    local digests = {}
    for index = 1, 3 do
      assert_not_nil(gm.Seasons.Create("Season " .. index))
      assert_true(gm.Seasons.PublishCatalog(nil, "SEASON_CREATE"))
      digests[index] = gm.Sync.BuildSeasonCatalogDigest()
    end
    local dibs = load("Officer-Realm", saved)
    assert_true(dibs.Sync.Receive(remote(dibs, digests[3], "GameMaster-Realm"), "GameMaster-Realm"))
    assert_true(dibs.Sync.Receive(remote(dibs, digests[1], "GameMaster-Realm"), "GameMaster-Realm"))
    assert_equal(3, dibs.GetDB().sync.v2.seasonCatalogTarget.revision)
    local conflict = dibs.DeepCopy(digests[3])
    conflict.contentHash = "another-history"
    local ok, reason = dibs.Sync.Receive(remote(dibs, conflict, "GameMaster-Realm"), "GameMaster-Realm")
    assert_false(ok)
    assert_equal("SEASON_CATALOG_CONFLICT", reason)
    assert_equal(digests[3].contentHash, dibs.GetDB().sync.v2.seasonCatalogTarget.contentHash)
  end)

  it("routes the guild repair slash command through the same Officer service", function()
    local dibs = load("Officer-Realm")
    dibs.HandleSlashCommand("sync repair guild")
    assert_equal(1, #messages(dibs, "SYNC_REPAIR_REQUEST"))
    assert_equal("GUILD", messages(dibs, "SYNC_REPAIR_REQUEST")[1].scope)
  end)

  it("exposes non-destructive peer and guild repair buttons to an Officer", function()
    local dibs = load("Officer-Realm")
    dibs.OfficerUI.CreateWindow("sync")
    local buttons = {}
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" then buttons[widget.text] = widget end
    end
    assert_not_nil(buttons["Repair peer"])
    assert_not_nil(buttons["Resynchronize guild"])
    buttons["Resynchronize guild"].callbacks.OnClick()
    assert_equal(1, #messages(dibs, "SYNC_REPAIR_REQUEST"))
    assert_equal("GUILD", messages(dibs, "SYNC_REPAIR_REQUEST")[1].scope)
  end)
end)
