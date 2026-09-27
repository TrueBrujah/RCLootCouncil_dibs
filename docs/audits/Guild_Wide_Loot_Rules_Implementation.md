# Guild-Wide Loot Rules Implementation

## Architecture Decision (Pre-Implementation)

- **Date:** 2026-09-25
- **Decision:** Reuse the existing `SEASON_CATALOG` authoritative entity, with an explicit, versioned `guildLootRules` configuration nested in its guild configuration. Do not add Loot Rules to `OperationalPolicy` and do not create a second synchronized entity.

### Evidence and Current Gap

The current source already places legacy `dibAllowedTypes` and `dibRCEnabledTypes` in `Seasons.lua`'s `GUILD_SETTING_KEYS`. `PublishCatalog` snapshots the guild settings into a revisioned, hashed season catalog; `ApplyCatalog` applies the catalog configuration. `SyncV2` advertises and transfers `SEASON_CATALOG` records through its existing bounded V2 mechanism. Catalog writes use the existing governance-backed writer authorization; that authorization does not require OperationalPolicy adoption.

This is a transport path, not a complete Loot Rules authority model. The current values are ordinary mutable settings, there is no explicit Loot Rules adoption marker or separate draft/effective projection, and the lifecycle sync path may publish changed guild configuration without a Loot Rules-specific review. The generic OperationalPolicy banner therefore does not describe the Loot Rules authority state.

### Alternatives

| Option | Assessment |
|---|---|
| Extend `OperationalPolicy` | It already has explicit adoption, revisions, audit, writer checks, and V2 distribution. However, its strict allowlist currently excludes Loot Rules, and adding those fields would duplicate the legacy settings already carried by `SEASON_CATALOG` while requiring a migration between two configuration authorities. Not selected. |
| Add a dedicated `LOOT_RULES` entity | Gives the feature an isolated schema, but duplicates existing catalog revision, hashing, authority, transfer, replay, and recovery mechanisms for settings already present in that catalog. Adds a second authority stream and cross-entity ordering. Not selected. |
| Reuse `SEASON_CATALOG` | Preserves the existing guild-configuration authority, writer validation, revision chain, hashing, detail transfer, and recovery. The new nested record can distinguish explicit guild adoption from legacy local settings without introducing another synchronized authority. Selected. |

### Compatibility and Migration Decision

The nested Loot Rules record will have its own schema version and be covered by the existing catalog content hash and catalog revision. Existing `settings.dibAllowedTypes` and `settings.dibRCEnabledTypes` remain intact as legacy/local draft data; they are not destructively migrated. Only an explicit Guild Master adoption publishes them as initial authoritative Loot Rules. Once active, the catalog record is the effective source and local settings cannot override it.

SyncV2 accepts peers only from the same addon `major.minor` family. The feature therefore requires the `0.7.0` version family so `0.6.x` clients fail closed through the existing `ADDON_UPDATE_REQUIRED` handling rather than silently ignoring the new authority marker. The V2 envelope and entity type remain unchanged; the `SEASON_CATALOG` payload gains the versioned nested configuration. No SavedVariables root schema bump is planned because the new record is additive data inside the existing persisted catalog history.

### Implementation Boundary

This feature will add explicit draft, adoption, publication, effective-configuration, readiness, and RCLootCouncil refresh behavior. It will not change Rank Rules or its Guided Setup reconciliation semantics, extend OperationalPolicy values, create a new addon-message protocol, or write unrelated RCLootCouncil SavedVariables directly. The prior Raid Readiness UX remediation audit remains separate and untouched.

**Implementation status at decision:** Not started. This architecture decision is recorded before implementation code changes.

## Implementation Evidence (0.7.0)

**Status:** Implemented in the development worktree; not Retail-certified.

### Authority and consumers

- `src/modules/LootRules.lua` derives its key set from the RCLootCouncil Loot
	Rules option source, normalizes complete schema-v1 snapshots, separates local
	drafts from catalog authority, and exposes status/effective-value APIs.
- `src/modules/Seasons.lua` stores the snapshot under
	`guildConfiguration.guildLootRules`, validates it before mutation, retains it
	across later catalog revisions, rejects downgrade/missing-parent records,
	and refreshes the DIBS-owned projection on apply and rollback.
- `src/integrations/RCLootCouncil.lua` and
	`src/integrations/RCLootCouncilOptions.lua` route both consumers and GM
	controls through the shared authority/draft APIs. `src/ui/OfficerUI.lua`
	exposes explicit GM adoption/publication and read-only Officer consumption.
- `src/modules/Readiness.lua` and Setup Assistant project the exact six Loot
	Rules states and include them in readiness summary/report output.

### Compatibility and migration

The version is `0.7.0`; SyncV2's existing major.minor gate rejects 0.6.x peers
with `ADDON_UPDATE_REQUIRED`. The catalog entity and root SavedVariables schema
are unchanged. Existing `dibAllowedTypes` and `dibRCEnabledTypes` remain local
and are not exported/applied as generic catalog settings. Before adoption they
are reviewable local input; after adoption the last validated guild snapshot
remains effective during sync lag. An incompatible client with no valid
authority does not silently fall back to local legacy values.

### Automated evidence

- Focused Wizard tests: **20 passed, 0 failed**.
- Feature quickstart focused suite: **80 passed, 0 failed (8 files)**, including
	the LRA01-LRA22 matrix across domain, UI, catalog, migration, and sync tests.
- Final full Fengari suite: **699 passed, 1 failed (143 files)**.
- Documentation generation, validation, and freshness checks: **PASS**; 26
	concepts, zero errors/warnings/missing locales/duplicate IDs, eight generated
	files current.

Failure classification from the first full run and final rerun:

| Failure | Classification | Resolution |
|---|---|---|
| `tests/integration/rclootcouncil_buttons_spec.lua:47` and `:138` | Loot Rules dynamic-source regression: active/configured RC profile keys were omitted, so the new authority resolver could not project those sets. | Fixed by sourcing all projected keys, including enabled sets with uninitialized arrays; both assertions now pass. |
| `tests/integration/setup_assistant_ui_spec.lua:254` | Test fixture defect: the Officer case still identified the actor as guild leader. | Fixed the fixture to make guild-leader status agree with the tested role; the UI spec now passes. |
| `tests/integration/predibs_sync_recovery_spec.lua:50` | **CONFIRMED PRE-EXISTING**: expected one scheduled heartbeat, observed two. This test and the Pre-Dib/Sync implementation are unchanged in the worktree. The final full run reproduces the same file, line, and values. | Unchanged; unrelated to Loot Rules. |

The final run has no other failures. No Rank Rules or Pre-Dib business behavior
was changed.

### Retail gate

**Final outcome: NOT READY.** Automated tests cannot establish real Retail
behavior for two-client synchronization, live raid-time application, the
RCLootCouncil profile projection, or narrow/wide UI layout. No Retail screenshots
were captured for this workflow. Complete the two-client and narrow/wide UI
scenarios in `specs/018-guild-authoritative-loot-rules/quickstart.md`, capture
screenshots, record evidence, then reassess this outcome. Do not treat the
0.6.5 B12 evidence as certification for 0.7.0.
