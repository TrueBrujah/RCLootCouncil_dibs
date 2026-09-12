local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

local function load(options, withAce3)
  return select(2, loader.load({ wow = options or { guildLeader = true }, withAce3 = withAce3 == true }))
end

describe("Governance bootstrap and identity", function()
  it("uses full Name-Realm as the canonical identity and preserves a GUID only as a witness", function()
    local dibs = load({ guildMembers = { "Tester-Realm", "Other-Realm" }, guildRankIndices = { [1] = 0, [2] = 3 } })
    local snapshot, reason = dibs.Identity.CreateSnapshot({ nameRealm = "Tester-Realm", guid = "Player-1-WITNESS" })

    assert_not_nil(snapshot, tostring(reason))
    assert_equal("tester-realm", snapshot.memberKey)
    assert_equal("tester-realm", dibs.Identity.CanonicalMemberKey("Tester-Realm"))
    assert_equal("Tester-Realm", snapshot.displayName)
    assert_equal("Player-1-WITNESS", snapshot.guidWitness)

    local disagreement = dibs.Identity.CreateSnapshot({ nameRealm = "Other-Realm", guid = "Player-1-TESTER" })
    assert_equal("other-realm", disagreement.memberKey)
    assert_equal("Player-1-TESTER", disagreement.guidWitness)
  end)

  it("resolves only a unique short name and reports ambiguity or unknown roster members", function()
    local dibs = load({ guildMembers = { "Tester-Realm", "Tester-Other", "Solo-Realm" }, guildRankIndices = { [1] = 0, [2] = 3, [3] = 3 } })

    assert_equal("RESOLVED", dibs.Identity.ResolveRosterMember("Solo").status)
    assert_equal("solo-realm", dibs.Identity.ResolveRosterMember("Solo").memberKey)
    assert_equal("AMBIGUOUS_IDENTITY", dibs.Identity.ResolveRosterMember("Tester").status)
    assert_equal("UNKNOWN_ROSTER_MEMBER", dibs.Identity.ResolveRosterMember("Absent-Realm").status)
  end)

  it("invalidates roster freshness and re-evaluates demotion/promotion from the live roster", function()
    local dibs = load({ guildLeader = false, guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 3, [2] = 1 } }, true)
    assert_equal("officer", dibs.Identity.ResolveRosterMember("Officer-Realm").role)
    local fresh = dibs.Identity.GetRosterState()
    assert_true(fresh.fresh)

    wow.setGuildRoster({ "Tester-Realm", "Officer-Realm" }, { [1] = 3, [2] = 3 })
    assert_not_nil(dibs.Ace3.handlers.events.GUILD_ROSTER_UPDATE)
    dibs.Ace3.handlers.events.GUILD_ROSTER_UPDATE("GUILD_ROSTER_UPDATE")
    local invalidated = dibs.Identity.GetRosterState()
    assert_false(invalidated.fresh)
    assert_true(invalidated.generation > fresh.generation)
    assert_equal("player", dibs.Identity.ResolveRosterMember("Officer-Realm").role)
    assert_false(dibs.Governance.AdoptInitial(nil, { reason = "not current GM" }))

    wow.setGuildRoster({ "Tester-Realm", "Officer-Realm" }, { [1] = 0, [2] = 3 })
    dibs.Ace3.handlers.events.GUILD_ROSTER_UPDATE("GUILD_ROSTER_UPDATE")
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "current roster promotion" }))
  end)

  it("starts POLICY_UNINITIALIZED and never promotes local settings or aliases automatically", function()
    local dibs = load({ guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 1 } })
    local db = dibs.GetDB()
    db.settings.officerMaxRankIndex = 0
    db.settings.officerRankIndices = { [0] = true }

    local state = dibs.Governance.GetState()
    assert_equal("POLICY_UNINITIALIZED", state.status)
    assert_equal(0, state.revision)
    assert_equal("GENESIS", state.hash)
    assert_equal(0, #state.auditLog)
    assert_nil(next(state.aliases.records))
    assert_false(dibs.Governance.AdoptInitial(nil, { reason = "local settings are not authority" }))
  end)

  it("allows only the current GM to create an auditable initial governance record", function()
    local dibs = load({ guildMembers = { "Tester-Realm", "Officer-Realm" }, guildRankIndices = { [1] = 0, [2] = 1 } })
    local denied, denialReason = dibs.Governance.AdoptInitial("Officer-Realm", { reason = "officer attempt" })
    assert_false(denied)
    assert_equal("CURRENT_GUILD_MASTER_REQUIRED", denialReason)

    local adopted, adoptionReason, record = dibs.Governance.AdoptInitial(nil, {
      reason = "GM explicit adoption",
      officerAuthorityRule = { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 },
      policyWriterRule = { kind = "GOVERNANCE_ONLY" },
    })
    assert_true(adopted, adoptionReason)
    assert_equal("ADOPTED", adoptionReason)
    assert_equal(1, record.governanceRevision)
    assert_equal(0, record.parentRevision)
    assert_equal("GENESIS", record.parentHash)
    assert_equal("tester-realm", record.authorMemberKey)
    assert_not_nil(record.contentHash)
    assert_equal("LEGACY_LOCAL", record.content.future.protocolState)
    assert_nil(record.content.future.coordinator)
    assert_nil(record.content.future.ledgerEpoch)
    assert_nil(record.content.future.baseline)
    assert_equal("GOVERNANCE_ADOPTED", dibs.Governance.GetState().status)

    local changed, changeReason = dibs.Governance.Change("Officer-Realm", { reason = "officer change attempt" })
    assert_false(changed)
    assert_equal("CURRENT_GUILD_MASTER_REQUIRED", changeReason)
  end)

  it("uses hash/parent rules for idempotency and explicit governance conflicts", function()
    local dibs = load()
    local initial = assert(dibs.Governance.CreateInitialRecord(nil, { reason = "initial" }))
    assert_true(dibs.Governance.ApplyRecord(initial, "Tester-Realm"))

    local replayed, replayReason = dibs.Governance.ApplyRecord(initial, "Tester-Realm")
    assert_true(replayed)
    assert_equal("IDEMPOTENT_REPLAY", replayReason)

    local conflict = dibs.DeepCopy(initial)
    conflict.audit.reason = "same revision, different hash"
    conflict.contentHash = dibs.Governance.CalculateContentHash(conflict)
    local accepted, conflictReason = dibs.Governance.ApplyRecord(conflict, "Tester-Realm")
    assert_false(accepted)
    assert_equal("GOVERNANCE_CONFLICT", conflictReason)
    assert_equal(1, #dibs.Governance.GetState().conflicts)

    local nextRecord = assert(dibs.Governance.CreateChangeRecord(nil, { reason = "parent check" }))
    nextRecord.parentHash = "wrong-parent"
    nextRecord.contentHash = dibs.Governance.CalculateContentHash(nextRecord)
    local changed, parentReason = dibs.Governance.ApplyRecord(nextRecord, "Tester-Realm")
    assert_false(changed)
    assert_equal("GOVERNANCE_PARENT_MISMATCH", parentReason)
  end)

  it("preserves historical names and ledger evidence through governance adoption", function()
    local dibs = load()
    local db = dibs.GetDB()
    db.ledger.transactions["legacy-history"] = {
      transactionId = "legacy-history",
      playerName = "LegacyName-OldRealm",
      amount = -1,
    }

    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "preserve history" }))
    assert_equal("LegacyName-OldRealm", db.ledger.transactions["legacy-history"].playerName)
    assert_equal("legacy-history", db.ledger.transactions["legacy-history"].transactionId)
  end)

  it("rejects future coordinator, epoch, baseline, and protocol activation concepts in B02a", function()
    local dibs = load()
    local rejected, reason = dibs.Governance.AdoptInitial(nil, {
      future = { coordinator = "Officer-Realm", ledgerEpoch = 1, protocolState = "V2_ENFORCED", baseline = "H1" },
    })
    assert_false(rejected)
    assert_equal("FUTURE_GOVERNANCE_INACTIVE", reason)
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
  end)

  it("defers governance adoption when a fresh guild roster cannot be confirmed", function()
    local dibs = load()
    _G.GetNumGuildMembers = nil
    local adopted, reason = dibs.Governance.AdoptInitial(nil, { reason = "no roster proof" })
    assert_false(adopted)
    assert_equal("ROSTER_UNAVAILABLE", reason)
    assert_equal("POLICY_UNINITIALIZED", dibs.Governance.GetState().status)
  end)
end)
