# Tasks: Centralized Feature Registry

**Feature Branch**: `027-feature-registry`

**Status**: Implemented

All tasks below are complete. Each task lists the evidence that demonstrates it.

## Phase 1 — Inventory and contracts

- [x] **T001** Inventory every application module and classify it as required
  core, optional, or conditional dependency.
  *Evidence*: the catalogue in `src/modules/OperationalPolicy.lua`; the
  classification table in `docs/developer/feature-catalog.md`.

- [x] **T002** Audit the existing module system and record the gap between the
  declared catalogue and the enforced state.
  *Evidence*: the enforcement coverage matrix in
  `specs/027-feature-registry/traceability.md`.

- [x] **T003** Verify every candidate dependency edge against the real code
  rather than assuming it.
  *Evidence*: the "Verified dependencies" section in
  `docs/developer/feature-dependencies.md`, which records two candidate edges
  that were examined and rejected.

## Phase 2 — Catalogue and registry

- [x] **T004** Extend the canonical catalogue with the full classified set,
  including a description and a category for every feature.
  *Evidence*: `CORE_MODULE_DEFINITIONS` and `MODULE_DEFINITIONS` in
  `src/modules/OperationalPolicy.lua`.

- [x] **T005** Reclassify any feature the canonical accounting path depends on
  as a required service.
  *Evidence*: `rankRules` moved to the core set; `src/modules/Ledger.lua`
  resolves the expected allocation from it before validating an award.

- [x] **T006** Implement the sparse overlay storage so that growing the
  catalogue does not change the content hash of an existing record.
  *Evidence*: `effectiveModules` and the `modules` branch of
  `normalizedValues`; the test "stores only the explicit decisions and keeps
  the record hash stable".

- [x] **T007** Implement the tolerant remote path: retain unknown keys, reject
  unknown local patches.
  *Evidence*: `validateLocalModulePatch` and the key-by-key `mergeValues`; the
  test "keeps a record produced with a larger catalogue valid on an older
  catalogue".

- [x] **T008** Implement the registry: listing, definition lookup, effective
  state, the enforcement gate, the dependency graph, patch validation, the
  preview, compatibility, diagnostics, and the change history.
  *Evidence*: `src/modules/FeatureRegistry.lua`.

## Phase 3 — Enforcement

- [x] **T009** Make the registry the single enforcement gate, keeping the
  established `MODULE_DISABLED_*` reason codes.
  *Evidence*: `Policy.RequireModuleEnabled` delegates to the registry.

- [x] **T010** Enforce the gate on every optional feature entry point.
  *Evidence*: the enforcement coverage matrix in the traceability document.

- [x] **T011** Exempt mandatory safety snapshots from the backup gate so that
  import, restore, and profile operations keep their recovery point.
  *Evidence*: `Backup.Create` `options.internal`; the callers in
  `ImportExport` and `Profiles`.

- [x] **T012** Fix the officer interface cascade, which was hardcoded to a
  single dependent, so that it uses the canonical dependent set.
  *Evidence*: `src/ui/OfficerUI.lua`; the test "preserves the draft when Save
  fails and disables only dependent modules".

## Phase 4 — Interface

- [x] **T013** Show the category, description, dependency, and consequences of
  each feature in the officer Modules page.
  *Evidence*: the Modules page rendering in `src/ui/OfficerUI.lua`.

- [x] **T014** Keep the interface free of direct SavedVariables writes and
  preserve the draft when a save fails.
  *Evidence*: the existing module management tests.

## Phase 5 — Documentation and validation

- [x] **T015** Write the feature catalogue, dependency, configuration, and
  synchronization documents.
  *Evidence*: `docs/developer/feature-catalog.md`,
  `feature-dependencies.md`, `feature-configuration.md`,
  `feature-sync-protocol.md`.

- [x] **T016** Write the Spec Kit artifacts with a full traceability matrix.
  *Evidence*: `specs/027-feature-registry/`.

- [x] **T017** Run the full Lua suite and confirm that no existing behaviour
  regressed.
  *Evidence*: the validation record below.

## Validation record

| Check | Result |
|---|---|
| `feature_registry_spec.lua` | 26 passed, 0 failed |
| `module_management_spec.lua` | 18 passed, 0 failed |
| `operational_policy_spec.lua` | 9 passed, 0 failed |
| Affected suites (backup, import, profiles, readiness, prompts, loot rules, great vault) | 174 passed, 0 failed |
| Full Lua suite | See the final report; 0 failures across every batch |
| TOC load order | `modules/FeatureRegistry.lua` added after `modules/OperationalPolicy.lua` in the TOC and in the test loader |
| Protected libraries | 77 entries, untouched |
| RF-0012 locks | `CANONICAL_OPERATIONS_RELEASE_ENABLED = false`, `DISPUTE_OPERATION_WRITES_ENABLED = false`, unchanged |
