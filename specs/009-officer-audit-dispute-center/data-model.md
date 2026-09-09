# Data Model: Officer Audit and Dispute Center

## Player Review Request

```text
requestId, guildScope, player, category, note, createdAt,
attachedContext, status, duplicateKey, lastUpdatedAt
```

The request is non-authoritative and may reference only the creating player's context.

## Evidence Link

```text
evidenceId, source(dibs|rclootcouncil|readiness|reconciliation|unknown),
transactionRef?, awardRef?, historyRef?, item?, winner?, response?,
status?, season?, confidence, unavailableFields
```

Evidence is copied/read-only and never guessed.

## Review Reply

```text
replyId, requestId, author(player|officer), boundedText, createdAt
```

Player replies are context, not evidence edits.

## Resolution Decision

```text
decisionId, requestId, actor, time, previousStatus, newStatus,
action, reason, confirmation, affectedTransaction?, linkedEvidence?
```

Every transition is append-only and attributable.

## Compensating Transaction

An append-only Dibs transaction linked to the request and original transaction when a balance
correction is authorized. It is deduplicated by request/evidence/action identity.

## Review Status

`Open`, `Under review`, `Need information`, `Resolved`, and `Rejected` are the visible
lifecycle states; equivalent localized labels must preserve these semantics.
