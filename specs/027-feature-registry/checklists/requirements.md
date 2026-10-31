# Requirements Checklist: Centralized Feature Registry

**Feature Branch**: `027-feature-registry`

**Status**: Complete

All items are checked. Each checked item has the evidence named beside it.

## Catalogue

- [x] **R01** Exactly one canonical catalogue exists, and the registry reads
  it rather than duplicating it.
  *Evidence*: `CORE_MODULE_DEFINITIONS` and `MODULE_DEFINITIONS` in
  `src/modules/OperationalPolicy.lua`; `FeatureRegistry.definitions()` reads
  them. The test "exposes every core and optional feature from the canonical
  catalogue" asserts the two counts are equal.
- [x] **R02** Every feature has a key, a label, a description, and a category.
  *Evidence*: the test "reports a description and a category for every
  feature".
- [x] **R03** Required services are always enabled and expose no toggle.
  *Evidence*: the test "keeps required features enabled and refuses to
  configure them".
- [x] **R04** Every optional feature is enabled by default.
  *Evidence*: `defaultModules()`; the test "treats an absent policy decision
  as the catalogue default".
- [x] **R05** A feature that the canonical accounting path depends on is
  classified as a required service.
  *Evidence*: `rankRules` is in `CORE_MODULE_DEFINITIONS`; the ledger
  resolves the expected allocation from it.

## Effective state

- [x] **R06** The precedence is required, unknown, dependency, policy.
  *Evidence*: `FeatureRegistry.resolve`; the three reason-code tests.
- [x] **R07** An unknown feature fails closed.
  *Evidence*: the test "fails closed for an unknown feature identifier".
- [x] **R08** The reason code names the blocking dependency.
  *Evidence*: `state.dependency` and `state.dependencyReasonCode`; the test
  "reports a dependency-disabled feature with the dependency reason code".

## Dependencies

- [x] **R09** Every declared edge is verified against the code.
  *Evidence*: the "Verified dependencies" section of
  `docs/developer/feature-dependencies.md`, including the two rejected
  candidates.
- [x] **R10** A dependent cannot be enabled while its dependency is off.
  *Evidence*: `validateModuleDependencies`; the test "reports a
  dependency-disabled feature with the dependency reason code".
- [x] **R11** A dependency cannot be disabled while an active dependent is
  enabled, and both may be changed together.
  *Evidence*: the tests "refuses to disable a feature while an active
  dependent is enabled" and "allows disabling a feature once its dependents
  are disabled".
- [x] **R12** The dependency rule is a local write constraint and is not
  applied to record shape validation.
  *Evidence*: the test "keeps a record produced with a larger catalogue valid
  on an older catalogue".

## Persistence

- [x] **R13** The overlay holds only the explicit decisions.
  *Evidence*: the test "stores only the explicit decisions and keeps the
  record hash stable".
- [x] **R14** Growing the catalogue does not change an existing record's
  content hash and needs no migration.
  *Evidence*: the sparse overlay design; `research.md` R2 and R3.
- [x] **R15** A local patch naming an unknown feature is refused.
  *Evidence*: `validateLocalModulePatch`; the existing test "denies unknown
  module keys".
- [x] **R16** A remote record carrying an unknown feature is accepted and the
  key is retained.
  *Evidence*: the test "keeps a record produced with a larger catalogue valid
  on an older catalogue".
- [x] **R17** An explicit decision survives a reload.
  *Evidence*: the test "reloads a persisted sparse overlay without losing the
  explicit decision".
- [x] **R18** Disabling a feature does not delete its data.
  *Evidence*: the existing test "denies unknown module keys and preserves
  disabled module data for re-enable".

## Authority

- [x] **R19** Only the Guild Master or an authorized policy writer may change
  the configuration.
  *Evidence*: the existing module management authority tests.
- [x] **R20** Authority fails closed when it cannot be verified.
  *Evidence*: `writerAuthorized` returns `ROSTER_UNAVAILABLE` and the related
  codes.
- [x] **R21** The verified authority must be the local player.
  *Evidence*: `requireLocalActor`; the existing authority tests.

## Synchronization

- [x] **R22** The configuration travels in the existing canonical
  `OPERATIONAL_POLICY` entity, with no parallel mechanism.
  *Evidence*: `docs/developer/feature-sync-protocol.md`; the existing
  operational policy chain tests.
- [x] **R23** Sender authority is verified at acceptance.
  *Evidence*: the existing test "accepts an authorized officer record but
  rejects a member and local settings as authority".
- [x] **R24** Every change is audited with its per-feature effective
  transition.
  *Evidence*: `audit.moduleChanges`; the test "exposes the configuration
  change history from the policy audit log".

## Enforcement

- [x] **R25** There is one enforcement gate.
  *Evidence*: `FeatureRegistry.RequireEnabled`;
  `Policy.RequireModuleEnabled` delegates to it.
- [x] **R26** Every optional feature entry point passes through the gate.
  *Evidence*: the enforcement coverage matrix in `traceability.md`.
- [x] **R27** The established `MODULE_DISABLED_*` reason codes are preserved.
  *Evidence*: the existing module management tests still assert
  `MODULE_DISABLED_REQUESTS` and `MODULE_DISABLED_PRE_DIBS`.
- [x] **R28** A mandatory safety snapshot survives the backup gate.
  *Evidence*: `Backup.Create` `options.internal`; the backup, import, and
  restore suites.
- [x] **R29** The registry is not a dependency of the canonical accounting
  path.
  *Evidence*: the test "keeps the production accounting path independent of
  the registry".

## Interface

- [x] **R30** The Modules page shows the category, the description, the
  dependency, and the consequences.
  *Evidence*: the Modules page rendering in `src/ui/OfficerUI.lua`.
- [x] **R31** The interface delegates every mutation to the policy service.
  *Evidence*: the existing test "keeps checkbox changes local until Save
  delegates to the policy service".
- [x] **R32** The draft is preserved when a save fails.
  *Evidence*: the existing test "preserves the draft when Save fails and
  disables only dependent modules".
- [x] **R33** The dependent cascade uses the canonical dependent set.
  *Evidence*: `Dibs.FeatureRegistry.GetDependents` in the Modules page.

## Diagnostics

- [x] **R34** The diagnostic report has one line per feature.
  *Evidence*: the test "produces a diagnostic line for every feature".
- [x] **R35** The change history is read from the canonical audit log.
  *Evidence*: `FeatureRegistry.GetChangeHistory` reads
  `OperationalPolicy.GetState().auditLog`.

## Validation

- [x] **R36** The full Lua suite passes with no regression.
  *Evidence*: 1567 passed, 0 failed.
- [x] **R37** The application sources compile.
  *Evidence*: the Lua compile check over every application file, 0 failures.
- [x] **R38** The protected libraries are intact.
  *Evidence*: 77 files, no `libs` issue reported by the guard, no `git status`
  entry under `src/libs`.
- [x] **R39** The RF-0012 locks are unchanged.
  *Evidence*: `Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED = false` in
  `src/Core.lua` and `DISPUTE_OPERATION_WRITES_ENABLED = false` in
  `src/modules/Ledger.lua`.
- [x] **R40** The documentation is regenerated and consistent.
  *Evidence*: `Generate-DibsDocs.ps1 -Check` returns `RESULT: PASS`; the
  cross-version harness reports 8/8 SHA-256 matches.
- [x] **R41** The audit documentation is consistent.
  *Evidence*: `validate_audit.py` reports 47 tags, 47 sheets, 0 warnings,
  0 errors.
