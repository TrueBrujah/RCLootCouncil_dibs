# B03 Implementation Evidence

## Git record

- Branch: `dev`
- `B03_START_COMMIT`: `35dd01ca06d73fdb867c969e2c526f1684ba7cae`
- `B03_CHECKPOINT_COMMIT`: `35dd01ca06d73fdb867c969e2c526f1684ba7cae`
- `B03_RESULT_COMMIT`: `74e248699863bf1d23880b3f1644a98e6ba8b0a6`

The pre-existing modified `docs/RC_OPTIONS.md` and untracked
`RCLootCouncil_dibs.code-workspace` were preserved and excluded from the B03
commit.

## Implemented boundary

`Dibs.Ledger.CommitLocalTransaction(context, record)` is the sole B03 durable
ledger command. It creates a detached `LOCAL_CANONICAL` record, validates the
current roster identity and actor authorization, validates action/sign/amount
and season, calculates canonical content, checks replay/conflict and balance,
then appends and updates indexes atomically.

`CommitDibUse` is the local-only equivalent of the future core command.
Neither command activates a coordinator, epoch, distributed sequence,
previous-hash chain, network replication, recovery, or protocol V2.

Legacy public mutators (`AddTransaction`, `AppendTransaction`, `Grant`, `Use`,
`Refund`, `AdminAdjust`, historical award, and allocation helpers) now delegate
to the same command and return a transaction plus a stable reason code. Core
passes the actor/action context through the boundary. Existing legacy ledger
records are left unmodified and remain readable.

## Transaction schema and identity

New B03 records contain schema `3`, record class, classification, transaction
ID, action/type, Name-Realm member key, immutable identity snapshot, optional
GUID witness, season, amount, evidence/context fields, actor snapshot, debt
policy, timestamps, and `canonicalContentHash`.

Name-Realm is the identity. GUID is stored only as witness metadata. The
Identity GUID pattern defect found while validating the GUID read path was fixed;
it cannot turn a GUID into a member key.

## Canonical serialization and hash

The B03 hash uses a type-tagged, length-delimited, recursively key-sorted Lua
serialization of an allowlisted transaction content projection. Its stable
31-bit polynomial hash is rendered as `D3-xxxxxxxx`. It is explicitly separate
from B00's test contract hash and is **not cryptographic authentication**; it
provides deterministic same-content comparison only.

- Same ID and same canonical content: `IDEMPOTENT_REPLAY`, no duplicate debit.
- Same ID and different canonical content: `TRANSACTION_CONFLICT`, no mutation.
- Existing legacy IDs and records are neither rewritten nor resequenced.

## Balance, debt, and import behavior

Debt defaults to disabled. A `DIB_USED` debit that exceeds the current balance
returns `INSUFFICIENT_BALANCE` before any transaction, index, cache, or audit
success state changes. A caller must provide an explicit local debt policy
(`allowDebt=true` and a non-empty policy source) to permit debt.

The existing first local season allocation is retained through a narrowly
bounded bootstrap command: it can allocate only the current player once and
cannot be used for another action or target. This keeps ordinary player clients
readable/usable without granting arbitrary ledger mutation.

Full imports remain available for existing duplicate legacy history. An absent
`LOCAL_CANONICAL` transaction is rejected with
`CANONICAL_LEDGER_IMPORT_UNAVAILABLE`, preventing import from becoming a second
B03 canonical write path. Baseline reconciliation remains B05a work.

## Synchronization boundary

Legacy snapshot ledger export/import is disabled for non-empty ledger payloads
(`LOCAL_ONLY` / `LEDGER_SYNC_NOT_AVAILABLE`). Pre-Dib behavior remains outside
the B03 ledger boundary. B04 must define the later transport, authenticated
envelope, ordering, gap recovery, and anti-entropy design.

## Files changed

- `src/modules/Ledger.lua`
- `src/Core.lua`
- `src/modules/Identity.lua`
- `src/modules/ProtectedActions.lua`
- `src/modules/Sync.lua`
- `src/modules/ImportExport.lua`
- `tests/unit/b03_local_ledger_spec.lua`
- ledger/Core/RC/combat/dispute compatibility tests listed in the result commit

## Validation

Focused B03 tests cover valid use, insufficient balance atomicity, explicit
debt, zero/sign/action/identity rejection, immutable Name-Realm snapshot, GUID
witness, replay/conflict, legacy readability, compatibility wrapper validation,
read copies, and B02a availability.

Executed after the final source change:

- B03 + import/export + B00 + B01 + B02a regression: **43 passed, 0 failed**.
- Affected Ledger/Core/RC/combat/dispute scenarios: **19 passed, 0 failed**.

The complete suite was executed once during B03. It initially surfaced six
legacy compatibility cases (RCLootCouncil award authority, balance setup, and
roster-validated dispute fixtures). They were fixed and verified by the focused
tests above. The complete suite was not repeated, to honor the instruction not
to repeatedly run large suites.

## Known limitations and explicit non-scope

- The content hash is non-cryptographic and cannot establish client truth.
- No B02b operational policy synchronization was implemented.
- No B04 transport or ledger replication was implemented.
- No B05a/B05b baseline, handoff, recovery, or takeover was implemented.
- No B06 coordinator activation, epoch, sequence, or hash chain was implemented.
- No RCLootCouncil adapter redesign was implemented; existing award flow only
  passes its already-authorized action context to the B03 boundary.
