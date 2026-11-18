local loader = require("helpers.load_addon")

describe("Bounded import and restore preview lifecycle", function()
  local dibs, db, clock, originalTime
  local function count(rows)
    local total = 0
    for _ in pairs(rows or {}) do total = total + 1 end
    return total
  end
  local function fingerprint()
    return assert(dibs.ImportExport.Encode({ ledgers = db.ledgers, governance = db.governance,
      tombstones = db.ledgerDeletionTombstones, settings = db.settings, backups = db.backups,
      audit = db.auditLog }))
  end
  local function create(kind, scope)
    scope = scope or "local"
    if kind == "import" then
      return assert(dibs.ImportExport.Preview(assert(dibs.ImportExport.Export(scope)), scope, "merge"))
    end
    local snapshot = assert(dibs.Backup.Create(scope, "preview lifecycle"))
    return assert(dibs.Backup.PreviewRestore(snapshot.snapshotId))
  end
  local function apply(kind, id, confirm)
    if kind == "import" then return dibs.ImportExport.Apply(id, confirm, "preview lifecycle") end
    return dibs.Backup.Restore(id, confirm, "preview lifecycle")
  end
  before_each(function()
    _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    db = dibs.GetDB()
    originalTime, clock = _G.time, 1800000000
    _G.time = function() return clock end
  end)
  after_each(function() _G.time = originalTime end)

  for _, kind in ipairs({ "import", "restore" }) do
    local storeKey = kind == "import" and "pendingImports" or "pendingRestores"

    it("bounds abandoned " .. kind .. " previews without deleting persistent records", function()
      local ids = {}
      local text, snapshot
      if kind == "import" then text = assert(dibs.ImportExport.Export("full"))
      else snapshot = assert(dibs.Backup.Create("full", "bounded preview")) end
      local ledgerBefore = assert(dibs.ImportExport.Encode(db.ledgers))
      local backupsBefore = assert(dibs.ImportExport.Encode(db.backups))
      for index = 1, 20 do
        local preview
        if text then preview = assert(dibs.ImportExport.Preview(text, "full", "append"))
        else preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId)) end
        ids[index] = preview.previewId
        clock = clock + 1
      end
      assert_equal(16, count(db[storeKey]))
      for index = 1, 4 do assert_nil(db[storeKey][ids[index]]) end
      for index = 5, 20 do assert_not_nil(db[storeKey][ids[index]]) end
      assert_equal(ledgerBefore, assert(dibs.ImportExport.Encode(db.ledgers)))
      assert_equal(backupsBefore, assert(dibs.ImportExport.Encode(db.backups)))
      local before = fingerprint()
      local result, reason = apply(kind, ids[1], true)
      assert_nil(result); assert_equal("PREVIEW_NOT_FOUND", reason)
      assert_equal(before, fingerprint())
    end)

    it("keeps " .. kind .. " previews usable until the exact thirty-minute boundary", function()
      local preview = create(kind)
      clock = preview.createdAt + 1799
      local cancelled = assert(apply(kind, preview.previewId, false))
      assert_equal("cancelled", cancelled.decision)
      assert_nil(db[storeKey][preview.previewId])
      local expired = create(kind)
      clock = expired.createdAt + 1800
      local before = fingerprint()
      local result, reason = apply(kind, expired.previewId, true)
      assert_nil(result); assert_equal("PREVIEW_NOT_FOUND", reason)
      assert_nil(db[storeKey][expired.previewId])
      assert_equal(before, fingerprint(), "expiry must not create a safety backup or change active data")
    end)

    it("purges legacy and invalid " .. kind .. " timestamps when creating another preview", function()
      db[storeKey] = {
        missing = { preview = {} }, malformed = { preview = { createdAt = "1800000000" } },
        future = { preview = { createdAt = clock + 1 } },
        nan = { preview = { createdAt = 0 / 0 } },
        infinity = { preview = { createdAt = math.huge } },
        expired = { preview = { createdAt = clock - 1800 } },
        broken = false,
      }
      local preview = create(kind)
      assert_equal(1, count(db[storeKey]))
      assert_not_nil(db[storeKey][preview.previewId])
    end)

    it("confirms a current " .. kind .. " preview and releases its transient data", function()
      db.settings.theme = "captured"
      local preview = create(kind)
      db.settings.theme = "live"
      local ledgerBefore = assert(dibs.ImportExport.Encode(db.ledgers))
      clock = preview.createdAt + 1799
      local result = assert(apply(kind, preview.previewId, true))
      assert_equal("confirmed", result.decision)
      assert_equal("captured", db.settings.theme)
      assert_nil(db[storeKey][preview.previewId])
      assert_equal(ledgerBefore, assert(dibs.ImportExport.Encode(db.ledgers)))
    end)

    it("revalidates " .. kind .. " permissions at confirmation", function()
      local preview = create(kind, "guild")
      local before = fingerprint()
      local originalCan = dibs.Permissions.Can
      dibs.Permissions.Can = function() return false end
      local result, reason = apply(kind, preview.previewId, true)
      dibs.Permissions.Can = originalCan
      assert_nil(result); assert_equal("GUILD_ADMIN_REQUIRED", reason)
      assert_equal(before, fingerprint())
      assert_not_nil(db[storeKey][preview.previewId], "a failed authorization must not confirm the preview")
    end)
  end

  it("evicts equal-age previews deterministically and restricts pruning to transient stores", function()
    db.pendingImports = {}
    for index = 20, 1, -1 do
      local id = string.format("preview-%02d", index)
      db.pendingImports[id] = { preview = { createdAt = clock } }
    end
    local before = fingerprint()
    dibs.ImportExport.PrunePendingPreviews(db, "pendingImports", clock)
    assert_equal(16, count(db.pendingImports))
    assert_nil(db.pendingImports["preview-04"])
    assert_not_nil(db.pendingImports["preview-05"])
    assert_nil(dibs.ImportExport.PrunePendingPreviews(db, "backups", clock))
    assert_nil(dibs.ImportExport.PrunePendingPreviews(db, "auditLog", clock))
    assert_equal(before, fingerprint())
  end)
end)
