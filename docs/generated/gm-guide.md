THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# Guild Master Documentation Reference

Addon version: 0.8.0

## Guild Ledger status

- **ID:** `guild.ledger.status`
- **Category:** `setup`
- **Audience:** developer, gm, officer

**English:** Shows whether the shared guild ledger needs setup, historical review, or recovery, or is active. Initialization remains a Guild Master-authorized action.
**Francais:** Indique si le registre partage doit etre configure, si les donnees historiques doivent etre examinees, s'il faut une recuperation ou s'il est actif. Son initialisation exige l'autorite du maitre de guilde.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Dibs season

- **ID:** `guild.season`
- **Category:** `governance`
- **Audience:** gm, officer

**English:** A season scopes the active Dibs balance and guild rules. Activating another season does not rewrite earlier history.
**Francais:** Une saison determine le solde Dibs actif et les regles de guilde. Activer une autre saison ne reecrit pas l'historique anterieur.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Guild Configuration

- **ID:** `guild.setup`
- **Category:** `setup`
- **Audience:** developer, gm

**English:** Guild Master workflow for Guild Configuration: review existing Dibs data and activate this guild's shared Dibs ledger. Opening this page does not initialize it.
**Francais:** Parcours du maitre de guilde pour la configuration de guilde : examinez les donnees Dibs existantes et activez le registre partage de cette guilde. Ouvrir cette page ne l'initialise pas.

Scope: `guild` | Audit: `true` | Reason required: `false`

## Manual Dibs Adjustment

- **ID:** `ledger.adjust`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Guild Master and authorized Officers can adjust a member's current-season balance. Each change records actor, target, reason, previous balance, and resulting balance in audit history.
**Francais:** Le maitre de guilde et les officiers autorises peuvent ajuster le solde de la saison pour un membre. L'historique conserve l'auteur, la cible, la raison et les soldes avant/apres.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `ledger.adjust`

## Adjustment reason

- **ID:** `ledger.adjust.reason`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** The recorded explanation for this action. Administrative changes require a meaningful reason.
**Francais:** Explication conservee avec cette action. Les changements administratifs exigent une raison pertinente.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `ledger.adjust`

## Dibs audit history

- **ID:** `ledger.audit.history`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Dib Balance

- **ID:** `ledger.balance`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Your available Dibs are scoped to this guild and season. A qualifying finalized award or authorized adjustment changes the balance.
**Francais:** Vos Dibs disponibles sont propres a cette guilde et a cette saison. Un gain eligible finalise ou un ajustement autorise modifie le solde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Loot eligibility

- **ID:** `loot.eligibility`
- **Category:** `governance`
- **Audience:** gm, officer, player

**English:** Shows whether a loot category may use Dibs under the active guild policy, and why a category is blocked or needs review.
**Francais:** Indique si une categorie de butin peut utiliser les Dibs selon la politique active, et pourquoi elle est bloquee ou a verifier.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Request audit timeline

- **ID:** `officer.audit.timeline`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Officer review requests

- **ID:** `officer.review.requests`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Shows player reports and their attached Dibs or RCLootCouncil evidence. Opening a request is read-only; Officer resolutions retain an audit reason.
**Francais:** Affiche les signalements des joueurs et leurs preuves Dibs ou RCLootCouncil. Ouvrir une demande est en lecture seule; les decisions des officiers conservent une raison d'audit.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Player raid readiness

- **ID:** `player.readiness`
- **Category:** `setup`
- **Audience:** gm, officer, player

**English:** Summarizes whether current guild setup and context are ready for live loot. An unavailable check is not a personal penalty; contact an Officer if the state remains blocked.
**Francais:** Resume si la configuration de guilde et le contexte actuel sont prets pour le butin en direct. Un controle indisponible n'est pas une penalite personnelle; contactez un officier si l'etat reste bloque.

Scope: `player` | Audit: `false` | Reason required: `false`

## Announcement channels

- **ID:** `predibs.announcement.channels`
- **Category:** `predibs`
- **Audience:** gm, officer

**English:** Choose destinations for public Pre-Dib notices and Officer-only notices. Availability depends on this character joining the configured channel; test it before live use.
**Francais:** Choisissez les destinations des annonces publiques Pre-Dib et des avis reserves aux officiers. Ce personnage doit rejoindre le canal configure; testez-le avant utilisation.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Encounter Mode

- **ID:** `predibs.encounter.mode`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** Controls when players may submit a Pre-Dib. Encounter mode requires the matching raid and difficulty context; Wild Open may allow requests outside the raid under guild policy.
**Francais:** Determine quand les joueurs peuvent envoyer un Pre-Dib. Le mode Encounter exige le raid et la difficulte correspondants; Wild Open peut autoriser les demandes hors raid selon la politique de guilde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Pre-Dib Request

- **ID:** `predibs.request`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** A Pre-Dib records your interest in eligible loot. It does not award an item or spend a Dib; that happens only after a qualifying award is finalized.
**Francais:** Un Pre-Dib indique votre interet pour un butin eligible. Il n'attribue pas l'objet et ne depense pas de Dib; cela arrive seulement apres un gain eligible finalise.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Rank Allocation

- **ID:** `rank.allocation`
- **Category:** `rank-rules`
- **Audience:** gm, officer

**English:** Starting Dibs assigned to a guild rank for the selected season. Changing the rule does not rewrite older ledger entries.
**Francais:** Dibs attribues au depart a un rang de guilde pour la saison selectionnee. Changer la regle ne reecrit pas les anciennes transactions.

Scope: `guild-season` | Audit: `false` | Reason required: `false`
Permission: `rank.set`

## Rank Allocation Reconciliation

- **ID:** `rank.reconciliation`
- **Category:** `rank-rules`
- **Audience:** gm, officer

**English:** Positive differences require an explicit, reasoned top-up through the canonical ledger. Existing allocations are never removed or converted to debt when a member's expected allocation decreases.
**Francais:** Un ecart positif exige un complement explicite, motive et enregistre dans le registre canonique. Une baisse d'allocation attendue ne retire jamais les allocations existantes et ne cree aucune dette.

Scope: `guild-season` | Audit: `true` | Reason required: `true`
Permission: `rank.reconcile`

## RCLootCouncil history review

- **ID:** `rclootcouncil.history.reconciliation`
- **Category:** `ledger`
- **Audience:** developer, gm, officer

**English:** Previews recorded awards without changing RCLootCouncil history. Confirm only supported evidence; ambiguous or incomplete rows require review and a reason.
**Francais:** Affiche les gains enregistres sans modifier l'historique RCLootCouncil. Confirmez seulement les preuves suffisantes; les lignes ambigues ou incompletes exigent une revue et une raison.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## RCLootCouncil response mapping

- **ID:** `rclootcouncil.response.mapping`
- **Category:** `ledger`
- **Audience:** gm, officer

**English:** Maps a RCLootCouncil response to Dibs meaning. Review the mapping with your guild before live loot; this does not change RCLootCouncil history.
**Francais:** Associe une reponse RCLootCouncil a une action Dibs. Verifiez la correspondance avant le butin en direct; l'historique RCLootCouncil reste inchange.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Raid Readiness

- **ID:** `setup.assistant.readiness`
- **Category:** `setup`
- **Audience:** gm, officer

**English:** Raid Readiness answers whether DIBS is ready for this raid and lists blocking checks with their next actions.
**Francais:** La preparation au raid indique si DIBS est pret pour ce raid et liste les controles bloquants avec leurs prochaines actions.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Historical Reconciliation

- **ID:** `setup.reconciliation`
- **Category:** `setup`
- **Audience:** developer, gm, officer

**English:** Review detected historical Dibs entries before the Guild Master initializes the shared ledger. Keep uncertain evidence unresolved until it is understood.
**Francais:** Examinez les entrees Dibs historiques detectees avant que le maitre de guilde initialise le registre partage. Laissez les preuves incertaines sans decision.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Coordinator

- **ID:** `sync.coordinator`
- **Category:** `governance`
- **Audience:** developer, gm, officer

**English:** The authorized Dibs client that applies canonical guild-ledger updates. It is normally selected during Guild Configuration.
**Francais:** Client Dibs autorise a appliquer les mises a jour canoniques du registre de guilde. Il est normalement choisi pendant la configuration.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Synchronization peer status

- **ID:** `sync.peer.status`
- **Category:** `synchronization`
- **Audience:** gm, officer

**English:** Peer status is based on the latest response observed by this client; an offline or unresponsive member may show stale synchronization details.
**Francais:** L'etat d'un membre depend de sa derniere reponse observee; un joueur absent ou sans reponse peut afficher des donnees de synchronisation anciennes.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Raid reminder

- **ID:** `sync.raid.reminder`
- **Category:** `synchronization`
- **Audience:** gm, officer

**English:** Sends the configured reminder to the current raid chat. Guild permission and raid-chat availability are required; this does not record a loot award or change Dibs.
**Francais:** Envoie le rappel configure dans le canal du raid actuel. Une autorisation de guilde et un canal disponible sont requis; cela n'enregistre aucun gain et ne modifie pas les Dibs.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Synchronization

- **ID:** `sync.status`
- **Category:** `synchronization`
- **Audience:** gm, officer, player

**English:** Shows whether this client can exchange current guild Dibs state. Unavailable or behind clients may be unable to apply canonical updates.
**Francais:** Indique si ce client peut echanger l'etat Dibs actuel de la guilde. Un client indisponible ou en retard peut ne pas appliquer les mises a jour canoniques.

Scope: `guild` | Audit: `false` | Reason required: `false`
