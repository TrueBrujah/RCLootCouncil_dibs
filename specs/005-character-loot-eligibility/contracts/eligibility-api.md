# Character Eligibility API Contract

The service is exposed through `Dibs.CharacterEligibility` and is guild-scoped by the
active Dibs SavedVariables bucket.

## Read operations

- `GetPolicy(seasonId, family)` returns a copy of the effective policy.
- `Evaluate(itemContext, playerName, seasonId)` returns `allow`, `warn`, `review`,
  `downgrade`, or `block`, plus a stable reason code and concise explanation.
- `GetAcquisitions(playerName, seasonId, family)` returns only the caller's records,
  unless the caller is a verified GM/Officer.
- `GetRelationshipStatus(playerName)` returns the player's own pending/approved status.

## Protected operations

- `SetPolicy(policy, actor)` requires `eligibility.policy.set`.
- `RecordAcquisition(record, actor)` requires `eligibility.history.add` unless called
  from the validated finalized-award path.
- `ReviewRelationship(requestId, decision, actor)` requires
  `eligibility.relationship.review`.
- `ApproveMainChange(requestId, options, actor)` requires `eligibility.main.review`.
- `CreateProbationException(options, actor)` requires `eligibility.exception.create`.

All mutations validate the active guild, use stable IDs, preserve prior records, and
return an idempotent result when the same award or evidence is delivered again.
