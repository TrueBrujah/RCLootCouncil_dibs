# Troubleshooting

**The Officer page is empty.** Confirm that the character is a guild GM/officer and that the active guild bucket is loaded. A degraded or absent RCLootCouncil integration does not prevent local Dibs pages from working.

**A live award is rejected.** Check readiness, combat state, guild authority, local RC Master Looter authority, item semantic family, and the active season. Retry after `PLAYER_REGEN_ENABLED` when the UI was locked.

**An import or restore does nothing.** Select the package/snapshot, run preview/validation, correct checksum or size errors, then explicitly apply. Create a backup first.

**A request is missing on another raid.** Check the `DIBS` prefix, guild membership, protocol version, officer scope, request revision, and manifest retry. Live loot data is intentionally not synchronized.

**A date displays as zero.** Treat it as invalid/missing source data. Do not audit or confirm it until the original RC timestamp/evidence is available.

**A profile does not activate.** Check profile name, scope, permissions, and preview result. Profile activation changes settings only; it cannot repair or rewrite ledger history.
