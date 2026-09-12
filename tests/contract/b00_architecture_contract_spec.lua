local fixture = require("helpers.distributed_ledger_fixture")

local function bootV2()
  local guild = fixture.createGuild({ guildKey = "Dibs-Test-Realm" })
  local gm = guild:createClient({ nameRealm = "Guildmaster-Realm", role = "gm", protocol = "V2", guidWitness = "Player-1-GM" })
  local coordinator = guild:createClient({ nameRealm = "Coordinator-Realm", role = "officer", protocol = "V2", guidWitness = "Player-1-A" })
  local officer = guild:createClient({ nameRealm = "Officer-Realm", role = "officer", protocol = "V2", guidWitness = "Player-1-B" })
  local player = guild:createClient({ nameRealm = "Player-Realm", role = "player", protocol = "LEGACY" })
  guild:createRaid("Raid-A", { gm.nameRealm, coordinator.nameRealm })
  guild:createRaid("Raid-B", { officer.nameRealm, player.nameRealm })

  local values = { coordinator = coordinator.id, ledgerEpoch = 7, protocolState = "CUTOVER_PREPARED" }
  local baselineHash = "HBASE07"
  local adopted, reason = guild:adoptGovernance(gm.nameRealm, {
    revision = 1,
    parentHash = "GENESIS",
    author = gm.id,
    hash = fixture.contractHash(values),
    values = values,
    ledgerEpoch = 7,
    coordinator = coordinator.id,
    baselineHash = baselineHash,
  })
  assert_true(adopted, reason)
  return guild, gm, coordinator, officer, player, baselineHash
end

describe("B00 distributed-ledger architecture contracts", function()
  it("models independent clients, raids, and deterministic delay/duplicate/reorder/drop/partition delivery", function()
    local guild, _, coordinator, officer = bootV2()
    guild:connectClients(coordinator.nameRealm, officer.nameRealm)
    local delayed = guild:send(coordinator.nameRealm, officer.nameRealm, { kind = "LEDGER_DIGEST", seq = 1 }, { delayed = true })
    local duplicate = guild:duplicate(delayed)
    local dropped = guild:send(coordinator.nameRealm, officer.nameRealm, { kind = "LEDGER_DIGEST", seq = 2 })
    guild:drop(dropped)
    guild:reorder(delayed, duplicate)
    guild:releaseDelayed(delayed)

    local ok, payload, delivered = guild:deliverNext()
    assert_true(ok)
    assert_equal("LEDGER_DIGEST", payload.kind)
    assert_not_nil(delivered)
    assert_false(dropped.delivered)
    guild:releaseDelayed(duplicate)
    assert_true(guild:deliver(duplicate))

    guild:partitionClients(coordinator.nameRealm, officer.nameRealm)
    local partitioned = guild:send(coordinator.nameRealm, officer.nameRealm, { kind = "LEDGER_DIGEST", seq = 3 })
    assert_false(guild:deliver(partitioned))
    guild:healPartition(coordinator.nameRealm, officer.nameRealm)
    partitioned.partitioned = false
    assert_true(guild:deliver(partitioned))
  end)

  it("keeps wire identity Name-Realm, treats GUID as a witness, and rejects ambiguous short names", function()
    local guild, _, coordinator = bootV2()
    local identity = guild:resolveWireIdentity(coordinator.nameRealm, coordinator.guidWitness)
    assert_equal("coordinator-realm", identity.memberKey)
    assert_equal("Player-1-A", identity.guidWitness)
    local unresolved, reason = guild:resolveWireIdentity("Coordinator", "Player-1-A")
    assert_nil(unresolved)
    assert_equal("AMBIGUOUS_IDENTITY", reason)
  end)

  it("separates GM governance from officer operational policy without changing ledger epoch", function()
    local guild, gm, coordinator, officer, _, baselineHash = bootV2()
    local legacyWriter = guild:createClient({ nameRealm = "LegacyOfficer-Realm", role = "officer", protocol = "LEGACY" })
    assert_false(guild:enforceV2(gm.nameRealm, { coordinator.nameRealm, officer.nameRealm, legacyWriter.nameRealm }, baselineHash))
    legacyWriter.protocol = "V2" -- virtual fixture state, never production behavior.
    assert_true(guild:enforceV2(gm.nameRealm, { coordinator.nameRealm, officer.nameRealm, legacyWriter.nameRealm }, baselineHash))

    local beforeEpoch = guild.governance.ledgerEpoch
    local operational = { preDibMode = "ENCOUNTER", allowDebt = false }
    local changed, reason = guild:applyOperationalPolicy(officer.nameRealm, {
      revision = 1,
      parentHash = "GENESIS",
      hash = fixture.contractHash(operational),
      values = operational,
    })
    assert_true(changed, reason)
    assert_equal(1, guild.governance.policyRevision)
    assert_equal(beforeEpoch, guild.governance.ledgerEpoch)

    local forbidden = {
      coordinator = officer.id,
      ledgerEpoch = 8,
      governanceAuthority = officer.id,
      baselineHash = "H-UNTRUSTED",
      protocolState = "V2_ENFORCED",
    }
    assert_false(guild:applyOperationalPolicy(officer.nameRealm, {
      revision = 2,
      parentHash = guild.governance.operationalHash,
      hash = fixture.contractHash(forbidden),
      values = forbidden,
    }))
    assert_false(guild:applyGovernance(officer.nameRealm, {
      revision = 2,
      parentHash = guild.governance.hash,
      author = officer.id,
      hash = fixture.contractHash({}),
      values = {},
    }))
  end)

  it("enforces exact sequence, previous hash, canonical content hash, and SYNC_BEHIND gaps", function()
    local guild, gm, coordinator, officer, _, baselineHash = bootV2()
    assert_true(guild:enforceV2(gm.nameRealm, { coordinator.nameRealm, officer.nameRealm }, baselineHash))
    assert_true(guild:activateCoordinator(coordinator.nameRealm, 7, baselineHash))

    local first = fixture.makeLedgerEvent({ id = "7/1", epoch = 7, seq = 1, previousHash = baselineHash, player = "player-realm", amount = -1, evidence = "award-1" })
    assert_true(guild:appendCommit(coordinator.nameRealm, first))
    assert_true(guild:receiveLedger(officer.nameRealm, first))

    local gap = fixture.makeLedgerEvent({ id = "7/3", epoch = 7, seq = 3, previousHash = "H-MISSING", player = "player-realm", amount = -1, evidence = "award-3" })
    local accepted, reason = guild:receiveLedger(officer.nameRealm, gap)
    assert_false(accepted)
    assert_equal("SYNC_BEHIND", reason)
    assert_true(guild:inspectCanonicalState(officer.nameRealm).syncBehind)
    assert_false(guild:activateCoordinator(officer.nameRealm, 7, baselineHash))

    assert_true(guild:markCoordinatorUnavailable(officer.nameRealm))
    local unavailableBalance = guild:inspectCanonicalState(officer.nameRealm).balance
    local proposalOK, proposal = guild:recordAwardProposal(officer.nameRealm, { item = 19019, player = "player-realm" })
    assert_true(proposalOK)
    assert_equal("PENDING_RECONCILIATION", proposal.status)
    assert_equal(unavailableBalance, guild:inspectCanonicalState(officer.nameRealm).balance)

    local badPrevious = fixture.makeLedgerEvent({ id = "7/2", epoch = 7, seq = 2, previousHash = "WRONG", player = "player-realm", amount = -1, evidence = "award-2" })
    assert_false(guild:appendCommit(coordinator.nameRealm, badPrevious))
    local badHash = { id = "7/2", epoch = 7, seq = 2, previousHash = first.contentHash, player = "player-realm", amount = -1, evidence = "award-2", contentHash = "tampered" }
    assert_false(guild:appendCommit(coordinator.nameRealm, badHash))
  end)

  it("requires predecessor closure and root for a normal fenced handoff", function()
    local guild, gm, coordinator, officer, _, baselineHash = bootV2()
    assert_true(guild:enforceV2(gm.nameRealm, { coordinator.nameRealm, officer.nameRealm }, baselineHash))
    assert_true(guild:activateCoordinator(coordinator.nameRealm, 7, baselineHash))
    local event = fixture.makeLedgerEvent({ id = "7/1", epoch = 7, seq = 1, previousHash = baselineHash, player = "player-realm", amount = -1, evidence = "normal-handoff" })
    assert_true(guild:appendCommit(coordinator.nameRealm, event))
    local closure = guild:closeHandoff(coordinator.nameRealm)
    assert_equal(7, closure.previousEpoch)
    assert_equal(1, closure.finalSeq)
    assert_equal(event.contentHash, closure.rootHash)
    assert_false(guild:appendCommit(coordinator.nameRealm, fixture.makeLedgerEvent({ id = "7/2", epoch = 7, seq = 2, previousHash = event.contentHash, player = "player-realm", amount = -1 })))
    assert_true(guild:activateNormalHandoff(gm.nameRealm, officer.nameRealm, closure, 8))
    local state = guild:inspectCanonicalState(officer.nameRealm)
    assert_equal("ACTIVE", state.authorityState)
    assert_equal(8, state.ledgerEpoch)
    assert_equal(event.contentHash, state.lastHash)
  end)

  it("reproduces CH-01 safely: partitioned old activity becomes orphaned evidence after GM recovery", function()
    local guild, gm, coordinator, officer, _, baselineHash = bootV2()
    assert_true(guild:enforceV2(gm.nameRealm, { coordinator.nameRealm, officer.nameRealm }, baselineHash))
    assert_true(guild:activateCoordinator(coordinator.nameRealm, 7, baselineHash))

    local shared = fixture.makeLedgerEvent({ id = "7/1", epoch = 7, seq = 1, previousHash = baselineHash, player = "player-realm", amount = -1, evidence = "shared-award" })
    assert_true(guild:appendCommit(coordinator.nameRealm, shared))
    assert_true(guild:receiveLedger(officer.nameRealm, shared))

    guild:partitionClients(coordinator.nameRealm, officer.nameRealm)
    local oldBranch = fixture.makeLedgerEvent({ id = "7/2", epoch = 7, seq = 2, previousHash = shared.contentHash, player = "player-realm", amount = -1, evidence = "late-old-award" })
    assert_true(guild:appendCommit(coordinator.nameRealm, oldBranch)) -- A can observe activity on its isolated branch.
    guild:disconnectClient(coordinator.nameRealm)

    assert_true(guild:beginRecovery(officer.nameRealm))
    local before = guild:inspectCanonicalState(officer.nameRealm)
    assert_equal("RECOVERY_PENDING", before.authorityState)
    local proposalOK, proposal = guild:recordAwardProposal(officer.nameRealm, { item = 19019, player = "player-realm", evidence = "raid-b-award" })
    assert_true(proposalOK)
    assert_equal("PENDING_RECONCILIATION", proposal.status)
    assert_equal(before.balance, guild:inspectCanonicalState(officer.nameRealm).balance)

    assert_true(guild:approveForcedRecovery(gm.nameRealm, officer.nameRealm, {
      hash = shared.contentHash,
      peerEvidence = {
        { peer = coordinator.id, lastSeq = 1, rootHash = shared.contentHash },
        { peer = officer.id, lastSeq = 1, rootHash = shared.contentHash },
      },
    }, 8, {
      { eventId = shared.id, decision = "include" },
      { eventId = oldBranch.id, decision = "exclude" },
    }))
    local recovered = guild:inspectCanonicalState(officer.nameRealm)
    assert_equal("ACTIVE", recovered.authorityState)
    assert_equal(8, recovered.ledgerEpoch)
    assert_equal(shared.contentHash, recovered.lastHash)

    guild:reconnectClient(coordinator.nameRealm)
    guild:healPartition(coordinator.nameRealm, officer.nameRealm)
    local applied, lateReason = guild:receiveLedger(officer.nameRealm, oldBranch)
    assert_false(applied)
    assert_equal("ORPHANED_EVIDENCE", lateReason)
    assert_equal(0, #guild:inspectCanonicalState(officer.nameRealm).canonicalEvents)
    assert_equal(1, #guild:inspectEvidenceState(officer.nameRealm).orphaned)
  end)

  it("keeps legacy single-client behavior as immutable evidence without activating production V2 behavior", function()
    local guild = fixture.createGuild()
    local legacy = guild:createClient({ nameRealm = "Legacy-Realm", role = "officer", protocol = "LEGACY" })
    guild:createRaid("Legacy-Raid", { legacy.nameRealm })
    local original = { item = 19019, awardedTo = "Player-Realm", source = "legacy-history" }
    local evidence = guild:recordLegacyEvidence(legacy.nameRealm, original)
    original.awardedTo = "Tampered-Realm"
    local state = guild:inspectCanonicalState(legacy.nameRealm)
    assert_equal("LEGACY_LOCAL", state.protocolState)
    assert_equal("LOCAL_ONLY", state.authorityState)
    assert_equal(0, #state.canonicalEvents)
    assert_true(evidence.immutable)
    assert_equal("Player-Realm", guild:inspectEvidenceState(legacy.nameRealm).evidence[1].awardedTo)
  end)
end)
