# RCLootCouncil_dibs

RCLootCouncil_dibs is a World of Warcraft Retail addon for seasonal guild Dibs
and Pre-Dib loot management. It can run on its own or integrate with
RCLootCouncil when that addon is installed.

RCLootCouncil manages the local loot session. RCLootCouncil_dibs manages the
guild Dibs ledger, reservations, permissions, and audit history.

## Downloads

- [Stable release v0.3.5](https://github.com/TrueBrujah/RCLootCouncil_dibs/releases/tag/v0.3.5)
- Development builds are published from the `dev` branch and its GitHub Actions artifacts.

Each release includes a WoW-ready ZIP and a SHA-256 checksum. The repository is
currently private, so GitHub download links require repository access. A public
test mirror can be used for guild testers without exposing the source repository.

## Features

- Independent seasonal Dibs balances.
- Configurable allocations by guild rank.
- Append-only ledger and auditable transaction history.
- Player Pre-Dib requests with optional raid and Encounter Journal flows.
- Player and Officer interfaces with shared settings.
- Standalone operation when RCLootCouncil is absent.
- Optional RCLootCouncil Master Looter integration.
- RCLootCouncil item-family mapping and an installation assistant for Dibs buttons.
- Multi-raid synchronization of guild Dibs state without sharing live loot votes.
- Developer Mode for local item and request testing.
- Raid Readiness checks with clear Ready, Degraded, Blocked and Unavailable states.
- Local Dry-Run Center for testing a finalized DIB decision without touching live loot or balances.
- Officer Audit and Dispute Center with one-step player reports, private evidence review, and auditable corrections.
- Backup, restore, configuration profiles, and portable import/export packages with previews, checksums, retention, and append-only ledger deduplication.
- Character Eligibility for Curio and Tier Set progression across approved main/alt links, with seasonal policy, probation and bounded exceptions (dev 0.5.3).
- SavedVariables migrations and localized English/French runtime strings.

## How to use

### Installation

1. Download the stable or development ZIP from the release links above.
2. Extract it into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Confirm that the extracted folder is named `RCLootCouncil_dibs` and contains
   `RCLootCouncil_dibs.toc` directly inside it.
4. Enable **RCLootCouncil_dibs** on the character-selection AddOns screen.
5. Reload the interface with `/reload` after installing or updating.

Install RCLootCouncil separately when the guild wants the integrated loot
workflow. RCLootCouncil remains optional for the Dibs core.

### First-time setup for a GM or Officer

1. Run `/dibs options`.
2. Open **Settings** and choose the installation mode: `AUTO`, `STANDALONE`, or
   `RCLootCouncil`.
3. Create a season under **Seasons** and make it active.
4. Configure the guild rank allocations under **Rank Rules**.
5. Open **RCLootCouncil > Dibs > RCLootCouncil > Installation assistant** and
   choose **Curio + Tier Set** or **Standard loot + collections**. Use **Refresh
   Dibs buttons** after changing RCLootCouncil's enabled button sets.
6. Choose the Pre-Dib mode, announcement channels, and supported loot types.
7. Review **Overview** to confirm the season, permissions, and integration status.
8. Open **RCLootCouncil > Dibs > RCLootCouncil > Raid Readiness & Dry-Run** and
   run the readiness check before a raid. Use the dry-run form to validate a
   test item, winner, response, finalization status, and synthetic session ID.
9. Open the **Data** tab for safety backups, named local/guild profiles, and
   portable package transfer. Every restore or import shows a preview and
   requires an explicit confirmation.

Only the current guild master and officers selected by the configured guild
rank policy can change Dibs settings, seasons, rank rules, modes, or balances.

### Player workflow

1. Open `/dibs ui` for the modeless Player window. Use `/dibs options` only for
   configuration and launch buttons.
2. Review the active season, current balance, and active Pre-Dibs.
3. Use the Encounter Journal or an RCLootCouncil loot row when a supported item
   offers a Dibs action.
4. Submit a Pre-Dib before the drop when the active season allows it.
5. Review your transaction history after an award, refund, or adjustment.
6. Open **My requests** (or use `/dibs requests`) to report a Dibs problem with
   an optional transaction, follow its status, answer an Officer question, and
   read the final explanation.

A Pre-Dib is a reservation request. It does not spend a Dib until a qualifying
award is finalized. A request that does not win remains active unless guild
policy or the player cancels it.

### Officer workflow

Open `/dibs officer` for the separate, modeless Officer control center. Its navigation mirrors the
RCLootCouncil layout:

- Overview
- Review Requests
- RC History
- Seasons
- Rank Rules
- Settings
- Pre-Dibs
- Announcements
- Developer
- RCLootCouncil
- Debug

Officer pages use the same protected callbacks and SavedVariables as the main
options panel. The Officer view can inspect the complete ledger and history,
manage seasons and allocations, configure announcements, and review diagnostics.
Review Requests is a private GM/Officer queue. Filter by status or player/item,
inspect the attached Dibs and RCLootCouncil references, then choose a clear
action. A reason is required for every resolution; corrections, refunds,
revokes, historical imports, and adjustments also require explicit confirmation
and append one linked ledger transaction.
For a **Wrong item or player** report, **Correct player** is selected from the
current guild roster (with a search field), and **Correct item** is selected
from a session-cached Adventure Guide raid-loot catalogue. Item search matches
the name, ID, raid, boss, Dibs category, and equipment metadata; when the game
does not expose Adventure Guide data, the form explains the reason and offers a
refresh instead of accepting arbitrary item text.
The **Raid Readiness & Dry-Run** page is read-only: it explains missing raid
context or integration capabilities, opens a privacy-safe report in a
selectable window with the addon version, and shows whether a qualifying live
award could consume a Dib after final revalidation.

The **RC History** page is the recovery tool for an existing RCLootCouncil
history. It asks for a target season, optional timestamp range, exact response
aliases (for example `DIB`, `Reserve`, or a localized label), and guided or
manual review. **Search history (preview)** is read-only and reports eligible,
already accounted, ambiguous, rejected, and unsupported rows. Select a row to
inspect its immutable source evidence. Guided confirmation accepts only a final
award with a stable history identity and an exact alias; manual confirmation is
available for legacy rows only after an Officer checks an acknowledgement and
enters a reason. Each confirmed row appends one `rclootcouncil_history` debit,
keeps the original award time beside the import time, and is idempotent across
reloads. RCLootCouncil history is never rewritten and these controls are
available only to verified guild GMs and Officers. Select a row and use **Open
in Adventure Guide** to jump to its raid and boss when the Adventure Guide
catalogue can identify them.

### Backup, profiles and transfer

The **Data** tab opens a separate modeless window with three small workspaces:

- **Backups** creates dated local recovery points, shows scope, size and checksum,
  and keeps the configured retention count. Restore always creates a safety
  snapshot, then shows a preview before applying it.
- **Profiles** manages named local presentation profiles and guild policy
  profiles. Create, copy, activate, reset and delete operations never remove
  ledger transactions. Guild policy activation remains GM/Officer protected.
- **Import / Export** produces a versioned `DIBS-PKG-1` text package. Local,
  guild-configuration and full-data scopes are labelled; sensitive scopes can be
  redacted. Packages are size, schema and checksum validated and imported as data
  only. Configuration uses explicit merge/replace, while full history uses
  append-and-deduplicate semantics and reports conflicts in the preview.

Copy packages through a private channel or file. Full-data packages contain
player identities and award history; do not publish them. A cancelled preview
does not change settings, profiles, balances or history.

### RCLootCouncil workflow

When RCLootCouncil is installed, Dibs adds a `DIB` response to the supported
Master Looter response sets without overwriting existing responses. The local
RCLootCouncil Master Looter manages the loot session and finalizes awards using
RCLootCouncil's own permissions.

For the supported Retail integration, RCLootCouncil identifies the Raid Leader
as its Master Looter. Raid Assistant or council status alone does not grant
Master Looter authority or Dibs administration.

After a verified Master Looter finalizes a qualifying `DIB` award, the adapter
records one protected Dibs debit. Normal, test, failed, pending, or duplicate
award events do not consume production Dibs. The Dibs ledger remains the
authoritative source for balances and history.

The source event `RCMLAwardSuccess` and the Dibs accounting action
`FinalizeAward` can appear as Officer evidence labels during reconciliation;
they are informational references and are never executable buttons.

Use `/dibs readiness` for an authorized administrative check; it opens the
selectable report window. Use
`/dibs dryrun <itemID/link> <winner> <response> <finalized|test|pending> [session]`
for a bounded local simulation. Both commands are read-only with respect to
the ledger, RCLootCouncil history, loot sessions, votes, chat traffic and
SavedVariables.

### Slash commands

```text
/dibs help
/dibs balance
/dibs ui
/dibs officer
/dibs requests
/dibs review
/dibs reconcile
/dibs options
/dibs data
/dibs backup
/dibs profiles
/dibs import
/dibs export
/dibs grant <player> <amount>
/dibs use <player> <amount>
/dibs pre <itemID> [name]
/dibs season create [name]
/dibs season set <id>
/dibs season list
/dibs rank set <index> <amount> [name]
/dibs rank list
/dibs admin list
/dibs admin add <Name-Realm>
/dibs admin remove <Name-Realm>
/dibs dev on
/dibs dev off
/dibs dev status
/dibs testitem <itemID>
/dibs debug report
/dibs debug rc
```

The legacy `admin add` and `admin remove` commands remain for migration history;
they do not grant authority to a character who is not a verified guild GM or
Officer.

## Authority and security

Guild GM and Officer authority is the same in Standalone and RCLootCouncil
modes. The verified RCLootCouncil Master Looter has a narrow exception: a
finalized qualifying DIB award may consume the configured Dib cost. The Master
Looter cannot grant, remove, refund, or configure Dibs unless that character is
also a verified guild GM or Officer.

Council membership, Raid Leader status, and Raid Assistant status alone do not
grant Dibs administration. Unknown or unverifiable authority fails closed.

Live RCLootCouncil candidates, votes, responses, and loot-session data never
cross raid groups. Synchronization is limited to guild Dibs state and recovery
metadata. Protected UI work is deferred while the player is in combat.

See [docs/SECURITY_DESIGN_REVIEW_2026-09-06.md](docs/SECURITY_DESIGN_REVIEW_2026-09-06.md)
for the security and design review, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for module boundaries, and [docs/PROTOCOL.md](docs/PROTOCOL.md) for the sync
protocol.

## Developer testing

Developer Mode tests the request flow locally without a raid, Master Looter,
RCLootCouncil event injection, or production ledger changes:

```text
/dibs dev on
/dibs testitem 275658
```

Run the repository test harness from PowerShell:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx --yes fengari tests/run.lua
```

See [docs/DEVELOPER_MODE.md](docs/DEVELOPER_MODE.md) and
[docs/RC_OPTIONS.md](docs/RC_OPTIONS.md) for focused validation steps. The full
[guild test plan](docs/TEST_PLAN.md) lists the manual scenarios and evidence to
record. Character Eligibility is available on `dev` under the Officer
**Loot Eligibility** page; its Retail validation checklist remains explicit
because protected-loot decisions should be tested with real Curio and Tier Set
items before production use.

## Repository layout

- `src/Core.lua`: addon entry point, initialization, and slash commands.
- `src/modules/`: seasons, rank rules, ledger, Pre-Dibs, permissions, and sync.
- `src/integrations/`: optional RCLootCouncil and Encounter Journal adapters.
- `src/ui/`: Player and Officer interfaces.
- `src/locales/`: runtime localization files.
- `docs/`: architecture, protocol, options, security, and roadmap documentation.
- `specs/`: Spec-Kit feature specifications and validation artifacts.

The Dibs core does not depend on RCLootCouncil. Integrations are adapters and
must not own business rules or rewrite RCLootCouncil data.

## Spec-Kit workflow

Spec-Kit is installed once at the repository root through `.specify/`. Select an
active feature without changing the current Git branch:

```powershell
pwsh scripts/select-spec.ps1 001-dibs-core
pwsh scripts/select-spec.ps1 004-rclootcouncil-integration-robust
```

Use the feature workflow in this order:

```text
/speckit.specify
/speckit.clarify
/speckit.plan
/speckit.tasks
/speckit.analyze
/speckit.implement
/speckit.converge
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution rules and architecture
constraints.

## License

MIT.
