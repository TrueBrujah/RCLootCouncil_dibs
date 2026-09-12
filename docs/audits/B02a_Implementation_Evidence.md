# B02a Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B02A_START_COMMIT`: `d0bc164b6fe7f7bc128534e34d8de59c5acc4b4f`
- `B02A_CHECKPOINT_COMMIT`: `d0bc164b6fe7f7bc128534e34d8de59c5acc4b4f`
- `B02A_RESULT_COMMIT`: `d0d6129f23eb90d47539878aff2015c29500a592`

The B01 evidence commit was verified as the exact committed project checkpoint
before B02a. Existing user work in `docs/RC_OPTIONS.md` and
`RCLootCouncil_dibs.code-workspace` was not staged or changed.

## Files changed

- `src/modules/Identity.lua` — canonical Name-Realm, roster freshness, explicit
  short-name outcomes, optional GUID witness, and immutable snapshots.
- `src/modules/Governance.lua` — GM-only explicit governance bootstrap,
  deterministic record hashing, parent validation, idempotency, and conflicts.
- `src/Core.lua` — additive governance persistence validation and
  `GUILD_ROSTER_UPDATE` forwarding.
- `src/RCLootCouncil_dibs.toc` and `tests/helpers/load_addon.lua` — identity and
  governance load order.
- `tests/helpers/wow_api.lua` and
  `tests/integration/governance_bootstrap_spec.lua` — mutable roster fixture and
  focused B02a contracts.
- `docs/developer/governance-bootstrap.md`,
  `docs/developer/saved-variables.md`, and `src/Types.lua` — public developer
  contract and annotations.

## Identity model

`Dibs.Identity` treats complete Name-Realm as the only canonical member/wire
key, normalized deterministically for comparison while retaining the observed
display Name-Realm in every snapshot. A GUID is optional `guidWitness` metadata;
it never replaces or remaps the Name-Realm key. A short name resolves only when
the live roster has exactly one candidate. Outcomes are `RESOLVED`,
`AMBIGUOUS_IDENTITY`, `UNKNOWN_ROSTER_MEMBER`, or `ROSTER_UNAVAILABLE`.

Historical ledger and Pre-Dib names are not inspected or rewritten. Alias storage
exists as empty, future GM-reviewed governance structure; no automatic alias,
rename, realm-transfer, or GUID merge is implemented.

## Roster freshness and authority

Core registers `GUILD_ROSTER_UPDATE` and calls `Identity.OnRosterChanged()`,
which increments the generation and invalidates roster freshness. Each governance
record creation or application refreshes the current WoW roster immediately and
accepts authority only when the actual sender/author resolves to the current
rank-0 Guild Master. Local rank settings and SavedVariables never qualify a GM.

## Governance record and adoption

`db.governance` is an additive schema-1 subtree. It starts with
`POLICY_UNINITIALIZED`, revision `0`, and hash `GENESIS`; no local setting is
promoted automatically. An initial record is explicit and auditable, with:

- schema/class and guild scope;
- governance revision and parent revision/hash;
- Name-Realm author plus immutable identity snapshot;
- timestamp/audit metadata;
- deterministic canonical content hash;
- officer/policy-writer rules and inactive future concepts.

Only the current GM can adopt or change governance. A same revision and hash is
an idempotent replay. A same revision with a different hash records an explicit
conflict. Any wrong/missing parent is rejected with
`GOVERNANCE_PARENT_MISMATCH`.

## Inactive future concepts

The B02a schema explicitly keeps `coordinator`, `ledgerEpoch`, and `baseline`
nil and `protocolState` at `LEGACY_LOCAL`. Persistence quarantines a malformed
or manually activated future value. No coordinator is activated, no canonical
ledger epoch exists, and no V2 production transport is registered.

## Migration

No root or guild schema increment was required. The B01 staged persistence
boundary adds/validates `db.governance` and its collections as an additive
subtree. Existing ledger, season, Pre-Dib, transaction-ID, and historical-name
data remain unchanged.

## Tests executed

Focused B02a plus B00/B01 regression:

```powershell
$env:DIBS_TEST_FILES = 'tests/integration/governance_bootstrap_spec.lua;tests/integration/persistence_recovery_spec.lua;tests/contract/b00_architecture_contract_spec.lua;tests/integration/migration_spec.lua;tests/integration/predibs_migration_spec.lua'
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **30 passed, 0 failed (5 files)**.

Broader suite, executed once after the final source change:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter '*_spec.lua' | ForEach-Object { $_.FullName.Substring($PWD.Path.Length + 1).Replace('\','/') } | Sort-Object
$env:DIBS_TEST_FILES = ($files -join ';')
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **253 passed, 0 failed (57 files)**.

The focused tests cover canonical/ambiguous/unknown identity resolution, GUID
witness disagreement, immutable historical names, roster event invalidation,
demotion/promotion re-evaluation, fresh-roster refusal, GM-only adoption/change,
local-setting self-authorization rejection, uninitialized startup, initial
revision/hash/audit, idempotent replay, hash conflict, parent mismatch, and
inactive future fields.

## Known limitations and scope confirmation

B02a deliberately does not implement B02b operational policy writers, B03/B04
canonical ledger/hash/protocol-V2 behavior, any coordinator activation, legacy
baseline reconciliation, distributed synchronization, `AWARD_COMMIT`, or
RCLootCouncil integration changes. Governance records are local persistence and
explicit validation APIs only; no governance transport is introduced in B02a.

This evidence is committed separately because a Git commit cannot contain its
own result hash. The result hash above identifies the B02a-only implementation
commit.
