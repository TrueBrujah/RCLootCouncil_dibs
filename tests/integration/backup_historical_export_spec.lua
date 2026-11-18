local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("Selected historical backup export", function()
  local dibs, db
  local function accounting()
    return assert(dibs.ImportExport.Encode({ ledgers = db.ledgers, governance = db.governance,
      tombstones = db.ledgerDeletionTombstones, settings = db.settings }))
  end
  local function snapshot(scope)
    local saved = assert(dibs.Backup.Create(scope or "local", "historical export", "Tester-Realm"))
    return assert(dibs.Backup.Get(saved.snapshotId))
  end
  local function repack(saved, mutate)
    local package = assert(dibs.ImportExport.Decode(saved.packageText, { allowUnsafe = true }))
    mutate(package)
    package.checksum = nil
    local body = assert(dibs.ImportExport.Encode(package)):sub(#dibs.ImportExport.PACKAGE_PREFIX + 1)
    package.checksum = dibs.ImportExport.Checksum(body)
    saved.packageText = assert(dibs.ImportExport.Encode(package))
    saved.packageChecksum, saved.checksum = package.checksum, package.checksum
    saved.payload = dibs.DeepCopy(package.payload)
    saved.payloadChecksum = dibs.ImportExport.Checksum(assert(dibs.ImportExport.Encode(saved.payload)))
  end
  local function refused(saved, expected, options)
    local before, auditCount = accounting(), #(db.auditLog or {})
    local result, reason = dibs.Backup.ExportSnapshot(saved.snapshotId, options)
    assert_nil(result); assert_equal(expected, reason)
    assert_equal(before, accounting())
    assert_equal(auditCount, #(db.auditLog or {}), "rejected export must not record a successful export")
  end
  before_each(function()
    _, dibs = loader.load({ savedVariables = {}, withAce3 = true, wow = {
      playerName = "Tester-Realm", playerGUID = "Player-1-TESTER", guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Member-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } })
    db = dibs.GetDB()
  end)

  for _, scope in ipairs({ "local", "guild", "full" }) do
    it("exports original " .. scope .. " contents without reading current state", function()
      db.settings.theme, db.settings.defaultAllocation = "historical", 7
      local saved = snapshot(scope)
      local originalText = saved.packageText
      local originalPackage = assert(dibs.ImportExport.Decode(originalText))
      db.settings.theme, db.settings.defaultAllocation = "current", 99
      local before = accounting()
      local oldGetPayload, oldExport = dibs.ImportExport.GetPayload, dibs.ImportExport.Export
      dibs.ImportExport.GetPayload = function() error("historical export must not capture live data") end
      dibs.ImportExport.Export = function() error("historical export must not export live data") end
      local text, package = dibs.Backup.ExportSnapshot(saved.snapshotId,
        { actor = "Tester-Realm", confirmedSensitive = true, reason = "chosen snapshot" })
      dibs.ImportExport.GetPayload, dibs.ImportExport.Export = oldGetPayload, oldExport
      assert_equal(originalText, text)
      assert_equal(originalPackage.createdAt, package.createdAt)
      assert_equal(originalPackage.sourceCharacter, package.sourceCharacter)
      assert_equal(originalPackage.checksum, package.checksum)
      assert_equal(before, accounting())
      local event = db.auditLog[#db.auditLog]
      assert_equal("backup_export", event.action); assert_equal(saved.snapshotId, event.snapshotId)
      assert_equal(scope, event.scope); assert_equal("chosen snapshot", event.reason)
      assert_equal(dibs.Permissions.CanonicalPlayerId(nil), event.actor)
      assert_nil(event.packageText); assert_nil(event.payload)
      package.payload.changedByCaller = true
      assert_nil(saved.payload.changedByCaller, "returned package must be detached from the stored snapshot")
    end)
  end

  for _, scope in ipairs({ "local", "guild" }) do
    it("round trips historical " .. scope .. " configuration through normal preview and confirmation", function()
      local field = scope == "local" and "theme" or "defaultAllocation"
      db.settings[field] = scope == "local" and "historical" or 7
      local expected = db.settings[field]
      local saved = snapshot(scope)
      local text = assert(dibs.Backup.ExportSnapshot(saved.snapshotId))
      db.settings[field] = scope == "local" and "current" or 99
      local ledgerBefore = assert(dibs.ImportExport.Encode(db.ledgers))
      local preview = assert(dibs.ImportExport.Preview(text, scope, "merge", "Tester-Realm"))
      assert_true(db.settings[field] ~= expected, "preview must not apply the configuration")
      assert_equal("confirmed", assert(dibs.ImportExport.Apply(preview.previewId, true,
        "historical configuration", "Tester-Realm")).decision)
      assert_equal(expected, db.settings[field])
      assert_equal(ledgerBefore, assert(dibs.ImportExport.Encode(db.ledgers)))
    end)
  end

  it("requires literal full-scope sensitive consent", function()
    local saved = snapshot("full")
    refused(saved, "SENSITIVE_CONFIRMATION_REQUIRED")
    refused(saved, "SENSITIVE_CONFIRMATION_REQUIRED", { confirmedSensitive = "true" })
    assert_not_nil(dibs.Backup.ExportSnapshot(saved.snapshotId, { confirmedSensitive = true }))
  end)

  it("refuses missing retained text and missing attestations without reconstruction", function()
    local saved = snapshot()
    saved.packageText = nil; refused(saved, "SNAPSHOT_PACKAGE_MISSING")
    saved = snapshot(); saved.packageChecksum = nil; refused(saved, "SNAPSHOT_ATTESTATION_MISSING")
    saved = snapshot(); saved.payloadChecksum = nil; refused(saved, "SNAPSHOT_ATTESTATION_MISSING")
  end)

  it("refuses corrupted text and independently checks package and payload attestations", function()
    local saved = snapshot()
    saved.packageText = saved.packageText:sub(1, -2) .. "X"
    local text = dibs.Backup.ExportSnapshot(saved.snapshotId); assert_nil(text)
    saved = snapshot(); saved.packageChecksum = "invalid"; refused(saved, "SNAPSHOT_CHECKSUM_MISMATCH")
    saved = snapshot(); saved.checksum = "invalid"; refused(saved, "SNAPSHOT_CHECKSUM_MISMATCH")
    saved = snapshot(); saved.payloadChecksum = "invalid"; refused(saved, "SNAPSHOT_CHECKSUM_MISMATCH")
    saved = snapshot(); saved.payload.presentation.theme = "tampered"; refused(saved, "SNAPSHOT_CHECKSUM_MISMATCH")
  end)

  it("refuses scope, schema and source context changes even on otherwise valid packages", function()
    local saved = snapshot("guild")
    repack(saved, function(package) package.scope = "local" end)
    refused(saved, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH")
    saved = snapshot("guild"); saved.schemaVersion = 999
    refused(saved, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH")
    saved = snapshot("guild"); repack(saved, function(package) package.sourceGuild = "OtherGuild" end)
    refused(saved, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH")
    saved = snapshot("guild"); repack(saved, function(package) package.sourceCharacter = "Other-Realm" end)
    refused(saved, "SNAPSHOT_PACKAGE_CONTEXT_MISMATCH")
  end)

  it("rechecks current guild for every scope", function()
    for _, scope in ipairs({ "local", "guild", "full" }) do
      local saved = snapshot(scope)
      saved.guildScope = "OtherGuild"
      refused(saved, "CROSS_GUILD_EXPORT_BLOCKED", { confirmedSensitive = true })
    end
  end)

  it("requires local ownership of both snapshot and original package", function()
    local saved = snapshot()
    saved.characterScope = "Other-Realm"; refused(saved, "CHARACTER_SCOPE_MISMATCH")
    saved = snapshot(); repack(saved, function(package) package.sourceCharacter = "Other-Realm" end)
    refused(saved, "CHARACTER_SCOPE_MISMATCH")
    saved = snapshot(); saved.characterScope = nil; refused(saved, "CHARACTER_SCOPE_MISMATCH")
    saved = snapshot(); saved.characterScope = "TESTER-realm"
    assert_not_nil(dibs.Backup.ExportSnapshot(saved.snapshotId))
  end)

  it("rejects caller actor spoofing instead of borrowing another member's identity", function()
    local saved = snapshot()
    refused(saved, "ACTOR_MISMATCH", { actor = "Other-Realm" })
    refused(saved, "ACTOR_MISMATCH", { actor = { name = "Tester-Realm", guid = "Player-OTHER" } })
    assert_not_nil(dibs.Backup.ExportSnapshot(saved.snapshotId, { actor = "TESTER-realm" }))
    assert_not_nil(dibs.Backup.ExportSnapshot(saved.snapshotId, { actor = UnitGUID("player") }))
    assert_not_nil(dibs.Backup.ExportSnapshot(saved.snapshotId, { actor = { guid = UnitGUID("player") } }))
  end)

  it("rechecks actual current permissions after an officer loses rank", function()
    local saved = snapshot("guild")
    wow.setGuildRoster({ "Tester-Realm", "Officer-Realm" }, { [1] = 3, [2] = 1 }, { guildLeader = false })
    refused(saved, "GUILD_ADMIN_REQUIRED")
    refused(saved, "ACTOR_MISMATCH", { actor = "Officer-Realm" })
    local full = snapshot("local")
    assert_not_nil(dibs.Backup.ExportSnapshot(full.snapshotId), "members retain access to their local configuration")
  end)

  it("honors unsafe-content restrictions rather than using restore's unsafe decoder", function()
    db.settings.theme = "/run prohibited"
    local saved = snapshot()
    refused(saved, "UNSAFE_CONTENT")
  end)

  it("accepts exactly the portable byte limit and refuses one more including the prefix", function()
    local saved = snapshot()
    repack(saved, function(package) package.payload.presentation.padding = "" end)
    local needed = dibs.ImportExport.MAX_PACKAGE_SIZE - #saved.packageText
    repack(saved, function(package) package.payload.presentation.padding = string.rep("x", needed) end)
    assert_equal(dibs.ImportExport.MAX_PACKAGE_SIZE, #saved.packageText)
    assert_not_nil(dibs.Backup.ExportSnapshot(saved.snapshotId))
    repack(saved, function(package) package.payload.presentation.padding = package.payload.presentation.padding .. "x" end)
    assert_equal(dibs.ImportExport.MAX_PACKAGE_SIZE + 1, #saved.packageText)
    refused(saved, "PACKAGE_TOO_LARGE")
  end)

  it("provides a boolean-only read-only validation that also catches stale permissions", function()
    local saved = snapshot("guild")
    local before = assert(dibs.ImportExport.Encode(db))
    local valid, extra = dibs.Backup.ValidateSnapshotExport(saved.snapshotId)
    assert_true(valid); assert_nil(extra)
    assert_equal(before, assert(dibs.ImportExport.Encode(db)), "validation must not append export audit or return package text")
    wow.setGuildRoster({ "Tester-Realm" }, { [1] = 3 }, { guildLeader = false })
    local validAfter, reason = dibs.Backup.ValidateSnapshotExport(saved.snapshotId)
    assert_nil(validAfter); assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)

  it("does not normalize retention or create backup stores during read-only lookup", function()
    local saved = snapshot()
    for _, retention in ipairs({ "5", 100 }) do
      db.backupRetention = retention
      local before = assert(dibs.ImportExport.Encode(db))
      assert_true(dibs.Backup.ValidateSnapshotExport(saved.snapshotId))
      assert_equal(before, assert(dibs.ImportExport.Encode(db)))
    end
    db.backupRetention = nil
    local before = assert(dibs.ImportExport.Encode(db))
    assert_true(dibs.Backup.ValidateSnapshotExport(saved.snapshotId))
    assert_equal(before, assert(dibs.ImportExport.Encode(db)))
    db.backups = nil
    before = assert(dibs.ImportExport.Encode(db))
    local valid, reason = dibs.Backup.ValidateSnapshotExport("missing")
    assert_nil(valid); assert_equal("SNAPSHOT_NOT_FOUND", reason)
    assert_equal(before, assert(dibs.ImportExport.Encode(db)))
    local text, exportReason = dibs.Backup.ExportSnapshot("missing")
    assert_nil(text); assert_equal("SNAPSHOT_NOT_FOUND", exportReason)
    assert_equal(before, assert(dibs.ImportExport.Encode(db)))
  end)

  it("binds cached text to the exact historical package even when its snapshot id is reused", function()
    local saved = snapshot()
    local oldText = assert(dibs.Backup.ExportSnapshot(saved.snapshotId))
    assert_true(dibs.Backup.ValidateSnapshotExport(saved.snapshotId, { expectedPackageText = oldText }))
    repack(saved, function(package) package.payload.presentation.theme = "valid replacement" end)
    assert_true(saved.packageText ~= oldText)
    local before = assert(dibs.ImportExport.Encode(db))
    local valid, reason = dibs.Backup.ValidateSnapshotExport(saved.snapshotId, { expectedPackageText = oldText })
    assert_nil(valid); assert_equal("SNAPSHOT_EXPORT_CHANGED", reason)
    assert_equal(before, assert(dibs.ImportExport.Encode(db)))
    refused(saved, "SNAPSHOT_EXPORT_CHANGED", { expectedPackageText = oldText })
    assert_true(dibs.Backup.ValidateSnapshotExport(saved.snapshotId, { expectedPackageText = saved.packageText }))
    assert_equal(saved.packageText, dibs.Backup.ExportSnapshot(saved.snapshotId, { expectedPackageText = saved.packageText }))
  end)

  it("does not turn a full historical package into a canonical-history adoption route", function()
    local saved = snapshot("full")
    local text, package = assert(dibs.Backup.ExportSnapshot(saved.snapshotId, { confirmedSensitive = true }))
    local canonicalRowId
    for id, row in pairs(package.payload.ledger.transactions) do
      if row.classification == "LOCAL_CANONICAL" then canonicalRowId = id; break end
    end
    assert_not_nil(canonicalRowId)
    db.ledger.transactions[canonicalRowId] = nil
    local before = accounting()
    local preview = assert(dibs.ImportExport.Preview(text, "full", "append", "Tester-Realm"))
    local applied, reason = dibs.ImportExport.Apply(preview.previewId, true, "not a second writer", "Tester-Realm")
    assert_nil(applied); assert_equal("CANONICAL_LEDGER_IMPORT_UNAVAILABLE", reason)
    assert_equal(before, accounting())
  end)
end)
