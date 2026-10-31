# Implementation Plan: Centralized Feature Registry

**Feature Branch**: `027-feature-registry`

**Status**: Implemented

## Summary

Extend the existing canonical operational policy module into a complete
feature registry, and enforce the resulting configuration state on every entry
path of every optional feature.

## Technical Context

| Item | Value |
|---|---|
| Language | Lua 5.1 (WoW Retail) |
| Module | `src/modules/FeatureRegistry.lua` |
| Canonical source | `src/modules/OperationalPolicy.lua` |
| Persistence | Canonical operational policy record, `values.modules` |
| Synchronization | Existing `OPERATIONAL_POLICY` entity in `SyncV2` |
| Test runner | `tests/run.lua` under Fengari |

## Design decision: extend, do not duplicate

A module system already exists in `src/modules/OperationalPolicy.lua`: a
canonical catalogue, authority verification, revisioned persistence, hash
validation, conflict detection, and an officer interface. Building a second
registry beside it would have created two sources of truth that could drift,
and it would have duplicated the authority, persistence, and synchronization
machinery that the constitution requires to stay canonical.

The registry therefore **reads** the canonical catalogue and adds only the
concerns the policy module did not have: a public registry API, a
deterministic effective-state resolver, a dependency graph, a single
enforcement gate, and a preview.

## Design decision: the sparse overlay

### The problem

The canonical content hash of a policy record is computed over its stored
`values`. The original implementation stored the **complete** module map,
reconstructed from the catalogue defaults and then overlaid with the guild's
patch.

Adding a feature to the catalogue would therefore have changed the stored
map of every existing record, and with it the content hash. On the next
load, `validateShape` would have recomputed the hash over the new map, found
a mismatch with the stored hash, and refused the record with
`POLICY_HASH_MISMATCH`. The parent chain would have been broken and the guild
would have been unable to adopt any new revision.

A schema bump would have avoided the hash problem but had its own cost: it
resets the policy to `POLICY_UNINITIALIZED`, forcing every guild to re-adopt
its policy and re-run the governance bootstrap.

### The solution

The stored map became a **sparse overlay**. It contains only the features a
guild explicitly decided. An absent key means "use the catalogue default".

```lua
-- stored: what the guild decided
values.modules = { requests = false, rclootcouncil = false }

-- effective: what the guild experiences
effective = defaultModules()
for key, enabled in pairs(overlay) do effective[key] = enabled end
```

Because the stored map keeps its exact shape when the catalogue grows, the
content hash of an existing record is unchanged. No schema bump, no
migration, and no re-adoption is required. The catalogue version is published
separately through `Policy.GetCatalogueVersion()`.

### Consequence for the audit trail

The audit trail records the **effective** transition, not the sparse map. A
reader of the audit log sees what the guild experienced before and after,
which is what an auditor needs. The sparse map remains the persisted form.

## Design decision: split the dependency rule by write path

The dependency rule — a feature cannot be enabled while its dependency is off
— is enforced on the **local write path** only.

Applying it during record shape validation would have coupled the validity of
a record to the catalogue of the receiving client. A peer running a different
catalogue would have had its records rejected outright, breaking the parent
chain and leaving the guild permanently out of sync.

The split is:

| Path | Rule applied | Result |
|---|---|---|
| `Policy.ChangeModules` (local write) | Dependency rule enforced | The guild cannot create an inconsistent state. |
| `OperationalPolicy.ApplyRecord` (remote acceptance) | Shape only | A peer record is accepted; the effective state of a dependency-disabled feature is resolved locally by the registry. |

## Design decision: retain unknown remote keys

A remote record may carry features this client does not know. Those keys are
**retained** rather than rejected, for two reasons:

1. The canonical content hash is computed over the stored map. Dropping an
   unknown key would change the hash of the new record and break the chain
   for every peer.
2. Rejecting the record would break the parent chain.

The unknown feature is not effective on the receiving client, because it is
not part of this client's catalogue. The registry reports it as
`FEATURE_UNKNOWN` and it fails closed.

A locally authored change may only reference features this client knows. The
two paths are distinguished by `validateLocalModulePatch`, which is applied to
local patches only.

## Design decision: required services are not optional features

The catalogue classification is driven by the code, not by intuition.

`rankRules` was initially classified as an optional feature. The audit found
that `src/modules/Ledger.lua` resolves the expected allocation from
`Dibs.RankRules.GetAllocationForPlayer` before validating an award, and
refuses the award with `RANK_RULE_INVALID` when the allocation cannot be
resolved. Making it toggleable would have made every allocation unverifiable,
and disabling it would have silently broken the canonical accounting path.

It was therefore reclassified as a required service. The same audit method
was applied to every other candidate feature, and the two candidate dependency
edges that the code did not support were rejected.

## Design decision: safety snapshots are exempt from the backup gate

`Backup.Create` is gated by the `backup` feature. However, four other
operations call it to take a **mandatory safety snapshot** before a risky
mutation: a full import, a guild configuration import, a profile reset, and a
profile deletion.

Refusing those snapshots would have left the calling operation without its
recovery point, which would make the data path less safe, not more. Those calls
now pass `{ internal = true }`, which exempts them from the gate.

A user-requested backup is still gated.

## Design decision: the gate is one function

`FeatureRegistry.RequireEnabled` is the single enforcement gate.
`Policy.RequireModuleEnabled` delegates to it and maps the registry's
`FEATURE_*` reason codes onto the established `MODULE_DISABLED_*` codes, so
that every existing caller and its tests keep their contract unchanged.

## Phases

1. **Catalogue.** Extend the canonical definitions with the classified set,
   descriptions, and categories. Reclassify any feature the accounting path
   depends on.
2. **Storage.** Implement the sparse overlay, the effective-state resolver,
   the local strictness split, and the tolerant remote path.
3. **Registry.** Implement the public API, the effective-state resolver, the
   dependency graph, patch validation, the preview, compatibility, and
   diagnostics.
4. **Enforcement.** Route every optional feature entry point through the gate.
   Exempt the mandatory safety snapshots.
5. **Interface.** Extend the officer Modules page with the category,
   description, and consequences, and replace the hardcoded dependent cascade
   with the canonical dependent set.
6. **Documentation and validation.** Write the four developer documents and
   the Spec Kit artifacts, then run the full suite.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| The catalogue change invalidates existing records | The sparse overlay keeps the stored map and its hash unchanged. Verified by the larger-catalogue test. |
| A new dependency edge is missed | Edges are verified against the code, and the interface cascade reads the canonical dependent set rather than a hardcoded list. |
| A required service is misclassified as optional | Every classification is traced to a code reference. `rankRules` was corrected this way. |
| The gate blocks a safety-critical path | The backup gate exempts internal safety snapshots, verified by the backup, import, and restore suites. |
| The registry becomes a dependency of the accounting path | The registry is a configuration boundary. A test asserts that the ledger does not reference it. |

## Out of scope

- New features. This work classifies and governs the features that exist.
- The canonical accounting mechanisms and the RF-0012 locks.
- The `OfficerUI.lua:3632` defect, which is handled separately.
- Publishing, deploying, or changing the TOC version.
