# Feature Dependencies

The dependency graph of the canonical feature catalogue. The source of truth
is the `requires` field of each definition in
[`src/modules/OperationalPolicy.lua`](../../src/modules/OperationalPolicy.lua).

## Graph

```
rclootcouncil
└── historicalReconciliation
```

That is the complete set of edges. Every other feature stands alone.

## Rules

### A dependent cannot be enabled while its dependency is off

Enabling `historicalReconciliation` while `rclootcouncil` is disabled is
refused with `MODULE_DEPENDENCY_RCLootCouncil`.

The rule is evaluated against the **effective** state, which overlays the
guild's explicit decisions on the catalogue defaults. A feature that the guild
never decided uses its default.

### A dependency cannot be disabled while an active dependent is enabled

Disabling `rclootcouncil` while `historicalReconciliation` is enabled is
refused with `MODULE_DEPENDENCY_RCLootCouncil`.

The guild can disable both in a single change. The change is applied in one
policy revision, and the audit trail records the effective transition.

### The dependency rule is a local write constraint

The rule is enforced by `Policy.ChangeModules`, the local write path. It is
deliberately **not** part of record shape validation.

A record that arrives from a peer is validated for shape only. If it carries a
module map that this client's catalogue cannot satisfy, the record is still
accepted, because rejecting it would break the parent chain and leave the
guild permanently out of sync. The effective state of a dependency-disabled
feature is resolved locally by the registry instead.

This split is what allows two clients with different catalogues to coexist in
one guild.

## Consequence handling

When an officer disables a feature in the interface, every feature that
depends on it is disabled in the same draft. The dependent set comes from
`Dibs.FeatureRegistry.GetDependents`, so a new dependency edge is honoured
without changing the interface code.

The officer interface also shows, under each feature, the list of features
that would be turned off as a consequence. Disabling a feature is therefore
never a silent side effect.

## Verified dependencies

Every dependency edge was verified against the real code. An edge is only
declared when the dependent module actually calls into the dependency.

| Dependent | Dependency | Evidence |
| --- | --- | --- |
| `historicalReconciliation` | `rclootcouncil` | `src/integrations/RCLootCouncil.lua` gates the historical reconciliation path on the `rclootcouncil` module. |

Two candidate edges were examined and **rejected** because the code does not
support them:

| Candidate | Verdict | Reason |
| --- | --- | --- |
| `independentRaid` → `rclootcouncil` | Rejected | `src/modules/IndependentRaid.lua` contains no call into `Dibs.RCLootCouncil`. The dependency was an assumption, not a fact. |
| `raidPrompts` → `encounterJournal` | Rejected | `src/modules/RaidPrompts.lua` calls `Dibs.EncounterJournal.OpenForRaidContext` only after a prompt is accepted, and the call is already guarded by a nil check. The journal is not a required precondition for the prompt feature. |

## Required services are not dependency edges

A required service is always enabled, so it can never be the blocked side of a
dependency edge. `rankRules` in particular is required because the canonical
allocation path in `src/modules/Ledger.lua` resolves the expected allocation
from it before any award is validated. It is listed as a required service
rather than as an optional feature with a dependency.

## Related documents

- [Feature catalogue](feature-catalog.md)
- [Feature configuration](feature-configuration.md)
