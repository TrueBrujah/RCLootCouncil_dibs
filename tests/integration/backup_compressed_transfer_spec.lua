local loader = require("helpers.load_addon")
local codecs = require("helpers.backup_transport_codec")

describe("Compressed backup service integration", function()
  local dibs, db, oldNative
  before_each(function()
    oldNative, _G.C_EncodingUtil = _G.C_EncodingUtil, nil
    _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    db = dibs.GetDB()
    codecs.Install()
  end)
  after_each(function() _G.C_EncodingUtil = oldNative end)

  for _, scope in ipairs({ "local", "guild", "full" }) do
    it("reads compressed " .. scope .. " packages with unchanged schema and no active-state mutation", function()
      local before = assert(dibs.ImportExport.Encode(db.ledgers))
      local encoded, package, info = assert(dibs.ImportExport.Export(scope, { compressed = true }))
      assert_equal("DIBS-COMP-1|", encoded:sub(1, 12))
      local decoded = assert(dibs.ImportExport.Decode(encoded))
      assert_equal(package.checksum, decoded.checksum)
      assert_equal(1, decoded.packageVersion)
      assert_equal(before, assert(dibs.ImportExport.Encode(db.ledgers)))
      assert_equal(#encoded, info.encodedBytes)
      local legacy = assert(dibs.ImportExport.Export(scope))
      assert_equal("DIBS-PKG-1|", legacy:sub(1, 11))
      assert_not_nil(dibs.ImportExport.Decode(legacy))
    end)
  end

  it("imports historical local configuration via normal preview and confirmation", function()
    db.settings.theme = "historical"
    local saved = assert(dibs.Backup.Create("local", "compressed historical"))
    db.settings.theme = "live"
    local encoded = assert(dibs.Backup.ExportSnapshot(saved.snapshotId, { compressed = true }))
    local before = assert(dibs.ImportExport.Encode(db.ledgers))
    local preview = assert(dibs.ImportExport.Preview(encoded, "local", "merge"))
    assert_equal("live", db.settings.theme)
    assert_not_nil(dibs.ImportExport.Apply(preview.previewId, true, "historical config"))
    assert_equal("historical", db.settings.theme)
    assert_equal(before, assert(dibs.ImportExport.Encode(db.ledgers)))
  end)

  it("retains large original packages compressed and exports their historical bytes", function()
    local original = string.rep("historical backup payload ", 12000)
    db.backupCompressionFixture = original
    local saved = assert(dibs.Backup.Create("full", "large compressed snapshot"))
    assert_nil(saved.packageText)
    assert_not_nil(saved.compressedPackageText)
    assert_true(#saved.compressedPackageText <= 250000)
    db.backupCompressionFixture = "new live value"
    local encoded, package, info = assert(dibs.Backup.ExportSnapshot(saved.snapshotId,
      { compressed = true, confirmedSensitive = true }))
    assert_equal(original, package.payload.backupCompressionFixture)
    assert_true(info.rawBytes > 250000)
    assert_true(info.encodedBytes < info.rawBytes)
    assert_equal(saved.packageChecksum, assert(dibs.ImportExport.Decode(encoded)).checksum)
    local raw, reason = dibs.Backup.ExportSnapshot(saved.snapshotId, { confirmedSensitive = true })
    assert_nil(raw); assert_equal("PACKAGE_TOO_LARGE", reason)
    assert_true(dibs.Backup.ValidateSnapshotExport(saved.snapshotId,
      { compressed = true, confirmedSensitive = true, expectedPackageText = encoded }))
    assert_not_nil(dibs.Backup.PreviewRestore(saved.snapshotId))
  end)

  it("preserves local snapshot creation and legacy export without an available codec", function()
    _G.LibStub, _G.C_EncodingUtil = nil, nil
    assert_not_nil(dibs.Backup.Create("local", "no codec"))
    assert_not_nil(dibs.ImportExport.Export("local"))
    local encoded, reason = dibs.ImportExport.Export("local", { compressed = true })
    assert_nil(encoded); assert_equal("COMPRESSION_UNAVAILABLE", reason)
    db.backupCompressionFixture = string.rep("local large snapshot ", 15000)
    local saved = assert(dibs.Backup.Create("full", "still local"))
    assert_nil(saved.packageText)
    assert_nil(saved.compressedPackageText)
  end)

  it("retains sensitive confirmation and verifies corruption without mutation", function()
    local saved = assert(dibs.Backup.Create("full", "confirm"))
    local before = assert(dibs.ImportExport.Encode(db.ledgers))
    local encoded, reason = dibs.Backup.ExportSnapshot(saved.snapshotId, { compressed = true })
    assert_nil(encoded); assert_equal("SENSITIVE_CONFIRMATION_REQUIRED", reason)
    encoded = assert(dibs.Backup.ExportSnapshot(saved.snapshotId, { compressed = true, confirmedSensitive = true }))
    local altered = encoded:gsub("|[0-9a-f]+|", "|00000000|", 1)
    assert_nil(dibs.ImportExport.Preview(altered, "full", "append"))
    assert_equal(before, assert(dibs.ImportExport.Encode(db.ledgers)))
  end)

  it("does not make compressed full imports a canonical adoption writer", function()
    local encoded, package = assert(dibs.ImportExport.Export("full", { compressed = true }))
    local id
    for rowId, row in pairs(package.payload.ledger.transactions) do
      if row.classification == "LOCAL_CANONICAL" then id = rowId; break end
    end
    assert_not_nil(id)
    db.ledger.transactions[id] = nil
    local before = assert(dibs.ImportExport.Encode(db.ledgers))
    local preview = assert(dibs.ImportExport.Preview(encoded, "full", "append"))
    local applied = dibs.ImportExport.Apply(preview.previewId, true, "not a canonical writer")
    assert_nil(applied)
    assert_equal(before, assert(dibs.ImportExport.Encode(db.ledgers)))
  end)

  it("restores a valid local payload without its optional transport codec", function()
    local original = string.rep("local retained payload ", 13000)
    db.backupCompressionFixture = original
    local saved = assert(dibs.Backup.Create("full", "optional transport"))
    assert_not_nil(saved.compressedPackageText)
    assert_nil(saved.packageText)
    db.backupCompressionFixture = "changed"
    _G.LibStub, _G.C_EncodingUtil = nil, nil
    local preview = assert(dibs.Backup.PreviewRestore(saved.snapshotId))
    assert_not_nil(dibs.Backup.Restore(preview.previewId, true, "local restore without codec"))
    assert_equal(original, db.backupCompressionFixture)
    codecs.Install()
    local live = assert(dibs.Backup.Get(saved.snapshotId))
    live.compressedPackageText = "corrupt optional transport"
    db.backupCompressionFixture = "changed again"
    preview = assert(dibs.Backup.PreviewRestore(saved.snapshotId))
    assert_not_nil(dibs.Backup.Restore(preview.previewId, true, "valid payload independent of wire"))
    assert_equal(original, db.backupCompressionFixture)
    assert_nil(dibs.Backup.ExportSnapshot(saved.snapshotId, { compressed = true, confirmedSensitive = true }))
  end)
end)
