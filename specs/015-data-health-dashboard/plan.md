# Implementation Plan: Data Health Dashboard

**Branch**: `015-data-health-dashboard`

## Architecture

`HealthUI.Evaluate()` composes existing read-only services into a bounded report. `OfficerUI` renders the report in the existing Diagnostics page and keeps the current debug report below it. No authority or persistence boundary moves.

## Delivery slices

1. Projection contract: stable health checks, role gate, privacy bounds, explicit unavailable states.
2. Officer rendering: version/schema summary, check states, technical disclosure, existing Diagnostics preservation.
3. Documentation and validation: quickstart, test plan, implementation evidence, and Retail checklist.

## Risks and controls

- Duplicate business logic: only normalize service outputs; do not reimplement readiness rules.
- Privacy leakage: return status metadata only and assert absence of records/names in contracts.
- False readiness: unavailable, degraded, blocked, and read-only persistence states remain non-ready.
