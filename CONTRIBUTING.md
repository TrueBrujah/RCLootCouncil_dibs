# Contributing

This project uses Spec Kit and spec-driven development.

## Before coding

1. Read `.specify/memory/constitution.md`.
2. Identify the active feature under `specs/`.
3. Do not implement behavior that is absent from the active specification.
4. Prefer a new bounded feature spec over silently expanding an existing feature.

## Feature workflow

```text
/speckit.specify
/speckit.clarify
/speckit.plan
/speckit.tasks
/speckit.analyze
/speckit.implement
/speckit.converge
```

## Architecture constraints

- Dibs core must not depend on RCLootCouncil.
- RCLootCouncil and Encounter Journal code are adapters.
- Ledger history is append-only.
- Live loot-session information never crosses raid groups.
- No private guild or personal data in public test fixtures.

## Validation and documentation

Use the [developer contribution guide](docs/developer/contributing.md) and
[targeted testing instructions](docs/developer/testing.md). On Windows,
explicitly select relevant suites with `DIBS_TEST_FILES` and restore its
previous value afterward.

Behavior changes must update the affected EN/FR Player and GM/Officer guides,
including screenshot inventories, plus a dated changelog note. Documentation-only
changes need document/diff checks, not an addon test run or package build.
Generated references cover source-annotated concepts only; check them with
`.\scripts\Generate-DibsDocs.ps1 -Check` and do not edit the output by hand.
Historical audits are not current certification, and a source version is not
proof that a stable download has been published.
