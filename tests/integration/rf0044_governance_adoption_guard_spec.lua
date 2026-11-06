local clients = require("helpers.canonical_operation_clients")

-- RF-0044 regression suite.
--
-- RF-0044 - "Governance : l'exception de retard est strictement limitee au
-- registre de gouvernance en cours d'adoption"
-- (docs/code-audit/INDEX.md#rf-0044).
--
-- The brief requires that the governance exception of RF-0035 is
-- **strictly limited** to the register needed for the adoption, and that
-- it does not indirectly authorise an adoption while another mandatory
-- component is behind:
--   * ledger ;
--   * policy ;
--   * seasons ;
--   * vault ;
--   * requests ;
--   * other really defined authoritative prerequisites.
--
-- Every client has its own environment, SavedVariables, ledger, SyncV2
-- state, MultiLedger state and Governance state.

local function setupV2()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  world:Load("Player-Realm", world:Snapshot(coordinator))
  world:TakePackets()
  return world, coordinator
end

-- The authority record the coordinator publishes, used to drive an
-- adoption on the follower.
local function successorAuthority(dibs, coordinatorName, epoch, closure)
  local successor = assert(dibs.Identity.CreateSnapshot(coordinatorName))
  return {
    schema = 1, state = "ACTIVE", coordinator = successor, ledgerEpoch = epoch,
    protocolState = "V2_ENFORCED",
    transition = { kind = "NORMAL_HANDOFF", parentClosure = closure, parentClosureHash = closure.closureHash },
  }
end

describe("RF-0044 the governance adoption exception stays limited", function()
  -- The guard of RF-0035 lives in `authorityContent`, which validates the
  -- **authority record that is being created**. The record is created by
  -- the Guild Master, so the guard is exercised on the coordinator. The
  -- exception must not let an adoption through while another mandatory
  -- component is behind.
  local function adoptOn(client, epoch)
    return client.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = assert(client.Identity.CreateSnapshot("Coordinator-Realm")),
      ledgerEpoch = epoch, protocolState = "V2_ENFORCED",
      transition = { kind = "INITIAL", baselineHash = "x" },
    } } })
  end

  it("refuses the adoption while a ledger gap is outstanding", function()
    local world, coordinator = setupV2()

    coordinator.dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a ledger gap was outstanding")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("refuses the adoption while a policy gap is outstanding", function()
    local world, coordinator = setupV2()

    coordinator.dibs.Sync.MarkSyncBehind("POLICY_PARENT_MISSING")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a policy gap was outstanding")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("refuses the adoption while a season catalog gap is outstanding", function()
    local world, coordinator = setupV2()

    coordinator.dibs.Sync.MarkSyncBehind("SEASON_CATALOG_PARENT_MISSING")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a season catalog gap was outstanding")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("refuses the adoption while a vault gap is outstanding", function()
    local world, coordinator = setupV2()

    coordinator.dibs.Sync.MarkSyncBehind("VAULT_DETAIL_MISSING")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a vault gap was outstanding")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("refuses the adoption while a request detail gap is outstanding", function()
    local world, coordinator = setupV2()

    coordinator.dibs.Sync.MarkSyncBehind("MISSING_DETAIL")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a request detail gap was outstanding")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("refuses the adoption while a ledger enforcement gap is outstanding", function()
    local world, coordinator = setupV2()

    coordinator.dibs.Sync.MarkSyncBehind("LEDGER_ENFORCEMENT_MISSING")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a ledger enforcement gap was outstanding")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("refuses the adoption when a ledger gap accompanies the governance gap", function()
    local world, coordinator = setupV2()

    -- Both reasons are outstanding: the ledger gap must still block.
    coordinator.dibs.Sync.MarkSyncBehind("GOVERNANCE_PARENT_MISSING")
    coordinator.dibs.Sync.MarkSyncBehind("LEDGER_GAP")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    assert_false(adopted, "the adoption succeeded while a ledger gap accompanied the governance gap")
    assert_equal("SYNC_BEHIND", reason)
  end)

  it("does not let the governance exception release a ledger gap", function()
    local world, coordinator = setupV2()

    -- Only the governance gap is outstanding: the exception applies, and
    -- the adoption is refused for its own reasons (the transition is not a
    -- valid handoff), not because of the gap.
    coordinator.dibs.Sync.MarkSyncBehind("GOVERNANCE_PARENT_MISSING")
    local adopted, reason = adoptOn(coordinator.dibs, 8)
    if adopted then
      assert_equal(8, coordinator.dibs.Governance.GetAuthorityState().ledgerEpoch)
    else
      assert_true(reason ~= "SYNC_BEHIND",
        "the governance gap blocked the adoption: " .. tostring(reason))
    end
  end)
end)
