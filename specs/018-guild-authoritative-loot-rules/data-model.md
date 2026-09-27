# Data Model: Guild-Authoritative Loot Rules

## Local Loot Rules Draft

Per-client legacy/draft values retained in the existing settings maps.

- `dibAllowedTypes`: local Adventure Guide / DIBS eligibility decisions.
- `dibRCEnabledTypes`: local RCLootCouncil DIBS-button decisions.
- Ownership: local client only; never authoritative by itself.
- Migration: preserve values exactly. Do not overwrite an existing local map when receiving a catalog.
- Draft coverage: an adoption or publication preview fills missing choices by querying the current `GetLootTypeOptions()` descriptor and the current DIBS RC option API, not by a hardcoded loot-type list.

## Guild Loot Rules

Nested at `SEASON_CATALOG.guildConfiguration.guildLootRules`.

```text
guildLootRules = {
  schemaVersion = 1,
  types = {
    [<canonical option-source key>] = {
      adventureGuide = <boolean>,
      rclootcouncil = <boolean>
    }
  }
}
```

- Presence in the current valid catalog record means explicitly adopted guild authority.
- The catalog record supplies the guild key, catalog revision, parent revision/hash, author identity, timestamp, audit action, and content hash.
- The nested `schemaVersion` versions the Loot Rules data independently of the existing catalog entity.
- Keys must be drawn from the current dynamic `GetLootTypeOptions()` source; values must be booleans; all currently supported keys must be present in a published snapshot.
- Unknown or malformed keys/values reject the record before application.
- A record without `guildLootRules` is legacy/unadopted unless a prior adopted state would be downgraded; an active authority cannot be removed by an older or incomplete record.

## Effective Loot Rules

A transient projection used by the RCLootCouncil and Adventure Guide integration.

- If a valid adopted catalog record exists and is current/compatible, use its `types` map.
- If no adopted record exists, use local legacy settings and report local-only/unconfigured status.
- If an adopted record is invalid, synchronization is behind, or the peer is incompatible, do not fall back to local values. Retain the last valid authority where available and expose the failure state.
- No separate SavedVariables root or mutable cache is authoritative.

## Publication Audit

The existing catalog record carries publication identity and order. Loot Rules publication adds an action and changed-type summary to its existing audit data. Adoption and each subsequent revision use catalog ordering; a failed publication creates no authoritative revision and does not replace the previous effective record.

## Status Projection

- `GUILD_LOOT_RULES_READY`: valid adopted current record; no known catalog lag or incompatible required peer.
- `GUILD_LOOT_RULES_NOT_CONFIGURED`: no valid adopted record and no usable local legacy configuration.
- `GUILD_LOOT_RULES_SYNC_BEHIND`: the local catalog is known to be behind or missing a parent.
- `GUILD_LOOT_RULES_INCOMPATIBLE`: required peer/version or nested rule schema cannot be represented.
- `LOCAL_LEGACY_ONLY`: local rules can run but no explicit guild authority exists.
- `UNAVAILABLE`: the option source or required configuration projection cannot be evaluated.

## Relationships

- One current `SEASON_CATALOG` revision owns zero or one active Guild Loot Rules record.
- A local draft is independent per client and may differ from current authority.
- Effective Rules select exactly one source: adopted catalog authority, otherwise legacy local fallback only before adoption.
- RCLootCouncil and Adventure Guide consume the same effective type decisions.
