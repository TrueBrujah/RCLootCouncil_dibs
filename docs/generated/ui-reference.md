THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# UI and API Reference

## Guild Setup (`guild.setup`)

Category: `setup` | Module: `Installation` | Audience: developer, gm

**English:** Guild Master workflow for reviewing existing Dibs data and activating this guild's shared Dibs ledger. Opening the page does not initialize it.
**Francais:** Parcours reserve au maitre de guilde pour examiner les donnees Dibs existantes et activer le registre partage de la guilde. Ouvrir la page ne l'initialise pas.
Source: `src/modules/Installation.lua:263` (`Installation.Initialize`)

## Manual Dibs Adjustment (`ledger.adjust`)

Category: `ledger` | Module: `ProtectedActions` | Audience: gm, officer

**English:** Guild Master and authorized Officers can adjust a member's current-season balance. Each change records actor, target, reason, previous balance, and resulting balance in audit history.
**Francais:** Le maitre de guilde et les officiers autorises peuvent ajuster le solde de la saison pour un membre. L'historique conserve l'auteur, la cible, la raison et les soldes avant/apres.
Source: `src/modules/ProtectedActions.lua:222` (`executeLedgerAdjust`)

## Dib Balance (`ledger.balance`)

Category: `ledger` | Module: `Ledger` | Audience: gm, officer, player

**English:** Your available Dibs are scoped to this guild and season. A qualifying finalized award or authorized adjustment changes the balance.
**Francais:** Vos Dibs disponibles sont propres a cette guilde et a cette saison. Un gain eligible finalise ou un ajustement autorise modifie le solde.
Source: `src/modules/Ledger.lua:641` (`Ledger.GetBalance`)

## Encounter Mode (`predibs.encounter.mode`)

Category: `predibs` | Module: `PreDibs` | Audience: gm, officer, player

**English:** Controls when players may submit a Pre-Dib. Encounter mode requires the matching raid and difficulty context; Wild Open may allow requests outside the raid under guild policy.
**Francais:** Determine quand les joueurs peuvent envoyer un Pre-Dib. Le mode Encounter exige le raid et la difficulte correspondants; Wild Open peut autoriser les demandes hors raid selon la politique de guilde.
Source: `src/modules/PreDibs.lua:456` (`Dibs.PreDibs.ValidatePublicRequest`)

## Pre-Dib Request (`predibs.request`)

Category: `predibs` | Module: `PreDibs` | Audience: gm, officer, player

**English:** A Pre-Dib records your interest in eligible loot. It does not award an item or spend a Dib; that happens only after a qualifying award is finalized.
**Francais:** Un Pre-Dib indique votre interet pour un butin eligible. Il n'attribue pas l'objet et ne depense pas de Dib; cela arrive seulement apres un gain eligible finalise.
Source: `src/modules/PreDibs.lua:574` (`Dibs.PreDibs.CreatePublic`)

## Rank Allocation (`rank.allocation`)

Category: `rank-rules` | Module: `ProtectedActions` | Audience: gm, officer

**English:** Starting Dibs assigned to a guild rank for the selected season. Changing the rule does not rewrite older ledger entries.
**Francais:** Dibs attribues au depart a un rang de guilde pour la saison selectionnee. Changer la regle ne reecrit pas les anciennes transactions.
Source: `src/modules/ProtectedActions.lua:154` (`executeRankSet`)

## Historical Reconciliation (`setup.reconciliation`)

Category: `setup` | Module: `Installation` | Audience: developer, gm, officer

**English:** Review detected historical Dibs entries before the Guild Master initializes the shared ledger. Keep uncertain evidence unresolved until it is understood.
**Francais:** Examinez les entrees Dibs historiques detectees avant que le maitre de guilde initialise le registre partage. Laissez les preuves incertaines sans decision.
Source: `src/modules/Installation.lua:164` (`Installation.GetReconciliationView`)

## Coordinator (`sync.coordinator`)

Category: `governance` | Module: `Governance` | Audience: developer, gm, officer

**English:** The authorized Dibs client that applies canonical guild-ledger updates. It is normally selected during Guild Setup.
**Francais:** Client Dibs autorise a appliquer les mises a jour canoniques du registre de guilde. Il est normalement choisi pendant la configuration.
Source: `src/modules/Governance.lua:416` (`Governance.GetAuthorityState`)

## SyncV2 Protocol State (`sync.protocol.state`)

Category: `protocol` | Module: `SyncV2` | Audience: developer

**English:** Diagnostics may show protocol state such as V2_ENFORCED, ledgerEpoch, and hashes. These identifiers help troubleshooting; ordinary setup uses the status and next action.
**Francais:** Les diagnostics peuvent afficher des etats de protocole comme V2_ENFORCED, ledgerEpoch et les empreintes. Ils servent au depannage; la configuration normale utilise les statuts et actions indiquees.
**Technical reference:** SyncV2 may report LEGACY_LOCAL before cutover, CUTOVER_PREPARED while writer compatibility is prepared, or V2_ENFORCED after approved enforcement. ledgerEpoch identifies the active canonical ledger generation; legacyBaselineHash identifies the approved legacy baseline.
Source: `src/modules/SyncV2.lua:478` (`Sync.SetProtocolState`)

## Synchronization (`sync.status`)

Category: `synchronization` | Module: `SyncV2` | Audience: gm, officer, player

**English:** Shows whether this client can exchange current guild Dibs state. Unavailable or behind clients may be unable to apply canonical updates.
**Francais:** Indique si ce client peut echanger l'etat Dibs actuel de la guilde. Un client indisponible ou en retard peut ne pas appliquer les mises a jour canoniques.
Source: `src/modules/SyncV2.lua:239` (`Sync.GetStatus`)
