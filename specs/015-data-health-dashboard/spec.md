# Feature Specification: Data Health Dashboard

**Feature Branch**: `015-data-health-dashboard`
**Created**: 2026-09-22
**Status**: Implemented pending Retail validation
**Source**: Etape 2 in `docs/PUBLIC-ROADMAP.md`

## Goal

Provide an Officer/GM page that explains the current operational health of Dibs without requiring SavedVariables inspection. The page must identify version, persistence/migration state, readiness, RCLootCouncil capability, synchronization, backups, and bounded remediation context.

## Requirements

- The dashboard MUST be read-only and derive its report from existing services.
- The dashboard MUST be available only to a verified GM or Officer.
- The report MUST expose stable check identifiers, state, reason, and detail.
- The report MUST distinguish `READY`, `DEGRADED`, `BLOCKED`, `UNAVAILABLE`, and `DENIED`.
- The report MUST not expose ledger rows, player names, private evidence, raw sync payloads, or executable actions.
- Missing RCLootCouncil or synchronization capability MUST remain explicit and must not imply live integration readiness.
- Persistence recovery and read-only states MUST be visible as blocking/degraded health.
- The page MUST preserve the existing debug report and Officer lifecycle behavior.
- No SavedVariables, SyncV2, ledger, authority, or RCLootCouncil mutation is allowed.

## Acceptance

1. An authorized Officer sees version, schema, persistence, readiness, RCLootCouncil, sync, and backup checks.
2. A normal player receives no administrative health report.
3. An absent/degraded optional capability is shown explicitly.
4. A future/read-only persistence state is blocking and cannot be presented as healthy.
5. Reopening Diagnostics recomputes current state and does not persist a completion flag.
6. Automated tests pass and Retail protected-frame/combat validation remains a separate gate.
