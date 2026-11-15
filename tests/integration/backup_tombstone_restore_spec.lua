local loader = require("helpers.load_addon")

local function setup()
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = true,
    guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 0 },
  } }))
end

local function createArchivedLedger(dibs)
  local proposed = dibs.MultiLedger.ProposeLedger(nil, "Tombstone restore regression")
  assert_true(proposed.ok, proposed.reasonCode)
  local approved = dibs.MultiLedger.ApproveLedger(nil, proposed.ledgerId)
  assert_true(approved.ok, approved.reasonCode)
  local archived = dibs.MultiLedger.ArchiveLedger(nil, proposed.ledgerId)
  assert_true(archived.ok, archived.reasonCode)
  return proposed.ledgerId
end

local function deleteLedger(dibs, ledgerId)
  local deleted = dibs.MultiLedger.DeleteLedger(nil, ledgerId, { confirmed = true })
  assert_true(deleted.ok, deleted.reasonCode)
  assert_nil(dibs.GetDB().ledgers[ledgerId])
  return dibs.DeepCopy(dibs.GetDB().ledgerDeletionTombstones[ledgerId])
end

describe("Backup ledger deletion tombstones", function()
  it("keeps an archived ledger deleted through repeated restore of an older full backup", function()
    local dibs = setup()
    local ledgerId = createArchivedLedger(dibs)
    local snapshot = assert(dibs.Backup.Create("full", "before ledger deletion"))
    assert_not_nil(snapshot.payload.ledgers[ledgerId])

    local tombstone = deleteLedger(dibs, ledgerId)
    local deletionRecord = dibs.DeepCopy(dibs.GetDB().governance.ledgerDeletionRecords[ledgerId])
    local db = dibs.GetDB()

    for _ = 1, 2 do
      local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
      local restored, reason = dibs.Backup.Restore(preview.previewId, true, "old recovery point", "Tester-Realm")
      assert_not_nil(restored, reason)
      assert_nil(db.ledgers[ledgerId])
      assert_equal(tombstone.deletedAt, db.ledgerDeletionTombstones[ledgerId].deletedAt)
      assert_equal(tombstone.deletedBy, db.ledgerDeletionTombstones[ledgerId].deletedBy)
      assert_equal(deletionRecord.timestamp, db.governance.ledgerDeletionRecords[ledgerId].timestamp)
      assert_equal(deletionRecord.actor, db.governance.ledgerDeletionRecords[ledgerId].actor)
      assert_true(db.ledger == db.ledgers[db.activeLedgerId])
    end
  end)

  it("does not resurrect a deleted ledger when importing an older full export", function()
    local dibs = setup()
    local ledgerId = createArchivedLedger(dibs)
    local oldExport = assert(dibs.ImportExport.Export("full"))
    local tombstone = deleteLedger(dibs, ledgerId)
    local db = dibs.GetDB()

    local preview = assert(dibs.ImportExport.Preview(oldExport, "full", "append", "Tester-Realm"))
    local imported, reason = dibs.ImportExport.Apply(preview.previewId, true, "old export", "Tester-Realm")
    assert_not_nil(imported, reason)
    assert_nil(db.ledgers[ledgerId])
    assert_equal(tombstone.deletedAt, db.ledgerDeletionTombstones[ledgerId].deletedAt)
    assert_equal(tombstone.deletedBy, db.ledgerDeletionTombstones[ledgerId].deletedBy)
  end)
end)
