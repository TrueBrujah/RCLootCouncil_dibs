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
