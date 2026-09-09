# Data Model: RCLootCouncil History Reconciliation

## Reconciliation Session

```text
id, guildScope, targetSeason, historyScope, dateFrom, dateTo,
aliases, reviewMode, createdAt, createdBy, status, previewCounts
```

The session is bounded and never itself changes the ledger.

## Response Alias Policy

```text
aliasId, guildScope, seasonScope, label, normalizedLabel,
responseIdentity?, createdAt, createdBy, active, changeReason
```

Only active explicit aliases participate in guided classification.

## History Candidate

```text
candidateId, sessionId, source, historyId?, awardRef?, sessionRef?,
itemId?, itemLink?, winner?, awardTime?, difficulty?, responseText?,
responseIdentity?, finalStatus, classification, reason, evidenceConfidence
```

`classification` is one of `eligible`, `already_accounted`, `ambiguous`, `rejected`, or
`unsupported`. Source fields are read-only copies of observed RCLootCouncil data.

## Historical Dibs Evidence

```text
evidenceId, candidateId, targetSeason, sourceRefs, item, winner,
response, status, originalAwardTime, importedAt, importedBy,
aliasUsed, reviewOutcome, confirmationReason
```

Unavailable fields are explicit values, not omitted guesses.

## Reconciliation Decision

```text
decisionId, candidateId, actor, time, previousState, outcome,
reason, manualAcknowledgement, transactionRef?
```

Decisions are append-only and link to a historical transaction when accepted.

## Historical Dibs Transaction

An existing append-only Dibs consumption with `transactionRef`, target season, and
`evidenceId`. It uses the normal balance and authorization rules and is deduplicated by
stable award identity or approved evidence link.
