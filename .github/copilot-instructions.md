# Repository Instructions

## Scope and evidence

- Start with `git status --short` and the latest relevant checkpoint, if available.
  Preserve existing changes; do not commit, publish, or deploy unless requested.
- Follow the [constitution](../.specify/memory/constitution.md) and the applicable
  approved feature under `specs/`. Do not invent business rules or expand feature scope.
  Read the relevant principles and spec sections, not every feature document.
- Reuse evidence only while its revision, paths, assumptions, and environment still
  apply. Search narrowly; read the affected code, callers, tests, and contracts before
  editing. Expand only for a concrete dependency, changed contract, or unexplained failure.
- Make complete, surgical changes using existing helpers. Update directly affected
  documentation. End with concise changed paths, validation results, and blockers;
  do not create planning files unless requested.

## Verified architecture and conventions

- This is a WoW Retail Lua addon. `src/RCLootCouncil_dibs.toc` defines load order:
  embedded libraries, `Core.lua`, locales, modules, integrations, then UI.
  `Core.lua` creates the shared `Dibs` namespace; `Dibs.CoreAPI` is the application facade.
- Domain and persistence live in `src/modules/`; external/framework adapters in
  `src/integrations/`; projections and controllers in `src/ui/`. UI delegates mutations
  through existing services and `ProtectedActions`; it does not own accounting policy.
- Follow [naming conventions](../docs/developer/naming-conventions.md): public module
  functions use PascalCase, private helpers lowerCamelCase, constants UPPER_SNAKE_CASE.
  Preserve existing public and serialized identifiers. Keep user-facing text localized
  through `src/locales/`, with English fallback.
- Consult [architecture](../docs/developer/architecture.md) only as needed. For UI work,
  follow [UI instructions](instructions/ui.instructions.md) and the linked Midnight rules.
  For persistence or sync changes, consult the relevant
  [SavedVariables](../docs/developer/saved-variables.md),
  [sync protocol](../docs/developer/sync-protocol.md), and approved feature contracts.

## Safety boundaries

- Preserve append-only, idempotent accounting and guild/character data isolation.
  Validate actual sender authority at acceptance; unknown authority must fail closed.
  Keep GM/Officer administration separate from verified RCLootCouncil award authority.
- RCLootCouncil is optional; never modify its core or make Dibs accounting depend on it.
  Never synchronize live loot, candidates, votes, or session state across raids.
- Respect WoW protected actions, combat and readiness guards. Developer/test contexts
  must remain isolated from production accounting and traffic.
- Surface failures through existing Dibs diagnostics. Do not commit secrets, personal
  or private guild data, credentials, or private logs; use synthetic fixtures.

## Targeted validation

- Run commands from the repository root. Tests use `tests/run.lua` with WoW/Ace3/RC
  doubles and `*_spec.lua` suites. On Windows, explicitly set `DIBS_TEST_FILES` to the
  relevant semicolon-separated paths; combine related suites in one Fengari run.
  Example for TOC/load-order changes (select other suites for other behavior):

  ```powershell
  $previousTestFiles = $env:DIBS_TEST_FILES
  try {
      $env:DIBS_TEST_FILES = 'tests\integration\toc_load_spec.lua'
      npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
      if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
  } finally {
      $env:DIBS_TEST_FILES = $previousTestFiles
  }
  git diff --check
  ```

- See [testing](../docs/developer/testing.md) for focused slices and full-suite discovery.
  Escalate only when affected shared behavior, failures, specs, or release gates require it.
  Fengari success is not Retail certification; report manual checks separately.
- Documentation-only work: check the diff, links, and document consistency; do not run
  code tests. Follow constitution XIX for change notes and versioning.
- Packaging copies `src/` into the addon package; it is not a compilation or runtime test.
  Do not use deployment as validation. Follow the
  [release process](../docs/developer/releasing.md) only for requested release work.
