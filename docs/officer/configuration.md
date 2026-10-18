# Initial configuration

1. Open the Dibs Officer control center from the addon options or `/dibs officer`.
2. Open **Guild Setup > Guided Setup**: choose Progression raid, Standard loot, or
   Custom/advanced, review the preview, then apply permitted actions and verify.
   Custom preserves settings; Officer preparation does not perform GM approvals.
   Confirm the guild and installation mode. Guild GM/officer authority is
   separate from RCLootCouncil Master Looter authority.
3. Follow correction links for unresolved setup. In **Guild Rules > Seasons**,
   create a season, give it a clear name, and make it active if still needed.
4. Configure rank allocations for that season. Disable Dibs for ranks that should
   not receive starting allocations; members of those ranks are omitted from
   allocation-reconciliation warnings. Existing ledger allocations are preserved.
   The rank snapshot used when a transaction is recorded remains in its audit data.
5. Choose Pre-Dibs mode and announcement channels/templates. Public requests can be disabled while officers continue to review existing records. In **Guild Rules > Announcements**, **Enable public announcements** and **Enable officer announcements** turn each announcement kind off (channel None) or back on (previous channel restored).
6. Review loot eligibility policies for supported semantic families and difficulties.
   The GM must explicitly adopt/publish **Guild Rules > Loot Rules**; editing
   a draft alone does not publish it. Use **Guild Setup > Guild Ledgers** for
   historical baseline review and canonical-ledger activation. Use **Automatic
   Dibs** for confirmed positive-only allocation top-ups; never remove assigned
   Dibs after demotion.
7. Create a backup before importing or restoring data. Imports are preview-first and require explicit application.

8. Review **System > Modules** as the Guild Master. Optional modules can be
   disabled without deleting their requests, Pre-Dibs, history, RCLootCouncil
   evidence, eligibility policy, announcements, or reconciliation evidence.
   Disabled features leave normal navigation and reject direct or stale access;
   re-enable them from this page to restore access. Core safety modules cannot
   be disabled.

Use profiles for repeatable settings. Activating a profile changes configuration projection; it does not rewrite ledger history. Keep the default backup retention unless guild policy requires another bounded value.

After setup, **Guild Setup > Guild Setup Checks** verifies the one-time guild
configuration and synchronization state without requiring a raid.

Setup and readiness results include specific correction instructions. Hover over
a status or correction button for the cause and next steps. On its destination
page, **What needs attention on this page** identifies the current blockers and
warnings, even when opened directly from navigation. Use **Verify again** after
the correction: resolved issues disappear. Opening help never changes settings;
existing authority and confirmation requirements still apply. A live Master
Looter check outside a raid requires joining the intended raid, not changing
guild permissions.

For missing or delayed guild data, use **System > Synchronization > Repair peer**
or **Resynchronize guild** (GM/Officer), not a factory reset. The equivalent
commands are `/dibs sync repair Name-Realm` and `/dibs sync repair guild`.
An accepted request starts validated recovery; it does not certify convergence.
Probe the affected member after transfers. Conflicting histories require review,
and recovery needs an available valid source. See
[the Officer guide](GM_OFFICER_GUIDE_EN.md#fixing-a-client-marked-behind).

Before a raid, use **Overview > Raid Readiness**, `/dibs readiness`, and a local
dry-run. Missing live raid context is distinct from failed standalone setup.
Raid Readiness warns, without blocking, when online raid members lack DIBS or
need an update; readiness and dry-run results are not Retail certification.
