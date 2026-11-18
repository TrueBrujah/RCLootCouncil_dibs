local loader = require("helpers.load_addon")
local fixtures = require("helpers.seasonal_roster_fixtures")

local GM, PLAYER, OFFICER = "Coordinator-Realm", "Player-Realm", "Officer-Realm"
-- Real bytes rather than the default harness's in-memory ACE token registry.
local function encode(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  assert(type(value) == "table", "unsupported wire value")
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) < type(b) end
    return a < b
  end)
  for _, key in ipairs(keys) do parts[#parts + 1] = "[" .. encode(key) .. "]=" .. encode(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function load(player, saved)
  local dibs = select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == GM,
    guildMembers = { GM, PLAYER, OFFICER }, guildRankIndices = { [1] = 0, [2] = 3, [3] = 1 },
  } }))
  dibs.Ace3.Serialize = encode
  dibs.Ace3.Deserialize = function(raw)
    local chunk
    if loadstring then
      chunk = loadstring("return " .. raw, "seasonal sync wire")
      if chunk then setfenv(chunk, {}) end
    else
      chunk = _G.load("return " .. raw, "seasonal sync wire", "t", {})
    end
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    return ok and value or nil
  end
  return { dibs = dibs }
end

local function receive(target, message, sender, mutate, channel)
  local dibs = target.dibs
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, sender:lower()
  if mutate then mutate(envelope) end
  return dibs.Sync.OnAddonMessage("DIBS", assert(dibs.Ace3.Serialize(envelope)), channel or "GUILD", sender)
end

local function begin(target, entityType, entityId, payload, sender, id, chunks, mutate)
  local dibs = target.dibs
  local raw = assert(dibs.Ace3.Serialize(payload))
  local ok, reason = receive(target, { type = "TRANSFER_BEGIN", transferId = id,
    entityType = entityType, entityId = entityId, revision = payload.revision,
    contentHash = payload.contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw),
    chunkCount = chunks or 2 }, sender, mutate)
  return ok, reason, raw
end

local function transfer(target, entityType, entityId, payload, sender, id, mutate)
  local ok, reason, raw = begin(target, entityType, entityId, payload, sender, id, 2, mutate)
  if not ok then return ok, reason end
  local middle = math.floor(#raw / 2)
  assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = id,
    chunkIndex = 1, chunk = raw:sub(1, middle) }, sender))
  assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = id,
    chunkIndex = 2, chunk = raw:sub(middle + 1) }, sender))
  return receive(target, { type = "TRANSFER_END", transferId = id,
    entityType = entityType, entityId = entityId, revision = payload.revision,
    contentHash = payload.contentHash }, sender, mutate)
end

local function source()
  local coordinator = load(GM)
  local dibs = coordinator.dibs
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "sync test",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 } }))
  assert_true(dibs.OperationalPolicy.AdoptInitial(nil,
    { allowPublicPreDibs = true, preDibModes = {} }, "roster sync test"))
  assert_true(dibs.OperationalPolicy.ChangeModules({ seasonalRoster = true }, nil, "enable roster"))
  local before = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
  local now = dibs.GetTimestamp()
  local created = dibs.SeasonalRoster.CreateSeason({ name = "Sync season", startAt = now + 10000,
    registrationStartAt = now - 10 }, "sync-create", GM)
  assert_true(created.ok, tostring(created.code))
  return coordinator, before, created.value
end

local function prepare()
  local coordinator, before, seasonId = source()
  local record = assert(coordinator.dibs.SeasonalRoster.GetSyncRevision(seasonId, 1))
  local target = load(PLAYER, before)
  return record, coordinator, target, seasonId
end

local function activated()
  local coordinator, before, seasonId = source()
  local dibs = coordinator.dibs
  local baseline = assert(dibs.HistoricalBaseline.FinalizeBaseline(nil))
  local identity = assert(dibs.Identity.CreateSnapshot(GM))
  assert_true(dibs.Governance.Change(nil, { future = { authority = { schema = 1, state = "ACTIVE",
    coordinator = identity, ledgerEpoch = 7,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash } } } }))
  assert_true(dibs.Governance.EnableV2(nil, { GM }))
  -- Preserve the established writer/ledger on both clients before dependencies diverge.
  before = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
  local opened = dibs.SeasonalRoster.SetRegistrationState(seasonId, "OPEN", 1,
    "sync-open", "Open registration", GM)
  assert_true(opened.ok, tostring(opened.code))
  local signup = dibs.SeasonalRoster.UpsertOwnEnrollment(seasonId,
    fixtures.enrollment({ character = GM }), 0, "sync-signup")
  assert_true(signup.ok, tostring(signup.code))
  local approved = dibs.SeasonalRoster.AdminUpdateEnrollment(seasonId, signup.value,
    { status = "ACTIVE" }, signup.revision, "Approved participant", "sync-approve", GM)
  assert_true(approved.ok, tostring(approved.code))
  local closed = dibs.SeasonalRoster.SetRegistrationState(seasonId, "CLOSED", opened.revision,
    "sync-close", "Close registration", GM)
  assert_true(closed.ok, tostring(closed.code))
  dibs.GetDB().rankRules[seasonId] = { ["0"] = { rankIndex = 0, rankName = "Guild Master", allocation = 2, enabled = true } }
  local published = dibs.SeasonalRoster.PublishRankAllocations(seasonId, closed.revision,
    "sync-ranks", "Publish ranks", GM)
  assert_true(published.ok, tostring(published.code))
  local precommit = dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
  local preview = assert(dibs.SeasonalRoster.PreviewActivation(seasonId, GM))
  assert_true(preview.ready)
  local ledgerBefore = dibs.Ledger.GetCanonicalState()
  local committed = dibs.SeasonalRoster.ActivateSeason(seasonId, preview.previewId,
    published.revision, "sync-activate", "Activate reviewed season", GM, true)
  assert_true(committed.ok, tostring(committed.code))
  local manifest = assert(dibs.SeasonalRoster.GetActivationSyncPayload(seasonId))
  local records, enrollments, identities, commits = {}, {}, {}, {}
  for revision = 1, published.revision do
    records[#records + 1] = assert(dibs.SeasonalRoster.GetSyncRevision(seasonId, revision))
  end
  for revision = 1, approved.revision do
    enrollments[#enrollments + 1] = assert(dibs.SeasonalRoster.GetSyncEntityRevision(seasonId .. "#" .. signup.value, revision))
  end
  for _, reference in ipairs(manifest.identities) do
    identities[#identities + 1] = assert(dibs.SeasonalRoster.GetActivationIdentitySyncPayload(reference.entityId))
  end
  local ledgerAfter = dibs.Ledger.GetCanonicalState()
  for sequence = ledgerBefore.nextSeq, ledgerAfter.nextSeq - 1 do
    commits[#commits + 1] = assert(dibs.Ledger.GetCanonicalCommit(ledgerAfter.epoch, sequence))
  end
  return { before = before, precommit = precommit, committed = dibs.DeepCopy(_G.RCLootCouncil_dibsDB),
    seasonId = seasonId, manifest = manifest,
    records = records, enrollments = enrollments, identities = identities, commits = commits,
    priorSeasonId = precommit.guilds[dibs.GetGuildKey()].currentSeasonId }
end

local function sendDependencies(target, bundle, omit)
  if omit ~= "config" then
    for index, record in ipairs(bundle.records) do
      local ok, reason = transfer(target, "SEASONAL_ROSTER", bundle.seasonId, record, GM, "config" .. index)
      assert_true(ok, tostring(reason))
    end
    for index, enrollment in ipairs(bundle.enrollments) do
      local ok, reason = transfer(target, "SEASONAL_ROSTER", bundle.seasonId .. "#" .. enrollment.enrollmentId,
        enrollment, GM, "enrollment" .. index)
      assert_true(ok, tostring(reason))
    end
  end
  if omit ~= "identity" then
    for index, identity in ipairs(bundle.identities) do
      local ok, reason = transfer(target, "SEASON_IDENTITY", identity.entityId, identity, GM, "identity" .. index)
      assert_true(ok, tostring(reason))
    end
  end
  if omit ~= "ledger" then
    for index, commit in ipairs(bundle.commits) do
      local wire = target.dibs.DeepCopy(commit)
      -- Ledger transfers have their canonical commit hash and sequence metadata.
      local id, dibs = "ledger" .. index, target.dibs
      local raw = assert(dibs.Ace3.Serialize(wire))
      assert_true(receive(target, { type = "TRANSFER_BEGIN", transferId = id, entityType = "AWARD_COMMIT",
        entityId = tostring(commit.ledgerEpoch) .. ":" .. tostring(commit.sequence), revision = commit.sequence,
        contentHash = commit.commitHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1 }, GM))
      assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = id, chunkIndex = 1, chunk = raw }, GM))
      local ok, reason = receive(target, { type = "TRANSFER_END", transferId = id, entityType = "AWARD_COMMIT" }, GM)
      assert_true(ok, tostring(reason))
    end
  end
end

describe("seasonal roster bounded synchronization", function()
  it("adopts configuration over chunks and replays without replacing ledger or current season", function()
    local record, coordinator, target, seasonId = prepare()
    local dibs = target.dibs
    local previous, ledger = dibs.GetCurrentSeasonId(), dibs.Sync.CalculateContentHash(dibs.GetDB().ledger)
    local ok, reason = transfer(target, "SEASONAL_ROSTER", seasonId, record, GM, "roster-create")
    assert_true(ok, tostring(reason))
    assert_true(transfer(target, "SEASONAL_ROSTER", seasonId, record, GM, "roster-replay"))
    assert_equal(1, dibs.SeasonalRoster.GetCurrentRevision(seasonId))
    assert_equal(previous, dibs.GetCurrentSeasonId())
    assert_equal(ledger, dibs.Sync.CalculateContentHash(dibs.GetDB().ledger))
  end)

  it("refuses wrong guild, unauthorized sender, disabled module and unsupported capability", function()
    local record, coordinator, target, seasonId = prepare()
    local ok, reason = begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "wrong-guild", 2,
      function(envelope) envelope.guildKey = "other-guild" end)
    assert_false(ok)
    assert_equal("GUILD_SCOPE_MISMATCH", reason)
    ok, reason = begin(target, "SEASONAL_ROSTER", seasonId, record, PLAYER, "player", 2)
    assert_false(ok)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    ok, reason = begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "capability", 2,
      function(envelope) envelope.protocol.capabilities.seasonalRoster = nil end)
    assert_false(ok)
    assert_equal("SEASONAL_ROSTER_PEER_UNSUPPORTED", reason)
    local requireEnabled = target.dibs.FeatureRegistry.RequireEnabled
    target.dibs.FeatureRegistry.RequireEnabled = function() return false end
    ok, reason = begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "disabled", 2)
    target.dibs.FeatureRegistry.RequireEnabled = requireEnabled
    assert_false(ok)
    assert_equal("MODULE_DISABLED", reason)
    assert_equal(0, target.dibs.SeasonalRoster.GetCurrentRevision(seasonId))
  end)

  it("retains partial chunks and refuses conflicting chunks and unchanged quotas", function()
    local record, coordinator, target, seasonId = prepare()
    local ok, reason, raw = begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "partial", 2)
    assert_true(ok, tostring(reason))
    assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = "partial", chunkIndex = 1,
      chunk = raw:sub(1, 20) }, GM))
    ok, reason = receive(target, { type = "TRANSFER_END", transferId = "partial",
      entityType = "SEASONAL_ROSTER" }, GM)
    assert_false(ok)
    assert_equal("MISSING_TRANSFER_CHUNK", reason)
    assert_equal(0, target.dibs.SeasonalRoster.GetCurrentRevision(seasonId))
    ok, reason = receive(target, { type = "TRANSFER_CHUNK", transferId = "partial", chunkIndex = 1,
      chunk = "conflicting" }, GM)
    assert_false(ok)
    assert_equal("CONFLICTING_CHUNK", reason)
    assert_false(begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "chunks17", 17))
    for index = 1, 8 do
      assert_true(begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "capacity" .. index, 2))
    end
    ok, reason = begin(target, "SEASONAL_ROSTER", seasonId, record, GM, "capacity9", 2)
    assert_false(ok)
    assert_equal("TRANSFER_CAPACITY", reason)
    assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = "capacity1", chunkIndex = 1,
      chunk = string.rep("x", 8192) }, GM))
    ok, reason = receive(target, { type = "TRANSFER_CHUNK", transferId = "capacity1", chunkIndex = 2,
      chunk = "x" }, GM)
    assert_false(ok)
    assert_equal("PAYLOAD_TOO_LARGE", reason)
  end)
end)

describe("season activation transport security", function()
  local function manifest(seasonId)
    return { schema = 1, state = "COMMITTED", seasonId = seasonId, revision = 1,
      operationId = "activation-wire", contentHash = "test-envelope-hash" }
  end

  it("requires activation capability and current guild administration before staging", function()
    local _, _, target, seasonId = prepare()
    local payload = manifest(seasonId)
    local ok, reason = begin(target, "SEASON_ACTIVATION", seasonId, payload, PLAYER, "activation-player", 2)
    assert_false(ok)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    ok, reason = begin(target, "SEASON_ACTIVATION", seasonId, payload, GM, "activation-legacy", 2,
      function(envelope) envelope.protocol.capabilities.seasonalActivationManifest = nil end)
    assert_false(ok)
    assert_equal("SEASON_ACTIVATION_PEER_UNSUPPORTED", reason)
    ok, reason = begin(target, "SEASON_ACTIVATION", seasonId, payload, GM, "activation-guild", 2,
      function(envelope) envelope.guildKey = "another-guild" end)
    assert_false(ok)
    assert_equal("GUILD_SCOPE_MISMATCH", reason)
    assert_nil(next(target.dibs.runtime.v2Transfers))
  end)

  it("keeps the old season visible until every chunk arrives", function()
    local _, _, target, seasonId = prepare()
    local previous = target.dibs.GetCurrentSeasonId()
    assert_true(begin(target, "SEASON_ACTIVATION", seasonId, manifest(seasonId), GM, "activation-partial", 2))
    assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = "activation-partial",
      chunkIndex = 1, chunk = "partial" }, GM))
    local ok, reason = receive(target, { type = "TRANSFER_END", transferId = "activation-partial",
      entityType = "SEASON_ACTIVATION" }, GM)
    assert_false(ok)
    assert_equal("MISSING_TRANSFER_CHUNK", reason)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    assert_not_nil(target.dibs.runtime.v2Transfers["activation-partial"])
  end)

  it("fails closed while disabled and disallows whisper fallback", function()
    local _, _, target, seasonId = prepare()
    local requireEnabled = target.dibs.FeatureRegistry.RequireEnabled
    target.dibs.FeatureRegistry.RequireEnabled = function() return false end
    local ok, reason = begin(target, "SEASON_ACTIVATION", seasonId, manifest(seasonId), GM, "activation-disabled", 2)
    target.dibs.FeatureRegistry.RequireEnabled = requireEnabled
    assert_false(ok)
    assert_equal("MODULE_DISABLED", reason)
    ok, reason = receive(target, { type = "TRANSFER_BEGIN", transferId = "activation-whisper",
      entityType = "SEASON_ACTIVATION", entityId = seasonId, revision = 1,
      contentHash = "x", payloadHash = "x", chunkCount = 1 }, GM, nil, "WHISPER")
    assert_false(ok)
    assert_equal("INVALID_TRANSPORT_CHANNEL", reason)
  end)

  it("bounds pending manifests and rejects a conflicting digest without evicting the original", function()
    local _, _, target = prepare()
    for index = 1, 8 do
      assert_true(receive(target, { type = "DIGEST", entityType = "SEASON_ACTIVATION",
        entityId = "season" .. index, revision = 1, contentHash = "hash" .. index }, GM))
    end
    local ok, reason = receive(target, { type = "DIGEST", entityType = "SEASON_ACTIVATION",
      entityId = "season9", revision = 1, contentHash = "hash9" }, GM)
    assert_false(ok)
    assert_equal("ACTIVATION_STAGE_CAPACITY", reason)
    ok, reason = receive(target, { type = "DIGEST", entityType = "SEASON_ACTIVATION",
      entityId = "season1", revision = 1, contentHash = "different" }, GM)
    assert_false(ok)
    assert_equal("SEASON_ACTIVATION_CONFLICT", reason)
    assert_equal("hash1", target.dibs.GetDB().sync.v2.seasonActivationTargets.season1.contentHash)
  end)

  it("throttles missing-manifest requests and allows an explicit recovery retry", function()
    local _, _, target, seasonId = prepare()
    local fetches = 0
    target.dibs.Ace3.SendComm = function(_, envelope)
      if envelope.type == "DETAIL_FETCH" then fetches = fetches + 1 end
      return true
    end
    assert_true(receive(target, { type = "DIGEST", entityType = "SEASON_ACTIVATION", entityId = seasonId,
      revision = 1, contentHash = "missing-manifest" }, GM))
    assert_equal(1, fetches)
    target.dibs.Sync.RetrySeasonActivations()
    assert_equal(1, fetches)
    target.dibs.Sync.RetrySeasonActivations(true)
    assert_equal(2, fetches)
  end)
end)

describe("committed season activation convergence", function()
  it("expands the compact bounded-wire manifest before service validation", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    sendDependencies(target, bundle)
    local wire = target.dibs.Sync._activationTransport.compactManifest(bundle.manifest)
    assert_equal(1, wire.wireSchema)
    assert_true(#encode(wire) <= 8192)
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, wire, GM, "compact-manifest")
    assert_true(ok, tostring(reason))
    local adopted = assert(target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId))
    assert_equal(bundle.manifest.contentHash, adopted.contentHash)
    assert_nil(adopted.wireSchema)
  end)

  it("serves manifests and rank snapshots only to peers advertising the required capabilities", function()
    local bundle = activated()
    local server = load(GM, bundle.committed)
    local replies = 0
    server.dibs.Ace3.SendComm = function() replies = replies + 1; return true end
    assert_true(receive(server, { type = "DETAIL_FETCH", requests = { { entityType = "SEASON_ACTIVATION",
      entityId = bundle.seasonId, revision = 1, contentHash = bundle.manifest.contentHash } } }, PLAYER,
      function(envelope) envelope.protocol.capabilities.seasonalActivationManifest = nil end))
    assert_equal(0, replies)
    local published = bundle.records[#bundle.records]
    assert_true(receive(server, { type = "DETAIL_FETCH", requests = { { entityType = "SEASONAL_ROSTER",
      entityId = bundle.seasonId, revision = published.revision, contentHash = published.contentHash } } }, PLAYER,
      function(envelope) envelope.protocol.capabilities.seasonalAllocationSnapshot = nil end))
    assert_equal(0, replies)
    assert_true(receive(server, { type = "DETAIL_FETCH", requests = { { entityType = "SEASON_ACTIVATION",
      entityId = bundle.seasonId, revision = 1, contentHash = bundle.manifest.contentHash } } }, PLAYER))
    assert_true(replies > 0)
  end)

  it("recovers a lost activation announcement using only digest/detail requests and canonical messages", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    local requests = {}
    local function captureRequests(client)
      client.dibs.Ace3.SendComm = function(_, envelope, channel)
        if envelope.type == "DETAIL_FETCH" then
          assert_equal("GUILD", channel)
          assert_true(#envelope.requests <= 8)
          requests[#requests + 1] = client.dibs.DeepCopy(envelope)
        end
        return true
      end
    end
    captureRequests(target)
    assert_true(receive(target, { type = "DIGEST", entityType = "SEASON_ACTIVATION", entityId = bundle.seasonId,
      revision = bundle.manifest.revision, contentHash = bundle.manifest.contentHash }, GM))
    assert_true(#requests > 0)
    local saved = target.dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    for _ = 1, 12 do
      local pending, replies = requests, {}
      requests = {}
      local server = load(GM, bundle.committed)
      server.dibs.Ace3.SendComm = function(_, envelope, channel)
        assert_equal("GUILD", channel)
        replies[#replies + 1] = server.dibs.DeepCopy(envelope)
        return true
      end
      for _, request in ipairs(pending) do
        local ok, reason = receive(server, request, PLAYER)
        assert_true(ok, tostring(reason))
      end
      target = load(PLAYER, saved)
      captureRequests(target)
      for _, reply in ipairs(replies) do
        local ok, reason = receive(target, reply, GM)
        assert_true(ok, tostring(reason))
      end
      if target.dibs.GetCurrentSeasonId() == bundle.seasonId then break end
      target.dibs.Sync.RetrySeasonActivations(true)
      saved = target.dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
    end
    assert_equal(bundle.seasonId, target.dibs.GetCurrentSeasonId())
    assert_equal(bundle.manifest.ledger.rootHash, target.dibs.Ledger.GetCanonicalState().rootHash)
  end)

  it("rejects an enrollment relayed by a different player without changing the cohort", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    for index, record in ipairs(bundle.records) do
      assert_true(transfer(target, "SEASONAL_ROSTER", bundle.seasonId, record, GM, "owner-config" .. index))
    end
    local enrollment = bundle.enrollments[1]
    local entityId = bundle.seasonId .. "#" .. enrollment.enrollmentId
    local ok, reason = transfer(target, "SEASONAL_ROSTER", entityId, enrollment, PLAYER, "wrong-owner")
    assert_false(ok)
    assert_equal("ENROLLMENT_OWNER_MISMATCH", reason)
    assert_equal(0, target.dibs.SeasonalRoster.GetSyncEntityState(entityId))
  end)

  it("adopts manifest last after configuration, approved cohort, identity and canonical ledger", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    local previous = target.dibs.GetCurrentSeasonId()
    sendDependencies(target, bundle)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "manifest-last")
    assert_true(ok, tostring(reason))
    assert_equal(bundle.seasonId, target.dibs.GetCurrentSeasonId())
    assert_equal(bundle.manifest.contentHash, target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId).contentHash)
    assert_nil(bundle.manifest.transactions)
    assert_nil(bundle.manifest.rows)
    assert_true(#encode(bundle.manifest) <= 8192)
  end)

  it("stages manifest first, requests missing dependencies and adopts after ledger arrives", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    local previous = target.dibs.GetCurrentSeasonId()
    local sent = {}
    target.dibs.Ace3.SendComm = function(_, envelope, channel)
      sent[#sent + 1] = { message = target.dibs.DeepCopy(envelope), channel = channel }
      return true
    end
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "manifest-first")
    assert_true(ok, tostring(reason))
    assert_equal("ACTIVATION_STAGED", reason)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    local fetched = false
    for _, packet in ipairs(sent) do
      if packet.message.type == "DETAIL_FETCH" then
        fetched = true
        assert_equal("GUILD", packet.channel)
        assert_true(#packet.message.requests <= 8)
      end
    end
    assert_true(fetched)
    sendDependencies(target, bundle, "ledger")
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    -- Existing ledger messages own all canonical events.
    local onlyLedger = target.dibs.DeepCopy(bundle)
    onlyLedger.records, onlyLedger.enrollments, onlyLedger.identities = {}, {}, {}
    sendDependencies(target, onlyLedger)
    assert_equal(bundle.seasonId, target.dibs.GetCurrentSeasonId())
    assert_nil(target.dibs.GetDB().sync.v2.seasonActivationTargets)
  end)

  it("retains the prior season until the exact published rank snapshot arrives", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    local previous = target.dibs.GetCurrentSeasonId()
    local pending = target.dibs.DeepCopy(bundle)
    local published = table.remove(pending.records)
    sendDependencies(target, pending)
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "missing-ranks")
    assert_true(ok, tostring(reason))
    assert_equal("ACTIVATION_STAGED", reason)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    assert_nil(target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId))
    assert_true(transfer(target, "SEASONAL_ROSTER", bundle.seasonId, published, GM, "published-ranks"))
    assert_equal(bundle.seasonId, target.dibs.GetCurrentSeasonId())
  end)

  it("keeps a different rank dependency staged without selecting the new season", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    local previous = target.dibs.GetCurrentSeasonId()
    sendDependencies(target, bundle)
    local edited = target.dibs.DeepCopy(bundle.manifest)
    edited.dependencies.rankRulesHash = "different-published-rank-snapshot"
    edited.contentHash = nil
    edited.contentHash = target.dibs.Sync.CalculateContentHash(edited)
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, edited, GM, "different-ranks")
    assert_true(ok, tostring(reason))
    assert_equal("ACTIVATION_STAGED", reason)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    assert_nil(target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId))
  end)

  it("uses portable dependencies despite different local guild-roster and identity generations", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    sendDependencies(target, bundle)
    local getState = target.dibs.Identity.GetRosterState
    target.dibs.Identity.GetRosterState = function(...)
      local state = target.dibs.DeepCopy(getState(...))
      state.generation = (state.generation or 0) + 500
      return state
    end
    local identityRevision = target.dibs.CharacterEligibility.GetRevision()
    target.dibs.GetDB().characterEligibility.revision = identityRevision + 100
    assert_equal(identityRevision + 100, target.dibs.CharacterEligibility.GetRevision())
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "portable-manifest")
    assert_true(ok, tostring(reason))
    assert_equal(bundle.seasonId, target.dibs.GetCurrentSeasonId())
  end)

  it("rechecks the module gate at transfer completion", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    sendDependencies(target, bundle)
    local previous = target.dibs.GetCurrentSeasonId()
    local ok, reason, raw = begin(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "disable-at-end", 1)
    assert_true(ok, tostring(reason))
    assert_true(receive(target, { type = "TRANSFER_CHUNK", transferId = "disable-at-end", chunkIndex = 1, chunk = raw }, GM))
    local requireEnabled = target.dibs.FeatureRegistry.RequireEnabled
    target.dibs.FeatureRegistry.RequireEnabled = function() return false end
    ok, reason = receive(target, { type = "TRANSFER_END", transferId = "disable-at-end", entityType = "SEASON_ACTIVATION" }, GM)
    target.dibs.FeatureRegistry.RequireEnabled = requireEnabled
    assert_false(ok)
    assert_equal("MODULE_DISABLED", reason)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    assert_nil(target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId))
  end)

  it("replays committed activation idempotently and rejects changed content", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    sendDependencies(target, bundle)
    assert_true(transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "initial-manifest"))
    local ledgerHash = target.dibs.Sync.CalculateContentHash(target.dibs.GetDB().ledger)
    assert_true(transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "replayed-manifest"))
    local edited = target.dibs.DeepCopy(bundle.manifest)
    edited.dependencies.rankRulesHash = "different-ranks"
    edited.contentHash = nil
    edited.contentHash = target.dibs.Sync.CalculateContentHash(edited)
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, edited, GM, "conflicting-manifest")
    assert_false(ok)
    assert_equal("ACTIVATION_CONFLICT", reason)
    assert_equal(bundle.manifest.contentHash, target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId).contentHash)
    assert_equal(ledgerHash, target.dibs.Sync.CalculateContentHash(target.dibs.GetDB().ledger))
  end)

  it("does not roll back a newer committed season when an old activation detail arrives late", function()
    local bundle = activated()
    local server = load(GM, bundle.committed)
    local dibs, roster = server.dibs, server.dibs.SeasonalRoster
    local now = dibs.GetTimestamp()
    local created = roster.CreateSeason({ name = "Newer committed season", startAt = now + 20000,
      registrationStartAt = now - 10 }, "second-create", GM)
    assert_true(created.ok, tostring(created.code))
    local opened = roster.SetRegistrationState(created.value, "OPEN", created.revision,
      "second-open", "Open next season", GM)
    assert_true(opened.ok, tostring(opened.code))
    local signup = roster.UpsertOwnEnrollment(created.value, fixtures.enrollment({ character = GM }), 0, "second-signup")
    assert_true(signup.ok, tostring(signup.code))
    assert_true(roster.AdminUpdateEnrollment(created.value, signup.value, { status = "ACTIVE" }, signup.revision,
      "Approved next season", "second-approve", GM).ok)
    local closed = roster.SetRegistrationState(created.value, "CLOSED", opened.revision,
      "second-close", "Close next season", GM)
    assert_true(closed.ok, tostring(closed.code))
    dibs.GetDB().rankRules[created.value] = { ["0"] = { rankIndex = 0, allocation = 3, enabled = true } }
    local published = roster.PublishRankAllocations(created.value, closed.revision,
      "second-ranks", "Publish next season allocations", GM)
    assert_true(published.ok, tostring(published.code))
    local preview = assert(roster.PreviewActivation(created.value, GM))
    assert_true(preview.ready)
    local committed = roster.ActivateSeason(created.value, preview.previewId, published.revision,
      "second-activate", "Activate next season", GM, true)
    assert_true(committed.ok, tostring(committed.code))
    -- Model a client that received all dependencies for A but first caught up
    -- to B's visibility commit. A's manifest announcement was lost.
    local older = dibs.GetDB().seasonalRoster.seasons[bundle.seasonId]
    older.activationManifest, older.activationAdopted, older.pendingActivation = nil, nil, nil
    local target = load(PLAYER, dibs.DeepCopy(_G.RCLootCouncil_dibsDB))
    local ledgerHash = target.dibs.Sync.CalculateContentHash(target.dibs.GetDB().ledger)
    transfer(target, "SEASON_ACTIVATION", bundle.seasonId, bundle.manifest, GM, "late-old-manifest")
    assert_equal(created.value, target.dibs.GetCurrentSeasonId())
    assert_equal(ledgerHash, target.dibs.Sync.CalculateContentHash(target.dibs.GetDB().ledger))
  end)

  it("requires a canonical activation author even when the sender is a current officer", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    sendDependencies(target, bundle)
    local previous = target.dibs.GetCurrentSeasonId()
    local edited = target.dibs.DeepCopy(bundle.manifest)
    edited.preparedBy = OFFICER:lower()
    edited.contentHash = nil
    edited.contentHash = target.dibs.Sync.CalculateContentHash(edited)
    local ok, reason = transfer(target, "SEASON_ACTIVATION", bundle.seasonId, edited, OFFICER, "officer-manifest")
    assert_false(ok)
    assert_equal("ACTIVATION_AUTHOR_MISMATCH", reason)
    assert_equal(previous, target.dibs.GetCurrentSeasonId())
    assert_nil(target.dibs.GetDB().sync.v2.seasonActivationTargets)
  end)

  it("validates identity authority, content and module state before adopting the snapshot", function()
    local bundle = activated()
    local target = load(PLAYER, bundle.before)
    local snapshot = bundle.identities[1]
    local forged = target.dibs.DeepCopy(snapshot)
    forged.authorKey = OFFICER:lower()
    forged.contentHash = nil
    forged.contentHash = target.dibs.Sync.CalculateContentHash(forged)
    local ok, reason = transfer(target, "SEASON_IDENTITY", forged.entityId, forged, OFFICER, "officer-identity")
    assert_false(ok)
    assert_equal("IDENTITY_AUTHOR_NOT_CANONICAL_WRITER", reason)
    local edited = target.dibs.DeepCopy(snapshot)
    edited.mainCharacterKey = "other-realm"
    edited.contentHash = nil
    edited.contentHash = target.dibs.Sync.CalculateContentHash(edited)
    ok, reason = transfer(target, "SEASON_IDENTITY", edited.entityId, edited, GM, "invalid-identity")
    assert_false(ok)
    assert_equal("INVALID_SEASON_IDENTITY", reason)
    local requireEnabled = target.dibs.FeatureRegistry.RequireEnabled
    target.dibs.FeatureRegistry.RequireEnabled = function() return false end
    ok, reason = begin(target, "SEASON_IDENTITY", snapshot.entityId, snapshot, GM, "disabled-identity", 2)
    target.dibs.FeatureRegistry.RequireEnabled = requireEnabled
    assert_false(ok)
    assert_equal("MODULE_DISABLED", reason)
    assert_true(transfer(target, "SEASON_IDENTITY", snapshot.entityId, snapshot, GM, "valid-identity"))
    assert_true(transfer(target, "SEASON_IDENTITY", snapshot.entityId, snapshot, GM, "replayed-identity"))
    assert_nil(target.dibs.SeasonalRoster.GetActivationManifest(bundle.seasonId))
  end)
end)
