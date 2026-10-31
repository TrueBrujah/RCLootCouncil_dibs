local clients = require("helpers.canonical_operation_clients")

-- RF-0038 regression suite.
--
-- RF-0038 - "Ledger : un snapshot canonique corrompu peut etre accepte
-- comme valide et reconstruit" (docs/code-audit/INDEX.md#rf-0038).
--
-- The audit brief asks for the canonical snapshot scenarios to be covered:
-- a valid snapshot, an empty snapshot, an incomplete snapshot, a corrupted
-- snapshot, a snapshot from another ledger, a snapshot from another guild,
-- a snapshot with a wrong hash, a snapshot with an old sequence, a
-- snapshot with a stale epoch, a snapshot with duplicated transactions, a
-- snapshot with unknown operations, a snapshot followed by a replay, a
-- snapshot received after a newer commit, a snapshot interrupted during
-- its application, and a snapshot of a Secondary Ledger.
--
-- The invariant under test: an invalid snapshot must fail **without any
-- accounting mutation**, and a valid local history must never be silently
-- replaced.
--
-- The client runs under the V2 authority, because the root of a canonical
-- chain is defined against the authority baseline, and that baseline only
-- exists once an authority is active.

local function setup()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  local dibs = coordinator.dibs
  return world, coordinator, dibs
end

local function canonicalOf(dibs, ledgerId)
  local state = dibs.Ledger.GetCanonicalState(ledgerId or "guild-primary")
  return state and { epoch = state.epoch, nextSeq = state.nextSeq, rootHash = state.rootHash } or nil
end

local function snapshotOf(dibs, ledgerId)
  local db = dibs.GetDB()
  local ledger = db.ledgers and db.ledgers[ledgerId or "guild-primary"]
  return ledger and ledger.canonical or nil
end

local function baselineOf(dibs)
  local authority = dibs.Governance.GetAuthorityState()
  return authority and authority.transition and authority.transition.baselineHash or nil
end

-- Puts the chain of a ledger at the authority baseline, with no commit.
local function emptyChainAtBaseline(dibs, ledgerId)
  local canonical = snapshotOf(dibs, ledgerId)
  canonical.epoch = dibs.Governance.GetAuthorityState().ledgerEpoch
  canonical.nextSeq = 1
  canonical.rootHash = baselineOf(dibs)
  return canonical
end

describe("RF-0038 canonical snapshot protection", function()
  it("classifies a valid canonical chain as recoverable", function()
    local world, coordinator, dibs = setup()
    local classification = dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("VALID", classification.classification, tostring(classification.reasonCode))
  end)

  it("accepts an empty chain that carries the authority baseline", function()
    local world, coordinator, dibs = setup()
    emptyChainAtBaseline(dibs)

    local classification = dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("VALID", classification.classification, tostring(classification.reasonCode))
  end)

  it("refuses an empty chain whose root is not the authority baseline", function()
    local world, coordinator, dibs = setup()
    local canonical = emptyChainAtBaseline(dibs)
    canonical.rootHash = "D3-V2-not-the-baseline"

    -- RF-0038: an empty chain has no commit to hash, so the root-hash
    -- check of the recovery classification never ran on it. The root of an
    -- empty chain is the authority baseline: it is the only proof that
    -- the chain descends from the approved baseline. Without the check, a
    -- corrupted snapshot classified as `VALID` and was rebuilt.
    local classification = dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_true(classification.classification ~= "VALID",
      "an empty chain with a foreign root was classified as valid")
    assert_equal("WRONG_ROOT", classification.classification, tostring(classification.reasonCode))

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_false(rebuilt.rebuilt, "an empty chain with a foreign root was rebuilt")
  end)

  it("keeps a valid local history when a corrupted snapshot is refused", function()
    local world, coordinator, dibs = setup()
    local seasonId = dibs.GetCurrentSeasonId()
    local beforeState = canonicalOf(dibs)
    local beforeBalance = dibs.Ledger.GetBalance("Player-Realm", seasonId)

    local canonical = emptyChainAtBaseline(dibs)
    canonical.rootHash = "D3-V2-not-the-baseline"

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_false(rebuilt.rebuilt, "a corrupted snapshot was applied")

    assert_equal(beforeBalance, dibs.Ledger.GetBalance("Player-Realm", seasonId),
      "the refused snapshot changed the balance")
    assert_equal(beforeState.nextSeq, canonicalOf(dibs).nextSeq,
      "the refused snapshot changed the canonical sequence")
  end)

  it("refuses to rebuild a chain that is missing a sequence", function()
    local world, coordinator, dibs = setup()
    -- A real canonical commit, then a hole in the chain.
    local committed = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
      playerName = "Player-Realm", amount = 5, reason = "RF-0038 allocation",
      source = "rf0038", seasonId = dibs.GetCurrentSeasonId(),
    })
    assert_true(committed.accepted, tostring(committed.reasonCode))
    local second = dibs.Ledger.CommitDibUse({ actor = "Coordinator-Realm" }, {
      transactionId = "rf0038-second", proposalId = "rf0038-second-p",
      playerName = "Player-Realm", amount = 1, itemID = 1,
      source = "rf0038", response = "PASS", status = "finalized",
    })
    assert_true(second.accepted, tostring(second.reasonCode))

    local canonical = snapshotOf(dibs)
    local epoch = canonical.epoch
    canonical.commits[epoch .. ":1"] = nil
    canonical.nextSeq = 3

    local classification = dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_equal("MISSING_SEQUENCE", classification.classification, tostring(classification.reasonCode))

    local before = dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId())
    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_false(rebuilt.rebuilt, "a broken chain was rebuilt")
    assert_equal(before, dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId()),
      "the refused rebuild changed the balance")
  end)

  it("refuses to rebuild a chain whose root hash does not match", function()
    local world, coordinator, dibs = setup()
    local committed = dibs.Ledger.CommitSeasonAllocation({ actor = "Coordinator-Realm" }, {
      playerName = "Player-Realm", amount = 5, reason = "RF-0038 allocation",
      source = "rf0038", seasonId = dibs.GetCurrentSeasonId(),
    })
    assert_true(committed.accepted, tostring(committed.reasonCode))

    local canonical = snapshotOf(dibs)
    canonical.rootHash = "D3-V2-deadbeef"

    local classification = dibs.Ledger.ClassifyCanonicalRecovery("guild-primary")
    assert_true(classification.classification ~= "VALID",
      "a chain with a wrong root hash was classified as valid")
    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_false(rebuilt.rebuilt, "a chain with a wrong root hash was rebuilt")
  end)

  it("refuses to rebuild a chain that contains a commit of a future epoch", function()
    local world, coordinator, dibs = setup()
    local canonical = emptyChainAtBaseline(dibs)
    local epoch = canonical.epoch
    canonical.commits[tostring(epoch + 1) .. ":1"] = {
      recordClass = "AWARD_COMMIT", ledgerEpoch = epoch + 1, sequence = 1,
    }

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_false(rebuilt.rebuilt, "a chain with a future-epoch commit was rebuilt")
  end)

  it("keeps a Secondary Ledger snapshot separate from the Primary Ledger", function()
    local world, coordinator, dibs = setup()
    local proposed = assert(dibs.MultiLedger.ProposeLedger("Coordinator-Realm", "Raid Ledger"))
    local approval = dibs.MultiLedger.ApproveLedger("Coordinator-Realm", proposed.ledgerId)
    assert_true(approval.ok, tostring(approval.reasonCode))

    local primary = snapshotOf(dibs, "guild-primary")
    local secondary = snapshotOf(dibs, proposed.ledgerId)
    assert_not_nil(secondary, "the Secondary Ledger has no canonical block")
    assert_true(primary ~= secondary, "the two ledgers share the same canonical table")

    -- A rebuild of the Secondary Ledger does not touch the Primary Ledger.
    local primaryBefore = canonicalOf(dibs, "guild-primary")
    dibs.Ledger.RebuildLedgerProjections(proposed.ledgerId)
    assert_equal(primaryBefore.nextSeq, canonicalOf(dibs, "guild-primary").nextSeq,
      "the Secondary Ledger rebuild changed the Primary Ledger sequence")
    assert_equal(primaryBefore.rootHash, canonicalOf(dibs, "guild-primary").rootHash,
      "the Secondary Ledger rebuild changed the Primary Ledger root hash")
  end)

  it("refuses a snapshot of an unknown ledger", function()
    local world, coordinator, dibs = setup()
    local classification = dibs.Ledger.ClassifyCanonicalRecovery("LDR-does-not-exist")
    assert_equal("UNRECOVERABLE_HISTORY", classification.classification, tostring(classification.reasonCode))
    local rebuilt = dibs.Ledger.RebuildLedgerProjections("LDR-does-not-exist")
    assert_false(rebuilt.rebuilt, "an unknown ledger was rebuilt")
    assert_equal("LEDGER_NOT_FOUND", rebuilt.reasonCode)
  end)

  it("refuses a canonical import as a second durable write path", function()
    local world, coordinator, dibs = setup()
    local exported = dibs.ImportExport.Export("full", { includeTransactions = true })
    assert_not_nil(exported, "the export was refused")

    -- A canonical operation commit is never importable as a new durable
    -- write path; an identical record at a known position is a no-op.
    local canonical = snapshotOf(dibs)
    local position = nil
    for key in pairs(canonical.commits or {}) do position = key break end
    if position then
      local preview = dibs.ImportExport.Preview(exported, "full", "merge", "Coordinator-Realm")
      assert_nil(preview, "a canonical package was previewed as importable")
    end
  end)
end)
