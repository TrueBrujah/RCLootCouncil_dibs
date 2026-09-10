# Dibs Project Constitution

<!--
Sync Impact Report
Version change: 2.3.0 -> 2.4.0
Modified principles: none; Governance metadata updated
Added sections: XXI. Human-Centered Interface and Search Quality
Removed sections: none
Rationale for MINOR bump: add enforceable interface and search quality rules so that
  every future feature remains readable, responsive, predictable, and easy to use.
Dependent documents: UI modules, options guide, search and history specifications,
  release checklist, and manual test plan must follow this rule. Existing ledger,
  protocol, and SavedVariables data remain compatible.
Follow-up TODOs: TODO(RATIFICATION_DATE) remains because the original adoption date is unknown.
-->

## Core Principles

### I. World of Warcraft API Compliance

The addon MUST use only APIs and addon communication mechanisms permitted by the current World of Warcraft Retail client.

The addon MUST NOT automate protected gameplay actions, bypass protected UI restrictions, or require modification of Blizzard client files.

Combat safety is mandatory. Non-critical processing SHOULD be deferred when execution during combat could destabilize the UI.

### II. Dibs Are Not DKP

A Dib is not DKP and MUST NOT be implemented as a generic boss-kill currency.

The system MUST NOT assume:
- boss kills automatically grant points;
- receiving any item automatically consumes a Dib;
- the player with the largest numeric balance automatically wins loot.

Dib eligibility and consumption MUST be decided by explicit Dibs rules.

### III. Seasonal and Rank-Based Allocation

Dibs MUST be allocated by season.

Each season MUST support independent configurable allocations per guild rank.

Rank allocation values MUST be configuration data and MUST NOT be hard-coded into business logic.

A player's rank at the time of a ledger transaction MUST be preserved in that transaction.

Rank changes during a season MUST NOT silently rewrite historical allocations or historical transactions.

### IV. Append-Only Ledger and Auditability

The authoritative accounting model MUST be an append-only ledger.

Existing ledger transactions MUST NOT be deleted or rewritten to correct mistakes.

Corrections MUST be represented by new transactions such as:
- DIB_REFUNDED
- DIB_REVOKED
- DIB_ADMIN_ADJUSTMENT

Every authoritative transaction MUST contain enough information to audit:
- unique transaction ID;
- timestamp;
- season;
- player identity;
- player rank at transaction time;
- action;
- Dib quantity delta when applicable;
- related item when applicable;
- originating authorized actor/system;
- reason when administrative.

Balances MUST be derivable from ledger transactions.

### V. Player and Administrative Visibility

Players MUST be able to view:
- their current seasonal allocation;
- their current Dib balance;
- their active Pre-Dibs;
- their own Dib transaction history.

Authorized Officers and GMs MUST be able to view the complete Dib ledger and history for all players.

Active public Pre-Dib information MAY be visible guild-wide according to configuration.

Administrative-only metadata MUST NOT be exposed to normal players unless explicitly configured.

### VI. Two Supported Dib Workflows

The system MUST support both:

1. **Pre-Dib**
   - A player requests a Dib on a specific supported item before the item drops.
   - The request is logged and synchronized.
   - A Pre-Dib reservation does not consume a Dib until a qualifying award is finalized.
   - A player who does not win the item retains the active Pre-Dib unless a rule explicitly cancels it.

2. **Drop-Dib**
   - When no applicable rule blocks it, a player may request use of a Dib during the local loot session.
   - A Dib is consumed only after the qualifying item is actually awarded.

Both workflows MUST use the same seasonal ledger.

### VII. RCLootCouncil Compatibility

RCLootCouncil integration MUST be optional and implemented as an adapter/module.

The project MUST NOT modify RCLootCouncil core source files.

The Dibs core MUST remain usable when RCLootCouncil is not installed.

The addon MUST support standalone operation and optional RCLootCouncil integration.
Both installation modes MUST use the same guild-based Dibs administrative permissions
defined in Principle XI. Installation mode and Pre-Dib/Drop-Dib workflow policy are
distinct settings, and changes to either MUST require GM or Officer authority.

RCLootCouncil MUST remain responsible for its own loot-session permissions and awards.
For the supported Retail integration, RCLootCouncil identifies the Raid Leader as its
Master Looter; Raid Assistant status alone MUST NOT be treated as Master Looter authority.
The adapter MUST verify the actual current RCLootCouncil Master Looter rather than
granting loot authority from a guild rank or Raid Assistant flag. Compatibility with
this behavior MUST be checked when supporting a new RCLootCouncil version.

The Master Looter MAY manage loot and finalize awards within RCLootCouncil's permissions.
Council members retain their RCLootCouncil permissions; council membership MUST NOT
implicitly grant Master Looter powers or Dibs administrative rights.

A finalized qualifying DIB award from the verified Master Looter MAY trigger automatic
Dib consumption by the Dibs system even when that Master Looter is not a guild Officer
or GM. This exception MUST be limited to the validated award and its rule-defined cost;
it MUST NOT allow arbitrary grants, removals, refunds, or settings changes. Ordinary
non-DIB awards and test awards MUST NOT consume production Dibs. Repeated delivery of
the same award MUST NOT consume a Dib more than once.

RCLootCouncil MAY:
- expose a DIB response;
- display Dib-related columns or status;
- provide local loot-award information;
- trigger local adapter events.

RCLootCouncil MUST NOT be the authoritative source of Dib balances or Dib history.

Live RCLootCouncil loot-session data MUST NOT be synchronized between separate raid groups.

### VIII. Encounter Journal Integration

Where technically supported by the current WoW Retail API, the addon SHOULD add a localized action such as "I want to DIB this" to supported Encounter Journal raid loot views.

The stored action MUST use stable internal identifiers, not localized display strings.

Localization MUST be separated from business logic.

When the Encounter Journal provides raid loot metadata, the addon MAY apply a user-configurable Adventure Guide sub-category matrix to decide whether a loot row is locally eligible for the Dib action. This matrix is a local policy layer for display and filtering only; it MUST NOT override authoritative guild ledger rules, season allocations, or historical audit records.

Adventure Guide categories MUST remain semantic. `TOKEN` represents a general or
Curio token pool, while `TOKEN_SET` represents a class-based Tier Set token pool.
`CATALYST` represents a personal player resource and MUST always be blocked from
Dibs actions, Pre-Dibs, Dibs response buttons, Dibs policy settings, and ledger
consumption. A saved or locally supplied Catalyst override MUST NOT re-enable it.

The default recommended matrix SHOULD prefer safe raid-eligible categories and SHOULD block clearly non-Dib categories such as Catalyst, cosmetics, housing decor, and other non-loot policy items. Catalyst MUST remain blocked even if a user attempts to change the local matrix. Unknown categories MAY remain visible by default to avoid suppressing legitimate combat loot by mistake.

### IX. Multi-Raid Operation

The addon MUST support multiple guild raid groups operating simultaneously.

No raid group is the exclusive source of truth.

Authorized Officers/GMs MAY create authoritative ledger transactions independently.

Cross-raid synchronization MUST include only guild Dib state such as:
- Dib grants/adjustments;
- Pre-Dib state;
- Dib consumption/refunds;
- finalized award history needed for Dib accounting/audit;
- synchronization metadata.

Cross-raid synchronization MUST NOT include:
- live item drops;
- current RCLootCouncil candidates;
- current RCLootCouncil votes;
- current loot-session state;
- live raid-specific loot discussions.

### X. Distributed Synchronization

Authoritative transactions MUST be:
- uniquely identifiable;
- immutable;
- idempotent;
- deduplicatable;
- order-tolerant where feasible;
- recoverable after clients reconnect.

Offline clients MUST be able to request missing state after reconnecting.

Synchronization SHOULD prefer delta synchronization and compact messages rather than repeatedly broadcasting the complete database.

The protocol MUST tolerate multiple authorized writers.

Last-write-wins MUST NOT be used for independent ledger transactions.

### XI. Authority and Trust

Normal player clients MUST NOT be authoritative for Dib balances.

Player requests such as Pre-Dib creation MUST be distinguishable from authoritative committed transactions.

Only the current GM and Officers of the guild whose Dibs data is being managed MUST
have Dibs administrative authority, in both standalone and RCLootCouncil integration
modes. Officer status MUST be derived from verified guild roster ranks and the guild's
configured Officer rank policy, not from raid roles or RCLootCouncil council membership.

GM/Officer authority MUST cover all Dibs administrative operations, including settings,
installation mode, workflow modes, seasons, rank allocations, and manual grants,
removals, refunds, and balance adjustments. These guild roles MUST NOT require Raid
Leader, Raid Assistant, Master Looter, or council status to administer Dibs.

Master Looter, council, Raid Leader, and Raid Assistant roles alone MUST NOT grant Dibs
administrative authority. A player who also holds a verified GM/Officer guild role
retains that role's Dibs rights. Standalone administrator appointments or other
delegation mechanisms MUST NOT grant these rights to a non-GM/non-Officer.

Authoritative administrative changes MUST be validated and committed under verified
GM/Officer authority. The only loot-role exception is automatic consumption for a
validated qualifying award under Principle VII: the Dibs system computes and records
the debit, and the Master Looter supplies the award event, not an arbitrary balance delta.

Player requests such as creating or cancelling their own Pre-Dibs MUST remain separate
from administrative operations and MUST NOT grant authority to change balances or policy.

Permission checks MUST be performed at the point where authoritative transactions are accepted.

Checks MUST also protect settings and mode changes, including changes received through
synchronization. Receivers MUST verify the actual sender and applicable guild or loot
authority rather than trusting a claimed role in a payload. Unknown or unverifiable
authority MUST be denied. RCLootCouncil absence, failure, or a mode change MUST NOT
expand Dibs administrative rights. Verified GM/Officer rights MUST remain available
independently of RCLootCouncil availability.

### XII. Raid Relay

When multiple authorized officers are in the same raid, the addon SHOULD elect or select a single active relay for routine raid-to-player synchronization, with standby takeover when necessary.

Duplicate relay traffic MUST NOT result in duplicate ledger transactions.

### XIII. Data Ownership and Persistence

Dibs SavedVariables own the Dib ledger.

RCLootCouncil SavedVariables MUST NOT be required to reconstruct Dib balances.

Data formats MUST be versioned and migrations MUST preserve historical audit data.

### XIV. Public Repository Quality

The project MUST remain suitable for a public GitHub repository.

Secrets, private guild identifiers, personal data, test credentials, and private logs MUST NOT be committed.

Public documentation MUST distinguish implemented behavior from planned behavior.

Breaking protocol or SavedVariables changes MUST be documented.

### XV. Developer Mode Safety and Isolation

An optional Developer Mode MAY inject local test loot contexts into Dibs for workflow validation.

Developer Mode MUST be explicitly enabled by user action and MUST be disabled by default.

Developer Mode MUST NOT:

- modify RCLootCouncil source code;
- impersonate Master Looter authority;
- emit fake RCLootCouncil network traffic;
- bypass Blizzard-protected action boundaries;
- inject fake global WoW events.

Developer Mode test flows MUST be marked as test contexts and MUST NOT silently mutate production authoritative accounting.

By default, Developer Mode test requests SHOULD remain local and SHOULD NOT emit production raid/guild announcement traffic.

### XVI. Embedded Framework Integration

The addon MAY embed Ace3 and companion libraries under `src/libs/` when they reduce operational risk or remove duplicated infrastructure.

When a library is adopted, the addon MUST:

- load its maintained embedded entry point from `src/RCLootCouncil_dibs.toc` before addon source modules;
- obtain the library through `LibStub` and tolerate the library being provided by another loaded addon, including RCLootCouncil;
- use only the minimum required library services;
- preserve Dibs-owned SavedVariables, migrations, ledger authority, and public behavior unless an explicit migration is specified and tested;
- keep business rules in Dibs modules rather than in framework callbacks;
- retain regression coverage for standalone operation with RCLootCouncil unavailable.

The available embedded library catalog is:

- AceAddon-3.0
- AceBucket-3.0
- AceComm-3.0
- AceConfig-3.0
- AceConsole-3.0
- AceDB-3.0
- AceDBOptions-3.0
- AceEvent-3.0
- AceGUI-3.0
- AceHook-3.0
- AceLocale-3.0
- AceSerializer-3.0
- AceTab-3.0
- AceTimer-3.0
- CallbackHandler-1.0
- lib-st
- LibDeflate
- LibDialog-1.0
- LibSharedMedia-3.0
- LibStub
- LibWindow-1.1
- MSA-DropDownMenu-1.0

AceComm and AceSerializer are preferred for addon-message transport. AceEvent and AceTimer are preferred for event registration and deferred retry work. AceConfig is preferred for persistent player and officer settings surfaces. AceGUI is preferred for complex reusable Dibs windows such as the officer dashboard, tabbed lists, search, and pagination. AceDB MUST NOT replace the existing Dibs SavedVariables layout without a separately approved migration plan. The other listed libraries remain available but MUST be adopted only for a concrete feature need, with load order, coexistence, fallback, and regression impact recorded in that feature's plan.

### XVII. Multi-Character and Multi-Guild Data Isolation

Dibs SavedVariables MUST isolate all guild-scoped state by guild identity (realm plus guild name), including the ledger, seasons, rank rules, Pre-Dibs, Officer rank policy, legacy administrator appointment history, and announcement/reminder/prompt settings.

Legacy standalone administrator appointments MUST be preserved as historical data
where present, but MUST NOT confer authority contrary to Principle XI.

A character that is not in a guild MUST be isolated per character rather than sharing a single unguilded bucket, so unguilded alts on the same account do not see each other's data.

Logging into a different character on the same WoW account, whether in a different guild or no guild, MUST NOT read, write, or leak another guild's or character's ledger, season, Pre-Dib, or settings data.

Any migration that introduces or changes the isolation key MUST preserve existing data for the currently active guild or character and MUST NOT delete or merge another guild's or character's historical data.

### XVIII. Diagnostics and Debug Visibility

All user-facing messages, diagnostic output, errors, and development controls MUST be emitted through a Dibs-owned diagnostic policy rather than direct unconditional output.

Each module and action family MUST have a named diagnostic scope and a numeric verbosity level from 0 through 5. Level 0 MUST suppress that scope's optional diagnostic messages and development-only controls; levels 1 through 5 MUST provide progressively more detail without changing business behavior.

The commands `/dibs debug <module> 0-5` and `/dibs debug all 0-5` MUST update the policy immediately and persist it in Dibs SavedVariables. Normal user-facing errors MAY remain visible at level 1, while debug traces, test controls, and verbose implementation details MUST require their configured level.

Diagnostics MUST NOT disclose live loot-session candidate, vote, response, or cross-raid private data. Debug controls MUST be absent or disabled when their scope is below the configured visibility threshold, and every new module MUST include automated coverage for its diagnostic scopes and level filtering.

All user-facing controls, tabs, fields, buttons, tooltips, status labels, and voting-frame Dibs indicators MUST provide concise help text. Localization MUST support the WoW client language and an explicit English or French override; English MUST remain the fallback when a translation is missing. Help text MUST explain the action's authority and whether it changes the ledger or consumes a Dib.

### XIX. Change Notes and Addon Versioning

Every committed change that modifies the addon source, behavior, user interface, security
policy, SavedVariables, protocol, embedded dependencies, or release configuration MUST
include a dated change note in the repository changelog. The note MUST state what changed,
why it changed, and any compatibility, migration, or player-facing impact.

Every shipped addon change MUST increment the `## Version` value in
`src/RCLootCouncil_dibs.toc`. The version MUST follow `MAJOR.MINOR.PATCH` semantics, with
an explicit development suffix permitted for unreleased builds. A commit that changes
addon behavior MUST NOT leave the addon version unchanged. Documentation-only edits that
do not alter the addon build still require a changelog note but MAY retain the addon
version.

The changelog entry and TOC version update MUST be reviewed together before a release is
accepted. SavedVariables or protocol migrations MUST identify their compatibility impact
in the same change note.

### XX. RCLootCouncil Item Mapping and Installation Safety

The RCLootCouncil adapter MUST translate loot into stable Dibs semantic families:

- `TOKEN` MUST represent general Curio or Context Token loot.
- `TOKEN_SET` MUST represent class-based Tier Set or Armor Token loot.
- `MOUNTS`, `PETS`, `RECIPE`, `DECOR`, and `OTHER` MUST remain independently configurable
  Dibs families.
- RCLootCouncil `Rare items` and `Items /w special effects` groups MUST resolve to
  the configurable `OTHER` family.
- Ordinary armor, weapons, and otherwise unclassified tradeable equipment MUST use
  `OTHER` when no more specific semantic family is available.
- Personal `CATALYST` loot MUST remain permanently ineligible for Dibs, even when it
  appears through RCLootCouncil's broader `Catalyst Items` group.

RCLootCouncil equipment-slot groups such as `Chest`, `Head`, `Trinket`, and `Weapon`
MUST be treated as response-routing compatibility sets only. They MUST inherit the
semantic Dibs decision and MUST NOT become independent Dibs accounting families.

The Installation assistant MAY apply a documented Dibs semantic preset and request
the adapter to prepare the dedicated Dibs response. It MUST require the same GM or
Officer settings authority as other Dibs policy changes, MUST be safe to run repeatedly,
and MUST preserve existing RCLootCouncil response text, colors, ordering, slot choices,
and active responses. The adapter MAY prepare the Dibs response in the default set and
additional sets already enabled by the Master Looter, but MUST NOT silently enable new
RCLootCouncil sets, overwrite a full response configuration, or modify RCLootCouncil
source code. When RCLootCouncil is unavailable, the preset MUST continue to configure
standalone Dibs and MUST be applied automatically if RCLootCouncil becomes available
later.

The Dibs ledger remains authoritative for Dibs balances, eligibility history, and
consumption. RCLootCouncil remains authoritative for its own loot-session responses
and awards; the mapping and projection provide compatibility and display only.

### XXI. Human-Centered Interface and Search Quality

The interface MUST be designed for a player who is unfamiliar with addon internals.
Labels, actions, status messages, and help text MUST use plain language, consistent
placement, readable contrast, and enough spacing to remain understandable at a glance.
Every actionable control MUST have a visible purpose and a concise explanation of its
effect on the ledger, a request, or a display-only view.

Blizzard's Options panel MUST contain persistent configuration only. Search, history,
statistics, review, import/export, and other workspaces MUST open in Dibs-owned modeless
windows so a player can keep the workspace open while using other game windows. Reports
that a player needs to inspect or copy MUST be available in a selectable Dibs view and
MUST NOT be delivered only through chat output.

Every table MUST provide:

- a visible header for every column and stable, aligned column boundaries;
- a date/time column whenever rows represent events, history, requests, or transactions;
- a deterministic default order, with the newest history first unless the feature says
  otherwise;
- clickable ascending and descending sorting with a visible sort indicator;
- bounded scrolling or pagination, responsive column widths, and no clipped, overlapping,
  or orphaned text at supported window sizes.

Search and filtering MUST keep the game UI responsive. Implementations MUST avoid a full
unbounded data scan and complete table rebuild on every keystroke; they MUST use bounded
results, incremental/deferred work, caching, or indexing when the data set can grow. A
search view MUST show its active filters, result count, loading state, empty state, and
recoverable error state. Where the source provides the data, player selectors MUST be
restricted to the guild roster and item selectors MUST use the Adventure Guide catalog,
with autocomplete or a dropdown plus search by player, item name, item ID, boss, and
semantic loot type.

Finite-choice controls SHOULD use the embedded `MSA-DropDownMenu-1.0` library, and large
tabular data SHOULD use the embedded scrolling-table library. Row right-click menus MAY
expose sorting and row actions, but the same action MUST remain discoverable without a
right-click. Item values MUST remain real WoW item links with their tooltip; when the
Retail API permits it, an item link SHOULD open the corresponding Adventure Guide entry.

Every UI feature MUST include an acceptance check for a narrow and a wide supported
window, table alignment and sorting, date visibility, menu discoverability, and search
responsiveness with a realistic history size. A release MUST reject any screen that
freezes the client, hides the active filter or sort, loses the date, or leaves a player
unable to tell what action is available.

## Governance

This constitution governs all specifications, plans, tasks, and implementations in this repository.

A feature that conflicts with a MUST requirement requires an explicit constitution amendment before implementation.

Architecture decisions affecting ledger integrity, synchronization, authority, RCLootCouncil independence, cross-raid privacy, or embedded framework adoption MUST be reviewed against this constitution.

Amendments MUST record the approved policy, affected principles, compatibility impact,
and dependent-document follow-up in the Sync Impact Report. Versioning MUST use MAJOR
for incompatible principle changes, MINOR for new or materially expanded principles,
and PATCH for non-semantic clarifications. Every addon change MUST also follow Principle
XIX: add a dated changelog note and increment the addon TOC version when the addon build
or behavior changes. Specifications, plans, tasks, release notes, and code reviews MUST
check compliance with the current constitution before implementation is accepted.

**Version**: 2.4.0 | **Ratified**: TODO(RATIFICATION_DATE): original adoption date unknown | **Last Amended**: 2026-09-10
