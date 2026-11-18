local loader = require("helpers.load_addon")

local function setup(member)
  return select(2, loader.load({ withAce3 = true, wow = {
    playerName = "Tester-Realm", guildLeader = not member,
    guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = member and 3 or 0 },
  } }))
end

local function repack(dibs, package)
  package.checksum = nil
  local unsigned = assert(dibs.ImportExport.Encode(package))
  package.checksum = dibs.ImportExport.Checksum(unsigned:sub(#dibs.ImportExport.PACKAGE_PREFIX + 1))
  return assert(dibs.ImportExport.Encode(package))
end

local function archivedLedger(dibs)
  local proposed = dibs.MultiLedger.ProposeLedger(nil, "Deletion regression")
  assert_true(proposed.ok, proposed.reasonCode)
  local approved = dibs.MultiLedger.ApproveLedger(nil, proposed.ledgerId)
  assert_true(approved.ok, approved.reasonCode)
  assert_true(dibs.MultiLedger.ArchiveLedger(nil, proposed.ledgerId).ok)
  return proposed.ledgerId
end

local function deleteLedger(dibs, ledgerId)
  local result = dibs.MultiLedger.DeleteLedger(nil, ledgerId, { confirmed = true })
  assert_true(result.ok, result.reasonCode)
  assert_nil(dibs.GetDB().ledgers[ledgerId])
  assert_not_nil(dibs.GetDB().ledgerDeletionTombstones[ledgerId])
end

describe("Audit import and restore isolation", function()
  it("does not promote a member through imported local presentation settings", function()
    local dibs = setup(true)
    assert_false(dibs.Permissions.IsOfficer())
    local _, package = dibs.ImportExport.Export("local")
    package.payload.presentation.theme = "imported"
    package.payload.presentation.officerRankIndices = { [3] = true }
    package.payload.presentation.officerMaxRankIndex = 3
    package.payload.presentation.defaultAllocation = 99
    local preview = assert(dibs.ImportExport.Preview(repack(dibs, package), "local", "merge"))
    local result, reason = dibs.ImportExport.Apply(preview.previewId, true, "local scope")
    assert_not_nil(result, reason)
    assert_equal("imported", dibs.GetDB().settings.theme)
    assert_false(dibs.Permissions.IsOfficer())
    assert_false(dibs.Permissions.Can("settings.modify"))
    assert_true(dibs.GetDB().settings.defaultAllocation ~= 99)
  end)

  it("limits local replacement to presentation keys", function()
    local dibs = setup()
    local db = dibs.GetDB()
    db.settings.defaultAllocation = 12
    db.settings.officerRankIndices = { [1] = true }
    db.settings.raidReminderMessage = "keep policy"
    db.settings.theme = "old"
    db.settings.pageSize = 17
    local _, package = dibs.ImportExport.Export("local")
    package.payload.presentation = { theme = "new", defaultAllocation = 99 }
    local preview = assert(dibs.ImportExport.Preview(repack(dibs, package), "local", "replace"))
    assert_not_nil(dibs.ImportExport.Apply(preview.previewId, true, "replace local"))
    assert_equal(12, db.settings.defaultAllocation)
    assert_true(db.settings.officerRankIndices[1])
    assert_equal("keep policy", db.settings.raidReminderMessage)
    assert_equal("new", db.settings.theme)
    assert_nil(db.settings.pageSize)
  end)

  it("limits guild replacement to the exported policy keys", function()
    local dibs = setup()
    local db = dibs.GetDB()
    db.settings.theme = "keep presentation"
    db.settings.customFuturePolicy = "keep unsupported"
    local _, package = dibs.ImportExport.Export("guild")
    package.payload.settings = { defaultAllocation = 14, theme = "injected" }
    local preview = assert(dibs.ImportExport.Preview(repack(dibs, package), "guild", "replace"))
    assert_not_nil(dibs.ImportExport.Apply(preview.previewId, true, "replace guild"))
    assert_equal(14, db.settings.defaultAllocation)
    assert_equal("keep presentation", db.settings.theme)
    assert_equal("keep unsupported", db.settings.customFuturePolicy)
  end)

  it("preserves a deleted ledger and its evidence when restoring a pre-deletion backup", function()
    local dibs = setup()
    local ledgerId = archivedLedger(dibs)
    local snapshot = assert(dibs.Backup.Create("full", "before deletion"))
    local revision = dibs.GetDB().governance.revision
    deleteLedger(dibs, ledgerId)
    local db = dibs.GetDB()
    assert_equal(revision, db.governance.revision)
    local tombstone = dibs.DeepCopy(db.ledgerDeletionTombstones[ledgerId])
    local evidence = dibs.DeepCopy(db.governance.ledgerDeletionRecords[ledgerId])
    for _ = 1, 2 do
      local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId))
      assert_not_nil(dibs.Backup.Restore(preview.previewId, true, "restore before deletion"))
      assert_nil(db.ledgers[ledgerId])
      assert_equal(tombstone.deletedAt, db.ledgerDeletionTombstones[ledgerId].deletedAt)
      assert_equal(tombstone.deletedBy, db.ledgerDeletionTombstones[ledgerId].deletedBy)
      assert_equal(evidence.timestamp, db.governance.ledgerDeletionRecords[ledgerId].timestamp)
      assert_equal(evidence.actor, db.governance.ledgerDeletionRecords[ledgerId].actor)
      assert_not_nil(db.governance.ledgerDeletionRequests[ledgerId])
      assert_true(db.ledger == db.ledgers[db.activeLedgerId])
    end
  end)

  it("preserves deletion tombstones and evidence through a pre-deletion full import", function()
    local dibs = setup()
    local ledgerId = archivedLedger(dibs)
    local text = assert(dibs.ImportExport.Export("full"))
    deleteLedger(dibs, ledgerId)
    local db = dibs.GetDB()
    local evidence = dibs.DeepCopy(db.governance.ledgerDeletionRecords[ledgerId])
    local preview = assert(dibs.ImportExport.Preview(text, "full", "append"))
    assert_not_nil(dibs.ImportExport.Apply(preview.previewId, true, "import before deletion"))
    assert_nil(db.ledgers[ledgerId])
    assert_not_nil(db.ledgerDeletionTombstones[ledgerId])
    assert_equal(evidence.actor, db.governance.ledgerDeletionRecords[ledgerId].actor)
    assert_not_nil(db.governance.ledgerDeletionRequests[ledgerId])
  end)

  it("releases cancelled import and restore previews", function()
    local dibs = setup()
    local text = assert(dibs.ImportExport.Export("local"))
    local preview = assert(dibs.ImportExport.Preview(text, "local", "merge"))
    assert_equal("cancelled", dibs.ImportExport.Apply(preview.previewId, false).decision)
    assert_nil(dibs.GetDB().pendingImports[preview.previewId])
    local snapshot = assert(dibs.Backup.Create("local", "cancel test"))
    local restore = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId))
    assert_equal("cancelled", dibs.Backup.Restore(restore.previewId, false).decision)
    assert_nil(dibs.GetDB().pendingRestores[restore.previewId])
  end)
end)
