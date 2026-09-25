THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# Developer Documentation Reference

Addon version: 0.6.5

## Guild Setup

- **ID:** `guild.setup`
- **Category:** `setup`
- **Audience:** developer, gm

**English:** Guild Master workflow for reviewing existing Dibs data and activating this guild's shared Dibs ledger. Opening the page does not initialize it.
**Francais:** Parcours reserve au maitre de guilde pour examiner les donnees Dibs existantes et activer le registre partage de la guilde. Ouvrir la page ne l'initialise pas.

Scope: `guild` | Audit: `true` | Reason required: `false`
Source: [src/modules/Installation.lua:263](../../src/modules/Installation.lua#L263) - `Installation.Initialize`

## Historical Reconciliation

- **ID:** `setup.reconciliation`
- **Category:** `setup`
- **Audience:** developer, gm, officer

**English:** Review detected historical Dibs entries before the Guild Master initializes the shared ledger. Keep uncertain evidence unresolved until it is understood.
**Francais:** Examinez les entrees Dibs historiques detectees avant que le maitre de guilde initialise le registre partage. Laissez les preuves incertaines sans decision.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Installation.lua:164](../../src/modules/Installation.lua#L164) - `Installation.GetReconciliationView`

## Coordinator

- **ID:** `sync.coordinator`
- **Category:** `governance`
- **Audience:** developer, gm, officer

**English:** The authorized Dibs client that applies canonical guild-ledger updates. It is normally selected during Guild Setup.
**Francais:** Client Dibs autorise a appliquer les mises a jour canoniques du registre de guilde. Il est normalement choisi pendant la configuration.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/Governance.lua:416](../../src/modules/Governance.lua#L416) - `Governance.GetAuthorityState`

## SyncV2 Protocol State

- **ID:** `sync.protocol.state`
- **Category:** `protocol`
- **Audience:** developer

**English:** Diagnostics may show protocol state such as V2_ENFORCED, ledgerEpoch, and hashes. These identifiers help troubleshooting; ordinary setup uses the status and next action.
**Francais:** Les diagnostics peuvent afficher des etats de protocole comme V2_ENFORCED, ledgerEpoch et les empreintes. Ils servent au depannage; la configuration normale utilise les statuts et actions indiquees.

**Technical reference:** SyncV2 may report LEGACY_LOCAL before cutover, CUTOVER_PREPARED while writer compatibility is prepared, or V2_ENFORCED after approved enforcement. ledgerEpoch identifies the active canonical ledger generation; legacyBaselineHash identifies the approved legacy baseline.
**Reference technique:** SyncV2 peut indiquer LEGACY_LOCAL avant le changement, CUTOVER_PREPARED pendant la preparation de compatibilite des ecrivains, ou V2_ENFORCED apres activation approuvee. ledgerEpoch identifie la generation active du registre canonique; legacyBaselineHash identifie la base historique approuvee.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/SyncV2.lua:478](../../src/modules/SyncV2.lua#L478) - `Sync.SetProtocolState`
