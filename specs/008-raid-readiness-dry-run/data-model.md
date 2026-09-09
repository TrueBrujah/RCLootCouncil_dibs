# Data Model: Raid Readiness and Dry-Run Center

## Readiness Check

```text
checkId, actor, createdAt, observedMode, status, freshnessMarker,
configurationFingerprint, probes[], safeSummary, officerDetails
```

Status is `Ready`, `Degraded`, `Blocked`, or `Unavailable`.

## Capability Probe

```text
probeId, name, required, state(pass|fail|skipped|unavailable),
reasonCode, impact, remediation, authority, observedAt
```

Probes include season/policy, authority, installation, RCLootCouncil, Master Looter,
response, award identity, synchronization, and local services.

## Dry-Run Case and Result

```text
caseId, item, winner, responseText, finalStatus, sessionIdentity,
difficulty?, mode?, createdAt, actor

resultId, caseId, outcome, reasonCodes[], validation,
wouldConsumeDib, simulatedAt, boundedDiagnosticRef?
```

No production transaction or idempotency record is attached.

## Readiness Report

```text
reportId, scope(safe|officer), checkRef?, dryRunRef?, versions,
mode, statuses, reasonCodes, testCount, createdAt, actor?
```

Safe reports exclude live/private loot state; Officer reports remain guild-scoped.

## Safety Gate

Read-only decision used by the live award path: whether current award provenance is
verifiable and consumption may proceed. It never grants GM/Officer administration.
