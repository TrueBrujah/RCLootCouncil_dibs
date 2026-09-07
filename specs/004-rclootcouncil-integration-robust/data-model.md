# Data Model: Robust RCLootCouncil Integration

## Integration Capability Snapshot

Runtime-only state describing what the current client has verified.

| Field | Meaning | Validation |
|---|---|---|
| `state` | `absent`, `operational`, `degraded`, or `unsupported` | Derived from observed capabilities; never claimed by a payload |
| `checkedAt` | Last capability evaluation time | Local timestamp |
| `addonLoaded` | Whether RCLootCouncil is loaded | Derived from the client |
| `capabilities` | Named supported surfaces | Each capability requires a callable/validating probe |
| `reasonCode` | Stable explanation for degraded/unsupported state | Localized only at presentation |
| `observedVersion` | Optional diagnostic version label | Informational; never authorizes an action |

Required capabilities for an operational award path are: RCLootCouncil instance discovery,
current Master Looter identity, finalized-award callback registration, stable item/winner
identity extraction, and response validation. A missing capability downgrades the state.

## Master Looter Identity

Runtime identity used for one protected award evaluation.

| Field | Meaning | Validation |
|---|---|---|
| `guid` | Canonical player GUID when supplied | Must match the local client for callback finalization |
| `nameRealm` | Normalized `Name-Realm` identity | Fallback only when a GUID is unavailable and unique |
| `observedAt` | Time identity was read | Re-read for every protected action |
| `sessionId` | Optional current loot-session identity | Must be stable for the current award |

The identity is not a Dibs admin identity. A Master Looter who is not a guild GM/officer may
only supply the provenance for a qualifying finalized award.

## Finalized Award Provenance

An immutable normalized event accepted by the adapter before it reaches protected accounting.

| Field | Meaning | Validation |
|---|---|---|
| `awardRef` | Stable idempotency identity | Required; history ID preferred, unique session fallback otherwise |
| `historyId` | RCLootCouncil immutable history identifier | Preferred when available |
| `sessionId` | Loot/session identity | Required for deterministic fallback |
| `awardIndex` | Position within the session when available | Bounded non-negative integer for fallback |
| `itemID` | Stable item identity | Required positive integer |
| `itemLink` | Display link | Optional; never used as sole identity |
| `winnerId` | Canonical winner identity | Required and uniquely resolvable |
| `responseCode` | Canonical response | Must be `DIB` |
| `sourceStatus` | Finalization status | Must not be `test_mode`; must be an accepted finalized status |
| `source` | `rclootcouncil` | Fixed for this contract |
| `observedAt` | Local receipt time | Required for diagnostics/audit |
| `responseValidated` | Adapter validation marker | Set only after all source checks pass |

An award with missing or ambiguous `awardRef`, item, winner, response, or provenance is
ignored or rejected without a ledger mutation.

## Award Accounting Record

The ledger transaction created by the protected finalization path for one award.

| Field | Meaning | Validation |
|---|---|---|
| `transactionId` | Dibs immutable transaction identity | Unique in the append-only ledger |
| `awardRef` | Link to finalized award provenance | Unique for a consumption |
| `playerId` | Award winner | Matches the validated winner |
| `itemID` | Awarded item | Matches the validated item |
| `seasonId` | Dibs season used for eligibility | Existing season |
| `amount` | Rule-defined debit | Positive consumption amount; finite and bounded |
| `actorId` | Verified local ML provenance | Matches current local Master Looter |
| `source` | `rclootcouncil` | Fixed for automatic award debit |
| `reason` | Audit explanation | Includes finalized award context |
| `createdAt` | Transaction time | Required timestamp |

When `awardRef` already exists, the protected action returns the existing accounting result
and appends no transaction.

## Adapter Hook State

Runtime-only state that prevents duplicate or recursive integration hooks.

| Field | Meaning | Validation |
|---|---|---|
| `ownerKey` | Identity of an RCLootCouncil frame/module | Required for each hook marker |
| `hookKind` | Loot, voting, options, or award callback | Closed set |
| `installed` | Whether the hook was installed | Set only after a successful installation |
| `retryCount` | Bounded retry count | Cannot exceed configured maximum |
| `lastErrorCode` | Diagnostic installation failure | Local diagnostic only |
| `lastCheckedAt` | Last lifecycle check | Runtime timestamp |

Hook state is never transmitted or used as authority. It may be discarded on reload.

## Compatibility Record

Documentation and diagnostics describing the supported RCLootCouncil surface for a release.

| Field | Meaning | Validation |
|---|---|---|
| `supportedSurface` | Named capabilities required by the adapter | Must match contract tests |
| `testedBuild` | RCLootCouncil and WoW client build used for validation | Recorded in release evidence |
| `fallbackBehavior` | Standalone/degraded behavior | Must preserve Dibs core |
| `knownLimitations` | Unsupported metadata or UI surfaces | Must be documented before release |
| `validatedOn` | Validation date | ISO date |

## State Transitions

```text
absent ------------------+
                         v
                   capability check
                         |
             +-----------+-----------+
             v           v           v
        operational   degraded   unsupported
             |           |           |
             +------- recheck -----+
```

Only `operational` permits automatic RCLootCouncil award accounting. `degraded` and
`unsupported` retain Standalone Dibs behavior but reject integration finalization.

## Ownership and Privacy

- Dibs owns the accounting record and all Dibs SavedVariables.
- RCLootCouncil owns loot sessions, candidates, votes, responses, and history.
- Capability, hook, and current ML state are local runtime data.
- Cross-raid synchronization may carry Dibs accounting references but never live RC session
  content.
- Ordinary players receive their own Dibs views only; officer data and diagnostics remain
  protected.
