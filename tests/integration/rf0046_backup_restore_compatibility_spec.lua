local loader = require("helpers.load_addon")

-- RF-0046 regression suite.
--
-- RF-0046 - "Backup : une restauration refuse un instantane valide"
-- (docs/code-audit/INDEX.md#rf-0046).
--
-- RF-0041 added a snapshot validation before any restore mutation. The
-- validation was correct in principle but introduced two regressions that
-- made legitimate snapshots unrestorable:
--
--   1. The validation decoded the stored package with
--      `ImportExport.Decode`, which refuses a package larger than
--      `MAX_PACKAGE_SIZE` (250 000 bytes). A backup is created with
--      `allowOversize = true` and is therefore legitimately allowed to
--      reach `MAX_BACKUP_SIZE` (32 MiB). Every such backup failed its own
--      validation with `INVALID_PACKAGE_SIZE` and could never be
--      previewed nor restored.
--
--   2. The validation required the encoded package to be present. A
--      snapshot written before RF-0041 carried a checksum but no package
--      text, so every pre-existing snapshot failed with
--      `SNAPSHOT_PACKAGE_MISSING` and became unrestorable.
--
-- The invariants:
--   * a snapshot the addon itself produced is always restorable;
--   * the checksum is still verified, and a corrupted snapshot is still
--     refused;
--   * a legacy snapshot that carries no encoded package is still
--     restorable, because the payload it carries is what the restore
--     actually applies;
--   * a snapshot of another guild is still refused;
--   * an incomplete snapshot is still refused.

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, savedVariables = options.savedVariables or {}, wow = {
    playerName = "Tester-Realm", guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = options.rank or 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

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
    transactionCount = count,
  }
end

local function assertAccountingUnchanged(dibs, before, message)
  local after = accountingState(dibs)
  assert_equal(before.balance, after.balance, message .. ": the balance changed")
  assert_equal(before.transactionCount, after.transactionCount, message .. ": the transaction count changed")
end

-- Fills the ledger until the encoded full package is larger than the
-- portable package limit but still inside the backup limit. This is the
-- ordinary state of a guild that has been running for a season.
local function seedOversizeLedger(dibs)
  local seasonId = dibs.GetCurrentSeasonId()
  for index = 1, 900 do
    dibs.Ledger.AddTransaction({
      transactionId = "rf0046-row-" .. tostring(index),
      playerName = "Tester-Realm",
      memberKey = "tester-realm",
      seasonId = seasonId,
      type = "DIB_GRANTED",
      actionType = "DIB_GRANTED",
      amount = 1,
      itemID = 19019,
      itemLink = "|Hitem:19019::::::::::::|h[Item]|h|r",
      reason = string.rep("padding ", 4),
      source = "probe",
      createdAt = 1700000000 + index,
    }, "guild-primary")
  end
end

describe("RF-0046 Backup restore compatibility", function()
  it("C01 restores a backup that is larger than the portable package limit", function()
    local dibs = setup()
    seedOversizeLedger(dibs)
    local snapshot, reason = dibs.Backup.Create("full", "C01 oversize", "Tester-Realm")
    assert_not_nil(snapshot, tostring(reason))
    assert_true(snapshot.size > dibs.ImportExport.MAX_PACKAGE_SIZE,
      "the fixture did not reach the portable package limit")
    assert_true(snapshot.size <= dibs.ImportExport.MAX_BACKUP_SIZE,
      "the fixture exceeded the backup limit")

    local preview, previewReason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "a legitimate oversize backup was refused: " .. tostring(previewReason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C01", "Tester-Realm")
    assert_not_nil(applied, "a legitimate oversize backup was not restored: " .. tostring(applyReason))
  end)

  it("C02 restores a snapshot that carries no encoded package", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-legacy-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C02 legacy", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    -- A snapshot written before RF-0041: the checksum is present but the
    -- encoded package is not.
    stored.packageText = nil
    assert_not_nil(stored.checksum)

    local preview, previewReason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "a legacy snapshot was refused: " .. tostring(previewReason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C02", "Tester-Realm")
    assert_not_nil(applied, "a legacy snapshot was not restored: " .. tostring(applyReason))
  end)

  it("C03 still refuses a corrupted snapshot that carries its package", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-corrupt-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C03 corrupted", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.packageText = stored.packageText:sub(1, #stored.packageText - 8) .. "CORRUPTED"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a corrupted snapshot was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore("none", true, "C03", "Tester-Realm")
    assert_nil(applied, "a corrupted snapshot was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "C03")
  end)

  it("C04 still refuses a snapshot of another guild", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-guild-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C04 other guild", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.guildScope = "another-guild"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a snapshot of another guild was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore("none", true, "C04", "Tester-Realm")
    assert_nil(applied, "a snapshot of another guild was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "C04")
  end)

  it("C05 still refuses an incomplete snapshot", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-incomplete-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C05 incomplete", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.payload = nil
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "an incomplete snapshot was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore("none", true, "C05", "Tester-Realm")
    assert_nil(applied, "an incomplete snapshot was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "C05")
  end)

  it("C06 refuses a snapshot whose package checksum does not match", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-mismatch-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C06 mismatch", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    -- The package is intact but the snapshot no longer attests it.
    stored.packageChecksum = "00000000"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a snapshot with a mismatched checksum was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore("none", true, "C06", "Tester-Realm")
    assert_nil(applied, "a snapshot with a mismatched checksum was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "C06")
  end)

  it("C14 refuses a snapshot whose payload was tampered with", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-tampered-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C14 tampered", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    -- The stored package stays intact; only the applied payload table is
    -- altered. The snapshot must still detect the contradiction.
    local row = stored.payload.ledgers["guild-primary"].transactions["rf0046-tampered-row"]
    row.amount = 9999
    row.reason = "TAMPERED"
    local before = accountingState(dibs)
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_nil(preview, "a tampered payload was previewed: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore("none", true, "C14", "Tester-Realm")
    assert_nil(applied, "a tampered payload was restored")
    assert_not_nil(applyReason)
    assertAccountingUnchanged(dibs, before, "C14")
  end)

  it("C15 restores a backup that carries player-authored text", function()
    local dibs = setup()
    -- A player note that the import content filter rejects. A backup is not
    -- an import: the addon must still be able to restore its own snapshot.
    local request = dibs.Disputes.CreateReport({
      category = "other", note = "do not type /run this in chat",
    })
    assert_not_nil(request)
    local snapshot, reason = dibs.Backup.Create("full", "C15 player text", "Tester-Realm")
    assert_not_nil(snapshot, tostring(reason))
    local preview, previewReason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "a backup with player text was refused: " .. tostring(previewReason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C15", "Tester-Realm")
    assert_not_nil(applied, "a backup with player text was not restored: " .. tostring(applyReason))
  end)

  it("C07 restores a local scope backup that is larger than the portable limit", function()
    local dibs = setup()
    seedOversizeLedger(dibs)
    local snapshot, reason = dibs.Backup.Create("local", "C07 oversize local", "Tester-Realm")
    assert_not_nil(snapshot, tostring(reason))
    local preview, previewReason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "a legitimate local backup was refused: " .. tostring(previewReason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C07", "Tester-Realm")
    assert_not_nil(applied, "a legitimate local backup was not restored: " .. tostring(applyReason))
  end)

  it("C08 keeps the restored state across a reload", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-reload-row", 7)
    local snapshot = assert(dibs.Backup.Create("full", "C08 reload", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.packageText = nil
    local preview = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(preview.previewId, true, "C08", "Tester-Realm"))
    local saved = dibs.GetDB()
    local reloaded = setup({ savedVariables = saved })
    assert_equal(7, reloaded.Ledger.GetBalance("Player-Realm", reloaded.GetCurrentSeasonId()),
      "the restored balance was lost across the reload")
  end)

  it("C09 keeps a snapshot restorable after it is listed", function()
    local dibs = setup()
    seedOversizeLedger(dibs)
    local snapshot = assert(dibs.Backup.Create("full", "C09 listed", "Tester-Realm"))
    local listed = dibs.Backup.List("full", "Tester-Realm")
    local found = false
    for _, entry in ipairs(listed) do
      if entry.snapshotId == snapshot.snapshotId then found = true end
    end
    assert_true(found, "the snapshot was not listed")
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "a listed backup was refused: " .. tostring(reason))
  end)

  it("C10 keeps a snapshot restorable after a second backup is taken", function()
    local dibs = setup()
    seedOversizeLedger(dibs)
    local first = assert(dibs.Backup.Create("full", "C10 first", "Tester-Realm"))
    assert(dibs.Backup.Create("full", "C10 second", "Tester-Realm"))
    local preview, reason = dibs.Backup.PreviewRestore(first.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "the first backup became unrestorable: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C10", "Tester-Realm")
    assert_not_nil(applied, "the first backup was not restored: " .. tostring(applyReason))
  end)

  it("C11 keeps a snapshot restorable when the checksum helper is unavailable", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-nochecksum-row", 5)
    -- The attestation helper is unavailable: the snapshot cannot be
    -- attested. It must still be restorable, because a snapshot that
    -- cannot be restored is a snapshot that does not exist.
    local originalChecksum = dibs.ImportExport.Checksum
    local originalEncode = dibs.ImportExport.Encode
    dibs.ImportExport.Checksum = nil
    dibs.ImportExport.Encode = nil
    local snapshot = assert(dibs.Backup.Create("full", "C11 no checksum helper", "Tester-Realm"))
    assert_nil(snapshot.payloadChecksum, "a payload attestation was produced without a checksum helper")
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    assert_nil(stored.payloadChecksum)

    dibs.ImportExport.Checksum = originalChecksum
    dibs.ImportExport.Encode = originalEncode
    local preview, previewReason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "a snapshot without an attestation was refused: " .. tostring(previewReason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C11", "Tester-Realm")
    assert_not_nil(applied, "a snapshot without an attestation was not restored: " .. tostring(applyReason))
  end)

  it("C12 keeps an unattested snapshot restorable and states the boundary", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-unattested-row", 5)
    -- A snapshot written before the attestation existed: the payload
    -- cannot be verified, and the restore applies it as-is. The boundary
    -- is explicit and documented.
    local snapshot = assert(dibs.Backup.Create("full", "C12 unattested", "Tester-Realm"))
    local stored = assert(dibs.Backup.Get(snapshot.snapshotId))
    stored.payloadChecksum = nil
    stored.packageChecksum = nil
    local row = stored.payload.ledgers["guild-primary"].transactions["rf0046-unattested-row"]
    row.amount = 4242
    local preview, reason = dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm")
    assert_not_nil(preview, "an unattested snapshot was refused: " .. tostring(reason))
    local applied, applyReason = dibs.Backup.Restore(preview.previewId, true, "C12", "Tester-Realm")
    assert_not_nil(applied, "an unattested snapshot was not restored: " .. tostring(applyReason))
    local restored = dibs.GetDB().ledgers["guild-primary"].transactions["rf0046-unattested-row"]
    assert_not_nil(restored)
  end)

  it("C13 restores the same snapshot twice without changing the state", function()
    local dibs = setup()
    seedLegacyRow(dibs, "rf0046-repeat-row", 5)
    local snapshot = assert(dibs.Backup.Create("full", "C13 repeated", "Tester-Realm"))
    local first = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(first.previewId, true, "C13 first", "Tester-Realm"))
    local afterFirst = accountingState(dibs)
    local second = assert(dibs.Backup.PreviewRestore(snapshot.snapshotId, "Tester-Realm"))
    assert(dibs.Backup.Restore(second.previewId, true, "C13 second", "Tester-Realm"))
    local afterSecond = accountingState(dibs)
    assert_equal(afterFirst.balance, afterSecond.balance, "a repeated restore changed the balance")
    assert_equal(afterFirst.transactionCount, afterSecond.transactionCount,
      "a repeated restore changed the transaction count")
  end)
end)
