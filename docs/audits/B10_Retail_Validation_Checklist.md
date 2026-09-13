# B10 Retail and release validation checklist

`RETAIL_RUNTIME_VALIDATION = PENDING_B10_RELEASE_GATE`

This checklist is the final production gate. Documentation and automated
fixtures do not substitute for live Retail evidence. Record the WoW build,
Dibs version, RCLootCouncil version/profile, date, actor roles, exact steps,
observed result, and debug report or screenshot for every completed item.

## Automated evidence

- [ ] B00-B09 evidence files are present and their result commits are recorded.
- [ ] The full Fengari suite passes, with any established baseline failure
      named exactly and not attributed to B10.
- [ ] `git diff --check` is clean and the packaged TOC/version is reviewed.

## Retail core and persistence

- [ ] Install the ZIP into a clean Retail AddOns directory and verify the TOC.
- [ ] Validate migration, startup backup, quarantine, future-schema read-only
      behavior, guild isolation, export/import, and restore-point behavior.
- [ ] Verify `LEGACY_LOCAL`, `CUTOVER_PREPARED`, and GM-approved
      `V2_ENFORCED` transitions; legacy writes remain evidence after cutover.

## Two-client and multi-raid protocol

- [ ] Run two clients in separate raids and verify GUILD digest hints plus
      WHISPER detail recovery without live loot/candidate/vote/response data.
- [ ] Apply an `AWARD_COMMIT` only at the exact next sequence with the matching
      previous hash; verify duplicate idempotency and conflict rejection.
- [ ] Drop, reorder, duplicate, and reconnect messages; verify `SYNC_BEHIND`
      blocks coordinator activation and canonical consumption until recovery.
- [ ] Verify normal handoff requires the predecessor epoch, final sequence,
      and root hash; old-epoch late events remain orphaned evidence.
- [ ] Make the coordinator unavailable and verify award evidence becomes
      `PENDING_RECONCILIATION` with no local balance change.
- [ ] Complete GM-approved forced recovery with a baseline hash and audit
      decisions; verify no proposal is automatically debited.

## RCLootCouncil and combat safety

- [ ] Test RC absent, disabled, late-loaded, reloaded, degraded, and
      unsupported; Standalone Dibs remains usable and automatic consumption is
      disabled unless the profile is explicitly supported.
- [ ] Validate the proposed RC profile's callback, finalized status, stable
      Name-Realm winner/item identity, duplicate/conflict behavior, correction,
      re-award, and history projection.
- [ ] Verify Dibs never writes RC history and legacy `dibsOrigin` rows remain
      display-only.
- [ ] During combat, verify no RC-owned control or script is mutated; deferred
      Dibs-owned UI refreshes complete once after combat ends.
- [ ] Verify a non-coordinator, non-ML, raid role, or council role cannot create
      a canonical Dibs debit or acquire guild administration authority.

## Release decision

Do not promote a real RC version in
`docs/developer/rclootcouncil-adapter-matrix.md`, publish a production claim,
or change the pending runtime marker until every required item has evidence.
