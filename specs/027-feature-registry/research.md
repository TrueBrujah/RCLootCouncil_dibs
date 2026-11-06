# Research: Centralized Feature Registry

Decisions taken during the implementation, with the evidence that motivated
them.

## R1 — The existing module system is the right substrate

**Question**: build a new registry, or extend the existing one?

**Evidence**: `src/modules/OperationalPolicy.lua` already implements a
canonical catalogue (`CORE_MODULE_DEFINITIONS`, `MODULE_DEFINITIONS`), GM and
policy-writer authority verification, revisioned and hashed persistence,
idempotent replay, conflict detection, parent-chain enforcement, and an
officer interface. `src/modules/SyncV2.lua` already synchronizes the
`OPERATIONAL_POLICY` entity with digest, gap recovery, and trusted relay
support.

**Decision**: extend. A second registry would have duplicated the canonical
machinery the constitution requires to stay single-sourced, and would have
created two catalogues that could drift.

## R2 — The catalogue hash hazard is real

**Question**: what happens to a persisted policy record when the catalogue
grows?

**Evidence**: `validateShape` recomputes the canonical hash over
`record.values` and compares it with the stored `contentHash`. The original
`normalizedValues` rebuilt `values.modules` from `defaultModules()` and then
overlaid the patch, so the stored map always contained every catalogue key.
Adding a key to the catalogue therefore changed the stored map and with it the
hash.

**Consequence**: every existing guild record would fail with
`POLICY_HASH_MISMATCH` on load, breaking the parent chain.

**Decision**: store a sparse overlay. See `plan.md`, "The sparse overlay".

## R3 — A schema bump is not an acceptable alternative

**Question**: would bumping `SCHEMA` be simpler?

**Evidence**: `ensureState` resets the status to `POLICY_UNINITIALIZED` when
the schema differs. The officer interface only offers the governance
bootstrap when the governance is not initialized, and the module management
tests assert the `POLICY_UNINITIALIZED` state directly.

**Consequence**: a schema bump forces every guild to re-adopt its policy and
re-run the governance bootstrap. That is a much larger operational cost than
the sparse overlay, and it discards the revision chain.

**Decision**: keep `SCHEMA = 1`. The record *format* did not change — the
stored map is still a map of string keys to booleans. The catalogue is a
separate concern, published through `CATALOGUE_VERSION`.

## R4 — The dependency rule must not gate record validation

**Question**: where should the dependency rule be applied?

**Evidence**: the rule as originally written lived in `normalizedValues`,
which is called both by `createRecord` on the local write path and by
`validateShape` on the remote acceptance path.

**Consequence**: a record from a peer whose catalogue differs could be
rejected outright, which breaks the parent chain and leaves the guild
permanently behind.

**Decision**: the rule is a local write constraint. `validateModuleDependencies`
is called from `Policy.ChangeModules` only. `normalizedValues` validates
shape only.

## R5 — Unknown remote keys must be retained

**Question**: should a record carrying an unknown feature be rejected?

**Evidence**: the canonical hash is computed over the stored map. `mergeValues`
replaces `values.modules` wholesale with the patch, which would drop any
unknown key and change the hash of the new record.

**Consequence**: dropping the key breaks the chain for every peer. Rejecting
the record breaks the chain too.

**Decision**: retain unknown keys in `normalizedValues`, and merge the module
map key by key in `mergeValues` so a local revision carries the unknown key
forward unchanged. Unknown keys are rejected only on the local write path,
through `validateLocalModulePatch`.

## R6 — `rankRules` is a required service, not an optional feature

**Question**: is `rankRules` safely optional?

**Evidence**: `src/modules/Ledger.lua` calls
`Dibs.RankRules.GetAllocationForPlayer` to compute the expected allocation
and refuses the operation with `RANK_RULE_INVALID` when the result is not a
finite non-negative integer. The allocation is part of the operation basis
recorded in the audit trail.

**Consequence**: disabling `rankRules` would make every allocation
unverifiable and would silently break the canonical accounting path.

**Decision**: reclassify `rankRules` as a required core service.

## R7 — Two candidate dependency edges were rejected

**Question**: should `independentRaid` depend on `rclootcouncil`, and should
`raidPrompts` depend on `encounterJournal`?

**Evidence**:

- `src/modules/IndependentRaid.lua` contains no reference to
  `Dibs.RCLootCouncil`. Its declared dependencies are `Dibs.Permissions` and
  `Dibs.Ledger`. The module header mentions "integration with vanilla
  RCLootCouncil voting", but the code does not call it.
- `src/modules/RaidPrompts.lua` calls
  `Dibs.EncounterJournal.OpenForRaidContext` only after a prompt is accepted,
  and the call is already guarded by a nil check that returns
  `JOURNAL_UNAVAILABLE`. The journal is not a precondition for the prompt
  feature.

**Decision**: neither edge is declared. The dependency graph contains exactly
one edge, `historicalReconciliation` → `rclootcouncil`, which is enforced in
`src/integrations/RCLootCouncil.lua`.

**Lesson**: the module header comment is not evidence of a dependency. The
call site is.

## R8 — A required service can never be the blocked side of an edge

**Question**: can a required service be a dependency target?

**Decision**: no. A required service is always enabled, so the dependency
rule can never block on it. `rankRules` is therefore a required service
rather than an optional feature with a dependency.

## R9 — Safety snapshots must survive the backup gate

**Question**: should `Backup.Create` be gated by the `backup` feature?

**Evidence**: four callers create a **mandatory** safety snapshot before a
risky mutation:

| Caller | Location |
|---|---|
| Full import | `src/modules/ImportExport.lua`, `before-import:` |
| Guild configuration import | `src/modules/ImportExport.lua`, `before-config-import:` |
| Profile reset | `src/modules/Profiles.lua`, `before-profile-reset` |
| Profile deletion | `src/modules/Profiles.lua`, `before-profile-delete` |

`Backup.Restore` also creates one before restoring.

**Consequence**: gating those calls would leave the operation without its
recovery point. If the import then failed, there would be no snapshot to
recover from. That is strictly less safe.

**Decision**: `Backup.Create` accepts `options.internal = true`, which
exempts the call from the gate. A user-requested backup remains gated.

## R10 — The registry must not become an accounting dependency

**Question**: does making the registry the single gate put it on the canonical
accounting path?

**Decision**: no. The registry is a configuration boundary. The canonical
ledger, governance, and synchronization modules do not reference it. A test
asserts that `Dibs.Ledger` exposes no registry reference, so a future change
that introduced one would fail.

## R11 - The registry reuses the established reason codes

**Question**: should the registry introduce its own reason codes at the public
`Policy.RequireModuleEnabled` boundary?

**Evidence**: `module_management_spec.lua` asserts
`MODULE_DISABLED_REQUESTS`, `MODULE_DISABLED_PRE_DIBS`, and
`MODULE_DEPENDENCY_RCLootCouncil` verbatim, and the officer interface renders
the reason code to the user.

**Decision**: the registry uses its own `FEATURE_*` vocabulary internally.
`Policy.RequireModuleEnabled` maps the result onto the established
`MODULE_DISABLED_*` codes, so every existing caller, test, and user-facing
message is unchanged.

The one exception is `MODULE_DEPENDENCY_RCLootCouncil`, whose mixed case is
not derivable from the dependency key. It is preserved through an explicit
mapping table.

## R12 - The officer cascade was hardcoded

**Question**: how does the interface disable a feature's dependents?

**Evidence**: `src/ui/OfficerUI.lua` contained a single hardcoded cascade:
turning off `rclootcouncil` also turned off `historicalReconciliation`. A
second dependency edge would have been silently ignored.

**Decision**: the cascade now reads `Dibs.FeatureRegistry.GetDependents`, so
a new edge is honoured without touching the interface. The interface also
lists the consequences under each feature, so a disable is never silent.

## R13 - The catalogue count assertions had to become derived

**Question**: why were two existing test assertions changed?

**Evidence**: `module_management_spec.lua` asserted `assert_equal(6, enabled)`
for the number of enabled optional checkboxes, and `assert_equal(7, #core)` for
the number of required services. Both are catalogue sizes that changed when
the catalogue was completed and when `rankRules` was reclassified.

**Decision**: both assertions now derive the expected value from the
canonical catalogue. The tests still assert the same property — every
optional feature renders one enabled control, and every core service is
always enabled — but they no longer need to be edited when the catalogue
changes. This is a stronger assertion, not a weaker one.
