# B02b Implementation Evidence

## Scope and commits

- Batch: **B02b — revisioned operational guild policy**.
- Branch: `dev`.
- Start/checkpoint commit: `0027d854c593fd76672eb719b7285825bf17dc33`.
- Source result commit: `3566d33f517fe45e0a1bb2fb02711017367bb8e1` (`feat(policy): add revisioned operational guild policy`).
- This batch does not implement B05a or any later batch. It does not modify RCLootCouncil sources.

The source commit changes only the operational-policy module and its integration points:

- `src/modules/OperationalPolicy.lua` (new)
- `src/Core.lua`
- `src/modules/PreDibs.lua`
- `src/modules/Profiles.lua`
- `src/modules/SyncV2.lua`
- `src/RCLootCouncil_dibs.toc`
- `tests/helpers/load_addon.lua`
- `tests/integration/operational_policy_spec.lua` (new)

## Implemented architecture

### Persisted operational policy

`Dibs.OperationalPolicy` owns `db.operationalPolicy`, with an additive, separately versioned schema:

```lua
{
  schema = 1,
  status = "POLICY_UNINITIALIZED" | "POLICY_ADOPTED",
  policyRevision = 0,
  hash = "GENESIS",
  records = {},
  auditLog = {},
  conflicts = {},
}
```

The canonical policy projection is deliberately narrow:

- `allowPublicPreDibs` (boolean)
- `preDibModes[seasonId]` (`WILD_OPEN` or `ENCOUNTER`)

Language, UI/debug preferences, governance, coordinator/epoch state, ledger state, baseline/cutover state, and unrelated profile settings are outside the operational-policy payload. `Core:InitializeDB` validates and quarantines malformed operational-policy and policy-sync persistence additively.

### Authority and adoption

Initial adoption is permitted only when a governance state has already been adopted and the current local actor is the current Guild Master. A received initial policy record is accepted only under the same already-adopted governance condition; a Guild Master being present by itself is insufficient.

Subsequent records require an authorized current writer under the existing governance `policyWriterRule`: the GM is accepted; an officer is accepted only by a supported `CURRENT_ROSTER_RANK` rule and current rank; `GOVERNANCE_ONLY` rejects officers. Local commands additionally require that the supplied actor is the local current `Name-Realm` identity. Incoming records require sender/author identity equality.

This is an authority boundary for normal addon operation, not a claim that locally editable SavedVariables can be made cryptographically trustworthy in the WoW addon model.

### Revision-chain integrity

Policy records carry a canonical hash, revision, parent revision/hash, writer identity snapshot, timestamp/audit data, and allowlisted values. Application validates shape, guild identity, hash, parent linkage, current writer authority, and values before mutating state.

- Identical record replay: idempotent (`IDEMPOTENT_REPLAY`).
- Same revision with a different hash: preserved as `POLICY_CONFLICT`.
- Older revision: rejected as `STALE_POLICY`.
- Missing or incorrect parent: rejected as `POLICY_PARENT_MISSING`.

The implementation keeps governance data read-only; applying or changing operational policy cannot advance a ledger epoch or mutate ledger authority.

### B04 transport integration

After policy adoption, `SyncV2` announces a bounded `GUILD` operational-policy digest. A client that is behind stores an exact revision/hash target and requests the record detail by `WHISPER`. Detail serving and transfer initiation independently revalidate the policy writer. Reassembled operational-policy transfers apply through `OperationalPolicy.ApplyRecord`.

For out-of-order chain delivery, an intermediate parent record does not clear `SYNC_BEHIND`: the state clears only after the locally applied revision and hash exactly equal the originally advertised target. Missing parents trigger a precise parent recovery request. This preserves B04's digest-plus-detail boundary and avoids sending operational policy in raid-only channels.

### Existing feature boundaries

After policy adoption, Pre-Dibs reads its public flag and season mode from operational policy; before adoption it preserves the legacy local behavior. The legacy `preDibs.modePolicies` store is not deleted or rewritten.

After policy adoption, the guild profile path can route `allowPublicPreDibs` through operational policy. Other legacy shared-policy keys are rejected as unsupported rather than being silently synchronized. Governance is not changed by the profile path.

## Test evidence

### B02b focused and neighboring feature tests

Executed:

```powershell
$env:DIBS_TEST_FILES = 'tests/integration/operational_policy_spec.lua;tests/contract/predibs_api_contract_spec.lua;tests/unit/predibs_request_spec.lua;tests/integration/backup_import_profiles_spec.lua;tests/unit/b04_transport_spec.lua'
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **35 passed, 0 failed**.

The B02b integration coverage exercises initial adoption, strict allowlisting, GM/officer/player authority cases, Pre-Dibs routing, revision increments, no governance epoch mutation, missing-parent recovery, replay/conflict/stale behavior, simultaneous-raid convergence fixture behavior, digest/WHISPER recovery, profile routing, and rejection of invalid guild/sender/transfer traffic.

### B00–B04 regression selection

Executed B00 architecture, B01 persistence/governance, B03 local ledger, B04 transport/recovery/privacy/relay, and B02b policy integration tests.

Result: **62 passed, 0 failed** on the initial B00–B04 selection; after the final authority hardening, the focused B00–B04 selection reported **52 passed, 0 failed**.

### Final full suite

Executed once against the final B02b source commit (60 files).

Result: **277 passed, 1 failed**.

The sole failure is the known pre-existing RCLootCouncil integration baseline:

```text
FAIL RCLootCouncil DIB response projection / renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

This matches the B04 baseline and is outside B02b scope. No additional failure was introduced by B02b.

## Validation notes

- `git show --check` reports no whitespace errors for the B02b source commit.
- The implementation is additive for SavedVariables: it introduces `operationalPolicy` and optional `sync.v2.policyTarget` validation without deleting or transforming the legacy policy stores.
- The worktree’s unrelated `docs/RC_OPTIONS.md` modification and `RCLootCouncil_dibs.code-workspace` file were excluded from the B02b source result commit.

## Deferred work

Coordinator election/takeover, authority epochs, ledger baseline/cutover, and later multi-raid ledger protocol work remain deferred to their designated later batches. B02b only establishes the operational guild-policy chain and its B04-compatible synchronization path.
