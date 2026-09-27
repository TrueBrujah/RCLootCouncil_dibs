# Research: Guild-Authoritative Loot Rules

## Decision: Reuse `SEASON_CATALOG` with an Explicit Nested Authority Record

The existing season catalog is the smallest authority surface that already fits this configuration. `Seasons.PublishCatalog` records author identity, timestamp, parent revision/hash, a content hash, rank rules, and guild configuration. `SyncV2` advertises and transfers the catalog with its existing bounded transfer, sender validation, replay handling, missing-parent recovery, and synchronization diagnostics.

The current code already includes `dibAllowedTypes` and `dibRCEnabledTypes` in the catalog's legacy `GUILD_SETTING_KEYS`. `ApplyCatalog` copies those values to local settings, and `Sync.OnLifecycle` can publish changed guild configuration after comparing it with the current record. This proves transport exists, but not explicit Loot Rules adoption, local-draft isolation, or the required GM review/publish UX. The feature will make the authority explicit rather than add another transport.

## Alternatives Considered

### Extend `OperationalPolicy`

OperationalPolicy is a strong source for settings with explicit GM adoption, revisioned records, audit, writer authorization, and V2 synchronization. Its value normalizer is a strict allowlist that currently excludes loot-type maps. Adding loot rules there would create a second authority alongside the existing season-catalog copy and require a migration/precedence rule between the records. It is not selected. OperationalPolicy remains unchanged.

### Add a Dedicated `LOOT_RULES` Sync Entity

A dedicated entity would isolate the domain and make incompatible payload handling explicit, but would require duplicating catalog revision ordering, hashes, writer validation, authorization, digest/detail dispatch, deduplication, recovery, and peer status. It would also duplicate the existing catalog transport for fields already carried there. It is not selected.

### Reuse `SEASON_CATALOG`

Selected. Add `guildConfiguration.guildLootRules` with its own schema version. The surrounding catalog revision supplies ordering, author, timestamp, hash, synchronization, and audit chain. Explicit adoption is represented by the presence of a validated nested authority record, not by OperationalPolicy state.

## Version and Compatibility

`Sync.GetAddonVersionCompatibility` accepts peers only when their addon `major.minor` family matches. The outer protocol envelope and `SEASON_CATALOG` entity do not need new message types, but the catalog payload gains a versioned nested rule record. The feature ships in addon version `0.8.0`, causing 0.7.x messages to be rejected with the existing `ADDON_UPDATE_REQUIRED` path before payload application. Mixed-version clients remain visibly incompatible and cannot overwrite the new authority.

## Migration and Effective Values

- Preserve `settings.dibAllowedTypes` and `settings.dibRCEnabledTypes` as local legacy/draft values.
- Treat only a valid explicit `guildLootRules` record in the current catalog as adopted authority. Legacy keys in old catalog records do not silently count as GM adoption.
- First adoption is GM-only and copies a complete preview built from the existing dynamic Loot Rules option source.
- Later edits remain local draft changes until the verified current GM explicitly publishes them. Officers remain read-only consumers even if existing catalog permissions let them publish other settings.
- When no authority exists, use the preserved local behavior and report `LOCAL_LEGACY_ONLY` or `GUILD_LOOT_RULES_NOT_CONFIGURED`.
- When authority exists, use only that record. Known behind, incompatible, or invalid states never fall back to local draft values.

## RCLootCouncil Application

The existing integration APIs are `IsDibEnabledForType`, `IsRCButtonEnabledForType`, and `RefreshConfigProjection`. Effective getters will consult the guild authority, while local maps remain draft/fallback storage. A successfully applied catalog revision will invoke the existing deferred DIBS projection refresh. Feature code will not write arbitrary RCLootCouncil profile/SavedVariables tables.

## Raid-Time Updates

A complete catalog transfer is validated before `ApplyCatalog` mutates state. A successful apply switches that client to the new authority and refreshes its DIBS projection. Peers that are known to have a higher catalog revision, have a missing parent, or are incompatible report a non-ready state; they keep the last valid authority and never switch to local values. V2 does not provide an atomic multi-client barrier, so the audit and Officer UI must make any observed convergence gap explicit.

## Extension Hooks

`.specify/extensions.yml` is absent; feature workflow hooks are skipped.