# GM / Officer Guide

This guide covers setup, administration, audit, recovery, and release checks for
RCLootCouncil_dibs.

This guide describes current source; see the [published/local version distinction](../../README.md#downloads).
Navigation labels are localized, and disabled modules can hide their pages.
Screenshot paths marked pending identify missing Retail captures, not delivered
images or proof of current-client validation.

## Purpose and limits

Dibs provides a seasonal ledger, Pre-Dib requests, eligibility checks, and
private audit evidence around guild loot. RCLootCouncil is optional and, when
installed, remains the voting and loot-session interface.

Dibs does not choose a winner automatically, replace RCLootCouncil voting, or
rewrite RCLootCouncil history. A Pre-Dib is not a debit. A Drop-Dib creates one
ledger debit only after a valid finalized award and remains idempotent on replay.

_Pending Retail capture: grouped Officer navigation and Dashboard —
`docs/assets/guides/screenshots/en/officer/officer-overview.png`._

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
3. Open `/dibs officer` > **Overview > Guided Setup**. `/dibs options` also
   provides configuration and launch controls.
4. Complete the three primary stages:
  - **Choose**: select Progression raid, Standard loot, or Custom/advanced.
    The profile explains who it is for, why it is useful, and what it leaves
    unchanged.
  - **Configure**: review every planned action, expected result, preserved
    record, and deferred GM approval before selecting **Apply this setup**.
  - **Verify**: review the current authoritative guild state after setup.
5. Correct red **Blocking** results before relying on live raid accounting.
  Every blocker explains what DIBS checked, why it matters, and provides a
  direct button to the relevant Officer page. Amber warnings require review
  but may describe non-blocking or currently unavailable context. Blue
  optional results, such as RCLootCouncil not being installed, do not prevent
  standalone DIBS use.
6. Run `/dibs readiness` and a dry-run before the first live raid.

The Dibs icon beside the minimap is a shortcut to the appropriate Player or
Officer view. It never grants authority; the same permission checks still
apply.

A normal Guild Master does not need to run `/run` commands or call internal
APIs to reach a working guild ledger. Guided Setup shows what needs
configuration, Guild Setup Checks verify the one-time guild configuration and
synchronization, Raid Readiness checks whether DIBS is ready for this raid, and
Guild Configuration handles historical review and canonical ledger activation
through the existing authoritative modules.

## Rank allocation reconciliation

Guided Setup keeps **Rank Rules** publication separate from **Allocation
Reconciliation**. Open **Automatic Dibs** to compare each current roster
member's rank rule with their assigned seasonal allocation. A positive
difference can be granted only after an explicit confirmation and a required
reason; non-coordinator actions remain pending until the coordinator commits
the canonical ledger transaction. Reconcile All processes members independently
and reports committed, pending, stale, skipped, and failed outcomes.

When reconciliation is unavailable, the page shows the reason instead of an
inert button (for example **Sync behind** when this client is behind on guild
synchronization). Use **Fix synchronization** from that page, then retry.

In **Rank Rules**, disable Dibs for ranks that should not receive starting
allocations. Members of disabled ranks are omitted from allocation warnings;
their existing ledger allocations are preserved.

A negative difference is informational only. Previously assigned Dibs stay
granted after demotion, including Dibs already spent; there is no clawback,
negative balance adjustment, or debt. The legacy Assignments option remains
available and routes through the same protected reconciliation service.

**Three related but distinct pages** exist under Officer > Overview/System —
use the one that matches what you're trying to do:

| Page | Purpose |
|---|---|
| **Guided Setup** | Three-stage turnkey workflow. It documents and applies a reviewed recommended profile through existing authoritative services, then points every unresolved blocker to its correction page. Custom mode leaves all settings unchanged. |
| **Guild Setup Checks** | One-time guild configuration and synchronization: season, policy, rank rules, authority, installation, local state, Loot Rules, loot types, local services, and synchronization state. Guided Setup's final step uses these checks. Raid context is not required. |
| **Raid Readiness** | Answers "is DIBS ready for this raid?": one rolled-up Guild setup item, raid context, RCLootCouncil, Dib response projection, channels, synchronization state, and **Raid members with DIBS**. Online raid members without DIBS, or needing an update, produce a warning, not a blocker; they can still loot but cannot see or send Dibs. |
| **Guild Configuration** | Guild-level configuration and canonical-ledger activation (the "Ledger" step in Guided Setup). Handles legacy-data reconciliation and one-time ledger activation; safe to reopen on an already-active guild (it reports `Ready` and changes nothing). |

_Pending Retail capture: Guided Setup Choose/Configure/Verify, blockers and
correction links — `docs/assets/guides/screenshots/en/officer/officer-setup.png`._

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

## Multi-Ledger Management

Dibs supports partitioned ledgers within the same guild to accommodate multiple raid teams, split runs, or distinct progression rosters without balance interference.

- **Storage Partitioning**: Each ledger maintains independent transaction logs and player balances (`guild-primary` is the default).
- **Proposing a Ledger**: Verified Officers can propose a new ledger through the Officer UI.
- **Guild Master Approval**: Proposed ledgers remain inactive until explicitly approved by the Guild Master in Officer > Guild Configuration.
- **Guild Active Ledger**: The Guild Master or an Officer selects the guild active ledger from Officer > Dashboard (or `/dibs ledger set <id>`). The choice travels in the synchronized operational policy and is imposed on every member: all Pre-Dibs, award proposals and reservations use it. Members cannot override it. Until a member has received the imposed ledger from the catalog, Pre-Dib and award creation fail closed. The imposed ledger cannot be archived.
- **Viewing Other Ledgers**: Anyone can view another approved ledger read-only from the "View ledger" dropdown (`/dibs`, Officer > History, or `/dibs ledger view <id>`). Pre-Dib submission is disabled while viewing another ledger. Every window shows the active ledger, addon version and sync state in its status bar.
- **Version requirement**: All members must run 0.8.10 or later once a guild active ledger is set; older clients cannot apply the new policy field and their policy chain stops updating.
- **Catalog Synchronization**: The approved ledger catalog (`LEDGER_CATALOG`) replicates automatically across all guild members.
- **Permanent deletion**: Only the Guild Master can permanently delete a non-default ledger after it is archived. The Officer UI requires a second confirmation, records a governance audit entry, and synchronizes an idempotent deletion tombstone to the guild. The default ledger and active or approved ledgers cannot be deleted.

## Officer Administration Empowerment

Verified Guild Officers can initialize setup proposals, configure seasons, adjust rank rules, and work through Guided Setup without fatal `GUILD_MASTER_REQUIRED` blockers:

- Officer initializations create a `PROPOSAL_CREATED` setup state.
- Operational policies and newly proposed ledgers remain clearly marked as pending GM confirmation.
- Routine administration (season activation, rank point allocations) is accessible directly to authorized officers when the GM is offline.

## Independent Raid Sessions

When running a raid with pick-up groups (PUGs) or non-guild players, Master Looters can start an **Independent Raid Session** (Officer > Integrations > Independent Raid):

- **Ephemeral Local Accounting**: The session tracks starting point allowances locally without affecting guild ledgers.
- **Strict Network Inhibition**: All outgoing synchronization to `GUILD`, `OFFICER`, and `RAID` addon channels is completely paused while an independent session is active.
- **RCLootCouncil DIB Integration**: Raiders only need the standard RCLootCouncil addon. Selecting the "DIB" response button deducts from their ephemeral session points. Free awards (non-DIB responses) spend zero points.
- **Award Reconciliation**: After the raid, Officers can review recorded awards and optionally reconcile eligible items into an approved guild ledger.

## Guild Loot Rules

Loot Rules are guild authority, separate from Rank Rules and OperationalPolicy.
The GM reviews the complete dynamic loot-type draft, then selects **Adopt
reviewed Loot Rules** once. Later edits remain a local draft until **Publish
Loot Rules changes** succeeds. A failed publication leaves the prior catalog
revision effective. Do not tell the raid a change is active until the success
state is shown.

Verified Officers can edit the local draft and apply the Dibs loot-policy
preset. Officers cannot adopt or publish the guild-wide rules; those actions
remain GM-only. Local legacy maps remain preserved for recovery and do not
override an adopted snapshot. DIBS derives supported
keys from the existing RCLootCouncil option source, and the same guild values
drive Adventure Guide eligibility and Dibs response buttons.

Raid Readiness reports the exact `Guild Loot Rules` state. `GUILD_LOOT_RULES_READY`
means this client has a validated snapshot; `GUILD_LOOT_RULES_NOT_CONFIGURED`
and `LOCAL_LEGACY_ONLY` are not guild-wide readiness;
`GUILD_LOOT_RULES_SYNC_BEHIND` keeps the last received snapshot effective while
recovery proceeds; `GUILD_LOOT_RULES_INCOMPATIBLE` requires updating DIBS;
`UNAVAILABLE` means the dynamic option source could not be loaded. SyncV2
rejects 0.7.x peers from the 0.8.x compatibility family. Ask affected members
to update rather than changing local settings to compensate.

In **Announcements**, **Enable public announcements** and **Enable officer
announcements** switch each announcement kind off or on. Disabling stores the
channel as None in the published policy; enabling restores the previously
selected channel (default Guild or Officer).

Configure supported loot families, announcement channels, and the Pre-Dib mode:

- `WILD_OPEN`: requests may be submitted outside the matching raid according to
  policy;
- `ENCOUNTER`: requests require the matching raid and difficulty context.

_Pending Retail capture: published Loot Rules and Pre-Dibs settings —
`docs/assets/guides/screenshots/en/officer/officer-policy.png`._

## Readiness and Drop-Dib workflow

Run `/dibs readiness` before live loot. Review season, policy, RCLootCouncil
status, verified Master Looter, DIB response projection, raid context, and sync
transport. **Overview > Raid Readiness** also lists online raid members without
DIBS or needing an update; this is a warning, not a blocker.

For a Drop-Dib:

1. Confirm the item family and season policy.
2. Confirm the winner, response, difficulty, and session identity.
3. Confirm the verified local Master Looter and finalized status.
4. Finalize through RCLootCouncil when integrated.
5. Verify one debit, one request fulfillment, and the expected evidence.

Normal, test, failed, pending, incomplete, or duplicate events must not consume
production Dibs. Never fix a debit by editing SavedVariables.

_Pending Retail capture: finalized award and linked append-only correction —
`docs/assets/guides/screenshots/en/officer/officer-ledger.png`._

## Pre-Dib workflow

1. A player submits a supported item request.
2. Dibs validates season, item, difficulty, and mode.
3. Review it in **Requests > Pre-Dib Requests**; **System > Pre-Dibs Settings**
   configures request policy rather than player problem reports.
4. Inspect owner, item, request status, and evidence.
5. Let the finalized award fulfill the request when appropriate.
6. Confirm that a replay creates no second debit.

## History, corrections, and audit trail

Use **Requests > Requests** (`/dibs review`, formerly **Review Requests**)
to filter by status, player, or item, inspect evidence,
and resolve a report. Every resolution requires a reason. Balance and target
corrections require explicit confirmation.

Corrections, refunds, revokes, historical imports, and adjustments are
append-only. They add linked transactions and retain actor, timestamp, reason,
before/after values, delta, request reference, and canonical evidence.

### Request follow-up and private delivery (0.8.8)

Use the existing request detail to send a **Public reply**, **Assign to me** or
choose a verified guild officer, and schedule/reschedule a follow-up. The queue
also filters Due, Assigned to me, Waiting for player, Concluded, and Archived.
Last activity and responsibility are explicit. Internal audit reasons are not
public replies. Reminders are per-character, throttled to one per request/hour
while online, and can be snoozed without changing the shared due time.

Delivered requests are writable only on the current verified coordinator client.
Other capable officers receive private read-only replicas (up to 16 online
capable officer peers per bounded pump); this is not remote correction authority.
Unproven epoch/coordinator handoff blocks old shared dossiers. Legacy local-only
dossiers retain their workflow; if changed before first coordinator binding,
their queued submission stops with `REQUEST_LOCAL_DOSSIER_CHANGED` rather than
publishing an incomplete or already-corrected dossier.

After Resolved or Rejected, **Close request**, then **Archive request**, each with
an explicit reviewed reason. Archives remain searchable including stored replies,
evidence references and audit reasons. Closing/archiving never touches accounting.
A linked compensation prevents reopening/reapplying it. At 500 retained dossiers
or 120 audit events, further affected writes fail explicitly; do not delete
history to make space. Oversized private transfers remain in error with their
source retained. Real-client delivery and handoff certification remains pending.

In **Dibs Administration**, choose the guild member and current-season action.
Add and Remove require a reason and explicit confirmation; the audit record
retains the acting Officer/GM, target, previous balance, resulting balance, and
reason. The original history is never edited or deleted.

Use `/dibs reconcile` for the **RC History** historical reconciliation workflow:

1. Select the target season.
2. Filter by date and exact response aliases where needed.
3. Run a read-only preview.
4. Inspect immutable source evidence.
5. Add a transfer note.
6. Confirm the historical DIB once.

RCLootCouncil is an optional evidence provider, not the Dibs ledger authority.
History is never rewritten, and confirmed transfers are idempotent.

### Searching existing history

Use the search and filter controls on the existing Officer ledger, Pre-Dib,
Great Vault, and RCLootCouncil history views to narrow records by player,
item, recorded raid/boss details, date, status, and source where those fields
are available. Enter dates as `YYYY-MM-DD`; date bounds are inclusive.
Missing metadata does not match placeholder text. Clearing one filter
preserves the others, while clearing all filters restores that page's default
scope. Search is read-only; it does not change balances, requests, Vault
records, or historical RCLootCouncil evidence. Existing Officer authorization
and privacy boundaries continue to apply.

### Player activity statistics

Open **Dibs > Statistics** and enter optional `YYYY-MM-DD` start and end
dates. Bounds are inclusive; leave both empty for the full selected season.
The table shows descriptive per-player ledger transaction, award, Dibs granted,
Dibs used, and correction counts. It is read-only and does not change the
ledger or consume Dibs. It is not a fairness score or a ranking of loot
distribution, and it does not count loot that is outside Dibs ledger records.
If undated transactions are excluded by a date filter, the page marks affected
coverage as partial.

## Multi-raid synchronization and recovery

Guild Configuration (Officer > System > Guild Configuration) is the normal way to initialize
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

### Fixing a client marked behind

The Synchronization page lists every recorded reason a client is behind (for
example a ledger gap, missing Pre-Dib detail, or a canonical root conflict).
Its repair tools never edit ledger entries:

- **Fix synchronization** rechecks local data, clears reasons that are now
  resolved, and re-requests what is still missing from online peers in bounded
  batches;
- **Verify again** rechecks local data only;
- **Force clear...** (Guild Master or Officer, with confirmation and a reason)
  clears the local behind flag; peers mark the client behind again if data is
  still missing. Use it only for stuck reasons that cannot be verified;
- **Probe peer** asks one online character for its synchronization
  diagnostics, and **Show report** displays the answer;
- **Repair peer** (Guild Master only) sends the guild baseline to one online
  character that rejected or never received it.

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

_Pending Retail capture: Officer Vault Review —
`docs/assets/guides/screenshots/en/officer/officer-vault-review.png`._

_Pending Retail capture: Synchronization and historical reconciliation —
`docs/assets/guides/screenshots/en/officer/officer-sync-reconciliation.png`._

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

### Data health review

Open **System > Diagnostics** to review guild-scoped invalid season references,
incomplete or duplicate Great Vault acquisitions, acquisitions requiring
verification, and unresolved Vault conflicts. Previews are read-only; use the
existing **Vault Review** workflow for decisions that require an audited reason.
Other findings remain investigation-only.

The **Export health report** contains only scan status, source availability,
and category counts. It is not the anonymized audit export and does not include
record identifiers, player names, raw evidence, or transactions.

Use **Export anonymized audit** for a separate, bounded summary of recorded
audit events and ledger transaction types. Unknown event labels are replaced
with fixed generic values; names, actor IDs, reasons, season identifiers, and
executable transactions are not included. Review the output before sharing it.

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
