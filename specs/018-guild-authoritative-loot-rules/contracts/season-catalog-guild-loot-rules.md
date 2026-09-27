# Wire Contract: Guild Loot Rules in `SEASON_CATALOG`

## Placement and Authority

This is a nested data contract for the existing `SEASON_CATALOG` entity, not a new SyncV2 entity or protocol message. The current catalog revision chain is authoritative. The field is omitted before explicit GM adoption and is present on every subsequent catalog revision while adopted.

```lua
guildConfiguration.guildLootRules = {
  schemaVersion = 1,
  types = {
    ["<canonical dynamic option key>"] = {
      adventureGuide = true,
      rclootcouncil = false,
    },
  },
}
```

`types` is a complete snapshot of the publishing client's current supported option-source keys. Both decisions are explicit booleans. The concrete key set comes from `Dibs.RCOptions.GetLootTypeOptions().types`; it is never duplicated as a hardcoded protocol list. Permanently prohibited personal categories remain false under the existing semantic eligibility safeguards.

## Validation and Application

A receiving client MUST validate, before mutation:

- the outer `SEASON_CATALOG` guild key, author/sender, revision, parent chain, and content hash;
- `schemaVersion == 1`;
- every key against the current canonical dynamic option source;
- every type entry contains both boolean decisions and no unsupported fields or values;
- the snapshot contains all currently supported keys;
- an already adopted authority is not omitted or downgraded by a later catalog revision.

A valid duplicate revision is idempotent under the existing catalog hash/replay rules. Stale, conflicting, malformed, unauthenticated, missing-parent, or unsupported records do not change effective rules or local legacy maps. The existing bounded catalog detail-transfer limits continue to apply.

## Local Draft and Publication

`dibAllowedTypes` and `dibRCEnabledTypes` remain per-client draft/fallback maps. They are not copied into newly published guild configuration, and an incoming catalog's legacy copies MUST NOT overwrite them. A draft save does not advance catalog revision or effective guild behavior.

First adoption and every later publication are explicit GM-only actions. Broader catalog-writer permission does not grant Loot Rules publication rights. A publication preflights verified current-GM identity and transport availability, constructs a complete snapshot, and commits one catalog revision. Before the commit point, any failure leaves the prior authority effective. After commit, synchronization lag is represented by the existing catalog digest/recovery state and the Loot Rules readiness projection; clients keep the last valid authority and never fall back to local draft values.

## Compatibility

The payload change ships in addon version `0.8.0`. SyncV2's existing same-major/minor compatibility rule rejects 0.7.x peers with `ADDON_UPDATE_REQUIRED`; no old peer may author or apply a format it cannot represent. No root SavedVariables schema or protocol-envelope version changes are planned.
