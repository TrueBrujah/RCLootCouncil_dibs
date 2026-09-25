THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# Officer Documentation Reference

Addon version: 0.6.5

## Manual Dibs Adjustment

- **ID:** `ledger.adjust`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Guild Master and authorized Officers can adjust a member's current-season balance. Each change records actor, target, reason, previous balance, and resulting balance in audit history.
**Francais:** Le maitre de guilde et les officiers autorises peuvent ajuster le solde de la saison pour un membre. L'historique conserve l'auteur, la cible, la raison et les soldes avant/apres.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `ledger.adjust`
Source: [src/modules/ProtectedActions.lua:222](../../src/modules/ProtectedActions.lua#L222) - `executeLedgerAdjust`

## Dib Balance

- **ID:** `ledger.balance`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Your available Dibs are scoped to this guild and season. A qualifying finalized award or authorized adjustment changes the balance.
**Francais:** Vos Dibs disponibles sont propres a cette guilde et a cette saison. Un gain eligible finalise ou un ajustement autorise modifie le solde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/Ledger.lua:641](../../src/modules/Ledger.lua#L641) - `Ledger.GetBalance`

## Encounter Mode

- **ID:** `predibs.encounter.mode`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** Controls when players may submit a Pre-Dib. Encounter mode requires the matching raid and difficulty context; Wild Open may allow requests outside the raid under guild policy.
**Francais:** Determine quand les joueurs peuvent envoyer un Pre-Dib. Le mode Encounter exige le raid et la difficulte correspondants; Wild Open peut autoriser les demandes hors raid selon la politique de guilde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/PreDibs.lua:456](../../src/modules/PreDibs.lua#L456) - `Dibs.PreDibs.ValidatePublicRequest`

## Pre-Dib Request

- **ID:** `predibs.request`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** A Pre-Dib records your interest in eligible loot. It does not award an item or spend a Dib; that happens only after a qualifying award is finalized.
**Francais:** Un Pre-Dib indique votre interet pour un butin eligible. Il n'attribue pas l'objet et ne depense pas de Dib; cela arrive seulement apres un gain eligible finalise.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Source: [src/modules/PreDibs.lua:574](../../src/modules/PreDibs.lua#L574) - `Dibs.PreDibs.CreatePublic`

## Rank Allocation

- **ID:** `rank.allocation`
- **Category:** `rank-rules`
- **Audience:** gm, officer

**English:** Starting Dibs assigned to a guild rank for the selected season. Changing the rule does not rewrite older ledger entries.
**Francais:** Dibs attribues au depart a un rang de guilde pour la saison selectionnee. Changer la regle ne reecrit pas les anciennes transactions.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Permission: `rank.set`
Source: [src/modules/ProtectedActions.lua:154](../../src/modules/ProtectedActions.lua#L154) - `executeRankSet`

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

## Synchronization

- **ID:** `sync.status`
- **Category:** `synchronization`
- **Audience:** gm, officer, player

**English:** Shows whether this client can exchange current guild Dibs state. Unavailable or behind clients may be unable to apply canonical updates.
**Francais:** Indique si ce client peut echanger l'etat Dibs actuel de la guilde. Un client indisponible ou en retard peut ne pas appliquer les mises a jour canoniques.

Scope: `guild` | Audit: `false` | Reason required: `false`
Source: [src/modules/SyncV2.lua:239](../../src/modules/SyncV2.lua#L239) - `Sync.GetStatus`
