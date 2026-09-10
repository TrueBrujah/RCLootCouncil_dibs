# Data Model: Character Loot Eligibility and Main/Alt Governance

## Eligibility Policy

```text
policyId, seasonId, family, enabled, matchingScope, difficultyScope,
enforcementOutcome, unknownDataBehavior, completionThreshold,
higherTrackOutcome, tierSetGroupMode, updatedAt, updatedBy
```

`family` is `TOKEN` for Curios or `TOKEN_SET` for class-based Tier Set tokens. Policies
are season-scoped and changes are prospective.

## Loot Acquisition

```text
acquisitionId, seasonId, family, itemID, itemLink, itemName, difficulty,
slot, tokenGroup, classID, upgradeTrack, characterId, characterName,
playerGroupId, source, awardRef, evidenceId, acquiredAt, actorId, reason
```

Only a validated finalized award or an officer-confirmed historical entry can create an
acquisition. `awardRef` and `evidenceId` are idempotency keys.

## Tier Set Group and Round

```text
groupId, seasonId, tokenGroup, eligibleClasses[], participantGroupIds[],
currentRound, memberProgress{}, noNeedMembers{}, updatedAt
```

The active round is the minimum progress among active eligible members. A member with
less progress joins the lowest round until the group catches up.

## Character Relationship

```text
relationshipId, seasonId, guildKey, mainCharacterId, altCharacterId,
playerGroupId, status(pending|approved|rejected|suspended), declaredBy,
reviewedBy, declaredAt, reviewedAt, reason
```

Relationships never contain Battle.net account identifiers. Unapproved declarations do
not affect enforcement.

## Main Change and Probation Exception

```text
changeId, seasonId, playerGroupId, oldMainId, newMainId, effectiveAt,
probationEndsAt, outcome, approverId, reason, status

exceptionId, changeId, scope, awardLimit, expiresAt, reason, approverId, status
```

The default probation is 14 days with no main-spec protected loot. Exceptions are
limited by time or award count and are recorded separately.

## Eligibility Decision

```text
decisionId, seasonId, family, playerGroupId, itemID, outcome,
reasonCode, explanation, policyId, consideredAcquisitions[], createdAt
```

Decisions are read-only evidence for a request or award; they do not mutate the ledger.
