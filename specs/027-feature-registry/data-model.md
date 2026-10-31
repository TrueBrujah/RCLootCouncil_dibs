# Data Model: Centralized Feature Registry

The registry adds no new SavedVariables structure. It reuses the canonical
operational policy record and adds only a public API over it.

## Entities

### Feature definition

The canonical description of one feature. Lives in a Lua table, not in
SavedVariables.

| Attribute | Type | Description |
| --- | --- | --- |
| `key` | string | Stable identifier. Appears in the persisted overlay, in reason codes, and in the registry API. Never renamed. |
| `label` | string | User-facing name. Localized in the interface, not stored. |
| `description` | string | One-line explanation shown in the officer interface. |
| `category` | string | `core`, `workflow`, `integration`, `rules`, or `data`. Presentation grouping. |
| `core` | boolean | Marks a required service. |
| `alwaysEnabled` | boolean | Marks a feature that can never be turned off. |
| `defaultEnabled` | boolean | The catalogue default. `false` marks an opt-in feature. |
| `requires` | string, optional | The key of the feature this one depends on. |
| `configurable` | boolean | `false` means the feature exposes no toggle. |

**Uniqueness**: `key` is unique across both the required and the optional set.

### Catalogue

The ordered list of feature definitions. Exactly one exists, in
`src/modules/OperationalPolicy.lua`.

| Attribute | Type | Description |
| --- | --- | --- |
| `CATALOGUE_VERSION` | integer | Incremented when the catalogue changes. Published through `Policy.GetCatalogueVersion()`. |

The catalogue is **not** persisted. It is part of the build.

### Module overlay

The sparse map of explicit guild decisions. Persisted inside the canonical
operational policy record.

| Attribute | Type | Description |
| --- | --- | --- |
| *(key)* | string | A feature key. May be a feature this client does not know, when the record came from a peer with a larger catalogue. |
| *(value)* | boolean | `true` means the guild explicitly enabled it, `false` means the guild explicitly disabled it. |

**Invariant**: every value is a boolean. There is no third state. An absent
key means "use the catalogue default", which is never persisted.

**Persistence path**: `db.operationalPolicy.records[revision].values.modules`.

### Effective state

A derived value. Never persisted.

| Attribute | Type | Description |
| --- | --- | --- |
| `id` | string | The feature key. |
| `known` | boolean | Whether the feature is in this client's catalogue. |
| `enabled` | boolean | The effective state. |
| `required` | boolean | Whether the feature is a required service. |
| `alwaysEnabled` | boolean | Whether the feature is forced on. |
| `label` | string | The user-facing name. |
| `canDisable` | boolean | Whether the feature exposes a toggle. |
| `locked` | boolean | Whether the feature is locked on. |
| `reasonCode` | string, optional | Why the feature is not enabled. |
| `dependency` | string, optional | The blocking dependency, when dependency-blocked. |
| `dependencyReasonCode` | string, optional | Why the dependency itself is not enabled. |

### Registry guard

A pluggable in-flight operation check.

| Attribute | Type | Description |
| --- | --- | --- |
| *(function)* | `function() -> boolean, string` | Returns `false` and a reason code when an operation is in flight and the feature must not be disabled. |

Registered in `Dibs.FeatureRegistry.guards[featureId]`. The guard table is
empty by default. It exists so that the registry does not need to know the
internals of every domain module, and so that a domain module can register
its own guard without the registry depending on it.

## Relationships

```
Catalogue (1) --contains--> (N) Feature definition
                                 |
                                 | key
                                 v
Module overlay (N entries) --references--> Feature definition
                                 |
                                 | overlay + defaults
                                 v
                           Effective state (derived, not stored)
```

A feature definition may reference another through `requires`. The reference
is a key, not a pointer, so the catalogue stays a flat, serializable table.

## Invariants

1. **The catalogue is the only list.** The registry reads it. No second list
   of features exists anywhere in the codebase.
2. **The overlay is sparse.** Only explicit decisions are stored. An absent
   key means the catalogue default.
3. **The overlay never contains a non-boolean value.**
4. **The effective state is always derived.** It is never persisted and never
   trusted as an input.
5. **A required service is always enabled.** Its effective state never
   depends on the overlay.
6. **An unknown feature fails closed.** Its effective state is disabled with
   `FEATURE_UNKNOWN`.
7. **The dependency rule is evaluated against the effective state**, never
   against the raw overlay.
8. **The overlay is guild-scoped.** It lives in a record that carries the
   guild key, and a record from another guild is refused with
   `GUILD_SCOPE_MISMATCH`.

## Change log

| Version | Change | Effect on existing records |
| --- | --- | --- |
| `CATALOGUE_VERSION = 1` | Six optional features, seven required services. The overlay stored the complete map. | — |
| `CATALOGUE_VERSION = 2` | The catalogue grew to nineteen optional features and eight required services. The overlay became sparse. `rankRules` was reclassified as a required service. | **None.** The stored map keeps its exact shape and therefore its exact canonical content hash. No migration and no re-adoption are required. |

## Related documents

- [spec.md](spec.md)
- [plan.md](plan.md)
- [Feature catalogue](../../docs/developer/feature-catalog.md)
- [Saved variables](../../docs/developer/saved-variables.md)
