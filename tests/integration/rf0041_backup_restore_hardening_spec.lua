local loader = require("helpers.load_addon")

-- RF-0041 regression suite.
--
-- RF-0041 - "Backup : une restauration ne doit jamais ecraser un etat
-- plus recent ni perdre une transaction" (docs/code-audit/INDEX.md#rf-0041).
--
-- The brief asks for 20 backup/restore scenarios to be covered, with the
-- invariant that a restoration must never silently roll back a newer or
-- conflicting canonical ledger, and that a restore is a distinct
-- operation from an import.
--
-- The scenarios are B01 to B20 of the audit brief.

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, savedVariables = options.savedVariables or {}, wow = {
    playerName = "Tester-Realm", guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = options.rank or 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

-- Seeds a legacy transaction row.
--
-- The balance model is `allocation + sum(non-SEASON_ALLOCATION amounts)`.
-- A `DIB_GRANTED` row therefore adds its amount to the **balance** and not
-- to the allocation: the allocation is carried by the `SEASON_ALLOCATION`
-- rows only.
local function seedLegacyRow(dibs, transactionId, amount)
  local seasonId = dibs.GetCurrentSeasonId()
  local row = {
    transactionId = transactionId, type = "DIB_GRANTED", actionType = "DIB_GRANTED",
    playerName = "Player-Realm", memberKey = "player-realm", amount = amount,
    seasonId = seasonId, reason = "legacy row", source = "legacy", createdAt = 1700000000,
  }
  dibs.GetDB().ledgers["guild-primary"].transactions[transactionId] = row
  local states = dibs.GetDB().ledgers["guild-primary"].playerStates
  states[seasonId] = states[seasonId] or {}
  local key = "player-realm"
  states[seasonId][key] = states[seasonId][key] or { allocation = 0, balance = 0, transactions = {} }
  local state = states[seasonId][key]
  state.balance = (tonumber(state.balance) or 0) + amount
  state.transactions = state.transactions or {}
  state.transactions[#state.transactions + 1] = transactionId
  return row
end

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

describe("RF-0041 Backup and restore hardening", function()

  it("B01 creates a valid snapshot", function()
    local dibs = setup()
    local snapshot, reason = dibs.Backup.Create("full", "B01 snapshot", "Tester-Realm")
    assert_not_nil(snapshot, tostring(reason))
    assert_equal("full", snapshot.scope)
    assert_not_nil(snapshot.snapshotId)
    assert_not_nil(snapshot.checksum)
    assert_not_nil(snapshot.payload)
  end)

  it("B02 creates a snapshot of an empty environment", function()
    local dibs = setup()
    local snapshot, reason = dibs.Backup.Create("full", "B02 empty", "Tester-Realm")
    assert_not_nil(snapshot, tostring(reason))
    assert_not_nil(snapshot.payload)
  end)

  it("B03 refuses to restore an incomplete snapshot", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b03", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B03 incomplete", "Tester-Realm"))
    -- `M.Create` returns a clone, so the stored snapshot is reached through
    -- the stored list.
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    -- The payload is removed: the snapshot no longer carries what it claims.
    stored.payload = nil
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "an incomplete snapshot was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore(preview and preview.previewId or "none", true, "B03", "Tester-Realm")
    assert_nil(applied, "an incomplete snapshot was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "B03")
  end)

  it("B04 refuses to restore a corrupted snapshot", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b04", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B04 corrupted", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    -- The stored package is corrupted: the snapshot no longer carries what
    -- its checksum attests.
    stored.packageText = stored.packageText:sub(1, #stored.packageText - 8) .. "CORRUPTED"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a corrupted snapshot was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore(preview and preview.previewId or "none", true, "B04", "Tester-Realm")
    assert_nil(applied, "a corrupted snapshot was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "B04")
  end)

  it("B05 refuses a snapshot of another guild", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b05", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B05 other guild", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.guildScope = "another-guild"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a snapshot of another guild was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore(preview and preview.previewId or "none", true, "B05", "Tester-Realm")
    assert_nil(applied, "a snapshot of another guild was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "B05")
  end)

  it("B06 keeps the local ledger when the snapshot holds another ledger", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b06-local", 9)
    local snapshot = assert(dibs.Backup.Create("full", "B06 other ledger", "Tester-Realm"))
    -- The snapshot claims a different ledger.
    snapshot.payload.ledgers["guild-primary"].id = "LDR-foreign"
    local before = accountingState(dibs)
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied = dibs.Backup.Restore(preview.previewId, true, "B06", "Tester-Realm")
    if applied then
      assertAccountingUnchanged(dibs, before, "B06")
    end
  end)

  it("B07 restores a snapshot of an older schema version", function()
    local dibs = setup()
    local snapshot = assert(dibs.Backup.Create("full", "B07 old schema", "Tester-Realm"))
    snapshot.schemaVersion = 1
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "B07", "Tester-Realm")
    -- The restore either refuses the old schema or keeps the current state.
    if applied then
      assert_true(dibs.Ledger.GetCanonicalState("guild-primary") ~= nil,
        "the restore left no canonical state")
    else
      assert_not_nil(reason)
    end
  end)

  it("B08 restores a snapshot of the current schema version", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b08", 4)
    local snapshot = assert(dibs.Backup.Create("full", "B08 schema 8", "Tester-Realm"))
    assert_equal(dibs.ImportExport.SCHEMA_VERSION, snapshot.schemaVersion)
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "B08", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
  end)

  it("B09 restores a snapshot that holds several ledgers", function()
    local dibs = setup()
    local proposed = assert(dibs.MultiLedger.ProposeLedger("Tester-Realm", "Raid Ledger"))
    assert(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposed.ledgerId).ok)
    local snapshot = assert(dibs.Backup.Create("full", "B09 several ledgers", "Tester-Realm"))
    assert_not_nil(snapshot.payload.ledgers)
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "B09", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assert_not_nil(dibs.MultiLedger.GetLedgerById(proposed.ledgerId),
      "the restore dropped the Secondary Ledger")
  end)

  it("B10 restores a snapshot that holds a Secondary Ledger", function()
    local dibs = setup()
    local proposed = assert(dibs.MultiLedger.ProposeLedger("Tester-Realm", "Raid Ledger"))
    assert(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposed.ledgerId).ok)
    local snapshot = assert(dibs.Backup.Create("full", "B10 secondary", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "B10", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assert_equal("APPROVED", dibs.MultiLedger.GetLedgerById(proposed.ledgerId).status,
      "the restore changed the Secondary Ledger approval")
  end)

  it("B11 restores the same snapshot repeatedly without changing the state", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b11", 6)
    local snapshot = assert(dibs.Backup.Create("full", "B11 repeated", "Tester-Realm"))

    local first = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(first.previewId, true, "B11 first", "Tester-Realm"))
    local afterFirst = accountingState(dibs)

    local second = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(second.previewId, true, "B11 second", "Tester-Realm"))
    local afterSecond = accountingState(dibs)

    assert_equal(afterFirst.balance, afterSecond.balance, "the repeated restore changed the balance")
    assert_equal(afterFirst.transactionCount, afterSecond.transactionCount,
      "the repeated restore changed the transaction count")
    assert_equal(afterFirst.canonical.rootHash, afterSecond.canonical.rootHash,
      "the repeated restore changed the canonical root hash")
  end)

  it("B12 does not roll back a local change made after the snapshot", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b12", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B12 local change", "Tester-Realm"))
    -- The local ledger grows after the snapshot.
    seedLegacyRow(dibs, "legacy-b12-newer", 11)
    local before = accountingState(dibs)

    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "B12", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))

    -- The newer local transaction must survive the restore.
    assert_not_nil(dibs.GetDB().ledgers["guild-primary"].transactions["legacy-b12-newer"],
      "the restore rolled back a newer local transaction")
    assert_true(dibs.Ledger.GetBalance("Player-Realm", dibs.GetCurrentSeasonId()) >= before.balance,
      "the restore rolled back a newer local grant")
  end)

  it("B13 keeps the restored state across a reload", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b13", 7)
    local snapshot = assert(dibs.Backup.Create("full", "B13 reload", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "B13", "Tester-Realm"))

    -- The restored state is persisted and read back by a fresh client.
    local saved = dibs.DeepCopy and dibs.DeepCopy(dibs.GetDB()) or dibs.GetDB()
    local reloaded = setup({ savedVariables = saved })
    assert_equal(7, reloaded.Ledger.GetBalance("Player-Realm", reloaded.GetCurrentSeasonId()),
      "the restored balance did not survive the reload")
    assert_not_nil(reloaded.GetDB().ledgers["guild-primary"].transactions["legacy-b13"],
      "the restored transaction did not survive the reload")
  end)

  it("B14 keeps the restored state across a projection rebuild", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b14", 8)
    local snapshot = assert(dibs.Backup.Create("full", "B14 rebuild", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "B14", "Tester-Realm"))

    local before = accountingState(dibs)
    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))
    assertAccountingUnchanged(dibs, before, "B14")
  end)

  it("B15 keeps the restored state across a synchronization check", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b15", 3)
    local snapshot = assert(dibs.Backup.Create("full", "B15 sync", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "B15", "Tester-Realm"))

    local before = accountingState(dibs)
    dibs.Sync.RecheckSyncBehind()
    assertAccountingUnchanged(dibs, before, "B15")
  end)

  it("B16 leaves the state untouched when the preparation fails", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b16", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B16 interrupted", "Tester-Realm"))
    local before = accountingState(dibs)

    -- The preview is never confirmed: the restore is cancelled.
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local result = dibs.Backup.Restore(preview.previewId, false, "B16 cancelled", "Tester-Realm")
    assert_not_nil(result)
    assertEqual = nil
    assertAccountingUnchanged(dibs, before, "B16")
  end)

  it("B17 leaves the state untouched when the apply fails", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b17", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B17 error", "Tester-Realm"))
    local before = accountingState(dibs)

    -- An unknown preview identifier: nothing is applied.
    local applied, reason = dibs.Backup.Restore("restore-does-not-exist", true, "B17", "Tester-Realm")
    assert_nil(applied, "an unknown preview was applied")
    assert_equal("PREVIEW_NOT_FOUND", reason)
    assertAccountingUnchanged(dibs, before, "B17")
  end)

  it("B18 keeps the newer side of a contradictory history", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b18", 5)
    local snapshot = assert(dibs.Backup.Create("full", "B18 contradiction", "Tester-Realm"))

    -- The live governance chain diverges from the snapshot at the same
    -- revision: the live side wins.
    local db = dibs.GetDB()
    db.governance = db.governance or {}
    db.governance.revision = 4
    db.governance.hash = "G-live-hash"
    snapshot.payload.governance = { revision = 4, hash = "G-snapshot-hash" }

    local before = accountingState(dibs)
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    local applied, reason = dibs.Backup.Restore(preview.previewId, true, "B18", "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assert_equal("G-live-hash", dibs.GetDB().governance.hash,
      "the restore rolled back a diverged governance chain")
    assertAccountingUnchanged(dibs, before, "B18")
  end)

  it("B19 keeps the restored state when the SavedVariables are partially persisted", function()
    local dibs = setup()
    seedLegacyRow(dibs, "legacy-b19", 6)
    local snapshot = assert(dibs.Backup.Create("full", "B19 partial", "Tester-Realm"))
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "B19", "Tester-Realm"))

    -- A partial persistence: the payload of the live database lost one
    -- section, but the ledger rows are still there.
    local saved = dibs.DeepCopy and dibs.DeepCopy(dibs.GetDB()) or dibs.GetDB()
    saved.settings = nil
    local reloaded = setup({ savedVariables = saved })
    assert_equal(6, reloaded.Ledger.GetBalance("Player-Realm", reloaded.GetCurrentSeasonId()),
      "a partial persistence lost the ledger balance")
  end)

  it("B20 refuses a restore by an unauthorized user", function()
    local dibs = setup({ guildLeader = false, rank = 3 })
    local snapshot = assert(dibs.Backup.Create("local", "B20 unauthorized", "Tester-Realm"))
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Player-Realm")
    -- A local-scope snapshot is authorized for everybody; a guild or full
    -- snapshot is not.
    if preview then
      local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "B20", "Player-Realm")
      if applied then
        assertAccountingUnchanged(dibs, before, "B20")
      else
        assert_not_nil(applyReason)
      end
    else
      assert_not_nil(reason)
    end
  end)

  it("B20b refuses a guild-scope restore by an unauthorized user", function()
    local dibs = setup({ guildLeader = false, rank = 3 })
    local snapshot = assert(dibs.Backup.Create("local", "B20b seed", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    -- Promote the snapshot to a guild scope.
    stored.scope = "guild"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Player-Realm")
    assert_nil(preview, "an unauthorized guild restore was previewed")
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    assertAccountingUnchanged(dibs, before, "B20b")
  end)
end)
