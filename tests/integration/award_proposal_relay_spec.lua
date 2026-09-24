local loader = require("helpers.load_addon")

-- NOTE: this repo's test harness reuses `_G.Dibs` across `loader.load()`
-- calls within a single process, and the AceSerializer test double keeps its
-- encoded-value table private per `loader.load()` call (see
-- tests/helpers/load_addon.lua's makeAce3()). Serialized wire payloads
-- therefore cannot round-trip across independently reloaded instances.
-- Multi-client scenarios in this repo (see b06_distributed_ledger_spec.lua)
-- instead pass the already-decoded Lua value between reloads and assert on
-- the receiving module's real, non-mocked contract -- exactly the pattern
-- used below. Wire framing itself (entity allowlist, transfer shape) is
-- covered separately on a single instance.

local roster = { "Coordinator-Realm", "Officer2-Realm", "Player-Realm" }
local ranks = { [1] = 0, [2] = 1, [3] = 3 }

local function load(player, saved)
  return select(2, loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = player, guildLeader = player == "Coordinator-Realm", guildMembers = roster, guildRankIndices = ranks,
  } }))
end

local function activateV2()
  local dibs = load("Coordinator-Realm")
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "award relay test" }))
  local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Coordinator-Realm"))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 1,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { "Coordinator-Realm" }))
  assert_not_nil(dibs.Seasons.Create("Relay"))
  assert_not_nil(dibs.Ledger.Grant("Player-Realm", 3, "setup", "test", dibs.GetCurrentSeasonId()))
  return dibs.DeepCopy(_G.RCLootCouncil_dibsDB)
end

local function findProposal(proposals, proposalId)
  for _, proposal in ipairs(proposals or {}) do
    if proposal.proposalId == proposalId then return proposal end
  end
end

describe("Award proposal relay wire framing (single instance)", function()
  it("targets the current coordinator with a WHISPER AWARD_PROPOSAL transfer", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, {
      playerName = "Player-Realm", itemID = 1, awardRef = "raid2-kill",
    }))
    assert_equal("RELAY_PENDING", proposal.relayStatus)
    assert_equal(1, proposal.relayAttempts)

    local begin
    for _, message in ipairs(officer.Ace3.libs.comm.sent) do
      local decoded = officer.Ace3.Deserialize(message.payload)
      if decoded and decoded.type == "TRANSFER_BEGIN" and decoded.entityType == "AWARD_PROPOSAL" then begin = { message = message, decoded = decoded } end
    end
    assert_not_nil(begin)
    assert_equal("WHISPER", begin.message.channel)
    assert_equal("Coordinator-Realm", begin.message.target)
    assert_equal(proposal.proposalId, begin.decoded.entityId)
  end)

  it("does not relay when no coordinator has been elected", function()
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = "Officer2-Realm", guildLeader = false, guildMembers = roster, guildRankIndices = ranks,
    } })
    local before = #dibs.Ace3.libs.comm.sent
    local proposal = assert(dibs.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 4, awardRef = "no-coordinator" }))
    assert_nil(proposal.relayStatus)
    assert_equal(before, #dibs.Ace3.libs.comm.sent)
  end)
end)

describe("Award proposal relay contract across simultaneous raids", function()
  it("lets the coordinator receive, ack, and commit a non-coordinator's proposal, converging balances", function()
    local saved = activateV2()

    -- Officer2-Realm (a different, non-coordinator raid) finalizes an award.
    local officer = load("Officer2-Realm", saved)
    local season = officer.GetCurrentSeasonId()
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, {
      playerName = "Player-Realm", itemID = 1, awardRef = "raid2-kill",
    }))
    assert_equal("RELAY_PENDING", proposal.relayStatus)
    local officerSaved = officer.DeepCopy(_G.RCLootCouncil_dibsDB)

    -- Coordinator receives the relayed proposal (equivalent to the wire delivery validated above).
    local coordinator = load("Coordinator-Realm", saved)
    local accepted, reason = coordinator.Governance.ReceiveRelayedProposal(proposal, "Officer2-Realm")
    assert_true(accepted, tostring(reason))
    local pending = coordinator.Governance.GetPendingCoordinatorProposals()
    assert_equal(1, #pending)
    assert_equal(proposal.proposalId, pending[1].proposalId)
    local pendingUi = coordinator.OfficerUI.GetPendingAwardProposals()
    assert_equal(1, #pendingUi)
    assert_equal(proposal.proposalId, pendingUi[1].proposalId)
    local coordinatorSaved = coordinator.DeepCopy(_G.RCLootCouncil_dibsDB)

    -- Officer applies the resulting ack.
    officer = load("Officer2-Realm", officerSaved)
    officer.Governance.AckProposalRelay(proposal.proposalId)
    local acknowledged = findProposal(officer.Governance.GetAwardProposals(), proposal.proposalId)
    assert_not_nil(acknowledged)
    assert_equal("RELAY_ACKED", acknowledged.relayStatus)

    -- Coordinator confirms/commits the award.
    coordinator = load("Coordinator-Realm", coordinatorSaved)
    local commit = coordinator.OfficerUI.ConfirmPendingAwardProposal(proposal.proposalId)
    assert_true(commit.accepted, tostring(commit.reasonCode))
    assert_equal(2, coordinator.Ledger.GetBalance("Player-Realm", season))
    local completed = findProposal(coordinator.Governance.GetAwardProposals(), proposal.proposalId)
    assert_not_nil(completed)
    assert_equal("COMMITTED", completed.status)

    -- The resulting AWARD_COMMIT, applied on the officer's own client, converges the balance.
    officer = load("Officer2-Realm", officer.DeepCopy(_G.RCLootCouncil_dibsDB))
    local applied = officer.Ledger.ApplyAwardCommit(commit.value, "Coordinator-Realm")
    assert_true(applied.accepted, tostring(applied.reasonCode))
    assert_equal(2, officer.Ledger.GetBalance("Player-Realm", season))
  end)

  it("is idempotent when the same proposal is relayed twice", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 2, awardRef = "dup-1" }))

    local coordinator = load("Coordinator-Realm", saved)
    assert_true(coordinator.Governance.ReceiveRelayedProposal(proposal, "Officer2-Realm"))
    assert_equal(1, #coordinator.Governance.GetPendingCoordinatorProposals())
    local accepted, reason = coordinator.Governance.ReceiveRelayedProposal(proposal, "Officer2-Realm")
    assert_true(accepted); assert_equal("IDEMPOTENT_PROPOSAL", reason)
    assert_equal(1, #coordinator.Governance.GetPendingCoordinatorProposals())
  end)

  it("rejects a relayed proposal received by a member who is not the current coordinator", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 5, awardRef = "wrong-target" }))

    local player = load("Player-Realm", saved)
    local accepted, reason = player.Governance.ReceiveRelayedProposal(proposal, "Officer2-Realm")
    assert_false(accepted)
    assert_equal("CURRENT_COORDINATOR_REQUIRED", reason)
  end)

  it("rejects a proposal from a non-officer or with modified content", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 6, awardRef = "secure-relay" }))

    local coordinator = load("Coordinator-Realm", saved)
    local accepted, reason = coordinator.Governance.ReceiveRelayedProposal(proposal, "Player-Realm")
    assert_false(accepted)
    assert_equal("PROPOSAL_SENDER_AUTHORITY_REQUIRED", reason)

    local tampered = coordinator.DeepCopy(proposal)
    tampered.itemID = 999
    accepted, reason = coordinator.Governance.ReceiveRelayedProposal(tampered, "Officer2-Realm")
    assert_false(accepted)
    assert_equal("PROPOSAL_HASH_MISMATCH", reason)
  end)

  it("rejects an acknowledgement that does not originate from the coordinator", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 7, awardRef = "secure-ack" }))
    local spoofed = assert(officer.Sync.BuildEnvelope({ type = "AWARD_PROPOSAL_ACK", proposalId = proposal.proposalId }))

    local accepted, reason = officer.Sync.Receive(spoofed, "Officer2-Realm")
    assert_false(accepted)
    assert_equal("CURRENT_COORDINATOR_REQUIRED", reason)
    local pending = findProposal(officer.Governance.GetAwardProposals(), proposal.proposalId)
    assert_not_nil(pending)
    assert_equal("RELAY_PENDING", pending.relayStatus)
  end)

  it("retries and eventually delivers a proposal once the coordinator becomes reachable", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 3, awardRef = "reconnect-1" }))
    assert_equal(1, proposal.relayAttempts)

    officer.Sync.RetryPendingAwardProposals()
    local afterRetry = findProposal(officer.Governance.GetAwardProposals(), proposal.proposalId)
    assert_not_nil(afterRetry)
    assert_equal(2, afterRetry.relayAttempts)
    assert_equal("RELAY_PENDING", afterRetry.relayStatus)

    local coordinator = load("Coordinator-Realm", saved)
    assert_true(coordinator.Governance.ReceiveRelayedProposal(afterRetry, "Officer2-Realm"))
    assert_equal(1, #coordinator.Governance.GetPendingCoordinatorProposals())
  end)

  it("stops retrying after the bounded relay attempt limit", function()
    local saved = activateV2()
    local officer = load("Officer2-Realm", saved)
    local proposal = assert(officer.Governance.RecordAwardProposal(nil, { playerName = "Player-Realm", itemID = 8, awardRef = "retry-cap" }))

    for _ = 1, 4 do officer.Sync.RetryPendingAwardProposals() end
    local exhausted = findProposal(officer.Governance.GetAwardProposals(), proposal.proposalId)
    assert_not_nil(exhausted)
    assert_equal(5, exhausted.relayAttempts)
    assert_equal("RELAY_ATTEMPTS_EXHAUSTED", exhausted.relayStatus)

    local sentBefore = #officer.Ace3.libs.comm.sent
    assert_equal(0, officer.Sync.RetryPendingAwardProposals())
    assert_equal(sentBefore, #officer.Ace3.libs.comm.sent)
  end)
end)
