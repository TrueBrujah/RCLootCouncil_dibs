# Officer guide

## Mode d'emploi en français

Voir [Mode d'emploi GM / Officer](MODE_EMPLOI_GM_OFFICER.md) pour la
configuration, la readiness, RCLootCouncil, les corrections et les sauvegardes.

## English guide

See [GM / Officer Guide](GM_OFFICER_GUIDE_EN.md) for setup, governance,
reconciliation, recovery, and release checks in English.

For the first installation, open **Overview > Setup Assistant**. The English
workflow is documented in [GM / Officer Guide](GM_OFFICER_GUIDE_EN.md), and the
French workflow is documented in [Mode d'emploi GM / Officer](MODE_EMPLOI_GM_OFFICER.md).
The assistant derives readiness from current state, routes supported changes
through protected actions, and keeps its dry-run local.

This guide describes the 0.6.5 B12 release. Do not treat it as
Retail certification until the manual checks in the [B12 Retail evidence record](../audits/B12_Retail_Validation_Evidence.md) are complete.

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
