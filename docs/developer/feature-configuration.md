# Feature Configuration

How a guild turns a feature on or off, who is allowed to do it, how the
decision is stored, and how it survives a reload.

## Authority

Only the following actors may change the guild feature configuration:

1. The **verified Guild Master** of the current guild.
2. An explicitly authorized **policy writer**, when the canonical governance
   record grants that authority through its `policyWriterRule`.

Authority is verified against the canonical governance record and the live
guild roster. It fails closed: if the roster is unavailable, if the identity
is ambiguous, or if the governance record is missing, the change is refused
with a specific reason code. A change is also refused unless the verified
actor is the local player, so a remote client cannot apply a change on
someone else's behalf.

| Reason code | Meaning |
| --- | --- |
| `GOVERNANCE_UNAVAILABLE` | The canonical governance revision is unavailable. |
| `POLICY_UNINITIALIZED` | The operational policy has not been adopted. |
| `IDENTITY_UNAVAILABLE` | Guild Master authority could not be verified. |
| `ROSTER_UNAVAILABLE` | The guild roster is unavailable; authority fails closed. |
| `UNKNOWN_ROSTER_MEMBER` | The actor is not a resolvable roster member. |
| `AMBIGUOUS_IDENTITY` | The actor maps to more than one roster member. |
| `CURRENT_GUILD_MASTER_REQUIRED` | Only the Guild Master can change guild modules. |
| `POLICY_WRITER_REQUIRED` | The actor is not an authorized policy writer. |
| `LOCAL_ACTOR_REQUIRED` | The verified authority must be the current local player. |
| `MIXED_PROVIDER_REJECTED` | Module management is unavailable while the developer sandbox is active. |

Members of the guild can always **read** the configuration. Only the actors
above can change it.

## Storage

The configuration lives in the canonical operational policy record, under
`values.modules`. The record is revisioned, hashed, and audited exactly like
every other canonical guild record.

### The stored map is a sparse overlay

`values.modules` contains **only the features a guild explicitly decided**.
A key that is absent means "use the catalogue default".

```lua
-- The guild turned requests off and decided nothing else.
values.modules = { requests = false }
```

The effective state is the overlay applied on top of the catalogue defaults:

```lua
effective = defaultModules()   -- every optional feature is enabled by default
for key, enabled in pairs(overlay) do effective[key] = enabled end
```

This design is what makes catalogue growth safe. When a new feature is added
to the catalogue, an existing record keeps its exact stored shape and
therefore its exact canonical content hash. Nothing has to be rewritten, no
record is invalidated, and no guild is forced to re-adopt its policy.

Had the stored map been rewritten with injected defaults, adding a single
feature would have changed the content hash of every existing record and
broken the parent chain for every peer in the guild.

### Local patches are strict

A locally authored change may only reference features this client knows. An
unknown key is refused with `INVALID_MODULE_POLICY`, so a typo or a feature
from a newer catalogue can never be persisted as a guild decision.

### Remote records are tolerant

A record that arrives from a peer may carry features this client does not
know. Those keys are **retained** rather than rejected:

- Retention preserves the record's canonical content hash, so the record
  still passes shape validation here.
- The parent chain is not broken, so the guild does not fall permanently out
  of synchronization.
- The unknown feature is simply not part of this client's catalogue, so it is
  not effective here. The registry reports it as `FEATURE_UNKNOWN`.

When this client later writes a local revision, the unknown key is carried
forward unchanged. Dropping it would change the canonical hash of the new
record and break the chain for every peer.

## Applying a change

```
Dibs.OperationalPolicy.CanChangeModules(actor)      -- may this actor change anything?
Dibs.OperationalPolicy.ChangeModules(patch, actor)    -- apply a change
```

`ChangeModules` performs, in order:

1. Validation that every key in the patch is a known feature with a boolean
   value.
2. Construction of the new sparse overlay.
3. Shape validation of the resulting module map.
4. Dependency validation against the resulting effective state.
5. Creation of a new canonical record with a new revision, a new content
   hash, a parent link to the previous revision, and an author snapshot.
6. Application of the record through the same idempotent replay and conflict
   detection used by every other canonical record.
7. Announcement of the new revision to the guild.

The audit trail records the **effective** transition — what the guild saw
before the change and what it sees after — in `audit.moduleChanges`, with one
entry per feature whose effective state changed.

The change is atomic. A rejected change leaves the current policy revision,
the current content hash, and the current state untouched.

## Reload behaviour

The configuration is part of the guild SavedVariables and is reloaded with the
rest of the canonical state.

- A persisted explicit decision is restored exactly. A guild that turned
  `requests` off still finds it off after a reload.
- A feature the guild never decided is restored to its catalogue default.
- The policy revision, the content hash, and the audit log are restored, so
  the revision chain continues across a reload.

A guild that has not adopted an operational policy at all is in the
`POLICY_UNINITIALIZED` state. In that state the catalogue defaults apply and
the officer interface offers the Guild Master the governance bootstrap
action.

## The officer interface

The **Modules** page of the officer interface is the configuration surface.

- **Core Services** are listed as always enabled and are not interactive.
- **Optional Features** each get a checkbox, the feature category, the
  feature description, the dependency note when one applies, and the list of
  features that would be turned off as a consequence of disabling this one.
- A feature whose dependency is off has its checkbox disabled, so it cannot be
  enabled in isolation.
- Changes stay in a local draft until **Save changes** is pressed. The draft
  is preserved when the save fails, so a rejected change never silently
  discards the officer's work.
- **Reset** restores the draft to the authoritative guild state.
- When the actor is not authorized, the page shows the exact blocking reason
  and the controls are disabled.

The interface never writes to the SavedVariables directly. It delegates every
mutation to `Dibs.OperationalPolicy.ChangeModules`, which performs the
authority, dependency, revision, and audit steps.

## Operating modes

| Mode | Effect on feature configuration |
| --- | --- |
| **Guild** | The guild catalogue applies. A policy writer or the Guild Master can change it. |
| **Independent raid** | The independent raid session is a local, guild-isolated authority. It does not change the guild catalogue, and `syncV2` refuses coordinator repair while such a session is active. |
| **RCLootCouncil** | The integration is optional. When it is off, the `rclootcouncil` feature is disabled and its dependents are disabled with it. Dibs accounting never depends on RCLootCouncil being present. |
| **Developer mode** | Local only, and isolated from production accounting. Module management is refused while the developer sandbox is active with `MIXED_PROVIDER_REJECTED`. |
| **Sandbox** | The developer sandbox uses a separate SavedVariables namespace. It never reads or writes production guild state. |

## Related documents

- [Feature catalogue](feature-catalog.md)
- [Feature dependencies](feature-dependencies.md)
- [Feature synchronization](feature-sync-protocol.md)
- [Saved variables](saved-variables.md)
