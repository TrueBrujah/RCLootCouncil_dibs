local loader = require("helpers.load_addon")

-- RF-0031 regression suite.
--
-- RF-0031 - "Ledger : une proposition terminale conserve une reservation
-- fantome et reduit indefiniment le solde disponible"
-- (docs/code-audit/INDEX.md#rf-0031).
--
-- A Dib reservation is the amount a player is holding for an award
-- proposal that has not been committed yet. The accounting balance is
-- untouched by a reservation; only the *available* balance is reduced.
--
-- `Governance.MarkAwardProposalCommitted` releases a reservation by setting
-- the proposal status to `COMMITTED` and clearing the remote reservation.
-- `Governance.ResolveAwardProposal` ends a proposal in a terminal state
-- (`STALE` or `REJECTED`) but did neither:
--   * `Ledger.GetPendingDibReservations` only excluded `COMMITTED`, so a
--     `STALE` or `REJECTED` proposal still counted as a reservation;
--   * the remote reservation was never cleared.
--
-- Consequence: a refused or stale award left a phantom reservation that
-- permanently reduced the player's available balance, with no accounting
-- movement to explain it.

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { playerName = "Tester-Realm", guildLeader = true } })
  local seasonId = dibs.GetCurrentSeasonId()
  assert(dibs.Ledger.Grant("Tester-Realm", 10, "RF-0031 opening grant", "probe", seasonId),
      "the opening grant was refused")
  return dibs, seasonId
end

local function recordProposal(dibs, sessionIdentity)
  return assert(dibs.Governance.RecordAwardProposal({
    playerName = "Tester-Realm", itemID = 275658, amount = 1,
    type = "DIB_USED", sessionIdentity = sessionIdentity, response = "PASS",
  }, "Tester-Realm"))
end

local function proposalStatus(dibs, proposalId)
  for _, proposal in ipairs(dibs.Governance.GetAwardProposals()) do
    if proposal.proposalId == proposalId then return proposal.status end
  end
  return nil
end

describe("RF-0031 a terminal proposal releases its Dib reservation", function()
  it("releases the reservation when a proposal is rejected", function()
    local dibs, seasonId = setup()
    local proposal = recordProposal(dibs, "rf0031-reject")

    -- The pending proposal holds a reservation and reduces the available
    -- balance without touching the accounting balance.
    assert_equal(1, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "the pending proposal did not hold a reservation")
    local balanceWithReservation = dibs.Ledger.GetBalance("Tester-Realm", seasonId)
    assert_true(dibs.Ledger.GetAvailableBalance("Tester-Realm", seasonId) < balanceWithReservation,
      "the reservation did not reduce the available balance")

    local resolved, reason = dibs.Governance.ResolveAwardProposal(proposal.proposalId, "REJECTED", "RF0031_REJECTED")
    assert_true(resolved, tostring(reason))
    assert_equal("REJECTED", proposalStatus(dibs, proposal.proposalId))

    assert_equal(0, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "a rejected proposal kept a phantom reservation")
    assert_equal(dibs.Ledger.GetBalance("Tester-Realm", seasonId),
      dibs.Ledger.GetAvailableBalance("Tester-Realm", seasonId),
      "a rejected proposal kept the available balance reduced")
  end)

  it("releases the reservation when a proposal becomes stale", function()
    local dibs, seasonId = setup()
    local proposal = recordProposal(dibs, "rf0031-stale")

    assert_equal(1, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "the pending proposal did not hold a reservation")

    local resolved, reason = dibs.Governance.ResolveAwardProposal(proposal.proposalId, "STALE", "RF0031_STALE")
    assert_true(resolved, tostring(reason))
    assert_equal("STALE", proposalStatus(dibs, proposal.proposalId))

    assert_equal(0, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "a stale proposal kept a phantom reservation")
    assert_equal(dibs.Ledger.GetBalance("Tester-Realm", seasonId),
      dibs.Ledger.GetAvailableBalance("Tester-Realm", seasonId),
      "a stale proposal kept the available balance reduced")
  end)

  it("does not change the accounting balance when a reservation is released", function()
    local dibs, seasonId = setup()
    local proposal = recordProposal(dibs, "rf0031-nobalance")
    local balanceBefore = dibs.Ledger.GetBalance("Tester-Realm", seasonId)

    dibs.Governance.ResolveAwardProposal(proposal.proposalId, "REJECTED", "RF0031_REJECTED")

    assert_equal(balanceBefore, dibs.Ledger.GetBalance("Tester-Realm", seasonId),
      "releasing a reservation changed the accounting balance")
  end)

  it("keeps the reservation of a proposal that is still pending", function()
    local dibs, seasonId = setup()
    recordProposal(dibs, "rf0031-still-pending")

    assert_equal("PENDING_RECONCILIATION", proposalStatus(dibs, "rf0031-still-pending") or "PENDING_RECONCILIATION")
    assert_equal(1, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "a pending proposal lost its reservation")
  end)

  it("releases a committed proposal reservation exactly once", function()
    local dibs, seasonId = setup()
    local proposal = recordProposal(dibs, "rf0031-committed")

    assert_equal(1, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "the pending proposal did not hold a reservation")

    assert(dibs.Governance.MarkAwardProposalCommitted(proposal.proposalId, { commitHash = "probe" }))
    assert_equal("COMMITTED", proposalStatus(dibs, proposal.proposalId))
    assert_equal(0, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "a committed proposal kept a reservation")

    -- A repeated commit must not change anything either.
    assert(dibs.Governance.MarkAwardProposalCommitted(proposal.proposalId, { commitHash = "probe" }))
    assert_equal(0, dibs.Ledger.GetPendingDibReservations("Tester-Realm", seasonId),
      "a repeated commit released a reservation twice")
  end)

  it("does not broadcast a terminal proposal as a pending reservation", function()
    local dibs = setup()
    local proposal = recordProposal(dibs, "rf0031-digest")

    local digest = dibs.Sync.BuildAwardReservationDigest()
    local broadcast = 0
    for _, record in ipairs(digest.records or {}) do
      if record.proposalId == proposal.proposalId then broadcast = broadcast + 1 end
    end
    assert_equal(1, broadcast, "the pending proposal was not broadcast")

    dibs.Governance.ResolveAwardProposal(proposal.proposalId, "REJECTED", "RF0031_REJECTED")

    digest = dibs.Sync.BuildAwardReservationDigest()
    broadcast = 0
    for _, record in ipairs(digest.records or {}) do
      if record.proposalId == proposal.proposalId then broadcast = broadcast + 1 end
    end
    assert_equal(0, broadcast,
      "a terminal proposal was still broadcast as a pending reservation")
  end)

  it("does not report a terminal proposal as pending", function()
    local dibs = setup()
    local proposal = recordProposal(dibs, "rf0031-pending-count")

    local status = dibs.Sync.GetSynchronizationStatus()
    assert_true(status.pendingAwardProposals >= 1, "the pending proposal was not reported")

    dibs.Governance.ResolveAwardProposal(proposal.proposalId, "REJECTED", "RF0031_REJECTED")

    status = dibs.Sync.GetSynchronizationStatus()
    assert_equal(0, status.pendingAwardProposals,
      "a terminal proposal was still reported as a pending award proposal")
  end)
end)
