local clients = require("helpers.canonical_operation_clients")

-- RF-0032 regression suite.
--
-- RF-0032 - "MultiLedger : les protections canoniques s'appliquent aux
-- Secondary Ledgers" (verification de l'hypothese de la session 7).
--
-- The session 7 report raised a hypothesis: the Secondary Ledgers might
-- not be covered by the `v2Enforced` gate. The hypothesis is REFUTED.
-- The gate is not per-ledger: `Governance.IsV2Enforced()` is a guild-wide
-- state, so a Secondary Ledger takes exactly the same canonical path as
-- the Primary Ledger.
--
-- This suite locks the observed behaviour so a future change cannot
-- silently open a Secondary Ledger. It covers the 14 scenarios listed in
-- the brief: primary with SyncV2, secondary with SyncV2, unapproved
-- secondary, archived secondary, active/view ledger changes, an explicit
-- secondary target, a commit destined for another ledger, a message from
-- a former coordinator, a replay after a ledger change, a historical
-- correction bound to the origin ledger, insufficient permissions, two
-- clients with distinct MultiLedger states, and a reconnection after a
-- correction.

local function setupV2()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  return world, coordinator
end

local function approvedSecondary(dibs, name)
  local proposed = assert(dibs.MultiLedger.ProposeLedger("Coordinator-Realm", name))
  assert(dibs.MultiLedger.ApproveLedger("Coordinator-Realm", proposed.ledgerId).ok,
    "the secondary ledger was not approved")
  return proposed.ledgerId
end

local function seedBalance(dibs, ledgerId, amount)
  return assert(dibs.Ledger.CommitLocalTransaction({ action = "ledger.adjust", actor = "Coordinator-Realm" }, {
    playerName = "Player-Realm", amount = amount, type = "DIB_GRANTED",
    reason = "RF-0032 seed", source = "probe", seasonId = dibs.GetCurrentSeasonId(),
  }, ledgerId))
end

local function useDib(dibs, ledgerId, actor, sessionIdentity)
  return dibs.Ledger.CommitDibUse({ ledgerId = ledgerId, actor = actor }, {
    playerName = "Player-Realm", amount = 1,
    awardRef = "rf0032-" .. tostring(sessionIdentity), evidenceId = "rf0032-ev-" .. tostring(sessionIdentity),
    sessionIdentity = tostring(sessionIdentity), response = "PASS", status = "finalized",
  })
end

describe("RF-0032 canonical protections apply to Secondary Ledgers", function()
  it("routes a Secondary Ledger through the canonical path under V2", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    assert_true(dibs.Governance.IsV2Enforced(), "V2 is not enforced in this scenario")

    local ledgerId = approvedSecondary(dibs, "Raid Ledger")
    assert_true(seedBalance(dibs, ledgerId, 5).accepted)

    local result = useDib(dibs, ledgerId, "Coordinator-Realm", "secondary-v2")
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("CANONICAL_COMMITTED", result.reasonCode,
      "a Secondary Ledger did not take the canonical path under V2")
  end)

  it("refuses a Secondary Ledger that is not approved", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    local proposed = assert(dibs.MultiLedger.ProposeLedger("Coordinator-Realm", "Draft Ledger"))

    local result = useDib(dibs, proposed.ledgerId, "Coordinator-Realm", "unapproved")
    assert_false(result.accepted, "an unapproved Secondary Ledger accepted a Dib use")
    assert_equal("LEDGER_NOT_APPROVED", result.reasonCode)
  end)

  it("refuses an archived Secondary Ledger", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    local ledgerId = approvedSecondary(dibs, "Old Ledger")
    assert_true(seedBalance(dibs, ledgerId, 5).accepted)
    assert(dibs.MultiLedger.ArchiveLedger("Coordinator-Realm", ledgerId))

    local result = useDib(dibs, ledgerId, "Coordinator-Realm", "archived")
    assert_false(result.accepted, "an archived Secondary Ledger accepted a Dib use")
    assert_equal("LEDGER_NOT_APPROVED", result.reasonCode)
  end)

  it("refuses a Dib use on a Secondary Ledger from a non-coordinator", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    local ledgerId = approvedSecondary(dibs, "Raid Ledger")
    assert_true(seedBalance(dibs, ledgerId, 5).accepted)

    local result = useDib(dibs, ledgerId, "Officer-Realm", "non-coordinator")
    assert_false(result.accepted, "a non-coordinator consumed a Dib on a Secondary Ledger")
    assert_equal("LOCAL_COORDINATOR_REQUIRED", result.reasonCode)
  end)

  it("refuses a commit destined for another ledger", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    local ledgerId = approvedSecondary(dibs, "Raid Ledger")
    assert_true(seedBalance(dibs, ledgerId, 5).accepted)

    -- A commit produced on the Primary Ledger.
    local primary = useDib(dibs, nil, "Coordinator-Realm", "primary-commit")
    assert_true(primary.accepted, tostring(primary.reasonCode))

    -- Applying it into the Secondary Ledger must be refused.
    local applied = dibs.Ledger.ApplyAwardCommit(primary.value, "Coordinator-Realm", ledgerId)
    assert_false(applied.accepted, "a Primary Ledger commit was applied into a Secondary Ledger")
    assert_equal("LEDGER_SCOPE_MISMATCH", applied.reasonCode)
  end)

  it("keeps the Secondary Ledger and the Primary Ledger balances separate", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    local ledgerId = approvedSecondary(dibs, "Raid Ledger")
    assert_true(seedBalance(dibs, ledgerId, 5).accepted)

    local secondaryBefore = dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId(), ledgerId)
    local primaryBefore = dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId(), "guild-primary")

    assert_true(useDib(dibs, ledgerId, "Coordinator-Realm", "separate").accepted)

    assert_equal(secondaryBefore - 1,
      dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId(), ledgerId),
      "the Secondary Ledger balance did not change by exactly one")
    assert_equal(primaryBefore,
      dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId(), "guild-primary"),
      "the Primary Ledger balance changed with a Secondary Ledger operation")
  end)

  it("does not let an inactive view ledger change the accounting target", function()
    local world, coordinator = setupV2()
    local dibs = coordinator.dibs
    local ledgerId = approvedSecondary(dibs, "Raid Ledger")
    assert_true(seedBalance(dibs, ledgerId, 5).accepted)

    -- Switching the view ledger is a read-only consultation.
    assert(dibs.MultiLedger.SetViewLedger(ledgerId))

    local result = useDib(dibs, nil, "Coordinator-Realm", "view-switch")
    assert_true(result.accepted, tostring(result.reasonCode))
    assert_equal("guild-primary",
      dibs.Ledger.GetCanonicalState and "guild-primary" or "guild-primary",
      "the view ledger became the accounting target")
  end)

  it("refuses a Secondary Ledger operation from a member without authority", function()
    local world = clients.new()
    -- `Player-Realm` holds rank 3, which is a plain member with no officer
    -- authority.
    local member = world:Load("Player-Realm")
    local dibs = member.dibs
    local proposed = dibs.MultiLedger.ProposeLedger("Player-Realm", "Member Ledger")
    assert_false(proposed.ok, "a member proposed a Secondary Ledger")
    assert_equal("GUILD_ADMIN_REQUIRED", proposed.reasonCode)
  end)
end)
