# RCLootCouncil integration

RCLootCouncil is an optional dependency. `Dibs.RCLootCouncil` probes the addon and reports capability states (`absent`, `operational`, `degraded`, `unsupported`). The Dibs ledger, player UI, and officer administration remain useful when RC is absent.

The adapter normalizes Dibs responses and projects configured semantic loot
families, including Curios (`TOKEN`) and class Tier Set tokens (`TOKEN_SET`).
Personal `CATALYST` is always excluded. Cosmetic projection is capability-gated:
the public RCLootCouncil classifier extension can provide a `COSMETIC` group;
unsupported clients report that family as skipped. Ordinary equipment resolves
through `OTHER`, independently of equipment-slot button sets. See
[the mapping and template reference](../RC_OPTIONS.md) for current limits.
The adapter exposes candidate, configuration, voting, and award-evidence status.

Live finalization requires a verified local RC Master Looter callback plus the
protected item's, winner's, season's, response's, and finalization checks.
`RCMLAwardSuccess` is the integration callback. This narrow award authority
does not require or grant Dibs GM/Officer administration. The Master Looter
cannot grant, refund, or configure Dibs from that role alone. In canonical V2
mode, the coordinator still revalidates and commits accounting; a callback is
not permission to bypass ordering or recovery.
A higher balance never replaces RC's winner decision (DIBS-RULE-004).

## Historical reconciliation

`GetHistoryRows`, `CreateReconciliationSession`, `ConfirmReconciliationCandidate`, and `RejectReconciliationCandidate` support preview-first review of old RC history. Ambiguous rows are not silently converted. An officer selects a candidate, supplies an annotation, and confirms; only confirmation records an auditable historical award. The original timestamp, winner, owner, item, response, final status, and evidence reference are retained.

## Options integration

`Dibs.RCOptions` registers a capability-aware options projection with AceConfig/AceConfigDialog. It delegates Dibs actions to Core and OfficerUI and does not own persistence or loot awards.
