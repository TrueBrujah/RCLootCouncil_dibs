# Contract: Authorization

`Permissions.Evaluate(actionId, actor)` selects exactly one authority source per call.

## Source Selection

- If RC availability is `absent`: use standalone policy.
- If RC availability is `operational` or `degraded`: evaluate through RC adapter path.
- If RC decision is malformed/unavailable while RC is present: deny (fail closed).

## Guarantees

- RC denial is final for that request; no standalone fallback.
- Standalone allow/deny applies only when RC is absent.
- Result includes stable `reasonCode` and `diagnostic`.

## Required deny reason families

- `INVALID_ACTION`
- `INVALID_ACTOR`
- `RC_AUTHORITY_UNVERIFIABLE`
- `RC_NOT_MASTER_LOOTER`
- `RC_STATE_CHANGED`
- `STANDALONE_NOT_AUTHORIZED`
- `GUILD_MASTER_REQUIRED`
