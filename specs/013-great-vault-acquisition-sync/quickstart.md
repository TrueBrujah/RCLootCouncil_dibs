# Quickstart: Great Vault Acquisition Tracking and Guild Sync

## Prerequisites

- Repository root checked out on the feature worktree.
- Node.js available for Fengari tests.
- A Retail test client for Great Vault signal discovery and UI validation.
- Two test characters in the same guild for synchronization validation.
- A separate character or guild context for isolation validation.
- RCLootCouncil may be absent for standalone checks; it is not required for local Vault recording.

## Automated validation

Run the full suite from PowerShell:

```powershell
npx.cmd --yes fengari tests/run.lua
```

During implementation, run the focused feature files through `DIBS_TEST_FILES`:

```powershell
$files = @(
  "tests/unit/great_vault_acquisition_spec.lua",
  "tests/contract/great_vault_sync_contract_spec.lua",
  "tests/integration/great_vault_migration_spec.lua",
  "tests/integration/great_vault_sync_recovery_spec.lua"
)
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
```

Expected automated coverage:

- automatic, manual, legacy, unverified, Officer-confirmed, rejected, and reference-only statuses;
- repeated manual command and repeated automatic event idempotence;
- no Dib ledger mutation for any Vault action;
- migration from existing `preDibs.acquisitions` records;
- guild isolation and unguilded character isolation;
- digest, fetch, detail, acknowledgement, stale revision, replay, conflict, and forbidden live-loot rejection;
- player versus Officer projections;
- incomplete and expired transfer recovery.

## Local manual fallback validation

1. Enable the addon in standalone mode or with RCLootCouncil absent.
2. Select or create an active season.
3. Run `/dibs vault <itemID> <difficulty>` with a valid item ID.
4. Confirm that one acquisition appears in the player's acquisition history.
5. Repeat the command and confirm that no second acquisition appears.
6. Confirm that the Dibs balance and ledger transaction count are unchanged.
7. Inspect the record and verify that it is labeled manual or review-required when no claim evidence exists.

## Great Vault Retail validation

1. Open the Great Vault without claiming a reward.
2. Confirm that opening the Vault or viewing a reward choice does not create an automatic confirmed record.
3. Claim one reward when the client exposes a supported signal.
4. Confirm the item, character, claim time, source, reset context, and verification state.
5. Reload and reconnect, then verify that the same claim is not recorded twice.
6. Repeat the claim observation or update if the client emits it more than once; verify idempotence.
7. If the client does not expose sufficient evidence, verify that the UI reports manual-only or unavailable detection and that `/dibs vault` remains available.
8. Record the exact client build, observed event/callback behavior, and any missing item/reset evidence in the Retail validation evidence file.

## Two-client guild synchronization

1. Prepare Client A and Client B in the same guild with valid roster visibility.
2. Record or confirm one Vault acquisition on Client A.
3. Trigger the normal guild lifecycle or sync heartbeat.
4. Confirm that Client B receives a bounded digest and requests only missing detail.
5. Confirm that Client B stores one acquisition with matching identity, content hash, and verification state.
6. Replay the digest and detail; confirm an idempotent result and no duplicate eligibility effect.
7. Disconnect Client B, create one additional confirmed record on Client A, reconnect B, and verify bounded recovery.
8. Send a malformed, cross-guild, stale, conflicting, or live-loot-containing message in the test harness; confirm rejection with no local mutation.
9. Confirm that a normal player sees only the permitted projection and that an Officer sees the complete review evidence.

## Migration validation

1. Load a pre-feature SavedVariables fixture containing existing Vault acquisitions with only the legacy fields.
2. Run the guild migration and inspect the migration result.
3. Confirm original acquisition IDs, item IDs, sources, dates, and player identities remain available.
4. Confirm missing verification fields become legacy/manual or review-required, never automatic confirmed.
5. Confirm no ledger transaction is created.
6. Run the migration a second time and confirm no duplicate metadata or acquisition is created.
7. Test a future unsupported schema and verify read-only recovery or rejection without data loss.

## Release evidence

Before shipping, record:

- automated test command and pass count;
- Retail client build and Great Vault capability result;
- one-client manual fallback evidence;
- two-client same-guild sync evidence;
- cross-guild rejection evidence;
- migration and SavedVariables compatibility result;
- player privacy and Officer review screenshots where the UI changes;
- changelog, version, French guide, English guide, and protocol documentation updates.

Automated tests do not replace Retail validation for Blizzard Great Vault signals, protected UI timing, roster identity, or real addon-message delivery.
