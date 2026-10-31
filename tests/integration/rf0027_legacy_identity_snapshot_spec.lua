local loader = require("helpers.load_addon")

-- RF-0027 regression suite.
--
-- RF-0027 - "Ledger : le hachage canonique suppose un instantane
-- d'identite present"
-- (docs/code-audit/INDEX.md#rf-0027).
--
-- `canonicalSnapshot` read `snapshot.memberKey`, `snapshot.displayName`
-- and `snapshot.guidWitness` unconditionally. A transaction migrated from
-- an older schema carries no `identitySnapshot` and no `actorSnapshot`,
-- so hashing such a row raised a nil index error. The error aborted
-- `Dibs.Initialize` entirely, so a guild with a legacy award commit
-- could not start the addon at all.
--
-- The projection now treats a missing snapshot as an empty identity. No
-- identity is invented: the record keeps exactly the fields it carried.

local function legacyGuildWithAwardCommit()
  local seasonId = "season-legacy-award"
  return {
    version = 7,
    currentSeasonId = seasonId,
    seasons = { [seasonId] = { id = seasonId, name = "Legacy", isArchived = false } },
    rankRules = {},
    ledger = {
      transactions = {
        ["legacy-award-tx"] = {
          transactionId = "legacy-award-tx", playerName = "Tester-Realm", amount = -1,
          seasonId = seasonId, type = "DIB_USED", actionType = "DIB_USED",
        },
      },
      playerStates = {}, awardTransactions = {}, evidenceTransactions = {},
      canonical = {
        schema = 1, epoch = 7, nextSeq = 2, rootHash = "LEGACY-ROOT",
        commits = {
          ["7:1"] = {
            schema = 1, recordClass = "AWARD_COMMIT", protocolMajor = 2,
            guildKey = "realm:testguild", ledgerId = "guild-primary", ledgerEpoch = 7, sequence = 1,
            previousHash = "GENESIS", transactionHash = "LEGACY-TX-HASH", commitHash = "LEGACY-COMMIT-HASH",
            transaction = {
              transactionId = "legacy-award-tx", playerName = "Tester-Realm", amount = -1,
              seasonId = seasonId, type = "DIB_USED", actionType = "DIB_USED",
            },
          },
        },
      },
    },
    permissions = { adminEvents = {}, activeStandaloneAdmins = {} },
    preDibs = { requests = {}, modePolicies = {}, acquisitions = {} },
    disputes = { version = 1, requests = {}, order = {}, corrections = {} },
    settings = {},
    sync = { seenTransactions = {}, peerStates = {} },
  }
end

describe("RF-0027 a legacy row without an identity snapshot can be hashed", function()
  it("initializes with a migrated award commit that has no identity snapshot", function()
    local loaded, dibs = pcall(function()
      return select(2, loader.load({ savedVariables = {
        schemaVersion = 6,
        guilds = { ["realm:testguild"] = legacyGuildWithAwardCommit() },
        persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
      } }))
    end)
    assert_true(loaded, "the addon refused to initialize with a legacy award commit")
    assert_not_nil(dibs, "no addon was returned")

    local db = dibs.GetDB()
    local commit = db.ledger.canonical.commits["7:1"]
    assert_not_nil(commit, "the legacy award commit was dropped")
    assert_equal("LEGACY-COMMIT-HASH", commit.commitHash, "the legacy commit hash was rewritten")
    assert_equal("LEGACY-ROOT", db.ledger.canonical.rootHash, "the legacy root hash was rewritten")
  end)

  it("classifies a legacy chain without raising", function()
    local _, dibs = loader.load({ savedVariables = {
      schemaVersion = 6,
      guilds = { ["realm:testguild"] = legacyGuildWithAwardCommit() },
      persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
    } })

    local ok, classification = pcall(dibs.Ledger.ClassifyCanonicalRecovery, "guild-primary")
    assert_true(ok, "the recovery classification raised on a legacy chain")
    assert_not_nil(classification, "no recovery classification was produced")
    assert_not_nil(classification.classification, "the recovery classification has no verdict")
  end)

  it("does not invent an identity for a row that never carried one", function()
    local _, dibs = loader.load({ savedVariables = {
      schemaVersion = 6,
      guilds = { ["realm:testguild"] = legacyGuildWithAwardCommit() },
      persistenceRecovery = { version = 1, backups = {}, quarantine = {}, nextBackupId = 1 },
    } })

    local db = dibs.GetDB()
    local transaction = db.ledger.transactions["legacy-award-tx"]
    assert_not_nil(transaction, "the legacy transaction was dropped")
    assert_nil(transaction.identitySnapshot,
      "an identity snapshot was fabricated for a legacy transaction")
    assert_equal("Tester-Realm", transaction.playerName,
      "the legacy player name was rewritten")
  end)
end)
