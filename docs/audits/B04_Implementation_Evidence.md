# B04 Implementation Evidence

## Result

- Branch: `dev`
- B04 checkpoint/start: `b1ead601f7d2792f2f087477b936d365e9b391f5`
- B04 source result commit (`B04_RESULT_COMMIT`): `d501bec0a399bdf6befbdbf9ce6f66084ff7023c`
- Scope: B04 transport, bounded pull anti-entropy, Pre-Dib request-index/tombstone recovery, and protocol-state representation only.

## Delivered behavior

- `src/modules/SyncV2.lua` provides protocol-major-2 envelopes over AceComm and AceSerializer only. Missing either service reports `SYNC_UNAVAILABLE`; there is no compact or Blizzard-API fallback.
- Guild-wide messages are bounded `GUILD` digests. Pre-Dib and governance detail is transferred only by `WHISPER`, in a bounded begin/chunk/end transfer.
- The Pre-Dib index stores a bounded view of active records and terminal `cancelled`, `invalidated`, and `fulfilled` tombstones. Detail application is deterministic: same revision/content is idempotent, a lower revision is stale, and different content at the same revision conflicts.
- Transfers bind the sender and transfer ID, accept reordered chunks, require every actual chunk, validate the concatenated payload hash before deserializing, and validate entity identity/content before persistence. Unsupported transfer entities and transfer-ID replacement are rejected.
- Replay, peer, index, tombstone, transfer, chunk, and payload resources are bounded. Ledger traffic remains digest-only and cannot mutate the canonical B03 ledger.
- Startup, recurring low-frequency heartbeat, and a settled `GUILD_ROSTER_UPDATE` pass initiate bounded anti-entropy. A roster event first preserves B02a freshness invalidation, then schedules the comparison after the roster settles.
- `SYNC_BEHIND`, `LEGACY_LOCAL`, and `CUTOVER_PREPARED` are represented. B04 refuses to activate `V2_ENFORCED`; governance/cutover enforcement remains later work.
- SavedVariables add an isolated `sync.v2` subtree. Invalid V2 schema/state is quarantined through the existing B01 recovery path. Existing ledger/history records are not migrated, rewritten, or replicated.

## Validation

- B04-focused transport, recovery, privacy, and relay tests: **21 passed, 0 failed**.
- B00/B01/B02a/B03 regressions: **34 passed, 0 failed**.
- Full suite executed once: **268 passed, 1 failed** across 59 files.

The one full-suite failure is isolated and reproducible in `tests/integration/rclootcouncil_buttons_spec.lua` (`renders the voting Dibs value from a normalized RCLootCouncil row identity`): it expects `2/2` and receives `1/1`. It exercises RCLootCouncil balance-column projection, not B04 transport, synchronization, persistence, or Pre-Dib code. It was not changed because B04 scope excludes RCLootCouncil adapter/ledger behavior.

## Explicit non-scope

- No B02b operational guild-policy synchronization.
- No B05 baseline, recovery, or coordinator handoff.
- No B06 coordinator, authority epoch, sequence, or distributed `AWARD_COMMIT` path.
- No ledger replication, canonical V2 ledger activation, or RCLootCouncil integration redesign.
- No changes to the unrelated working-tree files `docs/RC_OPTIONS.md` and `RCLootCouncil_dibs.code-workspace`.
