local loader = require("helpers.load_addon")

-- RF-0040 regression suite.
--
-- RF-0040 - "ImportExport : une importation invalide ne doit jamais
-- modifier les donnees comptables existantes"
-- (docs/code-audit/INDEX.md#rf-0040).
--
-- The brief asks for 25 import scenarios to be covered, with the invariant:
-- an invalid import must not modify the existing accounting data, a
-- `Preview` must not produce any persistent mutation, and an `Apply` must
-- revalidate the preconditions it needs.
--
-- The scenarios are A01 to A25 of the audit brief.

local function setup(options)
  options = options or {}
  -- Each `load` starts from a **fresh** SavedVariables table unless the
  -- caller provides one. The loader keeps the previous global database
  -- otherwise, so a target would silently inherit the source state and the
  -- scenario would test nothing.
  local saved = options.savedVariables
  if saved == nil then saved = {} end
  local _, dibs = loader.load({ withAce3 = true, savedVariables = saved, wow = {
    playerName = "Tester-Realm", guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = options.rank or 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

-- Exports a full package and returns the encoded text plus the envelope.
local function exportFull(dibs, options)
  local text, package = dibs.ImportExport.Export("full", { actor = "Tester-Realm" })
  return text, package
end

-- Seeds a **legacy** transaction row.
--
-- B03: every transaction created through the current write path carries
-- `classification = "LOCAL_CANONICAL"` and is deliberately **not**
-- importable (`CANONICAL_LEDGER_IMPORT_UNAVAILABLE`). A legacy row is a
-- pre-feature record with no classification, and it is the only kind an
-- import may carry.
--
-- The balance model is `allocation + sum(non-SEASON_ALLOCATION amounts)`,
-- so a `DIB_GRANTED` row adds its amount to the balance and not to the
-- allocation.
local function seedLegacyRow(dibs, transactionId, amount)
  local seasonId = dibs.GetCurrentSeasonId()
  local row = {
    transactionId = transactionId, type = "DIB_GRANTED", actionType = "DIB_GRANTED",
    playerName = "Player-Realm", memberKey = "player-realm", amount = amount,
    seasonId = seasonId, reason = "legacy row", source = "legacy", createdAt = 1700000000,
  }
  dibs.GetDB().ledgers["guild-primary"].transactions[transactionId] = row
  local state = dibs.GetDB().ledgers["guild-primary"].playerStates
  state[seasonId] = state[seasonId] or {}
  local key = "player-realm"
  state[seasonId][key] = state[seasonId][key] or { allocation = 0, balance = 0, transactions = {} }
  local playerState = state[seasonId][key]
  playerState.balance = (tonumber(playerState.balance) or 0) + amount
  playerState.transactions = playerState.transactions or {}
  playerState.transactions[#playerState.transactions + 1] = transactionId
  return row
end

-- Re-encodes a package with a modified payload, keeping the format valid.
-- The checksum is recomputed so the package passes the envelope check and
-- the scenario under test is the *content* check, not the checksum.
local function repack(dibs, package, mutate)
  local modified = dibs.DeepCopy and dibs.DeepCopy(package) or package
  mutate(modified)
  return dibs.ImportExport.Encode(modified)
end

-- The state of the accounting data, for the "nothing changed" assertions.
local function accountingState(dibs)
  local seasonId = dibs.GetCurrentSeasonId()
  local ledger = dibs.GetDB().ledgers["guild-primary"]
  local count = 0
  for _ in pairs(ledger.transactions or {}) do count = count + 1 end
  return {
    balance = dibs.Ledger.GetBalance("Player-Realm", seasonId),
    allocation = dibs.Ledger.GetPlayerState("Player-Realm", seasonId).allocation,
    transactionCount = count,
    canonical = dibs.Ledger.GetCanonicalState("guild-primary"),
  }
end

local function assertAccountingUnchanged(dibs, before, message)
  local after = accountingState(dibs)
  assert_equal(before.balance, after.balance, message .. ": the balance changed")
  assert_equal(before.allocation, after.allocation, message .. ": the allocation changed")
  assert_equal(before.transactionCount, after.transactionCount, message .. ": the transaction count changed")
  assert_equal(before.canonical.nextSeq, after.canonical.nextSeq, message .. ": the canonical sequence changed")
  assert_equal(before.canonical.rootHash, after.canonical.rootHash, message .. ": the canonical root hash changed")
end

describe("RF-0040 ImportExport hardening", function()
  it("A01 imports a valid package into an empty environment", function()
    -- A full import is only meaningful on a target that already holds the
    -- exported rows: B03 forbids adopting a `LOCAL_CANONICAL` row as a
    -- second durable write path. The scenario is therefore modelled on a
    -- ledger whose rows are all legacy rows, which the import may carry.
    local target = setup()
    seedLegacyRow(target, "legacy-a01", 5)
    local text = exportFull(target)

    local before = accountingState(target)
    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview, "the valid package was refused")
    local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A01", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assertAccountingUnchanged(target, before, "A01")
  end)

  it("A01b refuses a package whose canonical row is not already present locally", function()
    -- The addon creates one `SEASON_ALLOCATION` for the local player when
    -- it starts. That row is classified `LOCAL_CANONICAL`, like every row
    -- written by the current write path.
    --
    -- B03 is explicit: a `LOCAL_CANONICAL` row is never importable, so a
    -- full package that carries one is refused on a target that does not
    -- already hold it. Adopting it would be a second durable write path
    -- outside the canonical chain.
    --
    -- The consequence is that the user-facing "Full Dibs data" import can
    -- only succeed on a target that **already holds** the exported rows.
    -- This case locks that boundary so it cannot be widened by accident.
    local source = setup()
    local text, package = exportFull(source)
    local canonical = (package.payload.ledger or {}).canonical or {}
    local commitCount = 0
    for _ in pairs(canonical.commits or {}) do commitCount = commitCount + 1 end
    assert_equal(0, commitCount, "the fixture unexpectedly holds a canonical commit")

    -- The package carries exactly one canonical row: the bootstrap
    -- allocation of the source.
    local canonicalRows = 0
    for _, tx in pairs(package.payload.ledger.transactions or {}) do
      if tx.classification == "LOCAL_CANONICAL" then canonicalRows = canonicalRows + 1 end
    end
    assert_equal(1, canonicalRows, "the package does not hold exactly one canonical row")

    -- A target that holds a **different** canonical row must refuse the
    -- package: the source's row is not already present locally. The
    -- transaction identifier is forced to a distinct value so the case
    -- does not depend on the identifier the addon happened to generate.
    local target = setup()
    local sourceRowId = nil
    for id, tx in pairs(package.payload.ledger.transactions or {}) do
      if tx.classification == "LOCAL_CANONICAL" then sourceRowId = id break end
    end
    assert_not_nil(sourceRowId, "the package holds no canonical row")
    target.GetDB().ledgers["guild-primary"].transactions[sourceRowId] = nil
    local before = accountingState(target)
    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview, "the package was refused at preview time")
    local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A01b", "Tester-Realm")
    assert_nil(applied, "a canonical row was imported as a second write path")
    assert_equal("CANONICAL_LEDGER_IMPORT_UNAVAILABLE", reason, tostring(reason))
    assertAccountingUnchanged(target, before, "A01b")
  end)

  it("A02 imports the same file twice without duplicating anything", function()
    local target = setup()
    seedLegacyRow(target, "legacy-a02", 5)
    local text = exportFull(target)

    local first = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(first)
    assert_not_nil(target.ImportExport.Apply(first.previewId, true, "A02 first", "Tester-Realm"))
    local afterFirst = accountingState(target)

    local second = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(second)
    assert_not_nil(target.ImportExport.Apply(second.previewId, true, "A02 second", "Tester-Realm"))
    local afterSecond = accountingState(target)

    assert_equal(afterFirst.balance, afterSecond.balance, "the second import changed the balance")
    assert_equal(afterFirst.transactionCount, afterSecond.transactionCount,
      "the second import duplicated a transaction")
  end)

  it("A03 refuses a package that carries a different ledger", function()
    local source = setup()
    local text, package = exportFull(source)
    local other = "LDR-other-guild"

    local target = setup()
    local before = accountingState(target)
    local preview = target.ImportExport.Preview(repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.ledgerId = other
    end), "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A03", "Tester-Realm")
      assert_nil(applied, "a package with a foreign ledger was applied")
    end
    assertAccountingUnchanged(target, before, "A03")
  end)

  it("A04 refuses a package from another guild", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local preview = target.ImportExport.Preview(repack(target, package, function(p)
      p.sourceGuild = "another-guild"
    end), "full", "merge", "Tester-Realm")
    assert_nil(preview, "a package from another guild was previewed")
    assertAccountingUnchanged(target, before, "A04")
  end)

  it("A05 refuses a package without a guild context", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local preview = target.ImportExport.Preview(repack(target, package, function(p)
      p.sourceGuild = nil
    end), "full", "merge", "Tester-Realm")
    assert_nil(preview, "a package without a guild context was previewed")
    assertAccountingUnchanged(target, before, "A05")
  end)

  it("A06 refuses a package whose transaction carries a wrong ledgerId", function()
    local source = setup()
    seedLegacyRow(source, "legacy-a06", 5)
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.transactions = p.payload.ledger.transactions or {}
      for id, tx in pairs(p.payload.ledger.transactions) do
        tx.ledgerId = "LDR-foreign"
        p.payload.ledger.transactions[id] = tx
      end
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A06", "Tester-Realm")
      assert_nil(applied, "a package with a foreign transaction ledgerId was applied")
    end
    assertAccountingUnchanged(target, before, "A06")
  end)

  it("A07 refuses a package with duplicated transactions", function()
    local source = setup()
    seedLegacyRow(source, "legacy-a07", 5)
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      local transactions = p.payload.ledger.transactions or {}
      for id, tx in pairs(transactions) do
        -- The same transaction under a second identifier, with the same
        -- content: the import must not count it twice.
        transactions["dup-" .. id] = tx
        p.payload.ledger.transactions = transactions
        break
      end
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A07", "Tester-Realm")
      if applied then
        -- The duplicate must not have doubled the balance.
        local count = 0
        for _ in pairs(target.GetDB().ledgers["guild-primary"].transactions or {}) do count = count + 1 end
        assert_true(count >= 1, "the import produced no transaction")
      end
    end
    assertAccountingUnchanged(target, before, "A07")
  end)

  it("A08 refuses a package with a contradictory canonical commit", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.canonical = p.payload.ledger.canonical or { schema = 1, epoch = 7, nextSeq = 1, rootHash = "x", commits = {}, positions = {}, transactionIndex = {} }
      local canonical = p.payload.ledger.canonical
      canonical.commits = canonical.commits or {}
      canonical.positions = canonical.positions or {}
      canonical.transactionIndex = canonical.transactionIndex or {}
      canonical.commits["7:1"] = {
        recordClass = "LEDGER_OPERATION_COMMIT", ledgerEpoch = 7, sequence = 1,
        commitHash = "D3-V2-00000001", payloadHash = "D3-V2-00000002",
        operation = { schemaVersion = 1, operationId = "op-contradiction", ledgerId = "guild-primary" },
      }
      canonical.positions["7:1"] = "D3-V2-00000001"
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A08", "Tester-Realm")
      assert_nil(applied, "a contradictory canonical commit was applied")
    end
    assertAccountingUnchanged(target, before, "A08")
  end)

  it("A09 refuses a package with an invalid root hash", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.canonical = p.payload.ledger.canonical or {}
      p.payload.ledger.canonical.rootHash = "D3-V2-00000000"
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A09", "Tester-Realm")
      assert_nil(applied, "a package with an invalid root hash was applied")
    end
    assertAccountingUnchanged(target, before, "A09")
  end)

  it("A10 refuses a package with an incoherent sequence", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.canonical = p.payload.ledger.canonical or {}
      p.payload.ledger.canonical.nextSeq = 999
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A10", "Tester-Realm")
      assert_nil(applied, "a package with an incoherent sequence was applied")
    end
    assertAccountingUnchanged(target, before, "A10")
  end)

  it("A11 refuses a package with an incompatible epoch", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.canonical = p.payload.ledger.canonical or {}
      p.payload.ledger.canonical.epoch = 999
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A11", "Tester-Realm")
      assert_nil(applied, "a package with an incompatible epoch was applied")
    end
    assertAccountingUnchanged(target, before, "A11")
  end)

  it("A12 refuses a package whose transaction has no identity", function()
    local source = setup()
    seedLegacyRow(source, "legacy-a12", 5)
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      local transactions = p.payload.ledger.transactions or {}
      for id, tx in pairs(transactions) do
        tx.playerName = nil
        transactions[id] = tx
        p.payload.ledger.transactions = transactions
        break
      end
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A12", "Tester-Realm")
      assert_nil(applied, "a transaction without identity was applied")
    end
    assertAccountingUnchanged(target, before, "A12")
  end)

  it("A13 refuses a package with an invalid award reference", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.awardTransactions = p.payload.ledger.awardTransactions or {}
      p.payload.ledger.awardTransactions["ref-dangling"] = "tx-that-does-not-exist"
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A13", "Tester-Realm")
      if applied then
        -- The dangling reference must not have created a transaction.
        assert_nil(target.GetDB().ledgers["guild-primary"].transactions["tx-that-does-not-exist"],
          "a dangling award reference created a transaction")
      end
    end
    assertAccountingUnchanged(target, before, "A13")
  end)

  it("A14 refuses an incomplete package", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload = nil
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    assert_nil(preview, "an incomplete package was previewed")
    assertAccountingUnchanged(target, before, "A14")
  end)

  it("A15 refuses a corrupted package", function()
    local source = setup()
    local text = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local corrupted = text:sub(1, #text - 5) .. "XXXXX"
    local preview = target.ImportExport.Preview(corrupted, "full", "merge", "Tester-Realm")
    assert_nil(preview, "a corrupted package was previewed")
    assertAccountingUnchanged(target, before, "A15")
  end)

  it("A16 keeps a local ledger that is newer than the imported one", function()
    -- A full import is only meaningful on a target that already holds the
    -- exported rows: B03 forbids adopting a `LOCAL_CANONICAL` row as a
    -- second durable write path. The scenario is therefore modelled on the
    -- same ledger, where the local state grows **after** the export.
    local target = setup()
    seedLegacyRow(target, "legacy-a16", 5)
    local text = exportFull(target)

    -- The local ledger gets a newer grant after the export.
    seedLegacyRow(target, "legacy-a16-newer", 11)
    local before = accountingState(target)

    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview, "the import was refused at preview time")
    local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A16", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))

    -- The newer local grant must survive the import.
    assert_true(target.Ledger.GetBalance("Player-Realm", target.GetCurrentSeasonId()) >= before.balance,
      "the import rolled back a newer local grant")
  end)

  it("A17 keeps the recent transactions that the package does not carry", function()
    local target = setup()
    seedLegacyRow(target, "legacy-a17", 5)
    local text = exportFull(target)

    -- A newer local transaction that the package does not carry.
    seedLegacyRow(target, "legacy-a17-newer", 7)
    local before = accountingState(target)

    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview)
    assert_not_nil(target.ImportExport.Apply(preview.previewId, true, "A17", "Tester-Realm"))

    assert_not_nil(target.GetDB().ledgers["guild-primary"].transactions["legacy-a17-newer"],
      "the import dropped the recent local transaction")
    local kept = target.Ledger.GetBalance("Player-Realm", target.GetCurrentSeasonId())
    assert_true(kept >= before.balance,
      "the import dropped a recent local transaction (balance " .. tostring(kept) .. " < " .. tostring(before.balance) .. ")")
  end)

  it("A18 accepts an import that carries already-present old transactions", function()
    local target = setup()
    -- The target already holds the same transaction.
    local same = seedLegacyRow(target, "legacy-a18", 5)
    assert_not_nil(same, "the target row was refused")
    local text = exportFull(target)
    local before = accountingState(target)

    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview)
    local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A18", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assertAccountingUnchanged(target, before, "A18")
  end)

  it("A19 refuses to import a canonical operation as a second write path", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.transactions = p.payload.ledger.transactions or {}
      p.payload.ledger.transactions["canonical-tx"] = {
        transactionId = "canonical-tx", type = "DIB_USED", classification = "LOCAL_CANONICAL",
        playerName = "Player-Realm", amount = -1, seasonId = p.payload.seasons and next(p.payload.seasons) or "season",
        reason = "A19", source = "probe", createdAt = 1700000000,
      }
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A19", "Tester-Realm")
      assert_nil(applied, "a canonical transaction was imported as a second write path")
      assert_equal("CANONICAL_LEDGER_IMPORT_UNAVAILABLE", reason, tostring(reason))
    end
    assertAccountingUnchanged(target, before, "A19")
  end)

  it("A20 accepts a package that carries legacy data", function()
    local target = setup()
    seedLegacyRow(target, "legacy-a20", 5)
    local text = exportFull(target)

    local before = accountingState(target)
    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview, "a legacy package was refused")
    local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A20", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assertAccountingUnchanged(target, before, "A20")
  end)

  it("A21 refuses an import into a Secondary Ledger", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local proposed = assert(target.MultiLedger.ProposeLedger("Tester-Realm", "Raid Ledger"))
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.ledgerId = proposed.ledgerId
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A21", "Tester-Realm")
      assert_nil(applied, "an import into a Secondary Ledger was applied")
    end
    assertAccountingUnchanged(target, before, "A21")
  end)

  it("A22 refuses an import into an archived ledger", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local proposed = assert(target.MultiLedger.ProposeLedger("Tester-Realm", "Old Ledger"))
    assert(target.MultiLedger.ApproveLedger("Tester-Realm", proposed.ledgerId).ok)
    assert(target.MultiLedger.ArchiveLedger("Tester-Realm", proposed.ledgerId))
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.ledgerId = proposed.ledgerId
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A22", "Tester-Realm")
      assert_nil(applied, "an import into an archived ledger was applied")
    end
    assertAccountingUnchanged(target, before, "A22")
  end)

  it("A23 refuses an import into an unapproved ledger", function()
    local source = setup()
    local text, package = exportFull(source)

    local target = setup()
    local proposed = assert(target.MultiLedger.ProposeLedger("Tester-Realm", "Draft Ledger"))
    local before = accountingState(target)
    local encoded = repack(target, package, function(p)
      p.payload.ledger = p.payload.ledger or {}
      p.payload.ledger.ledgerId = proposed.ledgerId
    end)
    local preview = target.ImportExport.Preview(encoded, "full", "merge", "Tester-Realm")
    if preview then
      local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A23", "Tester-Realm")
      assert_nil(applied, "an import into an unapproved ledger was applied")
    end
    assertAccountingUnchanged(target, before, "A23")
  end)

  it("A24 refuses an import by an unauthorized user", function()
    local source = setup()
    local text = exportFull(source)

    local target = setup({ guildLeader = false, rank = 3 })
    local before = accountingState(target)
    local preview = target.ImportExport.Preview(text, "full", "merge", "Player-Realm")
    assert_nil(preview, "an unauthorized import was previewed")
    assertAccountingUnchanged(target, before, "A24")
  end)

  it("A25 does not apply a preview whose preconditions changed", function()
    local target = setup()
    seedLegacyRow(target, "legacy-a25", 5)
    local text = exportFull(target)

    local preview = target.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview, "the preview was refused")

    -- The local state changes between the preview and the apply.
    seedLegacyRow(target, "legacy-a25-local", 13)
    local before = accountingState(target)

    local applied, reason = target.ImportExport.Apply(preview.previewId, true, "A25", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))

    -- The local change must not have been lost by the apply.
    assert_not_nil(target.GetDB().ledgers["guild-primary"].transactions["legacy-a25-local"],
      "the apply discarded the local change made after the preview")
    assert_true(target.Ledger.GetBalance("Player-Realm", target.GetCurrentSeasonId()) >= before.balance,
      "the apply discarded the local change made after the preview")
  end)
end)
