# Contract: RCLootCouncil Adapter

## Purpose

The adapter is an optional boundary between Dibs and RCLootCouncil. It detects supported
capabilities, exposes a compatibility state, projects read-only loot information, and
converts a trusted finalized award into the protected Dibs finalization command.

## Capability Contract

The adapter MUST expose a status equivalent to:

| State | Meaning | Allowed behavior |
|---|---|---|
| `absent` | RCLootCouncil is not loaded or installed | Standalone Dibs remains available |
| `operational` | All required capabilities are verified | Read-only projections and validated award path are available |
| `degraded` | Some optional or runtime capability is unavailable | Standalone Dibs remains available; affected integration action is denied |
| `unsupported` | The loaded surface cannot be safely mapped | No protected integration action; diagnostic explains the mismatch |

The status MUST be derived locally and MUST NOT be accepted from an addon message or saved
payload. A version label alone MUST NOT produce `operational`.

## Required Capability Probes

An operational award path requires proof of:

1. RCLootCouncil instance discovery;
2. current Master Looter identity;
3. finalized-award callback registration;
4. stable winner and item identity extraction;
5. explicit response normalization;
6. protected finalization handoff.

UI projections may be degraded independently from award finalization. A missing voting-frame
surface MUST NOT disable Standalone Dibs or grant a fallback authority.

## Lifecycle Rules

- Discovery MUST tolerate RCLootCouncil loading after Dibs.
- Hook installation MUST be idempotent per owner and hook kind.
- Retry work MUST be bounded and MUST stop after the capability state is known to be
  unsupported.
- A frame refresh MUST NOT call the same update hook recursively.
- The adapter MUST NOT modify RCLootCouncil core source, registries, or unrelated history.
- Every protected award action MUST re-evaluate state and Master Looter identity.

## Failure Contract

The adapter returns a stable reason code and a localized diagnostic for denied integration
actions. It MUST fail closed for unknown, malformed, or changing state. Failure MUST NOT
clear or rewrite Dibs seasons, requests, balances, or history.

## Privacy Contract

Adapter projections and diagnostics MUST NOT expose live RCLootCouncil candidate lists,
votes, response payloads, or session state to cross-raid synchronization. Player-facing
surfaces show only data allowed by the Dibs visibility policy.
