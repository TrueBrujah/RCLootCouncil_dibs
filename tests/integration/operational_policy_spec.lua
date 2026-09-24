local loader = require("helpers.load_addon")
local fixture = require("helpers.distributed_ledger_fixture")

local function load(options)
  options = options or {}
  options.withAce3 = true
  options.wow = options.wow or {
    guildLeader = true,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
  }
  return select(2, loader.load(options))
end

local function adoptGovernance(dibs, writerRule)
  local ok, reason = dibs.Governance.AdoptInitial(nil, {
    reason = "B02b governance adoption",
    officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
    policyWriterRule = writerRule or { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
  })
  assert_true(ok, tostring(reason))
end

local function values(dibs, mode, public)
  return { preDibModes = { [dibs.GetCurrentSeasonId()] = mode or "WILD_OPEN" }, allowPublicPreDibs = public ~= false }
end

local function remote(dibs, message, sender)
  local envelope = assert(dibs.Sync.BuildEnvelope(message))
  envelope.senderNameRealm, envelope.senderMemberKey = sender, string.lower(sender)
  return envelope
end

local function transferPolicy(dibs, record, sender, transferId)
  local raw = assert(dibs.Ace3.Serialize(record))
  local begin = {
    type = "TRANSFER_BEGIN", transferId = transferId, entityType = "OPERATIONAL_POLICY",
    entityId = tostring(record.policyRevision), revision = record.policyRevision,
    contentHash = record.contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1,
  }
  assert_true(dibs.Sync.Receive(remote(dibs, begin, sender), sender))
  assert_true(dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = 1, chunk = raw }, sender), sender))
  return dibs.Sync.Receive(remote(dibs, { type = "TRANSFER_END", transferId = transferId }, sender), sender)
end

describe("B02b operational policy", function()
  it("requires explicit GM adoption and keeps uninitialized settings legacy-local", function()
    local dibs = load()
    assert_equal("POLICY_UNINITIALIZED", dibs.OperationalPolicy.GetState().status)
    assert_nil(dibs.OperationalPolicy.GetValues())
    local changed, reason = dibs.OperationalPolicy.Change(nil, values(dibs))
    assert_false(changed); assert_equal("POLICY_UNINITIALIZED", reason)
    assert_not_nil(dibs.PreDibs.SetModePolicy(dibs.GetCurrentSeasonId(), "ENCOUNTER", nil))
    assert_equal("ENCOUNTER", dibs.PreDibs.GetModePolicy().mode)
  end)

  it("accepts GM adoption and routes Pre-Dib mode through policyRevision without changing governance future state", function()
    local dibs = load(); adoptGovernance(dibs)
    local initial, reason = dibs.OperationalPolicy.AdoptInitial(nil, values(dibs))
    assert_true(initial, tostring(reason)); assert_equal(1, dibs.OperationalPolicy.GetState().policyRevision)
    local beforeFuture = dibs.Governance.GetState().future
    local mode, modeReason = dibs.PreDibs.SetModePolicy(dibs.GetCurrentSeasonId(), "ENCOUNTER", nil)
    assert_not_nil(mode, tostring(modeReason)); assert_equal("OPERATIONAL_POLICY", mode.source)
    assert_equal(2, dibs.OperationalPolicy.GetState().policyRevision)
    assert_equal("ENCOUNTER", dibs.PreDibs.GetModePolicy().mode)
    assert_equal(nil, beforeFuture.ledgerEpoch); assert_equal(nil, dibs.Governance.GetState().future.ledgerEpoch)
  end)

  it("replicates Pre-Dib announcement channels through the operational policy", function()
    local source = load(); adoptGovernance(source)
    assert_true(source.OperationalPolicy.AdoptInitial(nil, values(source)))
    local initialRecord = source.OperationalPolicy.GetCurrentRecord()
    local channels, reason = source.PreDibs.SetAnnouncementChannels("RAID", "OFFICER", nil)
    assert_not_nil(channels, tostring(reason))
    assert_equal("RAID", channels.publicChannel)
    assert_equal("OFFICER", channels.officerChannel)
    local record = source.OperationalPolicy.GetCurrentRecord()
    assert_equal("RAID", record.values.announcementChannels.publicChannel)

    local target = load(); adoptGovernance(target)
    assert_true(target.OperationalPolicy.ApplyRecord(initialRecord, "Tester-Realm"))
    local applied, applyReason = target.OperationalPolicy.ApplyRecord(record, "Tester-Realm")
    assert_true(applied, tostring(applyReason))
    local synced = target.PreDibs.GetAnnouncementSettings()
    assert_equal("RAID", synced.publicChannel)
    assert_equal("OFFICER", synced.officerChannel)
  end)

  it("accepts an authorized officer record but rejects a member and local settings as authority", function()
    local dibs = load(); adoptGovernance(dibs)
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, values(dibs)))
    local record = assert(dibs.OperationalPolicy.CreateChangeRecord(nil, { allowPublicPreDibs = false }, "remote officer"))
    local officer = assert(dibs.Identity.CreateSnapshot("Officer-Realm"))
    record.authorNameRealm, record.authorMemberKey, record.authorSnapshot = officer.displayName, officer.memberKey, officer
    record.contentHash = dibs.OperationalPolicy.CalculateContentHash(record)
    local applied, reason = dibs.OperationalPolicy.ApplyRecord(record, "Officer-Realm")
    assert_true(applied, tostring(reason)); assert_false(dibs.PreDibs.IsPublicEnabled())

    local restricted = load(); adoptGovernance(restricted, { kind = "GOVERNANCE_ONLY" })
    assert_true(restricted.OperationalPolicy.AdoptInitial(nil, values(restricted)))
    restricted.GetDB().settings.officerRankIndices = { [3] = true }
    local denied = assert(restricted.OperationalPolicy.CreateChangeRecord(nil, { allowPublicPreDibs = false }))
    local player = assert(restricted.Identity.CreateSnapshot("Player-Realm"))
    denied.authorNameRealm, denied.authorMemberKey, denied.authorSnapshot = player.displayName, player.memberKey, player
    denied.contentHash = restricted.OperationalPolicy.CalculateContentHash(denied)
    applied, reason = restricted.OperationalPolicy.ApplyRecord(denied, "Player-Realm")
    assert_false(applied); assert_equal("POLICY_WRITER_REQUIRED", reason)
  end)

  it("recovers a missed policy chain with deterministic replay, conflict, and stale outcomes", function()
    local source = load(); adoptGovernance(source)
    assert_true(source.OperationalPolicy.AdoptInitial(nil, values(source)))
    local first = source.OperationalPolicy.GetCurrentRecord()
    assert_true(source.OperationalPolicy.Change(nil, { allowPublicPreDibs = false }, "second"))
    local second = source.OperationalPolicy.GetCurrentRecord()

    local target = load(); adoptGovernance(target)
    local applied, reason = transferPolicy(target, second, "Tester-Realm", "policy-second")
    assert_false(applied); assert_equal("POLICY_PARENT_MISSING", reason); assert_true(target.Sync.IsSyncBehind())
    applied, reason = transferPolicy(target, first, "Tester-Realm", "policy-first")
    assert_true(applied, tostring(reason)); assert_equal("ADOPTED", reason); assert_true(target.Sync.IsSyncBehind())
    applied, reason = transferPolicy(target, second, "Tester-Realm", "policy-second-retry")
    assert_true(applied, tostring(reason)); assert_false(target.Sync.IsSyncBehind())
    applied, reason = target.OperationalPolicy.ApplyRecord(second, "Tester-Realm")
    assert_true(applied); assert_equal("IDEMPOTENT_REPLAY", reason)
    local conflict = target.DeepCopy(second); conflict.audit.reason = "conflict"; conflict.contentHash = target.OperationalPolicy.CalculateContentHash(conflict)
    applied, reason = target.OperationalPolicy.ApplyRecord(conflict, "Tester-Realm")
    assert_false(applied); assert_equal("POLICY_CONFLICT", reason)
    applied, reason = target.OperationalPolicy.ApplyRecord(first, "Tester-Realm")
    assert_false(applied); assert_equal("STALE_POLICY", reason)
  end)

  it("models two simultaneous raids converging on one operational policy chain", function()
    local guild = fixture.createGuild({ guildKey = "B02b-Realm" })
    local gm = guild:createClient({ nameRealm = "Guildmaster-Realm", role = "gm" })
    local writer = guild:createClient({ nameRealm = "Officer-Realm", role = "officer" })
    local raidB = guild:createClient({ nameRealm = "RaidB-Realm", role = "officer" })
    guild:createRaid("Raid-A", { gm.nameRealm, writer.nameRealm })
    guild:createRaid("Raid-B", { raidB.nameRealm })
    local governanceValues = { policyWriterRule = "officers" }
    assert_true(guild:adoptGovernance(gm.nameRealm, { revision = 1, parentHash = "GENESIS", author = gm.id, hash = fixture.contractHash(governanceValues), values = governanceValues }))
    local policyValues = { preDibMode = "ENCOUNTER", requestAvailability = true }
    assert_true(guild:applyOperationalPolicy(writer.nameRealm, { revision = 1, parentHash = "GENESIS", hash = fixture.contractHash(policyValues), values = policyValues }))
    assert_equal(1, guild:inspectCanonicalState(writer.nameRealm).policyRevision)
    assert_equal(1, guild:inspectCanonicalState(raidB.nameRealm).policyRevision)
  end)

  it("uses B04 GUILD hints and WHISPER policy details without synchronizing presentation settings", function()
    local dibs = load(); adoptGovernance(dibs)
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, values(dibs)))
    local digest = remote(dibs, dibs.Sync.BuildOperationalPolicyDigest(), "Officer-Realm")
    digest.revision, digest.contentHash, digest.parentRevision, digest.parentHash = 2, "policy-new", 1, dibs.OperationalPolicy.GetState().hash
    local accepted, reason = dibs.Sync.Receive(digest, "Officer-Realm")
    assert_true(accepted); assert_equal("POLICY_DETAIL_REQUESTED", reason); assert_true(dibs.Sync.IsSyncBehind())
    local sent = dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent]
    assert_equal("WHISPER", sent.channel)
    local beforeLanguage = dibs.GetDB().settings.language
    local changed, changeReason = dibs.OperationalPolicy.Change(nil, { allowPublicPreDibs = false }, "notify")
    assert_true(changed, tostring(changeReason)); assert_equal(beforeLanguage, dibs.GetDB().settings.language)
    sent = dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent]
    assert_equal("GUILD", sent.channel); assert_equal("OPERATIONAL_POLICY", dibs.Ace3.Deserialize(sent.payload).entityType)
  end)

  it("routes adopted guild profile policy through authorization and never changes governance", function()
    local dibs = load(); adoptGovernance(dibs)
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, values(dibs)))
    local governance = dibs.Governance.GetState()
    assert_not_nil(dibs.Profiles.Create("policy", "guild", { authoritativePolicy = { allowPublicPreDibs = false } }, nil))
    local active, reason = dibs.Profiles.Activate("policy", "guild", nil, true)
    assert_not_nil(active, tostring(reason)); assert_false(dibs.PreDibs.IsPublicEnabled())
    assert_equal(governance.revision, dibs.Governance.GetState().revision)
    assert_equal(governance.hash, dibs.Governance.GetState().hash)
    assert_not_nil(dibs.Profiles.Create("legacy", "guild", { authoritativePolicy = { defaultAllocation = 9 } }, nil))
    active, reason = dibs.Profiles.Activate("legacy", "guild", nil, true)
    assert_nil(active); assert_equal("PROFILE_SHARED_POLICY_UNSUPPORTED", reason)
  end)

  it("rejects wrong-guild, unknown-sender policy transport and leaves the B03 ledger unchanged", function()
    local dibs = load(); adoptGovernance(dibs)
    assert_true(dibs.OperationalPolicy.AdoptInitial(nil, values(dibs)))
    local before = #dibs.Ledger.GetAllTransactions()
    local badGuild = remote(dibs, dibs.Sync.BuildOperationalPolicyDigest(), "Officer-Realm"); badGuild.guildKey = "wrong"
    assert_false(dibs.Sync.Receive(badGuild, "Officer-Realm"))
    local member = remote(dibs, dibs.Sync.BuildOperationalPolicyDigest(), "Player-Realm")
    assert_false(dibs.Sync.Receive(member, "Player-Realm"))
    local record = dibs.OperationalPolicy.GetCurrentRecord(); local raw = assert(dibs.Ace3.Serialize(record))
    local policyBegin = remote(dibs, { type = "TRANSFER_BEGIN", transferId = "member-policy", entityType = "OPERATIONAL_POLICY", entityId = tostring(record.policyRevision), revision = record.policyRevision, contentHash = record.contentHash, payloadHash = dibs.Sync.CalculateContentHash(raw), chunkCount = 1 }, "Player-Realm")
    assert_false(dibs.Sync.Receive(policyBegin, "Player-Realm"))
    local unknown = remote(dibs, dibs.Sync.BuildOperationalPolicyDigest(), "Unknown-Realm")
    assert_false(dibs.Sync.Receive(unknown, "Unknown-Realm"))
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
