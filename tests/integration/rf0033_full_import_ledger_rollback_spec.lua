local loader = require("helpers.load_addon")

-- RF-0033 regression suite.
--
-- RF-0033 - "ImportExport : un import de portée complete remplace les
-- registres locaux et perd un solde valide"
-- (docs/code-audit/INDEX.md#rf-0033).
--
-- A full-scope import applies the package payload with
-- `for key, value in pairs(package.payload) do db[key] = clone(value) end`.
-- The payload carries a `ledgers` map, so the import replaced the local
-- `db.ledgers` with the exported clone.
--
-- The merge loop above had already merged the package transactions into
-- `db.ledger` (the live table), and the local player state still listed
-- the transactions that existed only locally. But `db.ledgers[active]`
-- became the exported clone, which did not contain the newer local
-- transaction. `db.ledger` and `db.ledgers[active]` were then two
-- different tables, and the accounting balance was recomputed from the
-- wrong one.
--
-- Consequence reproduced (2026-10-20): a player holding 16 Dibs saw
-- 11 after importing a package exported one grant earlier. The import
-- silently rolled back a valid, newer, authorised grant, which
-- contradicts FR-011 of spec 007: "existing transactions MUST NOT be
-- deleted or rewritten" and "append only new, authorized, valid
-- transactions".

local function setup()
  local _, dibs = loader.load({ withAce3 = true, wow = { playerName = "Tester-Realm", guildLeader = true } })
  return dibs, dibs.GetCurrentSeasonId()
end

describe("RF-0033 a full-scope import never rolls back a newer local ledger", function()
  it("keeps a grant made after the export", function()
    local dibs, seasonId = setup()
    assert(dibs.Ledger.Grant("Tester-Realm", 10, "RF-0033 opening grant", "probe", seasonId),
      "the opening grant was refused")

    local text = dibs.ImportExport.Export("full", { actor = "Tester-Realm" })
    assert_not_nil(text, "the full export failed")

    -- A newer, valid grant after the export.
    assert(dibs.Ledger.Grant("Tester-Realm", 5, "RF-0033 newer grant", "probe", seasonId),
      "the newer grant was refused")
    local balanceBefore = dibs.Ledger.GetBalance("Tester-Realm", seasonId)
    assert_equal(16, balanceBefore, "the opening balance is not the expected one")

    local preview, reason = dibs.ImportExport.Preview(text, "full", "merge", "Tester-Realm")
    assert_not_nil(preview, tostring(reason))
    local applied, applyReason = dibs.ImportExport.Apply(preview.previewId, true, "RF-0033 import", "Tester-Realm")
    assert_not_nil(applied, tostring(applyReason))

    assert_equal(balanceBefore, dibs.Ledger.GetBalance("Tester-Realm", seasonId),
      "the import rolled back a valid newer grant")
  end)

  it("keeps the live ledger and the ledger map pointing at the same table", function()
    local dibs, seasonId = setup()
    dibs.Ledger.Grant("Tester-Realm", 10, "RF-0033 identity grant", "probe", seasonId)
    local text = dibs.ImportExport.Export("full", { actor = "Tester-Realm" })
    dibs.Ledger.Grant("Tester-Realm", 5, "RF-0033 newer grant", "probe", seasonId)

    local preview = assert(dibs.ImportExport.Preview(text, "full", "merge", "Tester-Realm"))
    assert(dibs.ImportExport.Apply(preview.previewId, true, "RF-0033 import", "Tester-Realm"))

    local db = dibs.GetDB()
    assert_true(db.ledger == db.ledgers[db.activeLedgerId or "guild-primary"],
      "the live ledger and the ledger map diverged after the import")
  end)

  it("keeps the local transactions the package did not contain", function()
    local dibs, seasonId = setup()
    dibs.Ledger.Grant("Tester-Realm", 10, "RF-0033 keep grant", "probe", seasonId)
    local text = dibs.ImportExport.Export("full", { actor = "Tester-Realm" })
    dibs.Ledger.Grant("Tester-Realm", 5, "RF-0033 extra grant", "probe", seasonId)

    local db = dibs.GetDB()
    local countBefore = 0
    for _ in pairs(db.ledger.transactions or {}) do countBefore = countBefore + 1 end

    local preview = assert(dibs.ImportExport.Preview(text, "full", "merge", "Tester-Realm"))
    assert(dibs.ImportExport.Apply(preview.previewId, true, "RF-0033 import", "Tester-Realm"))

    local countAfter = 0
    for _ in pairs(db.ledger.transactions or {}) do countAfter = countAfter + 1 end
    assert_true(countAfter >= countBefore,
      "the import removed local transactions (" .. tostring(countBefore) .. " -> " .. tostring(countAfter) .. ")")
  end)

  it("refuses to import a canonical transaction as a second write path", function()
    local dibs, seasonId = setup()
    local text = dibs.ImportExport.Export("full", { actor = "Tester-Realm" })
    local package = assert(dibs.ImportExport.Decode(text))

    -- A canonical transaction is deliberately not importable: adopting it
    -- would be a second durable write path outside the canonical chain.
    local canonicalId
    for id, tx in pairs(package.payload.ledger.transactions or {}) do
      if tx.classification == "LOCAL_CANONICAL" then canonicalId = id break end
    end
    assert_not_nil(canonicalId, "the package held no canonical transaction to test with")

    local db = dibs.GetDB()
    db.ledger.transactions[canonicalId] = nil
    for _, st in pairs(db.ledger.playerStates or {}) do
      for _, st2 in pairs(st) do
        for index = #st2.transactions, 1, -1 do
          if st2.transactions[index] == canonicalId then table.remove(st2.transactions, index) end
        end
      end
    end

    local preview = assert(dibs.ImportExport.Preview(text, "full", "merge", "Tester-Realm"))
    local applied, reason = dibs.ImportExport.Apply(preview.previewId, true, "RF-0033 import", "Tester-Realm")
    assert_nil(applied, "a canonical transaction was imported as a second write path")
    assert_equal("CANONICAL_LEDGER_IMPORT_UNAVAILABLE", reason)
  end)
end)
