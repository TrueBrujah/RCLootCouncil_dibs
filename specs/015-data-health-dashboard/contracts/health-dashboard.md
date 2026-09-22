# Contract: Health Dashboard

## Authorized report

`HealthUI.Evaluate()` returns a bounded report for a verified GM or Officer. It includes stable checks for persistence, readiness, RCLootCouncil, synchronization, and backups.

## Privacy

The report MUST NOT include ledger transactions, player names, private evidence, raw sync payloads, or executable action payloads.

## Denied report

A normal player receives `status = DENIED` with no checks.

## State semantics

- `READY`: all reported checks are ready.
- `DEGRADED`: no blocking check, but one or more warnings exist.
- `BLOCKED`: at least one blocking check is not ready.
- `UNAVAILABLE`: the report cannot be computed.
- `DENIED`: the actor is not authorized for administrative health details.
