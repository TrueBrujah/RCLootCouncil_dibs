# RCLootCouncil integration

RCLootCouncil is an optional dependency. `Dibs.RCLootCouncil` probes the addon and reports capability states (`absent`, `operational`, `degraded`, `unsupported`). The Dibs ledger, player UI, and officer administration remain useful when RC is absent.

The adapter normalizes Dibs responses, projects supported loot semantic families (`TOKEN` and `TOKEN_SET`), and blocks unsupported cosmetic/catalyst projections. Equipment compatibility is a projection and does not by itself create a protected family. The adapter can expose candidate status, configuration projection status, voting status, and award evidence.

Live finalization requires both Dibs guild authority and a verified local RC Master Looter callback. `RCMLAwardSuccess` is the integration callback. A higher balance never replaces RC’s winner decision (DIBS-RULE-004). A qualifying finalized award may consume a Dib through the protected accounting path (DIBS-RULE-003).

## Historical reconciliation

`GetHistoryRows`, `CreateReconciliationSession`, `ConfirmReconciliationCandidate`, and `RejectReconciliationCandidate` support preview-first review of old RC history. Ambiguous rows are not silently converted. An officer selects a candidate, supplies an annotation, and confirms; only confirmation records an auditable historical award. The original timestamp, winner, owner, item, response, final status, and evidence reference are retained.

## Options integration

`Dibs.RCOptions` registers a capability-aware options projection with AceConfig/AceConfigDialog. It delegates Dibs actions to Core and OfficerUI and does not own persistence or loot awards.
