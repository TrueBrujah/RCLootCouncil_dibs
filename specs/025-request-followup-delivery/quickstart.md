# Validation

From the repository root, set `DIBS_TEST_FILES` to focused semicolon-separated suites,
run `npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua`, and restore the
previous environment in `finally`. Then run `git diff --check`.

Automated evidence is recorded in tasks.md after implementation; no Retail claim
follows from Fengari success.

2026-10-15 focused follow-up validation: `request_delivery_spec.lua` (16 tests)
and `request_followup_spec.lua` (13 tests), **29 passed, 0 failed**. The dedicated
wrong-actual-sender ACK regression preserves pending work despite matching
operation/request/revision/authority fields, then accepts the legitimate
coordinator's receipt. This is not a parent full-suite result.

Parent full regression: **994 passed, 0 failed (157 files)**, completed before
the added wrong-actual-sender ACK regression. The new regression was subsequently
covered by the targeted **29 passed, 0 failed (2 files)** run above; no 995-test
full run is claimed. Automated validation is complete. **T016 remains open** for
manual Retail certification.

## Current safety limitations

Shared request writes, including corrections and lifecycle transitions, require
the current verified coordinator client and the dossier's pinned epoch. Other
officers have read-only replicas, even when assigned responsibility. There is no
automatic coordinator/old-epoch handoff recovery: authority changes block old
shared dossiers and their pending operations rather than rebasing them.

## Manual Retail gates
- Two current clients: player offline submission/reload, coordinator reconnect,
  private receipt and owner reply/resolution; inspect no guild-body traffic.
- Third verified officer: read-only shared queue, demotion and coordinator change.
- EN/FR narrow/wide UI, combat/readiness guards, snooze/login reminders.
- Large dossier explicit capacity/transport error and recovery without data loss.
