# GM / Officer Guide

This guide covers setup, administration, audit, recovery, and release checks for
RCLootCouncil_dibs.

## Purpose and limits

Dibs provides a seasonal ledger, Pre-Dib requests, eligibility checks, and
private audit evidence around guild loot. RCLootCouncil is optional and, when
installed, remains the voting and loot-session interface.

Dibs does not choose a winner automatically, replace RCLootCouncil voting, or
rewrite RCLootCouncil history. A Pre-Dib is not a debit. A Drop-Dib creates one
ledger debit only after a valid finalized award and remains idempotent on replay.

![GM and Officer overview](../assets/guides/screenshots/en/officer/officer-overview.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/officer/officer-overview.png`_

## Authority and security

The Guild Master and configured verified Officers administer Dibs. Council
membership, Raid Leader status, Raid Assistant status, and RCLootCouncil Master
Looter status alone do not grant Dibs administration. Unknown or unverifiable
identities fail closed.

The RCLootCouncil Master Looter has a narrow exception: a verified finalized
qualifying DIB award may trigger the configured debit. That role cannot grant,
refund, configure, or otherwise administer Dibs unless it is also an authorized
GM or Officer.

## Installation and first launch

1. Install the `RCLootCouncil_dibs` folder under `Interface/AddOns/`.
2. Enable it and run `/reload`.
3. Open `/dibs options` and open **Guild Setup** under Officer > System.
4. As the Guild Master, follow the Guild Setup page: it reports Guild Governance,
   Existing DIBS Data, Coordinator, Guild Compatibility, Synchronization, and
   Guild Ledger readiness, and offers one **Initialize DIBS** action once every
   prerequisite is satisfied. If existing Dibs history is detected, review each
   item before the guild ledger can be initialized; nothing is decided for you.
5. Create and activate a season before distributing Dibs.
6. Configure rank allocations, policy, announcements, and modules.
7. Run `/dibs readiness` and a dry-run before the first live raid.

A normal Guild Master does not need to run `/run` commands or call internal
APIs to reach a working guild ledger; Guild Setup performs governance
initialization, historical data review, and canonical ledger activation through
the existing authoritative modules.

![Season, rank, and permissions setup](../assets/guides/screenshots/en/officer/officer-setup.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/officer/officer-setup.png`_

## Slash commands

```text
/dibs options
/dibs readiness
/dibs dryrun <itemID/link> <winner> <response> <finalized|test|pending> [session]
/dibs season create [name]
/dibs season set <id>
/dibs season list
/dibs rank set <index> <amount> [name]
/dibs rank list
/dibs grant <player> <amount>
/dibs use <player> <amount>
/dibs review
/dibs reconcile
/dibs data
/dibs backup
/dibs profiles
/dibs import
/dibs export
/dibs debug report
/dibs debug rc
```

## Seasons, ranks, permissions, and policy

Use **Seasons** to create, activate, and archive seasonal policy. Use **Rank
Rules** to define allocations by guild rank. Confirm the active season and zero
allocation behavior before a raid.

Choose an installation mode:

- `STANDALONE`: Dibs manages requests, balances, and local accounting without a
  live RCLootCouncil session;
- `RCLootCouncil`: RCLootCouncil manages the loot session while Dibs validates
  evidence and accounting;
- `AUTO`: use the integration when available and retain local operation when it
  is absent or unavailable.

Configure supported loot families, announcement channels, and the Pre-Dib mode:

- `WILD_OPEN`: requests may be submitted outside the matching raid according to
  policy;
- `ENCOUNTER`: requests require the matching raid and difficulty context.

![Policy and Pre-Dib settings](../assets/guides/screenshots/en/officer/officer-policy.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/officer/officer-policy.png`_

## Readiness and Drop-Dib workflow

Run `/dibs readiness` before live loot. Review season, policy, RCLootCouncil
status, verified Master Looter, DIB response projection, raid context, and sync
transport.

For a Drop-Dib:

1. Confirm the item family and season policy.
2. Confirm the winner, response, difficulty, and session identity.
3. Confirm the verified local Master Looter and finalized status.
4. Finalize through RCLootCouncil when integrated.
5. Verify one debit, one request fulfillment, and the expected evidence.

Normal, test, failed, pending, incomplete, or duplicate events must not consume
production Dibs. Never fix a debit by editing SavedVariables.

![Ledger entry for a finalized Drop-Dib](../assets/guides/screenshots/en/officer/officer-ledger.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/officer/officer-ledger.png`_

## Pre-Dib workflow

1. A player submits a supported item request.
2. Dibs validates season, item, difficulty, and mode.
3. Review it in **Review Requests** or **Pre-Dibs**.
4. Inspect owner, item, request status, and evidence.
5. Let the finalized award fulfill the request when appropriate.
6. Confirm that a replay creates no second debit.

## History, corrections, and audit trail

Use **Review Requests** to filter by status, player, or item, inspect evidence,
and resolve a report. Every resolution requires a reason. Balance and target
corrections require explicit confirmation.

Corrections, refunds, revokes, historical imports, and adjustments are
append-only. They add linked transactions and retain actor, timestamp, reason,
before/after values, delta, request reference, and canonical evidence.

Use **RC History** for historical RCLootCouncil evidence:

1. Select the target season.
2. Filter by date and exact response aliases where needed.
3. Run a read-only preview.
4. Inspect immutable source evidence.
5. Add a transfer note.
6. Confirm the historical DIB once.

RCLootCouncil is an optional evidence provider, not the Dibs ledger authority.
History is never rewritten, and confirmed transfers are idempotent.

## Multi-raid synchronization and recovery

Guild Setup (Officer > System > Guild Setup) is the normal way to initialize
the canonical guild ledger; it never requires understanding ledger epochs,
baseline hashes, or internal protocol states. Those technical values remain
available under its "Show technical details" disclosure and on the
Synchronization page for diagnostics.

Dibs synchronization shares guild-scoped Dibs state and recovery metadata. It
does not share live candidates, votes, responses, or loot-session details between
raids.

Test two clients, reconnect, duplicate delivery, stale revisions, partition,
coordinator handoff, and recovery before relying on multi-raid operation.

Watch for these coordinator states:

- `ACTIVE`: ordered writes may proceed;
- `COORDINATOR_UNAVAILABLE`: ordered accounting may be blocked;
- `RECOVERY_PENDING`: recovery evidence or state is incomplete;
- `HANDOFF_CLOSING`: the previous coordinator is closing its sequence.

Do not bypass these states by editing SavedVariables. Reconciliation must use a
preview, immutable evidence, an explicit reason, and one confirmation.

### Great Vault review and sync

The **Vault Review** view lists guild-scoped acquisitions and legacy records.
Players see only their permitted projection; complete evidence remains in the
Officer view. Review actions require an explicit reason and preserve original
evidence. Immutable identity conflicts are held for review rather than
replaced by last-write-wins.

Vault synchronization uses bounded `VAULT_DIGEST`, `VAULT_FETCH`,
`VAULT_DETAIL`, and `VAULT_ACK` messages. It rejects cross-guild, unauthorized,
private-evidence, malformed, and incomplete transfers. Reconnect retries are
bounded and idempotent. A guild change does not merge old history, and an
unguilded character keeps its own local ownership scope.

![Officer Great Vault review](../assets/guides/screenshots/en/officer/officer-vault-review.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/officer/officer-vault-review.png`_

![Synchronization and reconciliation state](../assets/guides/screenshots/en/officer/officer-sync-reconciliation.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/officer/officer-sync-reconciliation.png`_

## Backup, restore, profiles, and disputes

In **Data**:

- **Backups** creates scoped recovery points with size, checksum, and retention;
- **Restore** creates a safety snapshot and requires a preview plus confirmation;
- **Profiles** separates local presentation from guild policy;
- **Import / Export** validates scope, schema, size, checksum, and deduplication.

Full-data packages may contain identities and award history. Keep them private.
A cancelled preview must not change settings, balances, profiles, or history.

Use the dispute center for wrong debit, missing debit, duplicate, wrong item or
player, eligibility, and integration reports. Do not directly edit stored data.

## Optional modules and diagnostics

The GM manages optional modules from **System > Modules**. Disabled modules keep
their stored data, hide normal navigation where appropriate, reject stale routes,
and can be re-enabled. Core safety services remain enabled.

Use:

```text
/dibs debug report
/dibs debug rc
```

Diagnostics should not expose live candidate lists, votes, or responses.

## Release checks

Before release or guild rollout, record results for:

- clean ZIP installation and TOC version;
- no load-time Lua errors;
- GM, Officer, player, and Master Looter authority matrix;
- Standalone and RCLootCouncil readiness;
- one finalized Drop-Dib and idempotent replay;
- Pre-Dib modes and item eligibility;
- backup, restore preview, import checksum, and retention;
- dispute correction and append-only audit evidence;
- two-client sync, partition, coordinator recovery, and reconciliation;
- protected-frame behavior, combat deferral, and UI layout;
- the exact WoW build, RCLootCouncil version, actors, evidence, and screenshots.

Do not describe the addon as Retail-production-ready until the manual Retail
checks in `B12_Release_Candidate_Checklist.md` are recorded.

## Troubleshooting and FAQ

### The DIB response is missing

Check the RCLootCouncil profile, enabled response sets, installation assistant,
and the readiness report. Refresh Dibs buttons after changing response sets.

### Why is a debit blocked?

Check season, policy, item family, finalized status, winner identity, Master
Looter authority, session evidence, coordinator state, and module status.

### Can I delete a bad transaction?

No. Use an audited correction, refund, revoke, or historical workflow.

### What does `manual review` mean?

Historical evidence is incomplete or ambiguous. Verify identity, item, winner,
date, response, difficulty, and reason before confirming.

### What if RCLootCouncil is absent?

Standalone balances and requests can remain available. RCLootCouncil evidence,
live award callbacks, and related projections remain unavailable.

### What if a module is disabled?

Check **System > Modules**. Stored data is retained and should return after
reactivation; stale windows and direct routes should fail closed.
