# Officer guide

This guide describes the 0.6.0 release candidate. Do not treat it as Retail
certification until the manual checks in [B12 release checklist](../../B12_Release_Candidate_Checklist.md) are complete.

Use this guide to administer seasonal Dibs without changing the audit trail. Dibs is an accounting and eligibility layer; RCLootCouncil remains the loot voting/award interface when it is installed.

- [Initial configuration](configuration.md)
- [Loot and request workflow](loot-workflow.md)
- [Auditing and historical review](auditing.md)
- [Multi-raid and synchronization](multi-raid-sync.md)
- [Troubleshooting](troubleshooting.md)

## Optional modules and corrections

The Guild Master manages optional features from **System > Modules**. Disabled
modules disappear from normal navigation where appropriate, retain all stored
data, reject stale windows and direct slash/API entry points, and can be
re-enabled later. **System > Modules**, core safety services, and authorized
diagnostics remain available for management.

Administrative Dibs corrections are append-only. They add a new auditable
correction and never rewrite or delete an existing ledger/history event. Audit
evidence includes the actor, target player, timestamp, reason, before/after,
delta, request reference, and canonical event/reference.
