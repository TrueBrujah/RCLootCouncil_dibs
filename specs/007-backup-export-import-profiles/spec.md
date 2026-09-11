# Feature Specification: Dibs Backups, Data Transfer, and Configuration Profiles

**Feature Branch**: `007-backup-export-import-profiles`

**Created**: 2026-09-09

**Status**: Implemented on `dev` in version 0.5.8-dev; Retail visual validation remains scheduled.

**Input**: User description: "Add backups, export, import, and configuration profiles for RCLootCouncil_dibs so a guild can recover after a problem, move settings between characters or guilds, and share a safe configuration without accidentally overwriting the Dibs ledger."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create and restore a safety backup (Priority: P1)

As a GM or Officer, I want to create a local backup before a risky change, so that a broken import, migration, or SavedVariables problem can be recovered without losing Dibs history.

**Why this priority**: The ledger is authoritative and append-only. A recovery point protects the guild before profile changes, data transfers, or addon upgrades.

**Independent Test**: Create a backup containing a test season, balance, Pre-Dibs, policy, and audit record, change the active configuration, restore the backup in a test profile, and verify that the selected state is recovered with the original data intact.

**Acceptance Scenarios**:

1. **Given** Dibs contains guild data, **when** a GM or Officer presses **Create backup**, **then** the addon creates a dated, identifiable backup and reports its scope, size, schema version, and checksum without changing active balances.
2. **Given** a restore or import is about to replace configuration, **when** the operation is started, **then** the addon creates a safety snapshot of the current state before applying anything.
3. **Given** a backup is available, **when** a GM or Officer selects **Preview restore**, **then** the addon shows what would change and waits for explicit confirmation.
4. **Given** a backup restore is confirmed, **when** the operation completes, **then** the selected configuration and data are restored, the operation is recorded in the audit history, and unrelated guild or character data remains isolated.
5. **Given** a backup is corrupt, incomplete, or incompatible, **when** restore is attempted, **then** the addon rejects it without changing active data and explains the recovery reason.

---

### User Story 2 - Manage safe configuration profiles (Priority: P1)

As a player or guild administrator, I want named configuration profiles, so that I can switch between testing, production, character, and guild presentation settings without changing the Dibs ledger.

**Why this priority**: Guilds need different UI and policy presentations for testing, progression, and normal raids. A profile must never become a hidden way to reset balances.

**Independent Test**: Create two profiles with different UI and supported policy settings, switch between them, and verify that the active profile changes while seasons, balances, transactions, and confirmed loot history remain unchanged.

**Acceptance Scenarios**:

1. **Given** a user has permission to manage local settings, **when** they create, rename, copy, activate, reset, or delete a local profile, **then** only the profile's allowed configuration changes.
2. **Given** a GM or Officer manages a guild profile, **when** they activate it for the guild, **then** the profile's selected settings apply to the guild-scoped configuration after confirmation and the active ledger remains unchanged.
3. **Given** a profile contains policy settings such as rank allocations, Dibs modes, response aliases, or loot-family rules, **when** it is activated, **then** the addon shows that these are authoritative policy changes and records the actor and reason before applying them.
4. **Given** a player switches profiles, **when** the profile is loaded, **then** they cannot gain Officer visibility, GM/Officer authority, extra Dibs, or access to another guild's data.
5. **Given** a profile is reset or deleted, **when** the action is confirmed, **then** it removes only the selected profile configuration and never deletes ledger transactions, award evidence, seasons, or relationship history.

---

### User Story 3 - Export and import portable data (Priority: P1)

As a GM or Officer, I want to export and import a controlled package, so that I can move a guild configuration to another character, recover after reinstalling the addon, or share a policy with a new guild.

**Why this priority**: A portable package is the practical recovery path when a player changes computer, clears the WoW interface folder, or starts a new guild using the same rules.

**Independent Test**: Export a configuration package, import it into an empty test database, preview the differences, confirm it, and verify that settings match while the package cannot silently replace existing balances or private history.

**Acceptance Scenarios**:

1. **Given** a user selects **Export**, **when** they choose a package scope, **then** the addon explains whether the package contains local settings, guild policy, or sensitive ledger/history data before producing a portable text block.
2. **Given** a configuration-only package is imported, **when** the GM or Officer previews it, **then** the preview lists additions, changes, conflicts, omitted sensitive fields, source guild scope, addon/schema version, and checksum without mutating active data.
3. **Given** the administrator confirms a configuration import, **when** the package is valid and authorized, **then** allowed settings are merged or replaced according to the selected conflict strategy and every changed policy is audited.
4. **Given** a full data package is imported, **when** it contains ledger transactions, **then** transactions are validated, deduplicated, and appended without deleting or rewriting existing transactions.
5. **Given** an import targets a different guild, **when** the package contains guild-scoped ledger or history, **then** the addon blocks it by default and requires an explicit new-guild setup path that does not expose or merge the source guild's private identities.
6. **Given** an imported package is applied twice, **when** the second preview or import runs, **then** it reports existing settings and transactions as already present and creates no duplicate accounting.

---

### User Story 4 - Protect privacy and prevent unsafe imports (Priority: P1)

As a guild administrator, I want export and restore warnings, validation, and access controls, so that a copied package cannot leak private loot history or execute an unsafe change.

**Why this priority**: Export text can be copied into chat, tickets, or public websites. The addon must make sensitive content visible to the person exporting it and reject data that could bypass authority or corrupt accounting.

**Independent Test**: Attempt exports and imports as a normal player, a Master Looter, an Officer, and a GM using valid, malformed, future-version, cross-guild, and tampered packages, and verify the permission and rejection outcomes.

**Acceptance Scenarios**:

1. **Given** a normal player requests a guild ledger or full-history export, **when** the request is submitted, **then** it is rejected while the player may still export their permitted local UI profile.
2. **Given** a Master Looter, Raid Leader, Raid Assistant, or council member is not a guild GM/Officer, **when** they request policy, ledger, restore, or import access, **then** the request is rejected.
3. **Given** an export includes player names, award history, or guild identifiers, **when** the package is prepared, **then** the addon shows a sensitivity warning and offers a configuration-only or redacted alternative.
4. **Given** an import contains executable-looking content, invalid fields, an invalid checksum, or an unsupported schema, **when** validation runs, **then** the package is treated as data only, rejected, and never executed.
5. **Given** an import would change authority, actor identity, guild scope, or transaction ownership, **when** it is previewed, **then** the conflicting fields are ignored or rejected and cannot grant permissions.
6. **Given** a restore fails after the safety snapshot, **when** the failure is reported, **then** active data remains usable and the administrator can select the pre-operation snapshot for recovery.

---

### User Story 5 - Migrate across addon versions and installations (Priority: P2)

As a guild administrator, I want version-aware packages and migration guidance, so that I can restore data after an addon update or install Dibs for the first time without losing compatibility information.

**Why this priority**: SavedVariables and package formats evolve. Explicit compatibility prevents a new build from silently interpreting old or future data incorrectly.

**Independent Test**: Import packages from the current supported schema, an older supported schema, a newer unsupported schema, and a package with missing optional fields, then verify the migration, warning, and rejection behavior.

**Acceptance Scenarios**:

1. **Given** a package uses an older supported schema, **when** it is previewed, **then** the addon displays the migration path and expected compatibility impact before applying it.
2. **Given** a package uses a newer unsupported schema, **when** import is attempted, **then** the addon refuses it without changing active data and tells the administrator which addon update is required.
3. **Given** a package omits optional presentation settings, **when** it is imported, **then** documented defaults are used while authoritative ledger fields remain untouched.
4. **Given** an installation has existing Dibs data, **when** a configuration-only package is imported, **then** the existing ledger, seasons, Pre-Dibs, and evidence remain available and unchanged unless an explicitly confirmed data package is selected.

## Edge Cases

- The user cancels after the preview but before confirmation; no active data or profile is changed.
- The game reloads or the UI closes during an import; the package remains pending or is rejected safely, and the safety snapshot remains available.
- Two officers import the same package at nearly the same time; ledger transactions remain idempotent and policy conflicts require a visible decision.
- A backup contains a guild that no longer exists or a character that changed realm; the original identities remain historical labels and are not silently matched to a different character.
- A backup was created in standalone mode and restored while RCLootCouncil is installed, or the reverse; Dibs data remains valid and the integration status is re-evaluated separately.
- The same profile name exists in local and guild scopes; the UI clearly labels the scope and never activates one in place of the other without confirmation.
- An import contains a profile with an invalid or forbidden setting value; the invalid field is rejected or replaced by a documented default while valid fields remain reviewable.
- The exported text is truncated, pasted with extra formatting, or exceeds the supported size; validation rejects it with an actionable message and no mutation.
- A configuration package contains response aliases from another guild; aliases can be previewed but do not alter active policy until a GM/Officer confirms them.
- A full data import contains an award transaction whose `awardRef` already exists with different item or winner data; the conflict is blocked for manual review rather than merged.
- A backup includes private evidence or administrator notes; the export warning identifies the sensitive scope and redaction option before generation.
- A profile reset is attempted during combat or while a protected loot frame is visible; non-critical UI work is deferred and no ledger operation is performed implicitly.
- A player is unguilded or changes guilds; local profiles remain character-scoped, while guild policy, ledger, and history remain isolated by guild identity.
- A future feature adds new tracked loot families or main/alt data; unknown fields are preserved when safe and ignored by older builds without changing balances.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide manual backup creation and a visible list of available backups with creation time, scope, guild or character context, addon/schema version, size, and integrity status.
- **FR-002**: The system MUST create a safety snapshot before any restore, full-data import, profile reset that affects authoritative policy, or destructive profile operation.
- **FR-003**: The system MUST provide restore preview and explicit confirmation; preview and cancellation MUST leave active Dibs data unchanged.
- **FR-004**: The system MUST support at least three export scopes: local presentation profile, guild configuration and policy, and full Dibs data including ledger and audit history.
- **FR-005**: The system MUST clearly label sensitive export scopes and MUST offer a configuration-only or redacted export that excludes player identities, award history, ledger transactions, and administrator notes.
- **FR-006**: The system MUST produce a portable, versioned data package with an integrity check, documented package scope, source context, creation time, and compatibility metadata.
- **FR-007**: The system MUST validate package structure, size, scope, schema, integrity, required fields, guild or character context, and supported version before showing an import confirmation.
- **FR-008**: The system MUST treat imported content as data only and MUST never execute code, commands, serialized functions, hyperlinks, or embedded actions from a package.
- **FR-009**: The system MUST provide import preview with additions, changes, omissions, conflicts, migrations, sensitive fields, and expected ledger impact before mutation.
- **FR-010**: Configuration imports MUST support an explicit merge or replace strategy for allowed settings; the selected strategy MUST be visible and confirmed by the authorized administrator.
- **FR-011**: Full-data imports MUST validate each ledger transaction and append only new, authorized, valid transactions; existing transactions MUST NOT be deleted or rewritten.
- **FR-012**: Duplicate transactions, award references, profiles, and audit events MUST be idempotent and MUST report the existing record instead of creating a second accounting effect.
- **FR-013**: A full-data import targeting another guild MUST be blocked by default; a new-guild setup path MAY import non-sensitive configuration only and MUST never merge the source guild's private ledger or identities automatically.
- **FR-014**: GM/Officer authority MUST be required for guild policy export, full-data export, restore, full-data import, conflict resolution, and activation of profiles containing authoritative settings.
- **FR-015**: Normal players MAY manage and export only permitted local presentation profiles; they MUST NOT import or export guild policy, ledger, complete history, permissions, or administrator data.
- **FR-016**: Master Looter, Raid Leader, Raid Assistant, council membership, and RCLootCouncil response ownership MUST NOT grant backup, restore, policy profile, ledger import, or complete export authority unless the actor is also a verified guild GM or Officer.
- **FR-017**: Configuration profiles MUST be named, scoped as local or guild, and independently creatable, copyable, activatable, resettable, and removable.
- **FR-018**: Switching or resetting a profile MUST NOT change Dibs balances, append or delete ledger transactions, alter finalized award evidence, change guild ownership, or grant permissions unless an explicitly confirmed policy profile operation is selected.
- **FR-019**: Profile content MUST distinguish presentation settings from authoritative policy settings, and the UI MUST warn when activation changes rank rules, Dibs modes, response aliases, loot-family policy, season selection, or other protected configuration.
- **FR-020**: Backups, profiles, packages, and restore points MUST remain isolated by guild identity and by character when unguilded; importing one scope MUST NOT expose or merge another scope.
- **FR-021**: Every backup creation, export, import preview, confirmation, rejection, restore, profile change, migration, and conflict resolution MUST be recorded with actor, scope, time, outcome, and reason where applicable.
- **FR-022**: The system MUST preserve unknown optional fields when safe, display unsupported or unknown fields explicitly, and reject packages that would require guessing authoritative identity or transaction data.
- **FR-023**: The system MUST retain a bounded number of local safety backups according to a configurable retention policy and MUST report when an older backup is pruned.
- **FR-024**: A failed or cancelled operation MUST leave the active Dibs ledger usable and MUST keep the pre-operation safety snapshot available for a subsequent restore.
- **FR-025**: The feature MUST work in standalone and optional RCLootCouncil integration modes without making RCLootCouncil SavedVariables authoritative for Dibs balances or history.
- **FR-026**: All profile, backup, export, import, warning, conflict, migration, and restore controls MUST provide localized labels and help text with English fallback, including whether the action changes policy, ledger, permissions, or privacy scope.
- **FR-027**: Any SavedVariables or package schema change MUST include a migration note, a dated changelog entry, and an incremented addon version before the behavior is shipped.

### Key Entities

- **Backup Snapshot**: A local, dated recovery point containing a declared scope, source context, schema, integrity metadata, retention status, and snapshot data.
- **Configuration Profile**: A named local or guild-scoped collection of presentation and optionally authoritative policy settings, explicitly separated from ledger data.
- **Export Package**: A portable, versioned representation of a selected profile, guild configuration, or complete Dibs data scope, with sensitivity and integrity metadata.
- **Import Preview**: A read-only comparison of package content against active state, including changes, conflicts, migrations, omissions, and expected accounting impact.
- **Import Decision**: An authorized confirmation, cancellation, rejection, merge, replace, or conflict-resolution choice with actor, reason, and timestamp.
- **Restore Point**: The automatically created pre-operation snapshot used to recover from a failed or undesired restore or import.
- **Transfer Scope**: The guild, character, profile, season, policy, ledger, history, or privacy boundary that determines what a package may contain and where it may be applied.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In automated and Retail acceptance tests, 100% of backup creation, import previews, cancelled imports, and cancelled restores leave active Dibs balances and transaction counts unchanged.
- **SC-002**: A GM or Officer can create a backup, export a configuration-only package, preview it, and identify its sensitivity and compatibility information in under two minutes during a normal test run.
- **SC-003**: 100% of valid supported packages restore or import according to their selected scope, while 100% of malformed, tampered, future-version, or unsafe packages are rejected without an active-data mutation.
- **SC-004**: 100% of repeated full-data imports produce no duplicate ledger transaction, award reference, or accounting effect.
- **SC-005**: In profile isolation tests, 100% of profile switches and resets leave balances, finalized award evidence, permissions, and guild ownership unchanged unless an explicitly confirmed policy change is selected.
- **SC-006**: In authority tests, 100% of guild policy, full-data, restore, conflict, and complete-history operations succeed only for verified guild GMs or Officers.
- **SC-007**: In privacy tests, configuration-only exports contain zero player identities, ledger transactions, award evidence, or administrator notes, and sensitive exports display a warning before generation.
- **SC-008**: In migration tests, every supported older package either imports with a documented result or is rejected with a clear recovery path; no supported migration loses an existing immutable transaction.
- **SC-009**: In failure-injection tests, every failed restore or import leaves a usable pre-operation snapshot and permits recovery without manual SavedVariables editing.
- **SC-010**: In standalone and RCLootCouncil integration tests, package and profile operations preserve Dibs as the source of truth and do not modify unrelated RCLootCouncil history or loot-session data.
- **SC-011**: At least 95% of test users can identify package scope, sensitivity, conflict strategy, and expected ledger impact from the preview without opening external documentation.

## Assumptions

- The current Dibs SavedVariables layout and append-only ledger remain authoritative; this feature adds versioned snapshots and packages without replacing the persistence model with an unrelated database format.
- Backups are local to the WoW installation unless a user manually copies the portable export text elsewhere. The addon does not provide cloud storage or assume a trusted external host.
- The default retention policy keeps five recent local safety snapshots per applicable scope, with an Officer-visible setting to change the bound and a warning before pruning.
- Configuration-only export is the default because it is the safest way to share settings. Full ledger/history export requires an explicit sensitive-data confirmation.
- A local presentation profile may be managed by its character owner. Guild policy profiles and any profile containing authoritative settings require GM/Officer approval to activate.
- Import defaults to preview-only and merge for configuration. Full-data packages use append-and-deduplicate semantics; replacing or deleting ledger history is never a supported operation.
- A package can be copied through the game's normal text interfaces and may be truncated or altered during copying; integrity validation must detect this before import.
- Export text is not encrypted. The UI must warn users not to publish sensitive packages and must provide a redacted option where possible.
- Imported profile settings cannot grant Dibs permissions, change actor identity, bypass guild verification, or override RCLootCouncil's own loot-session authority.
- Older supported package schemas may be migrated forward. Newer unsupported schemas are rejected until a compatible addon version is installed.
- Complete cloud sync, automatic computer-to-computer backup, encryption, and external account identity matching are outside this feature.
- The feature must obey the current constitution's GM/Officer authority, append-only ledger, data isolation, privacy, diagnostics, RCLootCouncil ownership, change-note, and versioning rules.
