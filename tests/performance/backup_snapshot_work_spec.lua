local loader = require("helpers.load_addon")

describe("Backup snapshot capture work and isolation", function()
  local dibs
  before_each(function()
    _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
  end)

  for _, scope in ipairs({ "local", "guild", "full" }) do
    it("captures exactly one coherent " .. scope .. " payload", function()
      local original = dibs.ImportExport.GetPayload
      local captures, captured = 0, nil
      dibs.ImportExport.GetPayload = function(...)
        captures = captures + 1
        local payload, realm, character, reason = original(...)
        captured = payload
        return payload, realm, character, reason
      end
      local snapshot, reason = dibs.Backup.Create(scope, "single capture")
      dibs.ImportExport.GetPayload = original
      assert_not_nil(snapshot, reason)
      assert_equal(1, captures, "snapshot and attested package must use the same database capture")
      local package = assert(dibs.ImportExport.Decode(snapshot.packageText, { allowOversize = true, allowUnsafe = true }))
      assert_equal(assert(dibs.ImportExport.Encode(captured)), assert(dibs.ImportExport.Encode(snapshot.payload)))
      assert_equal(assert(dibs.ImportExport.Encode(package.payload)), assert(dibs.ImportExport.Encode(snapshot.payload)))
      assert_equal(package.checksum, snapshot.packageChecksum)
      assert_equal(dibs.ImportExport.Checksum(assert(dibs.ImportExport.Encode(snapshot.payload))), snapshot.payloadChecksum)
    end)
  end

  it("isolates captured full data from live edits and the returned snapshot", function()
    local db = dibs.GetDB()
    db.settings.theme = "captured"
    db.backupWorkFixture = { nested = { value = "captured" } }
    local snapshot = assert(dibs.Backup.Create("full", "snapshot isolation"))
    local originalPayload = assert(dibs.ImportExport.Encode(snapshot.payload))
    db.settings.theme = "live"
    db.backupWorkFixture.nested.value = "live"
    assert_equal(originalPayload, assert(dibs.ImportExport.Encode(snapshot.payload)))
    snapshot.payload.backupWorkFixture.nested.value = "caller"
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    assert_equal("captured", stored.payload.backupWorkFixture.nested.value)
    assert_equal(originalPayload, assert(dibs.ImportExport.Encode(stored.payload)))
    assert_not_nil(dibs.Backup.PreviewRestore(snapshot.snapshotId))
  end)
end)
