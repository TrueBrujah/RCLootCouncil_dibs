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

Only the current guild master and officers selected by the configured guild
rank policy can change Dibs settings, seasons, rank rules, modes, or balances.

### Player workflow

1. Open `/dibs ui` or `/dibs options` and select the Player view.
2. Review the active season, current balance, and active Pre-Dibs.
3. Use the Encounter Journal or an RCLootCouncil loot row when a supported item
   offers a Dibs action.
4. Submit a Pre-Dib before the drop when the active season allows it.
5. Review your transaction history after an award, refund, or adjustment.

A Pre-Dib is a reservation request. It does not spend a Dib until a qualifying
award is finalized. A request that does not win remains active unless guild
policy or the player cancels it.

### Officer workflow

Open `/dibs officer` for the full Officer interface. Its navigation mirrors the
RCLootCouncil layout:

- Overview
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
The **Raid Readiness & Dry-Run** page is read-only: it explains missing raid
context or integration capabilities, opens a privacy-safe report in a
selectable window with the addon version, and shows whether a qualifying live
award could consume a Dib after final revalidation.

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
/dibs options
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
[guild test plan](docs/TEST_PLAN.md) lists the manual scenarios, evidence to
record, and future Curio/Tier Set/main-alt checks.

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
